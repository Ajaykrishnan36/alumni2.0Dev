@IsTest
private class KenConstituentRoleTriggerHandlerTest {

    // ---------- Picklist helpers (restricted picklists safe) ----------

    private static String pickValue(Schema.SObjectType sObjType, String fieldApiName, List<String> preferred) {
        Schema.DescribeFieldResult dfr =
            sObjType.getDescribe().fields.getMap().get(KenNamespaceUtil.qualifyCustom(fieldApiName)).getDescribe();

        List<Schema.PicklistEntry> entries = dfr.getPicklistValues();
        Set<String> active = new Set<String>();
        for (Schema.PicklistEntry e : entries) {
            if (e.isActive()) active.add(e.getValue());
        }

        for (String p : preferred) {
            if (active.contains(p)) return p;
        }

        for (Schema.PicklistEntry e : entries) {
            if (e.isActive()) return e.getValue();
        }
        return null;
    }

    private static String pickDifferentValue(Schema.SObjectType sObjType, String fieldApiName, String currentValue) {
        Schema.DescribeFieldResult dfr =
            sObjType.getDescribe().fields.getMap().get(KenNamespaceUtil.qualifyCustom(fieldApiName)).getDescribe();

        for (Schema.PicklistEntry e : dfr.getPicklistValues()) {
            if (e.isActive() && e.getValue() != currentValue) return e.getValue();
        }
        return currentValue;
    }

    // ---------- Data helpers ----------

    private static Account createPersonAccount() {
        // Pick a person-account record type the RUNNING USER can actually use.
        // Querying RecordType returns every one in the org, including ones this
        // profile has no access to, which fails the insert with
        // INVALID_CROSS_REFERENCE_KEY.
        Set<Id> personTypeIds = new Set<Id>();
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true
        ]) {
            personTypeIds.add(rt.Id);
        }
        Id paRtId;
        for (Schema.RecordTypeInfo info : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (info.isAvailable() && !info.isMaster() && personTypeIds.contains(info.getRecordTypeId())) {
                paRtId = info.getRecordTypeId();
                break;
            }
        }

        Account pa = new Account();
        if (paRtId != null) pa.RecordTypeId = paRtId;

        pa.LastName = 'Test';
        pa.PersonEmail = 'test+' + String.valueOf(Crypto.getRandomInteger()) + '@example.com';
        insert pa;
        return pa;
    }

    private static ConstituentRole createConstituentRole(Id personAccountId, String registrationStatus) {
        ConstituentRole cr = new ConstituentRole();

        // Required fields in your org
        cr.PersonId = personAccountId;

        cr.RoleType = pickValue(
            ConstituentRole.SObjectType,
            'RoleType',
            new List<String>{ 'Alumni', 'Student', 'Constituent' }
        );

        cr.Status = pickValue(
            ConstituentRole.SObjectType,
            'Status',
            new List<String>{ 'Admitted', 'Active' }
        );

        cr.Registration_Status__c = (registrationStatus != null)
            ? registrationStatus
            : pickValue(
                ConstituentRole.SObjectType,
                'Registration_Status__c',
                new List<String>{ 'Unregistered' }
              );

        insert cr;
        return cr;
    }



    @IsTest
    static void test_registrationUnchanged_skips_byChangingOtherField() {
        Account pa = createPersonAccount();

        String startVal = pickValue(
            ConstituentRole.SObjectType,
            'Registration_Status__c',
            new List<String>{ 'Unregistered' }
        );

        ConstituentRole cr = createConstituentRole(pa.Id, startVal);

        // Force update while keeping registration status unchanged
        String newStatus = pickDifferentValue(
            ConstituentRole.SObjectType,
            'Status',
            cr.Status
        );

        Test.startTest();
        cr.Status = newStatus;
        update cr;
        Test.stopTest();
    }

    @IsTest
    static void test_nonVerifiedTransition_skips() {
        Account pa = createPersonAccount();

        String startVal = pickValue(
            ConstituentRole.SObjectType,
            'Registration_Status__c',
            new List<String>{ 'Unregistered' }
        );

        String verified = pickValue(
            ConstituentRole.SObjectType,
            'Registration_Status__c',
            new List<String>{ 'Onboarding In Progress' }
        );

        // choose a value that is NOT Verified (if possible)
        String nonVerified = pickDifferentValue(
            ConstituentRole.SObjectType,
            'Registration_Status__c',
            verified
        );

        ConstituentRole cr = createConstituentRole(pa.Id, startVal);

        Test.startTest();
        cr.Registration_Status__c = nonVerified;
        update cr;
        Test.stopTest();
    }

    @IsTest
    static void test_blankRegistrationStatus_skips_ifAllowed() {
        Account pa = createPersonAccount();

        String startVal = pickValue(
            ConstituentRole.SObjectType,
            'Registration_Status__c',
            new List<String>{ 'Unregistered' }
        );

        ConstituentRole cr = createConstituentRole(pa.Id, startVal);

        Test.startTest();
        // If null is not allowed in your org, delete this test method.
        cr.Registration_Status__c = null;
        update cr;
        Test.stopTest();
    }
}