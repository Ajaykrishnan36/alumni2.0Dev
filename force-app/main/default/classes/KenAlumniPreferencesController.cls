/**
 * Mentorship v2.0 — Epic 2: Preferences & Availability Engine.
 *
 * Flat-model read/upsert of the running alum's mentorship preferences on
 * Ken_Alumni_Preferences__c (one record per Person Account): recurring availability
 * (days + single time window), expertise, communication modes, mentee-type preference,
 * and max capacity / unlimited toggle.
 *
 * `without sharing` so a community alum manages their own preferences regardless of OWD.
 */
public without sharing class KenAlumniPreferencesController {

    @TestVisible private static Id testAccountId; // test seam — avoids provisioning a portal user

    public class PreferencesDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Boolean willingToMentor;
        @AuraEnabled public String availabilityDays;       // ';'-joined multiselect
        @AuraEnabled public String availabilityStart;      // 'HH:mm'
        @AuraEnabled public String availabilityEnd;        // 'HH:mm'
        @AuraEnabled public String expertiseAreas;         // ';'-joined multiselect
        @AuraEnabled public String communicationModes;     // ';'-joined multiselect
        @AuraEnabled public String menteeTypes;            // ';'-joined multiselect
        @AuraEnabled public Decimal maxCapacity;
        @AuraEnabled public Boolean unlimitedCapacity;
    }

    @AuraEnabled(cacheable=true)
    public static PreferencesDTO getMyPreferences() {
        PreferencesDTO dto = new PreferencesDTO();
        Id acc = currentAccountId();
        if (acc == null) return dto;
        List<Ken_Alumni_Preferences__c> recs = [
            SELECT Id, Willing_to_be_a_mentor__c, Mentorship_Availability_Days__c,
                   Mentorship_Availability_Start_Time__c, Mentorship_Availability_End_Time__c,
                   Mentorship_Expertise_Areas__c, Mentorship_Preferred_Communication_Modes__c,
                   Mentee_Type_Preference__c, Mentorship_Max_Capacity__c, Mentorship_Unlimited_Capacity__c
            FROM Ken_Alumni_Preferences__c WHERE Person_Account__c = :acc LIMIT 1];
        if (recs.isEmpty()) return dto;
        Ken_Alumni_Preferences__c p = recs[0];
        dto.id = p.Id;
        dto.willingToMentor = p.Willing_to_be_a_mentor__c;
        dto.availabilityDays = p.Mentorship_Availability_Days__c;
        dto.availabilityStart = fmtTime(p.Mentorship_Availability_Start_Time__c);
        dto.availabilityEnd = fmtTime(p.Mentorship_Availability_End_Time__c);
        dto.expertiseAreas = p.Mentorship_Expertise_Areas__c;
        dto.communicationModes = p.Mentorship_Preferred_Communication_Modes__c;
        dto.menteeTypes = p.Mentee_Type_Preference__c;
        dto.maxCapacity = p.Mentorship_Max_Capacity__c;
        dto.unlimitedCapacity = p.Mentorship_Unlimited_Capacity__c;
        return dto;
    }

    @AuraEnabled
    public static Id savePreferences(PreferencesDTO dto) {
        if (dto == null) throw new AuraHandledException('Preferences payload is required.');
        Id acc = currentAccountId();
        if (acc == null) throw new AuraHandledException('Unable to determine current user.');
        try {
            List<Ken_Alumni_Preferences__c> existing = [
                SELECT Id FROM Ken_Alumni_Preferences__c WHERE Person_Account__c = :acc LIMIT 1];
            Ken_Alumni_Preferences__c pref = existing.isEmpty()
                ? new Ken_Alumni_Preferences__c(Person_Account__c = acc)
                : existing[0];
            pref.Willing_to_be_a_mentor__c = dto.willingToMentor == true;
            pref.Mentorship_Availability_Days__c = dto.availabilityDays;
            pref.Mentorship_Availability_Start_Time__c = parseClockTime(dto.availabilityStart);
            pref.Mentorship_Availability_End_Time__c = parseClockTime(dto.availabilityEnd);
            pref.Mentorship_Expertise_Areas__c = dto.expertiseAreas;
            pref.Mentorship_Preferred_Communication_Modes__c = dto.communicationModes;
            pref.Mentee_Type_Preference__c = dto.menteeTypes;
            pref.Mentorship_Unlimited_Capacity__c = dto.unlimitedCapacity == true;
            // When "Unlimited" is on, the numeric capacity is irrelevant — null it out.
            pref.Mentorship_Max_Capacity__c = (dto.unlimitedCapacity == true) ? null : dto.maxCapacity;
            upsert pref;
            return pref.Id;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Could not save your preferences: ' + e.getMessage());
        }
    }

    // ---- helpers ----
    @TestVisible
    private static String fmtTime(Time t) {
        if (t == null) return null;
        String hh = (t.hour() < 10 ? '0' : '') + String.valueOf(t.hour());
        String mm = (t.minute() < 10 ? '0' : '') + String.valueOf(t.minute());
        return hh + ':' + mm;
    }
    @TestVisible
    private static Time parseClockTime(String hhmm) {
        if (String.isBlank(hhmm)) return null;
        List<String> parts = hhmm.split(':');
        Integer h = Integer.valueOf(parts[0].trim());
        Integer mi = parts.size() > 1 ? Integer.valueOf(parts[1].trim().substring(0, 2)) : 0;
        return Time.newInstance(h, mi, 0, 0);
    }

    private static Id currentAccountId() {
        if (Test.isRunningTest() && testAccountId != null) return testAccountId;
        List<User> users = [SELECT AccountId, ContactId, Contact.AccountId
                            FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (users.isEmpty()) return null;
        if (users[0].AccountId != null) return users[0].AccountId;
        if (users[0].ContactId != null && users[0].Contact != null) return users[0].Contact.AccountId;
        return null;
    }
}