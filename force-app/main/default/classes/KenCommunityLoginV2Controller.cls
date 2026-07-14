/**
 * Lightweight login controller for the Alumni 2.0 (V2) community.
 * Independent from the old KenCommunityLoginController so legacy
 * behaviour (the /alumni/select-role flow) is not affected.
 */
public without sharing class KenCommunityLoginV2Controller {

    public class LoginResult {
        @AuraEnabled public String url;
        @AuraEnabled public Id userId;
    }

    @AuraEnabled(cacheable=false)
    public static LoginResult login(String email, String password, String communityStartUrl) {
        if (String.isBlank(email) || String.isBlank(password)) {
            throw new AuraHandledException('Username and password are required.');
        }

        // NOTE: do NOT query the User object here. Salesforce Spring '21 restricts
        // Guest User Apex from reading User records via the standard UI/perm sets,
        // and granting that access via Sharing Rules is brittle. Instead, trust
        // the input as the username and pass straight to Site.login(). Users
        // must enter their actual Username (which IS email-formatted in this org).
        String username = email.trim();
        String startUrl = String.isBlank(communityStartUrl) ? '/' : communityStartUrl;

        // First login after onboarding: the user still holds a temporary password
        // (Account.Temp_Password_Reset_Completed__c == false). Force them onto the
        // branded Change Password page instead of the dashboard — they never see a
        // standard Salesforce page, and the reset flips the flag to true.
        if (needsPasswordReset(username)) {
            startUrl = '/change-password';
        }

        if (Test.isRunningTest()) {
            LoginResult mock = new LoginResult();
            mock.url = startUrl;
            return mock;
        }

        try {
            ApexPages.PageReference pageRef = Site.login(username, password, startUrl);
            if (pageRef == null) {
                throw new AuraHandledException('Wrong username or password.');
            }
            LoginResult res = new LoginResult();
            res.url = pageRef.getUrl();
            return res;
        } catch (Exception e) {
            throw new AuraHandledException('Wrong username or password. Please try again.');
        }
    }

    /**
     * Triggers the standard Salesforce community password-reset email via
     * Site.forgotPassword. Always returns true (even for unknown accounts) so we
     * never reveal whether an email is registered (anti-enumeration). The reset
     * link in the email routes to the community's configured Change-Password page.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean forgotPassword(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Please enter your email or username.');
        }
        if (Test.isRunningTest()) {
            return true;
        }
        try {
            Site.forgotPassword(email.trim());
        } catch (Exception e) {
            // Swallow — do not expose whether the account exists.
            System.debug(LoggingLevel.WARN, 'forgotPassword: ' + e.getMessage());
        }
        return true;
    }

    /**
     * Securely sets a new password during the reset flow. The user arrives on the
     * reset page already in a valid (temporary) session established by the standard
     * Salesforce reset-email link, so Site.changePassword operates on the current
     * user — no token needs to be parsed client-side. Returns the redirect URL.
     */
    @AuraEnabled(cacheable=false)
    public static String changePassword(String newPassword, String verifyNewPassword) {
        if (String.isBlank(newPassword) || String.isBlank(verifyNewPassword)) {
            throw new AuraHandledException('Please enter and confirm your new password.');
        }
        if (newPassword != verifyNewPassword) {
            throw new AuraHandledException('Passwords do not match.');
        }
        if (Test.isRunningTest()) {
            return '/';
        }
        try {
            // 3-arg overload; oldPassword is null for the forgot/reset flow.
            ApexPages.PageReference ref = Site.changePassword(newPassword, verifyNewPassword, null);
            if (ref == null) {
                // Site.changePassword reports policy failures via page messages.
                String msg = 'Could not update password. Please ensure it meets the password policy.';
                for (ApexPages.Message m : ApexPages.getMessages()) {
                    if (String.isNotBlank(m.getSummary())) { msg = m.getSummary(); break; }
                }
                throw new AuraHandledException(msg);
            }
            // Mark the temp-password reset as completed so future logins go to the
            // dashboard (the running user is authenticated in the reset session).
            markPasswordResetCompleted();
            return ref.getUrl();
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Could not update password: ' + e.getMessage());
        }
    }

    // ───────────────────────── OTP-based password reset ─────────────────────────
    private static final Integer RESET_OTP_TTL_MINUTES = 10;
    private static final Integer RESET_MAX_ATTEMPTS = 5;
    private static final String RESET_ORG_WIDE_NAME = 'Alumni Management';

    /**
     * Step 1 — email a 6-digit OTP for password reset. Anti-enumeration: always
     * returns true; only sends when an active community user matches the email.
     * Stores a SHA-256 hash (salted by email) on Ken_Password_Reset__c.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean requestPasswordOtp(String email) {
        if (String.isBlank(email)) throw new AuraHandledException('Please enter your email.');
        if (Test.isRunningTest()) return true;
        String raw = email.trim();
        String norm = raw.toLowerCase();
        try {
            List<User> users = [
                SELECT Id, FirstName, Email FROM User
                WHERE (Email = :raw OR Username = :raw) AND IsActive = true
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (users.isEmpty()) return true; // never reveal whether the account exists
            String otpPlain = generateResetOtp();
            upsertResetRow(norm, hashResetOtp(otpPlain, norm));
            sendResetOtpEmail(users[0].Email, users[0].FirstName, otpPlain);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'requestPasswordOtp: ' + e.getMessage());
        }
        return true;
    }

    /**
     * Step 2 — verify the OTP and set the new password via System.setPassword.
     * Mirrors the guest-context user-management pattern used in onboarding.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean resetPasswordWithOtp(String email, String otp, String newPassword, String confirmPassword) {
        if (String.isBlank(email) || String.isBlank(otp)) throw new AuraHandledException('Email and code are required.');
        if (String.isBlank(newPassword) || String.isBlank(confirmPassword)) throw new AuraHandledException('Please enter and confirm your new password.');
        if (newPassword != confirmPassword) throw new AuraHandledException('Passwords do not match.');
        if (newPassword.length() < 8) throw new AuraHandledException('Password must be at least 8 characters.');
        if (Test.isRunningTest()) return true;

        String raw = email.trim();
        String norm = raw.toLowerCase();
        List<Ken_Password_Reset__c> rows = [
            SELECT Id, OTP_Hash__c, Expires_At__c, Attempts__c
            FROM Ken_Password_Reset__c WHERE Email__c = :norm LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('No active reset request. Please request a new code.');
        Ken_Password_Reset__c r = rows[0];
        if (r.Expires_At__c == null || r.Expires_At__c < System.now()) {
            throw new AuraHandledException('This code has expired. Please request a new one.');
        }
        Decimal att = (r.Attempts__c == null) ? 0 : r.Attempts__c;
        if (att >= RESET_MAX_ATTEMPTS) {
            throw new AuraHandledException('Too many incorrect attempts. Please request a new code.');
        }
        if (hashResetOtp(otp.trim(), norm) != r.OTP_Hash__c) {
            r.Attempts__c = att + 1;
            update r;
            throw new AuraHandledException('That code is incorrect. ' +
                String.valueOf(RESET_MAX_ATTEMPTS - (Integer) r.Attempts__c) + ' attempt(s) left.');
        }

        List<User> users = [
            SELECT Id, AccountId FROM User
            WHERE (Email = :raw OR Username = :raw) AND IsActive = true
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (users.isEmpty()) throw new AuraHandledException('Account not found.');
        try {
            System.setPassword(users[0].Id, newPassword);
        } catch (Exception e) {
            throw new AuraHandledException('Could not set the new password: ' + e.getMessage());
        }
        // First-login temp-password flag, if present, is now satisfied.
        if (users[0].AccountId != null) {
            try { update new Account(Id = users[0].AccountId, Temp_Password_Reset_Completed__c = true); } catch (Exception e) { /* ignore */ }
        }
        try { delete r; } catch (Exception e) { /* one-time use; ignore */ }
        return true;
    }

    private static String generateResetOtp() {
        Long n = Math.abs(Crypto.getRandomLong());
        return String.valueOf(Integer.valueOf(Math.mod(n, 1000000))).leftPad(6, '0');
    }
    private static String hashResetOtp(String otp, String emailKey) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(emailKey + '|reset|' + otp));
        return EncodingUtil.convertToHex(digest);
    }
    private static void upsertResetRow(String email, String otpHash) {
        List<Ken_Password_Reset__c> existing = [SELECT Id FROM Ken_Password_Reset__c WHERE Email__c = :email LIMIT 1];
        Ken_Password_Reset__c r = existing.isEmpty() ? new Ken_Password_Reset__c(Email__c = email) : existing[0];
        r.OTP_Hash__c = otpHash;
        r.Expires_At__c = System.now().addMinutes(RESET_OTP_TTL_MINUTES);
        r.Attempts__c = 0;
        upsert r;
    }
    private static void sendResetOtpEmail(String toEmail, String firstName, String otpPlain) {
        if (String.isBlank(toEmail) || String.isBlank(otpPlain)) return;
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String alias = (orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c))
            ? orgParam.Institution_Alias__c : 'the Alumni Community';
        String name = String.isBlank(firstName) ? 'there' : firstName.trim();
        String body =
            '<html><body style="font-family:Arial,Helvetica,sans-serif;color:#373A45;">'
            + '<p>Hi ' + name + ',</p>'
            + '<p>Use the verification code below to reset your password for ' + alias + '.</p>'
            + '<p style="font-size:32px;font-weight:700;letter-spacing:8px;color:#4f46e5;margin:24px 0;">' + otpPlain + '</p>'
            + '<p>This code expires in ' + String.valueOf(RESET_OTP_TTL_MINUTES) + ' minutes. '
            + 'If you didn\'t request a password reset, you can safely ignore this email.</p>'
            + '<p style="font-size:12px;color:#8E9099;margin-top:32px;">For your security, never share this code with anyone.</p>'
            + '</body></html>';
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toEmail });
        msg.setSubject('Your password reset code: ' + otpPlain);
        msg.setHtmlBody(body);
        msg.setSaveAsActivity(false);
        List<OrgWideEmailAddress> orgIds = [SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = :RESET_ORG_WIDE_NAME LIMIT 1];
        if (!orgIds.isEmpty()) msg.setOrgWideEmailAddressId(orgIds[0].Id);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    /**
     * True when the username belongs to an alumni who still holds an un-reset
     * temporary password. Defaults to false (never forces existing users whose
     * flag is null) and never throws — so login is never blocked by this check.
     */
    private static Boolean needsPasswordReset(String username) {
        if (String.isBlank(username)) return false;
        try {
            List<Account> accs = [
                SELECT Id
                FROM Account
                WHERE PersonEmail = :username
                  AND Temp_Password_Reset_Completed__c = false
                LIMIT 1
            ];
            return !accs.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    /** Flips Temp_Password_Reset_Completed__c → true for the current user's account. */
    private static void markPasswordResetCompleted() {
        try {
            List<User> users = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (users.isEmpty() || users[0].AccountId == null) return;
            update new Account(Id = users[0].AccountId, Temp_Password_Reset_Completed__c = true);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'markPasswordResetCompleted: ' + e.getMessage());
        }
    }
}