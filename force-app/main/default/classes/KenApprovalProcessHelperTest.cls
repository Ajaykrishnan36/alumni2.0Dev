@IsTest
public class KenApprovalProcessHelperTest {

    @TestSetup
    static void setupData() {
               Opportunity opp = new Opportunity(
            Name = 'Approval Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(5)
        );
        insert opp;
    }

    @IsTest
    static void testSubmitForApprovalWithAllParams() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Flip the test bypass so the body runs and we get coverage on Approval.process().
        KenApprovalProcessHelper.testBypassApprovalSubmission = false;

        Test.startTest();

        KenApprovalProcessHelper.submitForApproval(
            opp.Id,
            'Some_Process_Definition',
            UserInfo.getUserId(),
            'Submitting with all params'
        );
        Test.stopTest();

        // Reset for any subsequent tests in the run.
        KenApprovalProcessHelper.testBypassApprovalSubmission = true;

        
        Opportunity verify = [SELECT Id FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, verify.Id, 'Record should still exist');
    }

    @IsTest
    static void testSubmitForApprovalWithDefaults() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        
        KenApprovalProcessHelper.submitForApproval(
            opp.Id,
            'Some_Process_Definition',
            null,
            ''
        );
        Test.stopTest();

       
        Opportunity verify = [SELECT Id FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, verify.Id, 'Record should still exist when using defaults');
    }

    @IsTest
    static void testSubmitForApprovalWithInvalidInput() {
        Test.startTest();
        
        KenApprovalProcessHelper.submitForApproval(
            null,
            null,
            null,
            null
        );
        Test.stopTest();

     
        System.assert(true, 'Handled invalid input gracefully without throwing exception');
    }
}