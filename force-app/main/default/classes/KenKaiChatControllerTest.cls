/**
 * @description Covers KenKaiChatController: config resolution for the two audiences, the
 *              bypass and unconfigured branches, and the two-call token handshake against a
 *              mocked KAI Chat Service.
 */
@IsTest
private class KenKaiChatControllerTest {

    private static final String NC_NAME = 'KAI_Chat_Test';
    private static final String API_KEY = 'kai_v2_test_key';
    private static final String PUBLIC_AGENT = 'public-agent-id';
    private static final String AUTH_AGENT = 'auth-agent-id';
    private static final String TOKEN = 'eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE5MDAwMDAwMDB9.sig';
    private static final String SDK_URL = 'https://cdn.example.com/kai/widget.global.js';

    private static void configure(Boolean bypass) {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        params.KAI_Chat_Connection__c = NC_NAME;
        params.KAI_Client_Id__c = API_KEY;
        params.KAI_Anonymous_Agent_Id__c = PUBLIC_AGENT;
        params.KAI_Verified_Agent_Id__c = AUTH_AGENT;
        params.KAI_SDK_URL__c = SDK_URL;
        upsert params;

        Ken_Alm_Module_Settings__c modules = Ken_Alm_Module_Settings__c.getOrgDefaults();
        modules.Skip_KAI_Chat__c = bypass;
        upsert modules;
    }

