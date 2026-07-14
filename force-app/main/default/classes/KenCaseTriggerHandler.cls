/**
 * @description
 * KenCaseTriggerHandler contains all trigger handler methods for the Case object.
 * Called from KenCaseTrigger. Keeps trigger logic separate from the LWC controller.
 */
public without sharing class KenCaseTriggerHandler {

    private class OfferingAssignment {
        public String serviceName;
    }

    // Default queue developer name used when the Ken_Support_Services_Parameters__c
    // custom setting has no value configured for Escalation_Queue_Developer_Name__c.
    // The string itself lives in KenSnSConstants for centralized management.
    private static final String DEFAULT_ESCALATION_QUEUE_DEVELOPER_NAME = KenSnSConstants.DEFAULT_ESCALATION_QUEUE_DEVELOPER_NAME;

    // -------------------------------------------------------------------------
    // Public trigger entry points
    // -------------------------------------------------------------------------

    /**
     * @description Case before-insert handler. Auto-populates
     *              - Case.Constituent_Role__c (from Account / running user)
     *              - Case.OwnerId / Case.EntitlementId (from Service Offering)
     *              Bulk-safe.
     */
    public static void handleBeforeInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) return;
        if (KenSnSConstants.isTriggerBypassed()) return;

        populateConstituentRole(newCases);
        routeCaseOwnerByService(newCases);
        setHostelCaseStatus(newCases);
        KenAssignmentHelper.updateRecordOwner(newCases);
    }

    // Sets Status = 'Hostel Approval' for new cases whose service offering belongs
    // to the Hostel service category. Done in before-insert so the approval process
    // Initial Submission Action is not needed (avoids a nested update DML that would
    // trigger the Standard Case Assignment Rule and override OwnerId).
    private static void setHostelCaseStatus(List<Case> cases) {
        Set<Id> offeringIds = new Set<Id>();
        for (Case c : cases) {
            if (c.Service_Offering__c != null) offeringIds.add(c.Service_Offering__c);
        }
        if (offeringIds.isEmpty()) return;

        Set<Id> hostelOfferingIds = new Set<Id>();
        try {
            for (Ken_Service_Offering__c o : [
                SELECT Id FROM Ken_Service_Offering__c
                WHERE Id IN :offeringIds
                AND Service__r.Service_Category__c = :KenSnSConstants.SERVICE_CATEGORY_HOSTEL
            ]) {
                hostelOfferingIds.add(o.Id);
            }
        } catch (Exception ignored) {}

        for (Case c : cases) {
            if (hostelOfferingIds.contains(c.Service_Offering__c)) {
                c.Status = KenSnSConstants.CASE_STATUS_HOSTEL_APPROVED;
            }
        }
    }


    public static void handleBeforeUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        if (newCases == null || newCases.isEmpty()) return;
        if (KenSnSConstants.isTriggerBypassed()) return;

        populateConstituentRole(newCases);
        routeCaseOwnerByService(newCases, oldMap);
        routeEscalatedCasesToCaseManager(newCases, oldMap);
        updatePriorityOnEscalation(newCases, oldMap);
        routeFinanceCaseOwner(newCases, oldMap);
    }

    // After-insert: submits hostel service cases into Hostel_Full_Approval_Flow.
    // Detects hostel cases by querying Service_Category__c on the related service offering.
    public static void handleHostelApprovalAfterInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) return;
        if (KenSnSConstants.isTriggerBypassed()) return;

        Set<Id> offeringIds = new Set<Id>();
        for (Case c : newCases) {
            if (c.Service_Offering__c != null) offeringIds.add(c.Service_Offering__c);
        }
        if (offeringIds.isEmpty()) return;

        Set<Id> hostelOfferingIds = new Set<Id>();
        try {
            for (Ken_Service_Offering__c o : [
                SELECT Id FROM Ken_Service_Offering__c
                WHERE Id IN :offeringIds
                AND Service__r.Service_Category__c = :KenSnSConstants.SERVICE_CATEGORY_HOSTEL
            ]) {
                hostelOfferingIds.add(o.Id);
            }
        } catch (Exception ignored) {}
        if (hostelOfferingIds.isEmpty()) return;

        List<Approval.ProcessSubmitRequest> requests = new List<Approval.ProcessSubmitRequest>();
        for (Case c : newCases) {
            if (hostelOfferingIds.contains(c.Service_Offering__c)) {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(c.Id);
                req.setProcessDefinitionNameOrId(KenSnSConstants.HOSTEL_APPROVAL_PROCESS_NAME);
                req.setSubmitterId(UserInfo.getUserId());
                req.setSkipEntryCriteria(true);
                requests.add(req);
            }
        }
        if (requests.isEmpty()) return;
        try {
            Approval.process(requests);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Hostel Approval Submit Error: ' + e.getMessage());
        }
    }

    /**
     * @description After-update handler called from KenCaseTrigger.
     *              When a Gate Pass Request case moves to Resolved for the first time,
     *              creates a Ken_Gate_Pass__c record and sends the gate pass email.
     *              No hardcoding — all status/record-type values from KenSnSConstants.
     */
    public static void handleGatePassAfterUpdate(
        List<Case> newCases,
        Map<Id, Case> oldMap
    ) {
        if (newCases == null || newCases.isEmpty()) return;
        if (KenSnSConstants.isTriggerBypassed()) return;

        Map<Id, Boolean> resolvedById = new Map<Id, Boolean>();
        Map<Id, Boolean> canceledById = new Map<Id, Boolean>();
        for (Case c : newCases) {
            Case old = oldMap.get(c.Id);
            Boolean justResolved = KenSnSConstants.CASE_STATUS_RESOLVED.equals(c.Status)
                                 && !KenSnSConstants.CASE_STATUS_RESOLVED.equals(old?.Status);
            Boolean justCanceled = KenSnSConstants.CASE_STATUS_CANCELED.equals(c.Status)
                                 && !KenSnSConstants.CASE_STATUS_CANCELED.equals(old?.Status);
            if (justResolved) resolvedById.put(c.Id, true);
            if (justCanceled) canceledById.put(c.Id, true);
        }

        if (resolvedById.isEmpty() && canceledById.isEmpty()) return;

        Set<Id> changedIds = new Set<Id>(resolvedById.keySet());
        changedIds.addAll(canceledById.keySet());

        List<Id> eligibleCaseIds = new List<Id>();
        List<Id> canceledCaseIds = new List<Id>();
        for (Case c : [SELECT Id FROM Case WHERE Id IN :changedIds
                        AND Service_Category__c = :KenSnSConstants.SERVICE_CATEGORY_GATE_PASS]) {
            if (resolvedById.containsKey(c.Id)) eligibleCaseIds.add(c.Id);
            if (canceledById.containsKey(c.Id)) canceledCaseIds.add(c.Id);
        }

        // When a gate pass case is canceled, backdate Entry_Time__c to the past
        // so the Is_Expired__c formula (Entry_Time + 30 min < NOW) evaluates to true.
        if (!canceledCaseIds.isEmpty()) {
            try {
                List<Ken_Gate_Pass__c> toExpire = [
                    SELECT Id, Entry_Time__c FROM Ken_Gate_Pass__c
                    WHERE GatePass_Request__c IN :canceledCaseIds
                ];
                Datetime pastTime = System.now().addHours(-2);
                for (Ken_Gate_Pass__c gp : toExpire) {
                    gp.Entry_Time__c = pastTime;
                }
                if (!toExpire.isEmpty()) update toExpire;
            } catch (Exception ignored) {}
        }

        if (eligibleCaseIds.isEmpty()) return;

        List<Case> freshCases = [
            SELECT Id, ContactId, AccountId, Account.PersonContactId,
                   Subject
            FROM Case
            WHERE Id IN :eligibleCaseIds
        ];

        for (Case fc : freshCases) {
            createGatePassFromResolvedCase(fc);
        }
    }

    // -------------------------------------------------------------------------
    // Public utility
    // -------------------------------------------------------------------------

    /**
     * @description Bulk lookup: given a set of Account Ids, return Map<AccountId, ConstituentRoleId>
     *              for those that have a ConstituentRole. Used by the Case before-insert trigger
     *              to auto-populate Case.Constituent_Role__c at insert time.
     */
    public static Map<Id, Id> getRoleIdsByAccountIds(Set<Id> accountIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (accountIds == null || accountIds.isEmpty()) return result;

        // Build account → PersonContactId map and the full set of PersonId candidates
        Map<Id, Id> personContactByAccount = new Map<Id, Id>();
        Set<Id> allCandidateIds = new Set<Id>(accountIds);
        try {
            for (Account a : [SELECT Id, PersonContactId FROM Account WHERE Id IN :accountIds]) {
                if (a.PersonContactId != null) {
                    personContactByAccount.put(a.Id, a.PersonContactId);
                    allCandidateIds.add(a.PersonContactId);
                }
            }
        } catch (Exception ignored) {}

        // Most-recent role per PersonId (registered first, then any)
        Map<Id, Id> roleByPersonId = new Map<Id, Id>();
        try {
            for (ConstituentRole r : [
                SELECT Id, PersonId, Registration_Status__c FROM ConstituentRole
                WHERE PersonId IN :allCandidateIds
                ORDER BY Registration_Status__c DESC NULLS LAST, CreatedDate DESC
            ]) {
                if (!roleByPersonId.containsKey(r.PersonId)) {
                    roleByPersonId.put(r.PersonId, r.Id);
                }
            }
        } catch (Exception ignored) {}

        // Resolve each AccountId — try direct PersonId match, then via PersonContactId
        for (Id acctId : accountIds) {
            Id roleId = roleByPersonId.get(acctId);
            if (roleId == null && personContactByAccount.containsKey(acctId)) {
                roleId = roleByPersonId.get(personContactByAccount.get(acctId));
            }
            if (roleId != null) result.put(acctId, roleId);
        }
        return result;
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static void createGatePassFromResolvedCase(Case freshCase) {
        if (freshCase == null) return;

        // Resolve contact: Case.ContactId first, then Account.PersonContactId
        Id resolvedContactId = freshCase.ContactId;
        if (resolvedContactId == null
            && freshCase.Account != null
            && freshCase.Account.PersonContactId != null) {
            resolvedContactId = freshCase.Account.PersonContactId;
        }
        if (resolvedContactId == null) return;

        // Read questionnaire responses for exit/entry time.
        // Primary: uses Gate_Pass_Mapping__c picklist on the question for
        // explicit field mapping — robust regardless of question label changes.
        // Fallback: label keywords + question type for questions without mapping set.
        List<Ken_Questionnaire_Parameter_Response__c> responses = [
            SELECT Response__c,
                   Questionnaire_Parameter__r.Question_Label__c,
                   Questionnaire_Parameter__r.Question_Type__c,
                   Questionnaire_Parameter__r.Gate_Pass_Mapping__c
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Case__c = :freshCase.Id
        ];

        Datetime exitTime  = null;
        Datetime entryTime = null;
        Date     exitDate  = null; Time exitTimeOnly  = null;
        Date     entryDate = null; Time entryTimeOnly = null;

        for (Ken_Questionnaire_Parameter_Response__c r : responses) {
            if (String.isBlank(r.Response__c)) continue;
            String mapping = r.Questionnaire_Parameter__r.Gate_Pass_Mapping__c;
            String qType   = r.Questionnaire_Parameter__r.Question_Type__c;
            String label   = r.Questionnaire_Parameter__r.Question_Label__c;

            // --- Primary: explicit Gate_Pass_Mapping__c ---
            if (String.isNotBlank(mapping)) {
                if (KenSnSConstants.GATE_PASS_MAP_EXIT_DATE.equals(mapping)) {
                    exitDate = KenServiceSupportController.parseGatePassDate(r.Response__c);
                } else if (KenSnSConstants.GATE_PASS_MAP_EXIT_TIME.equals(mapping)) {
                    exitTimeOnly = KenServiceSupportController.parseGatePassTime(r.Response__c);
                } else if (KenSnSConstants.GATE_PASS_MAP_ENTRY_DATE.equals(mapping)) {
                    entryDate = KenServiceSupportController.parseGatePassDate(r.Response__c);
                } else if (KenSnSConstants.GATE_PASS_MAP_ENTRY_TIME.equals(mapping)) {
                    entryTimeOnly = KenServiceSupportController.parseGatePassTime(r.Response__c);
                }
                continue;
            }

            // --- Fallback: keyword + type matching ---
            Boolean isExitContext  = String.isNotBlank(label)
                && label.containsIgnoreCase(KenSnSConstants.GATE_PASS_EXIT_LABEL_KEYWORD);
            Boolean isEntryContext = String.isNotBlank(label)
                && label.containsIgnoreCase(KenSnSConstants.GATE_PASS_ENTRY_LABEL_KEYWORD);

            if (KenSnSConstants.GATE_PASS_QUESTION_TYPE_DATE.equalsIgnoreCase(qType)) {
                Date parsed = KenServiceSupportController.parseGatePassDate(r.Response__c);
                if (isExitContext)  exitDate  = parsed;
                if (isEntryContext) entryDate = parsed;
            } else if (KenSnSConstants.GATE_PASS_QUESTION_TYPE_TIME.equalsIgnoreCase(qType)) {
                Time parsed = KenServiceSupportController.parseGatePassTime(r.Response__c);
                if (isExitContext)  exitTimeOnly  = parsed;
                if (isEntryContext) entryTimeOnly = parsed;
            } else if (String.isNotBlank(label)) {
                if (isExitContext)  exitTime  = KenServiceSupportController.parseGatePassDateTime(r.Response__c);
                if (isEntryContext) entryTime = KenServiceSupportController.parseGatePassDateTime(r.Response__c);
            }
        }

        // Combine Date + Time pairs when both are present
        if (exitDate != null && exitTimeOnly != null) {
            exitTime = Datetime.newInstance(exitDate, exitTimeOnly);
        }
        if (entryDate != null && entryTimeOnly != null) {
            entryTime = Datetime.newInstance(entryDate, entryTimeOnly);
        }

        Ken_Gate_Pass__c gp = new Ken_Gate_Pass__c(
            GatePass_Request__c = freshCase.Id,
            Contact__c          = resolvedContactId,
            Account__c          = freshCase.AccountId,
            Exit_Time__c        = exitTime,
            Entry_Time__c       = entryTime,
            Start_Time__c       = exitTime,
            End_Time__c         = entryTime,
            Email_Sent__c       = false
        );
        insert gp;

    }

    private static void updatePriorityOnEscalation(List<Case> newCases, Map<Id, Case> oldCaseById) {
        if (oldCaseById == null || oldCaseById.isEmpty()) return;
        for (Case c : newCases) {
            Case oldCase = oldCaseById.get(c.Id);
            if (oldCase != null && !oldCase.IsEscalated && c.IsEscalated) {
                c.Priority = KenSnSConstants.CASE_PRIORITY_HIGH;
            }
        }
    }

    private static void populateConstituentRole(List<Case> newCases) {
        // 1. Collect AccountIds needing a role lookup; note any Case lacking an Account
        Set<Id> accountIds = new Set<Id>();
        Boolean anyLacksAccount = false;
        for (Case c : newCases) {
            if (c.Constituent_Role__c != null) continue;
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            } else {
                anyLacksAccount = true;
            }
        }

        Id currentUserAccountId = null;
        if (anyLacksAccount) {
            try {
                for (User u : [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]) {
                    currentUserAccountId = u.AccountId;
                }
            } catch (Exception ignored) {}
            if (currentUserAccountId != null) accountIds.add(currentUserAccountId);
        }

        if (accountIds.isEmpty()) return;

        Map<Id, Id> roleByAccount = getRoleIdsByAccountIds(accountIds);
        if (roleByAccount.isEmpty()) return;

        for (Case c : newCases) {
            if (c.Constituent_Role__c != null) continue;
            Id lookupAcc = (c.AccountId != null) ? c.AccountId : currentUserAccountId;
            if (lookupAcc != null && roleByAccount.containsKey(lookupAcc)) {
                c.Constituent_Role__c = roleByAccount.get(lookupAcc);
            }
        }
    }

    // When the approval process Step 2 (Mess) fires its Status field update to
    // Finance Approval, this before-update method detects the transition and runs
    // Ken_Assignment_Rule__c records tagged with Stage__c = 'Finance' to assign
    // the hostel-specific finance user as OwnerId before Step 3 is routed.
    private static void routeFinanceCaseOwner(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> financeCases = new List<Case>();
        for (Case c : newCases) {
            Case old = oldMap.get(c.Id);
            if (KenSnSConstants.CASE_STATUS_FINANCE_APPROVED.equals(c.Status)
                && (old == null || !KenSnSConstants.CASE_STATUS_FINANCE_APPROVED.equals(old.Status))) {
                financeCases.add(c);
            }
        }
        if (financeCases.isEmpty()) return;
        KenAssignmentHelper.updateRecordOwner(financeCases, KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
    }

    // Service-name → queue mapping is in the Case_Owner_Assignment rule
    // (Setup → Object Manager → Case → Assignment Rules). Apex sets EntitlementId
    // only; OwnerId is set by the Assignment Rule when triggered via DMLOptions.
    //
    // Entitlement assignment is now DATA-DRIVEN: the controller queries Entitlement
    // records and matches by Entitlement.Name = Ken_Service__c.Name. Admins keep
    // the alignment by ensuring each Service has an Entitlement with the same name.
    // (Previously there was a hardcoded SERVICE_TO_ENTITLEMENT map; removed because
    //  adding new services required a code deploy.)

    @TestVisible
    private static String getEscalationQueueDeveloperName() {
        Ken_Support_Services_Parameters__c setting = Ken_Support_Services_Parameters__c.getOrgDefaults();
        if (setting != null && String.isNotBlank(setting.Escalation_Queue_Developer_Name__c)) {
            return setting.Escalation_Queue_Developer_Name__c;
        }
        // If custom setting is blank → do NOT fallback to default; skip owner update
        return null;
    }

    private static void routeCaseOwnerByService(List<Case> newCases) {
        routeCaseOwnerByService(newCases, null);
    }

    private static void routeCaseOwnerByService(List<Case> newCases, Map<Id, Case> oldCaseById) {
        Map<Id, OfferingAssignment> assignmentsByOfferingId = getOfferingAssignments(newCases);

        // Collect service names for entitlement lookup
        Set<String> neededServiceNames = new Set<String>();
        for (Case c : newCases) {
            String serviceName = getResolvedServiceName(c, assignmentsByOfferingId);
            if (String.isNotBlank(serviceName)) {
                neededServiceNames.add(serviceName);
            }
        }
        Map<String, Id> entitlementIdByName = neededServiceNames.isEmpty()
            ? new Map<String, Id>()
            : getPreferredEntitlementIds(neededServiceNames);

        Id supportRecordTypeId = KenServiceSupportController.getCaseRecordTypeId(KenSnSConstants.CASE_RECORD_TYPE_SUPPORT);
        Map<String, Id> queueIdByDevName = getQueueIdsByDeveloperNames(
            new Set<String>{ KenSnSConstants.DEFAULT_ASSIGNMENT_QUEUE_DEVELOPER_NAME }
        );

        for (Case c : newCases) {
            Case oldCase = oldCaseById == null ? null : oldCaseById.get(c.Id);
            Boolean isInsert = oldCase == null;
            Boolean serviceOfferingChanged = oldCase != null && c.Service_Offering__c != oldCase.Service_Offering__c;

            // Entitlement — set on insert or when offering changes or entitlement is blank.
            // Do NOT re-assign if an admin explicitly cleared EntitlementId (had value → null).
            String serviceName = getResolvedServiceName(c, assignmentsByOfferingId);
            Boolean entitlementExplicitlyCleared = !isInsert && oldCase != null && oldCase.EntitlementId != null && c.EntitlementId == null;
            Boolean shouldEvaluateEntitlement = !entitlementExplicitlyCleared && (isInsert || serviceOfferingChanged || c.EntitlementId == null);
            if (String.isNotBlank(serviceName) && shouldEvaluateEntitlement) {
                Id entitlementId = entitlementIdByName.get(serviceName);
                Boolean shouldAssignEntitlement = isInsert
                    ? true
                    : (c.EntitlementId == null || serviceOfferingChanged || c.EntitlementId == oldCase.EntitlementId);
                if (entitlementId != null && shouldAssignEntitlement) {
                    c.EntitlementId = entitlementId;
                }
            }

            // OwnerId — route to default queue on insert or service offering change
            // (owner assignment logic to be updated with replacement configuration)
            if (!isInsert && !serviceOfferingChanged) continue;
            if (c.Service_Offering__c == null
                && (supportRecordTypeId == null || c.RecordTypeId != supportRecordTypeId)) {
                continue;
            }
            Id fallbackQueueId = queueIdByDevName.get(KenSnSConstants.DEFAULT_ASSIGNMENT_QUEUE_DEVELOPER_NAME);
            if (fallbackQueueId != null) {
                c.OwnerId = fallbackQueueId;
            }
        }
    }

    private static void routeEscalatedCasesToCaseManager(List<Case> newCases, Map<Id, Case> oldCaseById) {
        if (oldCaseById == null || oldCaseById.isEmpty()) return;

        // Owner changes to Case Manager ONLY when BOTH IsEscalated = true AND Priority = High
        Boolean needsCaseManagerQueue = false;
        for (Case c : newCases) {
            Case oldCase = oldCaseById.get(c.Id);
            if (oldCase != null && !oldCase.IsEscalated && c.IsEscalated
                && KenSnSConstants.CASE_PRIORITY_HIGH.equals(c.Priority)) {
                needsCaseManagerQueue = true;
                break;
            }
        }
        if (!needsCaseManagerQueue) return;

        // If custom setting is blank → skip owner update (no fallback)
        String escalationQueueDeveloperName = getEscalationQueueDeveloperName();
        if (String.isBlank(escalationQueueDeveloperName)) return;

        Id caseManagerQueueId = null;
        try {
            for (Group g : [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue' AND DeveloperName = :escalationQueueDeveloperName
                LIMIT 1
            ]) {
                caseManagerQueueId = g.Id;
            }
        } catch (Exception ignored) {}
        if (caseManagerQueueId == null) return;

        for (Case c : newCases) {
            Case oldCase = oldCaseById.get(c.Id);
            if (oldCase != null && !oldCase.IsEscalated && c.IsEscalated
                && KenSnSConstants.CASE_PRIORITY_HIGH.equals(c.Priority)) {
                c.OwnerId = caseManagerQueueId;
            }
        }
    }

    @TestVisible
    private static String getResolvedServiceName(Case caseRecord, Map<Id, OfferingAssignment> assignmentsByOfferingId) {
        if (caseRecord == null) return null;

        String serviceName = caseRecord.Service_Name__c;
        if (String.isNotBlank(serviceName)) {
            return serviceName;
        }
        if (caseRecord.Service_Offering__c == null || assignmentsByOfferingId == null) {
            return null;
        }
        OfferingAssignment a = assignmentsByOfferingId.get(caseRecord.Service_Offering__c);
        return a != null ? a.serviceName : null;
    }

    @TestVisible
    private static Map<Id, OfferingAssignment> getOfferingAssignments(List<Case> newCases) {
        Map<Id, OfferingAssignment> result = new Map<Id, OfferingAssignment>();
        Set<Id> offeringIds = new Set<Id>();
        for (Case c : newCases) {
            if (c != null && c.Service_Offering__c != null) {
                offeringIds.add(c.Service_Offering__c);
            }
        }
        if (offeringIds.isEmpty()) return result;

        try {
            for (Ken_Service_Offering__c offering : [
                SELECT Id, Service__r.Name
                FROM Ken_Service_Offering__c
                WHERE Id IN :offeringIds
            ]) {
                OfferingAssignment a = new OfferingAssignment();
                if (offering.Service__r != null) {
                    a.serviceName = offering.Service__r.Name;
                }
                result.put(offering.Id, a);
            }
        } catch (Exception ignored) {}
        return result;
    }

    @TestVisible
    private static Map<String, Id> getQueueIdsByDeveloperNames(Set<String> developerNames) {
        Map<String, Id> result = new Map<String, Id>();
        if (developerNames == null || developerNames.isEmpty()) return result;
        try {
            for (Group g : [
                SELECT Id, DeveloperName
                FROM Group
                WHERE Type = 'Queue'
                AND DeveloperName IN :developerNames
            ]) {
                result.put(g.DeveloperName, g.Id);
            }
        } catch (Exception ignored) {}
        return result;
    }

    @TestVisible
    private static Map<String, Id> getPreferredEntitlementIds(Set<String> entitlementNames) {
        Map<String, Id> result = new Map<String, Id>();
        if (entitlementNames == null || entitlementNames.isEmpty()) return result;

        try {
            List<Entitlement> entitlements = [
                SELECT Id, Name, StartDate, EndDate
                FROM Entitlement
                WHERE Name IN :entitlementNames
                ORDER BY Name ASC, StartDate DESC NULLS LAST, CreatedDate DESC
            ];
            return selectPreferredEntitlementIds(entitlements, entitlementNames, Date.today());
        } catch (Exception ignored) {
            return result;
        }
    }

    @TestVisible
    private static Map<String, Id> selectPreferredEntitlementIds(
        List<Entitlement> entitlements,
        Set<String> requestedNames,
        Date asOfDate
    ) {
        Map<String, Id> result = new Map<String, Id>();
        if (requestedNames == null || requestedNames.isEmpty() || entitlements == null || entitlements.isEmpty()) {
            return result;
        }

        Date effectiveDate = (asOfDate == null) ? Date.today() : asOfDate;
        Map<String, Id> fallbackIdByName = new Map<String, Id>();

        for (Entitlement entitlementRecord : entitlements) {
            if (entitlementRecord == null || String.isBlank(entitlementRecord.Name) || entitlementRecord.Id == null) {
                continue;
            }
            if (!requestedNames.contains(entitlementRecord.Name)) {
                continue;
            }
            if (!fallbackIdByName.containsKey(entitlementRecord.Name)) {
                fallbackIdByName.put(entitlementRecord.Name, entitlementRecord.Id);
            }

            Boolean hasStarted = entitlementRecord.StartDate == null || entitlementRecord.StartDate <= effectiveDate;
            Boolean notEnded = entitlementRecord.EndDate == null || entitlementRecord.EndDate >= effectiveDate;
            if (hasStarted && notEnded && !result.containsKey(entitlementRecord.Name)) {
                result.put(entitlementRecord.Name, entitlementRecord.Id);
            }
        }

        for (String entitlementName : requestedNames) {
            if (!result.containsKey(entitlementName) && fallbackIdByName.containsKey(entitlementName)) {
                result.put(entitlementName, fallbackIdByName.get(entitlementName));
            }
        }
        return result;
    }

}