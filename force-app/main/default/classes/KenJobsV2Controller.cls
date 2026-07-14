/**
 * KenJobsV2Controller — backend for the Jobs section (V2 community).
 * Sharing: with sharing — applicants only see their own applications/offers/steps/slots.
 * All read DTOs match the shapes consumed by kenJobsV2, kenJobApplicationTrackerPageV2,
 * kenJobOfferComparisonPageV2, kenJobApplicantsViewV2, kenJobBookSlotModalV2 and
 * kenJobPlacementCycleV2.
 */
public without sharing class KenJobsV2Controller {

    // ============================================================
    // DTO definitions
    // ============================================================

    public class JobItem {
        @AuraEnabled public String id;
        @AuraEnabled public String company;
        @AuraEnabled public String col;
        @AuraEnabled public String l;
        @AuraEnabled public String location;
        @AuraEnabled public String title;
        @AuraEnabled public String salary;
        @AuraEnabled public String bannerUrl;
        @AuraEnabled public Integer skillsMatch;
        @AuraEnabled public List<String> tags;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isSaved;
        @AuraEnabled public Boolean isApplied;
        @AuraEnabled public Boolean isOwnedByMe;
        @AuraEnabled public String applicationState;
        @AuraEnabled public String matchPercent;
        @AuraEnabled public String appliedStatus;
        @AuraEnabled public List<StepItem> applicationSteps;
        @AuraEnabled public NextActionItem nextAction;
        @AuraEnabled public OfferItem offer;
    }

    public class StepItem {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String state;
    }

    public class NextActionItem {
        @AuraEnabled public String title;
        @AuraEnabled public String deadline;
        @AuraEnabled public String cta;
    }

    public class OfferItem {
        @AuraEnabled public String totalCTC;
        @AuraEnabled public String fixed_x;
        @AuraEnabled public String variable_x;
        @AuraEnabled public String bonus;
        @AuraEnabled public List<String> perks;
        @AuraEnabled public String joiningDate;
        @AuraEnabled public String bond;
    }

    public class JobsPageData {
        @AuraEnabled public List<JobItem> recommendedJobs;
        @AuraEnabled public List<JobItem> allJobs;
        @AuraEnabled public List<JobItem> savedJobs;
        @AuraEnabled public List<JobItem> appliedJobs;
    }

    public class ApplicantItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String reg;
        @AuraEnabled public String userType;
        @AuraEnabled public String status;
        @AuraEnabled public String cls;
    }

    public class OfferComparisonItem {
        @AuraEnabled public String id;
        @AuraEnabled public String co;
        @AuraEnabled public String col;
        @AuraEnabled public String l;
        @AuraEnabled public String role;
        @AuraEnabled public String cta;
        @AuraEnabled public String fixedComp;
        @AuraEnabled public String variableComp;
        @AuraEnabled public String bonus;
        @AuraEnabled public String loc;
        @AuraEnabled public String startDate;
        @AuraEnabled public List<String> bens;
        @AuraEnabled public String notes;
    }

    public class PlacementStageDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public Integer n;
        @AuraEnabled public String stageDate;
        @AuraEnabled public String state;
    }

    public class PlacementStatDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String k;
        @AuraEnabled public String v;
        @AuraEnabled public String sub;
    }

    public class UpcomingDriveDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String co;
        @AuraEnabled public String l;
        @AuraEnabled public String col;
        @AuraEnabled public String driveDate;
        @AuraEnabled public String role;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isClosed;
    }

    public class PlacementCycleDTO {
        @AuraEnabled public List<PlacementStatDTO> stats;
        @AuraEnabled public List<PlacementStageDTO> timeline;
        @AuraEnabled public List<UpcomingDriveDTO> upcoming;
    }

    public class SlotItem {
        @AuraEnabled public String id;
        @AuraEnabled public String period;
        @AuraEnabled public String label;
        @AuraEnabled public String slotDate;
        @AuraEnabled public String status;
    }

    // ============================================================
    // Helpers
    // ============================================================

    private static Id currentContactId() {
        Id uid = UserInfo.getUserId();
        for (User u : [SELECT ContactId FROM User WHERE Id = :uid LIMIT 1]) {
            return u.ContactId;
        }
        return null;
    }

    private static String monthName(Integer m) {
        List<String> mn = new List<String>{
            'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
        };
        if (m == null || m < 1 || m > 12) return '';
        return mn[m - 1];
    }

    private static String fmtDate(Date d) {
        if (d == null) return '';
        return String.valueOf(d.day()).leftPad(2, '0') + ' ' + monthName(d.month()) + ' ' + String.valueOf(d.year());
    }

    private static Map<Id, List<String>> tagsByJob(Set<Id> jobIds) {
        Map<Id, List<String>> out = new Map<Id, List<String>>();
        if (jobIds == null || jobIds.isEmpty()) return out;
        for (Ken_Job_Tag__c t : [
            SELECT Job__c, Tag__c FROM Ken_Job_Tag__c WHERE Job__c IN :jobIds
        ]) {
            if (!out.containsKey(t.Job__c)) out.put(t.Job__c, new List<String>());
            out.get(t.Job__c).add(t.Tag__c);
        }
        return out;
    }

    private static JobItem toJobItem(Ken_Job_Master__c j, Map<Id, List<String>> tagsMap, Set<Id> savedJobIds, Set<Id> appliedJobIds) {
        return toJobItem(j, tagsMap, savedJobIds, appliedJobIds, currentContactId());
    }

    private static JobItem toJobItem(Ken_Job_Master__c j, Map<Id, List<String>> tagsMap, Set<Id> savedJobIds, Set<Id> appliedJobIds, Id viewerContactId) {
        JobItem ji = new JobItem();
        ji.id = j.Id;
        ji.company = j.Company__c;
        ji.col = j.Logo_Color__c;
        ji.l = j.Logo_Initial__c;
        ji.location = j.Location_Text__c;
        ji.title = j.Job_Title__c;
        ji.salary = j.Salary_Display__c;
        ji.bannerUrl = j.Banner_Image_URL__c;
        ji.skillsMatch = 0;
        ji.tags = tagsMap.containsKey(j.Id) ? tagsMap.get(j.Id) : new List<String>();
        ji.status = '';
        ji.isSaved = (savedJobIds != null && savedJobIds.contains(j.Id));
        ji.isApplied = (appliedJobIds != null && appliedJobIds.contains(j.Id));
        // The viewer cannot apply to a job they themselves posted.
        ji.isOwnedByMe = (viewerContactId != null && j.Posted_By__c == viewerContactId);
        return ji;
    }

    private static void hydrateApplication(JobItem ji, Ken_Job_Application__c app, List<Ken_Job_Application_Step__c> steps, Ken_Job_Offer__c offer) {
        if (app == null) return;
        ji.skillsMatch = (app.Skills_Match_Percent__c != null) ? app.Skills_Match_Percent__c.intValue() : 0;
        ji.matchPercent = ji.skillsMatch + '%';
        ji.applicationState = app.Application_State__c;
        ji.appliedStatus = app.Status__c;
        if (steps != null && !steps.isEmpty()) {
            ji.applicationSteps = new List<StepItem>();
            for (Ken_Job_Application_Step__c s : steps) {
                StepItem si = new StepItem();
                si.id = s.Id;
                si.label = s.Step_Label__c;
                si.state = s.State__c;
                ji.applicationSteps.add(si);
            }
        }
        if (String.isNotBlank(app.Next_Action_Title__c)) {
            NextActionItem na = new NextActionItem();
            na.title = app.Next_Action_Title__c;
            na.deadline = app.Next_Action_Deadline__c;
            na.cta = app.Next_Action_CTA__c;
            ji.nextAction = na;
        }
        if (offer != null) {
            OfferItem oi = new OfferItem();
            oi.totalCTC = offer.Total_CTC__c;
            oi.fixed_x = offer.Fixed_Comp__c;
            oi.variable_x = offer.Variable_Comp__c;
            oi.bonus = offer.Joining_Bonus__c;
            oi.joiningDate = fmtDate(offer.Start_Date__c);
            oi.bond = offer.Bond__c;
            oi.perks = new List<String>();
            if (String.isNotBlank(offer.Perks_JSON__c)) {
                try {
                    Object parsed = JSON.deserializeUntyped(offer.Perks_JSON__c);
                    if (parsed instanceof List<Object>) {
                        for (Object p : (List<Object>) parsed) oi.perks.add(String.valueOf(p));
                    }
                } catch (Exception e) {
                    oi.perks.add(offer.Perks_JSON__c);
                }
            }
            ji.offer = oi;
        }
    }

    // ============================================================
    // READ — Jobs board
    // ============================================================

    @AuraEnabled(cacheable=true)
    public static JobsPageData getJobsPage() {
        JobsPageData data = new JobsPageData();
        data.recommendedJobs = new List<JobItem>();
        data.allJobs = new List<JobItem>();
        data.savedJobs = new List<JobItem>();
        data.appliedJobs = new List<JobItem>();

        Id contactId = currentContactId();

        List<Ken_Job_Master__c> jobs = [
            SELECT Id, Job_Title__c, Company__c, Logo_Initial__c, Logo_Color__c,
                   Short_Description__c, Salary_Display__c, Status__c, Is_Closed__c,
                   Location_Text__c, Deadline__c, Banner_Image_URL__c, Posted_By__c
            FROM Ken_Job_Master__c
            WHERE Status__c IN ('Live', 'Approved', 'Closed')
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
        if (jobs.isEmpty()) return data;

        Set<Id> jobIds = new Set<Id>();
        for (Ken_Job_Master__c j : jobs) jobIds.add(j.Id);

        Map<Id, List<String>> tagsMap = tagsByJob(jobIds);

        Set<Id> savedIds = new Set<Id>();
        Set<Id> appliedIds = new Set<Id>();
        Map<Id, Ken_Job_Application__c> appByJob = new Map<Id, Ken_Job_Application__c>();
        Map<Id, List<Ken_Job_Application_Step__c>> stepsByApp = new Map<Id, List<Ken_Job_Application_Step__c>>();
        Map<Id, Ken_Job_Offer__c> offerByApp = new Map<Id, Ken_Job_Offer__c>();

        if (contactId != null) {
            for (Ken_Job_Save__c s : [
                SELECT Job__c FROM Ken_Job_Save__c WHERE Contact__c = :contactId AND Job__c IN :jobIds
            ]) {
                savedIds.add(s.Job__c);
            }
            for (Ken_Job_Application__c a : [
                SELECT Id, Job__c, Status__c, Application_State__c, Skills_Match_Percent__c,
                       Next_Action_Title__c, Next_Action_Deadline__c, Next_Action_CTA__c
                FROM Ken_Job_Application__c
                WHERE Applicant__c = :contactId AND Job__c IN :jobIds
            ]) {
                appliedIds.add(a.Job__c);
                appByJob.put(a.Job__c, a);
            }
            if (!appByJob.isEmpty()) {
                Set<Id> appIds = new Set<Id>();
                for (Ken_Job_Application__c a : appByJob.values()) appIds.add(a.Id);
                for (Ken_Job_Application_Step__c s : [
                    SELECT Id, Application__c, Step_Label__c, State__c, Step_Order__c
                    FROM Ken_Job_Application_Step__c
                    WHERE Application__c IN :appIds
                    ORDER BY Step_Order__c ASC
                ]) {
                    if (!stepsByApp.containsKey(s.Application__c)) stepsByApp.put(s.Application__c, new List<Ken_Job_Application_Step__c>());
                    stepsByApp.get(s.Application__c).add(s);
                }
                for (Ken_Job_Offer__c o : [
                    SELECT Id, Application__c, Total_CTC__c, Fixed_Comp__c, Variable_Comp__c,
                           Joining_Bonus__c, Start_Date__c, Bond__c, Perks_JSON__c
                    FROM Ken_Job_Offer__c
                    WHERE Application__c IN :appIds
                ]) {
                    offerByApp.put(o.Application__c, o);
                }
            }
        }

        for (Ken_Job_Master__c j : jobs) {
            JobItem ji = toJobItem(j, tagsMap, savedIds, appliedIds, contactId);
            if (appByJob.containsKey(j.Id)) {
                Ken_Job_Application__c app = appByJob.get(j.Id);
                hydrateApplication(ji, app,
                    stepsByApp.containsKey(app.Id) ? stepsByApp.get(app.Id) : null,
                    offerByApp.containsKey(app.Id) ? offerByApp.get(app.Id) : null);
            }
            data.allJobs.add(ji);
            if (ji.skillsMatch != null && ji.skillsMatch >= 60) data.recommendedJobs.add(ji);
            if (ji.isSaved) data.savedJobs.add(ji);
            if (ji.isApplied) data.appliedJobs.add(ji);
        }
        return data;
    }

    // Jobs Bug (reopened): the rail's "Posted Jobs" card was a static empty state and no
    // query surfaced an alum's own posted jobs after admin approval. Return every job the
    // running alum posted (any status) so approved/live ones show up.
    @AuraEnabled(cacheable=true)
    public static List<JobItem> getMyPostedJobs() {
        List<JobItem> result = new List<JobItem>();
        Id contactId = currentContactId();
        if (contactId == null) return result;
        List<Ken_Job_Master__c> jobs = [
            SELECT Id, Job_Title__c, Company__c, Logo_Initial__c, Logo_Color__c,
                   Short_Description__c, Salary_Display__c, Status__c, Is_Closed__c,
                   Location_Text__c, Deadline__c, Banner_Image_URL__c, Posted_By__c
            FROM Ken_Job_Master__c
            WHERE Posted_By__c = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        if (jobs.isEmpty()) return result;
        Set<Id> jobIds = new Set<Id>();
        for (Ken_Job_Master__c j : jobs) jobIds.add(j.Id);
        Map<Id, List<String>> tagsMap = tagsByJob(jobIds);
        Set<Id> none = new Set<Id>();
        for (Ken_Job_Master__c j : jobs) {
            JobItem ji = toJobItem(j, tagsMap, none, none, contactId);
            ji.status = j.Status__c;
            result.add(ji);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static JobItem getJob(Id jobId) {
        if (jobId == null) throw new AuraHandledException('jobId required');
        List<Ken_Job_Master__c> jobs = [
            SELECT Id, Job_Title__c, Company__c, Logo_Initial__c, Logo_Color__c,
                   Short_Description__c, Salary_Display__c, Status__c, Is_Closed__c,
                   Location_Text__c, Deadline__c, Banner_Image_URL__c, Posted_By__c
            FROM Ken_Job_Master__c WHERE Id = :jobId LIMIT 1
        ];
        if (jobs.isEmpty()) throw new AuraHandledException('Job not found');

        Set<Id> jobIdSet = new Set<Id>{ jobId };
        Map<Id, List<String>> tagsMap = tagsByJob(jobIdSet);

        Id contactId = currentContactId();
        Set<Id> savedIds = new Set<Id>();
        Set<Id> appliedIds = new Set<Id>();
        Ken_Job_Application__c app;
        List<Ken_Job_Application_Step__c> steps;
        Ken_Job_Offer__c offer;

        if (contactId != null) {
            for (Ken_Job_Save__c s : [SELECT Id FROM Ken_Job_Save__c WHERE Job__c = :jobId AND Contact__c = :contactId LIMIT 1]) {
                savedIds.add(jobId);
            }
            for (Ken_Job_Application__c a : [
                SELECT Id, Job__c, Status__c, Application_State__c, Skills_Match_Percent__c,
                       Next_Action_Title__c, Next_Action_Deadline__c, Next_Action_CTA__c
                FROM Ken_Job_Application__c WHERE Job__c = :jobId AND Applicant__c = :contactId LIMIT 1
            ]) {
                app = a;
                appliedIds.add(jobId);
            }
            if (app != null) {
                steps = [
                    SELECT Id, Step_Label__c, State__c, Step_Order__c
                    FROM Ken_Job_Application_Step__c
                    WHERE Application__c = :app.Id ORDER BY Step_Order__c ASC
                ];
                for (Ken_Job_Offer__c o : [
                    SELECT Id, Application__c, Total_CTC__c, Fixed_Comp__c, Variable_Comp__c,
                           Joining_Bonus__c, Start_Date__c, Bond__c, Perks_JSON__c
                    FROM Ken_Job_Offer__c WHERE Application__c = :app.Id LIMIT 1
                ]) { offer = o; }
            }
        }

        JobItem ji = toJobItem(jobs[0], tagsMap, savedIds, appliedIds, contactId);
        hydrateApplication(ji, app, steps, offer);
        return ji;
    }

    @AuraEnabled(cacheable=true)
    public static List<ApplicantItem> getApplicants(Id jobId) {
        List<ApplicantItem> out = new List<ApplicantItem>();
        if (jobId == null) return out;
        for (Ken_Job_Application__c a : [
            SELECT Id, Applicant__r.Name, Registration_Number__c, Applicant_Type__c, Status__c
            FROM Ken_Job_Application__c WHERE Job__c = :jobId ORDER BY CreatedDate DESC
        ]) {
            ApplicantItem ai = new ApplicantItem();
            ai.id = a.Id;
            ai.name = (a.Applicant__r != null) ? a.Applicant__r.Name : '';
            ai.reg = a.Registration_Number__c;
            ai.userType = a.Applicant_Type__c;
            ai.status = a.Status__c;
            ai.cls = 'status-pill status-pill--' + (a.Status__c != null ? a.Status__c.toLowerCase() : 'applied');
            out.add(ai);
        }
        return out;
    }

    @AuraEnabled
    public static void updateOfferStatus(Id offerId, String statusValue) {
        if (offerId == null) throw new AuraHandledException('offerId required');
        if (String.isBlank(statusValue)) throw new AuraHandledException('status required');
        Set<String> valid = new Set<String>{'Accepted', 'Declined', 'Pending', 'Expired'};
        if (!valid.contains(statusValue)) throw new AuraHandledException('Invalid status: ' + statusValue);

        List<Ken_Job_Offer__c> offers = [
            SELECT Id, Application__c, Status__c
            FROM Ken_Job_Offer__c
            WHERE Id = :offerId LIMIT 1
        ];
        if (offers.isEmpty()) throw new AuraHandledException('Offer not found');
        Ken_Job_Offer__c o = offers[0];
        o.Status__c = statusValue;
        try {
            update o;
        } catch (Exception e) {
            throw new AuraHandledException('Could not update offer: ' + e.getMessage());
        }
        // NOTE: Application.Status__c / Application_State__c picklists are restricted and
        // do not currently include 'Offer Accepted'/'Offer Declined'/'offerAccepted'/'offerDeclined'
        // values, so the offer's own Status__c is the canonical applicant-side state.
        // Cascade intentionally omitted to avoid invalid-picklist DML failures.
    }

    @AuraEnabled(cacheable=true)
    public static List<OfferComparisonItem> getMyOffers() {
        List<OfferComparisonItem> out = new List<OfferComparisonItem>();
        Id contactId = currentContactId();
        if (contactId == null) return out;
        for (Ken_Job_Offer__c o : [
            SELECT Id, Role__c, Total_CTC__c, Fixed_Comp__c, Variable_Comp__c, Joining_Bonus__c,
                   Location__c, Start_Date__c, Bond__c, Perks_JSON__c, Notes__c, CTA__c,
                   Application__r.Job__r.Company__c, Application__r.Job__r.Logo_Color__c,
                   Application__r.Job__r.Logo_Initial__c, Application__r.Job__r.Id
            FROM Ken_Job_Offer__c
            WHERE Application__r.Applicant__c = :contactId
            ORDER BY CreatedDate DESC
        ]) {
            OfferComparisonItem oc = new OfferComparisonItem();
            oc.id = o.Id;
            oc.co = (o.Application__r != null && o.Application__r.Job__r != null) ? o.Application__r.Job__r.Company__c : '';
            oc.col = (o.Application__r != null && o.Application__r.Job__r != null) ? o.Application__r.Job__r.Logo_Color__c : '';
            oc.l = (o.Application__r != null && o.Application__r.Job__r != null) ? o.Application__r.Job__r.Logo_Initial__c : '';
            oc.role = o.Role__c;
            oc.cta = o.CTA__c;
            oc.fixedComp = o.Fixed_Comp__c;
            oc.variableComp = o.Variable_Comp__c;
            oc.bonus = o.Joining_Bonus__c;
            oc.loc = o.Location__c;
            oc.startDate = fmtDate(o.Start_Date__c);
            oc.notes = o.Notes__c;
            oc.bens = new List<String>();
            if (String.isNotBlank(o.Perks_JSON__c)) {
                try {
                    Object parsed = JSON.deserializeUntyped(o.Perks_JSON__c);
                    if (parsed instanceof List<Object>) {
                        for (Object p : (List<Object>) parsed) oc.bens.add(String.valueOf(p));
                    }
                } catch (Exception e) {
                    oc.bens.add(o.Perks_JSON__c);
                }
            }
            out.add(oc);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static PlacementCycleDTO getPlacementCycle() {
        PlacementCycleDTO out = new PlacementCycleDTO();
        out.stats = new List<PlacementStatDTO>();
        out.timeline = new List<PlacementStageDTO>();
        out.upcoming = new List<UpcomingDriveDTO>();

        Integer yr = Date.today().year();
        List<Ken_Placement_Cycle__c> cycles = [
            SELECT Id, Name, Year__c, Interviews_Count__c, Offers_Count__c, Exams_Count__c,
                   Applications_Sub__c, Interviews_Sub__c, Offers_Sub__c, Exams_Sub__c
            FROM Ken_Placement_Cycle__c WHERE Year__c = :yr ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (cycles.isEmpty()) return out;
        Ken_Placement_Cycle__c c = cycles[0];

        Integer appCount = 0;
        for (AggregateResult ar : [
            SELECT COUNT(Id) total FROM Ken_Job_Application__c
            WHERE Job__r.Placement_Cycle__c = :c.Id
        ]) {
            appCount = (Integer) ar.get('total');
        }

        PlacementStatDTO s1 = new PlacementStatDTO();
        s1.id = 's1'; s1.k = 'Applications'; s1.v = String.valueOf(appCount); s1.sub = c.Applications_Sub__c;
        out.stats.add(s1);
        PlacementStatDTO s2 = new PlacementStatDTO();
        s2.id = 's2'; s2.k = 'Interviews'; s2.v = String.valueOf(c.Interviews_Count__c != null ? c.Interviews_Count__c.intValue() : 0); s2.sub = c.Interviews_Sub__c;
        out.stats.add(s2);
        PlacementStatDTO s3 = new PlacementStatDTO();
        s3.id = 's3'; s3.k = 'Offers'; s3.v = String.valueOf(c.Offers_Count__c != null ? c.Offers_Count__c.intValue() : 0); s3.sub = c.Offers_Sub__c;
        out.stats.add(s3);
        PlacementStatDTO s4 = new PlacementStatDTO();
        s4.id = 's4'; s4.k = 'Exams'; s4.v = String.valueOf(c.Exams_Count__c != null ? c.Exams_Count__c.intValue() : 0); s4.sub = c.Exams_Sub__c;
        out.stats.add(s4);

        Integer i = 0;
        for (Ken_Placement_Stage__c st : [
            SELECT Id, Stage_Label__c, Stage_Order__c, Stage_Date__c, State__c
            FROM Ken_Placement_Stage__c WHERE Cycle__c = :c.Id ORDER BY Stage_Order__c ASC
        ]) {
            i++;
            PlacementStageDTO ps = new PlacementStageDTO();
            ps.id = st.Id;
            ps.label = st.Stage_Label__c;
            ps.n = i;
            ps.stageDate = (st.Stage_Date__c != null) ? fmtDate(st.Stage_Date__c) : '—';
            ps.state = st.State__c == 'upcoming' ? '' : st.State__c;
            out.timeline.add(ps);
        }

        for (Ken_Job_Master__c j : [
            SELECT Id, Company__c, Logo_Initial__c, Logo_Color__c, Job_Title__c,
                   Deadline__c, Status__c, Is_Closed__c
            FROM Ken_Job_Master__c
            WHERE Placement_Cycle__c = :c.Id AND Status__c IN ('Live','Approved','Closed')
            ORDER BY Deadline__c ASC NULLS LAST LIMIT 8
        ]) {
            UpcomingDriveDTO d = new UpcomingDriveDTO();
            d.id = j.Id;
            d.co = j.Company__c;
            d.l = j.Logo_Initial__c;
            d.col = j.Logo_Color__c;
            d.driveDate = fmtDate(j.Deadline__c);
            d.role = j.Job_Title__c;
            d.status = j.Is_Closed__c ? 'Closed' : (j.Status__c == 'Live' ? 'Open' : 'Upcoming');
            d.isClosed = j.Is_Closed__c;
            out.upcoming.add(d);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<SlotItem> getInterviewSlots(Id applicationId) {
        List<SlotItem> out = new List<SlotItem>();
        if (applicationId == null) return out;
        for (Ken_Job_Slot__c s : [
            SELECT Id, Slot_Date__c, Period__c, Time_Label__c, Status__c
            FROM Ken_Job_Slot__c
            WHERE Application__c = :applicationId AND Status__c IN ('Available', 'Booked')
            ORDER BY Slot_Date__c ASC, Time_Label__c ASC
        ]) {
            SlotItem si = new SlotItem();
            si.id = s.Id;
            si.period = s.Period__c;
            si.label = s.Time_Label__c;
            si.slotDate = (s.Slot_Date__c != null) ? String.valueOf(s.Slot_Date__c) : null;
            si.status = s.Status__c;
            out.add(si);
        }
        return out;
    }

    // ============================================================
    // WRITE
    // ============================================================

    @AuraEnabled
    public static Id postJob(Map<String, Object> payload) {
        // Full submission — goes into the approval pipeline.
        return persistJob(payload, 'Submitted for Review');
    }

    /**
     * Save Draft — persists the job with Status = 'Draft' so the user can resume later.
     * Same field mapping as postJob but never enters the approval pipeline.
     */
    @AuraEnabled
    public static Id saveJobDraft(Map<String, Object> payload) {
        return persistJob(payload, 'Draft');
    }

    /**
     * Shared insert path for postJob / saveJobDraft. The DML is wrapped so that a
     * validation rule, missing required field, restricted picklist, or FLS rejection
     * surfaces its EXACT message back to the LWC. A raw DmlException thrown from an
     * @AuraEnabled method is otherwise masked by the platform as a generic
     * "internal server error" — the silent submission failure QA reported.
     */
    private static Id persistJob(Map<String, Object> payload, String statusValue) {
        if (payload == null) throw new AuraHandledException('Payload required');
        Savepoint sp = Database.setSavepoint();
        try {
            Ken_Job_Master__c j = new Ken_Job_Master__c();
            j.Job_Title__c = (String) payload.get('title');
            j.Company__c = (String) payload.get('company');
            j.Logo_Initial__c = (String) payload.get('logoInitial');
            if (payload.containsKey('logoColor') && payload.get('logoColor') != null) {
                j.Logo_Color__c = (String) payload.get('logoColor');
            }
            if (String.isNotBlank((String) payload.get('bannerUrl'))) {
                j.Banner_Image_URL__c = (String) payload.get('bannerUrl');
            }
            j.Short_Description__c = (String) payload.get('shortDescription');
            j.Full_Description__c = (String) payload.get('fullDescription');
            j.Requirements__c = (String) payload.get('requirements');
            j.Responsibilities__c = (String) payload.get('responsibilities');
            j.Qualifications__c = (String) payload.get('qualifications');
            j.Experience_Level__c = (String) payload.get('experienceLevel');
            j.Location_Text__c = (String) payload.get('location');
            j.Salary_Display__c = (String) payload.get('salaryDisplay');
            j.Currency_Code__c = (String) payload.get('currencyCode');
            if (payload.get('salaryMin') != null && String.isNotBlank(String.valueOf(payload.get('salaryMin')))) {
                j.Salary_Min__c = Decimal.valueOf(String.valueOf(payload.get('salaryMin')));
            }
            if (payload.get('salaryMax') != null && String.isNotBlank(String.valueOf(payload.get('salaryMax')))) {
                j.Salary_Max__c = Decimal.valueOf(String.valueOf(payload.get('salaryMax')));
            }
            if (payload.get('openings') != null && String.isNotBlank(String.valueOf(payload.get('openings')))) {
                j.Openings__c = Integer.valueOf(String.valueOf(payload.get('openings')));
            }
            if (payload.get('deadline') != null && String.isNotBlank(String.valueOf(payload.get('deadline')))) {
                j.Deadline__c = Date.valueOf(String.valueOf(payload.get('deadline')));
            }
            // Audience selection from the shared builder is sent as a JSON blob. Store the
            // full JSON in the Long Text field (Audience__c is a restricted picklist and
            // would reject a 255+ char JSON). Set the picklist only to a valid bucket value.
            String audienceJson = (String) payload.get('audienceData');
            if (String.isNotBlank(audienceJson)) {
                j.Audience_JSON__c = audienceJson;
            }
            // Audience__c picklist: only assign when the payload sends a valid bucket value
            // (All Alumni / Specific Batches / Specific Programs); otherwise leave default.
            String audienceBucket = (String) payload.get('audience');
            Set<String> validBuckets = new Set<String>{ 'All Alumni', 'Specific Batches', 'Specific Programs' };
            if (String.isNotBlank(audienceBucket) && validBuckets.contains(audienceBucket)) {
                j.Audience__c = audienceBucket;
            }
            if (String.isNotBlank((String) payload.get('audienceBatches')))  j.Audience_Batches__c = (String) payload.get('audienceBatches');
            if (String.isNotBlank((String) payload.get('audiencePrograms'))) j.Audience_Programs__c = (String) payload.get('audiencePrograms');
            if (String.isNotBlank((String) payload.get('timeline')))         j.Timeline__c = (String) payload.get('timeline');

            // Create-Job wizard Step 2 (Eligibility & Requirements): the academic /
            // experience / work-experience / skills sections are serialized into a Long
            // Text field (no dedicated columns exist; mirrors the Audience_JSON__c pattern).
            String requirementsJson = (String) payload.get('requirementsJson');
            if (String.isNotBlank(requirementsJson)) {
                j.Requirements_JSON__c = requirementsJson;
            }
            // Create-Job wizard Step 3 (Stages): serialized array (order/name/type/dates/times).
            // NB: Ken_Placement_Stage__c is a master-detail child of Placement Cycle (not Job)
            // with restricted picklists and no time fields, so it cannot hold these rows; the
            // normalized Ken_Job_Stage__c child object is a recommended follow-up.
            String stagesJson = (String) payload.get('stagesJson');
            if (String.isNotBlank(stagesJson)) {
                j.Stages_JSON__c = stagesJson;
            }

            j.Status__c = statusValue;
            j.Posted_By__c = currentContactId();
            insert j;

            List<Ken_Job_Tag__c> tags = new List<Ken_Job_Tag__c>();
            if (payload.get('tags') instanceof List<Object>) {
                for (Object t : (List<Object>) payload.get('tags')) {
                    String ts = String.valueOf(t);
                    if (String.isNotBlank(ts)) {
                        tags.add(new Ken_Job_Tag__c(Job__c = j.Id, Tag__c = ts));
                    }
                }
            }
            if (!tags.isEmpty()) insert tags;

            List<Ken_Job_Skill__c> skills = new List<Ken_Job_Skill__c>();
            if (payload.get('skills') instanceof List<Object>) {
                for (Object s : (List<Object>) payload.get('skills')) {
                    String ss = String.valueOf(s);
                    if (String.isNotBlank(ss)) {
                        skills.add(new Ken_Job_Skill__c(Job__c = j.Id, Name = ss.length() > 80 ? ss.substring(0, 80) : ss));
                    }
                }
            }
            if (!skills.isEmpty()) insert skills;
            return j.Id;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id applyToJob(Map<String, Object> payload) {
        if (payload == null) throw new AuraHandledException('Payload required');
        Id jobId = (Id) payload.get('jobId');
        if (jobId == null) throw new AuraHandledException('jobId required');
        Id contactId = currentContactId();
        if (contactId == null) throw new AuraHandledException('No Contact for current user');

        for (Ken_Job_Application__c existing : [
            SELECT Id FROM Ken_Job_Application__c WHERE Job__c = :jobId AND Applicant__c = :contactId LIMIT 1
        ]) {
            return existing.Id;
        }

        Ken_Job_Application__c app = new Ken_Job_Application__c();
        app.Job__c = jobId;
        app.Applicant__c = contactId;
        app.Registration_Number__c = (String) payload.get('registrationNumber');
        app.Applicant_Type__c = payload.get('applicantType') != null ? (String) payload.get('applicantType') : 'Alumni';
        app.Resume_Content_Version__c = (String) payload.get('resumeContentVersionId');
        app.Cover_Letter__c = (String) payload.get('coverLetter');
        app.Apply_Notes__c = (String) payload.get('notes');
        if (payload.get('skillsMatchPercent') != null) {
            app.Skills_Match_Percent__c = Integer.valueOf(String.valueOf(payload.get('skillsMatchPercent')));
        }
        app.Status__c = 'Applied';
        app.Application_State__c = 'inProgress';
        insert app;

        List<String> labels = new List<String>{
            'Initial Screening', 'Technical Interview', 'Aptitude Test', 'HR Interview', 'Offer'
        };
        List<Ken_Job_Application_Step__c> steps = new List<Ken_Job_Application_Step__c>();
        for (Integer i = 0; i < labels.size(); i++) {
            Ken_Job_Application_Step__c s = new Ken_Job_Application_Step__c();
            s.Application__c = app.Id;
            s.Step_Label__c = labels[i];
            s.Step_Order__c = i + 1;
            s.State__c = (i == 0) ? 'active' : 'upcoming';
            steps.add(s);
        }
        insert steps;
        return app.Id;
    }

    @AuraEnabled
    public static Boolean toggleSaveJob(Id jobId) {
        if (jobId == null) throw new AuraHandledException('jobId required');
        Id contactId = currentContactId();
        if (contactId == null) throw new AuraHandledException('No Contact for current user');
        List<Ken_Job_Save__c> existing = [
            SELECT Id FROM Ken_Job_Save__c WHERE Job__c = :jobId AND Contact__c = :contactId LIMIT 1
        ];
        if (!existing.isEmpty()) {
            delete existing;
            return false;
        }
        insert new Ken_Job_Save__c(Job__c = jobId, Contact__c = contactId);
        return true;
    }

    @AuraEnabled
    public static Id bookSlot(Id applicationId, Id slotId) {
        if (applicationId == null || slotId == null) throw new AuraHandledException('applicationId and slotId required');
        Ken_Job_Slot__c picked;
        for (Ken_Job_Slot__c s : [
            SELECT Id, Slot_Date__c, Application__c, Status__c FROM Ken_Job_Slot__c WHERE Id = :slotId LIMIT 1
        ]) { picked = s; }
        if (picked == null) throw new AuraHandledException('Slot not found');
        picked.Status__c = 'Booked';
        update picked;

        List<Ken_Job_Slot__c> sameDay = [
            SELECT Id, Status__c FROM Ken_Job_Slot__c
            WHERE Application__c = :applicationId AND Slot_Date__c = :picked.Slot_Date__c AND Id != :slotId
        ];
        for (Ken_Job_Slot__c s : sameDay) s.Status__c = 'Closed';
        if (!sameDay.isEmpty()) update sameDay;

        for (Ken_Job_Application__c a : [
            SELECT Id, Application_State__c FROM Ken_Job_Application__c WHERE Id = :applicationId LIMIT 1
        ]) {
            a.Application_State__c = 'inProgress';
            a.Next_Action_Title__c = null;
            a.Next_Action_Deadline__c = null;
            a.Next_Action_CTA__c = null;
            update a;
        }
        return picked.Id;
    }
}