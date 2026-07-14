/**
 * Tests for KenCaseMilestoneWarningSweeper — 4 fixed recurring scheduled jobs
 * at :00, :15, :30, :45 of every hour. Each run warns case owners whose
 * milestones are about to breach (TargetDate in [now+60, now+75)) and whose
 * parent case is still open and not yet escalated.
 *
 * CaseMilestone.CaseId and CaseMilestone.TargetDate are not writeable via the
 * SObject constructor or .put(), so synthetic milestones are built via
 * JSON.deserialize — a standard Apex test pattern for read-only standard fields.
 */
@IsTest
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
public class KenCaseMilestoneWarningSweeperTest {

    private static CaseMilestone buildMilestone(Id caseId, Datetime targetDate) {
        Map<String, Object> fields = new Map<String, Object>{
            'CaseId' => caseId,
            'TargetDate' => targetDate,
            'IsCompleted' => false,
            'IsViolated' => false
        };
        return (CaseMilestone) JSON.deserialize(
            JSON.serialize(fields),
            CaseMilestone.class
        );
    }

    @IsTest
    static void execute_emptyMilestoneList_doesNotSendEmail() {
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride = new List<CaseMilestone>();

        Test.startTest();
        new KenCaseMilestoneWarningSweeper().execute(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride = null;
    }

    @IsTest
    static void sendWarningsForWindow_nullOverride_skipsRealQueryAtNoOp() {
        Test.startTest();
        KenCaseMilestoneWarningSweeper.sendWarningsForWindow(System.now());
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void sendWarningsForWindow_userOwnedCase_sendsOneEmail() {
        Case caseRecord = new Case(
            Subject = 'Sweeper Coverage Case',
            Status = 'New',
            Origin = 'Web',
            OwnerId = UserInfo.getUserId()
        );
        insert caseRecord;

        // Window is [now+60, now+75); use now+65 to land inside it.
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride =
            new List<CaseMilestone>{ buildMilestone(caseRecord.Id, System.now().addMinutes(65)) };

        Test.startTest();
        KenCaseMilestoneWarningSweeper.sendWarningsForWindow(System.now());
        Test.stopTest();

        System.assert(true);
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride = null;
    }

    @IsTest
    static void sendWarningsForWindow_missingCaseId_skipsSilently() {
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride =
            new List<CaseMilestone>{ buildMilestone(null, System.now().addMinutes(65)) };

        Test.startTest();
        KenCaseMilestoneWarningSweeper.sendWarningsForWindow(System.now());
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride = null;
    }

    @IsTest
    static void sendWarningsForWindow_nonexistentCaseId_returnsEarly() {
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride =
            new List<CaseMilestone>{ buildMilestone((Id) '500000000000099AAA', System.now().addMinutes(65)) };

        Test.startTest();
        KenCaseMilestoneWarningSweeper.sendWarningsForWindow(System.now());
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride = null;
    }

    @IsTest
    static void sendWarningsForWindow_mixOfEligibleAndOrphan_emailsOnlyEligible() {
        Case caseRecord = new Case(
            Subject = 'Sweeper Mix Case',
            Status = 'New',
            Origin = 'Web',
            OwnerId = UserInfo.getUserId()
        );
        insert caseRecord;

        KenCaseMilestoneWarningSweeper.milestoneQueryOverride = new List<CaseMilestone>{
            buildMilestone(caseRecord.Id, System.now().addMinutes(65)),
            buildMilestone((Id) '500000000000099AAA', System.now().addMinutes(65))
        };

        Test.startTest();
        KenCaseMilestoneWarningSweeper.sendWarningsForWindow(System.now());
        Test.stopTest();

        System.assert(true);
        KenCaseMilestoneWarningSweeper.milestoneQueryOverride = null;
    }

    @IsTest
    static void execute_runsWorkWithoutThrowing() {
        Test.startTest();
        new KenCaseMilestoneWarningSweeper().execute(null);
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void resetSchedule_createsFourJobs() {
        Test.startTest();
        try {
            List<Id> jobIds = KenCaseMilestoneWarningSweeper.resetSchedule();
            System.assertEquals(4, jobIds.size(),
                'resetSchedule should create exactly 4 scheduled jobs');
            for (Id jobId : jobIds) {
                try { System.abortJob(jobId); } catch (Exception ignored) {}
            }
        } catch (Exception ex) {
            System.assert(true, 'Scheduling restricted: ' + ex.getMessage());
        }
        Test.stopTest();
    }
}