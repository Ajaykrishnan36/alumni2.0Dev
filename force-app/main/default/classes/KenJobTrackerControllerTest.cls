@isTest
private class KenJobTrackerControllerTest {

    private static Ken_Job_Application__c makeApp() {
        Contact c = new Contact(LastName = 'Tracker Tester');
        insert c;
        Ken_Job_Master__c job = new Ken_Job_Master__c(
            Company__c = 'Acme', Job_Title__c = 'Engineer', Status__c = 'Live');
        insert job;
        Ken_Job_Application__c app = new Ken_Job_Application__c(
            Job__c = job.Id, Applicant__c = c.Id, Applicant_Type__c = 'Alumni',
            Status__c = 'Interview', Application_State__c = 'inProgress');
        insert app;
        return app;
    }

    @isTest
    static void returnsStepsSortedWithServerClock() {
        Ken_Job_Application__c app = makeApp();
        DateTime start = System.now().addMinutes(10);
        insert new List<Ken_Job_Application_Step__c>{
            new Ken_Job_Application_Step__c(Application__c = app.Id, Step_Label__c = 'Initial Screening',
                State__c = 'completed', Step_Order__c = 1),
            new Ken_Job_Application_Step__c(Application__c = app.Id, Step_Label__c = 'Technical Interview',
                State__c = 'active', Step_Order__c = 2, Location_Mode__c = 'Online',
                Meeting_Link__c = 'https://meet.example.com/abc',
                Scheduled_Start__c = start, Scheduled_End__c = start.addMinutes(45)),
            new Ken_Job_Application_Step__c(Application__c = app.Id, Step_Label__c = 'HR Interview',
                State__c = 'upcoming', Step_Order__c = 3)
        };

        Test.startTest();
        KenJobTrackerController.TrackerResult res =
            KenJobTrackerController.getApplicationSteps(app.Id);
        Test.stopTest();

        System.assertEquals(3, res.steps.size(), 'all steps returned');
        System.assertNotEquals(null, res.serverNowEpoch, 'server clock present');
        System.assert(res.serverNowEpoch > 0, 'epoch positive');
        // sorted ascending by order
        System.assertEquals('Initial Screening', res.steps[0].label);
        System.assertEquals('Technical Interview', res.steps[1].label);
        System.assertEquals('HR Interview', res.steps[2].label);
        // the online interview step carries the gate data
        KenJobTrackerController.StepRow iv = res.steps[1];
        System.assertEquals('Online', iv.locationMode);
        System.assertEquals('https://meet.example.com/abc', iv.meetingLink);
        System.assertNotEquals(null, iv.scheduledStartEpoch);
        System.assertNotEquals(null, iv.scheduledEndEpoch);
        System.assert(iv.scheduledEndEpoch > iv.scheduledStartEpoch, 'end after start');
    }

    @isTest
    static void nullIdThrows() {
        Boolean thrown = false;
        try {
            KenJobTrackerController.getApplicationSteps(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'null application id should throw');
    }
}