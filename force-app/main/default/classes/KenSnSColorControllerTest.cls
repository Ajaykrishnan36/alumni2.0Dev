@IsTest
private class KenSnSColorControllerTest {

    private static final String CONFIGURED_PRIMARY = '#FF6600';
    private static final String CONFIGURED_SECONDARY = 'FFE8D9';        // no '#' — must be normalized
    private static final String INVALID_HEX = '#NOTAHEX';
    private static final String SHORT_HEX = '#FFF';                     // 3-digit, regex requires 6

    private static Ken_Support_Services_Parameters__c upsertOrgDefaults(String primary, String secondary) {
        Ken_Support_Services_Parameters__c setting = Ken_Support_Services_Parameters__c.getOrgDefaults();
        if (setting == null || setting.Id == null) {
            setting = new Ken_Support_Services_Parameters__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Primary_Color__c = primary,
                Secondary_Color__c = secondary
            );
            insert setting;
        } else {
            setting.Primary_Color__c = primary;
            setting.Secondary_Color__c = secondary;
            update setting;
        }
        return setting;
    }

    /**
     * Happy path: configured primary returned verbatim, secondary without '#'
     * gets normalized to a '#'-prefixed value.
     */
    @IsTest
    static void getColors_returnsConfiguredValues() {
        upsertOrgDefaults(CONFIGURED_PRIMARY, CONFIGURED_SECONDARY);

        Test.startTest();
        KenSnSColorController.ColorResponse result = KenSnSColorController.getColors();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Response should not be null.');
        System.assertEquals(CONFIGURED_PRIMARY, result.primary, 'Configured primary should be returned.');
        System.assertEquals('#' + CONFIGURED_SECONDARY, result.secondary,
            'Secondary without # should be normalized to start with #.');
    }

    /**
     * No org-default record exists — both colors should be null so the LWC
     * can fall back to CSS-level defaults.
     */
    @IsTest
    static void getColors_returnsNullWhenSettingMissing() {
        Test.startTest();
        KenSnSColorController.ColorResponse result = KenSnSColorController.getColors();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Response wrapper itself should not be null.');
        System.assertEquals(null, result.primary,
            'Primary should be null when no custom-setting record exists.');
        System.assertEquals(null, result.secondary,
            'Secondary should be null when no custom-setting record exists.');
    }

    /**
     * Setting record exists but fields are blank — should also return null.
     */
    @IsTest
    static void getColors_returnsNullWhenFieldsBlank() {
        upsertOrgDefaults(null, '   ');

        Test.startTest();
        KenSnSColorController.ColorResponse result = KenSnSColorController.getColors();
        Test.stopTest();

        System.assertEquals(null, result.primary, 'Blank primary should yield null.');
        System.assertEquals(null, result.secondary, 'Whitespace secondary should yield null.');
    }

    /**
     * Invalid hex strings — should yield null (no fallback color).
     */
    @IsTest
    static void getColors_returnsNullOnInvalidHex() {
        upsertOrgDefaults(INVALID_HEX, SHORT_HEX);

        Test.startTest();
        KenSnSColorController.ColorResponse result = KenSnSColorController.getColors();
        Test.stopTest();

        System.assertEquals(null, result.primary, 'Non-hex string should yield null.');
        System.assertEquals(null, result.secondary, '3-digit hex should yield null (regex requires 6).');
    }

    /**
     * Setting has '#'-prefixed values with whitespace — must be trimmed.
     */
    @IsTest
    static void getColors_normalizesTrimmedHexValues() {
        upsertOrgDefaults('  #AABBCC  ', '#001122');

        Test.startTest();
        KenSnSColorController.ColorResponse result = KenSnSColorController.getColors();
        Test.stopTest();

        System.assertEquals('#AABBCC', result.primary, 'Whitespace around hex should be trimmed.');
        System.assertEquals('#001122', result.secondary);
    }

    /**
     * forceExceptionForTesting toggle — exercises the early throw and
     * documents that the wire adapter will surface the error to the LWC.
     */
    @IsTest
    static void getColors_throwsWhenForcedForTesting() {
        KenSnSColorController.forceExceptionForTesting = true;

        Boolean threw = false;
        Test.startTest();
        try {
            KenSnSColorController.getColors();
        } catch (IllegalArgumentException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('Test exception'),
                'Forced exception message should propagate.'
            );
        }
        Test.stopTest();

        System.assert(threw, 'Force-exception flag must cause an exception.');
        KenSnSColorController.forceExceptionForTesting = false;
    }

    /**
     * Combined branch coverage smoke test — single test that exercises the
     * happy path and asserts the response shape (primary/secondary present).
     */
    @IsTest
    static void getColors_responseShapeIsCorrect() {
        upsertOrgDefaults(CONFIGURED_PRIMARY, '#123456');

        Test.startTest();
        KenSnSColorController.ColorResponse result = KenSnSColorController.getColors();
        Test.stopTest();

        System.assertNotEquals(null, result.primary, 'Primary field must be populated.');
        System.assertNotEquals(null, result.secondary, 'Secondary field must be populated.');
        System.assertEquals(CONFIGURED_PRIMARY, result.primary);
        System.assertEquals('#123456', result.secondary);
    }
}