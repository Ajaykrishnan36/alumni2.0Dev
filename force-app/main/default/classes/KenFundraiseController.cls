public without sharing class KenFundraiseController {

    @TestVisible
    private static Id testCurrentAccountId;
    @TestVisible
    private static Id testCurrentRoleId;

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
    public static List<CampaignDTO> getMyCampaigns(Id constituentRoleId) {
        Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
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
    public static List<CampaignDTO> getAdminFundraiseList(Id constituentRoleId) {
        List<Ken_Fundraise__c> records = [
            SELECT Id, Name, Fundraise_Category__c, Fundraise_Category__r.Name, Approval_Status__c, Campaign_Status__c,
                   Fundraising_Goal__c, Currency__c, Start_Date__c, End_Date__c,
                   Cover_Image__c, Amount_Raised__c, Description__c,
                   Collection_Method__c, Constituent_Role__r.Person.Name
            FROM Ken_Fundraise__c
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
    public static Id createCampaign(FundraiseRequest request, Id constituentRoleId) {
        try {
            if (request == null) {
                throw new AuraHandledException('No data provided.');
            }
            if (String.isBlank(request.name)) {
                throw new AuraHandledException('Campaign name is required.');
            }

            Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }

            String directCoverUrl = (String.isNotBlank(request.coverImageUrl) && !request.coverImageUrl.startsWith('data:'))
                ? request.coverImageUrl
                : null;

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
                Constituent_Role__c = effectiveRoleId
            );
            insert campaign;

            if (String.isNotBlank(request.coverImageUrl) && request.coverImageUrl.startsWith('data:')) {
                campaign.Cover_Image__c = uploadAndLinkImage(
                    request.name.trim() + '_cover', request.coverImageUrl, campaign.Id
                );
                update campaign;
            }

            if (request.segmentationIds != null && !request.segmentationIds.isEmpty()) {
                List<Ken_Fundraise_Segmentation__c> links = new List<Ken_Fundraise_Segmentation__c>();
                for (String segId : request.segmentationIds) {
                    if (String.isNotBlank(segId)) {
                        links.add(new Ken_Fundraise_Segmentation__c(
                            Fundraise__c    = campaign.Id,
                            Segmentation__c = segId
                        ));
                    }
                }
                if (!links.isEmpty()) {
                    insert links;
                }
            }

            return campaign.Id;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    @AuraEnabled(cacheable=true)
    public static CampaignDTO getCampaignById(Id campaignId, Id constituentRoleId) {
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

        Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);

        String rejectionReason = null;
        if (r.Approval_Status__c == 'Rejected') {
            List<ProcessInstanceStep> steps = [
                SELECT Comments
                FROM ProcessInstanceStep
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND StepStatus = 'Rejected'
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
    public static void updateCampaign(Id campaignId, FundraiseRequest request, Id constituentRoleId) {
        try {
            if (campaignId == null) throw new AuraHandledException('Campaign ID is required.');
            if (request == null)    throw new AuraHandledException('No data provided.');

            Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c existing = [
                SELECT Id, Constituent_Role__c, Cover_Image__c
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                LIMIT 1
            ];
            if (existing.Constituent_Role__c != effectiveRoleId) {
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
            update existing;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    @AuraEnabled
    public static void finalizeAndSubmitCampaign(Id campaignId, FundraiseRequest request, Id constituentRoleId) {
        try {
            if (campaignId == null) throw new AuraHandledException('Campaign ID is required.');
            if (request == null)    throw new AuraHandledException('No data provided.');

            Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c existing = [
                SELECT Id, Constituent_Role__c, Cover_Image__c, Approval_Status__c, OwnerId
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                LIMIT 1
            ];
            if (existing.Constituent_Role__c != effectiveRoleId) {
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
    public static void deleteCampaign(Id campaignId, Id constituentRoleId) {
        try {
            Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c campaign = [
                SELECT Id, Name, Constituent_Role__c, Approval_Status__c
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
                LIMIT 1
            ];
            if (campaign.Constituent_Role__c != effectiveRoleId) {
                throw new AuraHandledException('You can only request deletion of your own campaigns.');
            }
            if (campaign.Approval_Status__c != 'Approved') {
                throw new AuraHandledException('Only approved campaigns can be deleted.');
            }
            campaign.Approval_Status__c = 'Deletion Requested';
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
    public static List<CampaignDTO> getDeletionRequests(Id constituentRoleId) {
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
    public static void approveDeletion(Id campaignId, Id constituentRoleId) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
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
                LIMIT 1
            ];
            delete campaign;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void rejectDeletion(Id campaignId, Id constituentRoleId) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
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
                    LIMIT 1
                ];
                campaign.Approval_Status__c = 'Approved';
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
            FROM Ken_Fundraise__c WHERE Id = :campaignId LIMIT 1
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
                SELECT Id, Name FROM Ken_Fundraise_Category__c WHERE Id = :categoryId LIMIT 1
            ];

            String imageUrl = uploadAndLinkImage(category.Name + '_image', base64, categoryId);
            category.Image__c = imageUrl;
            update category;
            return imageUrl;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at line ' + e.getLineNumber());
        }
    }

    @AuraEnabled
    public static void approveCampaign(Id campaignId, Id constituentRoleId) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
                LIMIT 1
            ];
            if (!items.isEmpty()) {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setWorkitemId(items[0].Id);
                req.setAction('Approve');
                req.setComments('Approved via admin panel.');
                Approval.process(req);
            } else {
                Ken_Fundraise__c c = [SELECT Id FROM Ken_Fundraise__c WHERE Id = :campaignId LIMIT 1];
                c.Approval_Status__c = 'Approved';
                c.Is_Active__c       = true;
                c.Is_Published__c    = true;
                update c;
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void rejectCampaign(Id campaignId, String reason, Id constituentRoleId) {
        try {
            List<ProcessInstanceWorkitem> items = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :campaignId
                AND ProcessInstance.Status = 'Pending'
                LIMIT 1
            ];
            if (!items.isEmpty()) {
                Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                req.setWorkitemId(items[0].Id);
                req.setAction('Reject');
                if (String.isNotBlank(reason)) req.setComments(reason);
                Approval.process(req);
            } else {
                Ken_Fundraise__c c = [SELECT Id FROM Ken_Fundraise__c WHERE Id = :campaignId LIMIT 1];
                c.Approval_Status__c = 'Rejected';
                update c;
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void closeCampaign(Id campaignId, Id constituentRoleId) {
        try {
            Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            Ken_Fundraise__c fr = [
                SELECT Id, Campaign_Status__c, Approval_Status__c, Constituent_Role__c, Start_Date__c, End_Date__c
                FROM Ken_Fundraise__c
                WHERE Id = :campaignId
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
            update fr;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Boolean isCurrentUserFundraiseAdmin() {
        Id userId = UserInfo.getUserId();
        User u = [SELECT Profile.Name FROM User WHERE Id = :userId LIMIT 1];
        if ('System Administrator'.equalsIgnoreCase(u.Profile.Name)) return true;
        List<GroupMember> members = [
            SELECT Id FROM GroupMember
            WHERE Group.Type = 'Queue'
            AND Group.DeveloperName IN ('Fundraise_Approvers', 'Business_Approvers')
            AND UserOrGroupId = :userId
            LIMIT 1
        ];
        return !members.isEmpty();
    }

    private static Id fetchCurrentAccountId() {
        if (Test.isRunningTest() && testCurrentAccountId != null) {
            return testCurrentAccountId;
        }
        User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return u.AccountId;
    }

    private static Id fetchLatestAlumniConstituentRoleId(Id currentAccountId) {
        if (currentAccountId == null) {
            return null;
        }
        List<ConstituentRole> roles = [
            SELECT Id
            FROM ConstituentRole
            WHERE PersonId = :currentAccountId
            AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return roles.isEmpty() ? null : roles[0].Id;
    }

    private static Id resolveConstituentRoleId(Id constituentRoleId) {
        if (Test.isRunningTest() && testCurrentRoleId != null) {
            return testCurrentRoleId;
        }
        if (constituentRoleId != null) {
            return constituentRoleId;
        }
        Id accountId = fetchCurrentAccountId();
        if (accountId == null) {
            return null;
        }
        return fetchLatestAlumniConstituentRoleId(accountId);
    }

    /**
     * @description Internal Salesforce users (System Admin, internal staff) have no AccountId
     *              and no ConstituentRole, so role-scoped requirements are relaxed for them.
     */
    private static Boolean isInternalUser() {
        User u = [SELECT Id, UserType, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
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
        insert cv;
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = linkedRecordId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
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