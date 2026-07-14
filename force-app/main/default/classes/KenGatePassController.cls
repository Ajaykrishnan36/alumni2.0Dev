/**
 * KenGatePassController
 *
 * @AuraEnabled methods for the Gate Pass module.
 * - Gate pass lookup for a Case (shown in related list)
 * - Active gate pass for a Contact (student portal view)
 */
public without sharing class KenGatePassController {

    // -----------------------------------------------------------------------
    // Wrapper classes
    // -----------------------------------------------------------------------

    public class GatePassRow {
        @AuraEnabled public Id       id;
        @AuraEnabled public String   name;
        @AuraEnabled public Id       contactId;
        @AuraEnabled public String   contactName;
        @AuraEnabled public String   contactPhone;
        @AuraEnabled public Id       accountId;
        @AuraEnabled public String   qrCode;
        @AuraEnabled public Datetime exitTime;
        @AuraEnabled public Datetime entryTime;
        @AuraEnabled public Boolean  emailSent;
    }

    // -----------------------------------------------------------------------
    // Gate Pass stats for Campus Life widget
    // -----------------------------------------------------------------------

    public class GatePassStats {
        @AuraEnabled public Integer activeCount   = 0;  // Status = Resolved
        @AuraEnabled public Integer newCount      = 0;  // Status = New
        @AuraEnabled public Integer canceledCount = 0;  // Status = Canceled
    }

    /**
     * Returns gate pass case statistics for the running user grouped by Status:
     *   activeCount   — Status = Resolved
     *   newCount      — Status = New
     *   canceledCount — Status = Canceled
     */
    @AuraEnabled(cacheable=false)
    public static GatePassStats getGatePassStats() {
        GatePassStats stats = new GatePassStats();
        try {
            Id userId = UserInfo.getUserId();
            String gatePassCategory = KenSnSConstants.SERVICE_CATEGORY_GATE_PASS;
            for (AggregateResult ar : [
                SELECT Status, COUNT(Id) cnt
                FROM Case
                WHERE CreatedById = :userId
                AND Service_Category__c = :gatePassCategory
                GROUP BY Status
            ]) {
                String status = (String) ar.get('Status');
                Integer cnt   = (Integer) ar.get('cnt');
                if (KenSnSConstants.CASE_STATUS_RESOLVED.equalsIgnoreCase(status)) {
                    stats.activeCount += cnt;
                } else if (KenSnSConstants.CASE_STATUS_NEW.equalsIgnoreCase(status)) {
                    stats.newCount += cnt;
                } else if (KenSnSConstants.CASE_STATUS_CANCELED.equalsIgnoreCase(status)) {
                    stats.canceledCount += cnt;
                }
            }
        } catch (Exception ignored) {}
        return stats;
    }

    // -----------------------------------------------------------------------
    // Gate Pass list for Campus Life "All Passes" page
    // -----------------------------------------------------------------------

    public class GatePassCaseRow {
        @AuraEnabled public Id       caseId;
        @AuraEnabled public String   caseNumber;
        @AuraEnabled public String   passType;
        @AuraEnabled public String   status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime closedDate;
        @AuraEnabled public String   exitTime;
        @AuraEnabled public String   entryTime;
        @AuraEnabled public String   gatePassId;
        @AuraEnabled public String   gatePassName;
        @AuraEnabled public String   qrCode;
        @AuraEnabled public Boolean  isActive;
        @AuraEnabled public Boolean  isExpired;
        @AuraEnabled public Boolean  hasGatePass;
        @AuraEnabled public Boolean  canCancel;
        @AuraEnabled public Boolean  canLeaveFeedback;
        @AuraEnabled public Boolean  hasFeedback;
        @AuraEnabled public String   approvedDate;
        @AuraEnabled public String   description;       // first questionnaire text response
        @AuraEnabled public String   visitorInfo;       // visitor name + relationship if any
        @AuraEnabled public List<String> attachmentNames; // file names attached to case
    }

    /**
     * Returns all gate pass cases for the current user, each decorated
     * with its linked Ken_Gate_Pass__c record where available.
     */
    @AuraEnabled(cacheable=false)
    public static List<GatePassCaseRow> getGatePassCases() {
        List<GatePassCaseRow> result = new List<GatePassCaseRow>();
        try {
            Id userId = UserInfo.getUserId();
            List<Case> cases = [
                SELECT Id, CaseNumber, Status, CreatedDate, ClosedDate,
                       LastModifiedDate,
                       Service_Offering__r.Name, Rating__c, Feedback__c
                FROM Case
                WHERE CreatedById = :userId
                AND Service_Category__c = :KenSnSConstants.SERVICE_CATEGORY_GATE_PASS
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];

            Set<Id> caseIds = new Map<Id, Case>(cases).keySet();

            // Questionnaire responses — grab first Short Answer text + visitor info
            Map<Id, String> descByCaseId    = new Map<Id, String>();
            Map<Id, String> visitorByCaseId = new Map<Id, String>();
            for (Ken_Questionnaire_Parameter_Response__c r : [
                SELECT Case__c, Response__c,
                       Questionnaire_Parameter__r.Question_Label__c,
                       Questionnaire_Parameter__r.Question_Type__c
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Case__c IN :caseIds
                ORDER BY Questionnaire_Parameter__r.Order__c ASC
            ]) {
                if (String.isBlank(r.Response__c)) continue;
                String label = r.Questionnaire_Parameter__r.Question_Label__c;
                String qType = r.Questionnaire_Parameter__r.Question_Type__c;
                // First Short Answer that's not a date/time = description
                if (!descByCaseId.containsKey(r.Case__c)
                    && 'Short Answer'.equalsIgnoreCase(qType)
                    && String.isNotBlank(label)
                    && !label.containsIgnoreCase('Time')
                    && !label.containsIgnoreCase('Date')
                    && !label.containsIgnoreCase('Phone')
                    && !label.containsIgnoreCase('Number')) {
                    descByCaseId.put(r.Case__c, r.Response__c);
                }
                // Visitor full name
                if (!visitorByCaseId.containsKey(r.Case__c)
                    && String.isNotBlank(label)
                    && (label.containsIgnoreCase('Visitor') || label.containsIgnoreCase('visitor'))
                    && label.containsIgnoreCase('Name')) {
                    visitorByCaseId.put(r.Case__c, r.Response__c);
                }
            }

            // Attachment file names per case
            Map<Id, List<String>> attachByCaseId = new Map<Id, List<String>>();
            for (ContentDocumentLink cdl : [
                SELECT LinkedEntityId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :caseIds
                AND ContentDocument.Title != NULL
                ORDER BY ContentDocument.CreatedDate ASC
                LIMIT 200
            ]) {
                if (!attachByCaseId.containsKey(cdl.LinkedEntityId)) {
                    attachByCaseId.put(cdl.LinkedEntityId, new List<String>());
                }
                attachByCaseId.get(cdl.LinkedEntityId).add(cdl.ContentDocument.Title);
            }

            // Get linked gate passes
            Map<Id, Ken_Gate_Pass__c> passByCaseId = new Map<Id, Ken_Gate_Pass__c>();
            for (Ken_Gate_Pass__c gp : [
                SELECT Id, Name, QR_Code__c, Exit_Time__c, Entry_Time__c,
                       Is_Active__c, Is_Expired__c, GatePass_Request__c
                FROM Ken_Gate_Pass__c
                WHERE GatePass_Request__c IN :caseIds
                ORDER BY CreatedDate DESC
            ]) {
                if (!passByCaseId.containsKey(gp.GatePass_Request__c)) {
                    passByCaseId.put(gp.GatePass_Request__c, gp);
                }
            }

            Set<String> openStatuses = new Set<String>{
                KenSnSConstants.CASE_STATUS_NEW,
                KenSnSConstants.CASE_STATUS_IN_PROGRESS,
                KenSnSConstants.CASE_STATUS_WAITING_FOR_STUDENT,
                KenSnSConstants.CASE_STATUS_RESPONSE_RECEIVED,
                KenSnSConstants.CASE_STATUS_ON_HOLD
            };

            for (Case c : cases) {
                GatePassCaseRow row = new GatePassCaseRow();
                row.caseId       = c.Id;
                row.caseNumber   = c.CaseNumber;
                row.passType     = c.Service_Offering__r != null ? c.Service_Offering__r.Name : 'Gate Pass';
                row.status       = c.Status;
                row.createdDate  = c.CreatedDate;
                row.closedDate   = c.ClosedDate;
                row.hasFeedback      = c.Rating__c != null || String.isNotBlank(c.Feedback__c);
                row.description      = descByCaseId.get(c.Id);
                row.visitorInfo      = visitorByCaseId.get(c.Id);
                row.attachmentNames  = attachByCaseId.containsKey(c.Id) ? attachByCaseId.get(c.Id) : new List<String>();
                row.canCancel        = openStatuses.contains(c.Status);
                row.canLeaveFeedback = KenSnSConstants.CASE_STATUS_CLOSED.equals(c.Status) && !row.hasFeedback;

                Ken_Gate_Pass__c gp = passByCaseId.get(c.Id);
                row.hasGatePass = gp != null;
                if (gp != null) {
                    row.gatePassId   = gp.Id;
                    row.gatePassName = gp.Name;
                    row.qrCode       = gp.QR_Code__c;
                    row.isActive     = gp.Is_Active__c;
                    row.isExpired    = gp.Is_Expired__c;
                    row.exitTime     = gp.Exit_Time__c != null  ? String.valueOf(gp.Exit_Time__c)  : null;
                    row.entryTime    = gp.Entry_Time__c != null ? String.valueOf(gp.Entry_Time__c) : null;
                }

                if (KenSnSConstants.CASE_STATUS_RESOLVED.equals(c.Status)) {
                    row.approvedDate = String.valueOf(c.LastModifiedDate);
                }
                result.add(row);
            }
        } catch (Exception ignored) {}
        return result;
    }

    // -----------------------------------------------------------------------
    // Gate Pass lookup for a Case
    // -----------------------------------------------------------------------

    /**
     * @description Returns all gate passes linked to a Case.
     *              Used in the Case record related list.
     */
    @AuraEnabled(cacheable=false)
    public static List<GatePassRow> getGatePassesForCase(Id caseId) {
        if (caseId == null) return new List<GatePassRow>();
        List<GatePassRow> result = new List<GatePassRow>();
        try {
            for (Ken_Gate_Pass__c gp : [
                SELECT Id, Name, Contact__c, Contact__r.Name,
                       Contact__r.Phone, Contact__r.MobilePhone,
                       Account__c, QR_Code__c,
                       Exit_Time__c, Entry_Time__c, Email_Sent__c
                FROM Ken_Gate_Pass__c
                WHERE GatePass_Request__c = :caseId
                ORDER BY CreatedDate DESC
                LIMIT 50
            ]) {
                result.add(toGatePassRow(gp));
            }
        } catch (Exception ignored) {}
        return result;
    }

    /**
     * @description Returns the most recent gate pass for a Contact.
     *              Used on the student portal to show their gate pass with QR.
     */
    @AuraEnabled(cacheable=false)
    public static GatePassRow getActiveGatePassForContact(Id contactId) {
        if (contactId == null) return null;
        try {
            List<Ken_Gate_Pass__c> passes = [
                SELECT Id, Name, Contact__c, Contact__r.Name,
                       Contact__r.MobilePhone, Contact__r.Phone,
                       Account__c, QR_Code__c,
                       Exit_Time__c, Entry_Time__c, Email_Sent__c
                FROM Ken_Gate_Pass__c
                WHERE Contact__c = :contactId
                AND   Entry_Time__c >= :System.now()
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            return passes.isEmpty() ? null : toGatePassRow(passes[0]);
        } catch (Exception ignored) {}
        return null;
    }

    // -----------------------------------------------------------------------
    // Private helper
    // -----------------------------------------------------------------------

    private static GatePassRow toGatePassRow(Ken_Gate_Pass__c gp) {
        GatePassRow row    = new GatePassRow();
        row.id             = gp.Id;
        row.name           = gp.Name;
        row.contactId      = gp.Contact__c;
        row.accountId      = gp.Account__c;
        row.qrCode         = gp.QR_Code__c;
        row.exitTime       = gp.Exit_Time__c;
        row.entryTime      = gp.Entry_Time__c;
        row.emailSent      = gp.Email_Sent__c;
        if (gp.Contact__r != null) {
            row.contactName  = gp.Contact__r.Name;
            row.contactPhone = String.isNotBlank(gp.Contact__r.MobilePhone)
                               ? gp.Contact__r.MobilePhone
                               : gp.Contact__r.Phone;
        }
        return row;
    }
}