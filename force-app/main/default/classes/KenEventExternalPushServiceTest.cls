/**
 * @description Covers the external event push: the single bypass, the unconfigured org, the
 *              created/updated distinction, the institute filter and resolution, payload shape,
 *              and every way the receiving system can refuse a push.
 *
 *              The callout is driven through `run()` rather than the queueable wherever the
 *              assertion is about the payload, so the request that would leave the org can be
 *              inspected directly; one test still goes the whole way through the trigger.
 *
 * @author  Surya
 */
@isTest
private class KenEventExternalPushServiceTest {

    private static final String CREDENTIAL = 'Ken_Event_Push';
    private static final String LOGIN_PATH = '/api/auth/integration/login';
    private static final String SYNC_PATH = '/api/globalnxt/events/sync';
    private static final String INSTITUTE = 'GlobalNxt University';

    private static final String TOKEN_BODY =
        '{"success":true,"data":{"access_token":"test-sanctum-token"}}';

    // -----------------------------------------------------------------------------------
    // Mock
    // -----------------------------------------------------------------------------------

    /**
     * Answers the login call with a token and the sync calls from a queue of scripted statuses,
     * recording every request so a test can assert on what was actually sent.
     */
    private class PushMock implements HttpCalloutMock {

        private final List<Integer> syncStatuses;
        private final Integer loginStatus;
        private final String loginBody;

        public List<HttpRequest> requests = new List<HttpRequest>();
        public List<String> syncBodies = new List<String>();

        public PushMock(List<Integer> syncStatuses) {
            this(syncStatuses, 200, TOKEN_BODY);
        }

        public PushMock(List<Integer> syncStatuses, Integer loginStatus, String loginBody) {
            this.syncStatuses = syncStatuses;
            this.loginStatus = loginStatus;
            this.loginBody = loginBody;
        }

        public HttpResponse respond(HttpRequest request) {

            requests.add(request);
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (request.getEndpoint().endsWith(LOGIN_PATH)) {
                response.setStatusCode(loginStatus);
                response.setBody(loginBody);
                return response;
            }

            syncBodies.add(request.getBody());
            Integer status = syncStatuses.isEmpty()
                ? 200
                : syncStatuses.remove(0);
            response.setStatusCode(status);
            response.setBody(status == 200 ? '{"success":true}' : '{"success":false,"message":"nope"}');
            return response;
        }

        public Integer syncCallCount() {
            return syncBodies.size();
        }
    }

    // -----------------------------------------------------------------------------------
    // Fixtures
    // -----------------------------------------------------------------------------------

    private static void configure(Boolean bypass, String credential) {

        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        params.Event_Push_Connection__c = credential;
        params.Institution_Name__c = INSTITUTE;
        upsert params;

        Ken_Alm_Module_Settings__c modules = Ken_Alm_Module_Settings__c.getOrgDefaults();
        modules.Skip_Event_External_Push__c = bypass;
        upsert modules;
    }

    private static Account institute() {

        Account provider = new Account(Name = INSTITUTE);
        insert provider;
        return provider;
    }

    private static Ken_Event_Master__c liveEvent(String instituteToken) {

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Annual Alumni Meet 2026',
            RecordTypeId = Schema.SObjectType.Ken_Event_Master__c
                .getRecordTypeInfosByDeveloperName().get('Event').getRecordTypeId(),
            Event_Status__c = 'Approved',
            Is_Published__c = true,
            Is_Active__c = true,
            Is_Archived__c = false,
            Show_On_Landing_Page__c = true,
            Event_Type__c = 'Conference',
            Start_Date__c = Date.newInstance(2026, 9, 12),
            End_Date__c = Date.newInstance(2026, 9, 13),
            Description__c = '<p>Join us for the <b>flagship</b> alumni gathering.</p>',
            Target_Topics__c = '<ul><li>09:00 Keynote</li></ul>',
            What_to_Expect_From_Event__c = '<p>Workshops and networking.</p>',
            Location__c = 'Main Auditorium',
            Max_Allowed_Participants__c = 500,
            Event_Pricing__c = 'Overall Pricing',
            Event_Fee__c = 1500,
            No_Fee__c = false,
            Institute_Name__c = instituteToken
        );

