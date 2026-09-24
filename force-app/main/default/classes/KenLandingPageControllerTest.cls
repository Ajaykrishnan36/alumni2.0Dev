@isTest
private class KenLandingPageControllerTest {

    private static Ken_Event_Master__c buildEvent(
        String name,
        Boolean showOnLanding,
        String status,
        Boolean isActive,
        Date startDate,
        Date endDate
    ) {
        return new Ken_Event_Master__c(
            Name = name,
            Show_On_Landing_Page__c = showOnLanding,
            Event_Status__c = status,
            Is_Active__c = isActive,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Location__c = 'Vidyavihar - Mumbai',
            Event_Type__c = 'Seminar'
        );
    }

    @isTest
    static void flaggedApprovedUpcomingEventIsReturned() {
        insert buildEvent('Landing Event', true, 'Approved', true, Date.today().addDays(5), Date.today().addDays(6));

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A flagged, approved, upcoming event should appear on the landing page.');
        System.assertEquals('Landing Event', rows[0].title, 'Title should come from the event Name.');
        System.assertEquals('SEMINAR', rows[0].badge, 'Badge should be the first event type, uppercased.');
        System.assertEquals('Vidyavihar - Mumbai', rows[0].location, 'Location should be carried through.');
        System.assertNotEquals(null, rows[0].dateLabel, 'A start date should produce a formatted label.');
    }

    @isTest
    static void unflaggedEventIsExcluded() {
        insert buildEvent('Hidden Event', false, 'Approved', true, Date.today().addDays(5), Date.today().addDays(6));

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Without the Show On Landing Page flag an event must not be published.');
    }

    @isTest
    static void unapprovedAndInactiveEventsAreExcluded() {
        List<Ken_Event_Master__c> events = new List<Ken_Event_Master__c>{
            buildEvent('Draft Event', true, 'Draft', true, Date.today().addDays(5), Date.today().addDays(6)),
            buildEvent('Inactive Event', true, 'Approved', false, Date.today().addDays(5), Date.today().addDays(6))
        };
        insert events;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Flagging alone must not publish a draft or inactive event.');
    }

