public without sharing class UserActivityController {
    @AuraEnabled
    public static void updateLastActive() {
        List<User> users = [
            SELECT ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (users.isEmpty() || users[0].ContactId == null || users[0].Contact.AccountId == null) {
            return;
        }

        Id accountId = users[0].Contact.AccountId;
        Datetime nowValue = System.now();

        List<Ken_Alumni_CRM__c> existing = [
            SELECT Id, Last_Active__c
            FROM Ken_Alumni_CRM__c
            WHERE Person_Account__c = :accountId
            ORDER BY LastModifiedDate DESC
        ];

        if (!existing.isEmpty()) {
            for (Ken_Alumni_CRM__c rec : existing) {
                rec.Last_Active__c = nowValue;
            }
            update existing;
            return;
        }

        insert new Ken_Alumni_CRM__c(
            Person_Account__c = accountId,
            Last_Active__c = nowValue
        );
    }
}