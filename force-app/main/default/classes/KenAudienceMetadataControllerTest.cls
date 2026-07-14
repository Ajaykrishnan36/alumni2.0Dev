@IsTest
private class KenAudienceMetadataControllerTest {

    // Helper: asserts list not null and returns size
    private static Integer sizeOf(List<KenAudienceMetadataController.Option> opts) {
        System.assertNotEquals(null, opts, 'Options list should not be null');
        return opts.size();
    }

    @IsTest
    static void test_getRoleAttributeOptions_blankRole_returnsEmpty() {
        Test.startTest();
        Map<String, List<KenAudienceMetadataController.Option>> result1 =
            KenAudienceMetadataController.getRoleAttributeOptions(null);
        Map<String, List<KenAudienceMetadataController.Option>> result2 =
            KenAudienceMetadataController.getRoleAttributeOptions('');
        Map<String, List<KenAudienceMetadataController.Option>> result3 =
            KenAudienceMetadataController.getRoleAttributeOptions('   ');
        Test.stopTest();

        System.assertEquals(0, result1.size(), 'Null role should return empty map');
        System.assertEquals(0, result2.size(), 'Empty role should return empty map');
        System.assertEquals(0, result3.size(), 'Blank role should return empty map');
    }

    @IsTest
    static void test_getRoleAttributeOptions_student_and_normalization() {
        Test.startTest();
        // Mixed case + extra spaces to cover normalization
        Map<String, List<KenAudienceMetadataController.Option>> result =
            KenAudienceMetadataController.getRoleAttributeOptions('  sTuDeNt  ');
        Test.stopTest();

        System.assert(result.containsKey('academicYear'));
        System.assert(result.containsKey('program'));
        System.assert(result.containsKey('school'));
        System.assert(result.containsKey('department'));
        System.assert(result.containsKey('campus'));
        System.assert(result.containsKey('status'));

        System.assertEquals(3, sizeOf(result.get('academicYear')));
        System.assertEquals(4, sizeOf(result.get('program')));
        System.assertEquals(3, sizeOf(result.get('school')));
        System.assertEquals(4, sizeOf(result.get('department')));
        System.assertEquals(2, sizeOf(result.get('campus')));
        System.assertEquals(2, sizeOf(result.get('status')));

        // Spot check label/value behavior
        KenAudienceMetadataController.Option firstProgram = result.get('program')[0];
        System.assertNotEquals(null, firstProgram.label);
        System.assertNotEquals(null, firstProgram.value);
        System.assertEquals(firstProgram.label, firstProgram.value, 'Sample options use label=value');
    }

    @IsTest
    static void test_getRoleAttributeOptions_allOtherRoles() {
        Test.startTest();
        Map<String, List<KenAudienceMetadataController.Option>> alumni =
            KenAudienceMetadataController.getRoleAttributeOptions('ALUMNI');
        Map<String, List<KenAudienceMetadataController.Option>> parent =
            KenAudienceMetadataController.getRoleAttributeOptions('PARENT');
        Map<String, List<KenAudienceMetadataController.Option>> faculty =
            KenAudienceMetadataController.getRoleAttributeOptions('FACULTY');
        Map<String, List<KenAudienceMetadataController.Option>> staff =
            KenAudienceMetadataController.getRoleAttributeOptions('STAFF');
        Map<String, List<KenAudienceMetadataController.Option>> org =
            KenAudienceMetadataController.getRoleAttributeOptions('ORG');
        Map<String, List<KenAudienceMetadataController.Option>> others =
            KenAudienceMetadataController.getRoleAttributeOptions('OTHERS');
        Map<String, List<KenAudienceMetadataController.Option>> unknown =
            KenAudienceMetadataController.getRoleAttributeOptions('SOMETHING_ELSE');
        Test.stopTest();

        // Alumni
        System.assert(alumni.containsKey('graduationYear'));
        System.assertEquals(5, sizeOf(alumni.get('graduationYear')));
        System.assert(alumni.containsKey('degree'));
        System.assertEquals(5, sizeOf(alumni.get('degree')));
        System.assert(alumni.containsKey('status'));
        System.assertEquals(2, sizeOf(alumni.get('status')));

        // Parent
        System.assert(parent.containsKey('parentsOf'));
        System.assertEquals(2, sizeOf(parent.get('parentsOf')));
        System.assert(parent.containsKey('childGradYear'));
        System.assertEquals(3, sizeOf(parent.get('childGradYear')));

        // Faculty
        System.assert(faculty.containsKey('employmentType'));
        System.assertEquals(3, sizeOf(faculty.get('employmentType')));

        // Staff
        System.assert(staff.containsKey('department'));
        System.assertEquals(4, sizeOf(staff.get('department')));

        // Org
        System.assert(org.containsKey('university'));
        System.assertEquals(2, sizeOf(org.get('university')));
        System.assert(org.containsKey('program'));
        System.assertEquals(2, sizeOf(org.get('program')));

        // Others
        System.assert(others.containsKey('category'));
        System.assertEquals(3, sizeOf(others.get('category')));

        // Unknown role -> empty
        System.assertEquals(0, unknown.size(), 'Unknown role should return empty map');
    }

