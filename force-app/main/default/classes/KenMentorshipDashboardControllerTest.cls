@IsTest
private class KenMentorshipDashboardControllerTest {

    @TestSetup
    static void setup() {
        // Alumni record type
        RecordType alumRT = [SELECT Id FROM RecordType WHERE SObjectType='Account' AND DeveloperName='Alumni_Person_Account' LIMIT 1];

        List<Account> people = new List<Account>{
            new Account(RecordTypeId=alumRT.Id, FirstName='Mentor',  LastName='Alpha', PersonEmail='malpha@test.edu'),
            new Account(RecordTypeId=alumRT.Id, FirstName='Mentor',  LastName='Beta',  PersonEmail='mbeta@test.edu'),
            new Account(RecordTypeId=alumRT.Id, FirstName='Mentee',  LastName='Gamma', PersonEmail='mgamma@test.edu'),
            new Account(RecordTypeId=alumRT.Id, FirstName='Mentee',  LastName='Delta', PersonEmail='mdelta@test.edu')
        };
        insert people;

        RecordType connRT = [SELECT Id FROM RecordType WHERE SObjectType='Ken_Mentorship__c' AND DeveloperName='Connection_Request' LIMIT 1];
        RecordType callRT = [SELECT Id FROM RecordType WHERE SObjectType='Ken_Mentorship__c' AND DeveloperName='Call_Request' LIMIT 1];

        List<Ken_Mentorship__c> records = new List<Ken_Mentorship__c>{
            // Connection Requests
            new Ken_Mentorship__c(RecordTypeId=connRT.Id, Mentor__c=people[0].Id, Mentee__c=people[2].Id, Meeting_Mode__c='Online'),
            new Ken_Mentorship__c(RecordTypeId=connRT.Id, Mentor__c=people[0].Id, Mentee__c=people[3].Id, Meeting_Mode__c='In-person'),
            new Ken_Mentorship__c(RecordTypeId=connRT.Id, Mentor__c=people[1].Id, Mentee__c=people[2].Id, Meeting_Mode__c='Online'),
            new Ken_Mentorship__c(RecordTypeId=connRT.Id, Mentor__c=people[1].Id, Mentee__c=people[3].Id, Meeting_Mode__c='In-person'),
            new Ken_Mentorship__c(RecordTypeId=connRT.Id, Mentor__c=people[0].Id, Mentee__c=people[3].Id, Meeting_Mode__c='Online'),
            // Call Requests
            new Ken_Mentorship__c(RecordTypeId=callRT.Id, Mentor__c=people[0].Id, Mentee__c=people[2].Id, Meet_Date__c=Date.today(), Meeting_Mode__c='Online'),
            new Ken_Mentorship__c(RecordTypeId=callRT.Id, Mentor__c=people[1].Id, Mentee__c=people[3].Id, Meet_Date__c=Date.today(), Meeting_Mode__c='In-person'),
            new Ken_Mentorship__c(RecordTypeId=callRT.Id, Mentor__c=people[0].Id, Mentee__c=people[2].Id, Meet_Date__c=Date.today(), Meeting_Mode__c='Online')
        };

        // Set restricted picklist values via put()
        records[0].put('Mentorship_Status__c', 'Accepted');
        records[1].put('Mentorship_Status__c', 'Requested');
        records[2].put('Mentorship_Status__c', 'Rejected');
        records[3].put('Mentorship_Status__c', 'Accepted');
        records[4].put('Mentorship_Status__c', 'Completed');
        records[5].put('Call_Request_Status__c', 'Completed');
        records[6].put('Call_Request_Status__c', 'Scheduled');
        records[7].put('Call_Request_Status__c', 'Requested');

        insert records;
    }

    @IsTest
    static void testGetSummaryStats_All() {
        Test.startTest();
        KenMentorshipDashboardController.SummaryStats s = KenMentorshipDashboardController.getSummaryStats('All', 'All', 'All');
        Test.stopTest();
        System.assert(s.total >= 8, 'Expected at least 8 records');
        System.assert(s.activeConnections >= 2);
        System.assert(s.pendingRequests >= 1);
        System.assert(s.totalCalls >= 3);
        System.assert(s.callsCompleted >= 1);
        System.assert(s.completionRate >= 0);
    }

    @IsTest
    static void testGetSummaryStats_ConnectionRequestFilter() {
        Test.startTest();
        KenMentorshipDashboardController.SummaryStats s = KenMentorshipDashboardController.getSummaryStats('All', 'Connection_Request', 'All');
        Test.stopTest();
        System.assertEquals(5, s.total);
    }

    @IsTest
    static void testGetSummaryStats_CallRequestFilter() {
        Test.startTest();
        KenMentorshipDashboardController.SummaryStats s = KenMentorshipDashboardController.getSummaryStats('All', 'Call_Request', 'All');
        Test.stopTest();
        System.assertEquals(3, s.total);
    }

    @IsTest
    static void testGetSummaryStats_WithYear() {
        Test.startTest();
        String yr = String.valueOf(Date.today().year());
        KenMentorshipDashboardController.SummaryStats s = KenMentorshipDashboardController.getSummaryStats('All', 'All', yr);
        Test.stopTest();
        System.assert(s.total >= 8);
    }

