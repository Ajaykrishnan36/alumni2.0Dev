public without sharing class KenServiceSupportV2Controller {

    public class FaqItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String q;
        @AuraEnabled public String a;
        @AuraEnabled public String category;
    }

    public class TicketReply {
        @AuraEnabled public Id id;
        @AuraEnabled public String who;
        @AuraEnabled public String whenStr;
        @AuraEnabled public String text;
    }

    public class CaseItem {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String id;          // Friendly id (#REQ-x or #x)
        @AuraEnabled public String title;       // Subject
        @AuraEnabled public String subject;     // Subject (alias)
        @AuraEnabled public String category;
        @AuraEnabled public String status;
        @AuraEnabled public String statusKey;
        @AuraEnabled public String priority;
        @AuraEnabled public String dateStr;
        @AuraEnabled public List<TicketReply> history;
    }

    @AuraEnabled(cacheable=true)
    public static List<CaseItem> getMyServiceRequests() {
        return queryCases('Service_Request', false);
    }

    @AuraEnabled(cacheable=true)
    public static List<CaseItem> getMySupportTickets() {
        return queryCases('Support_Ticket', true);
    }

    private static List<CaseItem> queryCases(String rtDevName, Boolean includeComments) {
        Id contactId = getCurrentContactId();
        List<CaseItem> out = new List<CaseItem>();
        if (contactId == null) return out;
        List<Case> cases;
        if (includeComments) {
            cases = [
                SELECT Id, CaseNumber, Subject, Status, Priority, Category__c, Friendly_Id__c, Status_Key__c,
                       CreatedDate, Description,
                       (SELECT Id, CommentBody, CreatedDate, CreatedBy.Name FROM CaseComments ORDER BY CreatedDate ASC)
                FROM Case
                WHERE ContactId = :contactId AND RecordType.DeveloperName = :rtDevName
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        } else {
            cases = [
                SELECT Id, CaseNumber, Subject, Status, Priority, Category__c, Friendly_Id__c, Status_Key__c,
                       CreatedDate, Description
                FROM Case
                WHERE ContactId = :contactId AND RecordType.DeveloperName = :rtDevName
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
        }
        for (Case c : cases) {
            CaseItem item = new CaseItem();
            item.recordId = c.Id;
            item.id = c.Friendly_Id__c != null ? c.Friendly_Id__c : '#' + c.CaseNumber;
            item.title = c.Subject;
            item.subject = c.Subject;
            item.category = c.Category__c;
            item.status = c.Status;
            item.statusKey = c.Status_Key__c != null ? c.Status_Key__c : 'open';
            item.priority = c.Priority;
            item.dateStr = c.CreatedDate != null ? c.CreatedDate.format('dd MMM yyyy') : '';
            item.history = new List<TicketReply>();
            if (includeComments) {
                // Seed with original description as the first message
                if (String.isNotBlank(c.Description)) {
                    TicketReply seed = new TicketReply();
                    seed.id = c.Id;
                    seed.who = 'You';
                    seed.whenStr = c.CreatedDate != null ? c.CreatedDate.format('dd MMM yyyy') : '';
                    seed.text = c.Description;
                    item.history.add(seed);
                }
                if (c.CaseComments != null) {
                    for (CaseComment cc : c.CaseComments) {
                        TicketReply r = new TicketReply();
                        r.id = cc.Id;
                        r.who = (cc.CreatedBy != null && cc.CreatedBy.Name != null) ? cc.CreatedBy.Name : 'Support';
                        r.whenStr = cc.CreatedDate != null ? cc.CreatedDate.format('dd MMM yyyy') : '';
                        r.text = cc.CommentBody;
                        item.history.add(r);
                    }
                }
            }
            out.add(item);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<FaqItem> getFAQs() {
        List<FaqItem> out = new List<FaqItem>();
        for (Ken_FAQ__c f : [
            SELECT Id, Question__c, Answer__c, Category__c, Display_Order__c
            FROM Ken_FAQ__c
            WHERE Is_Published__c = true
            ORDER BY Display_Order__c ASC NULLS LAST, CreatedDate ASC
            LIMIT 200
        ]) {
            FaqItem fi = new FaqItem();
            fi.id = f.Id;
            fi.q = f.Question__c;
            fi.a = f.Answer__c;
            fi.category = f.Category__c;
            out.add(fi);
        }
        return out;
    }

    @AuraEnabled
    public static CaseItem createSupportTicket(Map<String, Object> payload) {
        return createCase(payload, 'Support_Ticket');
    }

    @AuraEnabled
    public static CaseItem createServiceRequest(Map<String, Object> payload) {
        return createCase(payload, 'Service_Request');
    }

    private static CaseItem createCase(Map<String, Object> payload, String rtDevName) {
        if (payload == null) {
            throw new AuraHandledException('Missing payload');
        }
        Id contactId = getCurrentContactId();
        Id rtId = getCaseRecordTypeId(rtDevName);
        // Validate required input up-front so the user gets a clear message
        // instead of a raw DML/validation-rule error.
        String subject = payload.get('subject') != null
            ? String.valueOf(payload.get('subject'))
            : (payload.get('title') != null ? String.valueOf(payload.get('title')) : null);
        if (String.isBlank(subject)) {
            throw new AuraHandledException('Please enter a subject for your request.');
        }
        if (!Schema.sObjectType.Case.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create a case. Please contact support.');
        }

        Case c = new Case();
        c.RecordTypeId = rtId;
        if (contactId != null) c.ContactId = contactId;
        c.Subject = subject;
        c.Description = String.valueOf(payload.get('description'));
        Object cat = payload.get('category');
        if (cat != null && String.isNotBlank(String.valueOf(cat))) c.Category__c = String.valueOf(cat);
        Object pri = payload.get('priority');
        if (pri != null && String.isNotBlank(String.valueOf(pri))) c.Priority = String.valueOf(pri);
        c.Origin = 'Web';
        c.Status = 'New';

        try {
            insert c;
        } catch (DmlException e) {
            // Surface the precise reason (validation rule, required field, FLS).
            throw new AuraHandledException('Could not submit your request: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Could not submit your request. ' + e.getMessage());
        }
        List<CaseItem> items = queryCases(rtDevName, rtDevName == 'Support_Ticket');
        for (CaseItem ci : items) {
            if (ci.recordId == c.Id) return ci;
        }
        // fallback minimal
        CaseItem ci = new CaseItem();
        ci.recordId = c.Id;
        ci.id = '#' + c.Id;
        ci.title = c.Subject;
        ci.subject = c.Subject;
        ci.status = c.Status;
        ci.statusKey = 'open';
        ci.dateStr = Datetime.now().format('dd MMM yyyy');
        ci.history = new List<TicketReply>();
        return ci;
    }

    @AuraEnabled
    public static TicketReply addTicketReply(Id caseId, String body) {
        if (caseId == null || String.isBlank(body)) {
            throw new AuraHandledException('Case Id and body are required');
        }
        CaseComment cc = new CaseComment();
        cc.ParentId = caseId;
        cc.CommentBody = body;
        cc.IsPublished = true;
        insert cc;
        TicketReply r = new TicketReply();
        r.id = cc.Id;
        r.who = 'You';
        r.whenStr = 'Just now';
        r.text = body;
        return r;
    }

    private static Id getCurrentContactId() {
        Id userId = UserInfo.getUserId();
        List<User> us = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
        return us.isEmpty() ? null : us[0].ContactId;
    }

    private static Id getCaseRecordTypeId(String devName) {
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        Map<String, Schema.RecordTypeInfo> byDev = d.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo rti = byDev.get(devName);
        if (rti == null) {
            throw new AuraHandledException('Record type not found: ' + devName);
        }
        return rti.getRecordTypeId();
    }

    /* ============================================================= *
     *  SERVICE CATALOG (Phase 2) — Ken_Service__c → Ken_Service_Offering__c
     * ============================================================= */
    public class ServiceOffering {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
    }
    public class ServiceCategory {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public Integer offeringCount;
        @AuraEnabled public List<ServiceOffering> offerings;
    }

    @AuraEnabled(cacheable=true)
    public static List<ServiceCategory> getServiceCatalog() {
        Map<Id, ServiceCategory> byId = new Map<Id, ServiceCategory>();
        for (Ken_Service__c s : [
            SELECT Id, Name, Description__c FROM Ken_Service__c ORDER BY Name ASC LIMIT 500
        ]) {
            ServiceCategory c = new ServiceCategory();
            c.id = s.Id; c.name = s.Name; c.description = s.Description__c;
            c.offerings = new List<ServiceOffering>(); c.offeringCount = 0;
            byId.put(s.Id, c);
        }
        if (!byId.isEmpty()) {
            for (Ken_Service_Offering__c o : [
                SELECT Id, Name, Description__c, Service__c
                FROM Ken_Service_Offering__c
                WHERE Service__c IN :byId.keySet()
                ORDER BY Name ASC LIMIT 2000
            ]) {
                ServiceCategory c = byId.get(o.Service__c);
                if (c != null) {
                    ServiceOffering so = new ServiceOffering();
                    so.id = o.Id; so.name = o.Name; so.description = o.Description__c;
                    c.offerings.add(so);
                    c.offeringCount = c.offerings.size();
                }
            }
        }
        return byId.values();
    }

    /* ============================================================= *
     *  FILE UPLOAD (Phase 2) — ContentVersion + ContentDocumentLink
     * ============================================================= */
    @AuraEnabled
    public static Id uploadCaseAttachment(Id caseId, String base64Data, String filename) {
        if (caseId == null || String.isBlank(base64Data)) {
            throw new AuraHandledException('A case and file are required.');
        }
        String safeName = String.isBlank(filename) ? 'attachment' : filename;
        ContentVersion cv = new ContentVersion();
        cv.Title = safeName;
        cv.PathOnClient = safeName;
        cv.VersionData = EncodingUtil.base64Decode(base64Data);
        cv.Origin = 'H';
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = cdId,
            LinkedEntityId = caseId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert link;
        return cdId;
    }

    /* ============================================================= *
     *  TICKET DETAIL (Phase 3) — requirement, admin reply, documents
     * ============================================================= */
    public class CaseDoc {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String url;
        @AuraEnabled public String ext;
    }
    public class CaseDetail {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String id;
        @AuraEnabled public String subject;
        @AuraEnabled public String category;
        @AuraEnabled public String status;
        @AuraEnabled public String statusKey;
        @AuraEnabled public String recordType;
        @AuraEnabled public String requirement;
        @AuraEnabled public String adminReply;
        @AuraEnabled public String dateStr;
        @AuraEnabled public String closedDateStr;
        @AuraEnabled public Boolean canCancel;
        @AuraEnabled public Boolean canFeedback;
        @AuraEnabled public List<TicketReply> history;
        @AuraEnabled public List<CaseDoc> documents;
    }

    @AuraEnabled(cacheable=true)
    public static CaseDetail getCaseDetail(Id caseId) {
        if (caseId == null) throw new AuraHandledException('Request Id is required.');
        Id contactId = getCurrentContactId();
        List<Case> cs = [
            SELECT Id, CaseNumber, Subject, Status, Priority, Category__c, Friendly_Id__c, Status_Key__c,
                   CreatedDate, ClosedDate, Description, ContactId, RecordType.DeveloperName,
                   (SELECT Id, CommentBody, CreatedDate, CreatedBy.Name, CreatedById
                    FROM CaseComments WHERE IsPublished = true ORDER BY CreatedDate ASC)
            FROM Case WHERE Id = :caseId LIMIT 1
        ];
        if (cs.isEmpty()) throw new AuraHandledException('Request not found.');
        Case c = cs[0];
        if (contactId != null && c.ContactId != contactId) {
            throw new AuraHandledException('You do not have access to this request.');
        }
        CaseDetail d = new CaseDetail();
        d.recordId = c.Id;
        d.id = c.Friendly_Id__c != null ? c.Friendly_Id__c : '#' + c.CaseNumber;
        d.subject = c.Subject;
        d.category = c.Category__c;
        d.status = c.Status;
        d.statusKey = c.Status_Key__c;
        d.recordType = c.RecordType != null ? c.RecordType.DeveloperName : null;
        d.requirement = c.Description;
        d.dateStr = c.CreatedDate != null ? c.CreatedDate.format('dd MMM yyyy, hh:mm a') : '';
        d.closedDateStr = c.ClosedDate != null ? c.ClosedDate.format('dd-MM-yy') : null;
        d.canCancel = (c.Status == 'New' || c.Status == 'In Review' || c.Status == 'Working');
        d.canFeedback = (c.Status == 'Closed');
        d.history = new List<TicketReply>();
        List<String> adminMsgs = new List<String>();
        Id myUserId = UserInfo.getUserId();
        if (c.CaseComments != null) {
            for (CaseComment cc : c.CaseComments) {
                TicketReply r = new TicketReply();
                r.id = cc.Id;
                r.who = (cc.CreatedBy != null && cc.CreatedBy.Name != null) ? cc.CreatedBy.Name : 'Support';
                r.whenStr = cc.CreatedDate != null ? cc.CreatedDate.format('dd MMM yyyy') : '';
                r.text = cc.CommentBody;
                d.history.add(r);
                if (cc.CreatedById != myUserId) adminMsgs.add(cc.CommentBody);
            }
        }
        d.adminReply = adminMsgs.isEmpty() ? null : String.join(adminMsgs, '\n\n');
        d.documents = new List<CaseDoc>();
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :caseId]) {
            docIds.add(l.ContentDocumentId);
        }
        if (!docIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, Title, FileExtension, ContentDocumentId
                FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = true
            ]) {
                CaseDoc cd = new CaseDoc();
                cd.id = cv.ContentDocumentId;
                cd.ext = cv.FileExtension;
                cd.name = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
                // Direct-bytes download path (renders the file, not a blank preview page in LWR).
                cd.url = '/sfc/servlet.shepherd/version/download/' + cv.Id;
                d.documents.add(cd);
            }
        }
        return d;
    }

    /* ============================================================= *
     *  CANCEL (Phase 3) — owner-guarded status flip to 'Canceled'
     * ============================================================= */
    @AuraEnabled
    public static void cancelServiceRequest(Id caseId) {
        if (caseId == null) throw new AuraHandledException('Request Id is required.');
        Id contactId = getCurrentContactId();
        List<Case> cs = [SELECT Id, ContactId, Status FROM Case WHERE Id = :caseId LIMIT 1];
        if (cs.isEmpty()) throw new AuraHandledException('Request not found.');
        if (contactId != null && cs[0].ContactId != contactId) {
            throw new AuraHandledException('You can only cancel your own request.');
        }
        if (cs[0].Status == 'Closed' || cs[0].Status == 'Rejected' || cs[0].Status == 'Canceled') {
            throw new AuraHandledException('This request can no longer be cancelled.');
        }
        cs[0].Status = 'Canceled';
        update cs[0];
    }

    /* ============================================================= *
     *  FEEDBACK (Phase 3) — owner-guarded rating/comment on closed case
     * ============================================================= */
    @AuraEnabled
    public static void submitCaseFeedback(Id caseId, Integer rating, String comment) {
        if (caseId == null) throw new AuraHandledException('Request Id is required.');
        Id contactId = getCurrentContactId();
        List<Case> cs = [SELECT Id, ContactId FROM Case WHERE Id = :caseId LIMIT 1];
        if (cs.isEmpty()) throw new AuraHandledException('Request not found.');
        if (contactId != null && cs[0].ContactId != contactId) {
            throw new AuraHandledException('You can only leave feedback on your own request.');
        }
        if (rating != null) cs[0].Rating__c = String.valueOf(rating);
        if (String.isNotBlank(comment)) cs[0].Feedback__c = comment;
        update cs[0];
    }
}