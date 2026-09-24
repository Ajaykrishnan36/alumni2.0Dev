/**
 * @description Portal-side gate for the KAI alumni chatbot.
 *
 *              Two experiences share one browser SDK. Guests get the public agent with no user
 *              token; logged-in alumni get the authenticated agent with a short-lived KAI user
 *              token that the portal mints here, server-side, by provisioning the alumnus's KAI
 *              identity and then requesting a token for it. The browser never calls KAI's user
 *              endpoints and never supplies the identity mapping.
 *
 *              Resolution order, highest priority first:
 *                1. Bypass. `Ken_Alm_Module_Settings__c.Skip_KAI_Chat__c` switches the whole
 *                   feature off and is evaluated in exactly one place, `isBypassed()`.
 *                2. Endpoint. `KAI_Chat_Connection__c` says where KAI lives. With none
 *                   configured, or with no API key, agent id or SDK URL, the widget never
 *                   mounts.
 *
 *              The host lives in the Named Credential; the API key, the agent ids and the
 *              browser SDK URL live in the custom setting. The SDK is loaded from that URL at
 *              runtime by the bridge script in the site head markup, so a KAI release reaches
 *              the portal without a deploy. The API key is a publishable client key by KAI's design — the
 *              browser SDK sends it as a header — so it is returned to the widget as-is. The
 *              per-user access token is what authenticates an alumnus, and nothing here logs a
 *              token, the key or the identity mapping.
 *
 * @author  Surya
 */
