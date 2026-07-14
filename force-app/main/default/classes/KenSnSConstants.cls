/**
 * KenSnSConstants
 *
 * Centralized constants for the Service & Support (SnS) module so that
 * hardcoded literals are defined in one place. When a name changes (email
 * template DeveloperName, case status picklist value, record-type
 * DeveloperName, default queue, etc.), update this class — every consumer
 * picks up the new value.
 *
 * NOTE: org-configurable values (the escalation queue, org-wide email)
 * still read first from Ken_Support_Services_Parameters__c custom setting
 * and fall back to these constants when the setting is blank. Admins can
 * override per-org without a code change.
 */
public class KenSnSConstants {

    // -------------------------------------------------------------------
    // Org-Wide Email Address — From-address used for all SnS-sent emails.
    // Reads from Ken_Support_Services_Parameters__c.Org_Wide_Email_Display_Name__c
    // custom setting so admins can configure it per org without a code deploy.
    // -------------------------------------------------------------------
    public static String getOrgWideEmailDisplayName() {
        Ken_Support_Services_Parameters__c setting = Ken_Support_Services_Parameters__c.getOrgDefaults();
        if (setting != null && String.isNotBlank(setting.Org_Wide_Email_Display_Name__c)) {
            return setting.Org_Wide_Email_Display_Name__c;
        }
        return null;
    }

    // -------------------------------------------------------------------
    // Need Help visibility — read from Ken_Support_Services_Parameters__c.
    // Defaults to true (visible) when custom setting is not configured.
    // -------------------------------------------------------------------
    public static Boolean isNeedHelpVisible() {
        Ken_Support_Services_Parameters__c setting = Ken_Support_Services_Parameters__c.getOrgDefaults();
        // Default true — show Need Help unless explicitly set to false
        if (setting == null) return true;
        return setting.Show_Need_Help__c != false;
    }

    // -------------------------------------------------------------------
    // Trigger Bypass — read from Ken_Support_Services_Parameters__c.
    // Set Trigger_Bypass__c = true to disable case trigger logic.
    // -------------------------------------------------------------------
    public static Boolean isTriggerBypassed() {
        Ken_Support_Services_Parameters__c setting = Ken_Support_Services_Parameters__c.getOrgDefaults();
        return setting != null && setting.Trigger_Bypass__c == true;
    }

    // -------------------------------------------------------------------
    // Email Bypass flags — read from Ken_Email_Bypass_Settings__c.
    // Each flag independently controls one email notification type.
    // No hardcoding — all reads go through this constants class.
    // -------------------------------------------------------------------
    private static Ken_Email_Bypass_Settings__c getEmailBypassSettings() {
        return Ken_Email_Bypass_Settings__c.getInstance();
    }

    public static Boolean isCaseOwnerEmailBypassed() {
        Ken_Email_Bypass_Settings__c s = getEmailBypassSettings();
        return s != null && s.Case_Owner_Email_Bypass__c == true;
    }

    public static Boolean isCaseUserEmailBypassed() {
        Ken_Email_Bypass_Settings__c s = getEmailBypassSettings();
        return s != null && s.Case_User_Email_Bypass__c == true;
    }

    public static Boolean isEscalationEmailBypassed() {
        Ken_Email_Bypass_Settings__c s = getEmailBypassSettings();
        return s != null && s.Escalation_Email_Bypass__c == true;
    }

    public static Boolean isMilestoneBreachEmailBypassed() {
        Ken_Email_Bypass_Settings__c s = getEmailBypassSettings();
        return s != null && s.Milestone_Breach_Email_Bypass__c == true;
    }

    public static Boolean isMilestoneWarningEmailBypassed() {
        Ken_Email_Bypass_Settings__c s = getEmailBypassSettings();
        return s != null && s.Milestone_Warning_Email_Bypass__c == true;
    }

    // -------------------------------------------------------------------
    // Email Template DeveloperNames
    // -------------------------------------------------------------------
    public static final String EMAIL_TEMPLATE_CASE_CREATED_OWNER  = 'Ken_Case_Created_Notification';
    public static final String EMAIL_TEMPLATE_CASE_CREATED_USER   = 'Ken_Case_Created_User_Notification';
    public static final String EMAIL_TEMPLATE_CASE_ESCALATION     = 'Ken_Case_Escalation_Notification';
    public static final String EMAIL_TEMPLATE_CASE_MILESTONE_BREACH  = 'Ken_Case_Milestone_Breach';
    public static final String EMAIL_TEMPLATE_CASE_MILESTONE_WARNING = 'Ken_Case_Milestone_Warning';

