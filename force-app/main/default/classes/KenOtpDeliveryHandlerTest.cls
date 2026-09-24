/**
 * @description Coverage for the passwordless login delivery hook: the platform's code reaching
 *              Marketing Cloud, and every reason it might not.
 */
@IsTest(IsParallel=false)
private class KenOtpDeliveryHandlerTest {

    private class AcceptedMock implements HttpCalloutMock {
        public String capturedBody;
        public HttpResponse respond(HttpRequest req) {
            capturedBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(202);
            return res;
        }
    }

    private static void enablePhoneChannels() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        params.Send_SMS_Via_SFMC__c = true;
        params.Send_WhatsApp_Via_SFMC__c = true;
        params.Default_Dial_Code__c = '91';
        upsert params;

        KenMessagingService.credentialOverride = null;
        KenMessagingService.definitionOverride = new Map<String, Ken_Message_Definition__mdt>{
            KenMessagingService.TYPE_LOGIN_OTP => new Ken_Message_Definition__mdt(
                DeveloperName = KenMessagingService.TYPE_LOGIN_OTP,
                Active__c = true,
                SMS_Definition_Ref__c = 'SMS_OTP_3',
                WhatsApp_Definition_Ref__c = 'WA_OTP_1'
            )
        };
    }

    /**
     * @description A throwaway internal user to sign in as, with or without a mobile number.
     *
     *              These tests used to edit the running user's own record instead. That row is
     *              shared with every other test class in the run, and several of them update it
     *              too, so whichever transaction got there second died with UNABLE_TO_LOCK_ROW.
     *              A user nobody else knows about cannot be contended. It is inserted under
     *              runAs so the User DML never mixes with the custom-setting write above.
     */
    private static User internalUser(String mobile) {
        User signingIn = new User(
            Username          = 'otp.delivery.' + System.currentTimeMillis() + '.'
                                + Math.abs(Crypto.getRandomInteger()) + '@kenotp.test',
            Email             = 'otp.delivery@kenotp.test',
            LastName          = 'OtpDelivery',
            Alias             = 'otpdlvry',
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = UserInfo.getProfileId(),
            MobilePhone       = mobile
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert signingIn;
        }
        return signingIn;
    }

    @IsTest
    static void deliversThePlatformCodeToMarketingCloud() {

        enablePhoneChannels();
        Id signingIn = internalUser(null).Id;

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Auth.CustomOneTimePasswordDeliveryResult result = new KenOtpDeliveryHandler().sendOneTimePassword(
            signingIn, '9876543210', '482913', 'Your code is 482913', null, 'Alumni'
        );
        Test.stopTest();

        System.assertEquals(Auth.CustomOneTimePasswordDeliveryResult.SUCCESS, result,
            'A code handed to Marketing Cloud must report success so the platform waits for it');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('WA_OTP_1', body.get('definitionKey'), 'WhatsApp is the second channel tried');

        List<Object> recipients = (List<Object>) body.get('recipients');
        Map<String, Object> first = (Map<String, Object>) recipients[0];
        Map<String, Object> attributes = (Map<String, Object>) first.get('attributes');
        System.assertEquals('482913', attributes.get('otp'),
            'The third parameter is the code — sending the second would text people their own number');
        System.assertEquals('919876543210', first.get('to'),
            'The second parameter is the destination number, and it must carry the dial code');
    }

    @IsTest
    static void theUserRecordIsUsedWhenThereIsNoPersonAccount() {

        enablePhoneChannels();
        Id signingIn = internalUser('9000000009').Id;

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new KenOtpDeliveryHandler().sendOneTimePassword(
            signingIn, '9123456780', '482913', null, null, null
        );
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        List<Object> recipients = (List<Object>) body.get('recipients');
        Map<String, Object> first = (Map<String, Object>) recipients[0];
        System.assertEquals('919000000009', first.get('to'),
            'With no Person Account behind the user, the number on the User record is used');
    }

    @IsTest
    static void theSuppliedNumberIsTheLastResort() {

        enablePhoneChannels();
        Id signingIn = internalUser(null).Id;

        AcceptedMock mock = new AcceptedMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Auth.CustomOneTimePasswordDeliveryResult result = new KenOtpDeliveryHandler().sendOneTimePassword(
            signingIn, '9123456780', '482913', null, null, null
        );
        Test.stopTest();

        System.assertEquals(Auth.CustomOneTimePasswordDeliveryResult.SUCCESS, result,
            'Nothing on the alumni records means the number the platform supplied is still usable');

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        List<Object> recipients = (List<Object>) body.get('recipients');
        Map<String, Object> first = (Map<String, Object>) recipients[0];
        System.assertEquals('919123456780', first.get('to'), 'The platform-supplied number is the fallback');
    }

    @IsTest
    static void missingNumberIsReportedAsSuch() {

        enablePhoneChannels();
        Id signingIn = internalUser(null).Id;

        Test.startTest();
        Auth.CustomOneTimePasswordDeliveryResult result = new KenOtpDeliveryHandler().sendOneTimePassword(
            signingIn, null, '482913', null, null, null
        );
        Test.stopTest();

        System.assertEquals(Auth.CustomOneTimePasswordDeliveryResult.INVALID_PHONE_NUMBER, result,
            'The platform must be told the number is the problem so the alumnus sees the right error');
    }

    @IsTest
    static void marketingCloudOffIsReportedAsAProviderError() {

        Test.startTest();
        Auth.CustomOneTimePasswordDeliveryResult result = new KenOtpDeliveryHandler().sendOneTimePassword(
            UserInfo.getUserId(), '9876543210', '482913', null, null, null
        );
        Test.stopTest();

        System.assertEquals(Auth.CustomOneTimePasswordDeliveryResult.PROVIDER_ERROR, result,
            'Registering the handler without switching the channels on must fail loudly, not silently');
    }

    @IsTest
    static void aMissingCodeIsRejected() {

        Test.startTest();
        Auth.CustomOneTimePasswordDeliveryResult noCode = new KenOtpDeliveryHandler().sendOneTimePassword(
            UserInfo.getUserId(), '9876543210', '  ', null, null, null
        );
        Test.stopTest();

        System.assertEquals(Auth.CustomOneTimePasswordDeliveryResult.EXCEPTION, noCode,
            'No code, nothing to send');
    }

    /**
     * @description The Person Account is created in its own transaction; inserting a portal user
     *              alongside its freshly created Contact reliably trips UNABLE_TO_LOCK_ROW.
     */
    @TestSetup
    static void makeAccount() {
        insert new Account(
            FirstName = 'Test',
            LastName = 'Alumnus',
            PersonEmail = 'fallback.alumnus@kenotp.test',
            PersonMobilePhone = '9123456780',
            RecordTypeId = [
                SELECT Id FROM RecordType
                WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true
                LIMIT 1
            ].Id
        );
    }

    @IsTest
    static void mobileFallsBackToThePersonAccount() {

        Account person = [
            SELECT Id FROM Account WHERE PersonEmail = 'fallback.alumnus@kenotp.test' LIMIT 1
        ];

        User linkedToAccount = (User) JSON.deserialize(
            '{"attributes":{"type":"User"},"AccountId":"' + person.Id + '"}',
            User.class
        );

        Test.startTest();
        String resolved = KenOtpDeliveryHandler.numberFor(linkedToAccount);
        Test.stopTest();

        System.assertEquals('9123456780', resolved,
            'A user with no MobilePhone must fall back to the number on their Person Account');
    }

    @IsTest
    static void theUserNumberBeatsThePersonAccount() {

        Account person = [
            SELECT Id FROM Account WHERE PersonEmail = 'fallback.alumnus@kenotp.test' LIMIT 1
        ];

        User portalUser = (User) JSON.deserialize(
            '{"attributes":{"type":"User"},"AccountId":"' + person.Id + '","MobilePhone":"+91 9000000001"}',
            User.class
        );

        Test.startTest();
        String resolved = KenOtpDeliveryHandler.numberFor(portalUser);
        Test.stopTest();

        System.assertEquals('+91 9000000001', resolved,
            'Identity lives on the User, so the number the platform challenged against is the one we text');
    }

    @IsTest
    static void userWithNoAccountResolvesToNothing() {

        Id signingIn = internalUser(null).Id;

        Test.startTest();
        String noAccount = KenOtpDeliveryHandler.numberFor(new User());
        String noUser = KenOtpDeliveryHandler.numberFor(null);
        String unknown = KenOtpDeliveryHandler.resolveMobile(signingIn);
        Test.stopTest();

        System.assertEquals(null, noAccount, 'No number and no account means nothing to text');
        System.assertEquals(null, noUser, 'A null user must not throw');
        System.assertEquals(null, unknown,
            'An internal user with no mobile and no Person Account has no number to text');
    }
}