    @IsTest
    static void testGetMentorshipByStatus() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getMentorshipByStatus('All', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetMentorshipByStatus_Filtered() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getMentorshipByStatus('Accepted', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
        for (KenMentorshipDashboardController.ChartPoint p : pts) {
            System.assertEquals('Accepted', p.label);
        }
    }

    @IsTest
    static void testGetCallByStatus() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getCallByStatus('All', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetCallByStatus_Completed() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getCallByStatus('Completed', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetMonthlyTrend_All() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getMonthlyTrend('All', 'All', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetMonthlyTrend_ConnRT() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getMonthlyTrend('All', 'Connection_Request', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetMeetingMode() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getMeetingMode('All', 'All', 'All');
        Test.stopTest();
        System.assert(pts.size() >= 2); // Online + In-person
    }

    @IsTest
    static void testGetTopMentors() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getTopMentors('All', 'All', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
        // Should be sorted descending
        if (pts.size() > 1) System.assert(pts[0].value >= pts[1].value);
    }

    @IsTest
    static void testGetTopMentors_Filtered() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getTopMentors('Accepted', 'Connection_Request', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetTopMentees() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getTopMentees('All', 'All', 'All');
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetYearlyGrowth() {
        Test.startTest();
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getYearlyGrowth();
        Test.stopTest();
        System.assert(pts.size() > 0);
    }

    @IsTest
    static void testGetAvailableYears() {
        Test.startTest();
        List<String> years = KenMentorshipDashboardController.getAvailableYears();
        Test.stopTest();
        System.assert(years.size() > 0);
        System.assertEquals('All', years[0]);
    }

    @IsTest
    static void testGetMentorshipList_All() {
        Test.startTest();
        List<KenMentorshipDashboardController.MentorshipRecord> recs =
            KenMentorshipDashboardController.getMentorshipList('All', 'all', '', 'All', 'All', 'All');
        Test.stopTest();
        System.assert(recs.size() >= 8);
    }

    @IsTest
    static void testGetMentorshipList_ByConnStatus() {
        Test.startTest();
        List<KenMentorshipDashboardController.MentorshipRecord> recs =
            KenMentorshipDashboardController.getMentorshipList('Accepted', 'conn_status', 'Accepted', 'All', 'Connection_Request', 'All');
        Test.stopTest();
        System.assert(recs.size() >= 2);
    }

    @IsTest
    static void testGetMentorshipList_ByCallStatus() {
        Test.startTest();
        List<KenMentorshipDashboardController.MentorshipRecord> recs =
            KenMentorshipDashboardController.getMentorshipList('Completed', 'call_status', 'Completed', 'All', 'Call_Request', 'All');
        Test.stopTest();
        System.assert(recs.size() >= 1);
    }

    @IsTest
    static void testGetMentorshipList_ByMentor() {
        Account mentor = [SELECT Id FROM Account WHERE PersonEmail='malpha@test.edu' LIMIT 1];
        Test.startTest();
        List<KenMentorshipDashboardController.MentorshipRecord> recs =
            KenMentorshipDashboardController.getMentorshipList('Mentor Alpha', 'mentor', mentor.Id, 'All', 'All', 'All');
        Test.stopTest();
        System.assert(recs.size() >= 3);
    }

    @IsTest
    static void testGetMentorshipList_ByMentee() {
        Account mentee = [SELECT Id FROM Account WHERE PersonEmail='mgamma@test.edu' LIMIT 1];
        Test.startTest();
        List<KenMentorshipDashboardController.MentorshipRecord> recs =
            KenMentorshipDashboardController.getMentorshipList('Mentee Gamma', 'mentee', mentee.Id, 'All', 'All', 'All');
        Test.stopTest();
        System.assert(recs.size() >= 2);
    }

    @IsTest
    static void testGetMentorshipList_ByMode() {
        Test.startTest();
        List<KenMentorshipDashboardController.MentorshipRecord> recs =
            KenMentorshipDashboardController.getMentorshipList('Online', 'mode', 'Online', 'All', 'All', 'All');
        Test.stopTest();
        System.assert(recs.size() >= 4);
    }

    @IsTest
    static void testGetMentorshipList_ByStatusAllRT() {
        Test.startTest();
        List<KenMentorshipDashboardController.MentorshipRecord> recs =
            KenMentorshipDashboardController.getMentorshipList('Accepted', 'status', 'Accepted', 'All', 'All', 'All');
        Test.stopTest();
        System.assert(recs.size() >= 2);
    }

    @IsTest
    static void testInvalidYear() {
        Test.startTest();
        KenMentorshipDashboardController.SummaryStats s = KenMentorshipDashboardController.getSummaryStats('All', 'All', 'notAYear');
        List<KenMentorshipDashboardController.ChartPoint> pts = KenMentorshipDashboardController.getMonthlyTrend('All', 'All', 'notAYear');
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assertNotEquals(null, pts);
    }
}