    private class KaiMock implements HttpCalloutMock {
        Integer provisionStatus = 201;
        Integer tokenStatus = 200;
        String tokenBody = '{"user_id":"kai-1","external_id":"' + UserInfo.getUserId() + '","access_token":"' + TOKEN + '","refresh_token":"r"}';
        List<HttpRequest> requests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            if (request.getEndpoint().endsWith('/token')) {
                response.setStatusCode(tokenStatus);
                response.setBody(tokenBody);
            } else {
                response.setStatusCode(provisionStatus);
                response.setBody('{"user_id":"kai-1","external_id":"' + UserInfo.getUserId() + '","created":true}');
            }
            return response;
        }
    }

    @IsTest
    static void getConfigReturnsAuthenticatedAgentForInternalUser() {
        configure(false);

        KenKaiChatController.KaiConfig config = KenKaiChatController.getConfig();

        System.assertEquals(true, config.enabled, 'Feature should be enabled once configured');
        System.assertEquals(false, config.isGuest, 'Running user is not a guest');
        System.assertEquals(API_KEY, config.apiKey, 'API key should be returned for the widget');
        System.assertEquals(AUTH_AGENT, config.agentId, 'Authenticated agent expected for a logged-in user');
        System.assertEquals(SDK_URL, config.sdkUrl, 'SDK URL should be returned for the bridge to load');
    }

    @IsTest
    static void getConfigIsDisabledWithoutSdkUrl() {
        configure(false);
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        params.KAI_SDK_URL__c = null;
        upsert params;

        KenKaiChatController.KaiConfig config = KenKaiChatController.getConfig();

        System.assertEquals(false, config.enabled, 'No SDK URL means nothing to load, so the widget stays off');
    }

    @IsTest
    static void getConfigIsDisabledWhenBypassed() {
        configure(true);

        KenKaiChatController.KaiConfig config = KenKaiChatController.getConfig();

        System.assertEquals(false, config.enabled, 'Bypass must switch the feature off');
        System.assertEquals(null, config.apiKey, 'No key should leak when disabled');
    }

    @IsTest
    static void getConfigIsDisabledWhenUnconfigured() {
        KenKaiChatController.KaiConfig config = KenKaiChatController.getConfig();

        System.assertEquals(false, config.enabled, 'Blank settings must leave the widget unmounted');
    }

    @IsTest
    static void getUserSessionProvisionsThenMintsToken() {
        configure(false);
        KaiMock mock = new KaiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenKaiChatController.KaiSession session = KenKaiChatController.getUserSession();
        Test.stopTest();

        System.assertEquals(TOKEN, session.accessToken, 'Access token should come from the token response');
        System.assertEquals(UserInfo.getUserId(), session.externalId, 'External id is the portal User Id');
        System.assertEquals(2, mock.requests.size(), 'Exactly two KAI calls expected');
        HttpRequest provision = mock.requests[0];
        System.assert(provision.getEndpoint().endsWith('/users'), 'First call provisions the user');
        System.assertEquals(API_KEY, provision.getHeader('KAI-API-KEY'), 'API key header expected');
        Map<String, Object> identity = (Map<String, Object>) JSON.deserializeUntyped(provision.getBody());
        System.assertEquals(UserInfo.getUserId(), identity.get('externalId'), 'Identity keyed on the User Id');
        System.assertEquals(UserInfo.getName(), identity.get('name'), 'Name comes from the session');
        System.assert(mock.requests[1].getEndpoint().endsWith('/' + UserInfo.getUserId() + '/token'), 'Second call mints the token');
    }

    @IsTest
    static void getUserSessionIncludesSalesforceIdsInMeta() {
        configure(false);
        Id fakeRoleId = Id.valueOf(ConstituentRole.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA');
        Id fakeAccountId = Id.valueOf(Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA');
        KenConstituentRoleService.testCurrentRoleId = fakeRoleId;
        KenConstituentRoleService.testCurrentAccountId = fakeAccountId;
        KaiMock mock = new KaiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenKaiChatController.getUserSession();
        Test.stopTest();

        Map<String, Object> identity = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[0].getBody());
        Map<String, Object> meta = (Map<String, Object>) identity.get('meta');
        System.assertNotEquals(null, meta, 'meta should always be present');
        System.assertEquals(UserInfo.getUserId(), meta.get('salesforceUserId'), 'User id rides in meta');
        System.assertEquals(String.valueOf(fakeAccountId), meta.get('salesforceAccountId'), 'Person Account id rides in meta');
        System.assertEquals(String.valueOf(fakeRoleId), meta.get('alumniId'), 'Alumni role id rides in meta');
    }

    @IsTest
    static void getUserSessionOmitsAccountAndRoleWhenUserHasNone() {
        configure(false);
        KaiMock mock = new KaiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        KenKaiChatController.getUserSession();
        Test.stopTest();

        Map<String, Object> identity = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[0].getBody());
        Map<String, Object> meta = (Map<String, Object>) identity.get('meta');
        System.assertEquals(UserInfo.getUserId(), meta.get('salesforceUserId'), 'User id is always sent');
        System.assertEquals(false, meta.containsKey('salesforceAccountId'), 'No Person Account for an internal user');
        System.assertEquals(false, meta.containsKey('alumniId'), 'No alumni role for an internal user');
    }

    @IsTest
    static void getUserSessionFailsSafelyWhenProvisioningRejected() {
        configure(false);
        KaiMock mock = new KaiMock();
        mock.provisionStatus = 500;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Boolean threw = false;
        try {
            KenKaiChatController.getUserSession();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'A rejected provisioning call must surface as a handled exception');
        System.assertEquals(1, mock.requests.size(), 'Token call must not run after a failed provisioning');
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Logs__c WHERE Source__c = 'KenKaiChatController'], 'Failure should be logged');
    }

    @IsTest
    static void getUserSessionFailsSafelyWhenTokenMissing() {
        configure(false);
        KaiMock mock = new KaiMock();
        mock.tokenBody = '{"user_id":"kai-1","external_id":"x"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Boolean threw = false;
        try {
            KenKaiChatController.getUserSession();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'A token response without access_token must be rejected');
    }

    @IsTest
    static void getUserSessionRefusesWhenUnconfigured() {
        Boolean threw = false;
        try {
            KenKaiChatController.getUserSession();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'No configuration means no token handshake');
    }
}