    @isTest
    static void finishedEventIsExcluded() {
        insert buildEvent('Past Event', true, 'Approved', true, Date.today().addDays(-10), Date.today().addDays(-9));

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'An event that already finished should drop off the landing page.');
    }

    @isTest
    static void eventWithoutEndDateStaysUntilItsStartDatePasses() {
        List<Ken_Event_Master__c> events = new List<Ken_Event_Master__c>{
            buildEvent('Open Ended Upcoming', true, 'Approved', true, Date.today().addDays(3), null),
            buildEvent('Open Ended Past', true, 'Approved', true, Date.today().addDays(-3), null)
        };
        insert events;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'With no end date the start date decides whether the event is still current.');
        System.assertEquals('Open Ended Upcoming', rows[0].title, 'Only the future open-ended event should remain.');
    }

    @isTest
    static void resultsAreCappedAtTheCardCountAndOrderedByStartDate() {
        List<Ken_Event_Master__c> events = new List<Ken_Event_Master__c>();
        // Inserted latest-first so the ORDER BY is doing the work, not insert order.
        for (Integer i = 6; i >= 1; i--) {
            events.add(buildEvent(
                'Event ' + i, true, 'Approved', true,
                Date.today().addDays(i), Date.today().addDays(i)
            ));
        }
        insert events;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(
            KenLandingPageController.LANDING_EVENT_LIMIT,
            rows.size(),
            'The landing page has room for one hero plus three side cards.'
        );
        System.assertEquals('Event 1', rows[0].title, 'The soonest event should lead.');
        System.assertEquals('Event 4', rows[3].title, 'Events beyond the fourth soonest should be dropped.');
    }

    @isTest
    static void eventWithoutTypeFallsBackToGenericBadge() {
        Ken_Event_Master__c ev = buildEvent('No Type Event', true, 'Approved', true, Date.today().addDays(2), Date.today().addDays(2));
        ev.Event_Type__c = null;
        insert ev;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A missing event type should not hide the event.');
        System.assertEquals('EVENT', rows[0].badge, 'A blank event type should fall back to a generic badge.');
    }

    @isTest
    static void eventCarriesADayGranularLabelAndNoTime() {
        // An event owns a date, never a time — nothing writes a time onto
        // Ken_Event_Master__c. So the card shows "dd MMM, yyyy" with no clock,
        // and because a Date has no timezone the server-built label is correct
        // even under the site guest user, whose timezone nobody has ever set.
        Date day = Date.today().addDays(4);
        Ken_Event_Master__c ev = buildEvent('Day Event', true, 'Approved', true, day, day);
        insert ev;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The event should be returned.');
        String expected = Datetime.newInstance(day.year(), day.month(), day.day()).format('dd MMM, yyyy');
        System.assertEquals(expected, rows[0].dateLabel, 'Label should be the start day, date only.');
        System.assert(!rows[0].dateLabel.contains('|'), 'No time range should appear on an event label.');
    }

    @isTest
    static void multiDayEventStillLabelsItsStartDay() {
        Date start = Date.today().addDays(4);
        Ken_Event_Master__c ev = buildEvent('Week Event', true, 'Approved', true, start, start.addDays(3));
        insert ev;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The event should be returned.');
        String expected = Datetime.newInstance(start.year(), start.month(), start.day()).format('dd MMM, yyyy');
        System.assertEquals(expected, rows[0].dateLabel, 'A multi-day event is labelled by its start day.');
    }

    @isTest
    static void eventWithoutStartDateStillRendersWithoutADateLabel() {
        Ken_Event_Master__c ev = buildEvent('No Date Event', true, 'Approved', true, null, Date.today().addDays(4));
        insert ev;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A missing start date should not hide an otherwise current event.');
        System.assertEquals(null, rows[0].dateLabel, 'With no start date there is nothing to label.');
    }

    /**
     * Sessions are timed, so the fixture stores instants — that is what every
     * session in the org actually holds. A null endDate means a same-day session
     * saved with no end, which is 48 of 189 rows in AlumniDev and must still
     * count as current for the whole of its start day.
     */
    private static Ken_Schedule_Sessions__c buildSession(Id eventId, Date startDate, Date endDate) {
        return new Ken_Schedule_Sessions__c(
            Event_Reference__c = eventId,
            Start_DateTime__c = startDate == null
                ? null
                : DateTime.newInstance(startDate, Time.newInstance(10, 0, 0, 0)),
            End_DateTime__c = endDate == null
                ? null
                : DateTime.newInstance(endDate, Time.newInstance(11, 0, 0, 0))
        );
    }

    @isTest
    static void sessionStillToComeKeepsEventOnPageEvenWhenEventEndDatePassed() {
        Ken_Event_Master__c ev = buildEvent('Session Runs Later', true, 'Approved', true, Date.today().addDays(-10), Date.today().addDays(-5));
        insert ev;
        // Event's own End Date is stale, but a session is still ahead.
        insert buildSession(ev.Id, Date.today().addDays(3), Date.today().addDays(3));

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A future session should keep the event on the landing page.');
        System.assertEquals('Session Runs Later', rows[0].title, 'The session-backed event should be the one returned.');
    }

    @isTest
    static void allSessionsFinishedDropsEventEvenWhenEventEndDateIsStillAhead() {
        Ken_Event_Master__c ev = buildEvent('Sessions Already Over', true, 'Approved', true, Date.today().addDays(-10), Date.today().addDays(30));
        insert ev;
        // Sessions decide: every one has finished, so the stale future End Date loses.
        insert new List<Ken_Schedule_Sessions__c>{
            buildSession(ev.Id, Date.today().addDays(-9), Date.today().addDays(-9)),
            buildSession(ev.Id, Date.today().addDays(-8), Date.today().addDays(-8))
        };

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Once every session is over the event should leave the public page.');
    }

    @isTest
    static void sessionWithoutEndDateCountsAsEndingOnItsStartDate() {
        Ken_Event_Master__c ev = buildEvent('Same Day Session', true, 'Approved', true, Date.today().addDays(-10), Date.today().addDays(-10));
        insert ev;
        // Same-day sessions are stored with no end date; today still counts.
        insert buildSession(ev.Id, Date.today(), null);

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A session dated today should still count as current all day.');
    }

    @isTest
    static void eventWithNoSessionsStillFallsBackToItsOwnEndDate() {
        List<Ken_Event_Master__c> events = new List<Ken_Event_Master__c>{
            buildEvent('No Sessions Upcoming', true, 'Approved', true, Date.today().addDays(2), Date.today().addDays(2)),
            buildEvent('No Sessions Past', true, 'Approved', true, Date.today().addDays(-4), Date.today().addDays(-3))
        };
        insert events;

        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'With no sessions the event End Date decides, as before.');
        System.assertEquals('No Sessions Upcoming', rows[0].title, 'Only the future event should remain.');
    }

    @isTest
    static void noFlaggedEventsReturnsEmptyListSoThePageCanFallBack() {
        Test.startTest();
        List<KenLandingPageController.LandingEvent> rows = KenLandingPageController.getLandingPageEvents();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'With nothing flagged the controller returns an empty list, not null.');
    }

    /**
     * A person account will not insert without an explicit person-account record
     * type, which is org-specific rather than something we can hardcode.
     */
    private static Id personAccountRtId {
        get {
            if (personAccountRtId == null) {
                List<RecordType> rts = [
                    SELECT Id
                    FROM RecordType
                    WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true
                    LIMIT 1
                ];
                personAccountRtId = rts.isEmpty() ? null : rts[0].Id;
            }
            return personAccountRtId;
        }
        set;
    }

    private static Account insertPerson(String lastName, String photoUrl) {
        Account person = new Account(
            LastName = lastName,
            Profile_Photo_URL__c = photoUrl
        );
        if (personAccountRtId != null) {
            person.RecordTypeId = personAccountRtId;
        }
        insert person;
        return person;
    }

    private static ConstituentRole insertRole(
        Id personId,
        String faculty,
        String batch,
        String quote,
        Boolean flagged
    ) {
        ConstituentRole role = new ConstituentRole(
            PersonId = personId,
            RoleType = 'Alumni',
            Status = 'Active',
            Graduation_Year__c = batch,
            About__c = quote,
            Show_On_Landing_Page__c = flagged
        );
        insert role;

        // Institute_Name__c is stamped from the Program Plan by
        // KenConstituentRoleTriggerHandler on insert, which blanks it when there
        // is no plan. Setting it afterwards sticks, because the handler only
        // re-stamps when the plan changes or the value is blank.
        if (String.isNotBlank(faculty)) {
            update new ConstituentRole(Id = role.Id, Institute_Name__c = faculty);
            role.Institute_Name__c = faculty;
        }
        return role;
    }

    @isTest
    static void flaggedStoryIsReturnedWithItsBatchLabel() {
        Account person = insertPerson('Khetawat', 'https://cdn.example.com/swadesh.jpg');
        insertRole(person.Id, 'Faculty of Engineering', '1987', 'The alumni network opened doors.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A flagged story with a quote should publish.');
        System.assertEquals('Faculty of Engineering, Batch: 1987', rows[0].batchLabel, 'The caption reads faculty then batch.');
        System.assertEquals('https://cdn.example.com/swadesh.jpg', rows[0].imageUrl, 'An absolute photo URL is passed through.');
    }

    @isTest
    static void unflaggedStoryIsExcluded() {
        Account person = insertPerson('Hidden', null);
        insertRole(person.Id, 'Faculty of Management', '2004', 'Should not appear.', false);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Without the flag a story must stay off the public page.');
    }

    /**
     * The quote is the content of the card, so a flagged role without one would
     * render as a portrait over empty space.
     */
    @isTest
    static void flaggedStoryWithNoQuoteIsExcluded() {
        Account person = insertPerson('NoQuote', null);
        insertRole(person.Id, 'Faculty of Management', '2004', null, true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'A story with no quote has nothing to say and is skipped.');
    }

    /**
     * Unlike a newsletter, a missing photo must NOT drop the card - the caller
     * substitutes a static portrait, so the story still reaches the page.
     */
    @isTest
    static void storyWithNoPhotoIsStillPublished() {
        Account person = insertPerson('NoPhoto', null);
        insertRole(person.Id, 'Faculty of Science', '2011', 'Still worth telling.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A missing portrait must not hide the story.');
        System.assertEquals(null, rows[0].imageUrl, 'No usable photo is reported as null so the caller can substitute one.');
    }

    /**
     * A login-protected Salesforce path renders as a broken portrait for an
     * anonymous visitor, so it is treated as no photo at all.
     */
    @isTest
    static void relativePhotoPathIsTreatedAsNoPhoto() {
        Account person = insertPerson('RelativePath', '/services/images/photo/005xx');
        insertRole(person.Id, 'Faculty of Arts', '1999', 'A good story.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The story still publishes.');
        System.assertEquals(null, rows[0].imageUrl, 'A guest cannot load a login-protected path, so it is not used.');
    }

    /**
     * The reason the flag lives on the Constituent Role: one person, two
     * pass-outs, and only the qualification staff picked should appear.
     */
    @isTest
    static void onlyTheFlaggedPassOutOfTheSamePersonIsShown() {
        Account person = insertPerson('TwoDegrees', null);
        insertRole(person.Id, 'Faculty of Engineering', '2010', 'My B.Tech story.', false);
        insertRole(person.Id, 'Faculty of Management', '2014', 'My MBA story.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Only the flagged pass-out should publish.');
        System.assertEquals('My MBA story.', rows[0].quote, 'The chosen qualification decides the story.');
        System.assertEquals('Faculty of Management, Batch: 2014', rows[0].batchLabel, 'And the caption follows that role.');
    }

    @isTest
    static void storiesAreCappedAtTheCardCount() {
        Account person = insertPerson('Prolific', null);
        for (Integer i = 0; i < 5; i++) {
            insertRole(person.Id, 'Faculty ' + i, String.valueOf(2000 + i), 'Story ' + i, true);
        }

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(
            KenLandingPageController.LANDING_STORY_LIMIT,
            rows.size(),
            'The design has room for exactly three story cards.'
        );
    }

    @isTest
    static void noFlaggedStoriesReturnsEmptyListSoThePageCanFallBack() {
        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'With nothing flagged the page keeps its static cards.');
    }

    /**
     * Either half of the caption can be missing without producing a stray comma
     * or a literal "Batch: null".
     */
    @isTest
    static void batchLabelShrinksWhenHalfOfItIsMissing() {
        Account person = insertPerson('PartialCaption', null);
        insertRole(person.Id, 'Faculty of Law', null, 'No batch recorded.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals('Faculty of Law', rows[0].batchLabel, 'A missing batch should not leave a trailing comma.');
    }

    /**
     * Institute_Name__c carries the sharing token, which is the provider's record
     * id in every org that lets KenInstitutePopulationService stamp it. Printing
     * it raw put "001Im00000B9ASJIA3" on the public page where the faculty
     * belongs. Institution_Name__c and Program_Name__c are both formulas over
     * Program_Plan__r, so with no plan the caption correctly shrinks to the batch
     * - what matters is that the id itself never reaches a visitor.
     */
    @isTest
    static void idShapedInstituteTokenIsNeverPrinted() {
        Account person = insertPerson('TokenStamped', null);
        insertRole(person.Id, String.valueOf(person.Id), '2018', 'Stamped with a sharing token.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The story still publishes; only its caption changes.');
        System.assert(
            !rows[0].batchLabel.contains(String.valueOf(person.Id)),
            'A record id must never reach the public caption.'
        );
        System.assertEquals('Batch: 2018', rows[0].batchLabel, 'With no readable institute the caption keeps the batch.');
    }

    /**
     * A role spanning several institutes packs the tokens with the service
     * delimiter, so the first one has to be unpacked before it can be judged.
     */
    @isTest
    static void semicolonPackedTokensAreNeverPrinted() {
        Account person = insertPerson('MultiToken', null);
        String packed = person.Id + KenInstitutePopulationService.DELIMITER + person.Id;
        insertRole(person.Id, packed, '2019', 'Stamped across two institutes.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The story still publishes.');
        System.assertEquals('Batch: 2019', rows[0].batchLabel, 'A packed token list is not a faculty name.');
    }

    /**
     * An org that stamps a readable institute is still taken at its word, so this
     * change cannot regress the KJS orgs.
     */
    @isTest
    static void readableInstituteTokenSurvives() {
        Account person = insertPerson('ReadableToken', null);
        insertRole(person.Id, 'Faculty of Science', '2001', 'Named institute, not a token.', true);

        Test.startTest();
        List<KenLandingPageController.LandingStory> rows = KenLandingPageController.getLandingPageStories();
        Test.stopTest();

        System.assertEquals('Faculty of Science, Batch: 2001', rows[0].batchLabel, 'A typed institute name is printed unchanged.');
    }

    private static Ken_Album__c insertAlbum(String name) {
        Ken_Album__c album = new Ken_Album__c(Name = name);
        insert album;
        return album;
    }

    /**
     * Uploads are ordered by CreatedDate, which cannot be set on insert, so
     * every newsletter test back-dates its records to make the order explicit
     * rather than relying on insert sequence within one transaction.
     *
     * Flagged, image-named and publicly linked by default, because that is the
     * only combination the landing page publishes. The tests covering each
     * excluded case opt out of one of those three explicitly.
     */
    private static Ken_File__c insertPhoto(Id albumId, String name, Integer daysAgo) {
        return insertPhoto(albumId, name, daysAgo, true, true);
    }

    private static Ken_File__c insertPhoto(
        Id albumId,
        String name,
        Integer daysAgo,
        Boolean showOnLandingPage
    ) {
        return insertPhoto(albumId, name, daysAgo, showOnLandingPage, true);
    }

    private static Ken_File__c insertPhoto(
        Id albumId,
        String name,
        Integer daysAgo,
        Boolean showOnLandingPage,
        Boolean withPublicUrl
    ) {
        return insertPhoto(albumId, name, daysAgo, showOnLandingPage, withPublicUrl, true);
    }

    /**
     * isImage stands in for what the ContentVersion trigger stamps at upload. It
     * is set explicitly rather than inferred from the name on purpose - the whole
     * point of Is_Image__c is that the record name says nothing reliable about
     * what was attached.
     */
    private static Ken_File__c insertPhoto(
        Id albumId,
        String name,
        Integer daysAgo,
        Boolean showOnLandingPage,
        Boolean withPublicUrl,
        Boolean isImage
    ) {
        Ken_File__c photo = new Ken_File__c(
            Album__c = albumId,
            Name = name,
            Show_On_Landing_Page__c = showOnLandingPage,
            Is_Image__c = isImage,
            Share_URL__c = withPublicUrl
                ? 'https://example.file.force.com/sfc/dist/version/download/' + name
                : null
        );
        insert photo;
        Test.setCreatedDate(photo.Id, System.now().addDays(-daysAgo));
        return photo;
    }

    /**
     * Uploading into the Newsletter album is not the same as publishing. Until an
     * admin ticks the box the file stays staged and the page keeps its static
     * cards - this is the whole point of the flag.
     */
    @isTest
    static void unflaggedNewsletterIsExcluded() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Staged Newsletter.png', 1, false);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            0,
            rows.size(),
            'A newsletter that has not been flagged must stay off the public page.'
        );
    }

    /**
     * The realistic curation case: several files sitting in the album, only some
     * of them published. Also pins that the flag is applied BEFORE the limit of
     * three, so an unflagged newer file cannot displace a flagged older one.
     */
    @isTest
    static void onlyFlaggedNewslettersAreReturnedRegardlessOfUploadOrder() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Published Older.png', 30, true);
        insertPhoto(album.Id, 'Staged Newest.png', 1, false);
        insertPhoto(album.Id, 'Published Newer.png', 10, true);
        insertPhoto(album.Id, 'Staged Middle.png', 20, false);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Only the two flagged newsletters should be published.');
        System.assertEquals(
            'Published Newer',
            rows[0].title,
            'Flagged newsletters still run newest to oldest.'
        );
        System.assertEquals(
            'Published Older',
            rows[1].title,
            'The unflagged newer uploads must not displace a flagged older one.'
        );
    }

    @isTest
    static void newslettersAreReturnedNewestFirst() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Oldest.png', 30);
        insertPhoto(album.Id, 'Newest.png', 1);
        insertPhoto(album.Id, 'Middle.png', 15);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(3, rows.size(), 'All three uploaded newsletters should be returned.');
        System.assertEquals('Newest', rows[0].title, 'The most recent upload must lead the row.');
        System.assertEquals('Middle', rows[1].title, 'Newsletters run newest to oldest.');
        System.assertEquals('Oldest', rows[2].title, 'The earliest upload should come last.');
    }

    @isTest
    static void onlyTheThreeMostRecentNewslettersAreReturned() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Fourth.png', 40);
        insertPhoto(album.Id, 'First.png', 1);
        insertPhoto(album.Id, 'Second.png', 10);
        insertPhoto(album.Id, 'Third.png', 20);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(3, rows.size(), 'The design has room for exactly three newsletter cards.');
        System.assertEquals('Third', rows[2].title, 'The fourth-newest upload should drop off the page.');
    }

    @isTest
    static void pluralAlbumNameIsAlsoMatched() {
        Ken_Album__c album = insertAlbum('Newsletters');
        insertPhoto(album.Id, 'Plural Album Newsletter.png', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Either singular or plural album naming should publish newsletters.');
    }

    @isTest
    static void filesInOtherAlbumsAreNotPublished() {
        Ken_Album__c album = insertAlbum('Convocation 2023');
        insertPhoto(album.Id, 'Group Photo.png', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Only the Newsletter album reaches the public landing page.');
    }

    @isTest
    static void newsletterAlbumWithNoFilesReturnsEmptyListSoThePageCanFallBack() {
        insertAlbum('Newsletter');

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'An empty album keeps the static cards rather than blanking the section.');
    }

    @isTest
    static void noNewsletterAlbumReturnsEmptyListSoThePageCanFallBack() {
        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Before anyone creates the album the controller returns an empty list, not null.');
    }

    @isTest
    static void fileExtensionIsStrippedFromTheCardTitle() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Building the Future at Somaiya.png', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            'Building the Future at Somaiya',
            rows[0].title,
            'The card headline should read as a title, not as a file name.'
        );
    }

    @isTest
    static void aDotThatIsNotAnExtensionIsKeptInTheTitle() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Volume 2.1 Highlights.png', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            'Volume 2.1 Highlights',
            rows[0].title,
            'Only a short trailing suffix counts as a file extension.'
        );
    }

    @isTest
    static void anImageUploadIsUsableAsItsOwnCover() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'October Newsletter.png', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'An image upload should be published.');
        System.assertEquals(true, rows[0].isImage, 'Only images reach the caller, so this is always true.');
    }

    /**
     * A document has no publicly reachable thumbnail, so rather than dressing it
     * in a stock cover that misrepresents it, the card is dropped entirely.
     */
    @isTest
    static void aDocumentUploadIsExcludedEntirely() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'October Newsletter.pdf', 1, true, true, false);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            0,
            rows.size(),
            'A PDF has no renderable cover, so it must not occupy a newsletter card.'
        );
    }

    /**
     * No public link means nothing to point an <img> at - the guest user cannot
     * read the file itself - so the card has no cover and is dropped.
     */
    @isTest
    static void newsletterWithNoPublicLinkIsExcluded() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Unlinked Newsletter.png', 1, true, false);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            0,
            rows.size(),
            'Without a public link there is no cover to render, so the card is dropped.'
        );
    }

    /**
     * A short name that happens to match the start of the record's own Id used to
     * be mistaken for an auto-generated one and silently dropped. Names are always
     * present and always shown, so it is simply the headline now.
     */
    @isTest
    static void aShortNameIsStillShownAsTheHeadline() {
        Ken_Album__c album = insertAlbum('Newsletter');
        Ken_File__c photo = insertPhoto(album.Id, 'Placeholder.png', 1);
        photo.Name = String.valueOf(photo.Id).substring(0, 3);
        update photo;

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The image publishes.');
        System.assertEquals(
            String.valueOf(photo.Id).substring(0, 3),
            rows[0].title,
            'The file name is always the headline, however short it is.'
        );
    }

    /**
     * The regression this field exists for. A file created in Setup is named by
     * hand, so it routinely has no extension - "vgh,." holding a JPEG is a real
     * case from AlumniDev. Parsing the name dropped it; the stamped flag does not.
     */
    @isTest
    static void imageWithNoExtensionInItsNameIsStillPublished() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'vgh,.', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            1,
            rows.size(),
            'An image must publish even when its record name carries no extension.'
        );
    }

    /**
     * The mirror image: a name that looks like an image proves nothing. Only the
     * flag stamped from the real ContentVersion decides.
     */
    @isTest
    static void documentNamedLikeAnImageIsStillExcluded() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Actually A Document.png', 1, true, true, false);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            0,
            rows.size(),
            'The stamped flag decides, not a name that happens to end in .png.'
        );
    }

    /**
     * The user-visible point of the description field: a file name is rarely good
     * public copy, so an admin-written headline wins when there is one.
     */
    @isTest
    static void landingPageDescriptionIsPreferredOverTheFileName() {
        Ken_Album__c album = insertAlbum('Newsletter');
        Ken_File__c photo = insertPhoto(album.Id, 'SCAN_0042_final_v3.png', 1);
        photo.Description__c = 'Building the Future at Somaiya';
        update photo;

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'The newsletter should be published.');
        System.assertEquals(
            'Building the Future at Somaiya',
            rows[0].title,
            'An admin-written description should be the card headline, not the file name.'
        );
    }

    /**
     * Only images occupy card slots, so capping the SOQL at three would let an
     * unrenderable newer upload hide a perfectly good older newsletter. This
     * pins the scan-then-cap behaviour that prevents it.
     */
    @isTest
    static void anUnrenderableNewerNewsletterDoesNotConsumeACardSlot() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Newest But A Document.pdf', 1, true, true, false);
        insertPhoto(album.Id, 'First.png', 10);
        insertPhoto(album.Id, 'Second.png', 20);
        insertPhoto(album.Id, 'Third.png', 30);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(3, rows.size(), 'All three images should still fill the row.');
        System.assertEquals('First', rows[0].title, 'The newest image leads once the document is skipped.');
        System.assertEquals('Third', rows[2].title, 'The oldest image keeps its slot.');
    }

    /**
     * A part-filled row is intended: one real newsletter beats three stock ones.
     */
    @isTest
    static void aSingleNewsletterIsPublishedOnItsOwn() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Only One.png', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'A lone newsletter should publish rather than waiting for three.');
    }

    /**
     * The caption above the headline is the file's own name, not when it happened
     * to be uploaded - an October issue uploaded in December used to read
     * "December".
     */
    @isTest
    static void cardLabelIsTheFileName() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'October 2026 Newsletter.png', 40);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assertEquals(
            'October 2026 Newsletter',
            rows[0].dateLabel,
            'The caption should be the file name, with its extension stripped.'
        );
    }

    @isTest
    static void publicLinkIsPassedThroughAsTheCardImage() {
        Ken_Album__c album = insertAlbum('Newsletter');
        insertPhoto(album.Id, 'Linked Newsletter.png', 1);

        Test.startTest();
        List<KenLandingPageController.LandingNewsletter> rows = KenLandingPageController.getLandingPageNewsletters();
        Test.stopTest();

        System.assert(
            rows[0].imageUrl.startsWith('https://'),
            'The guest-readable public link is what the landing page renders as the cover.'
        );
    }

    // ═══════════════════ the community social band ═══════════════════

    /*
     * Absorbed from KenLandingPageControllerTest on 2026-08-14, when the class
     * it covered folded into KenLandingPageController.
     */

    private static final DateTime BASE_INSTANT =
        DateTime.newInstanceGmt(2026, 8, 9, 12, 0, 0);

    /**
     * @description Builds a post. Posted_At__c is offset by `minutesOld` so
     *              ordering is explicit rather than dependent on insert order.
     */
    private static Ken_Social_Media_Post__c buildPost(
        String externalId,
        String platform,
        Integer minutesOld,
        Boolean isActive,
        String mediaUrl
    ) {
        return new Ken_Social_Media_Post__c(
            External_Post_Id__c = externalId,
            Platform__c         = platform,
            Body__c             = 'Caption for ' + externalId,
            Media_Share_URL__c = mediaUrl,
            Post_URL__c         = POST_LINK,
            Posted_At__c        = BASE_INSTANT.addMinutes(-minutesOld),
            Is_Active__c        = isActive
        );
    }

    private static final String SAMPLE_URL =
        'https://example.file.force.com/sfc/dist/version/download/?oid=00D&ids=068';

    /** The platform's own post page, as the sync stores it. */
    private static final String POST_LINK = 'https://www.instagram.com/p/Db26up0EzBu/';

    @IsTest
    static void returnsNewestThreeAcrossPlatforms() {
        insert new List<Ken_Social_Media_Post__c>{
            buildPost('Instagram:1', 'Instagram', 10, true, SAMPLE_URL),
            buildPost('Facebook:2',  'Facebook',  20, true, SAMPLE_URL),
            buildPost('LinkedIn:3',  'LinkedIn',  30, true, SAMPLE_URL),
            buildPost('Instagram:4', 'Instagram', 40, true, SAMPLE_URL)
        };

        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.areEqual(3, cards.size(), 'Only three cards should ship to the band');
        Assert.areEqual('Instagram', cards[0].platform, 'Newest post should lead');
        Assert.areEqual('Facebook', cards[1].platform, 'Second newest should follow');
        Assert.areEqual('LinkedIn', cards[2].platform, 'Third newest should be last');
    }

    @IsTest
    static void allowsThreeCardsFromOnePlatform() {
        insert new List<Ken_Social_Media_Post__c>{
            buildPost('Instagram:1', 'Instagram', 10, true, SAMPLE_URL),
            buildPost('Instagram:2', 'Instagram', 20, true, SAMPLE_URL),
            buildPost('Instagram:3', 'Instagram', 30, true, SAMPLE_URL),
            buildPost('Facebook:4',  'Facebook',  40, true, SAMPLE_URL)
        };

        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.areEqual(3, cards.size(), 'Three cards should ship');
        for (KenLandingPageController.SocialPost card : cards) {
            Assert.areEqual(
                'Instagram', card.platform,
                'Recency alone decides, so one platform may take every slot'
            );
        }
    }

    @IsTest
    static void excludesInactiveButKeepsImagelessPosts() {
        insert new List<Ken_Social_Media_Post__c>{
            buildPost('Instagram:1', 'Instagram', 10, false, SAMPLE_URL),
            buildPost('Facebook:2',  'Facebook',  20, true,  null),
            buildPost('LinkedIn:3',  'LinkedIn',  30, true,  SAMPLE_URL)
        };

        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.areEqual(
            2, cards.size(),
            'Unticked posts must not reach the page, but an imageless one keeps its slot'
        );
        // Facebook is 20 minutes old and LinkedIn 30, so Facebook leads.
        Assert.areEqual(
            'Facebook', cards[0].platform,
            'The imageless post is still published, in its rightful recency slot'
        );
        Assert.isNull(
            cards[0].imageUrl,
            'Apex passes the empty image through untouched - substituting is the LWC\'s job'
        );
        Assert.areEqual('LinkedIn', cards[1].platform, 'Older active post follows');
    }

    @IsTest
    static void returnsEmptyWhenNothingPublished() {
        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.isTrue(
            cards.isEmpty(),
            'No records means an empty list, which is what makes the LWC fall back to static cards'
        );
    }

    @IsTest
    static void serialisesPostedAtAsGmtInstant() {
        insert buildPost('Instagram:1', 'Instagram', 0, true, SAMPLE_URL);

        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.areEqual(1, cards.size(), 'One card expected');
        Assert.areEqual(
            '2026-08-09T12:00:00.000Z', cards[0].postedInstant,
            'Instant must serialise in GMT so the guest user timezone never leaks in'
        );
    }

    @IsTest
    static void carriesCaptionAndImageThrough() {
        insert buildPost('Instagram:1', 'Instagram', 0, true, SAMPLE_URL);

        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.areEqual('Caption for Instagram:1', cards[0].body, 'Caption should reach the card');
        Assert.areEqual(SAMPLE_URL, cards[0].imageUrl, 'Salesforce-hosted image URL should reach the card');
        Assert.areEqual(POST_LINK, cards[0].postUrl, 'Deep link should reach the card');
        Assert.isNotNull(cards[0].id, 'Card needs an id for the template key');
    }

    /**
     * @description Posts stored before Post_URL__c existed still have to render.
     *              The sync never revisits a stored post, so those rows keep a
     *              blank link forever and the LWC turns that into an inert
     *              anchor rather than a card it cannot show.
     */
    @IsTest
    static void passesBlankDeepLinkThrough() {
        Ken_Social_Media_Post__c legacy = buildPost('Instagram:1', 'Instagram', 0, true, SAMPLE_URL);
        legacy.Post_URL__c = null;
        insert legacy;

        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.areEqual(1, cards.size(), 'A post with no deep link still ships');
        Assert.isNull(cards[0].postUrl, 'Apex passes the empty link through untouched');
    }

    @IsTest
    static void everyPlatformPicklistValueHasAHandleLookup() {
        // Would have caught X shipping with no handle on 2026-08-13. That failure
        // is invisible by inspection: the card still draws with its image and
        // caption, and only the handle is quietly absent - so nothing else in the
        // suite would ever have surfaced it. Driving the assertion off the
        // picklist means adding a platform without wiring its handle fails here.
        Set<String> handled = KenLandingPageController.handledPlatforms();

        for (Schema.PicklistEntry entry :
                Ken_Social_Media_Post__c.Platform__c.getDescribe().getPicklistValues()) {
            Assert.isTrue(handled.contains(entry.getValue()),
                'Platform "' + entry.getValue() + '" is a Platform__c picklist value but has '
                + 'no handle lookup in KenLandingPageController.loadHandles()');
        }
    }

    @IsTest
    static void stampsTheConfiguredHandleOnAnXCard() {
        // Stubbed rather than upserted: the handle now lives on a Custom Metadata
        // record, which Apex cannot write at all.
        KenSocialSync.overrides.put('X', new Ken_Alm_Integration_Settings__mdt(
            Service__c       = 'X',
            Account_Handle__c = '@kenalumni'
        ));

        insert new Ken_Social_Media_Post__c(
            External_Post_Id__c = 'X:HANDLE-TEST',
            Platform__c         = 'X',
            Body__c             = 'Convocation day',
            Media_Share_URL__c = 'https://example.com/img.jpg',
            Posted_At__c        = DateTime.newInstanceGmt(2026, 8, 13, 10, 0, 0),
            Is_Active__c        = true
        );

        Test.startTest();
        List<KenLandingPageController.SocialPost> cards =
            KenLandingPageController.getLandingSocialPosts();
        Test.stopTest();

        Assert.areEqual(1, cards.size(), 'The X post should reach the band');
        Assert.areEqual('X', cards[0].platform, 'Platform drives the card icon');
        Assert.areEqual('@kenalumni', cards[0].handle,
            'An X card must carry the handle from its Ken_Alm_Integration_Settings__mdt record');
    }

    // ═══════════════════ getSocialProfileLinks ═══════════════════

    @isTest
    static void getSocialProfileLinksBuildsFromHandlesAndAccountId() {
        KenSocialSync.overrides.put('Facebook', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'Facebook', Is_Active__c = true, Account_Handle__c = '@KenverseAlumni'
        ));
        KenSocialSync.overrides.put('Instagram', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'Instagram', Is_Active__c = true, Account_Handle__c = 'inst.handle'
        ));
        KenSocialSync.overrides.put('X', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'X', Is_Active__c = false, Account_Handle__c = '@kenalumni'
        ));
        KenSocialSync.overrides.put('LinkedIn', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'LinkedIn', Is_Active__c = true, Account_Id__c = '88395943'
        ));

        Test.startTest();
        Map<String, String> links = KenLandingPageController.getSocialProfileLinks();
        Test.stopTest();

        Assert.areEqual('https://facebook.com/KenverseAlumni', links.get('Facebook'),
            'Facebook link is built from the handle with @ stripped');
        Assert.areEqual('https://instagram.com/inst.handle', links.get('Instagram'),
            'Instagram link is built the same way even without a leading @');
        Assert.isFalse(links.containsKey('X'), 'An inactive platform must not produce a link');
        Assert.areEqual('https://www.linkedin.com/company/88395943/', links.get('LinkedIn'),
            'LinkedIn falls back to its numeric Account_Id__c, not a handle');
    }

    @isTest
    static void getSocialProfileLinksPrefersProfileUrlOverConstructedLink() {
        KenSocialSync.overrides.put('Facebook', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'Facebook', Is_Active__c = true, Account_Handle__c = '@KenverseAlumni',
            Profile_URL__c = 'https://custom.example.com/fb-page'
        ));
        KenSocialSync.overrides.put('LinkedIn', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'LinkedIn', Is_Active__c = true, Account_Id__c = '88395943',
            Profile_URL__c = 'https://custom.example.com/li-page'
        ));

        Test.startTest();
        Map<String, String> links = KenLandingPageController.getSocialProfileLinks();
        Test.stopTest();

        Assert.areEqual('https://custom.example.com/fb-page', links.get('Facebook'),
            'An explicit Profile_URL__c must win over a handle-constructed link');
        Assert.areEqual('https://custom.example.com/li-page', links.get('LinkedIn'),
            'An explicit Profile_URL__c must win over the Account_Id__c-derived link');
    }

    @isTest
    static void getSocialProfileLinksSkipsBlankHandleAndMissingLinkedInIdentifier() {
        KenSocialSync.overrides.put('X', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'X', Is_Active__c = true, Account_Handle__c = ''
        ));
        KenSocialSync.overrides.put('LinkedIn', new Ken_Alm_Integration_Settings__mdt(
            Service__c = 'LinkedIn', Is_Active__c = true
        ));

        Test.startTest();
        Map<String, String> links = KenLandingPageController.getSocialProfileLinks();
        Test.stopTest();

        Assert.isFalse(links.containsKey('X'), 'A blank handle must not produce a link');
        Assert.isFalse(links.containsKey('LinkedIn'),
            'LinkedIn with neither Profile_URL__c nor Account_Id__c must not produce a link');
    }

    // ═══════════════════ getContactEmailAddress ═══════════════════

    @isTest
    static void getContactEmailAddressFallsBackToInstitutionEmailWhenDisplayNameNotFound() {
        insert new Ken_Alm_Org_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            // Guaranteed not to match any real OrgWideEmailAddress in any org this
            // test runs in, so the lookup deterministically comes back empty.
            Org_Wide_Email_Address__c = 'Nonexistent Display Name XYZ123',
            Institution_Email__c = 'fallback@example.com'
        );

        Test.startTest();
        String email = KenLandingPageController.getContactEmailAddress();
        Test.stopTest();

        Assert.areEqual('fallback@example.com', email,
            'No OrgWideEmailAddress matches the configured display name, so Institution_Email__c is the fallback');
    }

    // ═══════════════════ getOrgContactDetails ═══════════════════

    @isTest
    static void getOrgContactDetailsReturnsWrapperWithoutError() {
        Test.startTest();
        KenLandingPageController.OrgContactDetails details = KenLandingPageController.getOrgContactDetails();
        Test.stopTest();

        Assert.isNotNull(details,
            'A wrapper should always come back, even when Organization has nothing set');
    }
}