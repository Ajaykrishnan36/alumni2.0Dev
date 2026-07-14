/**
 * @description Trigger handler for Lead lifecycle events.
 *              Manages verification tokens, alumni onboarding,
 *              magic link emails, registration submissions,
 *              and rejection notifications.
 */
public without sharing class KenLeadTriggerHandler extends KenTriggerHandler {

    private static final String PORTAL_REGISTRATION_INVITATION = 'Portal_Registration_Invitation_1765533227690';
    private static final String ALUMNI_REG_SUBMISSION_TEMPLATE = 'Alumni_Registration_Submission_1746433607016';
    private static final String ALUMNI_REG_REJECTION_TEMPLATE = 'Alumni_Registration_Rejection_Email_1747223680789';
    private static final String ORG_WIDE_NAME = 'Alumni Management';
    private static final Id ALUMNI_LEAD_RT_ID = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Alumni Lead').getRecordTypeId();

    public override void processBeforeInsert() {
        insertVerificationToken();
    }

    public override void processAfterInsert() {
        List<Lead> verified = getVerifiedLeads((List<Lead>) Trigger.new, null);
        KenAlumniOnboardingService.provisionOnLeadVerification(verified);
        sendMagicLinkEmails(verified);
        KenAlumniOnboardingService.markLeadsConverted(verified);
        sendRegistrationSubmissionEmails((List<Lead>) Trigger.new);
    }

    public override void processAfterUpdate() {
        List<Lead> verified = getVerifiedLeads((List<Lead>) Trigger.new, (Map<Id, Lead>) Trigger.oldMap);
        KenAlumniOnboardingService.provisionOnLeadVerification(verified);
        sendMagicLinkEmails(verified);
        KenAlumniOnboardingService.markLeadsConverted(verified);
        sendRejectionEmails((List<Lead>) Trigger.new, (Map<Id, Lead>) Trigger.oldMap);
    }

    @TestVisible
    private static void insertVerificationToken() {

        for (Lead lead : (List<Lead>) Trigger.new) {

            if (lead.RecordTypeId != ALUMNI_LEAD_RT_ID) {
                continue;
            }

            if (String.isBlank(lead.Verification_Token__c)) {
                lead.Verification_Token__c = generateUniqueToken();
                lead.Token_Expiration_Date__c = System.now().addHours(48);
            }
        }
    }

    @TestVisible
    private static void sendMagicLinkEmails(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }

        Alumni_Email_Settings__c emailSettings = Alumni_Email_Settings__c.getOrgDefaults();
        if (emailSettings != null && emailSettings.Bypass_Portal_Registration_Invitation__c) {
            return;
        }

        EmailTemplate template = fetchMagicLinkTemplate();

        if (template == null) {
            return;
        }

         // Fetch Custom Setting once
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';
        String portalURL = orgParam != null && String.isNotBlank(orgParam.Portal_URL__c) ? orgParam.Portal_URL__c : '';

        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ORG_WIDE_NAME
            LIMIT 1
        ];

        EnhancedLetterhead lh;
        try {
            lh = [
                SELECT LetterheadHeader, LetterheadFooter
                FROM EnhancedLetterhead
                WHERE Name = 'Alumni Letterhead'
                LIMIT 1
            ];
        } catch (Exception e) {
            lh = null;
        }

        String letterheadHeader = lh != null && lh.LetterheadHeader != null ? lh.LetterheadHeader : '';

        String letterheadFooter = lh != null && lh.LetterheadFooter != null ? lh.LetterheadFooter : '';

        Set<Id> leadIdsToSkip = getLeadIdsToSkipMagicLink(leads);
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

        for (Lead lead : leads) {
            if (lead == null) {
                continue;
            }
            if (lead.RecordTypeId != ALUMNI_LEAD_RT_ID) {
                continue;
            }
            if (lead.Status != 'Verified' && lead.Status != 'Converted') {
                continue;
            }
            if (lead.Id != null && leadIdsToSkip.contains(lead.Id)) {
                continue;
            }
            if (String.isBlank(lead.Email) || String.isBlank(lead.Verification_Token__c)) {
                continue;
            }

            String body = template.HtmlValue;
            String yearOfGraduation = lead.Year_of_Graduation__c;
            String verificationToken = lead.Verification_Token__c;
            String fullName = String.join(new List<String>{lead.FirstName, lead.LastName},' ').trim();
            
            body = body.replace('{Recipient.Name}', fullName);
            body = body.replace('{Institution_Alias}', institutionAlias);
            body = body.replace('{Recipient.Year_of_Graduation__c}', yearOfGraduation != null ? yearOfGraduation : '');
            body = body.replace('{Portal_Url}', portalURL);
            body = body.replace('{Verification_Token}', verificationToken);
            String finalBody ='<html><body>' + letterheadHeader + body 
            // + letterheadFooter 
            + '</body></html>';

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ lead.Email });
            msg.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
            msg.setSaveAsActivity(false);
            msg.setHtmlBody(finalBody);
            messages.add(msg);
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages);
        }
    }

    @TestVisible
    private static Set<Id> getLeadIdsToSkipMagicLink(List<Lead> leads) {
        Set<Id> leadIdsToSkip = new Set<Id>();
        if (leads == null || leads.isEmpty()) {
            return leadIdsToSkip;
        }

        Set<String> emailKeys = new Set<String>();
        Set<String> regNumberKeys = new Set<String>();
        for (Lead lead : leads) {
            if (lead == null) {
                continue;
            }
            if (String.isNotBlank(lead.Email)) {
                emailKeys.add(lead.Email.trim().toLowerCase());
            }
            if (String.isNotBlank(lead.Registration_Number__c)) {
                regNumberKeys.add(lead.Registration_Number__c.trim().toLowerCase());
            }
        }

        if (emailKeys.isEmpty() && regNumberKeys.isEmpty()) {
            return leadIdsToSkip;
        }

        Map<String, Id> accountByPersonEmail = new Map<String, Id>();
        if (!emailKeys.isEmpty()) {
            for (Account pa : [
                SELECT Id, PersonEmail
                FROM Account
                WHERE IsPersonAccount = true
                AND PersonEmail IN :emailKeys
            ]) {
                if (String.isNotBlank(pa.PersonEmail)) {
                    accountByPersonEmail.put(pa.PersonEmail.trim().toLowerCase(), pa.Id);
                }
            }
        }

        Map<String, Id> accountByRegNumber = new Map<String, Id>();
        Map<String, List<ConstituentRole>> rolesByEmail = new Map<String, List<ConstituentRole>>();
        if (!emailKeys.isEmpty() || !regNumberKeys.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT PersonId, Email__c, Registration_Number__c, Program_Plan__c
                FROM ConstituentRole
                WHERE RoleType = 'Alumni'
                AND (Registration_Number__c IN :regNumberKeys OR Email__c IN :emailKeys)
                ORDER BY CreatedDate DESC
            ]) {
                if (String.isNotBlank(cr.Registration_Number__c)) {
                    String regKey = cr.Registration_Number__c.trim().toLowerCase();
                    if (!accountByRegNumber.containsKey(regKey)) {
                        accountByRegNumber.put(regKey, cr.PersonId);
                    }
                }
                if (String.isNotBlank(cr.Email__c)) {
                    String emailKey = cr.Email__c.trim().toLowerCase();
                    if (!rolesByEmail.containsKey(emailKey)) {
                        rolesByEmail.put(emailKey, new List<ConstituentRole>());
                    }
                    rolesByEmail.get(emailKey).add(cr);
                }
            }
        }

        Map<Id, Id> accountByLeadId = new Map<Id, Id>();
        for (Lead lead : leads) {
            if (lead == null || lead.Id == null) {
                continue;
            }

            String emailKey = String.isNotBlank(lead.Email) ? lead.Email.trim().toLowerCase() : null;
            String regKey = String.isNotBlank(lead.Registration_Number__c) ? lead.Registration_Number__c.trim().toLowerCase() : null;
            Id accountId = null;

            if (String.isNotBlank(emailKey)) {
                accountId = accountByPersonEmail.get(emailKey);
            }
            if (accountId == null && String.isNotBlank(regKey)) {
                accountId = accountByRegNumber.get(regKey);
            }
            if (accountId == null && String.isNotBlank(emailKey) && rolesByEmail.containsKey(emailKey)) {
                List<ConstituentRole> emailRoles = rolesByEmail.get(emailKey);
                if (lead.Program_Plan__c != null) {
                    for (ConstituentRole cr : emailRoles) {
                        if (cr.Program_Plan__c == lead.Program_Plan__c) {
                            accountId = cr.PersonId;
                            break;
                        }
                    }
                }
                if (accountId == null && !emailRoles.isEmpty()) {
                    accountId = emailRoles[0].PersonId;
                }
            }

            if (accountId != null) {
                accountByLeadId.put(lead.Id, accountId);
            }
        }

        if (accountByLeadId.isEmpty()) {
            return leadIdsToSkip;
        }

        Set<Id> accountIds = new Set<Id>();
        accountIds.addAll(accountByLeadId.values());

        Set<Id> accountsWithActiveUsers = new Set<Id>();
        for (User u : [
            SELECT AccountId
            FROM User
            WHERE IsActive = true
            AND AccountId IN :accountIds
        ]) {
            if (u.AccountId != null) {
                accountsWithActiveUsers.add(u.AccountId);
            }
        }

        if (accountsWithActiveUsers.isEmpty()) {
            return leadIdsToSkip;
        }

        Set<Id> accountsWithProgressedRoles = new Set<Id>();
        for (ConstituentRole cr : [
            SELECT PersonId, Registration_Status__c
            FROM ConstituentRole
            WHERE PersonId IN :accountIds
            AND RoleType = 'Alumni'
        ]) {
            if (cr.PersonId != null &&
                String.isNotBlank(cr.Registration_Status__c) &&
                cr.Registration_Status__c != 'Unregistered') {
                accountsWithProgressedRoles.add(cr.PersonId);
            }
        }

        for (Id leadId : accountByLeadId.keySet()) {
            Id accountId = accountByLeadId.get(leadId);
            if (accountsWithActiveUsers.contains(accountId) &&
                accountsWithProgressedRoles.contains(accountId)) {
                leadIdsToSkip.add(leadId);
            }
        }

        return leadIdsToSkip;
    }

    @TestVisible
    private static void sendRegistrationSubmissionEmails(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        
        Alumni_Email_Settings__c emailSettings = Alumni_Email_Settings__c.getOrgDefaults();
        if (emailSettings != null && emailSettings.Bypass_Alumni_Registration_Submission__c) {
            return;
        }

        EmailTemplate template = fetchTemplateByDeveloperName(ALUMNI_REG_SUBMISSION_TEMPLATE);
        if (template == null) {
            return;
        }

         // Fetch Custom Setting once
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';

        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ORG_WIDE_NAME
            LIMIT 1
        ];

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Lead lead : leads) {
            if (lead == null) {
                continue;
            }
            if (lead.RecordTypeId != ALUMNI_LEAD_RT_ID) {
                continue;
            }
            if (String.isBlank(lead.Email)) {
                continue;
            }

            String body = template.HtmlValue;
            String fullName = String.join(new List<String>{lead.FirstName, lead.LastName},' ').trim();

            body = body.replace('{Recipient.Name}', fullName);
            body = body.replace('{Institution_Alias}', institutionAlias);



            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setHtmlBody(body);
            msg.setToAddresses(new List<String>{ lead.Email });
            msg.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
            msg.setSaveAsActivity(false);
            messages.add(msg);
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages);
        }
    }

    @TestVisible
        private static void sendRejectionEmails(List<Lead> newLeads, Map<Id, Lead> oldLeadMap) {
            if (newLeads == null || newLeads.isEmpty() || oldLeadMap == null) {
                return;
            }

            Alumni_Email_Settings__c emailSettings = Alumni_Email_Settings__c.getOrgDefaults();
            if (emailSettings != null && emailSettings.ByPass_Alumni_Registration_Rejection_Ema__c) {
                return;
            }

            EmailTemplate template = fetchTemplateByDeveloperName(ALUMNI_REG_REJECTION_TEMPLATE);
            if (template == null) {
                return;
            }

            // Fetch Custom Setting once
            Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
            String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';
            String institutionEmail = orgParam != null && String.isNotBlank(orgParam.Institution_Email__c) ? orgParam.Institution_Email__c : '';

            List<OrgWideEmailAddress> orgIds = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = :ORG_WIDE_NAME
                LIMIT 1
            ];

            List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
            for (Lead l : newLeads) {
                if (l == null) {
                    continue;
                }
                if (l.RecordTypeId != ALUMNI_LEAD_RT_ID) {
                    continue;
                }
                Lead oldLead = oldLeadMap.get(l.Id);
                Boolean becameRejected = oldLead != null && l.Status == 'Rejected' && oldLead.Status != 'Rejected';
                if (!becameRejected || String.isBlank(l.Email)) {
                    continue;
                }

                String body = template.HtmlValue;
                String fullName = String.join(new List<String>{l.FirstName, l.LastName},' ').trim();

                body = body.replace('{User_Name}', fullName);
                body = body.replace('{Institution_Alias}', institutionAlias);
                body = body.replace('{Institution_Email}', institutionEmail);

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ l.Email });
                msg.setHtmlBody(body);
                msg.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
                msg.setSaveAsActivity(false);
                messages.add(msg);
            }

            if (!messages.isEmpty()) {
                Messaging.sendEmail(messages);
            }
        }
