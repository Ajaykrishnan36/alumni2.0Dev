/**
 * @description Single source of truth for the logged-in community user's effective
 *              ConstituentRole. Stamps Last_Login__c when a role is picked on the
 *              select-role screen at login, and resolves the active role server-side
 *              (latest Last_Login__c) so LWCs no longer pass the id from localStorage.
 */
public without sharing class KenConstituentRoleService {
    @TestVisible
    private static Id testCurrentAccountId;
    @TestVisible
    private static Id testCurrentRoleId;

    private static Boolean roleResolved = false;
    private static Id cachedRoleId;

    /**
     * @description Stamps Last_Login__c = now on the role selected at login. Ignores
     *              roles that do not belong to the logged-in user's Person Account,
     *              and is a no-op for guests/internal users (no AccountId).
     *
     * @param constituentRoleId Role chosen on the select-role screen.
     */
    @AuraEnabled
    public static void updateLastLogin(Id constituentRoleId) {
        if (constituentRoleId == null) {
            return;
        }
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) {
            return;
        }
        List<ConstituentRole> roles = [
            SELECT Id
            FROM ConstituentRole
            WHERE Id = :constituentRoleId AND PersonId = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (roles.isEmpty()) {
            return;
        }
        roles[0].Last_Login__c = System.now();
        Database.update(roles[0], System.AccessLevel.SYSTEM_MODE);
        roleResolved = true;
        cachedRoleId = roles[0].Id;
    }

    /**
     * @description Client-side accessor for the resolved active role id, for LWCs that
     *              need it for UI checks (e.g. host-vs-viewer comparisons).
     *
     * @return ConstituentRole Id, or null.
     */
    @AuraEnabled(cacheable=true)
    public static Id getActiveRoleId() {
        return getActiveConstituentRoleId();
    }

    /**
     * @description Session catch-all for logins that never pass through the select-role
     *              screen (SSO deep links, admin "Log in to Experience as user"). Stamps
     *              Last_Login__c on the resolved active role and returns its
     *              Registration_Status__c so the caller can route incomplete journeys
     *              back through select-role. No-op returning null when the running user
     *              has no role. Called once per browser session from kenNavBar.
     *
     * @return Registration_Status__c of the stamped role, or null.
     */
    @AuraEnabled
    public static String ensureSessionLastLogin() {
        Id roleId = getActiveConstituentRoleId();
        if (roleId == null) {
            return null;
        }
        List<ConstituentRole> roles = [
            SELECT Id, Registration_Status__c
            FROM ConstituentRole
            WHERE Id = :roleId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (roles.isEmpty()) {
            return null;
        }
        roles[0].Last_Login__c = System.now();
        Database.update(roles[0], System.AccessLevel.SYSTEM_MODE);
        return roles[0].Registration_Status__c;
    }

    /**
     * @description Effective ConstituentRole of the logged-in user — the Alumni role
     *              with the most recent Last_Login__c (newest created as tie-breaker),
     *              resolved once per transaction. Null for internal users, who have
     *              no Person Account.
     *
     * @return ConstituentRole Id, or null.
     */
    public static Id getActiveConstituentRoleId() {
        if (Test.isRunningTest() && testCurrentRoleId != null) {
            return testCurrentRoleId;
        }
        if (!roleResolved) {
            roleResolved = true;
            cachedRoleId = fetchLatestLoginRoleId(getCurrentUserAccountId());
        }
        return cachedRoleId;
    }

    /**
     * @description Person Account Id of the logged-in community user, resolved via
     *              User.AccountId with a Contact.AccountId fallback.
     *
     * @return Account Id, or null for internal users.
     */
    public static Id getCurrentUserAccountId() {
        if (Test.isRunningTest() && testCurrentAccountId != null) {
            return testCurrentAccountId;
        }
        List<User> users = [
            SELECT Id, AccountId, ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return null;
        }
        User u = users[0];
        if (u.AccountId != null) {
            return u.AccountId;
        }
        if (u.ContactId != null) {
            List<Contact> contacts = [
                SELECT AccountId
                FROM Contact
                WHERE Id = :u.ContactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                return contacts[0].AccountId;
            }
        }
        return null;
    }

    private static Id fetchLatestLoginRoleId(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<ConstituentRole> roles = [
            SELECT Id
            FROM ConstituentRole
            WHERE PersonId = :accountId AND RoleType = 'Alumni'
            WITH SYSTEM_MODE
            ORDER BY Last_Login__c DESC NULLS LAST, CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        return roles.isEmpty() ? null : roles[0].Id;
    }
}