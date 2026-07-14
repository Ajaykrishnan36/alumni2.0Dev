/**
 * Reusable lookups + formatting helpers for the group-feed surface area.
 * Kept thin in Slice 1; will host notification dispatch + scheduler logic in later slices.
 */
public without sharing class KenGroupFeedService {

    public static Map<Id, String> lookupProfileImages(Set<Id> accountIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) return out;
        for (Ken_Alumni_CRM__c crm : [
            SELECT Person_Account__c, Profile_Photo_URL__c
            FROM Ken_Alumni_CRM__c
            WHERE Person_Account__c IN :accountIds
            ORDER BY LastModifiedDate DESC
        ]) {
            if (String.isNotBlank(crm.Profile_Photo_URL__c) && !out.containsKey(crm.Person_Account__c)) {
                out.put(crm.Person_Account__c, crm.Profile_Photo_URL__c);
            }
        }
        Set<Id> stillNeed = new Set<Id>();
        for (Id aid : accountIds) if (!out.containsKey(aid)) stillNeed.add(aid);
        if (!stillNeed.isEmpty()) {
            String orgDomain = URL.getOrgDomainUrl().toExternalForm();
            for (Account a : [SELECT Id, PhotoUrl FROM Account WHERE Id IN :stillNeed AND PhotoUrl != null]) {
                out.put(a.Id, orgDomain + a.PhotoUrl);
            }
        }
        return out;
    }

    public static Map<Id, String> lookupBatchLabels(Set<Id> accountIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) return out;
        for (Ken_Alumni_CRM__c crm : [
            SELECT Person_Account__c, Year_of_Graduation__c
            FROM Ken_Alumni_CRM__c
            WHERE Person_Account__c IN :accountIds AND Year_of_Graduation__c != null
            ORDER BY LastModifiedDate DESC
        ]) {
            if (!out.containsKey(crm.Person_Account__c)) {
                out.put(crm.Person_Account__c, 'Batch - ' + crm.Year_of_Graduation__c);
            }
        }
        return out;
    }

    public static Map<Id, List<KenGroupFeedController.AttachmentDTO>> lookupAttachments(Set<Id> feedItemIds) {
        Map<Id, List<KenGroupFeedController.AttachmentDTO>> out = new Map<Id, List<KenGroupFeedController.AttachmentDTO>>();
        if (feedItemIds == null || feedItemIds.isEmpty()) return out;

        Map<Id, Id> documentToFeedItem = new Map<Id, Id>();
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :feedItemIds
        ]) {
            documentToFeedItem.put(link.ContentDocumentId, link.LinkedEntityId);
            documentIds.add(link.ContentDocumentId);
        }
        if (documentIds.isEmpty()) return out;

        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId, Title, FileType, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds AND IsLatest = true
        ]) {
            Id feedItemId = documentToFeedItem.get(cv.ContentDocumentId);
            if (feedItemId == null) continue;
            KenGroupFeedController.AttachmentDTO dto = new KenGroupFeedController.AttachmentDTO();
            dto.contentVersionId  = cv.Id;
            dto.contentDocumentId = cv.ContentDocumentId;
            dto.fileName          = cv.Title;
            dto.fileType          = cv.FileType;
            dto.isImage           = isImageType(cv.FileType, cv.FileExtension);
            dto.downloadUrl       = '/sfc/servlet.shepherd/version/download/' + cv.Id;
            dto.previewUrl        = dto.isImage
                ? '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + cv.Id
                : null;
            if (!out.containsKey(feedItemId)) out.put(feedItemId, new List<KenGroupFeedController.AttachmentDTO>());
            out.get(feedItemId).add(dto);
        }
        return out;
    }

    private static Boolean isImageType(String fileType, String fileExtension) {
        if (String.isNotBlank(fileType)) {
            String f = fileType.toUpperCase();
            if (f == 'JPG' || f == 'JPEG' || f == 'PNG' || f == 'GIF' || f == 'WEBP' || f == 'BMP' || f == 'SVG') return true;
        }
        if (String.isNotBlank(fileExtension)) {
            String ex = fileExtension.toLowerCase();
            if (ex == 'jpg' || ex == 'jpeg' || ex == 'png' || ex == 'gif' || ex == 'webp' || ex == 'bmp' || ex == 'svg') return true;
        }
        return false;
    }

    public static Map<Id, KenGroupFeedController.PollDTO> lookupPolls(Set<Id> feedItemIds, Id currentUserId) {
        Map<Id, KenGroupFeedController.PollDTO> out = new Map<Id, KenGroupFeedController.PollDTO>();
        if (feedItemIds == null || feedItemIds.isEmpty()) return out;

        // Feed_Item__c is Text(18); the controller writes the 18-char Id, but match both lengths to be safe.
        Set<String> feedItemKeys = new Set<String>();
        for (Id fid : feedItemIds) {
            feedItemKeys.add(String.valueOf(fid));
            feedItemKeys.add(String.valueOf(fid).substring(0, 15));
        }

        List<Ken_Questionnaire_Parameter__c> qps = [
            SELECT Id, Feed_Item__c, Question_Label__c, MCQ_Options__c, Ends_At__c, Duration_Days__c
            FROM Ken_Questionnaire_Parameter__c
            WHERE Feed_Item__c IN :feedItemKeys
        ];
        if (qps.isEmpty()) return out;

        Set<Id> qpIds = new Set<Id>();
        for (Ken_Questionnaire_Parameter__c qp : qps) qpIds.add(qp.Id);

        // Response__c is Long Text Area — Salesforce blocks WHERE/GROUP BY on it. Pull all
        // votes for the polls in one query and aggregate in memory (poll-scale, low cardinality).
        Map<Id, Map<String, Integer>> votesByOptionPerPoll = new Map<Id, Map<String, Integer>>();
        Map<Id, Integer> totalVotesPerPoll = new Map<Id, Integer>();
        for (Ken_Questionnaire_Parameter_Response__c r : [
            SELECT Questionnaire_Parameter__c, Response__c
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__c IN :qpIds
        ]) {
            if (String.isBlank(r.Response__c)) continue;
            Id pid = r.Questionnaire_Parameter__c;
            String op = r.Response__c.trim();
            if (!votesByOptionPerPoll.containsKey(pid)) votesByOptionPerPoll.put(pid, new Map<String, Integer>());
            Map<String, Integer> bucket = votesByOptionPerPoll.get(pid);
            bucket.put(op, (bucket.containsKey(op) ? bucket.get(op) : 0) + 1);
            totalVotesPerPoll.put(pid, (totalVotesPerPoll.containsKey(pid) ? totalVotesPerPoll.get(pid) : 0) + 1);
        }

        // The current user's vote per poll (if any). Respondent is an Account (Person Account).
        Map<Id, String> myVoteByPoll = new Map<Id, String>();
        Id myAccountId = currentUserAccountId(currentUserId);
        if (myAccountId != null) {
            for (Ken_Questionnaire_Parameter_Response__c r : [
                SELECT Questionnaire_Parameter__c, Response__c
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Questionnaire_Parameter__c IN :qpIds AND Respondent__c = :myAccountId
            ]) {
                myVoteByPoll.put(r.Questionnaire_Parameter__c, r.Response__c);
            }
        }

        for (Ken_Questionnaire_Parameter__c qp : qps) {
            KenGroupFeedController.PollDTO dto = new KenGroupFeedController.PollDTO();
            dto.pollId      = qp.Id;
            dto.question    = qp.Question_Label__c;
            dto.endsAt      = qp.Ends_At__c;
            dto.isClosed    = qp.Ends_At__c != null && qp.Ends_At__c < Datetime.now();
            Integer total   = totalVotesPerPoll.containsKey(qp.Id) ? totalVotesPerPoll.get(qp.Id) : 0;
            dto.totalVotes  = total;
            String myResp   = myVoteByPoll.get(qp.Id);
            dto.hasVoted    = String.isNotBlank(myResp);
            dto.options     = new List<KenGroupFeedController.PollOptionDTO>();

            Map<String, Integer> votesForThisPoll = votesByOptionPerPoll.containsKey(qp.Id)
                ? votesByOptionPerPoll.get(qp.Id) : new Map<String, Integer>();
            Integer order = 1;
            if (String.isNotBlank(qp.MCQ_Options__c)) {
                for (String optText : qp.MCQ_Options__c.split(';')) {
                    String trimmed = optText.trim();
                    if (String.isBlank(trimmed)) continue;
                    KenGroupFeedController.PollOptionDTO odto = new KenGroupFeedController.PollOptionDTO();
                    odto.optionId    = trimmed; // the text doubles as a stable identifier per poll
                    odto.optionText  = trimmed;
                    odto.order_x     = order++;
                    Integer c        = votesForThisPoll.containsKey(trimmed) ? votesForThisPoll.get(trimmed) : 0;
                    odto.voteCount   = c;
                    odto.votePercent = total == 0 ? 0 : Math.round(100.0 * c / total);
                    odto.votedByMe   = myResp == trimmed;
                    dto.options.add(odto);
                }
            }

            Id feedItemId18 = null;
            if (String.isNotBlank(qp.Feed_Item__c)) {
                try { feedItemId18 = Id.valueOf(qp.Feed_Item__c); } catch (Exception e) { /* skip */ }
            }
            if (feedItemId18 != null) out.put(feedItemId18, dto);
        }
        return out;
    }

    private static Id currentUserAccountId(Id userId) {
        if (userId == null) return null;
        List<User> us = [SELECT AccountId, ContactId FROM User WHERE Id = :userId LIMIT 1];
        if (us.isEmpty()) return null;
        if (us[0].AccountId != null) return us[0].AccountId;
        if (us[0].ContactId != null) {
            List<Contact> cs = [SELECT AccountId FROM Contact WHERE Id = :us[0].ContactId LIMIT 1];
            if (!cs.isEmpty()) return cs[0].AccountId;
        }
        return null;
    }

    public static String relativeTime(DateTime dt) {
        if (dt == null) return '';
        Long diffMs   = Datetime.now().getTime() - dt.getTime();
        Long diffMin  = diffMs / 60000;
        if (diffMin < 1)    return 'Just now';
        if (diffMin < 60)   return diffMin + 'm';
        Long diffHr   = diffMin / 60;
        if (diffHr  < 24)   return diffHr + 'h';
        Long diffDay  = diffHr / 24;
        if (diffDay < 7)    return diffDay + 'd';
        return dt.format('d MMM yyyy');
    }
}