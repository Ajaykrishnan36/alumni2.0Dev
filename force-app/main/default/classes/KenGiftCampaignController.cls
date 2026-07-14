/**
 * Fundraiser-Initiator flow (Bug D — "Create campaign").
 *
 * Standard Campaign create/edit requires the Marketing User permission, which Apex does
 * NOT bypass even `without sharing`. So community users CANNOT insert a Campaign directly.
 * Instead they submit a staging record (Ken_Gift_Campaign_Request__c); an admin who HAS
 * Marketing User later materializes it into a real Campaign via approveRequest().
 */
public without sharing class KenGiftCampaignController {

    public class CampaignRequestInput {
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String story { get; set; }
        @AuraEnabled public Decimal goalAmount { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public String heroImageUrl { get; set; }
        @AuraEnabled public String requestId { get; set; }
        // New fields from the "Start a giving initiative" form (Figma).
        @AuraEnabled public String whyItMatters { get; set; }
        @AuraEnabled public String beneficiaryGroup { get; set; }
        @AuraEnabled public String batchAssociation { get; set; }
        @AuraEnabled public Boolean isReunionLinked { get; set; }
        @AuraEnabled public Boolean listAsInitiator { get; set; }
        @AuraEnabled public Boolean inviteBatchmates { get; set; }
        // ContentDocument Ids from <lightning-file-upload> (server-side upload already
        // happened; we only need to ContentDocumentLink them to the new request record).
        @AuraEnabled public List<String> documentIds { get; set; }
        // OR an inline upload from the native SLDS file selector (LWR workaround for
        // lightning-file-upload's oversized icon). Apex creates ContentVersion +
        // ContentDocumentLink in the same transaction.
        @AuraEnabled public String attachmentFileName { get; set; }
        @AuraEnabled public String attachmentBase64   { get; set; }
    }

    public class CampaignRequestResult {
        @AuraEnabled public Id requestId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean alreadyExisted { get; set; }
    }

    /** Community-facing: stage a campaign proposal. No Marketing User needed. */
    @AuraEnabled
    public static CampaignRequestResult submitCampaignRequest(CampaignRequestInput req) {
        if (req == null) throw new AuraHandledException('Campaign details are required.');
        if (String.isBlank(req.title)) throw new AuraHandledException('Please enter a campaign title.');
        if (String.isBlank(req.requestId)) throw new AuraHandledException('A request id is required.');

        // Idempotency — a retried submit returns the existing request.
        List<Ken_Gift_Campaign_Request__c> existing = [
            SELECT Id, Status__c FROM Ken_Gift_Campaign_Request__c
            WHERE Request_Id__c = :req.requestId LIMIT 1
        ];
        if (!existing.isEmpty()) {
            CampaignRequestResult dup = new CampaignRequestResult();
            dup.requestId = existing[0].Id; dup.status = existing[0].Status__c; dup.alreadyExisted = true;
            return dup;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            Ken_Gift_Campaign_Request__c r = new Ken_Gift_Campaign_Request__c();
            r.Name = req.title.trim().left(80);
            r.Description__c = req.description;
            r.Story__c = req.story;
            r.Goal_Amount__c = req.goalAmount;
            if (String.isNotBlank(req.category)) r.Category__c = req.category;
            r.Hero_Image_URL__c = req.heroImageUrl;
            r.Status__c = 'Submitted';
            r.Request_Id__c = req.requestId;
            r.Requested_By__c = currentContactId();
            r.Why_It_Matters__c = req.whyItMatters;
            r.Beneficiary_Group__c = req.beneficiaryGroup;
            r.Batch_Program_Association__c = req.batchAssociation;
            r.Is_Reunion_Linked__c = (req.isReunionLinked == true);
            r.List_As_Initiator__c = (req.listAsInitiator != false);   // default true
            r.Invite_Batchmates__c = (req.inviteBatchmates != false);  // default true
            insert r;

            // Inline native-input upload: create the ContentVersion ourselves, then link.
            if (String.isNotBlank(req.attachmentBase64) && String.isNotBlank(req.attachmentFileName)) {
                ContentVersion cv = new ContentVersion(
                    Title         = req.attachmentFileName.left(255),
                    PathOnClient  = req.attachmentFileName.left(255),
                    VersionData   = EncodingUtil.base64Decode(req.attachmentBase64),
                    IsMajorVersion= true
                );
                insert cv;
                cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
                insert new ContentDocumentLink(
                    LinkedEntityId    = r.Id,
                    ContentDocumentId = cv.ContentDocumentId,
                    ShareType         = 'V',
                    Visibility        = 'AllUsers'
                );
            }

            // Existing path: files already uploaded by <lightning-file-upload> elsewhere.
            if (req.documentIds != null && !req.documentIds.isEmpty()) {
                List<ContentDocumentLink> links = new List<ContentDocumentLink>();
                for (String docId : req.documentIds) {
                    if (String.isBlank(docId)) continue;
                    links.add(new ContentDocumentLink(
                        LinkedEntityId   = r.Id,
                        ContentDocumentId = (Id) docId,
                        ShareType        = 'V',          // Viewer access for the record
                        Visibility       = 'AllUsers'
                    ));
                }
                if (!links.isEmpty()) insert links;
            }

            CampaignRequestResult res = new CampaignRequestResult();
            res.requestId = r.Id; res.status = r.Status__c; res.alreadyExisted = false;
            return res;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Admin-facing materialization. Must be run by a user WITH the Marketing User permission
     * (the Campaign DML enforces it). Creates an inactive, non-portal-visible Campaign that
     * an admin then reviews/publishes. Idempotent: skips if already materialized.
     */
    @AuraEnabled
    public static Id approveRequest(Id requestId) {
        if (requestId == null) throw new AuraHandledException('Request id is required.');
        List<Ken_Gift_Campaign_Request__c> rows = [
            SELECT Id, Name, Description__c, Story__c, Goal_Amount__c, Category__c,
                   Hero_Image_URL__c, Status__c, Campaign__c
            FROM Ken_Gift_Campaign_Request__c WHERE Id = :requestId LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Request not found.');
        Ken_Gift_Campaign_Request__c r = rows[0];
        if (r.Campaign__c != null) return r.Campaign__c; // already materialized

        try {
            Campaign c = new Campaign();
            c.Name = r.Name;
            Id givingRtId = KenGiftCampaignRequestTriggerHandler.resolveGivingRecordTypeId();
            if (givingRtId != null) c.RecordTypeId = givingRtId;   // explicit Giving record type
            c.IsActive = false;                              // not live until an admin publishes
            c.Status = 'Planned';
            c.Description = r.Description__c;
            c.Ken_Giving_Goal_Amount__c = r.Goal_Amount__c;
            c.Ken_Giving_Category__c = r.Category__c;
            c.Ken_Giving_Story__c = r.Story__c;
            c.Ken_Giving_Hero_Image_URL__c = r.Hero_Image_URL__c;
            c.Ken_Giving_Is_Portal_Visible__c = false;       // admin flips on after review
            insert c;

            r.Campaign__c = c.Id;
            r.Status__c = 'Approved';
            update r;
            return c.Id;
        } catch (DmlException e) {
            // Most likely: running user lacks the Marketing User permission.
            throw new AuraHandledException('Could not create Campaign: ' + e.getDmlMessage(0)
                + ' (the approving user must have the "Marketing User" permission).');
        }
    }

    private static Id currentContactId() {
        for (User u : [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]) {
            return u.ContactId;
        }
        return null;
    }
}