public without sharing class UserActivityController {
    /**
     * @description Stamps the heartbeat time on the logged-in user's Person
     *              Account. Update-only: the Account always exists for a portal
     *              user, so this path never inserts. Previously wrote (and
     *              created) Ken_Alumni_CRM__c rows; that object is retired.
     */
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

        try {
            update new Account(
                Id = users[0].Contact.AccountId,
                Last_Active__c = System.now()
            );
        } catch (DmlException e) {
            System.debug(LoggingLevel.WARN, 'updateLastActive skipped: ' + e.getMessage());
        }
    }
}