public without sharing class KenKaiChatController {

    private static final String USERS_PATH = '/users';
    private static final String AUTH_PATH_SUFFIX = '/token';
    private static final String KAI_HEADER_NAME = 'KAI-API-KEY';
    private static final Integer TIMEOUT_MS = 10000;
    private static final Set<Integer> ACCEPTED = new Set<Integer>{ 200, 201 };

    private static final String GUEST_USER_TYPE = 'Guest';
    private static final String UNAVAILABLE_MESSAGE = 'Alumni chat is temporarily unavailable';

    private static final String LOG_PROCESS = 'KAI Chat Token';
    private static final String LOG_SOURCE = 'KenKaiChatController';

    /** Everything the widget needs to mount, for the calling user's audience. */
    public class KaiConfig {
        @AuraEnabled public Boolean enabled { get; set; }
        @AuraEnabled public Boolean isGuest { get; set; }
        @AuraEnabled public String apiKey { get; set; }
        @AuraEnabled public String agentId { get; set; }
        @AuraEnabled public String baseUrl { get; set; }
        @AuraEnabled public String sdkUrl { get; set; }
    }

    /** The two values the browser is allowed to see from the token handshake. */
    public class KaiSession {
        @AuraEnabled public String accessToken { get; set; }
        @AuraEnabled public String externalId { get; set; }
    }

    /**
     * @description Widget configuration for the calling user. Guests are told to mount the
     *              public agent, everyone else the authenticated one. `enabled` is false when
     *              the feature is bypassed or any required setting is blank, and the widget
     *              then never loads the SDK.
     *
     * @return KaiConfig; never null.
     */
    @AuraEnabled(cacheable=true)
    public static KaiConfig getConfig() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        KaiConfig config = new KaiConfig();
        config.isGuest = isGuest();
        config.enabled = false;
        if (isBypassed() || String.isBlank(params.KAI_Chat_Connection__c)) {
            return config;
        }
        String agentId = config.isGuest ? params.KAI_Anonymous_Agent_Id__c : params.KAI_Verified_Agent_Id__c;
        if (String.isBlank(params.KAI_Client_Id__c) || String.isBlank(agentId) || String.isBlank(params.KAI_SDK_URL__c)) {
            return config;
        }
        config.enabled = true;
        config.apiKey = params.KAI_Client_Id__c.trim();
        config.agentId = agentId.trim();
        config.sdkUrl = params.KAI_SDK_URL__c.trim();
        return config;
    }

    /**
     * @description Provisions the logged-in alumnus in KAI and mints a short-lived user token
     *              for the authenticated agent. Provisioning is idempotent on KAI's side, so it
     *              runs on every call and keeps name, email and phone current. Guests are
     *              refused before any callout.
     *
     * @return KaiSession with the access token and the stable external id.
     */
    @AuraEnabled
    public static KaiSession getUserSession() {
        if (isGuest()) {
            throw new AuraHandledException(UNAVAILABLE_MESSAGE);
        }
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        if (isBypassed()
            || String.isBlank(params.KAI_Chat_Connection__c)
            || String.isBlank(params.KAI_Client_Id__c)) {
            throw new AuraHandledException(UNAVAILABLE_MESSAGE);
        }
        String base = 'callout:' + params.KAI_Chat_Connection__c.trim();
        String apiKey = params.KAI_Client_Id__c.trim();
        String externalId = UserInfo.getUserId();
        try {
            HttpResponse provisioned = post(base + USERS_PATH, apiKey, JSON.serialize(buildIdentity(externalId)));
            if (!ACCEPTED.contains(provisioned.getStatusCode())) {
                throw new KaiCalloutException('KAI provisioning failed: ' + provisioned.getStatusCode());
            }
            HttpResponse minted = post(
                base + USERS_PATH + '/' + EncodingUtil.urlEncode(externalId, 'UTF-8') + AUTH_PATH_SUFFIX,
                apiKey,
                '{}'
            );
            if (!ACCEPTED.contains(minted.getStatusCode())) {
                throw new KaiCalloutException('KAI token request failed: ' + minted.getStatusCode());
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(minted.getBody());
            KaiSession session = new KaiSession();
            session.accessToken = (String) body.get('access_token');
            String returnedId = (String) body.get('external_id');
            session.externalId = String.isNotBlank(returnedId) ? returnedId : externalId;
            if (String.isBlank(session.accessToken)) {
                throw new KaiCalloutException('KAI token response carried no access token');
            }
            return session;
        } catch (Exception e) {
            KenLogService.log(
                KenLogService.CATEGORY_INTEGRATION,
                KenLogService.TYPE_ERROR,
                LOG_PROCESS,
                LOG_SOURCE,
                externalId,
                e.getMessage(),
                e.getStackTraceString()
            );
            throw new AuraHandledException(UNAVAILABLE_MESSAGE);
        }
    }

    /**
     * @description The identity KAI keys the alumnus on. `externalId` is the portal User Id,
     *              which survives email and phone changes. `meta` carries the Salesforce ids a
     *              permission-aware connector needs — the User, the Person Account and the
     *              alumni ConstituentRole — the same shape the Admissions KAI integration sends.
     */
    private static Map<String, Object> buildIdentity(String externalId) {
        Map<String, Object> identity = new Map<String, Object>{
            'externalId' => externalId,
            'name' => UserInfo.getName(),
            'email' => UserInfo.getUserEmail()
        };
        Id accountId = KenConstituentRoleService.getCurrentUserAccountId();
        String phone = currentUserPhone(accountId);
        if (String.isNotBlank(phone)) {
            identity.put('phone', phone);
        }
        Map<String, Object> meta = new Map<String, Object>{ 'salesforceUserId' => externalId };
        if (accountId != null) {
            meta.put('salesforceAccountId', String.valueOf(accountId));
        }
        Id roleId = KenConstituentRoleService.getActiveConstituentRoleId();
        if (roleId != null) {
            meta.put('alumniId', String.valueOf(roleId));
        }
        identity.put('meta', meta);
        return identity;
    }

    private static String currentUserPhone(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<Account> accounts = [
            SELECT PersonMobilePhone, Phone
            FROM Account
            WHERE Id = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return null;
        }
        return String.isNotBlank(accounts[0].PersonMobilePhone) ? accounts[0].PersonMobilePhone : accounts[0].Phone;
    }

    private static HttpResponse post(String endpoint, String apiKey, String body) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(TIMEOUT_MS);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader(KAI_HEADER_NAME, apiKey);
        request.setBody(body);
        return new Http().send(request);
    }

    private static Boolean isBypassed() {
        Ken_Alm_Module_Settings__c modules = Ken_Alm_Module_Settings__c.getOrgDefaults();
        return modules != null && modules.Skip_KAI_Chat__c == true;
    }

    private static Boolean isGuest() {
        return UserInfo.getUserType() == GUEST_USER_TYPE;
    }

    public class KaiCalloutException extends Exception {}
}