    // -------------------------------------------------------------------
    // Case Record Type DeveloperNames
    // -------------------------------------------------------------------
    public static final String CASE_RECORD_TYPE_SERVICE      = 'Service';
    public static final String CASE_RECORD_TYPE_SUPPORT      = 'Support';
    public static final String CASE_RECORD_TYPE_GATE_PASS    = 'Gate_Pass_Request';

    // -------------------------------------------------------------------
    // Case Status picklist values (must match the Status picklist + Case
    // record type's Business Process).
    // -------------------------------------------------------------------
    public static final String CASE_STATUS_NEW                  = 'New';
    public static final String CASE_STATUS_IN_PROGRESS          = 'In Progress';
    public static final String CASE_STATUS_WAITING_FOR_STUDENT  = 'Waiting for Student';
    public static final String CASE_STATUS_RESPONSE_RECEIVED    = 'Response Received';
    public static final String CASE_STATUS_ON_HOLD              = 'On Hold';
    public static final String CASE_STATUS_ESCALATED            = 'Escalated';
    public static final String CASE_STATUS_CLOSED               = 'Closed';
    public static final String CASE_STATUS_RESOLVED             = 'Resolved';
    public static final String CASE_STATUS_CANCELED             = 'Canceled';
    public static final String CASE_STATUS_CANCELLED            = 'Cancelled';
    public static final String CASE_STATUS_MERGED               = 'Merged';
    public static final String CASE_STATUS_REJECTED            = 'Rejected';
    public static final String CASE_STATUS_HOSTEL_APPROVED       = 'Hostel Approval';
    public static final String CASE_STATUS_MESS_APPROVED         = 'Mess Approval';
    public static final String CASE_STATUS_FINANCE_APPROVED      = 'Finance Approval';
    public static final String CASE_STATUS_REFUND               = 'Refund';

    // -------------------------------------------------------------------
    // Constituent Role types — must match ConstituentRole.RoleType values
    // configured in the org.
    // -------------------------------------------------------------------
    public static final String ROLE_TYPE_STUDENT      = 'Student';
    public static final String ROLE_TYPE_FACULTY      = 'Faculty';
    public static final String ROLE_TYPE_ALUMNI       = 'Alumni';
    public static final String ROLE_TYPE_RELATIONSHIP = 'Relationship';
    public static final String ROLE_TYPE_SECURITY     = 'Security';

    // -------------------------------------------------------------------
    // ConstituentRole Status — standard picklist values
    // -------------------------------------------------------------------
    public static final String CONSTITUENT_ROLE_STATUS_ACTIVE = 'Active';

    // -------------------------------------------------------------------
    // Target Audience — picklist values on Ken_Service__c and
    // Ken_Service_Offering__c.Target_Audience__c. Must match API values
    // exactly. resolveUserAudienceType() maps the running user's
    // ConstituentRole.RoleType (or absence of one) to these values.
    // -------------------------------------------------------------------
    public static final String TARGET_AUDIENCE_STUDENT   = 'Student';
    public static final String TARGET_AUDIENCE_FACULTY   = 'Faculty';
    public static final String TARGET_AUDIENCE_ALUMNI    = 'Alumni';
    public static final String TARGET_AUDIENCE_SECURITY  = 'Security';
    public static final String TARGET_AUDIENCE_ADMISSION = 'Admission';
    public static final String TARGET_AUDIENCE_ALL       = 'All';

    // -------------------------------------------------------------------
    // Case Priority picklist values
    // -------------------------------------------------------------------
    public static final String CASE_PRIORITY_LOW    = 'Low';
    public static final String CASE_PRIORITY_MEDIUM = 'Medium';
    public static final String CASE_PRIORITY_HIGH   = 'High';

    // -------------------------------------------------------------------
    // Queues — only fallbacks; the live values come from
    // Ken_Support_Services_Parameters__c custom setting where applicable.
    // -------------------------------------------------------------------
    public static final String DEFAULT_ESCALATION_QUEUE_DEVELOPER_NAME = 'Case_Manager';
    // Fallback owner queue used when no specific assignment is configured.
    public static final String DEFAULT_ASSIGNMENT_QUEUE_DEVELOPER_NAME = 'Case_Owner';
    // Hostel approval flow — queue developer names
    public static final String HOSTEL_APPROVED_QUEUE_DEVELOPER_NAME  = 'Hostel_Approved';
    public static final String MESS_APPROVED_QUEUE_DEVELOPER_NAME    = 'Mess_Approved';
    public static final String FINANCE_APPROVED_QUEUE_DEVELOPER_NAME = 'Finance_Approved';

