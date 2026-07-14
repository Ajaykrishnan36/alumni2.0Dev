/**
 * KenVisitorPassController
 *
 * Handles the Gate Pass Visitor flow.
 * - Searches for an existing Contact by email under the student's Account
 * - Creates a new Contact under the student's Account if not found
 * - Does NOT modify existing Contact records
 */
public without sharing class KenVisitorPassController {

    public class VisitorContactInfo {
        @AuraEnabled public String contactId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String relationshipType;
        @AuraEnabled public Boolean found;
    }

    /**
     * Search for an existing Contact by email.
     * Looks first under the student's Account, then broadly.
     * Returns null if not found.
     */
    @AuraEnabled(cacheable=false)
    public static VisitorContactInfo searchVisitorByEmail(String email) {
        if (String.isBlank(email)) return null;
        try {
            String cleanEmail = email.trim();
            Id studentAccountId = getStudentAccountId();

            List<Contact> contacts = new List<Contact>();

            // 1. Search under student's own Account first
            if (studentAccountId != null) {
                contacts = [
                    SELECT Id, FirstName, LastName, Email, Phone, MobilePhone,
                           Relationship_Type__c
                    FROM Contact
                    WHERE Email = :cleanEmail
                    AND AccountId = :studentAccountId
                    LIMIT 1
                ];
            }

            // 2. Broader search if not found under student's account
            if (contacts.isEmpty()) {
                contacts = [
                    SELECT Id, FirstName, LastName, Email, Phone, MobilePhone,
                           Relationship_Type__c
                    FROM Contact
                    WHERE Email = :cleanEmail
                    LIMIT 1
                ];
            }

            if (contacts.isEmpty()) return null;

            Contact c = contacts[0];
            VisitorContactInfo info = new VisitorContactInfo();
            info.contactId        = c.Id;
            info.firstName        = c.FirstName;
            info.lastName         = c.LastName;
            info.email            = c.Email;
            info.phone            = String.isNotBlank(c.MobilePhone) ? c.MobilePhone : c.Phone;
            info.relationshipType = c.Relationship_Type__c;
            info.found            = true;
            return info;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Create a new Contact under the student's Account.
     * If a Contact with the given email already exists, returns its Id without changes.
     */
    @AuraEnabled
    public static String saveVisitorContact(
        String firstName,
        String lastName,
        String email,
        String phone,
        String relationshipType
    ) {
        if (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(email)) {
            throw new AuraHandledException('First name, last name and email are required.');
        }

        String cleanEmail = email.trim();

        // Check if Contact already exists — return as-is, no update
        List<Contact> existing = [
            SELECT Id FROM Contact
            WHERE Email = :cleanEmail
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        // Get the student's Account ID from current logged-in user
        Id studentAccountId = getStudentAccountId();

        // Create Contact linked to student's Account via Related_To__c
        // (Person Accounts don't allow AccountId — Related_To__c is the correct lookup field)
        try {
            Contact c = new Contact(
                FirstName            = firstName.trim(),
                LastName             = lastName.trim(),
                Email                = cleanEmail,
                MobilePhone          = String.isNotBlank(phone) ? phone.trim() : null,
                Relationship_Type__c = String.isNotBlank(relationshipType) ? relationshipType : null,
                Related_To__c        = studentAccountId
            );
            insert c;
            return c.Id;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to create visitor contact: ' + e.getDmlMessage(0));
        }
    }

    private static Id getStudentAccountId() {
        try {
            List<User> users = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (!users.isEmpty() && users[0].AccountId != null) {
                return users[0].AccountId;
            }
        } catch (Exception ignored) {}
        return null;
    }
}