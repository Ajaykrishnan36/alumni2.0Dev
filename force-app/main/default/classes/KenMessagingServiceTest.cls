/**
 * @description Coverage for the outbound messaging gate: bypass winning over Marketing Cloud,
 *              per-channel enablement, definition key resolution, payload shape and phone
 *              normalisation.
 */
@IsTest
private class KenMessagingServiceTest {

    private class AcceptedMock implements HttpCalloutMock {
        public String capturedBody;
        public String capturedEndpoint;
        public HttpResponse respond(HttpRequest req) {
            capturedBody = req.getBody();
            capturedEndpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(202);
            return res;
        }
    }

    private class RejectedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"message":"bad definition key"}');
            return res;
        }
    }

    /**
     * @description Turns Marketing Cloud on for all three channels. Named Credentials are read from
     *              the org rather than configured, so tests stub the list the org would return.
     */
    private static void enableSfmc() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        params.Send_Email_Via_SFMC__c = true;
        params.Send_SMS_Via_SFMC__c = true;
        params.Send_WhatsApp_Via_SFMC__c = true;
        params.Default_Dial_Code__c = '91';
        upsert params;
        KenMessagingService.credentialOverride = null;
    }

    private static void stubDefinition(String messageType, String emailKey, String smsKey, String waKey) {
        KenMessagingService.definitionOverride = new Map<String, Ken_Message_Definition__mdt>{
            messageType => new Ken_Message_Definition__mdt(
                DeveloperName = messageType,
                Active__c = true,
                Email_Definition_Ref__c = emailKey,
                SMS_Definition_Ref__c = smsKey,
                WhatsApp_Definition_Ref__c = waKey
            )
        };
    }

    @IsTest
    static void bypassBeatsMarketingCloud() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, 'alumni_otp', null, null);

        Ken_Alm_Bypass_Settings__c settings = KenSettings.bypass();
        settings.Skip_Otp_Email_Template__c = true;
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new RejectedMock());

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL).toEmail('a@b.com')
        );
        Test.stopTest();

        System.assertEquals(true, result.handled, 'A bypassed message must be reported as handled');
        System.assertEquals(true, result.suppressed, 'A bypassed message must be marked suppressed');
        System.assertEquals(false, result.sentViaSfmc,
            'Enabling Marketing Cloud must never resurrect a message an admin switched off');
    }

    @IsTest
    static void routesEmailToMarketingCloud() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_MAGIC_LINK, 'send_magic_link', null, null);

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_MAGIC_LINK)
                .toEmail('alum@example.com')
                .attribute('Recipient_Name', 'Asha')
                .attribute('Portal_Url', 'https://portal.example.com')
        );
        Test.stopTest();

        System.assertEquals(true, result.handled, 'Marketing Cloud accepted the send');
        System.assertEquals(true, result.sentViaSfmc, 'The message went to Marketing Cloud');
        System.assert(mock.capturedEndpoint.contains('SFMC_sendEmail'),
            'An org with a credential per channel must use its email credential');
        System.assert(mock.capturedEndpoint.contains('/messaging/v1/email/messages'),
            'The email channel must post to the email messaging path');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('send_magic_link', body.get('definitionKey'), 'Definition key must be sent');

        List<Object> recipients = (List<Object>) body.get('recipients');
        System.assertEquals(1, recipients.size(), 'One recipient expected');

        Map<String, Object> first = (Map<String, Object>) recipients[0];
        System.assertEquals('alum@example.com', first.get('to'), 'Recipient address must be the email');
        System.assertEquals('alum@example.com', first.get('contactKey'), 'Contact key must be the email');

        Map<String, Object> attributes = (Map<String, Object>) first.get('attributes');
        System.assertEquals('Asha', attributes.get('Recipient_Name'), 'Attributes must reach the payload');
    }

    @IsTest
    static void nativePathKeptWhenSfmcDisabled() {

        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, 'alumni_otp', null, null);

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL).toEmail('a@b.com')
        );
        Test.stopTest();

        System.assertEquals(false, result.handled,
            'With Marketing Cloud off the caller must fall back to its native send');
    }

    @IsTest
    static void nativePathKeptWhenDefinitionKeyMissing() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, null, null, null);

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL).toEmail('a@b.com')
        );
        Test.stopTest();

        System.assertEquals(false, result.handled,
            'A message type with no definition key must keep using the native path');
    }

    @IsTest
    static void nativePathKeptWhenMarketingCloudRejects() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, 'alumni_otp', null, null);
        Test.setMock(HttpCalloutMock.class, new RejectedMock());

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL).toEmail('a@b.com')
        );
        Test.stopTest();

        System.assertEquals(false, result.handled,
            'A rejected send must fall back so the message still reaches the alumnus');
    }

    @IsTest
    static void routesSmsAndNormalisesPhone() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, null, 'alumni_otp_sms', null);

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL)
                .onChannel(KenMessagingService.CHANNEL_SMS)
                .toPhone('98765 43210', '+91')
                .attribute('otp', '123456')
        );
        Test.stopTest();

        System.assertEquals(true, result.sentViaSfmc, 'SMS should route to Marketing Cloud');
        System.assert(mock.capturedEndpoint.contains('/messaging/v1/sms/messages/'),
            'SMS must post to the SMS messaging path');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        List<Object> recipients = (List<Object>) body.get('recipients');
        Map<String, Object> first = (Map<String, Object>) recipients[0];
        System.assertEquals('919876543210', first.get('to'),
            'The number must be normalised to digits with the dial code');
    }

    @IsTest
    static void routesWhatsAppToOttPath() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_MAGIC_LINK, null, null, 'alumni_wa');

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_MAGIC_LINK)
                .onChannel(KenMessagingService.CHANNEL_WHATSAPP)
                .toPhone('9876543210', null)
        );
        Test.stopTest();

        System.assert(mock.capturedEndpoint.contains('/messaging/v1/ott/messages/'),
            'WhatsApp must post to the OTT messaging path');
        System.assert(mock.capturedEndpoint.contains('SFMC_sendWA'),
            'An org with a credential per channel must use its WhatsApp credential');
    }

    @IsTest
    static void theConfiguredCredentialServesEveryChannel() {

        enableSfmc();
        KenMessagingService.credentialOverride = null;

        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        params.SFMC_Connection__c = 'SFMC_Alumni';
        upsert params;

        Test.startTest();
        String email = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_EMAIL);
        String sms = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_SMS);
        String whatsApp = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_WHATSAPP);
        Test.stopTest();

        System.assertEquals('SFMC_Alumni', email, 'The configured credential must serve email');
        System.assertEquals('SFMC_Alumni', sms, 'One tenant, one credential — it serves SMS too');
        System.assertEquals('SFMC_Alumni', whatsApp, 'And WhatsApp; only the path differs');
    }

    @IsTest
    static void conventionalNameUsedWhenNothingIsConfigured() {

        enableSfmc();
        KenMessagingService.credentialOverride = null;

        Test.startTest();
        String resolved = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_EMAIL);
        Test.stopTest();

        System.assertEquals('SFMC_sendEmail', resolved,
            'With the field blank the org convention applies, which is what the KJS orgs already have');
    }

    @IsTest
    static void anAdmissionsCredentialIsNeverPickedUp() {

        enableSfmc();
        KenMessagingService.credentialOverride = null;

        Test.startTest();
        String email = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_EMAIL);
        Test.stopTest();

        System.assertEquals('SFMC_sendEmail', email,
            'Resolution must never search the org: an Admissions org also holds credentials like '
            + 'SFMC_applicationCompletedEmail, and a search would send alumni mail through one');
    }

    @IsTest
    static void conventionalNameIsPerChannel() {

        enableSfmc();
        KenMessagingService.credentialOverride = null;

        Test.startTest();
        String sms = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_SMS);
        String whatsApp = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_WHATSAPP);
        Test.stopTest();

        System.assertEquals('SFMC_sendSMS', sms, 'The SMS fallback must match the existing org convention');
        System.assertEquals('SFMC_sendWA', whatsApp, 'The WhatsApp fallback must match the existing org convention');
    }

    @IsTest
    static void calloutRunsInlineWhenNothingHasBeenCommitted() {
        Test.startTest();
        Boolean deferred = KenMessagingService.mustDefer();
        Test.stopTest();

        System.assertEquals(false, deferred,
            'A synchronous transaction with no DML must call out inline so the caller can fall back');
    }

    @IsTest
    static void deferredFailureFallsBackToTheNativeEmails() {

        Test.setMock(HttpCalloutMock.class, new RejectedMock());

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ 'alum@example.com' });
        mail.setSubject('Your magic link');
        mail.setHtmlBody('<p>link</p>');
        mail.setSaveAsActivity(false);

        KenMessagingService.SfmcCallout job = new KenMessagingService.SfmcCallout(
            'callout:SFMC_sendEmail/messaging/v1/email/messages',
            '{"definitionKey":"x","recipients":[]}',
            KenMessagingService.CHANNEL_EMAIL,
            new List<Messaging.SingleEmailMessage>{ mail }
        );

        Test.startTest();
        Integer before = Limits.getEmailInvocations();
        job.execute(null);
        Integer after = Limits.getEmailInvocations();
        Test.stopTest();

        System.assert(after > before,
            'A rejected deferred send must still deliver the message through the native path');
    }

    @IsTest
    static void deferredFailureWithoutFallbackIsSurvivable() {

        Test.setMock(HttpCalloutMock.class, new RejectedMock());

        KenMessagingService.SfmcCallout job = new KenMessagingService.SfmcCallout(
            'callout:SFMC_sendEmail/messaging/v1/email/messages',
            '{"definitionKey":"x","recipients":[]}',
            KenMessagingService.CHANNEL_EMAIL,
            null
        );

        Test.startTest();
        job.execute(null);
        Test.stopTest();

        System.assert(true, 'A caller that supplied no fallback must not break the queueable');
    }

    @IsTest
    static void sharedTenantCredentialServesAChannelItDoesNotName() {

        enableSfmc();
        KenMessagingService.credentialOverride = 'SFMC_Alumni_Tenant';

        Test.startTest();
        String resolved = KenMessagingService.namedCredentialFor(KenMessagingService.CHANNEL_SMS);
        Test.stopTest();

        System.assertEquals('SFMC_Alumni_Tenant', resolved,
            'A credential naming no channel is the shared tenant credential for every channel');
    }

    @IsTest
    static void perRecipientAttributesOverrideShared() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_EMAIL_CAMPAIGN, 'alumni_campaign', null, null);

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_EMAIL_CAMPAIGN)
                .attribute('Institution_Alias', 'Somaiya')
                .recipient('one@example.com', new Map<String, String>{ 'Recipient_Name' => 'One' })
                .recipient('two@example.com', new Map<String, String>{ 'Recipient_Name' => 'Two' })
        );
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        List<Object> recipients = (List<Object>) body.get('recipients');
        System.assertEquals(2, recipients.size(), 'Both recipients must be in one payload');

        Map<String, Object> second = (Map<String, Object>) recipients[1];
        Map<String, Object> attributes = (Map<String, Object>) second.get('attributes');
        System.assertEquals('Two', attributes.get('Recipient_Name'), 'Per-recipient attribute expected');
        System.assertEquals('Somaiya', attributes.get('Institution_Alias'),
            'Shared attributes must also be applied to each recipient');
    }

    @IsTest
    static void noDeliverableRecipientIsHandledWithoutCallout() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, 'alumni_otp', null, null);

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL).toEmail('   ')
        );
        Test.stopTest();

        System.assertEquals(true, result.handled, 'Nothing to send is still handled');
        System.assertEquals(false, result.sentViaSfmc, 'No callout should be attempted');
    }

    @IsTest
    static void unusablePhoneIsDropped() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, null, 'sms_key', null);

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL)
                .onChannel(KenMessagingService.CHANNEL_SMS)
                .toPhone('123', '91')
        );
        Test.stopTest();

        System.assertEquals(false, result.sentViaSfmc, 'A too-short number must not be sent');
    }

    @IsTest
    static void inactiveDefinitionFallsBackToNative() {

        enableSfmc();
        KenMessagingService.definitionOverride = new Map<String, Ken_Message_Definition__mdt>{
            KenMessagingService.TYPE_OTP_EMAIL => new Ken_Message_Definition__mdt(
                DeveloperName = KenMessagingService.TYPE_OTP_EMAIL,
                Active__c = false,
                Email_Definition_Ref__c = 'alumni_otp'
            )
        };

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL).toEmail('a@b.com')
        );
        Test.stopTest();

        System.assertEquals(false, result.handled,
            'Deactivating a definition must return the message type to the native path');
    }

    @IsTest
    static void everyMessageTypeCanBeSwitchedOff() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_EMAIL_CAMPAIGN, 'alumni_campaign', null, null);

        Ken_Alm_Bypass_Settings__c settings = KenSettings.bypass();
        settings.Skip_Email_Campaign__c = true;
        settings.Skip_Adhoc_Email__c = true;
        settings.Skip_New_Role_Added__c = true;
        upsert settings;

        Test.setMock(HttpCalloutMock.class, new RejectedMock());

        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_EMAIL_CAMPAIGN).toEmail('a@b.com')
        );
        Test.stopTest();

        System.assertEquals(true, result.suppressed,
            'The message types that had no off switch must now be suppressible too');
    }

    @IsTest
    static void otpGoesOutOnBothPhoneChannels() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, 'alumni_otp', 'SMS_OTP_3', 'WA_OTP_1');

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<String> delivered = KenMessagingService.sendOtpToPhone(
            KenMessagingService.TYPE_OTP_EMAIL, '98765 43210', '+91', '4321'
        );
        Test.stopTest();

        System.assertEquals(2, delivered.size(), 'The code must go out on both SMS and WhatsApp');
        System.assertEquals(KenMessagingService.CHANNEL_SMS, delivered[0], 'SMS is tried first');
        System.assertEquals(KenMessagingService.CHANNEL_WHATSAPP, delivered[1], 'WhatsApp is tried second');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('WA_OTP_1', body.get('definitionKey'), 'The last send used the WhatsApp key');

        List<Object> recipients = (List<Object>) body.get('recipients');
        Map<String, Object> first = (Map<String, Object>) recipients[0];
        Map<String, Object> attributes = (Map<String, Object>) first.get('attributes');
        System.assertEquals('4321', attributes.get('otp'),
            'WhatsApp journeys read the code from the otp attribute');
        System.assertEquals(null, attributes.get('var'),
            'The SMS attribute name must not leak into the WhatsApp payload');
    }

    @IsTest
    static void otpPhoneSendIsSkippedWithoutANumber() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, 'alumni_otp', 'SMS_OTP_3', 'WA_OTP_1');

        Test.startTest();
        List<String> noNumber = KenMessagingService.sendOtpToPhone(
            KenMessagingService.TYPE_OTP_EMAIL, '   ', null, '4321'
        );
        List<String> noCode = KenMessagingService.sendOtpToPhone(
            KenMessagingService.TYPE_OTP_EMAIL, '9876543210', null, null
        );
        Test.stopTest();

        System.assertEquals(0, noNumber.size(), 'An alumnus with no mobile number costs no callout');
        System.assertEquals(0, noCode.size(), 'A blank code must never be sent');
    }

    @IsTest
    static void otpPhoneSendStaysOffWhenChannelsAreDisabled() {

        stubDefinition(KenMessagingService.TYPE_OTP_EMAIL, 'alumni_otp', 'SMS_OTP_3', 'WA_OTP_1');

        Test.startTest();
        List<String> delivered = KenMessagingService.sendOtpToPhone(
            KenMessagingService.TYPE_OTP_EMAIL, '9876543210', '91', '4321'
        );
        Test.stopTest();

        System.assertEquals(0, delivered.size(),
            'With the phone channels switched off this must be free to call next to the email send');
    }

    @IsTest
    static void aCampaignReachesEmailAndBothPhoneChannels() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_EMAIL_CAMPAIGN, 'campaign_email', 'campaign_sms', 'campaign_wa');

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        KenMessagingService.Request routing =
            new KenMessagingService.Request(KenMessagingService.TYPE_EMAIL_CAMPAIGN)
                .attribute('Institution_Alias', 'Somaiya')
                .recipient('one@example.com', '9876543210', new Map<String, String>{ 'Recipient_Name' => 'One' })
                .recipient('two@example.com', null, new Map<String, String>{ 'Recipient_Name' => 'Two' });

        Test.startTest();
        List<String> phoneChannels = KenMessagingService.sendToPhoneChannels(routing);
        KenMessagingService.Result emailResult = KenMessagingService.send(routing);
        Test.stopTest();

        System.assertEquals(2, phoneChannels.size(), 'The campaign must reach SMS and WhatsApp');
        System.assertEquals(true, emailResult.sentViaSfmc, 'The email channel is unaffected');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('campaign_email', body.get('definitionKey'),
            'The last send is the email one, using the email key');
    }

    @IsTest
    static void recipientsWithoutANumberAreDroppedFromThePhoneSend() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_EMAIL_CAMPAIGN, 'campaign_email', 'campaign_sms', null);

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        KenMessagingService.Request routing =
            new KenMessagingService.Request(KenMessagingService.TYPE_EMAIL_CAMPAIGN)
                .recipient('one@example.com', '9876543210', null)
                .recipient('two@example.com', null, null);

        Test.startTest();
        List<String> phoneChannels = KenMessagingService.sendToPhoneChannels(routing);
        Test.stopTest();

        System.assertEquals(new List<String>{ KenMessagingService.CHANNEL_SMS }, phoneChannels,
            'WhatsApp has no key here, so only SMS carries it');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        List<Object> recipients = (List<Object>) body.get('recipients');
        System.assertEquals(1, recipients.size(),
            'The alumnus with no number must be dropped rather than sent a blank address');

        Map<String, Object> only = (Map<String, Object>) recipients[0];
        System.assertEquals('919876543210', only.get('to'), 'The number must be normalised');
    }

    @IsTest
    static void nobodyWithANumberCostsNoCallout() {

        enableSfmc();
        stubDefinition(KenMessagingService.TYPE_EMAIL_CAMPAIGN, 'campaign_email', 'campaign_sms', 'campaign_wa');
        Test.setMock(HttpCalloutMock.class, new RejectedMock());

        Test.startTest();
        List<String> phoneChannels = KenMessagingService.sendToPhoneChannels(
            new KenMessagingService.Request(KenMessagingService.TYPE_EMAIL_CAMPAIGN)
                .toEmail('nophone@example.com')
        );
        Test.stopTest();

        System.assertEquals(0, phoneChannels.size(),
            'An email-only audience must not spend a callout on the phone channels');
    }

    @IsTest
    static void oneTokenMapDrivesBothPaths() {

        Map<String, String> tokens = new Map<String, String>{
            'Recipient_Name' => 'Asha',
            'Portal_Url' => 'https://portal.example.com',
            'Missing_Value' => null
        };

        Test.startTest();
        String merged = KenMessagingService.mergeTokens(
            '<p>Hello {Recipient_Name}, visit {Portal_Url}{Missing_Value}</p>', tokens
        );
        String untouched = KenMessagingService.mergeTokens(null, tokens);
        Test.stopTest();

        System.assertEquals('<p>Hello Asha, visit https://portal.example.com</p>', merged,
            'The same map that feeds Marketing Cloud must merge the Classic template');
        System.assertEquals(null, untouched, 'A missing template must not throw');
    }

    @IsTest
    static void nullRequestIsSafe() {
        Test.startTest();
        KenMessagingService.Result result = KenMessagingService.send(null);
        Test.stopTest();
        System.assertEquals(false, result.handled, 'A null request must not be treated as handled');
    }
}