    // -------------------------------------------------------------------
    // Service Category — Ken_Service__c.Service_Category__c picklist values
    // used for cross-module deep-linking to the SnS service detail page.
    // -------------------------------------------------------------------
    public static final String SERVICE_CATEGORY_HOSTEL    = 'Hostel';
    public static final String SERVICE_CATEGORY_FINANCE   = 'Finance';
    public static final String SERVICE_CATEGORY_ACADEMICS = 'Academics';
    public static final String SERVICE_CATEGORY_ADMISSION = 'Admission';
    public static final String SERVICE_CATEGORY_GATE_PASS = 'Gate_Pass';

    // -------------------------------------------------------------------
    // Hostel — Approval Process API name (single 3-step process)
    // -------------------------------------------------------------------
    public static final String HOSTEL_APPROVAL_PROCESS_NAME = 'Hostel_Full_Approval_Flow';

    // -------------------------------------------------------------------
    // Ken_Assignment_Rule__c Stage__c picklist value for finance routing.
    // Admin tags finance user rules with Stage__c = 'Finance'.
    // Hostel user rules use blank Stage__c (general rules) — they are
    // applied at case creation via the standard updateRecordOwner call.
    // -------------------------------------------------------------------
    public static final String ASSIGNMENT_STAGE_FINANCE = 'Finance';

    // -------------------------------------------------------------------
    // Gate Pass — Email template DeveloperName
    // -------------------------------------------------------------------
    public static final String EMAIL_TEMPLATE_GATE_PASS_CREATED = 'Ken_Gate_Pass_Created_Notification';

    // -------------------------------------------------------------------
    // Gate Pass — Questionnaire question label keywords used to identify
    // exit and entry/return time responses and map them to the
    // Ken_Gate_Pass__c.Exit_Time__c and Entry_Time__c fields.
    // Short Answer responses: matched by label keyword.
    // Date/Time type responses: matched by the dedicated type value below.
    // -------------------------------------------------------------------
    public static final String GATE_PASS_EXIT_LABEL_KEYWORD  = 'Exit';
    public static final String GATE_PASS_ENTRY_LABEL_KEYWORD = 'Return';
    public static final String GATE_PASS_QUESTION_TYPE_DATE  = 'Date';
    public static final String GATE_PASS_QUESTION_TYPE_TIME  = 'Time';

    // -------------------------------------------------------------------
    // Gate Pass — Gate_Pass_Mapping__c picklist values on
    // Ken_Questionnaire_Parameter__c. Used to explicitly map a question
    // to Exit_Time__c or Entry_Time__c on Ken_Gate_Pass__c.
    // -------------------------------------------------------------------
    public static final String GATE_PASS_MAP_EXIT_DATE  = 'Exit_Date';
    public static final String GATE_PASS_MAP_EXIT_TIME  = 'Exit_Time';
    public static final String GATE_PASS_MAP_ENTRY_DATE = 'Entry_Date';
    public static final String GATE_PASS_MAP_ENTRY_TIME = 'Entry_Time';

    // -------------------------------------------------------------------
    // Approval Process — ProcessInstanceStep.StepStatus API values
    // -------------------------------------------------------------------
    public static final String APPROVAL_STEP_STATUS_STARTED  = 'Started';
    public static final String APPROVAL_STEP_STATUS_APPROVED = 'Approved';
    public static final String APPROVAL_STEP_STATUS_REJECTED = 'Rejected';

    // CSS modifier tokens returned to LWC for approval-row styling
    public static final String APPROVAL_DECISION_CLASS_APPROVED = 'ah-decision ah-approved';
    public static final String APPROVAL_DECISION_CLASS_REJECTED = 'ah-decision ah-rejected';
    public static final String APPROVAL_DECISION_CLASS_DEFAULT  = 'ah-decision';

    // -------------------------------------------------------------------
    // Reports & Dashboard — reportType values for KenSnSReportsController
    // -------------------------------------------------------------------
    public static final String REPORT_TYPE_ALL_CASES   = 'allCases';
    public static final String REPORT_TYPE_STATUS      = 'status';
    public static final String REPORT_TYPE_CATEGORY    = 'category';
    public static final String REPORT_TYPE_RECORD_TYPE = 'recordType';
    public static final String REPORT_TYPE_PRIORITY    = 'priority';
    public static final String REPORT_TYPE_OWNER       = 'owner';
    public static final String REPORT_TYPE_TREND       = 'trend';

}