    @IsTest
    static void test_getPicklistValues_defensiveChecks_returnEmpty() {
        Test.startTest();
        // Blank params
        List<KenAudienceMetadataController.Option> r1 =
            KenAudienceMetadataController.getPicklistValues(null, 'Name');
        List<KenAudienceMetadataController.Option> r2 =
            KenAudienceMetadataController.getPicklistValues('Account', null);
        List<KenAudienceMetadataController.Option> r3 =
            KenAudienceMetadataController.getPicklistValues('   ', '   ');

        // Invalid object
        List<KenAudienceMetadataController.Option> r4 =
            KenAudienceMetadataController.getPicklistValues('NoSuchObject__c', 'NoField__c');

        // Valid object, invalid field
        List<KenAudienceMetadataController.Option> r5 =
            KenAudienceMetadataController.getPicklistValues('Account', 'NoSuchField__c');

        // Valid object + valid field but NOT a picklist type (e.g., Name is Text)
        List<KenAudienceMetadataController.Option> r6 =
            KenAudienceMetadataController.getPicklistValues('Account', 'Name');
        Test.stopTest();

        System.assertEquals(0, r1.size(), 'Null object should return empty list');
        System.assertEquals(0, r2.size(), 'Null field should return empty list');
        System.assertEquals(0, r3.size(), 'Blank inputs should return empty list');
        System.assertEquals(0, r4.size(), 'Invalid object should return empty list');
        System.assertEquals(0, r5.size(), 'Invalid field should return empty list');
        System.assertEquals(0, r6.size(), 'Non-picklist field should return empty list');
    }

    @IsTest
    static void test_getPicklistValues_onRealPicklist_whenAvailable() {
        // We try a couple of very common standard picklists.
        // If the org doesn't have them (rare), we simply skip assertions.
        Test.startTest();
        List<KenAudienceMetadataController.Option> industry =
            KenAudienceMetadataController.getPicklistValues('Account', 'Industry');
        List<KenAudienceMetadataController.Option> leadStatus =
            KenAudienceMetadataController.getPicklistValues('Lead', 'Status');
        Test.stopTest();

        // At least one of these usually exists as a picklist with values in most orgs.
        // If both are empty in your org (highly customized), add a custom picklist field
        // and point this test to it.
        if (!industry.isEmpty()) {
            System.assertNotEquals(null, industry[0].label);
            System.assertNotEquals(null, industry[0].value);
        }
        if (!leadStatus.isEmpty()) {
            System.assertNotEquals(null, leadStatus[0].label);
            System.assertNotEquals(null, leadStatus[0].value);
        }

        System.assert(
            !industry.isEmpty() || !leadStatus.isEmpty(),
            'Expected at least one standard picklist to have values. ' +
            'If your org has neither, update this test to use a known picklist field.'
        );
    }

    @IsTest
    static void test_saveAudienceSelection_and_deleteSavedGroup() {
        Test.startTest();
        // saveAudienceSelection
        System.assertEquals(false, KenAudienceMetadataController.saveAudienceSelection(null));
        System.assertEquals(false, KenAudienceMetadataController.saveAudienceSelection('   '));
        System.assertEquals(true, KenAudienceMetadataController.saveAudienceSelection('{"role":"STUDENT","filters":{}}'));

        // deleteSavedGroup
        System.assertEquals(false, KenAudienceMetadataController.deleteSavedGroup(null));
        System.assertEquals(false, KenAudienceMetadataController.deleteSavedGroup(''));
        System.assertEquals(true, KenAudienceMetadataController.deleteSavedGroup('a0123456789ABCDE'));
        Test.stopTest();
    }

    @IsTest
    static void test_option_ctor_setsFields() {
        KenAudienceMetadataController.Option o =
            new KenAudienceMetadataController.Option('My Label', 'My Value');

        System.assertEquals('My Label', o.label);
        System.assertEquals('My Value', o.value);
    }
}