/**
 * @description Single outbound gate for every alumni notification, across email, SMS and WhatsApp.
 *              Callers describe the message once and this class decides how it leaves the org.
 *
 *              Resolution order, highest priority first:
 *                1. Bypass. If the message type is bypassed in Ken_Alm_Bypass_Settings__c nothing is
 *                   sent on any channel. Turning Marketing Cloud on must never resurrect a message
 *                   an admin has switched off, so the bypass is evaluated before anything else.
 *                2. Marketing Cloud. If the channel is enabled in Ken_Alm_Org_Parameters__c and the
 *                   message type has a definition key, the payload goes to SFMC and the caller is
 *                   told the message is handled.
 *                3. Native. Nothing is sent here; the caller falls back to its own
 *                   Messaging.sendEmail path unchanged.
 *
 *              Usage from any existing send site:
 *
 *                  KenMessagingService.Request req =
 *                      new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL)
 *                          .toEmail(emailAddress)
 *                          .attribute('otp', code);
 *
 *                  if (KenMessagingService.send(req).handled) {
 *                      return;
 *                  }
 *                  // existing native Messaging.sendEmail code stays exactly as it is
 *
 *              Endpoints and credentials live entirely in Named Credentials configured per org.
 *              No host or secret is hardcoded here. Marketing Cloud is a single tenant behind one
 *              REST base URI, so one Named Credential serves all three channels and only the path
 *              differs; the org is read for whichever Marketing Cloud credential it already has,
 *              falling back to the names the KJS orgs already use when nothing can be read.
 */
