/**
 * Epic 1 — Resume Library & Native Builder.
 *
 * Dual purpose:
 *   1) @AuraEnabled API for the LWC dashboard + builder (list / get / save / delete / PDF).
 *   2) Visualforce controller for the two renderAs="pdf" templates (KenResumeNewYork /
 *      KenResumeToronto) — the constructor loads the Ken_Resume__c by ?id and parses the
 *      JSON sections into typed lists the VF pages iterate.
 *
 * `without sharing` so a community alum can manage their own resumes + generate the PDF
 * server-side regardless of OWD. Every write surfaces e.getDmlMessage(0).
 */
public without sharing class KenResumeController {

    // ============================================================ DTOs
    public class ResumeInput {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String template;
        @AuraEnabled public String fullName;
        @AuraEnabled public String headline;
        @AuraEnabled public String summary;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String location;
        @AuraEnabled public String experienceJson;
        @AuraEnabled public String educationJson;
        @AuraEnabled public String skillsJson;
        @AuraEnabled public Boolean isDefault;
    }

    public class ResumeRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String template;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public String lastModified;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public Boolean hasPdf;
        @AuraEnabled public String contentVersionId;
    }

    // ============================================================ LWC API
    @AuraEnabled(cacheable=true)
    public static List<ResumeRow> getMyResumes() {
        Id c = currentContactId();
        List<ResumeRow> rows = new List<ResumeRow>();
        for (Ken_Resume__c r : [
            SELECT Id, Name, Template__c, Status__c, Is_Default__c,
                   Content_Version_Id__c, PDF_Download_URL__c, LastModifiedDate
            FROM Ken_Resume__c
            WHERE Owner_Contact__c = :c
            ORDER BY Is_Default__c DESC, LastModifiedDate DESC
            LIMIT 200
        ]) {
            ResumeRow row = new ResumeRow();
            row.id = r.Id; row.name = r.Name; row.template = r.Template__c;
            row.status = r.Status__c; row.isDefault = r.Is_Default__c;
            row.downloadUrl = r.PDF_Download_URL__c;
            row.hasPdf = String.isNotBlank(r.Content_Version_Id__c);
            row.contentVersionId = r.Content_Version_Id__c;
            row.lastModified = r.LastModifiedDate != null ? r.LastModifiedDate.format('dd MMM yyyy') : '';
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static ResumeInput getResume(Id resumeId) {
        if (resumeId == null) throw new AuraHandledException('Resume id is required.');
        List<Ken_Resume__c> recs = [
            SELECT Id, Name, Template__c, Full_Name__c, Headline__c, Summary__c, Email__c,
                   Phone__c, Location__c, Experience_JSON__c, Education_JSON__c, Skills_JSON__c, Is_Default__c
            FROM Ken_Resume__c WHERE Id = :resumeId LIMIT 1
        ];
        if (recs.isEmpty()) throw new AuraHandledException('Resume not found.');
        Ken_Resume__c r = recs[0];
        ResumeInput dto = new ResumeInput();
        dto.id = r.Id; dto.name = r.Name; dto.template = r.Template__c;
        dto.fullName = r.Full_Name__c; dto.headline = r.Headline__c; dto.summary = r.Summary__c;
        dto.email = r.Email__c; dto.phone = r.Phone__c; dto.location = r.Location__c;
        dto.experienceJson = r.Experience_JSON__c; dto.educationJson = r.Education_JSON__c;
        dto.skillsJson = r.Skills_JSON__c; dto.isDefault = r.Is_Default__c;
        return dto;
    }

    @AuraEnabled
    public static Id saveResumeDraft(ResumeInput input) {
        if (input == null) throw new AuraHandledException('Resume payload is required.');
        Savepoint sp = Database.setSavepoint();
        try {
            Ken_Resume__c r = (input.id != null) ? new Ken_Resume__c(Id = input.id) : new Ken_Resume__c();
            if (input.id == null) {
                r.Owner_Contact__c = currentContactId();
                r.Status__c = 'Draft';
            }
            r.Name = String.isNotBlank(input.name) ? input.name.trim().left(80) : 'My Resume';
            r.Template__c = String.isNotBlank(input.template) ? input.template : 'New York';
            r.Full_Name__c = input.fullName;
            r.Headline__c = input.headline;
            r.Summary__c = input.summary;
            r.Email__c = input.email;
            r.Phone__c = input.phone;
            r.Location__c = input.location;
            r.Experience_JSON__c = input.experienceJson;
            r.Education_JSON__c = input.educationJson;
            r.Skills_JSON__c = input.skillsJson;
            r.Is_Default__c = (input.isDefault == true);
            upsert r;

            // Only one default per owner.
            if (r.Is_Default__c) clearOtherDefaults(r.Id);
            return r.Id;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String generatePdf(Id resumeId) {
        if (resumeId == null) throw new AuraHandledException('Resume id is required.');
        List<Ken_Resume__c> recs = [SELECT Id, Name, Template__c FROM Ken_Resume__c WHERE Id = :resumeId LIMIT 1];
        if (recs.isEmpty()) throw new AuraHandledException('Resume not found.');
        Ken_Resume__c r = recs[0];
        Savepoint sp = Database.setSavepoint();
        try {
            PageReference pr = ('Toronto'.equalsIgnoreCase(r.Template__c)) ? Page.KenResumeToronto : Page.KenResumeNewYork;
            pr.getParameters().put('id', resumeId);
            Blob pdf = Test.isRunningTest() ? Blob.valueOf('%PDF-1.4 test') : pr.getContentAsPdf();

            ContentVersion cv = new ContentVersion(
                Title = (String.isNotBlank(r.Name) ? r.Name : 'Resume'),
                PathOnClient = (String.isNotBlank(r.Name) ? r.Name : 'Resume') + '.pdf',
                VersionData = pdf,
                IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            // Link the file to the resume record so it shows under Files.
            insert new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = resumeId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );

            // Public download link (works in the community) via ContentDistribution.
            ContentDistribution dist = new ContentDistribution(
                Name = (String.isNotBlank(r.Name) ? r.Name : 'Resume') + ' PDF',
                ContentVersionId = cv.Id,
                PreferencesAllowViewInBrowser = true,
                PreferencesLinkLatestVersion = true,
                PreferencesNotifyOnVisit = false
            );
            insert dist;
            // QA Bug — the PDF "opened but appeared blank". DistributionPublicUrl is the
            // public delivery/preview page, which renders an empty viewer in this LWR
            // community context. ContentDownloadUrl streams the actual file bytes — use it.
            ContentDistribution refreshed = [
                SELECT DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution WHERE Id = :dist.Id LIMIT 1
            ];
            String url = String.isNotBlank(refreshed.ContentDownloadUrl)
                ? refreshed.ContentDownloadUrl
                : '/sfc/servlet.shepherd/version/download/' + cv.Id;

            update new Ken_Resume__c(Id = resumeId, Content_Version_Id__c = cv.Id,
                PDF_Download_URL__c = url, Status__c = 'Generated');
            return url;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not generate PDF: ' + e.getMessage());
        }
    }

    /**
     * QA Bug — "users who already have an updated resume" had no way to upload it.
     * Accepts a base64 file (PDF/DOC), creates a Ken_Resume__c (Status='Generated'),
     * stores the file as a ContentVersion linked to the record + a public ContentDistribution,
     * and returns the new resume Id. Mirrors the generatePdf storage path.
     */
    @AuraEnabled
    public static Id uploadResume(String fileName, String base64Data) {
        if (String.isBlank(base64Data)) throw new AuraHandledException('No file data was provided.');
        String cleanName = String.isNotBlank(fileName) ? fileName.trim() : 'Uploaded Resume';
        // QA Bug — the uploaded file must be tied to the alum's Contact, not just the
        // Ken_Resume__c row. Resolve the running user's Contact up front.
        Id contactId = currentContactId();
        // Ensure the stored filename ends in .pdf so browsers stream/render it correctly.
        String pathOnClient = cleanName.toLowerCase().endsWith('.pdf') ? cleanName : cleanName + '.pdf';
        Savepoint sp = Database.setSavepoint();
        try {
            // Template__c is a restricted picklist (New York/Toronto only) — leave it
            // null for uploaded files rather than introducing an invalid value.
            Ken_Resume__c r = new Ken_Resume__c(
                Name = cleanName.left(80),
                Owner_Contact__c = contactId,
                Status__c = 'Generated'
            );
            insert r;

            // Decode the base64 (LWC already strips the `data:...;base64,` prefix) into the
            // real file bytes so VersionData holds the actual PDF, not an empty/garbled blob.
            ContentVersion cv = new ContentVersion(
                Title = cleanName.left(255),
                PathOnClient = pathOnClient.left(255),
                VersionData = EncodingUtil.base64Decode(base64Data),
                IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            // Link the document to the Ken_Resume__c row AND to the alum's Contact record.
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            links.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = r.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
            if (contactId != null) {
                links.add(new ContentDocumentLink(
                    ContentDocumentId = cv.ContentDocumentId,
                    LinkedEntityId = contactId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
            insert links;

            ContentDistribution dist = new ContentDistribution(
                Name = cleanName.left(255),
                ContentVersionId = cv.Id,
                PreferencesAllowViewInBrowser = true,
                PreferencesLinkLatestVersion = true,
                PreferencesNotifyOnVisit = false
            );
            insert dist;
            // QA Bug — downloaded PDF "opened but appeared blank". DistributionPublicUrl is
            // the public *delivery/preview* page, which renders an empty viewer in this LWR
            // community context. ContentDownloadUrl is the direct file-byte stream and returns
            // the actual PDF. Prefer it; fall back to the servlet download endpoint if blank.
            ContentDistribution refreshed = [
                SELECT DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution WHERE Id = :dist.Id LIMIT 1
            ];
            String url = String.isNotBlank(refreshed.ContentDownloadUrl)
                ? refreshed.ContentDownloadUrl
                : '/sfc/servlet.shepherd/version/download/' + cv.Id;

            update new Ken_Resume__c(Id = r.Id, Content_Version_Id__c = cv.Id, PDF_Download_URL__c = url);
            return r.Id;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Could not upload resume: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteResume(Id resumeId) {
        if (resumeId == null) throw new AuraHandledException('Resume id is required.');
        Id c = currentContactId();
        List<Ken_Resume__c> recs = [SELECT Id FROM Ken_Resume__c WHERE Id = :resumeId AND Owner_Contact__c = :c LIMIT 1];
        if (recs.isEmpty()) throw new AuraHandledException('Resume not found or not yours to delete.');
        delete recs[0];
    }

    // ============================================================ helpers
    private static void clearOtherDefaults(Id keepId) {
        Id c = currentContactId();
        List<Ken_Resume__c> others = [
            SELECT Id FROM Ken_Resume__c WHERE Owner_Contact__c = :c AND Is_Default__c = true AND Id != :keepId
        ];
        for (Ken_Resume__c o : others) o.Is_Default__c = false;
        if (!others.isEmpty()) update others;
    }

    private static Id currentContactId() {
        for (User u : [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]) {
            return u.ContactId;
        }
        return null;
    }

    // ============================================================ Visualforce controller members
    public class ExpItem { public String title { get; set; } public String company { get; set; } public String dates { get; set; } public String description { get; set; } }
    public class EduItem { public String degree { get; set; } public String institution { get; set; } public String dates { get; set; } }

    public Ken_Resume__c rec { get; private set; }
    public List<ExpItem> experiences { get; private set; }
    public List<EduItem> educations { get; private set; }
    public List<String> skills { get; private set; }

    public KenResumeController() {
        experiences = new List<ExpItem>();
        educations = new List<EduItem>();
        skills = new List<String>();
        rec = new Ken_Resume__c(); // null-safe default so VF merge fields never NPE
        Id rid = (Id) ApexPages.currentPage().getParameters().get('id');
        if (rid == null) return;
        List<Ken_Resume__c> recs = [
            SELECT Id, Name, Template__c, Full_Name__c, Headline__c, Summary__c, Email__c,
                   Phone__c, Location__c, Experience_JSON__c, Education_JSON__c, Skills_JSON__c
            FROM Ken_Resume__c WHERE Id = :rid LIMIT 1
        ];
        if (recs.isEmpty()) return;
        rec = recs[0];
        if (String.isNotBlank(rec.Experience_JSON__c)) {
            try { experiences = (List<ExpItem>) JSON.deserialize(rec.Experience_JSON__c, List<ExpItem>.class); } catch (Exception e) { /* tolerate */ }
        }
        if (String.isNotBlank(rec.Education_JSON__c)) {
            try { educations = (List<EduItem>) JSON.deserialize(rec.Education_JSON__c, List<EduItem>.class); } catch (Exception e) { /* tolerate */ }
        }
        if (String.isNotBlank(rec.Skills_JSON__c)) {
            try { skills = (List<String>) JSON.deserialize(rec.Skills_JSON__c, List<String>.class); }
            catch (Exception e) { skills = rec.Skills_JSON__c.split(','); }
        }
    }
}