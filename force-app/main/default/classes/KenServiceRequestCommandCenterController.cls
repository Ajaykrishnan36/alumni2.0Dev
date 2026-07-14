/**
 * KenServiceRequestCommandCenterController
 *
 * Backend for the admin Service Request Command Center LWC.
 * Provides:
 *  - KPI counts (open, sla risk, high priority, solved)
 *  - Filtered queue rows
 *  - Case detail (header + service-offering field data)
 *  - Solve / Assign-to-me / Need-info actions
 */
public with sharing class KenServiceRequestCommandCenterController {

    public class KpiData {
        @AuraEnabled public Integer openRequests;
        @AuraEnabled public Integer slaRisk;
        @AuraEnabled public Integer highPriority;
        @AuraEnabled public Integer solved;
    }

    public class QueueRow {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String requesterName;
        @AuraEnabled public String requesterType;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String queueName;
        @AuraEnabled public String slaStatus;          // Healthy | At Risk | Breached
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String createdDateLabel;
    }

    public class CaseDetail {
        @AuraEnabled public Id caseId;
        @AuraEnabled public Id recordTypeId;  // used by the LWC to fetch the
                                              // record-type-specific Status picklist values
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String requesterName;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String queueName;
        @AuraEnabled public String slaStatus;
        @AuraEnabled public Datetime slaTarget;
        @AuraEnabled public String slaTargetLabel;
        @AuraEnabled public String serviceName;
        @AuraEnabled public String serviceOfferingName;
        @AuraEnabled public String description;
        @AuraEnabled public String reason;
        @AuraEnabled public String resolutionNote;
        @AuraEnabled public List<QuestionResponse> responses;
    }

    public class QuestionResponse {
        @AuraEnabled public Id responseId;
        @AuraEnabled public String label;
        @AuraEnabled public String answer;
    }

    public class QueueWorkload {
        @AuraEnabled public Id queueId;
        @AuraEnabled public String queueName;
        @AuraEnabled public String category;       // derived from queue name (prefix before '-')
        @AuraEnabled public Integer totalCases;
        @AuraEnabled public Integer openCount;
        @AuraEnabled public Integer slaRiskCount;
    }

    public class TriageCase {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String requesterName;
        @AuraEnabled public String updatedLabel;    // e.g. "2 days ago"
        @AuraEnabled public String priority;
        @AuraEnabled public String slaStatus;
    }

    public class AdminOverview {
        @AuraEnabled public List<QueueWorkload> queueWorkload;
        @AuraEnabled public List<TriageCase> solveNext;
    }

    @AuraEnabled(cacheable=true)
    public static KpiData getKpis() {
        KpiData k = new KpiData();
        // Open = anything not Closed / Cancelled / Resolved
        k.openRequests = [SELECT count() FROM Case WHERE IsClosed = false];
        // SLA risk: cases where milestone is at-risk or breached (Salesforce CaseMilestone)
        k.slaRisk = 0;
        try {
            k.slaRisk = [
                SELECT count() FROM CaseMilestone
                WHERE Case.IsClosed = false
                AND (IsViolated = true OR (CompletionDate = null AND TargetDate < :Datetime.now()))
            ];
        } catch (Exception ignore) {
            // CaseMilestone may not be queryable if Entitlements aren't enabled
            k.slaRisk = 0;
        }
        k.highPriority = [
            SELECT count() FROM Case
            WHERE IsClosed = false AND Priority IN ('High','Critical')
        ];
        k.solved = [SELECT count() FROM Case WHERE IsClosed = true];
        return k;
    }

    @AuraEnabled(cacheable=true)
    public static List<QueueRow> getQueue(String statusFilter, String priorityFilter,
                                          String slaFilter, String quickChip, String searchKey) {
        // Build a dynamic where clause carefully (no string-concat of user input — use bind vars).
        List<String> conditions = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();

        if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
            conditions.add('Status = :statusFilter');
            binds.put('statusFilter', statusFilter);
        }
        if (String.isNotBlank(priorityFilter) && priorityFilter != 'All') {
            conditions.add('Priority = :priorityFilter');
            binds.put('priorityFilter', priorityFilter);
        }
        if (String.isNotBlank(quickChip)) {
            if (quickChip == 'newOnly') {
                conditions.add('Status = \'New\'');
            } else if (quickChip == 'critical') {
                conditions.add('Priority = \'Critical\'');
            }
        }
        if (String.isNotBlank(searchKey)) {
            String searchPattern = '%' + searchKey + '%';
            conditions.add('(Subject LIKE :searchPattern OR CaseNumber LIKE :searchPattern)');
            binds.put('searchPattern', searchPattern);
        }

        String whereClause = conditions.isEmpty() ? '' : (' WHERE ' + String.join(conditions, ' AND '));
        String query = 'SELECT Id, CaseNumber, Subject, Account.Name, Contact.Name, SuppliedName, '
            + 'Status, Priority, Owner.Name, CreatedDate, '
            + 'Service_Name__c, Service_Offering_Name__c '
            + 'FROM Case' + whereClause
            + ' ORDER BY CreatedDate DESC LIMIT 50';

        List<Case> cases = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);

        // Look up SLA status from CaseMilestone in a single query, then merge
        Map<Id, String> slaByCase = new Map<Id, String>();
        try {
            for (CaseMilestone m : [
                SELECT CaseId, IsViolated, CompletionDate, TargetDate
                FROM CaseMilestone WHERE CaseId IN :cases
            ]) {
                String label = 'Healthy';
                if (m.IsViolated == true) {
                    label = 'Breached';
                } else if (m.CompletionDate == null && m.TargetDate != null
                           && m.TargetDate < Datetime.now()) {
                    label = 'Breached';
                } else if (m.CompletionDate == null && m.TargetDate != null
                           && m.TargetDate < Datetime.now().addHours(2)) {
                    label = 'At Risk';
                }
                // First milestone wins (cases usually have 1 active)
                if (!slaByCase.containsKey(m.CaseId)) slaByCase.put(m.CaseId, label);
            }
        } catch (Exception ignore) { /* Entitlements may not be enabled */ }

        List<QueueRow> rows = new List<QueueRow>();
        for (Case c : cases) {
            QueueRow r = new QueueRow();
            r.caseId = c.Id;
            r.caseNumber = 'CS-' + c.CaseNumber;
            r.subject = c.Subject;
            r.requesterName = c.Account != null ? c.Account.Name
                            : (c.Contact != null ? c.Contact.Name : c.SuppliedName);
            r.requesterType = 'Student'; // placeholder — Persona detection would need ConstituentRole
            r.status = c.Status;
            r.priority = c.Priority;
            r.queueName = c.Owner != null ? c.Owner.Name : '';
            r.slaStatus = slaByCase.containsKey(c.Id) ? slaByCase.get(c.Id) : 'Healthy';
            r.createdDate = c.CreatedDate;
            r.createdDateLabel = c.CreatedDate == null ? '' : c.CreatedDate.format('MMM d, h:mm a');
            // Apply SLA chip filter post-query (CaseMilestone join is reflected in slaByCase)
            if (String.isNotBlank(slaFilter) && slaFilter != 'All' && slaFilter != r.slaStatus) continue;
            if (quickChip == 'breachedSla' && r.slaStatus != 'Breached') continue;
            rows.add(r);
        }
        return rows;
    }

    // Note: not cacheable. The LWC calls this imperatively after status
    // changes (Need Info / Solve / Assign / step click) and needs the FRESH
    // case state — cacheable would return the pre-update snapshot.
    @AuraEnabled
    public static CaseDetail getCaseDetail(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Status, Priority, Description, Reason,
                   RecordTypeId,
                   Account.Name, Contact.Name, SuppliedName,
                   Owner.Name,
                   Service_Name__c, Service_Offering_Name__c
            FROM Case WHERE Id = :caseId LIMIT 1
        ];
        if (cases.isEmpty()) return null;
        Case c = cases[0];

        CaseDetail d = new CaseDetail();
        d.caseId = c.Id;
        d.recordTypeId = c.RecordTypeId;
        d.caseNumber = 'CS-' + c.CaseNumber;
        d.subject = c.Subject;
        d.requesterName = c.Account != null ? c.Account.Name
                        : (c.Contact != null ? c.Contact.Name : c.SuppliedName);
        d.status = c.Status;
        d.priority = c.Priority;
        d.queueName = c.Owner != null ? c.Owner.Name : '';
        d.serviceName = c.Service_Name__c;
        d.serviceOfferingName = c.Service_Offering_Name__c;
        d.description = c.Description;
        d.reason = c.Reason;
        d.resolutionNote = null;

        // Service Request Data: questionnaire responses tied to this case
        d.responses = new List<QuestionResponse>();
        try {
            for (Ken_Questionnaire_Parameter_Response__c r : [
                SELECT Id, Question_Label__c, Response__c, Questionnaire_Parameter__r.Order__c
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Case__c = :caseId
                ORDER BY Questionnaire_Parameter__r.Order__c ASC NULLS LAST
            ]) {
                QuestionResponse qr = new QuestionResponse();
                qr.responseId = r.Id;
                qr.label = r.Question_Label__c;
                qr.answer = r.Response__c;
                d.responses.add(qr);
            }
        } catch (Exception ignored) {}

        // SLA target from first active milestone
        d.slaStatus = 'Healthy';
        try {
            for (CaseMilestone m : [
                SELECT TargetDate, CompletionDate, IsViolated
                FROM CaseMilestone WHERE CaseId = :caseId
                ORDER BY TargetDate ASC LIMIT 1
            ]) {
                d.slaTarget = m.TargetDate;
                d.slaTargetLabel = m.TargetDate == null ? '' : m.TargetDate.format('MMM d, yyyy HH:mm');
                if (m.IsViolated == true) { d.slaStatus = 'Breached'; }
                else if (m.CompletionDate == null && m.TargetDate != null
                         && m.TargetDate < Datetime.now()) { d.slaStatus = 'Breached'; }
                else if (m.CompletionDate == null && m.TargetDate != null
                         && m.TargetDate < Datetime.now().addHours(2)) { d.slaStatus = 'At Risk'; }
            }
        } catch (Exception ignore) {}

        return d;
    }

    /**
     * @description Admin Overview tab data — Queue Workload (open + SLA risk per queue)
     *              and Solve Next (recommended triage order).
     */
    @AuraEnabled(cacheable=true)
    public static AdminOverview getAdminOverview() {
        AdminOverview overview = new AdminOverview();

        // ---- 1. Queue Workload ----
        Map<Id, QueueWorkload> queueMap = new Map<Id, QueueWorkload>();
        try {
            for (Group g : [
                SELECT Id, Name FROM Group
                WHERE Type = 'Queue' ORDER BY Name LIMIT 200
            ]) {
                QueueWorkload qw = new QueueWorkload();
                qw.queueId = g.Id;
                qw.queueName = g.Name;
                qw.category = deriveCategory(g.Name);
                qw.totalCases = 0;
                qw.openCount = 0;
                qw.slaRiskCount = 0;
                queueMap.put(g.Id, qw);
            }
        } catch (Exception ignored) {}

        if (!queueMap.isEmpty()) {
            try {
                for (AggregateResult ar : [
                    SELECT OwnerId, IsClosed, COUNT(Id) cnt
                    FROM Case
                    WHERE OwnerId IN :queueMap.keySet()
                    GROUP BY OwnerId, IsClosed
                ]) {
                    Id ownerId = (Id) ar.get('OwnerId');
                    Boolean closed = (Boolean) ar.get('IsClosed');
                    Integer cnt = (Integer) ar.get('cnt');
                    QueueWorkload qw = queueMap.get(ownerId);
                    if (qw != null) {
                        qw.totalCases += cnt;
                        if (closed == false) qw.openCount += cnt;
                    }
                }
            } catch (Exception ignored) {}

            // SLA-risk counts (best-effort — Entitlements may not be enabled)
            try {
                for (AggregateResult ar : [
                    SELECT Case.OwnerId own, COUNT(Id) cnt
                    FROM CaseMilestone
                    WHERE Case.IsClosed = false
                      AND Case.OwnerId IN :queueMap.keySet()
                      AND (IsViolated = true
                           OR (CompletionDate = null AND TargetDate < :Datetime.now()))
                    GROUP BY Case.OwnerId
                ]) {
                    Id ownerId = (Id) ar.get('own');
                    QueueWorkload qw = queueMap.get(ownerId);
                    if (qw != null) qw.slaRiskCount = (Integer) ar.get('cnt');
                }
            } catch (Exception ignored) {}
        }
        overview.queueWorkload = queueMap.values();

        // ---- 2. Solve Next (top 5 by priority then recency) ----
        overview.solveNext = new List<TriageCase>();
        List<Case> openCases = [
            SELECT Id, CaseNumber, Subject, Priority, LastModifiedDate,
                   Account.Name, Contact.Name, SuppliedName
            FROM Case
            WHERE IsClosed = false
            LIMIT 100
        ];

        Map<Id, String> slaByCase = new Map<Id, String>();
        try {
            for (CaseMilestone m : [
                SELECT CaseId, IsViolated, CompletionDate, TargetDate
                FROM CaseMilestone WHERE CaseId IN :openCases
            ]) {
                String label = 'Healthy';
                if (m.IsViolated == true
                    || (m.CompletionDate == null && m.TargetDate != null
                        && m.TargetDate < Datetime.now())) {
                    label = 'Breached';
                } else if (m.CompletionDate == null && m.TargetDate != null
                           && m.TargetDate < Datetime.now().addHours(2)) {
                    label = 'At Risk';
                }
                if (!slaByCase.containsKey(m.CaseId)) slaByCase.put(m.CaseId, label);
            }
        } catch (Exception ignored) {}

        // Score: lower = more urgent. Breached/Critical first.
        List<CaseScore> scored = new List<CaseScore>();
        Map<String, Integer> pri = new Map<String, Integer>{
            'Critical' => 0, 'High' => 1, 'Medium' => 2, 'Low' => 3
        };
        for (Case c : openCases) {
            CaseScore s = new CaseScore();
            s.c = c;
            s.sla = slaByCase.containsKey(c.Id) ? slaByCase.get(c.Id) : 'Healthy';
            Integer slaScore = (s.sla == 'Breached') ? 0 : (s.sla == 'At Risk' ? 1 : 2);
            Integer priScore = pri.containsKey(c.Priority) ? pri.get(c.Priority) : 4;
            // Combine: SLA dominates, then priority
            s.score = slaScore * 10 + priScore;
            scored.add(s);
        }
        scored.sort();

        Integer limitN = 5;
        Integer i = 0;
        for (CaseScore s : scored) {
            if (i >= limitN) break;
            i++;
            Case c = s.c;
            TriageCase t = new TriageCase();
            t.caseId = c.Id;
            t.caseNumber = 'CS-' + c.CaseNumber;
            t.subject = c.Subject;
            t.requesterName = c.Account != null ? c.Account.Name
                            : (c.Contact != null ? c.Contact.Name : c.SuppliedName);
            t.priority = c.Priority;
            t.slaStatus = s.sla;
            t.updatedLabel = formatRelative(c.LastModifiedDate);
            overview.solveNext.add(t);
        }
        return overview;
    }

    private class CaseScore implements Comparable {
        public Case c;
        public String sla;
        public Integer score;
        public Integer compareTo(Object other) {
            CaseScore o = (CaseScore) other;
            if (this.score < o.score) return -1;
            if (this.score > o.score) return 1;
            // Newer first as tiebreaker
            if (this.c.LastModifiedDate > o.c.LastModifiedDate) return -1;
            if (this.c.LastModifiedDate < o.c.LastModifiedDate) return 1;
            return 0;
        }
    }

    private static String deriveCategory(String queueName) {
        if (queueName == null) return '';
        Integer idx = queueName.indexOf(' - ');
        if (idx >= 0) return queueName.substring(idx + 3).trim();
        idx = queueName.indexOf('-');
        return idx > 0 ? queueName.substring(idx + 1).trim() : queueName;
    }

    private static String formatRelative(Datetime dt) {
        if (dt == null) return '';
        Long ms = Datetime.now().getTime() - dt.getTime();
        Long mins = ms / 60000;
        if (mins < 1) return 'just now';
        if (mins < 60) return 'updated ' + mins + ' min ago';
        Long hours = mins / 60;
        if (hours < 24) return 'updated about ' + hours + ' hours ago';
        Long days = hours / 24;
        if (days < 30) return 'updated ' + days + ' days ago';
        return 'updated on ' + dt.format('MMM d, yyyy');
    }

    public class RecordTypeOption {
        @AuraEnabled public Id recordTypeId;
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isDefault;
    }

    /**
     * @description Return Case record types the running user can use, for the
     *              "+ New Request" chooser modal. Falls back to all active record
     *              types if user-specific filtering isn't available.
     */
    @AuraEnabled(cacheable=true)
    public static List<RecordTypeOption> getCaseRecordTypes() {
        List<RecordTypeOption> out = new List<RecordTypeOption>();
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        Id defaultRtId = null;
        for (Schema.RecordTypeInfo rti : d.getRecordTypeInfos()) {
            if (rti.isMaster() || !rti.isAvailable() || !rti.isActive()) continue;
            if (rti.isDefaultRecordTypeMapping()) defaultRtId = rti.getRecordTypeId();
            RecordTypeOption o = new RecordTypeOption();
            o.recordTypeId = rti.getRecordTypeId();
            o.name = rti.getName();
            o.label = rti.getName();
            o.isDefault = rti.isDefaultRecordTypeMapping();
            out.add(o);
        }
        return out;
    }

    @AuraEnabled
    public static void changeCaseStatus(Id caseId, String status) {
        if (caseId == null || String.isBlank(status)) {
            throw new AuraHandledException('Case Id and status are required.');
        }
        update new Case(Id = caseId, Status = status);
    }

    @AuraEnabled
    public static void saveResolution(Id caseId, String resolutionNote) {
        // Resolution-note field not yet decided. Method exists so the LWC button
        // doesn't error, but it intentionally does NOT write to Feedback__c
        // (that's reserved for student feedback) or Description (requester's
        // original problem statement). Once the target field is confirmed,
        // wire it here.
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }
    }

    @AuraEnabled
    public static void assignToMe(Id caseId) {
        Case c = new Case(Id = caseId, OwnerId = UserInfo.getUserId());
        update c;
    }

    @AuraEnabled
    public static void solveCase(Id caseId, String resolutionNote) {
        // Resolution-note field not yet decided — for now just close the case.
        // The resolutionNote parameter is intentionally accepted but not persisted.
        update new Case(Id = caseId, Status = KenSnSConstants.CASE_STATUS_CLOSED);
    }

    @AuraEnabled
    public static void needInfo(Id caseId, String note) {
        // Move the case to "Waiting for Student" to signal the support team is
        // waiting on a student response.
        update new Case(Id = caseId, Status = KenSnSConstants.CASE_STATUS_WAITING_FOR_STUDENT);
    }
}