/**
     * @description Resends the magic login link email to a verified or
     *              converted lead. Regenerates the verification token
     *              if it is missing or expired.
     *
     * @param leadId  Id of the Lead to resend the magic link to.
     */
    @AuraEnabled
    public static void resendMagicLink(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('MISSING_LEAD_ID');
        }

        List<Lead> leadList = [
            SELECT Id, FirstName, LastName, Email, Status, Verification_Token__c, Token_Expiration_Date__c,
                   RecordTypeId, Year_of_Graduation__c, Registration_Number__c, Program_Plan__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (leadList.isEmpty()) {
            throw new AuraHandledException('MISSING_LEAD');
        }
        Lead lead = leadList[0];

        if (lead.Status != 'Verified' && lead.Status != 'Converted') {
            throw new AuraHandledException('NOT_VERIFIED');
        }
        if (String.isBlank(lead.Email)) {
            throw new AuraHandledException('MISSING_EMAIL');
        }

        if (lead.Token_Expiration_Date__c == null || lead.Token_Expiration_Date__c < System.now() || String.isBlank(lead.Verification_Token__c)) {
            lead.Verification_Token__c = generateUniqueToken();
            lead.Token_Expiration_Date__c = System.now().addHours(48);
            update lead;
        }

        sendMagicLinkEmails(new List<Lead>{ lead });
    }

    private static String generateUniqueToken() {
        Blob randomBlob = Crypto.generateAesKey(256);
        String timestamp = String.valueOf(System.currentTimeMillis());
        return EncodingUtil.convertToHex(randomBlob).substring(0, 32) + timestamp;
    }

    @TestVisible
    private static EmailTemplate fetchMagicLinkTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id,HtmlValue 
            FROM EmailTemplate
            WHERE DeveloperName = :PORTAL_REGISTRATION_INVITATION
            AND IsActive = true 
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }

    @TestVisible
    private static List<Lead> getVerifiedLeads(List<Lead> newLeads, Map<Id, Lead> oldLeadMap) {
        List<Lead> verified = new List<Lead>();

        for (Lead l : newLeads) {
            if (l.RecordTypeId != ALUMNI_LEAD_RT_ID) {
                continue;
            }
            Boolean statusJustVerified = (oldLeadMap == null) ? l.Status == 'Verified' : (l.Status == 'Verified' && oldLeadMap.containsKey(l.Id) && oldLeadMap.get(l.Id).Status != 'Verified');
            if (statusJustVerified) {
                verified.add(l);
            }
        }
        return verified;
    }

    @TestVisible
    private static EmailTemplate fetchTemplateByDeveloperName(String devName) {
        if (String.isBlank(devName)) {
            return null;
        }
        List<EmailTemplate> templates = [
            SELECT Id,HtmlValue 
            FROM EmailTemplate
            WHERE DeveloperName = :devName
            AND IsActive = true 
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }
}