        // Inserted with the trigger off. This event is already live, so a plain insert would push
        // it during setup and every later assertion about how many calls were made would be
        // counting somebody else's. It also keeps the institute stamp off the token being tested.
        KenTriggerHandler.skipTrigger = true;
        insert event;
        KenTriggerHandler.skipTrigger = false;

        return event;
    }

    /** The event as the push service will read it back, including the fields it writes. */
    private static Ken_Event_Master__c reload(Id eventId) {

        return [
            SELECT Id, External_Sync_Status__c, External_Synced_On__c, External_Sync_Message__c
            FROM Ken_Event_Master__c
            WHERE Id = :eventId
        ];
    }

    private static Map<String, Object> parse(String body) {
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    // -----------------------------------------------------------------------------------
    // The switch
    // -----------------------------------------------------------------------------------

    @isTest
    static void bypassStopsThePushEvenWhenFullyConfigured() {

        configure(true, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.pushEvents(new Set<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(true, KenEventExternalPushService.isBypassed(),
            'The bypass should read back as on.');
        System.assertEquals(0, mock.requests.size(),
            'Nothing may leave the org while the bypass is on.');
        System.assertEquals(null, reload(event.Id).External_Sync_Status__c,
            'A bypassed event should not even be marked as attempted.');
    }

    @isTest
    static void anOrgWithNoCredentialIsInert() {

        configure(false, null);
        Ken_Event_Master__c event = liveEvent(null);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.pushEvents(new Set<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(0, mock.requests.size(),
            'With no Named Credential there is nowhere to push, so nothing should be attempted.');
        System.assertEquals(null, reload(event.Id).External_Sync_Status__c,
            'An unconfigured org should not record failures it never tried to avoid.');
    }

    // -----------------------------------------------------------------------------------
    // created / updated
    // -----------------------------------------------------------------------------------

    @isTest
    static void firstPushSendsCreatedAndRecordsTheSync() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(1, mock.syncCallCount(), 'One sync call was expected.');

        Map<String, Object> payload = parse(mock.syncBodies[0]);
        System.assertEquals(KenEventExternalPushService.ACTION_CREATED, payload.get('action'),
            'An event never accepted before has to be sent as a creation.');
        System.assertEquals(String.valueOf(event.Id), payload.get('eventId'),
            'The upsert key is the event id.');
        System.assertEquals('Annual Alumni Meet 2026', payload.get('title'), 'Title should be the event name.');

        Ken_Event_Master__c synced = reload(event.Id);
        System.assertEquals(KenEventExternalPushService.SYNC_SYNCED, synced.External_Sync_Status__c,
            'An accepted push should be recorded as synced.');
        System.assertNotEquals(null, synced.External_Synced_On__c,
            'The sync timestamp is what makes the next push an update.');
        System.assertEquals(null, synced.External_Sync_Message__c,
            'A successful push should clear any earlier error.');
    }

    @isTest
    static void aSecondPushSendsUpdated() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        // Stand in for an earlier accepted push.
        KenTriggerHandler.skipTrigger = true;
        update new Ken_Event_Master__c(
            Id = event.Id,
            External_Sync_Status__c = KenEventExternalPushService.SYNC_SYNCED,
            External_Synced_On__c = System.now().addDays(-1)
        );
        KenTriggerHandler.skipTrigger = false;

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(KenEventExternalPushService.ACTION_UPDATED,
            parse(mock.syncBodies[0]).get('action'),
            'An event already accepted has to be sent as an update.');
    }

    @isTest
    static void anExternalRecordThatWentMissingIsSentAgainAsACreation() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        KenTriggerHandler.skipTrigger = true;
        update new Ken_Event_Master__c(Id = event.Id, External_Synced_On__c = System.now().addDays(-1));
        KenTriggerHandler.skipTrigger = false;

        PushMock mock = new PushMock(new List<Integer>{ 404, 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(2, mock.syncCallCount(),
            'A 404 on an update should be retried as a creation.');
        System.assertEquals(KenEventExternalPushService.ACTION_UPDATED,
            parse(mock.syncBodies[0]).get('action'), 'The first attempt is the update.');
        System.assertEquals(KenEventExternalPushService.ACTION_CREATED,
            parse(mock.syncBodies[1]).get('action'), 'The retry recreates the missing record.');
        System.assertEquals(KenEventExternalPushService.SYNC_SYNCED,
            reload(event.Id).External_Sync_Status__c,
            'The retry succeeded, so the event is in sync.');
    }

    // -----------------------------------------------------------------------------------
    // Failure
    // -----------------------------------------------------------------------------------

    @isTest
    static void aRejectionIsRecordedOnTheEventAndLogged() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        Test.setMock(HttpCalloutMock.class, new PushMock(new List<Integer>{ 500 }));

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        Ken_Event_Master__c failed = reload(event.Id);
        System.assertEquals(KenEventExternalPushService.SYNC_FAILED, failed.External_Sync_Status__c,
            'A rejected push should be visible on the event itself.');
        System.assert(failed.External_Sync_Message__c.contains('500'),
            'The response status belongs in the message so the failure can be diagnosed. Got: '
            + failed.External_Sync_Message__c);

        List<Ken_Logs__c> logs = [
            SELECT Id, Category__c, Log_Type__c, Reference_Id__c
            FROM Ken_Logs__c
            WHERE Process__c = 'Event External Push'
        ];
        System.assertEquals(1, logs.size(), 'The failure should also be logged.');
        System.assertEquals(KenLogService.CATEGORY_INTEGRATION, logs[0].Category__c,
            'An integration failure should be filterable as one.');
        System.assertEquals(String.valueOf(event.Id), logs[0].Reference_Id__c,
            'The log should point back at the event.');
    }

    @isTest
    static void aFailedLoginStopsTheSyncCall() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200 }, 401, '{"message":"Unauthorised"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(0, mock.syncCallCount(),
            'Without a token there is no point posting the event.');
        System.assertEquals(KenEventExternalPushService.SYNC_FAILED,
            reload(event.Id).External_Sync_Status__c,
            'A login failure is still a failure to push.');
    }

    @isTest
    static void aLoginThatReturnsNoTokenIsAFailure() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200 }, 200, '{"success":true,"data":{}}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(0, mock.syncCallCount(), 'A tokenless login should not be treated as one.');
        System.assertEquals(KenEventExternalPushService.SYNC_FAILED,
            reload(event.Id).External_Sync_Status__c, 'The event should be marked failed.');
    }

    @isTest
    static void oneTokenServesTheWholeBatch() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c first = liveEvent(provider.Id);
        Ken_Event_Master__c second = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200, 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ first.Id, second.Id });
        Test.stopTest();

        System.assertEquals(2, mock.syncCallCount(), 'Both events should be posted.');
        System.assertEquals(3, mock.requests.size(),
            'Two events should cost one login, not one each.');
        System.assert(mock.requests[0].getEndpoint().endsWith(LOGIN_PATH),
            'The token exchange should come first. Got: ' + mock.requests[0].getEndpoint());
        System.assert(mock.requests[1].getEndpoint().endsWith(SYNC_PATH),
            'The sync should follow it. Got: ' + mock.requests[1].getEndpoint());
    }

    // -----------------------------------------------------------------------------------
    // Institute
    // -----------------------------------------------------------------------------------

    @isTest
    static void theInstituteTokenIsResolvedToTheInstitutesName() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(INSTITUTE, parse(mock.syncBodies[0]).get('instituteName'),
            'Institute_Name__c holds the provider record id, so the name has to be resolved '
            + 'before it is sent or the receiving API rejects every event.');
    }

    @isTest
    static void anEventWithNoInstituteFallsBackToTheOrgsOwnInstitution() {

        configure(false, CREDENTIAL);
        Ken_Event_Master__c event = liveEvent(null);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(INSTITUTE, parse(mock.syncBodies[0]).get('instituteName'),
            'A single-institute org should still name itself.');
    }

    @isTest
    static void anInstituteTokenThatResolvesToNothingStillNamesTheOrg() {

        configure(false, CREDENTIAL);

        // A token pointing at an Account that no longer exists, which is what a deleted or merged
        // provider leaves behind on an event.
        Account provider = institute();
        Id staleToken = provider.Id;
        delete provider;

        Ken_Event_Master__c event = liveEvent(staleToken);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        System.assertEquals(INSTITUTE, parse(mock.syncBodies[0]).get('instituteName'),
            'An unresolvable token should fall back to the org institution, not send a raw id.');
    }

    // -----------------------------------------------------------------------------------
    // Payload
    // -----------------------------------------------------------------------------------

    @isTest
    static void thePayloadCarriesSessionsSpeakersAndTheContractsFormats() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(
            Name = 'Keynote: Future of EdTech',
            Event_Reference__c = event.Id,
            Start_DateTime__c = Datetime.newInstanceGmt(2026, 9, 12, 4, 0, 0),
            End_DateTime__c = Datetime.newInstanceGmt(2026, 9, 12, 6, 0, 0),
            Location_Type__c = 'Hybrid',
            Location__c = 'Seminar Hall 1',
            Session_Link__c = 'https://example.com/session',
            Target_Topics__c = 'Keynote then live Q&A.',
            What_to_Expect_From_Event__c = 'Insights into online learning.',
            Session_Fee__c = 500,
            No_Fee__c = false
        );
        insert session;

        Id speakerRt = Schema.SObjectType.Ken_Events_Sessions_Enrollment__c
            .getRecordTypeInfosByDeveloperName().get('Speaker_Enrollment').getRecordTypeId();

        insert new Ken_Events_Sessions_Enrollment__c(
            RecordTypeId = speakerRt,
            Event_Reference__c = event.Id,
            Schedule_Sessions__c = session.Id,
            Speaker_Name__c = 'Dr Meera Sharma',
            Speaker_Email__c = 'meera.sharma@example.com',
            Description__c = 'Dean of Educational Innovation.'
        );

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        Map<String, Object> payload = parse(mock.syncBodies[0]);

        System.assertEquals('2026-09-12', payload.get('startDate'),
            'Dates go out as yyyy-MM-dd regardless of the running user locale.');
        System.assertEquals(new List<Object>{ 'Conference' }, payload.get('eventTypes'),
            'A multi-select picklist becomes an array.');
        System.assertEquals('Join us for the flagship alumni gathering.', payload.get('shortDescription'),
            'The short description is the description with its markup stripped.');
        System.assert(((String) payload.get('descriptionHtml')).contains('<b>flagship</b>'),
            'The HTML description goes out intact.');

        Map<String, Object> pricing = (Map<String, Object>) payload.get('pricing');
        System.assertEquals('Overall Pricing', pricing.get('model'), 'The pricing model should be sent.');
        System.assertEquals('INR', pricing.get('currency'), 'Currency falls back to INR.');
        System.assertEquals(false, pricing.get('isFree'), 'A paid event is not free.');

        List<Object> sessions = (List<Object>) payload.get('sessions');
        System.assertEquals(1, sessions.size(), 'The session should travel with its event.');
        Map<String, Object> sent = (Map<String, Object>) sessions[0];
        System.assertEquals('2026-09-12T04:00:00Z', sent.get('startDateTime'),
            'Session times go out in UTC with the Z suffix.');
        System.assertEquals('Keynote then live Q&A.', sent.get('agenda'),
            'Target_Topics__c is the agenda field, however it is named.');
        System.assertNotEquals(null, sent.get('sessionNumber'),
            'The auto-numbered session id should be sent.');

        List<Object> speakers = (List<Object>) payload.get('speakers');
        System.assertEquals(1, speakers.size(), 'The speaker should travel with its event.');
        Map<String, Object> speaker = (Map<String, Object>) speakers[0];
        System.assertEquals('Speaker', speaker.get('role'),
            'The record type becomes a role a public site can display.');
        System.assertEquals('Dr Meera Sharma', speaker.get('name'), 'The speaker name should be sent.');
        System.assertEquals(String.valueOf(session.Id), speaker.get('sessionId'),
            'A session speaker should stay attached to their session.');
        System.assertEquals('Dean of Educational Innovation.', speaker.get('bio'),
            'Description__c is the speaker bio.');
    }

    /**
     * Is_Active__c defaults to false on an enrollment and the event wizard never sets it, so a
     * speaker created by the product looks inactive. Filtering on it would send an empty speaker
     * list for every event in the org, which is exactly the bug this pins down.
     */
    @isTest
    static void aSpeakerIsSentEvenThoughTheWizardNeverMarksThemActive() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        Id hostRt = Schema.SObjectType.Ken_Events_Sessions_Enrollment__c
            .getRecordTypeInfosByDeveloperName().get('Event_Host_Enrollment').getRecordTypeId();

        Ken_Events_Sessions_Enrollment__c speaker = new Ken_Events_Sessions_Enrollment__c(
            RecordTypeId = hostRt,
            Event_Reference__c = event.Id,
            Speaker_Name__c = 'Dr Aris Thorne'
        );
        insert speaker;

        System.assertEquals(false,
            [SELECT Is_Active__c FROM Ken_Events_Sessions_Enrollment__c WHERE Id = :speaker.Id].Is_Active__c,
            'The default really is false, which is why the push must not filter on it.');

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenEventExternalPushService.run(new List<Id>{ event.Id });
        Test.stopTest();

        List<Object> speakers = (List<Object>) parse(mock.syncBodies[0]).get('speakers');
        System.assertEquals(1, speakers.size(),
            'The speaker should be sent regardless of an unused active flag.');

        Map<String, Object> sent = (Map<String, Object>) speakers[0];
        System.assertEquals('Event Host', sent.get('role'),
            'An event host record type should read as a role, not as an internal label.');
        System.assertEquals(null, sent.get('sessionId'),
            'An event level speaker belongs to no session.');
    }

    // -----------------------------------------------------------------------------------
    // Criteria
    // -----------------------------------------------------------------------------------

    @isTest
    static void goingLiveThroughTheTriggerPushesTheEvent() {

        configure(false, CREDENTIAL);
        Account provider = institute();

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Draft Event',
            Event_Status__c = 'Draft',
            Is_Published__c = false,
            Institute_Name__c = provider.Id
        );
        insert event;

        System.assertEquals(null, reload(event.Id).External_Sync_Status__c,
            'A draft has nothing to publish externally.');

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        update new Ken_Event_Master__c(
            Id = event.Id,
            Event_Status__c = 'Approved',
            Is_Published__c = true
        );
        Test.stopTest();

        System.assertEquals(1, mock.syncCallCount(),
            'Approving and publishing an event should push it exactly once.');
        System.assertEquals(KenEventExternalPushService.SYNC_SYNCED,
            reload(event.Id).External_Sync_Status__c,
            'The trigger path should record the sync like any other.');
    }

    @isTest
    static void cancellingALiveEventPushesTheCancellation() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        update new Ken_Event_Master__c(Id = event.Id, Event_Status__c = 'Cancelled');
        Test.stopTest();

        System.assertEquals(1, mock.syncCallCount(),
            'An event that stops being live still has to be sent, or the site keeps showing it.');
        System.assertEquals('Cancelled', parse(mock.syncBodies[0]).get('status'),
            'The payload should carry the cancellation.');
    }

    @isTest
    static void anInternalOnlyEditDoesNotPush() {

        configure(false, CREDENTIAL);
        Account provider = institute();
        Ken_Event_Master__c event = liveEvent(provider.Id);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        update new Ken_Event_Master__c(Id = event.Id, Email_Subject__c = 'Internal campaign subject');
        Test.stopTest();

        System.assertEquals(0, mock.syncCallCount(),
            'Saving a field the external site never shows should not cost a callout.');
    }

    @isTest
    static void anEventCreatedAlreadyLiveIsPushedOnInsert() {

        configure(false, CREDENTIAL);
        Account provider = institute();

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Loaded Event',
            Event_Status__c = 'Approved',
            Is_Published__c = true,
            Institute_Name__c = provider.Id
        );
        insert event;
        Test.stopTest();

        System.assertEquals(1, mock.syncCallCount(),
            'An event loaded in already approved and published has to be pushed too.');
        System.assertEquals(KenEventExternalPushService.ACTION_CREATED,
            parse(mock.syncBodies[0]).get('action'), 'A brand new event is a creation.');
    }

    @isTest
    static void aDraftInsertDoesNotPush() {

        configure(false, CREDENTIAL);

        PushMock mock = new PushMock(new List<Integer>{ 200 });
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        insert new Ken_Event_Master__c(Name = 'Just A Draft', Event_Status__c = 'Draft');
        Test.stopTest();

        System.assertEquals(0, mock.requests.size(), 'A draft event is nobody else business yet.');
    }

    // -----------------------------------------------------------------------------------
    // Formatting
    // -----------------------------------------------------------------------------------

    @isTest
    static void shortDescriptionStripsMarkupAndTruncates() {

        String longHtml = '<p>' + 'x'.repeat(400) + '</p>';

        Test.startTest();
        String fromNull = KenEventExternalPushService.shortDescription(null);
        String fromMarkup = KenEventExternalPushService.shortDescription(
            '<p>Hello   <b>there</b></p>'
        );
        String truncated = KenEventExternalPushService.shortDescription(longHtml);
        Test.stopTest();

        System.assertEquals(null, fromNull, 'No description means nothing to summarise.');
        System.assertEquals('Hello there', fromMarkup,
            'Markup should go and runs of whitespace should collapse.');
        System.assertEquals(255, truncated.length(),
            'A long description should be clipped to the listing length.');
        System.assert(truncated.endsWith('...'), 'A clipped summary should say so.');
    }

    @isTest
    static void formattingHelpersAreNullSafe() {

        Test.startTest();
        System.assertEquals(null, KenEventExternalPushService.isoDate(null),
            'A blank date should stay blank rather than becoming an epoch.');
        System.assertEquals(null, KenEventExternalPushService.isoDateTime(null),
            'A blank datetime should stay blank.');
        System.assertEquals('2026-01-05',
            KenEventExternalPushService.isoDate(Date.newInstance(2026, 1, 5)),
            'Single digit months and days should be padded.');
        System.assertEquals(0, KenEventExternalPushService.picklistValues(null).size(),
            'An empty multi-select is an empty array, never null.');
        System.assertEquals(new List<String>{ 'A', 'B' },
            KenEventExternalPushService.picklistValues('A;B'),
            'A packed multi-select should split on the delimiter.');
        Test.stopTest();
    }

    /**
     * The whole configuration is two fields. This pins that down: the credential is read from the
     * setting, and a blank one leaves the feature inert rather than guessing a host.
     */
    @isTest
    static void theCredentialIsTheOnlyEndpointConfiguration() {

        configure(false, CREDENTIAL);

        Test.startTest();
        String configured = KenEventExternalPushService.namedCredential();
        configure(false, '   ');
        String blank = KenEventExternalPushService.namedCredential();
        Test.stopTest();

        System.assertEquals(CREDENTIAL, configured, 'The configured credential should be returned.');
        System.assertEquals(null, blank,
            'A whitespace only credential is no credential, so the feature stays inert.');
    }
}