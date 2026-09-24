/**
 * @description Product-level outbound gate for pushing portal events to an external website.
 *
 *              An alumni event is created and approved inside Salesforce but has to appear on the
 *              client's own public site, so once an event goes live here it is posted to the
 *              external system as a single self-contained document: the event, its sessions and
 *              its speakers in one payload, upserted on the Salesforce event id.
 *
 *              Resolution order, highest priority first:
 *                1. Bypass. `Ken_Alm_Module_Settings__c.Skip_Event_External_Push__c` switches the
 *                   whole feature off. It is the only switch, it is evaluated in exactly one place
 *                   — `isBypassed()` below — and nothing configured anywhere else can override it.
 *                2. Endpoint. `Event_Push_Connection__c` says where to push. With none
 *                   configured the feature is inert. That is deliberate: an org that does not use
 *                   it needs no admin action at all, and no fresh org calls out to anybody.
 *
 *              Those two settings are the whole of the configuration. Everything else the contract
 *              needs — the sync path, the login path, the currency — is a constant in this class,
 *              because a partner who changes any of them has changed the contract, and that is a
 *              code change whether or not an admin could have typed it into a field.
 *
 *              Every failure is swallowed. A push is a downstream side effect of approving an
 *              event and must never break the approval, so a rejection is written to the event's
 *              own External_Sync_* fields and to Ken_Logs__c and the transaction carries on.
 *
 *              The host and the integration credentials live entirely in a Named Credential, so
 *              no URL and no secret appears in this class. The admin creates a Named Credential
 *              with Password Authentication — username and password being the integration user's
 *              — and ticks "Allow Merge Fields in HTTP Body", which lets the login body below
 *              reference `{!$Credential.UserName}` without Apex ever seeing the value.
 *
 *              Usage:
 *                  KenEventExternalPushService.pushEvents(eventIds);   // force a re-push
 *              Everything else is automatic, from the event trigger.
 *
 * @author  Surya
 */
