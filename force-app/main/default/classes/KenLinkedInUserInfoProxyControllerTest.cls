/**
 * @description Tests for KenLinkedInUserInfoProxyController — the normalizing UserInfo proxy
 *              the LinkedIn OIDC Auth Provider points at. Verifies LinkedIn's non-compliant
 *              claims are corrected: email_verified (string "true") -> Boolean, and locale
 *              (object {language,country}) -> "en-US". Also covers missing-token and
 *              callout-failure branches.
 */
@IsTest
private class KenLinkedInUserInfoProxyControllerTest {
    private class NonCompliantUserInfoMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assertEquals(
                'https://api.linkedin.com/v2/userinfo',
                req.getEndpoint(),
                'Proxy must call LinkedIn userinfo endpoint.'
            );
            System.assertEquals(
                true,
                req.getHeader('Authorization').startsWithIgnoreCase('Bearer '),
                'Proxy must forward the bearer token to LinkedIn.'
            );
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                '"sub":"zh8FbUco0X",' +
                '"name":"Ada Lovelace",' +
                '"given_name":"Ada",' +
                '"family_name":"Lovelace",' +
                '"email":"ada@example.com",' +
                '"picture":"https://media.linkedin.com/ada.jpg",' +
                '"email_verified":"true",' +
                '"locale":{"language":"en","country":"US"}' +
                '}'
            );
            return res;
        }
    }

    private class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated LinkedIn outage');
        }
    }

    @IsTest
    static void normalizesNonCompliantClaims() {
        Test.setMock(HttpCalloutMock.class, new NonCompliantUserInfoMock());
        Test.setCurrentPage(Page.KenLinkedInUserInfoProxy);
        ApexPages.currentPage().getParameters().put('access_token', 'fake-access-token');

        Test.startTest();
        KenLinkedInUserInfoProxyController ctrl = new KenLinkedInUserInfoProxyController();
        Test.stopTest();

        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(ctrl.body);
        System.assertEquals('zh8FbUco0X', out.get('sub'), 'sub should pass through unchanged.');
        System.assertEquals('ada@example.com', out.get('email'), 'email should pass through.');
        System.assertEquals(
            true,
            out.get('email_verified') instanceof Boolean,
            'email_verified must be a Boolean, not the String LinkedIn sends.'
        );
        System.assertEquals(
            true,
            (Boolean) out.get('email_verified'),
            'email_verified string "true" must normalize to boolean true.'
        );
        System.assertEquals(
            'en-US',
            out.get('locale'),
            'locale object {language,country} must be flattened to "en-US".'
        );
    }

    @IsTest
    static void returnsErrorWhenNoToken() {
        Test.setCurrentPage(Page.KenLinkedInUserInfoProxy);

        Test.startTest();
        KenLinkedInUserInfoProxyController ctrl = new KenLinkedInUserInfoProxyController();
        Test.stopTest();

        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(ctrl.body);
        System.assertEquals('no_token', out.get('error'), 'Missing token should produce a no_token error.');
    }

    @IsTest
    static void returnsErrorWhenCalloutFails() {
        Test.setMock(HttpCalloutMock.class, new ThrowingMock());
        Test.setCurrentPage(Page.KenLinkedInUserInfoProxy);
        ApexPages.currentPage().getParameters().put('access_token', 'fake-access-token');

        Test.startTest();
        KenLinkedInUserInfoProxyController ctrl = new KenLinkedInUserInfoProxyController();
        Test.stopTest();

        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(ctrl.body);
        System.assertNotEquals(null, out.get('error'), 'A callout failure should be surfaced as an error payload.');
    }
}