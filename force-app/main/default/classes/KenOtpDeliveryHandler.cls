/**
 * @description Delivers the platform's passwordless login code through Marketing Cloud.
 *
 *              Salesforce still owns everything that matters about the code: it generates it,
 *              holds it, enforces expiry, rate limiting and lockout, and
 *              System.UserManagement.verifyPasswordlessLogin mints the portal session. This class
 *              is only asked to carry the code to the alumnus, which is what makes routing login
 *              OTPs through Marketing Cloud safe — nothing here stores a code, verifies a code, or
 *              touches a password.
 *
 *              Both phone channels are used for a login code. An alumnus who has WhatsApp gets it
 *              there and by SMS, and either one arriving is enough; the org can drop a channel
 *              later by clearing that channel's definition key or unticking its send switch.
 *
 *              Registering it is a Setup step, not a deployment. Salesforce Support has to switch
 *              the custom messaging service on for the org first, then the class is selected per
 *              site under All Sites > Workspaces > Administration > Login & Registration, in the
 *              Custom One-Time Password (OTP) Delivery section. Until then the platform keeps
 *              delivering codes itself.
 *
 *              It is only ever called for Experience Cloud external users — never for employees —
 *              and only for phone delivery, so there is no verification method to filter on. Note
 *              that a custom provider also means Salesforce stops requiring the number to be a
 *              verified verification method before it will send to it.
 */
global without sharing class KenOtpDeliveryHandler implements Auth.CustomOneTimePasswordDeliveryHandler {

    /**
     * @description Called by the identity framework once it has generated a code. The parameter
     *              order is fixed by the interface — position two is the number to text and
     *              position three is the code, which is easy to transpose and silently sends
     *              people their own phone number as their password.
     *
     * @param userId          the alumnus signing in
     * @param phoneNumber     the number the platform wants the code sent to
     * @param oneTimePassword the code the platform will expect back on verify
     * @param defaultText     the message Salesforce would have sent; the journey owns the wording
     * @param networkId       the Experience Cloud site the request came from
     * @param experienceId    the branding experience, unused here
     * @return whether the code was handed to Marketing Cloud
     */
    global Auth.CustomOneTimePasswordDeliveryResult sendOneTimePassword(
        Id userId,
        String phoneNumber,
        String oneTimePassword,
        String defaultText,
        Id networkId,
        String experienceId
    ) {
        Integer codeLength = oneTimePassword == null ? 0 : oneTimePassword.length();
        System.debug(LoggingLevel.ERROR, 'KEN_OTP handler INVOKED'
            + ' userId=' + userId
            + ' hasPhoneNumber=' + String.isNotBlank(phoneNumber)
            + ' codeLength=' + codeLength
            + ' hasDefaultText=' + String.isNotBlank(defaultText)
            + ' networkId=' + networkId
            + ' experienceId=' + experienceId);

        if (String.isBlank(oneTimePassword)) {
            System.debug(LoggingLevel.ERROR, 'KEN_OTP handler returning EXCEPTION - no code supplied');
            return Auth.CustomOneTimePasswordDeliveryResult.EXCEPTION;
        }

        String mobile;
        try {
            mobile = resolveMobile(userId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenOtpDeliveryHandler could not resolve a mobile number: ' + e.getMessage());
            return Auth.CustomOneTimePasswordDeliveryResult.EXCEPTION;
        }
        if (String.isBlank(mobile)) {
            mobile = phoneNumber;
        }

        if (String.isBlank(mobile)) {
            System.debug(LoggingLevel.ERROR,
                'KEN_OTP handler returning INVALID_PHONE_NUMBER - no number found for ' + userId);
            return Auth.CustomOneTimePasswordDeliveryResult.INVALID_PHONE_NUMBER;
        }

        List<String> delivered = KenMessagingService.sendOtpToPhone(
            KenMessagingService.TYPE_LOGIN_OTP,
            mobile,
            null,
            oneTimePassword
        );

        System.debug(LoggingLevel.ERROR, 'KEN_OTP handler sent'
            + ' deliveredChannels=' + delivered
            + ' result=' + (delivered.isEmpty() ? 'PROVIDER_ERROR' : 'SUCCESS'));

        return delivered.isEmpty()
            ? Auth.CustomOneTimePasswordDeliveryResult.PROVIDER_ERROR
            : Auth.CustomOneTimePasswordDeliveryResult.SUCCESS;
    }

    /**
     * @description Finds a number to text, taking the User record first.
     *
     *              Identity lives on the User: the platform verifies against User.Email and issues
     *              the SMS challenge against User.MobilePhone, so the number we text should be the
     *              same one. The Person Account is only consulted for alumni provisioned before
     *              the mobile was mirrored across at user creation.
     */
    @TestVisible
    private static String resolveMobile(Id userId) {

        List<User> users = [
            SELECT Id, MobilePhone, AccountId
            FROM User
            WHERE Id = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : numberFor(users[0]);
    }

    /**
     * @description The number-picking half of the resolution, split out so it can be exercised
     *              without provisioning a portal user — creating one inside a test locks rows that
     *              other test classes running in parallel are also holding.
     */
    @TestVisible
    private static String numberFor(User portalUser) {

        if (portalUser == null) {
            return null;
        }
        if (String.isNotBlank(portalUser.MobilePhone)) {
            return portalUser.MobilePhone;
        }
        if (portalUser.AccountId == null) {
            return null;
        }

        List<Account> accounts = [
            SELECT PersonMobilePhone, Phone
            FROM Account
            WHERE Id = :portalUser.AccountId
            AND IsPersonAccount = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return null;
        }
        return String.isNotBlank(accounts[0].PersonMobilePhone)
            ? accounts[0].PersonMobilePhone
            : accounts[0].Phone;
    }
}