@isTest
private class KenAlumniPreferencesControllerTest {

    private static Id makeAccount() {
        Account a = new Account(Name = 'Pref Tester');
        insert a;
        return a.Id;
    }

    @isTest
    static void savesAndReadsBackPreferences_unlimited() {
        Id acc = makeAccount();
        KenAlumniPreferencesController.testAccountId = acc;

        KenAlumniPreferencesController.PreferencesDTO dto = new KenAlumniPreferencesController.PreferencesDTO();
        dto.willingToMentor = true;
        dto.availabilityDays = 'Monday;Wednesday';
        dto.availabilityStart = '09:30';
        dto.availabilityEnd = '17:00';
        dto.menteeTypes = 'Students;Recent Graduates';
        dto.unlimitedCapacity = true;
        dto.maxCapacity = 7;  // should be ignored/nulled when unlimited

        Test.startTest();
        Id prefId = KenAlumniPreferencesController.savePreferences(dto);
        Test.stopTest();

        System.assertNotEquals(null, prefId, 'preference record created');
        Ken_Alumni_Preferences__c rec = [
            SELECT Willing_to_be_a_mentor__c, Mentorship_Availability_Days__c,
                   Mentorship_Availability_Start_Time__c, Mentorship_Availability_End_Time__c,
                   Mentee_Type_Preference__c, Mentorship_Unlimited_Capacity__c, Mentorship_Max_Capacity__c
            FROM Ken_Alumni_Preferences__c WHERE Id = :prefId];
        System.assertEquals(true, rec.Willing_to_be_a_mentor__c);
        System.assertEquals('Monday;Wednesday', rec.Mentorship_Availability_Days__c);
        System.assertEquals(Time.newInstance(9, 30, 0, 0), rec.Mentorship_Availability_Start_Time__c);
        System.assertEquals(true, rec.Mentorship_Unlimited_Capacity__c);
        System.assertEquals(null, rec.Mentorship_Max_Capacity__c, 'capacity nulled when unlimited');

        // read-back roundtrip, including HH:mm formatting
        KenAlumniPreferencesController.PreferencesDTO got = KenAlumniPreferencesController.getMyPreferences();
        System.assertEquals(prefId, got.id);
        System.assertEquals('09:30', got.availabilityStart, 'start time formatted HH:mm');
        System.assertEquals('17:00', got.availabilityEnd);
        System.assertEquals(true, got.willingToMentor);
        System.assertEquals(true, got.unlimitedCapacity);
    }

    @isTest
    static void updatesExistingPreference_finiteCapacity() {
        Id acc = makeAccount();
        KenAlumniPreferencesController.testAccountId = acc;
        // seed
        insert new Ken_Alumni_Preferences__c(Person_Account__c = acc, Willing_to_be_a_mentor__c = false);

        KenAlumniPreferencesController.PreferencesDTO dto = new KenAlumniPreferencesController.PreferencesDTO();
        dto.willingToMentor = true;
        dto.expertiseAreas = 'Project Management;Development';
        dto.communicationModes = 'Email;Whatsapp';
        dto.unlimitedCapacity = false;
        dto.maxCapacity = 3;

        Test.startTest();
        Id prefId = KenAlumniPreferencesController.savePreferences(dto);
        Test.stopTest();

        Ken_Alumni_Preferences__c rec = [
            SELECT Mentorship_Max_Capacity__c, Mentorship_Unlimited_Capacity__c,
                   Mentorship_Preferred_Communication_Modes__c
            FROM Ken_Alumni_Preferences__c WHERE Id = :prefId];
        System.assertEquals(3, rec.Mentorship_Max_Capacity__c, 'finite capacity persisted');
        System.assertEquals(false, rec.Mentorship_Unlimited_Capacity__c);
        // upsert reused the existing row, not a 2nd one
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Alumni_Preferences__c WHERE Person_Account__c = :acc]);
    }

    @isTest
    static void getReturnsEmptyWhenNoAccount() {
        // No testAccountId set + running as admin (no AccountId) -> null account
        KenAlumniPreferencesController.PreferencesDTO got = KenAlumniPreferencesController.getMyPreferences();
        System.assertEquals(null, got.id, 'empty dto when no account');
    }

    @isTest
    static void saveThrowsWhenNoAccountOrNullDto() {
        Boolean t1 = false, t2 = false;
        try { KenAlumniPreferencesController.savePreferences(null); } catch (AuraHandledException e) { t1 = true; }
        try {
            KenAlumniPreferencesController.savePreferences(new KenAlumniPreferencesController.PreferencesDTO());
        } catch (AuraHandledException e) { t2 = true; }
        System.assert(t1, 'null payload throws');
        System.assert(t2, 'no account throws');
    }
}