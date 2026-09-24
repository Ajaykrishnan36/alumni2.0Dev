public without sharing class KenFundraiseController {

    public class CampaignDTO {
        @AuraEnabled public Id     id               { get; set; }
        @AuraEnabled public String name             { get; set; }
        @AuraEnabled public String category         { get; set; }
        @AuraEnabled public Id     categoryId       { get; set; }
        @AuraEnabled public String approvalStatus   { get; set; }
        @AuraEnabled public String campaignStatus   { get; set; }
        @AuraEnabled public Decimal fundraisingGoal { get; set; }
        @AuraEnabled public String currencyCode     { get; set; }
        @AuraEnabled public String startDate        { get; set; }
        @AuraEnabled public String endDate          { get; set; }
        @AuraEnabled public String coverImage       { get; set; }
        @AuraEnabled public Decimal amountRaised    { get; set; }
        @AuraEnabled public String description      { get; set; }
        @AuraEnabled public String ownerName        { get; set; }
        @AuraEnabled public String ownerPhotoUrl    { get; set; }
        @AuraEnabled public String collectionMethod { get; set; }
        @AuraEnabled public String externalLink     { get; set; }
        @AuraEnabled public String rejectionReason  { get; set; }
        @AuraEnabled public Boolean isOwner         { get; set; }
        @AuraEnabled public Boolean isAdmin         { get; set; }
        @AuraEnabled public String  createdDate     { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<CampaignDTO> getMyCampaigns() {
        Id effectiveRoleId = resolveConstituentRoleId();
        if (effectiveRoleId == null && !isInternalUser()) {
            throw new AuraHandledException('ConstituentRoleId is required.');
        }
        List<Ken_Fundraise__c> records = [
            SELECT Id, Name, Fundraise_Category__c, Fundraise_Category__r.Name, Approval_Status__c, Campaign_Status__c,
            Fundraising_Goal__c, Currency__c, Start_Date__c, End_Date__c,
            Cover_Image__c, Amount_Raised__c, Description__c,
            Constituent_Role__r.Person.Name, CreatedBy.SmallPhotoUrl, CreatedDate
            FROM Ken_Fundraise__c
            WHERE Constituent_Role__c = :effectiveRoleId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
        List<CampaignDTO> result = new List<CampaignDTO>();
        for (Ken_Fundraise__c r : records) {
            CampaignDTO dto = new CampaignDTO();
            dto.id             = r.Id;
            dto.name           = r.Name;
            dto.categoryId     = r.Fundraise_Category__c;
            dto.category       = r.Fundraise_Category__r != null ? r.Fundraise_Category__r.Name : null;
            dto.approvalStatus = r.Approval_Status__c;
            dto.campaignStatus = r.Campaign_Status__c;
            dto.fundraisingGoal = r.Fundraising_Goal__c;
            dto.currencyCode   = String.isNotBlank(r.Currency__c) ? r.Currency__c : 'INR';
            dto.startDate      = r.Start_Date__c != null ? String.valueOf(r.Start_Date__c) : null;
            dto.endDate        = r.End_Date__c   != null ? String.valueOf(r.End_Date__c)   : null;
            dto.coverImage     = r.Cover_Image__c;
            dto.amountRaised   = r.Amount_Raised__c;
            dto.description    = r.Description__c;
            dto.ownerName      = r.Constituent_Role__r != null ? r.Constituent_Role__r.Person?.Name : null;
            dto.ownerPhotoUrl  = r.CreatedBy?.SmallPhotoUrl;
            dto.createdDate    = r.CreatedDate != null ? String.valueOf(r.CreatedDate.date()) : null;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<CampaignDTO> getPublishedCampaigns() {
        List<Ken_Fundraise__c> records = [
            SELECT Id, Name, Fundraise_Category__c, Fundraise_Category__r.Name, Campaign_Status__c,
            Fundraising_Goal__c, Currency__c, Start_Date__c, End_Date__c,
            Cover_Image__c, Amount_Raised__c, Description__c,
            External_Link__c, Collection_Method__c,
            Constituent_Role__r.Person.Name, CreatedBy.SmallPhotoUrl, CreatedDate
            FROM Ken_Fundraise__c
            WHERE Approval_Status__c = 'Approved'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        List<CampaignDTO> result = new List<CampaignDTO>();
        for (Ken_Fundraise__c r : records) {
            CampaignDTO dto = new CampaignDTO();
            dto.id              = r.Id;
            dto.name            = r.Name;
            dto.categoryId      = r.Fundraise_Category__c;
            dto.category        = r.Fundraise_Category__r != null ? r.Fundraise_Category__r.Name : null;
            dto.approvalStatus  = 'Approved';
            dto.campaignStatus  = r.Campaign_Status__c;
            dto.fundraisingGoal = r.Fundraising_Goal__c;
            dto.currencyCode    = String.isNotBlank(r.Currency__c) ? r.Currency__c : 'INR';
            dto.startDate       = r.Start_Date__c != null ? String.valueOf(r.Start_Date__c) : null;
            dto.endDate         = r.End_Date__c   != null ? String.valueOf(r.End_Date__c)   : null;
            dto.coverImage      = r.Cover_Image__c;
            dto.amountRaised    = r.Amount_Raised__c;
            dto.description     = r.Description__c;
            dto.collectionMethod = r.Collection_Method__c;
            dto.externalLink    = r.External_Link__c;
            dto.ownerName       = r.Constituent_Role__r != null ? r.Constituent_Role__r.Person?.Name : null;
            dto.ownerPhotoUrl   = r.CreatedBy?.SmallPhotoUrl;
            dto.createdDate     = r.CreatedDate != null ? String.valueOf(r.CreatedDate.date()) : null;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<CampaignDTO> getAdminFundraiseList() {
        List<Ken_Fundraise__c> records = [
            SELECT Id, Name, Fundraise_Category__c, Fundraise_Category__r.Name, Approval_Status__c, Campaign_Status__c,
            Fundraising_Goal__c, Currency__c, Start_Date__c, End_Date__c,
            Cover_Image__c, Amount_Raised__c, Description__c,
            Collection_Method__c, Constituent_Role__r.Person.Name
            FROM Ken_Fundraise__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        List<CampaignDTO> result = new List<CampaignDTO>();
        for (Ken_Fundraise__c r : records) {
            CampaignDTO dto = new CampaignDTO();
            dto.id               = r.Id;
            dto.name             = r.Name;
            dto.categoryId       = r.Fundraise_Category__c;
            dto.category         = r.Fundraise_Category__r != null ? r.Fundraise_Category__r.Name : null;
            dto.approvalStatus   = r.Approval_Status__c;
            dto.campaignStatus   = r.Campaign_Status__c;
            dto.fundraisingGoal  = r.Fundraising_Goal__c;
            dto.currencyCode     = String.isNotBlank(r.Currency__c) ? r.Currency__c : 'INR';
            dto.startDate        = r.Start_Date__c != null ? String.valueOf(r.Start_Date__c) : null;
            dto.endDate          = r.End_Date__c   != null ? String.valueOf(r.End_Date__c)   : null;
            dto.coverImage       = r.Cover_Image__c;
            dto.amountRaised     = r.Amount_Raised__c;
            dto.description      = r.Description__c;
            dto.collectionMethod = r.Collection_Method__c;
            dto.ownerName        = r.Constituent_Role__r != null ? r.Constituent_Role__r.Person?.Name : null;
            result.add(dto);
        }
        return result;
    }

    public class FundraiseRequest {
        @AuraEnabled public String name           { get; set; }
        @AuraEnabled public Id categoryId         { get; set; }
        @AuraEnabled public String description    { get; set; }
        @AuraEnabled public String currencyCode   { get; set; }
        @AuraEnabled public Decimal fundraisingGoal { get; set; }
        @AuraEnabled public String collectionMethod { get; set; }
        @AuraEnabled public String externalLink   { get; set; }
        @AuraEnabled public String startDate      { get; set; }
        @AuraEnabled public String endDate        { get; set; }
        @AuraEnabled public String coverImageUrl  { get; set; }
        @AuraEnabled public List<String> segmentationIds { get; set; }
    }

    @AuraEnabled
    public static Id createCampaign(FundraiseRequest request) {
        try {
            if (request == null) {
                throw new AuraHandledException('No data provided.');
            }
            if (String.isBlank(request.name)) {
                throw new AuraHandledException('Campaign name is required.');
            }

            Id effectiveRoleId = resolveConstituentRoleId();
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }

            String directCoverUrl = (String.isNotBlank(request.coverImageUrl) && !request.coverImageUrl.startsWith('data:'))
                ? request.coverImageUrl
                : null;

            // A campaign carries one audience. The request still arrives as a list from
            // the picker, whose whole selection is already collapsed into a single
            // segmentation, so anything past the first entry is legacy noise.
            Id audienceId = null;
            if (request.segmentationIds != null) {
                for (String segId : request.segmentationIds) {
                    if (String.isNotBlank(segId)) {
                        audienceId = (Id) segId;
                        break;
                    }
                }
            }

            Ken_Fundraise__c campaign = new Ken_Fundraise__c(
                Name                = request.name.trim(),
                Fundraise_Category__c = request.categoryId,
                Description__c      = request.description,
                Currency__c         = String.isNotBlank(request.currencyCode) ? request.currencyCode : 'INR',
                Fundraising_Goal__c = request.fundraisingGoal,
                Collection_Method__c = request.collectionMethod,
                External_Link__c    = request.externalLink,
                Start_Date__c       = parseDate(request.startDate),
                End_Date__c         = parseDate(request.endDate),
                Cover_Image__c      = directCoverUrl,
                Approval_Status__c  = null,
                Campaign_Status__c  = 'Upcoming',
                Is_Active__c        = false,
                Is_Published__c     = false,
                Constituent_Role__c = effectiveRoleId,
                Segmentation__c     = audienceId
            );
            if (!Schema.sObjectType.Ken_Fundraise__c.isCreateable()) {
                throw new KenCrudException('Ken_Fundraise__c is not createable by the current user.');
            }
            insert campaign;

            if (String.isNotBlank(request.coverImageUrl) && request.coverImageUrl.startsWith('data:')) {
                campaign.Cover_Image__c = uploadAndLinkImage(
                    request.name.trim() + '_cover', request.coverImageUrl, campaign.Id
                );
                if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
                }
                update campaign;
            }

            return campaign.Id;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    @AuraEnabled(cacheable=true)
    public static CampaignDTO getCampaignById(Id campaignId) {
        Ken_Fundraise__c r = [
            SELECT Id, Name, Fundraise_Category__c, Fundraise_Category__r.Name, Approval_Status__c, Campaign_Status__c,
            Fundraising_Goal__c, Currency__c, Start_Date__c, End_Date__c,
            Cover_Image__c, Amount_Raised__c, Description__c,
            External_Link__c, Constituent_Role__c,
            Constituent_Role__r.Person.Name, CreatedBy.SmallPhotoUrl
            FROM Ken_Fundraise__c
            WHERE Id = :campaignId
            LIMIT 1
        ];

        Id effectiveRoleId = resolveConstituentRoleId();

        String rejectionReason = null;
        if (r.Approval_Status__c == 'Rejected') {
            List<ProcessInstanceStep> steps = [
                SELECT Comments
                FROM ProcessInstanceStep
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND StepStatus = 'Rejected'
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!steps.isEmpty() && String.isNotBlank(steps[0].Comments)) {
                rejectionReason = steps[0].Comments;
            }
        }

        CampaignDTO dto = new CampaignDTO();
        dto.id              = r.Id;
        dto.name            = r.Name;
        dto.categoryId      = r.Fundraise_Category__c;
        dto.category        = r.Fundraise_Category__r != null ? r.Fundraise_Category__r.Name : null;
        dto.approvalStatus  = r.Approval_Status__c;
        dto.campaignStatus  = r.Campaign_Status__c;
        dto.fundraisingGoal = r.Fundraising_Goal__c;
        dto.currencyCode    = String.isNotBlank(r.Currency__c) ? r.Currency__c : 'INR';
        dto.startDate       = r.Start_Date__c != null ? String.valueOf(r.Start_Date__c) : null;
        dto.endDate         = r.End_Date__c   != null ? String.valueOf(r.End_Date__c)   : null;
        dto.coverImage      = r.Cover_Image__c;
        dto.amountRaised    = r.Amount_Raised__c;
        dto.description     = r.Description__c;
        dto.ownerName       = r.Constituent_Role__r != null ? r.Constituent_Role__r.Person?.Name : null;
        dto.ownerPhotoUrl   = r.CreatedBy?.SmallPhotoUrl;
        dto.externalLink    = r.External_Link__c;
        dto.isOwner         = (effectiveRoleId != null && r.Constituent_Role__c == effectiveRoleId);
        dto.isAdmin         = isCurrentUserFundraiseAdmin();
        dto.rejectionReason = rejectionReason;
        return dto;
    }

    @AuraEnabled
    public static void updateCampaign(Id campaignId, FundraiseRequest request) {
        try {
            if (campaignId == null) throw new AuraHandledException('Campaign ID is required.');
            if (request == null)    throw new AuraHandledException('No data provided.');

            Id effectiveRoleId = resolveConstituentRoleId();
            Boolean isInternal = isInternalUser();
            if (effectiveRoleId == null && !isInternal) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c existing = [
                SELECT Id, Constituent_Role__c, Cover_Image__c
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!isInternal && existing.Constituent_Role__c != effectiveRoleId) {
                throw new AuraHandledException('You can only edit your own campaigns.');
            }

            String coverUrl = existing.Cover_Image__c;
            if (request.coverImageUrl != null) {
                coverUrl = request.coverImageUrl.startsWith('data:')
                    ? uploadAndLinkImage(request.name.trim() + '_cover', request.coverImageUrl, campaignId)
                    : request.coverImageUrl;
            } else {
                coverUrl = null;
            }

            existing.Name                = request.name.trim();
            existing.Fundraise_Category__c = request.categoryId;
            existing.Description__c      = request.description;
            existing.Currency__c         = String.isNotBlank(request.currencyCode) ? request.currencyCode : 'INR';
            existing.Fundraising_Goal__c = request.fundraisingGoal;
            existing.Collection_Method__c = request.collectionMethod;
            existing.External_Link__c    = request.externalLink;
            existing.Start_Date__c       = parseDate(request.startDate);
            existing.End_Date__c         = parseDate(request.endDate);
            existing.Cover_Image__c      = coverUrl;
            if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
            }
            update existing;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    @AuraEnabled
    public static void finalizeAndSubmitCampaign(Id campaignId, FundraiseRequest request) {
        try {
            if (campaignId == null) throw new AuraHandledException('Campaign ID is required.');
            if (request == null)    throw new AuraHandledException('No data provided.');

            Id effectiveRoleId = resolveConstituentRoleId();
            Boolean isInternal = isInternalUser();
            if (effectiveRoleId == null && !isInternal) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c existing = [
                SELECT Id, Constituent_Role__c, Cover_Image__c, Approval_Status__c, OwnerId
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!isInternal && existing.Constituent_Role__c != effectiveRoleId) {
                throw new AuraHandledException('You can only submit your own campaigns.');
            }
            String priorApprovalStatus = existing.Approval_Status__c;

            String coverUrl = existing.Cover_Image__c;
            if (request.coverImageUrl != null) {
                coverUrl = request.coverImageUrl.startsWith('data:')
                    ? uploadAndLinkImage(request.name.trim() + '_cover', request.coverImageUrl, campaignId)
                    : request.coverImageUrl;
            } else {
                coverUrl = null;
            }

            List<ProcessInstance> pendingPIs = [
                SELECT Id, (SELECT Id FROM Workitems)
                FROM ProcessInstance
                WHERE TargetObjectId = :campaignId AND Status = 'Pending'
            WITH SYSTEM_MODE
            ];
            for (ProcessInstance pi : pendingPIs) {
                if (!pi.Workitems.isEmpty()) {
                    try {
                        Approval.ProcessWorkitemRequest recall = new Approval.ProcessWorkitemRequest();
                        recall.setWorkitemId(pi.Workitems[0].Id);
                        recall.setAction('Removed');
                        recall.setComments('Recalled for owner re-edit');
                        Approval.process(recall);
                    } catch (Exception ex) {
                        System.debug('Recall tolerated: ' + ex.getMessage());
                    }
                }
            }

            existing.Name                = request.name.trim();
            existing.Fundraise_Category__c = request.categoryId;
            existing.Description__c      = request.description;
            existing.Currency__c         = String.isNotBlank(request.currencyCode) ? request.currencyCode : 'INR';
            existing.Fundraising_Goal__c = request.fundraisingGoal;
            existing.Collection_Method__c = request.collectionMethod;
            existing.External_Link__c    = request.externalLink;
            existing.Start_Date__c       = parseDate(request.startDate);
            existing.End_Date__c         = parseDate(request.endDate);
            existing.Cover_Image__c      = coverUrl;
            existing.Approval_Status__c  = 'In Review';
            if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
            }
            update existing;

            if (priorApprovalStatus == 'In Review') {
                KenApprovalProcessHelper.submitForApproval(
                    campaignId,
                    'Fundraise_Campaign_Approval_Process',
                    existing.OwnerId,
                    'Resubmitted after owner edit'
                );
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    @AuraEnabled
    public static void deleteCampaign(Id campaignId) {
        try {
            Id effectiveRoleId = resolveConstituentRoleId();
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c campaign = [
                SELECT Id, Name, Constituent_Role__c, Approval_Status__c
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (campaign.Constituent_Role__c != effectiveRoleId) {
                throw new AuraHandledException('You can only request deletion of your own campaigns.');
            }
            if (campaign.Approval_Status__c != 'Approved') {
                throw new AuraHandledException('Only approved campaigns can be deleted.');
            }
            campaign.Approval_Status__c = 'Deletion Requested';
            if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
            }
            update campaign;

            KenApprovalProcessHelper.submitForApproval(
                campaignId, 'Fundraise_Deletion_Approval_Process', null, null
            );
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<CampaignDTO> getDeletionRequests() {
        List<Ken_Fundraise__c> records = [
            SELECT Id, Name, Fundraise_Category__c, Fundraise_Category__r.Name, Campaign_Status__c,
            Fundraising_Goal__c, Currency__c, Start_Date__c, End_Date__c,
            Collection_Method__c,
            Constituent_Role__r.Person.Name, CreatedDate, LastModifiedDate
            FROM Ken_Fundraise__c
            WHERE Approval_Status__c = 'Deletion Requested'
            ORDER BY LastModifiedDate DESC
        ];
        List<CampaignDTO> result = new List<CampaignDTO>();
        for (Ken_Fundraise__c r : records) {
            CampaignDTO dto = new CampaignDTO();
            dto.id              = r.Id;
            dto.name            = r.Name;
            dto.categoryId      = r.Fundraise_Category__c;
            dto.category        = r.Fundraise_Category__r != null ? r.Fundraise_Category__r.Name : null;
            dto.approvalStatus  = 'Deletion Requested';
            dto.campaignStatus  = r.Campaign_Status__c;
            dto.fundraisingGoal = r.Fundraising_Goal__c;
            dto.currencyCode    = String.isNotBlank(r.Currency__c) ? r.Currency__c : 'INR';
            dto.startDate       = r.Start_Date__c != null ? String.valueOf(r.Start_Date__c) : null;
            dto.endDate         = r.End_Date__c   != null ? String.valueOf(r.End_Date__c)   : null;
            dto.ownerName       = r.Constituent_Role__r != null ? r.Constituent_Role__r.Person?.Name : null;
            dto.collectionMethod = r.Collection_Method__c;
            dto.createdDate     = r.CreatedDate != null ? String.valueOf(r.CreatedDate.date()) : null;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void approveDeletion(Id campaignId) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!items.isEmpty()) {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setWorkitemId(items[0].Id);
                req.setAction('Approve');
                req.setComments('Deletion approved by admin.');
                Approval.process(req);
            }
            Ken_Fundraise__c campaign = [
                SELECT Id FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!Schema.sObjectType.Ken_Fundraise__c.isDeletable()) {
                throw new KenCrudException('Ken_Fundraise__c is not deletable by the current user.');
            }
            delete campaign;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void rejectDeletion(Id campaignId) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!items.isEmpty()) {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setWorkitemId(items[0].Id);
                req.setAction('Reject');
                req.setComments('Deletion dismissed by admin.');
                Approval.process(req);
            } else {
                Ken_Fundraise__c campaign = [
                    SELECT Id FROM Ken_Fundraise__c
                    WHERE Id = :campaignId AND Approval_Status__c = 'Deletion Requested'
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                campaign.Approval_Status__c = 'Approved';
                if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
                }
                update campaign;
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFundraiseStatus(Id campaignId) {
        Ken_Fundraise__c r = [
            SELECT Name, Approval_Status__c
            FROM Ken_Fundraise__c WHERE Id = :campaignId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return new Map<String, String>{
            'name'           => r.Name,
            'approvalStatus' => r.Approval_Status__c
        };
    }

    public class CategoryOption {
        @AuraEnabled public Id       id          { get; set; }
        @AuraEnabled public String   name        { get; set; }
        @AuraEnabled public String   imageUrl    { get; set; }
        @AuraEnabled public String   description { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<CategoryOption> getFundraiseCategories() {
        List<CategoryOption> options = new List<CategoryOption>();
        for (Ken_Fundraise_Category__c c : [
            SELECT Id, Name, Image__c, Description__c, CreatedDate
            FROM Ken_Fundraise_Category__c
            WHERE Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ]) {
            CategoryOption opt = new CategoryOption();
            opt.id          = c.Id;
            opt.name        = c.Name;
            opt.createdDate = c.CreatedDate;
            opt.imageUrl    = c.Image__c;
            opt.description = c.Description__c;
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled
    public static String uploadCategoryImage(Id categoryId, String base64) {
        try {
            if (categoryId == null) throw new AuraHandledException('Category ID is required.');
            if (String.isBlank(base64)) throw new AuraHandledException('No image data provided.');

            Ken_Fundraise_Category__c category = [
                SELECT Id, Name FROM Ken_Fundraise_Category__c WHERE Id = :categoryId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            String imageUrl = uploadAndLinkImage(category.Name + '_image', base64, categoryId);
            category.Image__c = imageUrl;
            if (!Schema.sObjectType.Ken_Fundraise_Category__c.isUpdateable()) {
                throw new KenCrudException('Ken_Fundraise_Category__c is not updateable by the current user.');
            }
            update category;
            return imageUrl;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    @AuraEnabled
    public static void approveCampaign(Id campaignId) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!items.isEmpty()) {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setWorkitemId(items[0].Id);
                req.setAction('Approve');
                req.setComments('Approved via admin panel.');
                Approval.process(req);
            } else {
                Ken_Fundraise__c c = [SELECT Id FROM Ken_Fundraise__c WHERE Id = :campaignId WITH SECURITY_ENFORCED LIMIT 1];
                c.Approval_Status__c = 'Approved';
                c.Is_Active__c       = true;
                c.Is_Published__c    = true;
                if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
                }
                update c;
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void rejectCampaign(Id campaignId, String reason) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!items.isEmpty()) {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setWorkitemId(items[0].Id);
                req.setAction('Reject');
                if (String.isNotBlank(reason)) req.setComments(reason);
                Approval.process(req);
            } else {
                Ken_Fundraise__c c = [SELECT Id FROM Ken_Fundraise__c WHERE Id = :campaignId WITH SECURITY_ENFORCED LIMIT 1];
                c.Approval_Status__c = 'Rejected';
                if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
                }
                update c;
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void closeCampaign(Id campaignId) {
        try {
            Id effectiveRoleId = resolveConstituentRoleId();
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c fr = [
                SELECT Id, Campaign_Status__c, Approval_Status__c, Constituent_Role__c, Start_Date__c, End_Date__c
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (fr.Constituent_Role__c != effectiveRoleId) {
                throw new AuraHandledException('Only the campaign owner can close this campaign.');
            }
            if (fr.Approval_Status__c != 'Approved') {
                throw new AuraHandledException('Only approved campaigns can be closed.');
            }
            Date today = Date.today();
            Boolean isOngoing = fr.Start_Date__c != null && fr.Start_Date__c <= today
                && (fr.End_Date__c == null || fr.End_Date__c >= today);
            if (!isOngoing) {
                throw new AuraHandledException('Only ongoing campaigns can be closed.');
            }
            fr.Campaign_Status__c = 'Completed';
            if (!Schema.sObjectType.Ken_Fundraise__c.isUpdateable()) {
                throw new KenCrudException('Ken_Fundraise__c is not updateable by the current user.');
            }
            update fr;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static final Decimal DEFAULT_MINIMUM_CONTRIBUTION = 100;
    private static final String  DEFAULT_SUGGESTED_AMOUNTS    = '500,1000,2000,3000,5000,10000';

    public class ContributionConfig {
        @AuraEnabled public Decimal       minimumAmount          { get; set; }
        @AuraEnabled public List<Decimal> suggestedAmounts       { get; set; }
        @AuraEnabled public String        currencyCode           { get; set; }
        @AuraEnabled public Boolean       acceptingContributions { get; set; }
    }

    public class DonationRequest {
        @AuraEnabled public String  campaignId  { get; set; }
        @AuraEnabled public Decimal amount      { get; set; }
        @AuraEnabled public String  message     { get; set; }
        @AuraEnabled public Boolean isAnonymous { get; set; }
    }

    public class DonationSummary {
        @AuraEnabled public Integer donorCount   { get; set; }
        @AuraEnabled public Decimal amountRaised { get; set; }
    }

    /**
     * @description Amount rules for the Contribute modal plus whether the campaign can take money
     *              right now, so the LWC never has to re-derive the open/closed rule.
     */
    @AuraEnabled(cacheable=true)
    public static ContributionConfig getContributionConfig(Id campaignId) {
        Ken_Fundraise__c campaign = [
            SELECT Id, Currency__c, Approval_Status__c, Campaign_Status__c,
                   Start_Date__c, End_Date__c, External_Link__c
            FROM Ken_Fundraise__c
            WHERE Id = :campaignId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        ContributionConfig config = new ContributionConfig();
        config.currencyCode  = String.isNotBlank(campaign.Currency__c) ? campaign.Currency__c : 'INR';
        config.minimumAmount = DEFAULT_MINIMUM_CONTRIBUTION;
        config.acceptingContributions = isOpenForContributions(campaign);

        config.suggestedAmounts = new List<Decimal>();
        for (String raw : DEFAULT_SUGGESTED_AMOUNTS.split(',')) {
            String trimmed = raw.trim();
            if (String.isBlank(trimmed)) continue;
            try {
                config.suggestedAmounts.add(Decimal.valueOf(trimmed));
            } catch (Exception ignored) {
                continue;
            }
        }
        return config;
    }

    /**
     * @description Records a contribution against a campaign and returns the new donation Id. The
     *              donation lands as Payment Status 'Pending' - it is the payment gateway
     *              confirmation, not this method, that moves it to 'Completed' and makes it count
     *              towards the campaign totals.
     *
     *              Anonymity is enforced by what is NOT written: Constituent_Role__c is left blank
     *              so no portal user reading the donation can resolve a name, and the contributor
     *              survives only as the encrypted Donor_Reference__c.
     */
    @AuraEnabled
    public static Id submitDonation(DonationRequest request) {
        try {
            if (request == null || String.isBlank(request.campaignId)) {
                throw new AuraHandledException('No contribution data provided.');
            }
            Id campaignId = (Id) request.campaignId;

            Id effectiveRoleId = resolveConstituentRoleId();
            if (effectiveRoleId == null) {
                throw new AuraHandledException('We could not identify your alumni profile. Please sign in again.');
            }

            Ken_Fundraise__c campaign = [
                SELECT Id, Currency__c, Approval_Status__c, Campaign_Status__c,
                       Start_Date__c, End_Date__c
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (!isOpenForContributions(campaign)) {
                throw new AuraHandledException('This campaign is not accepting contributions right now.');
            }

            if (request.amount == null || request.amount < DEFAULT_MINIMUM_CONTRIBUTION) {
                throw new AuraHandledException('The minimum contribution is ' + DEFAULT_MINIMUM_CONTRIBUTION.setScale(0) + '.');
            }

            Boolean anonymous = request.isAnonymous == true;
            Ken_Donation__c donation = new Ken_Donation__c(
                Fundraise__c        = campaign.Id,
                Amount__c           = request.amount,
                Currency__c         = String.isNotBlank(campaign.Currency__c) ? campaign.Currency__c : 'INR',
                Donation_Date__c    = Date.today(),
                Message__c          = request.message,
                Payment_Status__c   = 'Pending',
                Is_Anonymous__c     = anonymous,
                Constituent_Role__c = anonymous ? null : effectiveRoleId,
                Donor_Reference__c      = String.valueOf(effectiveRoleId)
            );
            if (!Schema.sObjectType.Ken_Donation__c.isCreateable()) {
                throw new KenCrudException('Ken_Donation__c is not createable by the current user.');
            }
            insert donation;
            return donation.Id;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Live donor count and amount raised for a campaign, counting confirmed payments
     *              only. Anonymous contributions are included in both numbers - it is the
     *              contributor's name that is hidden, never their money.
     */
    @AuraEnabled(cacheable=true)
    public static DonationSummary getDonationSummary(Id campaignId) {
        AggregateResult agg = [
            SELECT COUNT(Id) donorCount, SUM(Amount__c) amountRaised
            FROM Ken_Donation__c
            WHERE Fundraise__c = :campaignId
            AND Payment_Status__c = 'Completed'
        WITH SECURITY_ENFORCED
        ];
        DonationSummary summary = new DonationSummary();
        summary.donorCount   = (Integer) agg.get('donorCount');
        summary.amountRaised = (Decimal) agg.get('amountRaised');
        if (summary.donorCount == null)   summary.donorCount   = 0;
        if (summary.amountRaised == null) summary.amountRaised = 0;
        return summary;
    }

    public class DonorImpact {
        @AuraEnabled public Integer campaignCount          { get; set; }
        @AuraEnabled public Integer liveCampaignCount      { get; set; }
        @AuraEnabled public Integer completedCampaignCount { get; set; }
        @AuraEnabled public Integer causeCount             { get; set; }
        @AuraEnabled public Integer contributionCount      { get; set; }
        @AuraEnabled public Decimal totalRaised            { get; set; }
        @AuraEnabled public Decimal totalGoal              { get; set; }
        @AuraEnabled public String  currencyCode           { get; set; }
    }

    /**
     * @description Portal-wide fundraise totals for the Donor Impact panel, so the panel can never
     *              drift from the data behind it. Campaigns count Approved rows only - the same
     *              published set getPublishedCampaigns shows - and money counts 'Completed'
     *              payments only, the same rule getDonationSummary applies per campaign, so a
     *              pending payment can never inflate the headline. Every figure comes back as a
     *              number rather than null, so the LWC has nothing to guard.
     */
    @AuraEnabled(cacheable=true)
    public static DonorImpact getDonorImpact() {
        DonorImpact impact = new DonorImpact();

        AggregateResult campaigns = [
            SELECT COUNT(Id) campaignCount,
                   COUNT_DISTINCT(Fundraise_Category__c) causeCount,
                   SUM(Fundraising_Goal__c) totalGoal
            FROM Ken_Fundraise__c
            WHERE Approval_Status__c = 'Approved'
        WITH SECURITY_ENFORCED
        ];
        impact.campaignCount = (Integer) campaigns.get('campaignCount');
        impact.causeCount    = (Integer) campaigns.get('causeCount');
        impact.totalGoal     = (Decimal) campaigns.get('totalGoal');

        impact.completedCampaignCount = [
            SELECT COUNT()
            FROM Ken_Fundraise__c
            WHERE Approval_Status__c = 'Approved'
            AND Campaign_Status__c = 'Completed'
        WITH SECURITY_ENFORCED
        ];

        Date today = Date.today();
        impact.liveCampaignCount = [
            SELECT COUNT()
            FROM Ken_Fundraise__c
            WHERE Approval_Status__c = 'Approved'
            AND Campaign_Status__c != 'Completed'
            AND (Start_Date__c = NULL OR Start_Date__c <= :today)
            AND (End_Date__c = NULL OR End_Date__c >= :today)
        WITH SECURITY_ENFORCED
        ];

        AggregateResult donations = [
            SELECT COUNT(Id) contributionCount, SUM(Amount__c) totalRaised
            FROM Ken_Donation__c
            WHERE Payment_Status__c = 'Completed'
        WITH SECURITY_ENFORCED
        ];
        impact.contributionCount = (Integer) donations.get('contributionCount');
        impact.totalRaised       = (Decimal) donations.get('totalRaised');

        impact.currencyCode = resolveDominantCurrency();

        if (impact.campaignCount     == null) impact.campaignCount     = 0;
        if (impact.causeCount        == null) impact.causeCount        = 0;
        if (impact.contributionCount == null) impact.contributionCount = 0;
        if (impact.totalRaised       == null) impact.totalRaised       = 0;
        if (impact.totalGoal         == null) impact.totalGoal         = 0;
        return impact;
    }

    /**
     * @description Currency for the portal-wide totals. Currency__c is per-campaign free text, so
     *              the most-used code across published campaigns wins rather than whichever row
     *              happens to sort first, and an org with nothing published falls back to the same
     *              'INR' default the contribution config uses.
     */
    private static String resolveDominantCurrency() {
        List<AggregateResult> rows = [
            SELECT Currency__c code
            FROM Ken_Fundraise__c
            WHERE Approval_Status__c = 'Approved'
            AND Currency__c != NULL
            WITH SECURITY_ENFORCED
            GROUP BY Currency__c
            ORDER BY COUNT(Id) DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) return 'INR';
        String code = (String) rows[0].get('code');
        return String.isNotBlank(code) ? code : 'INR';
    }

    /**
     * @description Decrypts the contributor behind an anonymous donation. Restricted to fundraise
     *              admins because this is the one path that turns Donor_Reference__c back into a name.
     */
    @AuraEnabled
    public static String revealAnonymousDonor(Id donationId) {
        try {
            if (!isCurrentUserFundraiseAdmin()) {
                throw new AuraHandledException('You do not have permission to reveal contributors.');
            }
            Ken_Donation__c donation = [
                SELECT Id, Donor_Reference__c, Constituent_Role__c
                FROM Ken_Donation__c
                WHERE Id = :donationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            Id roleId = donation.Constituent_Role__c != null
                ? donation.Constituent_Role__c
                : readDonorToken(donation.Donor_Reference__c);
            if (roleId == null) {
                throw new AuraHandledException('This contribution cannot be traced back to a contributor.');
            }
            List<ConstituentRole> roles = [
                SELECT Id, Person.Name FROM ConstituentRole WHERE Id = :roleId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (roles.isEmpty()) {
                throw new AuraHandledException('The contributor record no longer exists.');
            }
            return roles[0].Person?.Name;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Boolean isOpenForContributions(Ken_Fundraise__c campaign) {
        if (campaign.Approval_Status__c != 'Approved')  return false;
        if (campaign.Campaign_Status__c == 'Completed') return false;
        Date today = Date.today();
        if (campaign.Start_Date__c != null && campaign.Start_Date__c > today) return false;
        if (campaign.End_Date__c   != null && campaign.End_Date__c   < today) return false;
        return true;
    }

    /**
     * @description Turns a stored donor token back into a ConstituentRole Id. Donor_Reference__c is a
     *              standard Encrypted Text field, so a caller without View Encrypted Data reads a
     *              masked string rather than an Id - that is not an error, it is the masking doing
     *              its job, and it resolves to nothing instead of throwing.
     */
    @TestVisible
    private static Id readDonorToken(String token) {
        if (String.isBlank(token)) return null;
        try {
            return (Id) token;
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isCurrentUserFundraiseAdmin() {
        Id userId = UserInfo.getUserId();
        User u = [SELECT Profile.Name FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if ('System Administrator'.equalsIgnoreCase(u.Profile.Name)) return true;
        List<GroupMember> members = [
            SELECT Id FROM GroupMember
            WHERE Group.Type = 'Queue'
            AND Group.DeveloperName IN ('Fundraise_Approvers', 'Business_Approvers')
            AND UserOrGroupId = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !members.isEmpty();
    }

    /**
     * @description Effective ConstituentRole for the running user, resolved server-side
     *              from the logged-in user via KenConstituentRoleService (role with the
     *              latest Last_Login__c wins).
     */
    private static Id resolveConstituentRoleId() {
        return KenConstituentRoleService.getActiveConstituentRoleId();
    }

    /**
     * @description Internal Salesforce users (System Admin, internal staff) have no AccountId
     *              and no ConstituentRole, so role-scoped requirements are relaxed for them.
     */
    @TestVisible private static Boolean testIsInternalUser = null;

    private static Boolean isInternalUser() {
        if (testIsInternalUser != null) return testIsInternalUser;
        User u = [SELECT Id, UserType, AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        return u.AccountId == null || u.UserType == 'Standard';
    }

    /**
     * @description Uploads a base64 image as a ContentVersion and links it to the given record via
     *              ContentDocumentLink (AllUsers visibility) — the same pattern KenGalleryController
     *              uses. ContentDistribution (used by the older KenCreateContentVersion helper) is
     *              deliberately avoided here: Experience Cloud users get
     *              INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY on ContentDistribution's NetworkId
     *              lookup, so cover/category images never saved for them.
     */
    private static String uploadAndLinkImage(String title, String base64DataUri, Id linkedRecordId) {
        String base64Data = base64DataUri;
        Integer commaIdx = base64DataUri.indexOf(',');
        if (base64DataUri.startsWith('data:') && commaIdx >= 0) {
            base64Data = base64DataUri.substring(commaIdx + 1);
        }
        ContentVersion cv = new ContentVersion(
            Title        = title,
            PathOnClient = title,
            VersionData  = EncodingUtil.base64Decode(base64Data)
        );
        Database.insert(cv, true, AccessLevel.SYSTEM_MODE);
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE LIMIT 1].ContentDocumentId;
        Database.insert(new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = linkedRecordId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        ), true, AccessLevel.SYSTEM_MODE);
        return URL.getOrgDomainUrl().toExternalForm() + '/sfc/servlet.shepherd/version/download/' + cv.Id;
    }

    private static Date parseDate(String dateStr) {
        if (String.isBlank(dateStr)) return null;
        try {
            return Date.valueOf(dateStr);
        } catch (Exception e) {
            return null;
        }
    }
}