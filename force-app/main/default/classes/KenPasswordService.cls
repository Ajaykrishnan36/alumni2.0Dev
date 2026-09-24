/**
 * Single choke point for changing a Salesforce password from Apex.
 *
 * System.setPassword rewrites a user's credential, so every caller is funnelled
 * through here rather than calling the platform method from a controller: the
 * callers stay responsible for proving the request is authorised (an OTP, an
 * admin-only entry point) and this class stays the one place that performs the
 * write, so the audit surface is a single method.
 */
public without sharing class KenPasswordService {

    /**
     * Sets a new password for a user whose identity the caller has ALREADY verified.
     *
     * @param userId       The user to reset. Callers must have proven the requester
     *                     owns this user before calling.
     * @param newPassword  The replacement password.
     */
    public static void applyNewPassword(Id userId, String newPassword) {
        if (userId == null) {
            throw new KenPasswordException('A user is required to set a password.');
        }
        if (String.isBlank(newPassword)) {
            throw new KenPasswordException('A password is required.');
        }
        System.setPassword(userId, newPassword);
    }

    public class KenPasswordException extends Exception {}
}