public without sharing class KenEventExternalPushService {

    /** Action names the receiving contract understands. It upserts on eventId. */
    public static final String ACTION_CREATED = 'created';
    public static final String ACTION_UPDATED = 'updated';

    public static final String SYNC_PENDING = 'Pending';
    public static final String SYNC_SYNCED = 'Synced';
    public static final String SYNC_FAILED = 'Failed';

    private static final String STATUS_APPROVED = 'Approved';

    /**
     * The receiving contract. These are paths, not hosts — the host lives in the Named Credential
     * — so they are fixed here rather than being two more settings for an admin to get wrong. A
     * partner who moves an endpoint is changing the contract, which is a code change either way.
     */
    private static final String SYNC_PATH = '/api/globalnxt/events/sync';
    private static final String LOGIN_PATH = '/api/auth/integration/login';

    /** Fees are quoted in one currency across the product. Revisit when a client bills in another. */
    private static final String CURRENCY_CODE = 'INR';

    private static final Integer TIMEOUT_MS = 120000;
    private static final Set<Integer> ACCEPTED = new Set<Integer>{ 200, 201, 202, 204 };
    private static final Integer NOT_FOUND = 404;

    private static final String LOG_PROCESS = 'Event External Push';
    private static final String LOG_SOURCE = 'KenEventExternalPushService';

    /** Short description is derived from the HTML description, which has no length limit. */
    private static final Integer SHORT_DESCRIPTION_LENGTH = 255;

    /** External_Sync_Message__c is a 32768 character long text area. */
    private static final Integer MAX_MESSAGE_LENGTH = 32768;

    /**
     * Events per queueable execution. Each one costs a callout, plus one for the token, and a
     * retry when the external record has gone missing, so this stays well inside the 100 the
     * platform allows and the remainder is chained.
     */
    private static final Integer MAX_PER_JOB = 40;

    /**
     * Fields whose change the external site would actually show. An event is re-pushed only when
     * one of these moved, so saving an internal-only field — approval comments, the email
     * campaign, a wizard step counter — does not generate a callout.
     */
    private static final Set<String> WATCHED_FIELDS = new Set<String>{
        'Name',
        'Event_Status__c',
        'Is_Published__c',
        'Is_Active__c',
        'Is_Archived__c',
        'Show_On_Landing_Page__c',
        'Event_Type__c',
        'Start_Date__c',
        'End_Date__c',
        'Description__c',
        'Target_Topics__c',
        'What_to_Expect_From_Event__c',
        'Language__c',
        'Target_Audience_Applicable__c',
        'Location__c',
        'Max_Allowed_Participants__c',
        'Institute_Name__c',
        'Evvent_Group__c',
        'Event_banner__c',
        'Cover_Image_Title__c',
        'Event_Broucher__c',
        'Broucher_Title__c',
        'Event_Photos_Link__c',
        'Event_Highlights_Link__c',
        'Event_Pricing__c',
        'Event_Fee__c',
        'No_Fee__c'
    };

    /**
     * Speaker role sent to the external site. The object carries no role field — the distinction
     * lives in the record type — and "Speaker Enrollment" is an internal label nobody wants to
     * read on a public agenda, so it is translated here.
     */
    private static final Map<String, String> ROLE_BY_RECORD_TYPE = new Map<String, String>{
        'Speaker_Enrollment' => 'Speaker',
        'Event_Host_Enrollment' => 'Event Host',
        'Session_Host_Enrollment' => 'Session Host'
    };

    /** One push per event per transaction, however many times the record is saved. */
    @TestVisible
    private static Set<Id> alreadyQueued = new Set<Id>();

    // -----------------------------------------------------------------------------------
    // The switch
    // -----------------------------------------------------------------------------------

    /**
     * @description The single bypass for the whole feature, evaluated here and nowhere else.
     *
     *              Callers never test a flag of their own: they ask this class to push and this
     *              class decides whether anything leaves the org. Keeping the decision in one
     *              method is what makes the switch trustworthy — an admin who ticks it cannot be
     *              undone by a call site that forgot to check.
     *
     * @return true when no event may be pushed
     */
    public static Boolean isBypassed() {

        Ken_Alm_Module_Settings__c modules = Ken_Alm_Module_Settings__c.getOrgDefaults();
        return modules != null && modules.Skip_Event_External_Push__c == true;
    }

    // -----------------------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------------------

    /**
     * @description Pushes events that were created already live, which is how a data load or an
     *              integration creates one; an event built in the wizard starts as a draft and is
     *              picked up later by pushOnUpdate.
     *
     * @param newRecords Trigger.new
     */
    public static void pushOnInsert(List<Ken_Event_Master__c> newRecords) {

        if (newRecords == null || isBypassed()) {
            return;
        }

        Set<Id> toPush = new Set<Id>();
        for (Ken_Event_Master__c event : newRecords) {
            if (isLive(event)) {
                toPush.add(event.Id);
            }
        }
        pushEvents(toPush);
    }

    /**
     * @description Pushes events whose visible state changed.
     *
     *              Three cases matter and they are not the same. An event that has just gone live
     *              has to be sent. An event that has just stopped being live has to be sent too,
     *              carrying its new status, or the external site would keep advertising something
     *              that was cancelled. An event that is live and stayed live is sent only when a
     *              field the site displays actually moved.
     *
     * @param newRecords Trigger.new
     * @param oldMap     Trigger.oldMap
     */
    public static void pushOnUpdate(
        List<Ken_Event_Master__c> newRecords,
        Map<Id, Ken_Event_Master__c> oldMap
    ) {
        if (newRecords == null || oldMap == null || isBypassed()) {
            return;
        }

        Set<Id> toPush = new Set<Id>();
        for (Ken_Event_Master__c event : newRecords) {

            Ken_Event_Master__c old = oldMap.get(event.Id);
            if (old == null) {
                continue;
            }

            Boolean isLiveNow = isLive(event);
            Boolean wasLive = isLive(old);

            if (isLiveNow != wasLive) {
                toPush.add(event.Id);
            } else if (isLiveNow && hasVisibleChange(event, old)) {
                toPush.add(event.Id);
            }
        }
        pushEvents(toPush);
    }

    /**
     * @description Pushes the given events regardless of what changed, for a manual re-push or for
     *              a caller that has just rewritten an event's sessions or speakers.
     *
     *              Safe to call from a trigger or from inside a DML transaction: the callout is
     *              carried out asynchronously, which is the only way Apex permits it.
     *
     * @param eventIds the events to send
     */
    public static void pushEvents(Set<Id> eventIds) {

        if (eventIds == null || eventIds.isEmpty() || isBypassed()) {
            return;
        }

        // Nothing to push to. An unconfigured org is inert rather than noisy, so this is not
        // logged; it is the normal state of every org that does not use the feature.
        if (String.isBlank(namedCredential())) {
            return;
        }

        List<Id> pending = new List<Id>();
        for (Id eventId : eventIds) {
            if (eventId != null && alreadyQueued.add(eventId)) {
                pending.add(eventId);
            }
        }
        if (pending.isEmpty()) {
            return;
        }

        // A queueable cannot be enqueued from a batch or from another queueable's callout window
        // in every context, and a failure to enqueue must not break the save that triggered it.
        try {
            System.enqueueJob(new EventPush(pending));
        } catch (Exception ex) {
            KenLogService.logException(
                KenLogService.CATEGORY_INTEGRATION, LOG_PROCESS, LOG_SOURCE,
                String.join(pending, ','), ex
            );
        }
    }

    // -----------------------------------------------------------------------------------
    // Push criteria
    // -----------------------------------------------------------------------------------

    /**
     * @description Whether an event is something the external site should be showing: approved,
     *              published and not archived. Anything else — a draft, a rejection, a
     *              cancellation, an archived event — is still pushed when it *leaves* this state,
     *              so the site is told to take it down.
     */
    @TestVisible
    private static Boolean isLive(Ken_Event_Master__c event) {

        return event != null
            && event.Event_Status__c == STATUS_APPROVED
            && event.Is_Published__c == true
            && event.Is_Archived__c != true;
    }

    @TestVisible
    private static Boolean hasVisibleChange(Ken_Event_Master__c newEvent, Ken_Event_Master__c old) {

        for (String field : WATCHED_FIELDS) {
            if (newEvent.get(field) != old.get(field)) {
                return true;
            }
        }
        return false;
    }

    // -----------------------------------------------------------------------------------
    // Configuration
    // -----------------------------------------------------------------------------------

    @TestVisible
    private static String namedCredential() {

        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        return (params != null && String.isNotBlank(params.Event_Push_Connection__c))
            ? params.Event_Push_Connection__c.trim()
            : null;
    }

    /** The org's own institution name, used when an event carries no institute of its own. */
    private static String orgInstitution() {

        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        return (params != null && String.isNotBlank(params.Institution_Name__c))
            ? params.Institution_Name__c.trim()
            : null;
    }

    // -----------------------------------------------------------------------------------
    // The job
    // -----------------------------------------------------------------------------------

    /**
     * @description Carries the callout out of the trigger transaction, where Apex forbids it, and
     *              writes the outcome back onto each event.
     */
    public class EventPush implements Queueable, Database.AllowsCallouts {

        private final List<Id> eventIds;

        public EventPush(List<Id> eventIds) {
            this.eventIds = eventIds;
        }

        public void execute(QueueableContext context) {

            List<Id> batch = new List<Id>();
            List<Id> remainder = new List<Id>();

            for (Integer i = 0; i < eventIds.size(); i++) {
                if (i < MAX_PER_JOB) {
                    batch.add(eventIds[i]);
                } else {
                    remainder.add(eventIds[i]);
                }
            }

            try {
                run(batch);
            } catch (Exception ex) {
                KenLogService.logException(
                    KenLogService.CATEGORY_INTEGRATION, LOG_PROCESS, LOG_SOURCE,
                    String.join(batch, ','), ex
                );
            }

            // A test transaction allows only one chained queueable, and the platform allows only
            // one enqueue from inside a queueable, so the tail is chained rather than looped.
            if (!remainder.isEmpty() && !Test.isRunningTest()) {
                try {
                    System.enqueueJob(new EventPush(remainder));
                } catch (Exception ex) {
                    KenLogService.logException(
                        KenLogService.CATEGORY_INTEGRATION, LOG_PROCESS, LOG_SOURCE,
                        String.join(remainder, ','), ex
                    );
                }
            }
        }
    }

    /**
     * @description Sends one batch of events and records what happened to each.
     */
    @TestVisible
    private static void run(List<Id> eventIds) {

        if (eventIds == null || eventIds.isEmpty()) {
            return;
        }

        List<Ken_Event_Master__c> events = load(eventIds);
        if (events.isEmpty()) {
            return;
        }

        Map<Id, String> instituteNames = resolveInstituteNames(events);

        // One token for the whole batch. It is fetched before the loop so a run of forty events
        // costs one login rather than forty.
        TokenResult tokenResult = authenticate();
        String token = tokenResult.token;

        List<Ken_Event_Master__c> writeBacks = new List<Ken_Event_Master__c>();
        List<Ken_Logs__c> logs = new List<Ken_Logs__c>();

        for (Ken_Event_Master__c event : events) {

            String institute = instituteNames.get(event.Id);

            if (String.isBlank(token)) {
                writeBacks.add(failure(event.Id, tokenResult.error));
                logs.add(logFor(event.Id, tokenResult.error));
                continue;
            }

            String action = (event.External_Synced_On__c == null) ? ACTION_CREATED : ACTION_UPDATED;
            String payload = JSON.serialize(buildPayload(event, institute, action), true);

            CalloutResult result = dispatch(payload, token);

            // The external record has gone — their database was reset, or the event was removed
            // there — so an update can never land. Re-send it as a creation rather than leaving
            // the event permanently out of sync.
            if (result.statusCode == NOT_FOUND && action == ACTION_UPDATED) {
                payload = JSON.serialize(buildPayload(event, institute, ACTION_CREATED), true);
                result = dispatch(payload, token);
            }

            if (result.success) {
                writeBacks.add(new Ken_Event_Master__c(
                    Id = event.Id,
                    External_Sync_Status__c = SYNC_SYNCED,
                    External_Synced_On__c = System.now(),
                    External_Sync_Message__c = null
                ));
            } else {
                writeBacks.add(failure(event.Id, result.message));
                logs.add(logFor(event.Id, result.message));
            }
        }

        saveOutcomes(writeBacks);
        KenLogService.insertLogs(logs);
    }

    private static Ken_Event_Master__c failure(Id eventId, String message) {

        return new Ken_Event_Master__c(
            Id = eventId,
            External_Sync_Status__c = SYNC_FAILED,
            External_Sync_Message__c = clip(message, MAX_MESSAGE_LENGTH)
        );
    }

    private static String clip(String value, Integer limitLength) {

        if (value == null) {
            return null;
        }
        return value.length() > limitLength ? value.substring(0, limitLength) : value;
    }

    private static Ken_Logs__c logFor(Id eventId, String message) {

        return KenLogService.build(
            KenLogService.CATEGORY_INTEGRATION, KenLogService.TYPE_ERROR,
            LOG_PROCESS, LOG_SOURCE, String.valueOf(eventId), message, null
        );
    }

    /**
     * @description Records the outcome on each event with the event trigger switched off.
     *
     *              Without that the write-back would be an update to Ken_Event_Master__c, which
     *              would re-enter pushOnUpdate and push again — and although Event_Status__c has
     *              not moved and the watched-field test would stop it, relying on that would make
     *              adding a sync field to WATCHED_FIELDS an infinite loop waiting to happen.
     */
    private static void saveOutcomes(List<Ken_Event_Master__c> writeBacks) {

        if (writeBacks.isEmpty()) {
            return;
        }

        Boolean wasSkipping = KenTriggerHandler.skipTrigger;
        try {
            KenTriggerHandler.skipTrigger = true;
            // Partial success: one event whose write-back is blocked by a validation rule must not
            // cost the others the record of a push that did succeed.
            if (!Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
                throw new KenCrudException('Ken_Event_Master__c is not updateable by the current user.');
            }
            Database.update(writeBacks, false);
        } catch (Exception ex) {
            KenLogService.logException(
                KenLogService.CATEGORY_INTEGRATION, LOG_PROCESS, LOG_SOURCE, null, ex
            );
        } finally {
            KenTriggerHandler.skipTrigger = wasSkipping;
        }
    }

    // -----------------------------------------------------------------------------------
    // Data
    // -----------------------------------------------------------------------------------

    @TestVisible
    private static List<Ken_Event_Master__c> load(List<Id> eventIds) {

        return [
            SELECT Id, Name, Event_Status__c, Is_Published__c, Is_Active__c, Is_Archived__c,
                   Show_On_Landing_Page__c, Event_Type__c, Start_Date__c, End_Date__c,
                   Description__c, Target_Topics__c, What_to_Expect_From_Event__c, Language__c,
                   Target_Audience_Applicable__c, Location__c, Max_Allowed_Participants__c,
                   Institute_Name__c, Evvent_Group__c, Event_banner__c, Cover_Image_Title__c,
                   Event_Broucher__c, Broucher_Title__c, Event_Photos_Link__c,
                   Event_Highlights_Link__c, Event_Pricing__c, Event_Fee__c, No_Fee__c,
                   External_Synced_On__c, CreatedDate, LastModifiedDate,
                   (SELECT Id, Name, Schedule_Sessions_Id__c, Start_DateTime__c, End_DateTime__c,
                           Location_Type__c, Location__c, Session_Link__c, Target_Topics__c,
                           What_to_Expect_From_Event__c, Session_Fee__c, No_Fee__c,
                           Session_Broucher__c, Broucher_Name__c, Broucher_Type__c
                    FROM Schedule_Sessions__r
                    ORDER BY Start_DateTime__c NULLS LAST),
                   (SELECT Id, Speaker_Name__c, Speaker_Email__c, Speaker_Image__c, Description__c,
                           Schedule_Sessions__c, Person_Account__r.Name,
                           RecordType.DeveloperName, RecordType.Name
                    FROM Events_Sessions_Enrollment__r)
            FROM Ken_Event_Master__c
            WHERE Id IN :eventIds
        WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description The institute name for each event.
     *
     *              Institute_Name__c does not hold a name. It holds the provider Account's
     *              18-character record id, semicolon separated when a record spans several,
     *              because criteria sharing rules match it with CONTAINS. The receiving API
     *              matches on the institute's actual name, so the token has to be resolved back
     *              through Account before it can be sent — pushing the raw field would send
     *              "001Ta00000V7FOgIAN" and have every event rejected.
     *
     *              An event with no token falls back to the org's own institution name, which is
     *              the right answer for a single-institute client and the only answer available.
     */
    @TestVisible
    private static Map<Id, String> resolveInstituteNames(List<Ken_Event_Master__c> events) {

        Map<Id, String> byEvent = new Map<Id, String>();
        Map<Id, Id> tokenByEvent = new Map<Id, Id>();
        Set<Id> providerIds = new Set<Id>();
        String fallback = orgInstitution();

        for (Ken_Event_Master__c event : events) {

            String raw = event.Institute_Name__c;
            if (String.isBlank(raw)) {
                byEvent.put(event.Id, fallback);
                continue;
            }

            // An event belongs to one institute, so the first token is the one to resolve even
            // when the stamp packed several.
            String first = raw.trim().split(KenInstitutePopulationService.DELIMITER)[0].trim();

            Id providerId = asId(first);
            if (providerId == null) {
                // Not an id at all. An org that stamps a readable name can be taken at its word.
                byEvent.put(event.Id, first);
                continue;
            }

            tokenByEvent.put(event.Id, providerId);
            providerIds.add(providerId);
        }

        Map<Id, String> nameByProvider = new Map<Id, String>();
        if (!providerIds.isEmpty()) {
            for (Account provider : [SELECT Id, Name FROM Account WHERE Id IN :providerIds WITH SECURITY_ENFORCED]) {
                nameByProvider.put(provider.Id, provider.Name);
            }
        }

        for (Id eventId : tokenByEvent.keySet()) {
            String resolved = nameByProvider.get(tokenByEvent.get(eventId));
            byEvent.put(eventId, String.isBlank(resolved) ? fallback : resolved);
        }
        return byEvent;
    }

    private static Id asId(String value) {

        if (String.isBlank(value) || (value.length() != 15 && value.length() != 18)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception ignored) {
            return null;
        }
    }

    // -----------------------------------------------------------------------------------
    // Payload
    // -----------------------------------------------------------------------------------

    /**
     * @description Builds the whole event document: the event, every session and every speaker.
     *
     *              Sent as one payload rather than three because the sessions and speakers only
     *              mean anything alongside their event, and because the receiving end replaces the
     *              event's children wholesale — a session deleted here has to disappear there, and
     *              an absent list is the only way to say so.
     */
    @TestVisible
    private static Map<String, Object> buildPayload(
        Ken_Event_Master__c event,
        String instituteName,
        String action
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'eventId' => event.Id,
            'action' => action,
            'title' => event.Name,
            'status' => event.Event_Status__c,
            'isPublished' => event.Is_Published__c == true,
            'isActive' => event.Is_Active__c == true,
            'isArchived' => event.Is_Archived__c == true,
            'showOnLandingPage' => event.Show_On_Landing_Page__c == true,
            'eventTypes' => picklistValues(event.Event_Type__c),
            'startDate' => isoDate(event.Start_Date__c),
            'endDate' => isoDate(event.End_Date__c),
            'shortDescription' => shortDescription(event.Description__c),
            'descriptionHtml' => event.Description__c,
            'agendaHtml' => event.Target_Topics__c,
            'whatToExpectHtml' => event.What_to_Expect_From_Event__c,
            'languages' => picklistValues(event.Language__c),
            'targetAudience' => picklistValues(event.Target_Audience_Applicable__c),
            'location' => event.Location__c,
            'maxParticipants' => asInteger(event.Max_Allowed_Participants__c),
            'instituteName' => instituteName,
            'eventGroupId' => event.Evvent_Group__c,
            'bannerUrl' => event.Event_banner__c,
            'coverImageTitle' => event.Cover_Image_Title__c,
            'brochure' => new Map<String, Object>{
                'url' => event.Event_Broucher__c,
                'title' => event.Broucher_Title__c
            },
            'eventPhotosLink' => event.Event_Photos_Link__c,
            'eventHighlightsLink' => event.Event_Highlights_Link__c,
            'pricing' => new Map<String, Object>{
                'model' => event.Event_Pricing__c,
                'eventFee' => event.Event_Fee__c,
                'isFree' => event.No_Fee__c == true,
                'currency' => CURRENCY_CODE
            },
            'sessions' => buildSessions(event),
            'speakers' => buildSpeakers(event),
            'audit' => new Map<String, Object>{
                'createdAt' => isoDateTime(event.CreatedDate),
                'lastModifiedAt' => isoDateTime(event.LastModifiedDate)
            }
        };
        return payload;
    }

    private static List<Map<String, Object>> buildSessions(Ken_Event_Master__c event) {

        List<Map<String, Object>> sessions = new List<Map<String, Object>>();
        if (event.Schedule_Sessions__r == null) {
            return sessions;
        }

        for (Ken_Schedule_Sessions__c session : event.Schedule_Sessions__r) {
            sessions.add(new Map<String, Object>{
                'sessionId' => session.Id,
                'sessionNumber' => session.Schedule_Sessions_Id__c,
                'title' => session.Name,
                'startDateTime' => isoDateTime(session.Start_DateTime__c),
                'endDateTime' => isoDateTime(session.End_DateTime__c),
                'locationType' => session.Location_Type__c,
                'location' => session.Location__c,
                'sessionLink' => session.Session_Link__c,
                'agenda' => session.Target_Topics__c,
                'whatToExpect' => session.What_to_Expect_From_Event__c,
                'sessionFee' => session.Session_Fee__c,
                'isFreeSession' => session.No_Fee__c == true,
                'brochureUrl' => session.Session_Broucher__c,
                'brochureName' => session.Broucher_Name__c,
                'brochureType' => session.Broucher_Type__c
            });
        }
        return sessions;
    }

    private static List<Map<String, Object>> buildSpeakers(Ken_Event_Master__c event) {

        List<Map<String, Object>> speakers = new List<Map<String, Object>>();
        if (event.Events_Sessions_Enrollment__r == null) {
            return speakers;
        }

        // Every enrollment is sent. Is_Active__c looks like the flag to filter on and is not: it
        // defaults to false and the event wizard never sets it, so honouring it would drop every
        // speaker the product has ever created. A speaker who is off the bill is deleted here.
        for (Ken_Events_Sessions_Enrollment__c speaker : event.Events_Sessions_Enrollment__r) {

            // A speaker who is an alumnus is held as a lookup and their name lives on the Account;
            // an external guest is typed straight onto the enrollment.
            String name = (speaker.Person_Account__r != null && String.isNotBlank(speaker.Person_Account__r.Name))
                ? speaker.Person_Account__r.Name
                : speaker.Speaker_Name__c;

            speakers.add(new Map<String, Object>{
                'enrollmentId' => speaker.Id,
                'role' => roleFor(speaker),
                'name' => name,
                'email' => speaker.Speaker_Email__c,
                'photoUrl' => speaker.Speaker_Image__c,
                'bio' => speaker.Description__c,
                'sessionId' => speaker.Schedule_Sessions__c
            });
        }
        return speakers;
    }

    @TestVisible
    private static String roleFor(Ken_Events_Sessions_Enrollment__c speaker) {

        if (speaker.RecordType == null) {
            return ROLE_BY_RECORD_TYPE.get('Speaker_Enrollment');
        }

        String mapped = ROLE_BY_RECORD_TYPE.get(speaker.RecordType.DeveloperName);
        return String.isNotBlank(mapped) ? mapped : speaker.RecordType.Name;
    }

    // -----------------------------------------------------------------------------------
    // Transport
    // -----------------------------------------------------------------------------------

    private class TokenResult {
        String token;
        String error;
    }

    private class CalloutResult {
        Boolean success = false;
        Integer statusCode;
        String message;
    }

    /**
     * @description Exchanges the integration credentials for a bearer token.
     *
     *              The credentials are never read by Apex. `{!$Credential.UserName}` and
     *              `{!$Credential.Password}` are substituted by the platform on the way out of the
     *              org, which is why the Named Credential needs "Allow Merge Fields in HTTP Body"
     *              — the secret stays in setup where an admin put it, and a debug log of this
     *              request shows the merge field, not the password.
     */
    private static TokenResult authenticate() {

        TokenResult result = new TokenResult();

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + namedCredential() + LOGIN_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(TIMEOUT_MS);
            req.setBody('{"email":"{!$Credential.UserName}","password":"{!$Credential.Password}"}');

            HttpResponse res = new Http().send(req);

            if (!ACCEPTED.contains(res.getStatusCode())) {
                result.error = 'Integration login rejected. Status ' + res.getStatusCode()
                    + ': ' + res.getBody();
                return result;
            }

            result.token = accessTokenFrom(res.getBody());
            if (String.isBlank(result.token)) {
                result.error = 'Integration login returned no access token: ' + res.getBody();
            }
            return result;

        } catch (Exception ex) {
            result.error = 'Integration login failed: ' + ex.getMessage();
            return result;
        }
    }

    /**
     * @description Reads the token out of the login response, which nests it under `data`.
     */
    @TestVisible
    private static String accessTokenFrom(String body) {

        if (String.isBlank(body)) {
            return null;
        }

        try {
            Object parsed = JSON.deserializeUntyped(body);
            if (!(parsed instanceof Map<String, Object>)) {
                return null;
            }

            Map<String, Object> root = (Map<String, Object>) parsed;
            Object data = root.get('data');
            if (data instanceof Map<String, Object>) {
                Object token = ((Map<String, Object>) data).get('access_token');
                if (token != null) {
                    return String.valueOf(token);
                }
            }

            // Tolerated so a slightly different deployment of the same API still works.
            Object flat = root.get('access_token');
            return flat == null ? null : String.valueOf(flat);

        } catch (Exception ignored) {
            return null;
        }
    }

    /**
     * @description Posts one event document. Never throws: the caller has to record an outcome for
     *              every event whatever happens to any one of them.
     */
    private static CalloutResult dispatch(String payload, String token) {

        CalloutResult result = new CalloutResult();

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + namedCredential() + SYNC_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(payload);

            HttpResponse res = new Http().send(req);

            result.statusCode = res.getStatusCode();
            result.success = ACCEPTED.contains(result.statusCode);
            if (!result.success) {
                result.message = 'Event push rejected. Status ' + result.statusCode
                    + ': ' + res.getBody();
            }
            return result;

        } catch (Exception ex) {
            result.message = 'Event push failed: ' + ex.getMessage();
            return result;
        }
    }

    // -----------------------------------------------------------------------------------
    // Formatting
    // -----------------------------------------------------------------------------------

    /**
     * @description Splits a multi-select picklist into the array the contract expects. An empty
     *              list rather than null, so the receiving end can replace the stored values
     *              instead of having to tell "cleared" apart from "not sent".
     */
    @TestVisible
    private static List<String> picklistValues(String packed) {

        List<String> values = new List<String>();
        if (String.isBlank(packed)) {
            return values;
        }

        for (String value : packed.split(';')) {
            if (String.isNotBlank(value)) {
                values.add(value.trim());
            }
        }
        return values;
    }

    /**
     * @description A plain-text summary for listings, derived from the HTML description because
     *              the event has no separate short description to send.
     */
    @TestVisible
    private static String shortDescription(String html) {

        if (String.isBlank(html)) {
            return null;
        }

        String text = html.stripHtmlTags().unescapeHtml4().replaceAll('\\s+', ' ').trim();
        if (String.isBlank(text)) {
            return null;
        }
        return text.length() <= SHORT_DESCRIPTION_LENGTH
            ? text
            : text.substring(0, SHORT_DESCRIPTION_LENGTH - 3).trim() + '...';
    }

    /**
     * @description Dates as yyyy-MM-dd, built explicitly rather than formatted, because Date
     *              formatting follows the running user's locale and the contract does not.
     */
    @TestVisible
    private static String isoDate(Date value) {

        if (value == null) {
            return null;
        }
        return String.valueOf(value.year()) + '-' + twoDigits(value.month()) + '-' + twoDigits(value.day());
    }

    /** Times in UTC, matching the contract's Z-suffixed form, never the user's time zone. */
    @TestVisible
    private static String isoDateTime(Datetime value) {

        return value == null ? null : value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static String twoDigits(Integer value) {
        return value < 10 ? '0' + String.valueOf(value) : String.valueOf(value);
    }

    private static Integer asInteger(Decimal value) {
        return value == null ? null : value.intValue();
    }
}