public without sharing class KenMessagingService {

    public static final String TYPE_OTP_EMAIL = 'OTP_Email';
    public static final String TYPE_MAGIC_LINK = 'Magic_Link';
    public static final String TYPE_REGISTRATION_SUBMISSION = 'Registration_Submission';
    public static final String TYPE_REGISTRATION_REJECTION = 'Registration_Rejection';
    public static final String TYPE_TEMPORARY_LOGIN = 'Temporary_Password';
    public static final String TYPE_NEW_ROLE_ADDED = 'New_Role_Added';
    public static final String TYPE_SPEAKER_INVITE = 'Speaker_Invite';
    public static final String TYPE_EMAIL_CAMPAIGN = 'Email_Campaign';
    public static final String TYPE_ADHOC_EMAIL = 'Adhoc_Email';
    public static final String TYPE_LOGIN_OTP = 'Login_OTP';
    public static final String TYPE_LEAD_MERGED = 'Lead_Merged';

    public static final String CHANNEL_EMAIL = 'Email';
    public static final String CHANNEL_SMS = 'SMS';
    public static final String CHANNEL_WHATSAPP = 'WhatsApp';

    private static final String EMAIL_PATH = '/messaging/v1/email/messages';
    private static final String SMS_PATH = '/messaging/v1/sms/messages/';
    private static final String WHATSAPP_PATH = '/messaging/v1/ott/messages/';

    private static final Integer ACCEPTED = 202;
    private static final Integer TIMEOUT_MS = 120000;
    private static final String DEFAULT_DIAL_CODE = '91';
    // E.164 permits at most 15 digits including the country code; the floor keeps obvious
    // junk out without excluding countries with short national numbers.
    private static final Integer MIN_E164_DIGITS = 7;
    private static final Integer MAX_E164_DIGITS = 15;
    private static final String DEFAULT_ORG_WIDE_NAME = 'Alumni Management';
    /**
     * The names the Marketing Cloud credentials already carry across the KJS estate. A guest or
     * portal user cannot read setup metadata, so on the login and registration pages these are the
     * only names available — which is exactly how the KJS admissions code addresses the same
     * endpoints. An org that names its credential differently is still matched by lookup wherever
     * the running user can see it.
     */
    private static final Map<String, String> DEFAULT_SFMC_ENDPOINT_BY_CHANNEL = new Map<String, String>{
        CHANNEL_EMAIL => 'SFMC_sendEmail',
        CHANNEL_SMS => 'SFMC_sendSMS',
        CHANNEL_WHATSAPP => 'SFMC_sendWA'
    };

    private static final List<String> PHONE_CHANNELS = new List<String>{ CHANNEL_SMS, CHANNEL_WHATSAPP };

    private static final Map<String, String> OTP_ATTRIBUTE_BY_CHANNEL = new Map<String, String>{
        CHANNEL_SMS => 'var',
        CHANNEL_WHATSAPP => 'otp'
    };

    /**
     * Message type to the Ken_Alm_Bypass_Settings__c checkbox that suppresses it. Every message type
     * has a switch, so an admin can silence any of them without a deployment.
     */
    private static final Map<String, String> BYPASS_FIELD_BY_TYPE = new Map<String, String>{
        TYPE_OTP_EMAIL => 'Skip_Otp_Email_Template__c',
        TYPE_MAGIC_LINK => 'Skip_Portal_Registration_Invitation__c',
        TYPE_REGISTRATION_SUBMISSION => 'Skip_Alumni_Registration_Submission__c',
        TYPE_REGISTRATION_REJECTION => 'Skip_Alumni_Registration_Rejection_Ema__c',
        TYPE_TEMPORARY_LOGIN => 'Skip_Temporary_Login__c',
        TYPE_SPEAKER_INVITE => 'Skip_Speaker_Invite_Email__c',
        TYPE_EMAIL_CAMPAIGN => 'Skip_Email_Campaign__c',
        TYPE_ADHOC_EMAIL => 'Skip_Adhoc_Email__c',
        TYPE_NEW_ROLE_ADDED => 'Skip_New_Role_Added__c',
        TYPE_LEAD_MERGED => 'Skip_Lead_Merged_Email__c'
    };

    @TestVisible
    private static Map<String, Ken_Message_Definition__mdt> definitionOverride;

    @TestVisible
    private static String credentialOverride;

    // -----------------------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------------------

    /**
     * @description Describes one message: who it goes to, which configured message type it is, and
     *              the merge attributes Marketing Cloud should receive.
     */
    public class Request {

        public String messageType { get; private set; }
        public String channel { get; private set; }
        public List<Recipient> recipients { get; private set; }
        public Map<String, String> attributes { get; private set; }
        public List<Messaging.SingleEmailMessage> nativeFallback { get; private set; }

        public Request(String messageType) {
            this.messageType = messageType;
            this.channel = CHANNEL_EMAIL;
            this.recipients = new List<Recipient>();
            this.attributes = new Map<String, String>();
        }

        public Request onChannel(String channelName) {
            this.channel = channelName;
            return this;
        }

        public Request toEmail(String emailAddress) {
            if (String.isNotBlank(emailAddress)) {
                recipients.add(new Recipient(emailAddress.trim(), emailAddress.trim()));
            }
            return this;
        }

        public Request toPhone(String rawPhone, String dialCode) {
            String normalised = normalisePhone(rawPhone, dialCode);
            if (String.isNotBlank(normalised)) {
                recipients.add(new Recipient(normalised, normalised));
            }
            return this;
        }

        public Request attribute(String key, String value) {
            if (String.isNotBlank(key)) {
                attributes.put(key, value == null ? '' : value);
            }
            return this;
        }

        public Request attributes(Map<String, String> values) {
            if (values != null) {
                attributes.putAll(values);
            }
            return this;
        }

        /**
         * @description Per-recipient attributes, for a bulk send where each person gets different
         *              merge values. Attributes set on the Request are applied to every recipient
         *              underneath these.
         */
        /**
         * @description Hands the gate the native emails the caller would otherwise have sent, so a
         *              Marketing Cloud failure that only becomes known after the caller has moved
         *              on still reaches the alumnus. Without this a deferred send is
         *              fire-and-forget; with it the queueable sends these on any failure.
         */
        public Request withNativeFallback(List<Messaging.SingleEmailMessage> messages) {
            this.nativeFallback = messages;
            return this;
        }

        public Request recipient(String contactKey, Map<String, String> perRecipientAttributes) {
            return recipient(contactKey, null, perRecipientAttributes);
        }

        /**
         * @description A recipient reachable on more than one channel. The phone is carried
         *              alongside the email so the same request can be handed to
         *              sendToPhoneChannels without the caller assembling it twice.
         */
        public Request recipient(String contactKey, String phone, Map<String, String> perRecipientAttributes) {
            if (String.isBlank(contactKey) && String.isBlank(phone)) {
                return this;
            }
            String key = String.isNotBlank(contactKey) ? contactKey.trim() : phone.trim();
            Recipient r = new Recipient(key, key);
            r.phone = phone;
            r.attributes = perRecipientAttributes;
            recipients.add(r);
            return this;
        }

        /**
         * @description A single recipient reachable by email and phone.
         */
        public Request toContact(String emailAddress, String phone) {
            return recipient(emailAddress, phone, null);
        }

        /**
         * @description The same message aimed at one phone channel, keeping only the recipients
         *              who actually have a usable number. Returns null when nobody does, so the
         *              caller can skip the channel without spending a callout.
         */
        private Request copyForPhoneChannel(String phoneChannel) {

            Request copy = new Request(messageType);
            copy.channel = phoneChannel;
            copy.attributes = attributes;

            for (Recipient original : recipients) {
                String normalised = normalisePhone(original.phone, null);
                if (String.isBlank(normalised)) {
                    continue;
                }
                Recipient onPhone = new Recipient(normalised, normalised);
                onPhone.attributes = original.attributes;
                copy.recipients.add(onPhone);
            }
            return copy.recipients.isEmpty() ? null : copy;
        }
    }

    private class Recipient {
        String contactKey;
        String address;
        String phone;
        Map<String, String> attributes;

        Recipient(String contactKey, String address) {
            this.contactKey = contactKey;
            this.address = address;
        }
    }

    /**
     * @description What the gate decided. `handled` true means the caller must not send anything
     *              itself, either because Marketing Cloud accepted it or because it was suppressed.
     */
    public class Result {
        @AuraEnabled public Boolean handled { get; set; }
        @AuraEnabled public Boolean suppressed { get; set; }
        @AuraEnabled public Boolean sentViaSfmc { get; set; }
        @AuraEnabled public String detail { get; set; }

        Result(Boolean handled, Boolean suppressed, Boolean sentViaSfmc, String detail) {
            this.handled = handled;
            this.suppressed = suppressed;
            this.sentViaSfmc = sentViaSfmc;
            this.detail = detail;
        }
    }

    /**
     * @description Routes one message. Never throws; a Marketing Cloud failure returns handled
     *              false so the caller's native path still delivers the message.
     * @param request the message to route
     * @return the routing decision
     */
    public static Result send(Request request) {

        if (request == null || String.isBlank(request.messageType)) {
            return new Result(false, false, false, 'No message type supplied');
        }

        if (isBypassed(request.messageType)) {
            return new Result(true, true, false, 'Suppressed by bypass setting');
        }

        if (!isSfmcEnabled(request.channel)) {
            return new Result(false, false, false, 'Marketing Cloud not enabled for ' + request.channel);
        }

        String definitionKey = definitionKeyFor(request.messageType, request.channel);
        if (String.isBlank(definitionKey)) {
            return new Result(false, false, false,
                'No definition key configured for ' + request.messageType + ' on ' + request.channel);
        }

        if (request.recipients.isEmpty()) {
            return new Result(true, false, false, 'No deliverable recipients');
        }

        String payload = buildPayload(definitionKey, request);
        String endpoint = 'callout:' + namedCredentialFor(request.channel) + pathFor(request.channel);

        if (mustDefer()) {
            if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() <= 0) {
                return new Result(false, false, false, 'No queueable capacity for the Marketing Cloud callout');
            }
            System.enqueueJob(new SfmcCallout(endpoint, payload, request.channel, request.nativeFallback));
            return new Result(true, false, true, 'Queued for Marketing Cloud');
        }

        Boolean accepted = dispatch(endpoint, payload, request.channel);
        return accepted
            ? new Result(true, false, true, 'Accepted by Marketing Cloud')
            : new Result(false, false, false, 'Marketing Cloud rejected the send, falling back to native');
    }

    /**
     * @description Whether the callout has to be handed to a queueable rather than run here.
     *
     *              A trigger can never call out. An async context can, provided the entry class
     *              declares Database.AllowsCallouts and nothing has been committed yet — so the
     *              test is uncommitted DML, not merely being asynchronous. Running inline whenever
     *              it is legal matters for two reasons: the caller learns the real outcome and can
     *              fall back natively, and a queueable that has already spent its single chained
     *              job on its own continuation does not blow up trying to enqueue a second.
     */
    @TestVisible
    private static Boolean mustDefer() {

        if (Trigger.isExecuting) {
            return true;
        }
        if (!System.isFuture() && !System.isQueueable() && !System.isBatch()) {
            return false;
        }
        return Limits.getDmlStatements() > 0;
    }

    /**
     * @description Sends a one-time password to a mobile number on every phone channel the org has
     *              switched on, so an alumnus can receive the same code by SMS, by WhatsApp, or by
     *              both. Channels that are switched off, unmapped, or unreachable cost nothing and
     *              are simply skipped, which makes this safe to call unconditionally next to the
     *              existing email send.
     *
     *              The two channels deliberately use different attribute names for the same code:
     *              the Marketing Cloud journeys this reuses expect `var` on SMS and `otp` on
     *              WhatsApp. Changing either name breaks the journey, not this class.
     *
     * @param messageType the configured message type holding the SMS and WhatsApp definition keys
     * @param mobile      the alumnus's number in any format; blank numbers are ignored
     * @param dialCode    country code to assume, or null for the org default
     * @param code        the one-time password
     * @return the channels the code actually went out on, in the order they were tried
     */
    public static List<String> sendOtpToPhone(String messageType, String mobile, String dialCode, String code) {

        List<String> delivered = new List<String>();
        if (String.isBlank(mobile) || String.isBlank(code)) {
            return delivered;
        }

        for (String channel : PHONE_CHANNELS) {
            Result routed = send(
                new Request(messageType)
                    .onChannel(channel)
                    .toPhone(mobile, dialCode)
                    .attribute(OTP_ATTRIBUTE_BY_CHANNEL.get(channel), code)
            );
            if (routed.sentViaSfmc == true) {
                delivered.add(channel);
            }
        }
        return delivered;
    }

    /**
     * @description Sends the same message on every phone channel the org has switched on, to the
     *              numbers already carried on the request's recipients.
     *
     *              This is deliberately independent of the email decision, so a caller keeps its
     *              existing `if (send(...).handled) return;` flow untouched and simply calls this
     *              alongside. A message can therefore go out natively by email and still reach
     *              WhatsApp. Every guard still applies per channel — a bypassed message type, a
     *              channel that is switched off, a missing definition key or a recipient with no
     *              number all cost nothing and send nothing.
     *
     * @param request the message, with phones supplied via recipient(...) or toContact(...)
     * @return the phone channels the message actually went out on
     */
    public static List<String> sendToPhoneChannels(Request request) {

        List<String> delivered = new List<String>();
        if (request == null) {
            return delivered;
        }

        for (String channel : PHONE_CHANNELS) {
            Request onPhone = request.copyForPhoneChannel(channel);
            if (onPhone == null) {
                continue;
            }
            if (send(onPhone).sentViaSfmc == true) {
                delivered.add(channel);
            }
        }
        return delivered;
    }

    /**
     * @description Display Name of the Organization-Wide Email Address every alumni email is sent
     *              from, so a client can send as their own address without a code change. Falls
     *              back to the name the product has always used.
     *
     * @return the configured display name, or 'Alumni Management'
     */
    public static String orgWideAddressName() {

        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        return (params != null && String.isNotBlank(params.Org_Wide_Email_Address__c))
            ? params.Org_Wide_Email_Address__c.trim()
            : DEFAULT_ORG_WIDE_NAME;
    }

    /**
     * @description Replaces `{Token}` placeholders in a stored email template with the very values
     *              handed to Marketing Cloud.
     *
     *              Both delivery paths merge the same map, so the native email and the journey can
     *              no longer drift apart — which is how a misspelled token survived unnoticed in
     *              the temporary password email.
     *
     * @param template the template body
     * @param tokens   token name to value, without the surrounding braces
     * @return the merged body
     */
    public static String mergeTokens(String template, Map<String, String> tokens) {

        if (String.isBlank(template) || tokens == null) {
            return template;
        }

        String merged = template;
        for (String token : tokens.keySet()) {
            String value = tokens.get(token);
            merged = merged.replace('{' + token + '}', value == null ? '' : value);
        }
        return merged;
    }

    // -----------------------------------------------------------------------------------
    // Configuration
    // -----------------------------------------------------------------------------------

    /**
     * @description Highest priority check. An admin switching a message off must keep it off no
     *              matter which delivery channel is configured.
     */
    @TestVisible
    private static Boolean isBypassed(String messageType) {

        String field = BYPASS_FIELD_BY_TYPE.get(messageType);
        if (String.isBlank(field)) {
            return false;
        }

        Ken_Alm_Bypass_Settings__c settings = KenSettings.bypass();
        if (settings == null) {
            return false;
        }

        Object value = settings.get(field);
        return value == true;
    }

    @TestVisible
    private static Boolean isSfmcEnabled(String channel) {

        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        if (params == null) {
            return false;
        }

        if (channel == CHANNEL_SMS) {
            return params.Send_SMS_Via_SFMC__c == true;
        }
        if (channel == CHANNEL_WHATSAPP) {
            return params.Send_WhatsApp_Via_SFMC__c == true;
        }
        return params.Send_Email_Via_SFMC__c == true;
    }

    /**
     * @description The Named Credential to call for a channel.
     *
     *              `Ken_Alm_Org_Parameters__c.SFMC_Connection__c` names it outright and wins.
     *              One Marketing Cloud tenant is one REST base URI, so that single credential
     *              serves email, SMS and WhatsApp alike — only the path differs. Reading it from a
     *              custom setting also works for the guest user on the login and registration
     *              pages, who cannot see setup metadata at all.
     *
     *              Left blank, the conventional per-channel names are used, which is what the KJS
     *              orgs already have. An earlier version searched the org's Named Credentials for
     *              anything containing "SFMC"; that is deliberately gone, because an org that also
     *              runs Admissions has credentials like SFMC_applicationCompletedEmail and the
     *              search would happily pick one of those for an alumni email.
     */
    @TestVisible
    private static String namedCredentialFor(String channel) {

        String resolved = DEFAULT_SFMC_ENDPOINT_BY_CHANNEL.containsKey(channel) ? channel : CHANNEL_EMAIL;

        if (credentialOverride != null) {
            return credentialOverride;
        }

        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        if (params != null && String.isNotBlank(params.SFMC_Connection__c)) {
            return params.SFMC_Connection__c.trim();
        }
        return DEFAULT_SFMC_ENDPOINT_BY_CHANNEL.get(resolved);
    }

    private static String pathFor(String channel) {
        if (channel == CHANNEL_SMS) {
            return SMS_PATH;
        }
        if (channel == CHANNEL_WHATSAPP) {
            return WHATSAPP_PATH;
        }
        return EMAIL_PATH;
    }

    /**
     * @description Marketing Cloud definition key for a message type and channel, from
     *              Ken_Message_Definition__mdt so each org maps its own journeys.
     */
    @TestVisible
    private static String definitionKeyFor(String messageType, String channel) {

        Ken_Message_Definition__mdt definition = definitions().get(messageType);
        if (definition == null || definition.Active__c != true) {
            return null;
        }

        if (channel == CHANNEL_SMS) {
            return definition.SMS_Definition_Ref__c;
        }
        if (channel == CHANNEL_WHATSAPP) {
            return definition.WhatsApp_Definition_Ref__c;
        }
        return definition.Email_Definition_Ref__c;
    }

    private static Map<String, Ken_Message_Definition__mdt> definitions() {

        if (definitionOverride != null) {
            return definitionOverride;
        }

        Map<String, Ken_Message_Definition__mdt> byType = new Map<String, Ken_Message_Definition__mdt>();
        for (Ken_Message_Definition__mdt definition : Ken_Message_Definition__mdt.getAll().values()) {
            byType.put(definition.DeveloperName, definition);
        }
        return byType;
    }

    // -----------------------------------------------------------------------------------
    // Payload and transport
    // -----------------------------------------------------------------------------------

    private static String buildPayload(String definitionKey, Request request) {

        List<Map<String, Object>> recipients = new List<Map<String, Object>>();

        for (Recipient r : request.recipients) {
            Map<String, String> merged = new Map<String, String>(request.attributes);
            if (r.attributes != null) {
                merged.putAll(r.attributes);
            }
            recipients.add(new Map<String, Object>{
                'contactKey' => r.contactKey,
                'to' => r.address,
                'attributes' => merged
            });
        }

        return JSON.serialize(new Map<String, Object>{
            'definitionKey' => definitionKey,
            'recipients' => recipients
        });
    }

    /**
     * @description Carries the callout out of a trigger or DML transaction, where Apex forbids it.
     *              Because the caller was told the message was handled before the callout ran, this
     *              is the only place left that can rescue it, so a failure here sends the caller's
     *              native emails rather than logging and giving up.
     */
    public class SfmcCallout implements Queueable, Database.AllowsCallouts {

        private final String endpoint;
        private final String payload;
        private final String channel;
        private final List<Messaging.SingleEmailMessage> nativeFallback;

        public SfmcCallout(
            String endpoint,
            String payload,
            String channel,
            List<Messaging.SingleEmailMessage> nativeFallback
        ) {
            this.endpoint = endpoint;
            this.payload = payload;
            this.channel = channel;
            this.nativeFallback = nativeFallback;
        }

        public void execute(QueueableContext context) {
            if (dispatch(endpoint, payload, channel)) {
                return;
            }
            if (nativeFallback == null || nativeFallback.isEmpty()) {
                System.debug(LoggingLevel.ERROR,
                    'KenMessagingService ' + channel + ' send failed with no native fallback supplied; '
                    + 'the message was not delivered');
                return;
            }
            try {
                Messaging.sendEmail(nativeFallback, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'KenMessagingService native fallback also failed: ' + e.getMessage());
            }
        }
    }

    /**
     * @description Posts to Marketing Cloud. Returns whether it accepted the request; failures are
     *              logged rather than thrown so a messaging outage never breaks the caller.
     */
    @TestVisible
    private static Boolean dispatch(String endpoint, String payload, String channel) {

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(payload);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() != ACCEPTED) {
                System.debug(LoggingLevel.ERROR,
                    'KenMessagingService ' + channel + ' send rejected. Status '
                    + res.getStatusCode() + ': ' + res.getBody());
                return false;
            }
            return true;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenMessagingService ' + channel + ' callout failed: ' + e.getMessage());
            return false;
        }
    }

    // -----------------------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------------------

    /**
     * @description Normalises a phone number to the digits-only international form Marketing Cloud
     *              expects for SMS and WhatsApp. Returns null when the number is unusable.
     */
    @TestVisible
    private static String normalisePhone(String rawPhone, String rawDialCode) {

        if (String.isBlank(rawPhone)) {
            return null;
        }

        String digits = digitsOnly(rawPhone);
        if (String.isBlank(digits)) {
            return null;
        }

        // Already international, so these digits are the whole number and no default may
        // be prepended. The '+' is the only marker of where the country code ends, so once
        // digitsOnly has removed it the number can no longer be re-split: a country whose
        // code and national number total ten digits (Singapore's '+65 91234567') would
        // otherwise be mistaken for a bare national number and have the org default glued
        // in front of it, producing a plausible-looking number belonging to nobody.
        if (rawPhone.trim().startsWith('+')) {
            return (digits.length() >= MIN_E164_DIGITS && digits.length() <= MAX_E164_DIGITS)
                ? digits
                : null;
        }

        String dialCode = digitsOnly(rawDialCode);
        if (String.isBlank(dialCode)) {
            Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
            dialCode = (params != null && String.isNotBlank(params.Default_Dial_Code__c))
                ? digitsOnly(params.Default_Dial_Code__c)
                : DEFAULT_DIAL_CODE;
        }
        if (String.isBlank(dialCode)) {
            dialCode = DEFAULT_DIAL_CODE;
        }

        if (digits.length() == 11 && digits.startsWith('0')) {
            digits = digits.substring(1);
        }
        if (digits.length() == 10) {
            return dialCode + digits;
        }
        if (digits.length() == (dialCode.length() + 10) && digits.startsWith(dialCode)) {
            return digits;
        }
        if (digits.length() >= 11 && digits.length() <= 15) {
            return digits;
        }
        return null;
    }

    private static String digitsOnly(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String digits = value.replaceAll('[^0-9]', '');
        return String.isBlank(digits) ? null : digits;
    }
}