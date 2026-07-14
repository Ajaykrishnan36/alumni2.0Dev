public without sharing class KenReferralService {

    /**
     * Returns the full referral invite link for the currently logged-in community user.
     * On first call, generates and stores a random referral code on the user's Account.
     * Subsequent calls return the same link (code is stable).
     * Format: <Portal_URL>/SelfRegister?referal=<code>
     */
    @AuraEnabled(cacheable=false)
    public static String getReferralLink() {
        try {
            User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (u.AccountId == null) return null;

            Account acct = [SELECT Id, Referral_Code__c FROM Account WHERE Id = :u.AccountId LIMIT 1];

            if (String.isBlank(acct.Referral_Code__c)) {
                acct.Referral_Code__c = generateCode();
                update acct;
            }

            Alumni_Org_Parameters__c params = Alumni_Org_Parameters__c.getOrgDefaults();
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
            SELECT Id FROM Account WHERE Referral_Code__c = :code LIMIT 1
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