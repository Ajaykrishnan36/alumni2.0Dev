/**
 * @description Normalizing UserInfo proxy for the LinkedIn OIDC Auth Provider. LinkedIn's
 *              /v2/userinfo is spec-non-compliant (email_verified as a String, locale as an
 *              object); Salesforce's OIDC parser is strict. This controller calls LinkedIn,
 *              whitelists clean claims, and converts email_verified -> Boolean and
 *              locale -> "en-US" so the Auth Provider can consume it. Served as raw JSON via
 *              the KenLinkedInUserInfoProxy Visualforce page.
 */
public without sharing class KenLinkedInUserInfoProxyController {
    public String body { get; private set; }

    /**
     * @description Forwards the END USER'S own OAuth token, handed in by the Auth Provider
     *              part way through login, to LinkedIn's userinfo endpoint. No Named
     *              Credential can carry it because no Salesforce user exists yet, so it
     *              travels as LinkedIn's oauth2_access_token query parameter, which LinkedIn
     *              accepts in place of a Bearer header. The Auth Provider already delivers
     *              the token to this page in the query string.
     */
    public KenLinkedInUserInfoProxyController() {
        PageReference pr = ApexPages.currentPage();
        Map<String, String> params = pr.getParameters();
        Map<String, String> headers = pr.getHeaders();

        String token = params.get('access_token');
        String source = 'query';
        if (String.isBlank(token)) {
            String auth = headers.get('Authorization');
            if (String.isBlank(auth)) {
                auth = headers.get('authorization');
            }
            if (String.isNotBlank(auth)) {
                token = auth.replaceFirst('(?i)bearer\\s+', '');
                source = 'header';
            }
        }

        if (String.isBlank(token)) {
            System.debug('### LIPROXY NO TOKEN RECEIVED');
            body = JSON.serialize(new Map<String, Object>{ 'error' => 'no_token' });
            return;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'https://api.linkedin.com/v2/userinfo?oauth2_access_token=' + EncodingUtil.urlEncode(token, 'UTF-8')
        );
        req.setMethod('GET');
        req.setTimeout(20000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            body = JSON.serialize(new Map<String, Object>{ 'error' => e.getMessage() });
            return;
        }

        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        Map<String, Object> clean = new Map<String, Object>();
        clean.put('sub', raw.get('sub'));
        clean.put('name', raw.get('name'));
        clean.put('given_name', raw.get('given_name'));
        clean.put('family_name', raw.get('family_name'));
        clean.put('email', raw.get('email'));
        clean.put('picture', raw.get('picture'));

        Object ev = raw.get('email_verified');
        clean.put('email_verified', ev instanceof String ? String.valueOf(ev).equalsIgnoreCase('true') : ev);

        if (raw.get('locale') instanceof Map<String, Object>) {
            Map<String, Object> lm = (Map<String, Object>) raw.get('locale');
            if (lm.get('language') != null && lm.get('country') != null) {
                clean.put('locale', String.valueOf(lm.get('language')) + '-' + String.valueOf(lm.get('country')));
            }
        }

        body = JSON.serialize(clean);
    }
}