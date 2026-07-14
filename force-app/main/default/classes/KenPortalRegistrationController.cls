/**
 * Self-registration handler for the Alumni 2.0 (V2) community.
 * Called from kenPortalRegisterPageV2 on the public /register page (guest context),
 * so it must run `without sharing`.
 *
 * Two-step flow (QA fix — was previously single-step which skipped the OTP screen):
 *   1. registerAlumni(input)             — validates form, creates the Lead with
 *                                          Ken_OTP_Verified__c=false, stamps a
 *                                          SHA-256-hashed 6-digit OTP, and emails
 *                                          the OTP to the alumnus.
 *   2. verifyRegistrationOtp(email, otp) — compares hash, flips Ken_OTP_Verified__c
 *                                          to true. The Lead trigger then sends the
 *                                          "registration submitted for review" email
 *                                          and the lead is visible to the admin queue.
 *   2b. resendRegistrationOtp(email)     — regenerates OTP, resets attempts, resends.
 *
 * Until OTP_Verified is true:
 *   - KenLeadTriggerHandler.sendRegistrationSubmissionEmails skips the lead.
 *   - KenLeadTriggerHandler.getVerifiedLeads keeps ignoring it (admin can't approve
 *     an unverified registration).
 */
public without sharing class KenPortalRegistrationController {

    private static final String COMMUNITY_PROFILE = 'Alumni-Student';
    private static final Integer OTP_TTL_MINUTES = 10;
    private static final Integer MAX_OTP_ATTEMPTS = 3;
    private static final String ORG_WIDE_NAME = 'Alumni Management';

    public class RegistrationInput {
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String countryCode { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String universityRegNumber { get; set; }
        @AuraEnabled public String graduationYear { get; set; }
        @AuraEnabled public String linkedinUrl { get; set; }
    }

    /**
     * Step 1 — validate the form, upsert a Lead (OTP_Verified=false), stamp a fresh
     * OTP hash, send the OTP email. Returns 'OK' on success. The LWC then transitions
     * to the OTP-entry screen.
     */
    @AuraEnabled
    public static String registerAlumni(RegistrationInput input) {
        validate(input);
        String email = input.email.trim().toLowerCase();

        // Hard-block when a community user already exists for this email.
        if (![SELECT Id FROM Contact WHERE Email = :email LIMIT 1].isEmpty()
            || ![SELECT Id FROM User WHERE Username = :email OR Email = :email LIMIT 1].isEmpty()) {
            throw new AuraHandledException('An account with this email already exists. Please log in instead.');
        }

        Id leadRtId = alumniLeadRecordTypeId();
        if (leadRtId == null) {
            throw new AuraHandledException('Alumni Lead record type is not available in this org.');
        }

        // If a pending (OTP-unverified OR awaiting admin) lead already exists for this
        // email, reuse it instead of creating a duplicate. This makes the form resubmit-safe
        // and also handles the "I came back later" case.
        List<Lead> existing = [
            SELECT Id, FirstName, LastName, Email, Status, Ken_OTP_Verified__c
            FROM Lead WHERE Email = :email AND IsConverted = false LIMIT 1
        ];

        String phoneFull = String.isBlank(input.phone)
            ? null
            : (String.isBlank(input.countryCode) ? input.phone.trim() : input.countryCode + ' ' + input.phone.trim());
        String company = (input.firstName.trim() + ' ' + input.lastName.trim() + ' (Alumni)').trim();

        // Generate a fresh 6-digit OTP and SHA-256 hash it. Plaintext never persisted.
        String otpPlain = generateOtp();
        String otpHash  = hashOtp(otpPlain, email);

        Savepoint sp = Database.setSavepoint();
        Lead l;
        try {
            if (!existing.isEmpty()) {
                // Block re-registration only if OTP was already verified (lead is in
                // the admin review queue) — don't make the user wait for admin rejection
                // to retry if they fat-fingered something.
                if (existing[0].Ken_OTP_Verified__c == true) {
                    throw new AuraHandledException('A registration request with this email is already pending review.');
                }
                l = existing[0];
                l.FirstName = input.firstName.trim();
                l.LastName  = input.lastName.trim();
                l.Phone     = phoneFull;
                l.Year_of_Graduation__c  = input.graduationYear.trim();
                l.Registration_Number__c = input.universityRegNumber.trim();
                l.Ken_OTP_Hash__c        = otpHash;
                l.Ken_OTP_Expires_At__c  = System.now().addMinutes(OTP_TTL_MINUTES);
                l.Ken_OTP_Verified__c    = false;
                l.Ken_OTP_Attempts__c    = 0;
                update l;
            } else {
                l = new Lead(
                    RecordTypeId = leadRtId,
                    FirstName = input.firstName.trim(),
                    LastName  = input.lastName.trim(),
                    Company   = company,
                    Email     = email,
                    Phone     = phoneFull,
                    Year_of_Graduation__c  = input.graduationYear.trim(),
                    Registration_Number__c = input.universityRegNumber.trim(),
                    LeadSource = 'Portal Self-Registration',
                    Status = 'New',
                    Ken_OTP_Hash__c       = otpHash,
                    Ken_OTP_Expires_At__c = System.now().addMinutes(OTP_TTL_MINUTES),
                    Ken_OTP_Verified__c   = false,
                    Ken_OTP_Attempts__c   = 0
                );
                insert l;
            }

            sendOtpEmail(email, input.firstName, otpPlain);
            return 'OK';

        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not submit registration: ' + e.getDmlMessage(0));
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not submit registration. ' + e.getMessage());
        }
    }

    /**
     * Step 2 — verify the OTP entered by the user.
     * On success: Ken_OTP_Verified__c -> true (triggers the submission email via
     * KenLeadTriggerHandler.processAfterUpdate).
     * On failure: increments Ken_OTP_Attempts__c; after MAX_OTP_ATTEMPTS the OTP is
     * invalidated and the user must request a fresh one.
     */
    @AuraEnabled
    public static String verifyRegistrationOtp(String email, String otp) {
        if (String.isBlank(email) || String.isBlank(otp)) {
            throw new AuraHandledException('Email and OTP are both required.');
        }
        String norm = email.trim().toLowerCase();
        String code = otp.trim();

        List<Lead> rows = [
            SELECT Id, Email, Ken_OTP_Hash__c, Ken_OTP_Expires_At__c,
                   Ken_OTP_Verified__c, Ken_OTP_Attempts__c
            FROM Lead WHERE Email = :norm AND IsConverted = false LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('No pending registration found for this email. Please register first.');
        }
        Lead l = rows[0];
        if (l.Ken_OTP_Verified__c == true) {
            return 'ALREADY_VERIFIED';
        }
        if (String.isBlank(l.Ken_OTP_Hash__c) || l.Ken_OTP_Expires_At__c == null) {
            throw new AuraHandledException('No active OTP. Please tap Resend to get a new code.');
        }
        if (l.Ken_OTP_Expires_At__c < System.now()) {
            throw new AuraHandledException('This OTP has expired. Please tap Resend to get a new code.');
        }
        Decimal attempts = (l.Ken_OTP_Attempts__c == null) ? 0 : l.Ken_OTP_Attempts__c;
        if (attempts >= MAX_OTP_ATTEMPTS) {
            // Force a resend by invalidating the hash.
            l.Ken_OTP_Hash__c = null;
            update l;
            throw new AuraHandledException('Too many incorrect attempts. Please tap Resend to get a new code.');
        }

        if (hashOtp(code, norm) != l.Ken_OTP_Hash__c) {
            l.Ken_OTP_Attempts__c = attempts + 1;
            update l;
            throw new AuraHandledException('That code is incorrect. ' +
                String.valueOf(MAX_OTP_ATTEMPTS - (Integer)(l.Ken_OTP_Attempts__c)) + ' attempt(s) left.');
        }

        l.Ken_OTP_Verified__c = true;
        l.Ken_OTP_Hash__c     = null;
        l.Ken_OTP_Expires_At__c = null;
        l.Ken_OTP_Attempts__c = 0;
        update l;  // triggers sendRegistrationSubmissionEmails (gated on OTP_Verified flip)
        return 'OK';
    }

    /**
     * Resend a fresh OTP for an existing pending registration.
     * Idempotent: refreshes hash + expiry + attempts and re-emails.
     */
    @AuraEnabled
    public static String resendRegistrationOtp(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email is required.');
        }
        String norm = email.trim().toLowerCase();
        List<Lead> rows = [
            SELECT Id, FirstName, Email, Ken_OTP_Verified__c
            FROM Lead WHERE Email = :norm AND IsConverted = false LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('No pending registration found for this email.');
        }
        Lead l = rows[0];
        if (l.Ken_OTP_Verified__c == true) {
            throw new AuraHandledException('Your OTP is already verified — please wait for admin review.');
        }

        String otpPlain = generateOtp();
        l.Ken_OTP_Hash__c       = hashOtp(otpPlain, norm);
        l.Ken_OTP_Expires_At__c = System.now().addMinutes(OTP_TTL_MINUTES);
        l.Ken_OTP_Attempts__c   = 0;
        update l;

        sendOtpEmail(norm, l.FirstName, otpPlain);
        return 'OK';
    }

    // ───────────────────────── OTP helpers ─────────────────────────

    private static String generateOtp() {
        // 6-digit zero-padded code. Crypto.getRandomLong avoids Math.random() bias
        // and is non-deterministic across requests.
        Long n = Math.abs(Crypto.getRandomLong());
        Integer six = Integer.valueOf(Math.mod(n, 1000000));
        return String.valueOf(six).leftPad(6, '0');
    }

    private static String hashOtp(String otp, String emailKey) {
        // Salt with email so the same digits at the same time on different accounts
        // don't collide.
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(emailKey + '|' + otp));
        return EncodingUtil.convertToHex(digest);
    }

    private static void sendOtpEmail(String toEmail, String firstName, String otpPlain) {
        if (String.isBlank(toEmail) || String.isBlank(otpPlain)) return;
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String alias = (orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c))
            ? orgParam.Institution_Alias__c : 'the Alumni Community';
        String name = String.isBlank(firstName) ? 'there' : firstName.trim();

        String body =
            '<html><body style="font-family:Arial,Helvetica,sans-serif;color:#373A45;">'
            + '<p>Hi ' + name + ',</p>'
            + '<p>Use the verification code below to continue your registration for '
            + alias + '.</p>'
            + '<p style="font-size:32px;font-weight:700;letter-spacing:8px;color:#4f46e5;'
            + 'margin:24px 0;">' + otpPlain + '</p>'
            + '<p>This code expires in ' + String.valueOf(OTP_TTL_MINUTES) + ' minutes. '
            + 'If you didn\'t start a registration, you can safely ignore this email.</p>'
            + '<p style="font-size:12px;color:#8E9099;margin-top:32px;">'
            + 'For your security, never share this code with anyone.</p>'
            + '</body></html>';

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toEmail });
        msg.setSubject('Your verification code: ' + otpPlain);
        msg.setHtmlBody(body);
        msg.setSaveAsActivity(false);
        List<OrgWideEmailAddress> orgIds = [
            SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = :ORG_WIDE_NAME LIMIT 1
        ];
        if (!orgIds.isEmpty()) msg.setOrgWideEmailAddressId(orgIds[0].Id);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    /** Resolves the 'Alumni Lead' record type Id that the lead pipeline keys on. */
    private static Id alumniLeadRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> rts = Lead.SObjectType.getDescribe().getRecordTypeInfosByName();
        Schema.RecordTypeInfo info = rts.get('Alumni Lead');
        return (info != null && info.isActive()) ? info.getRecordTypeId() : null;
    }

    // ───────────────────────── validation ─────────────────────────

    private static void validate(RegistrationInput input) {
        if (input == null) throw new AuraHandledException('No registration data was provided.');
        if (String.isBlank(input.firstName)) throw new AuraHandledException('First name is required.');
        if (String.isBlank(input.lastName))  throw new AuraHandledException('Last name is required.');
        if (String.isBlank(input.email) || !Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', input.email.trim())) {
            throw new AuraHandledException('A valid email address is required.');
        }
        if (String.isBlank(input.phone) || !Pattern.matches('^[0-9]{6,15}$', input.phone.replaceAll('[\\s-]', ''))) {
            throw new AuraHandledException('A valid phone number (digits only) is required.');
        }
        if (String.isBlank(input.universityRegNumber)) throw new AuraHandledException('University registration number is required.');
        if (String.isBlank(input.graduationYear) || !Pattern.matches('^[0-9]{4}$', input.graduationYear.trim())) {
            throw new AuraHandledException('A valid year of graduation is required.');
        }
        if (String.isNotBlank(input.linkedinUrl)
            && !Pattern.matches('(?i)^(https?://)?([a-z0-9-]+\\.)?linkedin\\.com/.+$', input.linkedinUrl.trim())) {
            throw new AuraHandledException('Please enter a valid LinkedIn profile URL.');
        }
    }
}