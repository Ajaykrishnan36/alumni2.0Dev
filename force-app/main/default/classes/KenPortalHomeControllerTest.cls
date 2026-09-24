/**
 * @description Tests for the portal Home dashboard controller.
 */
@isTest
private class KenPortalHomeControllerTest {

    @TestSetup
    static void makeData() {
        insert new Ken_Alm_Bypass_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Event_Trigger__c = true,
            Skip_Group_Trigger__c = true,
            Skip_Group_Member_Trigger__c = true,
            Skip_Feed_Item_Trigger__c = true
        );

        Id paRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        // Birthdays are relative to today so the 30-day window is exercised the
        // same way in every month; leap years make 2000/1996 safe birth years for
        // any month/day pair the offsets land on.
        Date soon = Date.today().addDays(5);
        Date faraway = Date.today().addDays(200);
        Account a1 = new Account(
            RecordTypeId = paRtId, LastName = 'Home Alumni One',
            PersonEmail = 'home1@test.com',
            PersonBirthdate = Date.newInstance(2000, soon.month(), soon.day())
        );
        Account a2 = new Account(
            RecordTypeId = paRtId, LastName = 'Home Alumni Two',
            PersonEmail = 'home2@test.com',
            PersonBirthdate = Date.newInstance(1996, faraway.month(), faraway.day())
        );
        insert new List<Account>{ a1, a2 };

        ConstituentRole cr = new ConstituentRole(
            PersonId = a1.Id, RoleType = 'Alumni',
            Graduation_Year__c = '2016'
        );
        cr.put('Status', 'Active');
        insert cr;

        // Events are day-granular: a date with no time of their own.
        Date eventDay = Date.today().addDays(7);
        insert new Ken_Event_Master__c(
            Name = 'Home Test Event',
            Event_Status__c = 'Approved',
            Start_Date__c = eventDay
        );

        Ken_Group__c grp = new Ken_Group__c(Name = 'Home Test Group');
        insert grp;
        insert new Ken_Group_Member__c(
            Group__c = grp.Id, Member__c = a1.Id, Status__c = 'Approved'
        );
        insert new FeedItem(ParentId = grp.Id, Body = 'Hello from the group feed');
    }

    @isTest
    static void testGetHomeDataReturnsAllSections() {
        Account viewer = [SELECT Id FROM Account WHERE PersonEmail = 'home1@test.com' LIMIT 1];
        KenPortalHomeController.testAccountId = viewer.Id;

        Test.startTest();
        KenPortalHomeController.HomeData data = KenPortalHomeController.getHomeData();
        Test.stopTest();

        System.assertNotEquals(null, data, 'Home data should be returned');

        System.assertEquals(false, data.events.isEmpty(), 'Upcoming approved event should be listed');
        System.assertEquals('Home Test Event', data.events[0].title, 'Event title should map');
        // An event is day-granular: it owns a date and never a time, so the card
        // shows "dd MMM, yyyy" with no clock. Building that server-side is safe
        // because a Date carries no timezone to be converted wrongly.
        System.assertNotEquals(null, data.events[0].dateLabel, 'Event date label should be built');
        System.assert(!data.events[0].dateLabel.contains('|'), 'No time should appear on an event label');

        System.assertEquals(false, data.birthdays.isEmpty(), 'Birthdays should be listed');
        System.assertEquals(1, data.birthdays.size(),
            'Only the birthday inside the 30-day window is listed; the one 200 days out is filtered');
        Boolean sawBatch = false;
        for (KenPortalHomeController.HomeBirthdayRow b : data.birthdays) {
            System.assertNotEquals(null, b.monthLabel, 'Month label should be built');
            if (b.batch == 'Batch 2016') sawBatch = true;
        }
        System.assertEquals(true, sawBatch, 'Batch label should come from the ConstituentRole');

        System.assertEquals(false, data.feed.isEmpty(), 'Group feed post should be listed');
        System.assertEquals('Home Test Group', data.feed[0].groupName, 'Feed rows should carry the group name');
        System.assert(data.feed[0].body.contains('Hello from the group feed'), 'Feed body should map');
    }

    @isTest
    static void testFeedEmptyWhenNoAccount() {
        KenPortalHomeController.testAccountId = null;
        Test.startTest();
        KenPortalHomeController.HomeData data = KenPortalHomeController.getHomeData();
        Test.stopTest();
        System.assertNotEquals(null, data.feed, 'Feed list should never be null');
    }

    /**
     * @description The feed mingles group and social posts newest-first, and a social
     *              post is ordered by Posted_At__c - when it went live on the platform -
     *              never by its Salesforce created date. Both rows are created in this
     *              transaction, so ordering by the SF date would put the group post
     *              first and this test would fail.
     */
    @isTest
    static void testSocialPostsMingleAndSortByPostedAt() {
        Account viewer = [SELECT Id FROM Account WHERE PersonEmail = 'home1@test.com' LIMIT 1];
        KenPortalHomeController.testAccountId = viewer.Id;

        insert new Ken_Social_Media_Post__c(
            Platform__c = 'LinkedIn',
            Title__c = 'Alumni mentoring drive',
            Body__c = 'Sign-ups are open for this term.',
            Post_URL__c = 'https://www.linkedin.com/feed/update/urn:li:activity:1',
            Posted_At__c = System.now().addDays(1),
            Is_Active__c = true
        );
        insert new Ken_Social_Media_Post__c(
            Platform__c = 'Instagram',
            Title__c = 'Old campus throwback',
            Body__c = 'Posted long ago.',
            Posted_At__c = System.now().addYears(-3),
            Is_Active__c = true
        );

        Test.startTest();
        KenPortalHomeController.HomeData data = KenPortalHomeController.getHomeData();
        Test.stopTest();

        System.assertEquals(false, data.feed.isEmpty(), 'Feed should not be empty');
        System.assertEquals('LinkedIn', data.feed[0].platform,
            'The future-dated social post must sort to the top on Posted_At__c');
        System.assertNotEquals(null, data.feed[0].postUrl, 'Social rows carry their post URL');
        System.assert(data.feed[0].body.contains('<p>'),
            'A plain-text social body is wrapped as HTML for the feed renderer');

        Boolean sawGroupRow = false;
        Datetime previous = null;
        for (KenPortalHomeController.HomeFeedRow r : data.feed) {
            System.assertNotEquals(null, r.postedAt, 'Every feed row carries a postedAt');
            if (previous != null) {
                System.assert(previous >= r.postedAt, 'Feed must be ordered newest first');
            }
            previous = r.postedAt;
            if (r.platform == null) sawGroupRow = true;
        }
        System.assertEquals(true, sawGroupRow, 'Group posts still appear alongside social posts');
    }
}