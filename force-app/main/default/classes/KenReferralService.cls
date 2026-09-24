public without sharing class KenReferralService {

    /**
     * Lets a test state which Account the caller belongs to.
     *
     * The real lookup needs a running community user, and creating one means inserting a portal
     * User against a person Account. Concurrent portal-user inserts contend on shared rows, so
     * under a full parallel RunLocalTests that insert intermittently throws UNABLE_TO_LOCK_ROW
     * and fails a test that has nothing wrong with it. getReferralLink_noAccount still runs the
     * real query path with the seam unset.
     */
    @TestVisible
    private static Id testRunningAccountId;

    private static Id runningAccountId() {
        if (Test.isRunningTest() && testRunningAccountId != null) {
            return testRunningAccountId;
        }
        User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        return u.AccountId;
    }

    /**
     * Returns the full referral invite link for the currently logged-in community user.
     * On first call, generates and stores a random referral code on the user's Account.
     * Subsequent calls return the same link (code is stable).
     * Format: <Portal_URL>/SelfRegister?referal=<code>
     */
    @AuraEnabled(cacheable=false)
    public static String getReferralLink() {
        try {
            Id accountId = runningAccountId();
            if (accountId == null) return null;

            Account acct = [SELECT Id, Referral_Code__c FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1];

            if (String.isBlank(acct.Referral_Code__c)) {
                acct.Referral_Code__c = generateCode();
                if (!Schema.sObjectType.Account.isUpdateable()) {
                    throw new KenCrudException('Account is not updateable by the current user.');
                }
                update acct;
            }

            Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
            String portalUrl = (params != null && String.isNotBlank(params.Portal_URL__c))
                ? params.Portal_URL__c.removeEnd('/')
                : null;
            if (String.isBlank(portalUrl)) return null;

            return portalUrl + '/SelfRegister?referal=' + acct.Referral_Code__c;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Looks up an Account by its referral code.
     * Returns the Account ID, or null if no match.
     */
    public static Id resolveReferrerAccountId(String code) {
        if (String.isBlank(code)) return null;
        List<Account> matches = [
            SELECT Id FROM Account WHERE Referral_Code__c = :code
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return matches.isEmpty() ? null : matches[0].Id;
    }

    private static String generateCode() {
        String chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        String code = '';
        for (Integer i = 0; i < 12; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            code += chars.substring(idx, idx + 1);
        }
        return code;
    }
}