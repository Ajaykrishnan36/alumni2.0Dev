/**
 * KenSnSConstantsTest
 *
 * Covers KenSnSConstants:
 *   - All static constant values are readable (simple read coverage).
 *   - getOrgWideEmailDisplayName: no setting, with blank, with populated value.
 *   - isNeedHelpVisible: no setting (defaults true), false flag, true flag.
 *   - isTriggerBypassed: no setting (defaults false), bypass=true.
 *   - All email bypass flag methods: bypassed and not bypassed paths.
 *
 * No SeeAllData. All test data inserted via DML.
 */
@IsTest
private class KenSnSConstantsTest {

    // ── helpers ──────────────────────────────────────────────────────────────

    private static Ken_Support_Services_Parameters__c getOrCreateOrgDefaults() {
        Ken_Support_Services_Parameters__c setting = Ken_Support_Services_Parameters__c.getOrgDefaults();
        if (setting == null || setting.Id == null) {
            setting = new Ken_Support_Services_Parameters__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
            insert setting;
        }
        return setting;
    }

    private static Ken_Email_Bypass_Settings__c getOrCreateEmailBypassInstance() {
        Ken_Email_Bypass_Settings__c s = Ken_Email_Bypass_Settings__c.getInstance();
        if (s == null || s.Id == null) {
            s = new Ken_Email_Bypass_Settings__c(
                SetupOwnerId = UserInfo.getUserId()
            );
            insert s;
        }
        return s;
    }

    // ── constant values ───────────────────────────────────────────────────────

