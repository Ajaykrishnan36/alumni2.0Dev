public without sharing class LinkedInUserInfoProxyController {
    public String body { get; private set; }

    public LinkedInUserInfoProxyController() {
        PageReference pr = ApexPages.currentPage();
        Map<String, String> params  = pr.getParameters();
        Map<String, String> headers = pr.getHeaders();

        // Find the token wherever Salesforce put it
        String token = params.get('access_token');
        String source = 'query';
        if (String.isBlank(token)) {
            String auth = headers.get('Authorization');
            if (String.isBlank(auth)) auth = headers.get('authorization');
            if (String.isNotBlank(auth)) {
                token = auth.replaceFirst('(?i)bearer\\s+', '');
                source = 'header';
            }
        }

        if (String.isBlank(token)) {
            body = JSON.serialize(new Map<String, Object>{ 'error' => 'no_token' });
            return;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.linkedin.com/v2/userinfo');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setTimeout(20000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            body = JSON.serialize(new Map<String, Object>{ 'error' => e.getMessage() });
            return;
        }

        Map<String, Object> raw =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        Map<String, Object> clean = new Map<String, Object>();
        clean.put('sub',         raw.get('sub'));
        clean.put('name',        raw.get('name'));
        clean.put('given_name',  raw.get('given_name'));
        clean.put('family_name', raw.get('family_name'));
        clean.put('email',       raw.get('email'));
        clean.put('picture',     raw.get('picture'));
        Object ev = raw.get('email_verified');
        clean.put('email_verified',
            ev instanceof String ? String.valueOf(ev).equalsIgnoreCase('true') : ev);
        if (raw.get('locale') instanceof Map<String, Object>) {
            Map<String, Object> lm = (Map<String, Object>) raw.get('locale');
            if (lm.get('language') != null && lm.get('country') != null) {
                clean.put('locale',
                    String.valueOf(lm.get('language')) + '-' + String.valueOf(lm.get('country')));
            }
        }

        body = JSON.serialize(clean);
    }
}