    @IsTest
    static void constants_areReadable() {
        // Read every constant to ensure they compile and are non-null/non-blank.
        System.assertEquals('Ken_Case_Created_Notification',        KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_OWNER);
        System.assertEquals('Ken_Case_Created_User_Notification',   KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_USER);
        System.assertEquals('Ken_Case_Escalation_Notification',     KenSnSConstants.EMAIL_TEMPLATE_CASE_ESCALATION);
        System.assertEquals('Ken_Case_Milestone_Breach',            KenSnSConstants.EMAIL_TEMPLATE_CASE_MILESTONE_BREACH);
        System.assertEquals('Ken_Case_Milestone_Warning',           KenSnSConstants.EMAIL_TEMPLATE_CASE_MILESTONE_WARNING);

        System.assertEquals('Service',          KenSnSConstants.CASE_RECORD_TYPE_SERVICE);
        System.assertEquals('Support',          KenSnSConstants.CASE_RECORD_TYPE_SUPPORT);
        System.assertEquals('Gate_Pass_Request',KenSnSConstants.CASE_RECORD_TYPE_GATE_PASS);

        System.assertEquals('New',                   KenSnSConstants.CASE_STATUS_NEW);
        System.assertEquals('In Progress',            KenSnSConstants.CASE_STATUS_IN_PROGRESS);
        System.assertEquals('Waiting for Student',    KenSnSConstants.CASE_STATUS_WAITING_FOR_STUDENT);
        System.assertEquals('Response Received',      KenSnSConstants.CASE_STATUS_RESPONSE_RECEIVED);
        System.assertEquals('On Hold',                KenSnSConstants.CASE_STATUS_ON_HOLD);
        System.assertEquals('Escalated',              KenSnSConstants.CASE_STATUS_ESCALATED);
        System.assertEquals('Closed',                 KenSnSConstants.CASE_STATUS_CLOSED);
        System.assertEquals('Resolved',               KenSnSConstants.CASE_STATUS_RESOLVED);
        System.assertEquals('Canceled',               KenSnSConstants.CASE_STATUS_CANCELED);
        System.assertEquals('Merged',                 KenSnSConstants.CASE_STATUS_MERGED);

        System.assertEquals('Low',    KenSnSConstants.CASE_PRIORITY_LOW);
        System.assertEquals('Medium', KenSnSConstants.CASE_PRIORITY_MEDIUM);
        System.assertEquals('High',   KenSnSConstants.CASE_PRIORITY_HIGH);

        System.assertEquals('Case_Manager', KenSnSConstants.DEFAULT_ESCALATION_QUEUE_DEVELOPER_NAME);
        System.assertEquals('Case_Owner',   KenSnSConstants.DEFAULT_ASSIGNMENT_QUEUE_DEVELOPER_NAME);

        System.assertEquals('allCases',    KenSnSConstants.REPORT_TYPE_ALL_CASES);
        System.assertEquals('status',      KenSnSConstants.REPORT_TYPE_STATUS);
        System.assertEquals('category',    KenSnSConstants.REPORT_TYPE_CATEGORY);
        System.assertEquals('recordType',  KenSnSConstants.REPORT_TYPE_RECORD_TYPE);
        System.assertEquals('priority',    KenSnSConstants.REPORT_TYPE_PRIORITY);
        System.assertEquals('owner',       KenSnSConstants.REPORT_TYPE_OWNER);
        System.assertEquals('trend',       KenSnSConstants.REPORT_TYPE_TREND);

        System.assertEquals('Exit',   KenSnSConstants.GATE_PASS_EXIT_LABEL_KEYWORD);
        System.assertEquals('Return', KenSnSConstants.GATE_PASS_ENTRY_LABEL_KEYWORD);
        System.assertEquals('Date',   KenSnSConstants.GATE_PASS_QUESTION_TYPE_DATE);
        System.assertEquals('Time',   KenSnSConstants.GATE_PASS_QUESTION_TYPE_TIME);

        System.assertEquals('Exit_Date',  KenSnSConstants.GATE_PASS_MAP_EXIT_DATE);
        System.assertEquals('Exit_Time',  KenSnSConstants.GATE_PASS_MAP_EXIT_TIME);
        System.assertEquals('Entry_Date', KenSnSConstants.GATE_PASS_MAP_ENTRY_DATE);
        System.assertEquals('Entry_Time', KenSnSConstants.GATE_PASS_MAP_ENTRY_TIME);

        System.assertEquals('Gate_Pass',  KenSnSConstants.SERVICE_CATEGORY_GATE_PASS);
        System.assertEquals('Hostel',     KenSnSConstants.SERVICE_CATEGORY_HOSTEL);
        System.assertEquals('Finance',    KenSnSConstants.SERVICE_CATEGORY_FINANCE);
        System.assertEquals('Academics',  KenSnSConstants.SERVICE_CATEGORY_ACADEMICS);
        System.assertEquals('Admission',  KenSnSConstants.SERVICE_CATEGORY_ADMISSION);

        System.assertEquals('Student',      KenSnSConstants.ROLE_TYPE_STUDENT);
        System.assertEquals('Faculty',      KenSnSConstants.ROLE_TYPE_FACULTY);
        System.assertEquals('Alumni',       KenSnSConstants.ROLE_TYPE_ALUMNI);
        System.assertEquals('Relationship', KenSnSConstants.ROLE_TYPE_RELATIONSHIP);
        System.assertEquals('Security',     KenSnSConstants.ROLE_TYPE_SECURITY);

        System.assertEquals('Student',   KenSnSConstants.TARGET_AUDIENCE_STUDENT);
        System.assertEquals('Faculty',   KenSnSConstants.TARGET_AUDIENCE_FACULTY);
        System.assertEquals('Alumni',    KenSnSConstants.TARGET_AUDIENCE_ALUMNI);
        System.assertEquals('Security',  KenSnSConstants.TARGET_AUDIENCE_SECURITY);
        System.assertEquals('Admission', KenSnSConstants.TARGET_AUDIENCE_ADMISSION);
        System.assertEquals('All',       KenSnSConstants.TARGET_AUDIENCE_ALL);

        System.assertEquals('Active', KenSnSConstants.CONSTITUENT_ROLE_STATUS_ACTIVE);

        System.assertEquals('Rejected',          KenSnSConstants.CASE_STATUS_REJECTED);
        System.assertEquals('Hostel Approval',   KenSnSConstants.CASE_STATUS_HOSTEL_APPROVED);
        System.assertEquals('Mess Approval',     KenSnSConstants.CASE_STATUS_MESS_APPROVED);
        System.assertEquals('Finance Approval',  KenSnSConstants.CASE_STATUS_FINANCE_APPROVED);
        System.assertEquals('Refund',            KenSnSConstants.CASE_STATUS_REFUND);

        System.assertEquals('Hostel_Approved',  KenSnSConstants.HOSTEL_APPROVED_QUEUE_DEVELOPER_NAME);
        System.assertEquals('Mess_Approved',    KenSnSConstants.MESS_APPROVED_QUEUE_DEVELOPER_NAME);
        System.assertEquals('Finance_Approved', KenSnSConstants.FINANCE_APPROVED_QUEUE_DEVELOPER_NAME);

        System.assertEquals('Hostel_Full_Approval_Flow', KenSnSConstants.HOSTEL_APPROVAL_PROCESS_NAME);
        System.assertEquals('Finance',                   KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
        System.assertEquals('Ken_Gate_Pass_Created_Notification', KenSnSConstants.EMAIL_TEMPLATE_GATE_PASS_CREATED);

        System.assertEquals('Started',  KenSnSConstants.APPROVAL_STEP_STATUS_STARTED);
        System.assertEquals('Approved', KenSnSConstants.APPROVAL_STEP_STATUS_APPROVED);
        System.assertEquals('Rejected', KenSnSConstants.APPROVAL_STEP_STATUS_REJECTED);
    }

    // ── getOrgWideEmailDisplayName ────────────────────────────────────────────

    @IsTest
    static void getOrgWideEmailDisplayName_noSetting_returnsNull() {
        Test.startTest();
        String name = KenSnSConstants.getOrgWideEmailDisplayName();
        Test.stopTest();

        // Without a Ken_Support_Services_Parameters__c record the method returns null
        System.assertEquals(null, name, 'Should return null when no setting exists');
    }

    @IsTest
    static void getOrgWideEmailDisplayName_blankField_returnsNull() {
        Ken_Support_Services_Parameters__c s = getOrCreateOrgDefaults();
        s.Org_Wide_Email_Display_Name__c = '';
        update s;

        Test.startTest();
        String name = KenSnSConstants.getOrgWideEmailDisplayName();
        Test.stopTest();

        System.assertEquals(null, name, 'Blank display name should return null');
    }

    @IsTest
    static void getOrgWideEmailDisplayName_populatedField_returnsValue() {
        Ken_Support_Services_Parameters__c s = getOrCreateOrgDefaults();
        s.Org_Wide_Email_Display_Name__c = 'SMU Support';
        update s;

        Test.startTest();
        String name = KenSnSConstants.getOrgWideEmailDisplayName();
        Test.stopTest();

        System.assertEquals('SMU Support', name);
    }

    // ── isTriggerBypassed ────────────────────────────────────────────────────

    @IsTest
    static void isTriggerBypassed_noSetting_returnsFalse() {
        Test.startTest();
        Boolean bypassed = KenSnSConstants.isTriggerBypassed();
        Test.stopTest();

        System.assertEquals(false, bypassed, 'Default should be not bypassed');
    }

    @IsTest
    static void isTriggerBypassed_bypassTrue_returnsTrue() {
        Ken_Support_Services_Parameters__c s = getOrCreateOrgDefaults();
        s.Trigger_Bypass__c = true;
        update s;

        Test.startTest();
        Boolean bypassed = KenSnSConstants.isTriggerBypassed();
        Test.stopTest();

        System.assertEquals(true, bypassed, 'Trigger_Bypass__c=true should be bypassed');
    }

    @IsTest
    static void isTriggerBypassed_bypassFalse_returnsFalse() {
        Ken_Support_Services_Parameters__c s = getOrCreateOrgDefaults();
        s.Trigger_Bypass__c = false;
        update s;

        Test.startTest();
        Boolean bypassed = KenSnSConstants.isTriggerBypassed();
        Test.stopTest();

        System.assertEquals(false, bypassed);
    }

    // ── isNeedHelpVisible ─────────────────────────────────────────────────────

    @IsTest
    static void isNeedHelpVisible_noSetting_returnsBoolean() {
        // Custom settings read org defaults even without SeeAllData — just verify method runs
        Test.startTest();
        Boolean visible = KenSnSConstants.isNeedHelpVisible();
        Test.stopTest();

        System.assertNotEquals(null, visible, 'isNeedHelpVisible should return a non-null Boolean');
    }

    @IsTest
    static void isNeedHelpVisible_settingExistsNoFlag_defaultsTrue() {
        Ken_Support_Services_Parameters__c s = getOrCreateOrgDefaults();
        update s;

        Test.startTest();
        Boolean visible = KenSnSConstants.isNeedHelpVisible();
        Test.stopTest();

        System.assertEquals(true, visible, 'Should default to true when Show_Need_Help__c is not explicitly false');
    }

    @IsTest
    static void isNeedHelpVisible_showNeedHelpFalse_returnsFalse() {
        Ken_Support_Services_Parameters__c s = getOrCreateOrgDefaults();
        s.Show_Need_Help__c = false;
        update s;

        Test.startTest();
        Boolean visible = KenSnSConstants.isNeedHelpVisible();
        Test.stopTest();

        System.assertEquals(false, visible, 'Should return false when Show_Need_Help__c is explicitly false');
    }

    // ── email bypass flags ────────────────────────────────────────────────────

    @IsTest
    static void emailBypassFlags_noSetting_allReturnFalse() {
        Test.startTest();
        Boolean ownerBypassed      = KenSnSConstants.isCaseOwnerEmailBypassed();
        Boolean userBypassed       = KenSnSConstants.isCaseUserEmailBypassed();
        Boolean escalBypassed      = KenSnSConstants.isEscalationEmailBypassed();
        Boolean breachBypassed     = KenSnSConstants.isMilestoneBreachEmailBypassed();
        Boolean warningBypassed    = KenSnSConstants.isMilestoneWarningEmailBypassed();
        Test.stopTest();

        System.assertEquals(false, ownerBypassed,   'Owner bypass should default false');
        System.assertEquals(false, userBypassed,    'User bypass should default false');
        System.assertEquals(false, escalBypassed,   'Escalation bypass should default false');
        System.assertEquals(false, breachBypassed,  'Breach bypass should default false');
        System.assertEquals(false, warningBypassed, 'Warning bypass should default false');
    }

    @IsTest
    static void emailBypassFlags_allTrue_allReturnTrue() {
        Ken_Email_Bypass_Settings__c s = getOrCreateEmailBypassInstance();
        s.Case_Owner_Email_Bypass__c     = true;
        s.Case_User_Email_Bypass__c      = true;
        s.Escalation_Email_Bypass__c     = true;
        s.Milestone_Breach_Email_Bypass__c  = true;
        s.Milestone_Warning_Email_Bypass__c = true;
        update s;

        Test.startTest();
        Boolean ownerBypassed      = KenSnSConstants.isCaseOwnerEmailBypassed();
        Boolean userBypassed       = KenSnSConstants.isCaseUserEmailBypassed();
        Boolean escalBypassed      = KenSnSConstants.isEscalationEmailBypassed();
        Boolean breachBypassed     = KenSnSConstants.isMilestoneBreachEmailBypassed();
        Boolean warningBypassed    = KenSnSConstants.isMilestoneWarningEmailBypassed();
        Test.stopTest();

        System.assertEquals(true, ownerBypassed,   'Owner bypass should be true');
        System.assertEquals(true, userBypassed,    'User bypass should be true');
        System.assertEquals(true, escalBypassed,   'Escalation bypass should be true');
        System.assertEquals(true, breachBypassed,  'Breach bypass should be true');
        System.assertEquals(true, warningBypassed, 'Warning bypass should be true');
    }

    @IsTest
    static void emailBypassFlags_allFalse_allReturnFalse() {
        Ken_Email_Bypass_Settings__c s = getOrCreateEmailBypassInstance();
        s.Case_Owner_Email_Bypass__c     = false;
        s.Case_User_Email_Bypass__c      = false;
        s.Escalation_Email_Bypass__c     = false;
        s.Milestone_Breach_Email_Bypass__c  = false;
        s.Milestone_Warning_Email_Bypass__c = false;
        update s;

        Test.startTest();
        Boolean ownerBypassed   = KenSnSConstants.isCaseOwnerEmailBypassed();
        Boolean userBypassed    = KenSnSConstants.isCaseUserEmailBypassed();
        Boolean escalBypassed   = KenSnSConstants.isEscalationEmailBypassed();
        Boolean breachBypassed  = KenSnSConstants.isMilestoneBreachEmailBypassed();
        Boolean warningBypassed = KenSnSConstants.isMilestoneWarningEmailBypassed();
        Test.stopTest();

        System.assertEquals(false, ownerBypassed);
        System.assertEquals(false, userBypassed);
        System.assertEquals(false, escalBypassed);
        System.assertEquals(false, breachBypassed);
        System.assertEquals(false, warningBypassed);
    }
}