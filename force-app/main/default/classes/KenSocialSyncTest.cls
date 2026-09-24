/**
 * @description Covers KenSocialSync - the whole social feed: scheduling, the
 *              run, the per-platform callouts, configuration and the fetch
 *              limit.
 *
 *              One test class because there is one class under test. It absorbed
 *              KenPlatformFetcherTest, KenSocialConfigTest,
 *              KenSocialMediaSyncServiceTest, KenSocialSyncQueueableTest and
 *              KenSocialSyncTest as those classes were consolidated.
 *
 *              A scheduled Apex test never actually fires on the cron - stopTest
 *              runs the job once, immediately - so what is worth asserting is
 *              that the configured expression reaches the CronTrigger, that a bad
 *              expression cannot leave the org unscheduled, and that rescheduling
 *              is repeatable, since System.schedule throws on a duplicate job
 *              name.
 *
 *              Several tests schedule for real rather than asserting on the
 *              string, because only System.schedule can tell us an expression is
 *              actually valid - a string comparison would happily pass on a cron
 *              Salesforce rejects.
 *
 *              Every callout test name is platform-prefixed. That is not
 *              decoration: most of those assertions exist per platform (each one
 *              drops non-image posts, each one must stay silent when dormant), so
 *              without the prefix half of them would collide, and a failure report
 *              has to say which platform broke.
 *
 *              Config comes from the override seam rather than the org's records,
 *              so assertions stay independent of whichever accounts the running
 *              org points at - and a test can never write over a real token. The
 *              one exception is readsARealDeployedRecord, which is deliberate; see
 *              its comment.
 */
@IsTest
private class KenSocialSyncTest {

    /**
     * Deliberately NOT the production job name.
     *
     * Scheduled jobs are not isolated in Apex tests: System.schedule sees the
     * org's real CronTrigger rows and rejects a duplicate name. Once the sync is
     * genuinely scheduled in an org, tests that scheduled under the production
     * name would fail with "already scheduled for execution" - breaking every
     * later deploy and CI run. Using a separate name also guarantees a test's
     * unschedule() can never abort the org's live job.
     */
    private static final String JOB = 'Ken Social Media Sync TEST';

    /** Redirects the scheduler onto the test-only job name. */
    private static void useTestJobName() {
        KenSocialSync.jobNameOverride = JOB;
    }

    private static String scheduledCron(Id cronId) {
        return [SELECT CronExpression FROM CronTrigger WHERE Id = :cronId].CronExpression;
    }

    @IsTest
    static void aNullExpressionIsRejectedRatherThanDefaulted() {
        useTestJobName();

        Boolean threw = false;
        Test.startTest();
        try {
            KenSocialSync.schedule(null);
        } catch (IllegalArgumentException ex) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw,
            'This class holds no cron of its own, so there is nothing to fall back TO. '
            + 'Inventing a cadence here would schedule the band at a rhythm nobody chose');
        Assert.isNull(KenSocialSync.currentCron(),
            'and a rejected call must leave no job behind');
    }

    @IsTest
    static void usesTheExpressionItIsGiven() {
        useTestJobName();

        Test.startTest();
        Id cronId = KenSocialSync.schedule('0 0 2 ? * MON');
        Test.stopTest();

        Assert.areEqual('0 0 2 ? * MON', scheduledCron(cronId),
            'The caller\'s expression should reach the job verbatim');
    }

    @IsTest
    static void trimsWhitespaceFromAPastedValue() {
        useTestJobName();

        Test.startTest();
        Id cronId = KenSocialSync.schedule('   0 0 5 1 * ?   ');
        Test.stopTest();

        Assert.areEqual('0 0 5 1 * ?', scheduledCron(cronId),
            'A value pasted from docs or a spreadsheet often carries stray whitespace, '
            + 'which System.schedule would otherwise reject');
    }

    @IsTest
    static void aWhitespaceOnlyExpressionIsRejectedToo() {
        useTestJobName();

        Boolean threw = false;
        Test.startTest();
        try {
            KenSocialSync.schedule('     ');
        } catch (IllegalArgumentException ex) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw,
            'A field that looks filled in but holds only spaces is the likeliest way an '
            + 'empty cadence reaches this method, so it must fail the same way as null');
    }

    @IsTest
    static void schedulesAWeekdaysOnlyExpressionForReal() {
        // The kind of schedule raw cron exists for - a range in the day-of-week
        // position, which structured scheduling UI cannot express.
        useTestJobName();

        Test.startTest();
        Id cronId = KenSocialSync.schedule('0 0 2 ? * MON-FRI');
        Test.stopTest();

        Assert.areEqual('0 0 2 ? * MON-FRI', scheduledCron(cronId),
            'A day-of-week range should be accepted');
    }

    @IsTest
    static void schedulesATwiceMonthlyExpressionForReal() {
        useTestJobName();

        Test.startTest();
        Id cronId = KenSocialSync.schedule('0 30 0 1,15 * ?');
        Test.stopTest();

        Assert.areEqual('0 30 0 1,15 * ?', scheduledCron(cronId),
            'A list in the day-of-month position, and a half-past start, should be accepted');
    }

    @IsTest
    static void aMalformedExpressionThrowsRatherThanSilentlyFallingBack() {
        // This USED to fall back to the default. That was right while the value
        // came from a custom setting the admin edited elsewhere and would never
        // see fail. Passed in directly, a fallback would ignore what they just
        // typed and leave them believing a schedule they do not have.
        useTestJobName();

        Test.startTest();
        Boolean threw = false;
        try {
            KenSocialSync.schedule('this is not a cron expression');
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A malformed expression must fail loudly, not silently');
        Assert.areEqual(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :JOB],
            'and must not leave a half-configured job behind');
    }

    @IsTest
    static void theClassicBothWildcardsMistakeIsRejected() {
        // Cron requires "?" in exactly one of day-of-month / day-of-week. "*" in
        // both is the single most common mistake, and the admin must be told.
        useTestJobName();

        Test.startTest();
        Boolean threw = false;
        try {
            KenSocialSync.schedule('0 0 2 * * *');
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw,
            'The most common cron mistake must surface, not be quietly swapped out');
    }

    @IsTest
    static void rescheduleMovesTheJobToTheNewCadence() {
        useTestJobName();
        KenSocialSync.schedule('0 0 0 1 * ?');

        Test.startTest();
        Id newCronId = KenSocialSync.reschedule('0 0 3 ? * SAT');
        Test.stopTest();

        Assert.areEqual('0 0 3 ? * SAT', scheduledCron(newCronId),
            'reschedule() should rebuild the job at the expression it was given');
        Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :JOB],
            'Rescheduling must replace the job, not leave two running');
    }

    // ─────────── Every tick syncs ───────────

    @IsTest
    static void everyTickEnqueuesTheSync() {
        // The cron is now the ONLY cadence control. A tick that reached execute()
        // must always do the work, because nothing downstream will decide it was
        // too soon - that used to be the interval gate's job and it is gone.
        //
        // This also covers the enqueue itself, which is the ONLY way to catch
        // Apex refusing Queueable alongside another system interface - that
        // failure is invisible to the compiler and to the deploy.
        Test.startTest();
        new KenSocialSync().execute(null);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        Assert.areEqual(1, queued,
            'Reaching execute() must always enqueue - the cron already decided it was time');
    }

    @IsTest
    static void unscheduleRemovesTheJobSoTheCadenceCanBeChanged() {
        useTestJobName();

        Test.startTest();
        KenSocialSync.schedule('0 0 0 1 * ?');
        Boolean removed = KenSocialSync.unschedule();
        Test.stopTest();

        Assert.isTrue(removed, 'unschedule() should report that it aborted a job');
        Assert.areEqual(0, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :JOB],
            'The job should be gone, so schedule() can be called again without throwing');
    }

    @IsTest
    static void unscheduleIsSafeWhenNothingIsScheduled() {
        useTestJobName();

        Test.startTest();
        Boolean removed = KenSocialSync.unschedule();
        Test.stopTest();

        Assert.isFalse(removed,
            'Unscheduling a job that was never scheduled must return false, not throw');
    }

    @IsTest
    static void productionJobNameStaysStable() {
        // unschedule() finds the job by name, so a rename would orphan the
        // running job in every existing org and silently create a second one
        // alongside it. Asserted against the constant rather than by scheduling,
        // because scheduling under the production name collides with the real job.
        Assert.areEqual('Ken Social Media Sync', KenSocialSync.JOB_NAME,
            'Renaming the job would orphan the live CronTrigger in every org');
    }

    // ═════════════ the sync run (was the queueable half) ═════════════

    /** A config in the shape a fully working platform would have. */
    /** The same config with no Named Credential, which is how a platform reads as unconfigured. */
    private static Ken_Alm_Integration_Settings__mdt noConnection(Ken_Alm_Integration_Settings__mdt config) {
        return new Ken_Alm_Integration_Settings__mdt(
            Service__c       = config.Service__c,
            Is_Active__c      = config.Is_Active__c,
            Account_Id__c     = config.Account_Id__c,
            Account_Handle__c = config.Account_Handle__c,
            API_Version__c    = config.API_Version__c
        );
    }

    private static Ken_Alm_Integration_Settings__mdt usableConfig(String platform) {
        return new Ken_Alm_Integration_Settings__mdt(
            Service__c       = platform,
            Connection__c    = 'Test_Social',
            Is_Active__c      = true,
            Account_Id__c     = '123',
            Account_Handle__c = 'kenalumni',
            // Both hosts are accepted by every platform's endpoint builder; only
            // whether a branch EXISTS is under test here, not what it builds.
            API_Version__c    = 'v21.0'
        );
    }

    /** Records that a callout happened, and what it was aimed at. */
    private class EndpointRecordingMock implements HttpCalloutMock {
        private String requestedEndpoint;

        public HttpResponse respond(HttpRequest req) {
            requestedEndpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"data":[]}');
            return res;
        }
    }

    @IsTest
    static void everyListedPlatformIsRoutable() {
        // Guards the one way this class can break silently: adding a platform to
        // ALL_PLATFORMS without giving it a branch in the service's endpoint
        // builder would skip it on every run, logging an error nobody reads.
        //
        // A reached callout is the proof. There is no longer a fetcher OBJECT to
        // assert against - one service serves every platform - so what is still
        // breakable is whether the name resolves to a request at all.
        Test.startTest();
        for (String platform : KenSocialSync.ALL_PLATFORMS) {
            KenSocialSync.overrides.put(platform, usableConfig(platform));
            EndpointRecordingMock mock = new EndpointRecordingMock();
            Test.setMock(HttpCalloutMock.class, mock);

            KenSocialSync.fetchRecent(platform);

            Assert.isNotNull(mock.requestedEndpoint,
                'No endpoint is built for listed platform: ' + platform);
        }
        Test.stopTest();
    }

    @IsTest
    static void unknownPlatformIsSkippedNotFatal() {
        // syncOne guards the name rather than passing it through, so a typo'd
        // platform is logged instead of producing an empty run indistinguishable
        // from a dormant one. Reaching the assertion is the point: it must not throw.
        Test.startTest();
        KenSocialSync.syncOne('Myspace');
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Ken_Social_Media_Post__c],
            'An unrecognised platform must store nothing, and must not throw');
    }

    @IsTest
    static void runsWithoutErrorWhenEveryPlatformIsDormant() {
        Test.startTest();
        Id jobId = KenSocialSync.enqueueAll();
        Test.stopTest();

        Assert.isNotNull(jobId, 'enqueueAll should return a job id');

        // The job completing is the assertion: a dormant platform must not throw,
        // and no post should have been invented out of nothing.
        Assert.areEqual(0, [SELECT COUNT() FROM Ken_Social_Media_Post__c],
            'A dormant sync must not create records');
    }

    @IsTest
    static void storesAFetchedPostEndToEnd() {
        // The one test that drives the whole pipeline: fetch, dedup, image
        // download, rehost and upsert, through the queued job rather than by
        // calling the service directly.
        KenSocialSync.overrides.put('X', new Ken_Alm_Integration_Settings__mdt(
            Service__c       = 'X',
            Connection__c    = 'Test_Social',
            Is_Active__c      = true,
            Account_Id__c     = '123',
            Account_Handle__c = 'kenalumni',
            API_Version__c    = '2'
        ));
        Test.setMock(HttpCalloutMock.class, new TimelineThenImageMock());

        Test.startTest();
        System.enqueueJob(new KenSocialSync.Runner(new List<String>{ 'X' }));
        Test.stopTest();

        List<Ken_Social_Media_Post__c> posts = [
            SELECT External_Post_Id__c, Platform__c, Body__c, Post_URL__c,
                   Media_Share_URL__c, Posted_At__c
            FROM Ken_Social_Media_Post__c
        ];
        Assert.areEqual(1, posts.size(), 'The run should have stored the post');
        Assert.areEqual('X:555', posts[0].External_Post_Id__c, 'Dedup key should be stored');
        Assert.areEqual('X', posts[0].Platform__c, 'Platform drives the card icon');
        Assert.areEqual('Convocation day', posts[0].Body__c, 'Post text becomes the body');
        Assert.areEqual('https://x.com/kenalumni/status/555', posts[0].Post_URL__c,
            'The built deep link should survive to the record');
    }

    @IsTest
    static void doesNothingWhenGivenNoPlatforms() {
        Test.startTest();
        System.enqueueJob(new KenSocialSync.Runner(new List<String>()));
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Ken_Social_Media_Post__c],
            'An empty platform list is a no-op, not an error');
    }

    /** A platform whose endpoint is unreachable, as a dead credential would be. */
    private class ExplodingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('simulated dead credential');
        }
    }

    @IsTest
    static void oneBrokenPlatformIsLoggedAndSwallowedNotFatal() {
        // The guarantee the whole chain depends on: if a platform's config or
        // credential is broken, the run must log it and carry on to the next
        // platform. An escaping exception would kill the job and every platform
        // queued behind it.
        //
        // Driven through a throwing HttpCalloutMock rather than an injected fake
        // fetcher: the fetcher interface that seam relied on went away when the
        // four platform classes became one service. This exercises the real path
        // a dead credential takes, which the fake only approximated.
        KenSocialSync.overrides.put('Instagram', usableConfig('Instagram'));
        Test.setMock(HttpCalloutMock.class, new ExplodingMock());

        Test.startTest();
        KenSocialSync.syncOne('Instagram');
        Test.stopTest();

        // Reaching here at all is the assertion - syncOne must not rethrow.
        Assert.areEqual(0, [SELECT COUNT() FROM Ken_Social_Media_Post__c],
            'A broken platform must store nothing, and must not throw');
    }

    /**
     * @description Answers the X timeline on the api.x.com call and a tiny PNG on
     *              the pbs.twimg.com call, so one mock can serve the whole
     *              fetch-then-download sequence the service performs.
     */
    private class TimelineThenImageMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            if (req.getEndpoint().startsWith('callout:')) {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'data' => new List<Object>{
                        new Map<String, Object>{
                            'id'          => '555',
                            'text'        => 'Convocation day',
                            'created_at'  => '2026-08-13T10:00:00.000Z',
                            'attachments' => new Map<String, Object>{
                                'media_keys' => new List<String>{ '3_555' }
                            }
                        }
                    },
                    'includes' => new Map<String, Object>{
                        'media' => new List<Object>{
                            new Map<String, Object>{
                                'media_key' => '3_555',
                                'type'      => 'photo',
                                'url'       => 'https://pbs.twimg.com/media/abc.jpg'
                            }
                        }
                    }
                }));
                return res;
            }

            // The image. Must exceed the service's 100-byte floor, which rejects
            // error pages and tracking pixels, so a single pixel will not do.
            res.setHeader('Content-Type', 'image/png');
            res.setBodyAsBlob(Blob.valueOf('x'.repeat(500)));
            return res;
        }
    }

    // ───────────────────────── shared harness ─────────────────────────

    private static final String IG_ID       = '17841442872605647';
    private static final String FB_PAGE_ID  = '1226664980537896';
    private static final String FB_OTHER_ID = '9999999999999999';
    private static final String X_USER_ID   = '1234567890123456789';
    private static final String X_HANDLE    = 'kenversealumni';
    private static final String X_PHOTO_URL = 'https://pbs.twimg.com/media/AbCdEfGhIj.jpg';
    private static final String TH_USER_ID  = '17841400000000000';
    private static final String TH_IMG =
        'https://scontent-bom1-2.cdninstagram.com/v/t51/threads.jpg?oh=sig';

    /**
     * Returns a canned response and remembers what it was asked for.
     *
     * Captures the Authorization header as well as the endpoint, because that is
     * the one request-shape difference between platforms worth asserting: X
     * authenticates by header, the other three by query parameter.
     */
    private class ApiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        private String requestedEndpoint;
        private String authorizationHeader;

        private ApiMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            requestedEndpoint = req.getEndpoint();
            authorizationHeader = req.getHeader('Authorization');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static List<KenSocialSync.FetchedPost> fetchWith(
        String platform,
        Ken_Alm_Integration_Settings__mdt configRow,
        ApiMock mock
    ) {
        KenSocialSync.overrides.put(platform, configRow);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<KenSocialSync.FetchedPost> posts =
            KenSocialSync.fetchRecent(platform);
        Test.stopTest();
        return posts;
    }

    /** A `data`-wrapped body, which is the shape all three Meta-family APIs use. */
    private static String dataBody(List<Map<String, Object>> rows) {
        return JSON.serialize(new Map<String, Object>{ 'data' => rows });
    }

    // ═════════════════════ configuration ═════════════════════

    /** The same fully-working shape, fixed to Instagram for the guard tests. */
    private static Ken_Alm_Integration_Settings__mdt usable() {
        return usableConfig('Instagram');
    }

    private static void stub(Ken_Alm_Integration_Settings__mdt config) {
        KenSocialSync.overrides.put(config.Service__c, config);
    }

    @IsTest
    static void anUnknownPlatformYieldsAnEmptyRecordNotNull() {
        Ken_Alm_Integration_Settings__mdt config = KenSocialSync.forPlatform('Myspace');

        // The whole point: absence must surface as a blank token, which callers
        // already treat as dormant, rather than as a NullPointerException part
        // way through a sync.
        Assert.isNotNull(config, 'A missing platform must not return null');
        Assert.isNull(config.Connection__c, 'and must read as unconfigured');
    }

    @IsTest
    static void anOverrideWinsOverTheDeployedRecord() {
        Ken_Alm_Integration_Settings__mdt stubbed = usable();
        stubbed.Service__c = 'Facebook';
        stubbed.Account_Id__c = 'stubbed-id';
        stub(stubbed);

        Assert.areEqual('stubbed-id',
            KenSocialSync.forPlatform('Facebook').Account_Id__c,
            'A test override must take precedence over the deployed record');
    }

    @IsTest
    static void isUsableWhenActiveAndFullyConfigured() {
        stub(usable());

        Assert.isTrue(KenSocialSync.isUsable('Instagram'),
            'Active, with an account id and a token, is usable');
    }

    @IsTest
    static void isNotUsableWhenSwitchedOff() {
        Ken_Alm_Integration_Settings__mdt config = usable();
        config.Is_Active__c = false;
        stub(config);

        Assert.isFalse(KenSocialSync.isUsable('Instagram'),
            'Switched off must be unusable even when fully configured - that is how a '
            + 'dormant platform avoids costing a callout');
    }

    @IsTest
    static void isNotUsableWithoutAToken() {
        Ken_Alm_Integration_Settings__mdt config = usable();
        config.Connection__c = null;
        stub(config);

        // Ticking Is_Active before pasting the credential is the normal order of
        // events, so this state is expected rather than an error.
        Assert.isFalse(KenSocialSync.isUsable('Instagram'),
            'Active but with no Named Credential must be unusable, not a failed callout');
    }

    @IsTest
    static void isNotUsableWithoutAnAccountId() {
        Ken_Alm_Integration_Settings__mdt config = usable();
        config.Account_Id__c = null;
        stub(config);

        Assert.isFalse(KenSocialSync.isUsable('Instagram'),
            'A token with nothing to point it at cannot build a request');
    }

    @IsTest
    static void aWhitespaceOnlyTokenIsUnusable() {
        Ken_Alm_Integration_Settings__mdt config = usable();
        config.Connection__c = '   ';
        stub(config);

        Assert.isFalse(KenSocialSync.isUsable('Instagram'),
            'Whitespace is not a credential');
    }

    // ═════════════════════ the org-wide fetch limit ═════════════════════

    /*
     * Worth isolating because every platform depends on it and a bad value has
     * consequences no per-platform test would catch: too high and a run exceeds
     * the 100-callout ceiling and dies mid-sync, too low and the band goes short.
     */

    /** Writes the org-wide parameter the way an admin would. */
    private static void setOrgLimit(Decimal value) {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        params.SetupOwnerId = UserInfo.getOrganizationId();
        params.Social_Fetch_Limit__c = value;
        upsert params;
    }

    @IsTest
    static void readsTheConfiguredOrgWideLimit() {
        setOrgLimit(7);

        Assert.areEqual(7, KenSocialSync.fetchLimit(),
            'Every platform should read the org parameter');
    }

    @IsTest
    static void fallsBackToTheDefaultWhenUnset() {
        // No parameter row written at all - the state a fresh org is in.
        Assert.areEqual(KenSocialSync.DEFAULT_FETCH_LIMIT,
            KenSocialSync.fetchLimit(),
            'An unconfigured org must still sync, not fetch zero posts');
    }

    @IsTest
    static void fallsBackToTheDefaultOnZeroOrNegative() {
        setOrgLimit(0);
        Assert.areEqual(KenSocialSync.DEFAULT_FETCH_LIMIT,
            KenSocialSync.fetchLimit(),
            'Zero would silently disable the whole feed');

        setOrgLimit(-5);
        Assert.areEqual(KenSocialSync.DEFAULT_FETCH_LIMIT,
            KenSocialSync.fetchLimit(),
            'A negative limit is meaningless and must not reach the platforms');
    }

    @IsTest
    static void clampsAnOversizedLimit() {
        // A run performs one fetch plus one image download per post, against a
        // 100-callout ceiling. Left unclamped this would abort the sync with an
        // uncatchable limit exception rather than degrading.
        setOrgLimit(500);

        Assert.areEqual(KenSocialSync.MAX_FETCH_LIMIT,
            KenSocialSync.fetchLimit(),
            'An oversized value must be capped, not obeyed');
    }

    @IsTest
    static void acceptsTheCapItself() {
        setOrgLimit(KenSocialSync.MAX_FETCH_LIMIT);

        Assert.areEqual(KenSocialSync.MAX_FETCH_LIMIT,
            KenSocialSync.fetchLimit(),
            'The boundary value is legal and must not be clamped down');
    }

    @IsTest
    static void overrideWinsSoTestsNeedNoOrgWrite() {
        setOrgLimit(9);
        KenSocialSync.fetchLimitOverride = 2;

        Assert.areEqual(2, KenSocialSync.fetchLimit(),
            'The test seam must take precedence over the stored parameter');
    }

    // ═════════════════════ Instagram ═════════════════════

    private static Ken_Alm_Integration_Settings__mdt igConfig(Boolean isActive, String token) {
        return igConfig(isActive, token, IG_ID);
    }

    private static Ken_Alm_Integration_Settings__mdt igConfig(
        Boolean isActive,
        String token,
        String igId
    ) {
        return new Ken_Alm_Integration_Settings__mdt(
            Service__c      = 'Instagram',
            Connection__c   = 'Test_Social',
            Is_Active__c     = isActive,
            Account_Id__c    = igId,
            API_Version__c   = 'v21.0'
        );
    }

    /**
     * @description One media row in the shape Graph returns.
     *
     * @param mediaUrl media_url, or null to omit it
     */
    private static Map<String, Object> igRow(
        String mediaId,
        String mediaType,
        String mediaUrl
    ) {
        Map<String, Object> entry = new Map<String, Object>{
            'id'         => mediaId,
            'caption'    => 'Caption for ' + mediaId,
            'media_type' => mediaType,
            'permalink'  => 'https://www.instagram.com/p/' + mediaId + '/',
            'timestamp'  => '2026-08-10T11:34:30+0000'
        };
        if (mediaUrl != null) {
            entry.put('media_url', mediaUrl);
        }
        return entry;
    }

    @IsTest
    static void instagramMapsImagePostOntoFetchedPost() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            igRow('18112569821318664', 'IMAGE',
                'https://scontent-bom1-2.cdninstagram.com/v/t51/photo.jpg?oh=sig')
        }));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('Instagram', igConfig(true, 'token'), mock);

        Assert.areEqual(1, posts.size(), 'An image post should ship');
        KenSocialSync.FetchedPost post = posts[0];
        Assert.areEqual('Instagram:18112569821318664', post.externalId,
            'External id must be platform-prefixed so the dedup key cannot collide');
        Assert.areEqual('Instagram', post.platform,
            'Platform must match the Ken_Social_Media_Post__c picklist value');
        Assert.areEqual('Caption for 18112569821318664', post.body,
            'caption becomes the card body');
        Assert.areEqual('https://scontent-bom1-2.cdninstagram.com/v/t51/photo.jpg?oh=sig',
            post.sourceImageUrl, 'media_url is the image to rehost');
        Assert.areEqual('https://www.instagram.com/p/18112569821318664/', post.postUrl,
            'permalink becomes the card\'s deep link');
        Assert.areEqual(DateTime.newInstanceGmt(2026, 8, 10, 11, 34, 30), post.postedAt,
            'timestamp should normalise to the same GMT instant');
    }

    @IsTest
    static void instagramKeepsCarouselAlbums() {
        // An album's first child is a still image, so the post is renderable.
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            igRow('111', 'CAROUSEL_ALBUM', 'https://scontent.cdninstagram.com/v/t51/album.jpg')
        }));

        Assert.areEqual(1, fetchWith('Instagram', igConfig(true, 'token'), mock).size(),
            'A carousel album is usable as a single-image card');
    }

    @IsTest
    static void instagramDropsVideoPosts() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            igRow('222', 'VIDEO', 'https://scontent.cdninstagram.com/v/t51/clip.mp4')
        }));

        Assert.isTrue(fetchWith('Instagram', igConfig(true, 'token'), mock).isEmpty(),
            'Only still images are shown on the landing page for v1');
    }

    @IsTest
    static void instagramDropsPostsWithNoMediaUrl() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            igRow('333', 'IMAGE', null)
        }));

        Assert.isTrue(fetchWith('Instagram', igConfig(true, 'token'), mock).isEmpty(),
            'A post with no image has nothing to render');
    }

    @IsTest
    static void instagramDropsPostsWithAnUnparseableTimestamp() {
        Map<String, Object> bad = igRow('444', 'IMAGE',
            'https://scontent.cdninstagram.com/v/t51/photo.jpg');
        bad.put('timestamp', 'not-a-date');
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{ bad }));

        Assert.isTrue(fetchWith('Instagram', igConfig(true, 'token'), mock).isEmpty(),
            'Posted_At__c drives the band ordering, so a post without one is unusable');
    }

    @IsTest
    static void instagramRequestsTheMediaEdgeForTheConfiguredAccount() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));

        fetchWith('Instagram', igConfig(true, 'tok en'), mock);

        Assert.isTrue(mock.requestedEndpoint.contains('/' + IG_ID + '/media'),
            'Instagram is addressed by its business account id on the media edge');
        Assert.isFalse(mock.requestedEndpoint.contains('access_token'),
            'The credential is supplied by the Named Credential header, never in the URL');
    }

    @IsTest
    static void instagramReturnsEmptyWhenSwitchedOff() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            igRow('555', 'IMAGE', 'https://scontent.cdninstagram.com/v/t51/photo.jpg')
        }));

        Assert.isTrue(fetchWith('Instagram', igConfig(false, 'token'), mock).isEmpty(),
            'Is_Active__c false must stop the platform entirely');
        Assert.isNull(mock.requestedEndpoint, 'A dormant platform should not call out at all');
    }

    @IsTest
    static void instagramReturnsEmptyWhenTokenMissing() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));

        Assert.isTrue(fetchWith('Instagram', noConnection(igConfig(true, null)), mock).isEmpty(),
            'No token means nothing to fetch');
        Assert.isNull(mock.requestedEndpoint, 'An unconfigured platform should not call out');
    }

    @IsTest
    static void instagramReturnsEmptyWhenAccountIdMissing() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));

        Assert.isTrue(fetchWith('Instagram', igConfig(true, 'token', null), mock).isEmpty(),
            'Without the business account id there is no account to address');
        Assert.isNull(mock.requestedEndpoint, 'An unconfigured platform should not call out');
    }

    @IsTest
    static void instagramReturnsEmptyOnGraphError() {
        ApiMock mock = new ApiMock(200,
            '{"error":{"message":"Invalid OAuth access token","code":190}}');

        Assert.isTrue(fetchWith('Instagram', igConfig(true, 'token'), mock).isEmpty(),
            'Graph answers some failures with HTTP 200 and an error body');
    }

    @IsTest
    static void instagramReturnsEmptyOnHttpFailure() {
        ApiMock mock = new ApiMock(500, 'Internal Server Error');

        Assert.isTrue(fetchWith('Instagram', igConfig(true, 'token'), mock).isEmpty(),
            'One platform failing must not throw at the sync service');
    }

    // ═════════════════════ Facebook ═════════════════════

    private static Ken_Alm_Integration_Settings__mdt fbConfig(Boolean isActive, String token) {
        return new Ken_Alm_Integration_Settings__mdt(
            Service__c      = 'Facebook',
            Connection__c   = 'Test_Social',
            Is_Active__c     = isActive,
            Account_Id__c    = FB_PAGE_ID,
            API_Version__c   = 'v21.0'
        );
    }

    /**
     * @description One feed row in the shape Graph returns.
     *
     * @param authorId who posted it, or null to omit `from` entirely
     * @param imageUrl full_picture, or null to omit it
     */
    private static Map<String, Object> fbRow(
        String postId,
        String authorId,
        String statusType,
        String imageUrl
    ) {
        Map<String, Object> entry = new Map<String, Object>{
            'id'            => postId,
            'message'       => 'Caption for ' + postId,
            'created_time'  => '2026-08-10T11:34:30+0000',
            'status_type'   => statusType,
            'permalink_url' => 'https://www.facebook.com/' + FB_PAGE_ID + '/posts/' + postId
        };
        if (imageUrl != null) {
            entry.put('full_picture', imageUrl);
        }
        if (authorId != null) {
            entry.put('from', new Map<String, Object>{ 'id' => authorId, 'name' => 'Edu' });
        }
        return entry;
    }

    @IsTest
    static void facebookMapsImagePostOntoFetchedPost() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            fbRow(FB_PAGE_ID + '_111', FB_PAGE_ID, 'added_photos',
                'https://scontent-bom1-2.xx.fbcdn.net/v/t39/photo.png?oh=sig')
        }));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('Facebook', fbConfig(true, 'token'), mock);

        Assert.areEqual(1, posts.size(), 'A Page photo post should ship');
        KenSocialSync.FetchedPost post = posts[0];
        Assert.areEqual('Facebook:' + FB_PAGE_ID + '_111', post.externalId,
            'External id must be platform-prefixed so the dedup key cannot collide');
        Assert.areEqual('Facebook', post.platform,
            'Platform must match the Ken_Social_Media_Post__c picklist value');
        Assert.areEqual('Caption for ' + FB_PAGE_ID + '_111', post.body,
            'message becomes the card body');
        Assert.areEqual('https://scontent-bom1-2.xx.fbcdn.net/v/t39/photo.png?oh=sig',
            post.sourceImageUrl, 'full_picture is the image to rehost');
        Assert.areEqual(
            'https://www.facebook.com/' + FB_PAGE_ID + '/posts/' + FB_PAGE_ID + '_111',
            post.postUrl, 'permalink_url becomes the card\'s deep link');
        Assert.areEqual(DateTime.newInstanceGmt(2026, 8, 10, 11, 34, 30), post.postedAt,
            'created_time should normalise to the same GMT instant');
        Assert.isTrue(mock.requestedEndpoint.contains('/' + FB_PAGE_ID + '/feed'),
            'The Page feed edge is the one whose read permission the token carries');
    }

    @IsTest
    static void facebookDropsVideoPosts() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            fbRow(FB_PAGE_ID + '_222', FB_PAGE_ID, 'added_video',
                'https://scontent.xx.fbcdn.net/v/t39/thumbnail.jpg')
        }));

        Assert.isTrue(fetchWith('Facebook', fbConfig(true, 'token'), mock).isEmpty(),
            'A video carries a thumbnail in full_picture and must not ship as a photo card');
    }

    @IsTest
    static void facebookDropsPostsWithNoImage() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            fbRow(FB_PAGE_ID + '_333', FB_PAGE_ID, 'mobile_status_update', null)
        }));

        Assert.isTrue(fetchWith('Facebook', fbConfig(true, 'token'), mock).isEmpty(),
            'A text-only status has nothing to render');
    }

    @IsTest
    static void facebookDropsVisitorPosts() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            fbRow('444', FB_OTHER_ID, 'added_photos',
                'https://scontent.xx.fbcdn.net/v/t39/theirs.jpg'),
            fbRow(FB_PAGE_ID + '_555', FB_PAGE_ID, 'added_photos',
                'https://scontent.xx.fbcdn.net/v/t39/ours.jpg')
        }));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('Facebook', fbConfig(true, 'token'), mock);

        Assert.areEqual(1, posts.size(), 'Only the Page\'s own post should ship');
        Assert.areEqual('Facebook:' + FB_PAGE_ID + '_555', posts[0].externalId,
            'The surviving post should be ours');
    }

    @IsTest
    static void facebookKeepsPostsWithNoAuthorField() {
        // `from` is withheld while the token cannot read other people's content,
        // which is precisely when every row is already the Page's own.
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            fbRow(FB_PAGE_ID + '_666', null, 'added_photos',
                'https://scontent.xx.fbcdn.net/v/t39/ours.jpg')
        }));

        Assert.areEqual(1, fetchWith('Facebook', fbConfig(true, 'token'), mock).size(),
            'An absent author must not silently drop our own posts');
    }

    @IsTest
    static void facebookReturnsEmptyWhenSwitchedOff() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            fbRow(FB_PAGE_ID + '_777', FB_PAGE_ID, 'added_photos',
                'https://scontent.xx.fbcdn.net/v/t39/photo.jpg')
        }));

        Assert.isTrue(fetchWith('Facebook', fbConfig(false, 'token'), mock).isEmpty(),
            'Is_Active__c false must stop the platform entirely');
        Assert.isNull(mock.requestedEndpoint, 'A dormant platform should not call out at all');
    }

    @IsTest
    static void facebookReturnsEmptyWhenTokenMissing() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));

        Assert.isTrue(fetchWith('Facebook', noConnection(fbConfig(true, null)), mock).isEmpty(),
            'No token means nothing to fetch');
        Assert.isNull(mock.requestedEndpoint, 'An unconfigured platform should not call out');
    }

    @IsTest
    static void facebookReturnsEmptyOnGraphError() {
        ApiMock mock = new ApiMock(200,
            '{"error":{"message":"Invalid OAuth access token","code":190}}');

        Assert.isTrue(fetchWith('Facebook', fbConfig(true, 'token'), mock).isEmpty(),
            'Graph answers some failures with HTTP 200 and an error body');
    }

    @IsTest
    static void facebookReturnsEmptyOnHttpFailure() {
        ApiMock mock = new ApiMock(500, 'Internal Server Error');

        Assert.isTrue(fetchWith('Facebook', fbConfig(true, 'token'), mock).isEmpty(),
            'One platform failing must not throw at the sync service');
    }

    // ═════════════════════ X ═════════════════════

    private static Ken_Alm_Integration_Settings__mdt xConfig(Boolean isActive, String token) {
        return xConfig(isActive, token, X_HANDLE, 3);
    }

    /**
     * @description Builds a config and sets the ORG-WIDE fetch limit.
     *
     *              The limit does not live on the platform's config - it is one
     *              Ken_Alm_Org_Parameters__c value shared by every platform - so it
     *              is set through the override seam rather than as a field here.
     */
    private static Ken_Alm_Integration_Settings__mdt xConfig(
        Boolean isActive,
        String token,
        String handle,
        Integer fetchLimit
    ) {
        KenSocialSync.fetchLimitOverride = fetchLimit;
        return new Ken_Alm_Integration_Settings__mdt(
            Service__c       = 'X',
            Connection__c    = 'Test_Social',
            Is_Active__c      = isActive,
            Account_Id__c     = X_USER_ID,
            Account_Handle__c = handle,
            API_Version__c    = '2'
        );
    }

    /**
     * @description One timeline row in the shape X returns.
     *
     * @param mediaKeys attachments.media_keys, or null to omit attachments
     */
    private static Map<String, Object> xRow(
        String postId,
        String text,
        List<String> mediaKeys
    ) {
        Map<String, Object> entry = new Map<String, Object>{
            'id'         => postId,
            'text'       => text,
            'created_at' => '2026-08-13T10:00:00.000Z'
        };
        if (mediaKeys != null) {
            entry.put('attachments', new Map<String, Object>{ 'media_keys' => mediaKeys });
        }
        return entry;
    }

    private static Map<String, Object> xMedia(String mediaKey, String type, String url) {
        Map<String, Object> item = new Map<String, Object>{
            'media_key' => mediaKey,
            'type'      => type
        };
        if (url != null) {
            item.put('url', url);
        }
        return item;
    }

    /** X is the one platform whose images arrive in a sibling `includes` block. */
    private static String xTimeline(
        List<Map<String, Object>> rows,
        List<Map<String, Object>> mediaItems
    ) {
        Map<String, Object> body = new Map<String, Object>{ 'data' => rows };
        if (mediaItems != null) {
            body.put('includes', new Map<String, Object>{ 'media' => mediaItems });
        }
        return JSON.serialize(body);
    }

    @IsTest
    static void xMapsPhotoPostOntoFetchedPost() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{
                xRow('111', 'Convocation day!', new List<String>{ '3_111' })
            },
            new List<Map<String, Object>>{ xMedia('3_111', 'photo', X_PHOTO_URL) }
        ));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('X', xConfig(true, 'token'), mock);

        Assert.areEqual(1, posts.size(), 'A photo post should ship');
        KenSocialSync.FetchedPost post = posts[0];
        Assert.areEqual('X:111', post.externalId,
            'External id must be platform-prefixed so the dedup key cannot collide');
        Assert.areEqual('X', post.platform,
            'Platform must match the Ken_Social_Media_Post__c picklist value');
        Assert.areEqual('Convocation day!', post.body, 'text becomes the card body');
        Assert.areEqual(X_PHOTO_URL, post.sourceImageUrl,
            'The url must come from includes.media, joined by media_key');
        Assert.areEqual('https://x.com/' + X_HANDLE + '/status/111', post.postUrl,
            'X returns no permalink, so the deep link is built from the handle');
        Assert.areEqual(DateTime.newInstanceGmt(2026, 8, 13, 10, 0, 0), post.postedAt,
            'created_at should normalise to the same GMT instant');
    }

    @IsTest
    static void xSendsTokenAsAuthorizationHeader() {
        ApiMock mock = new ApiMock(200, xTimeline(new List<Map<String, Object>>(), null));

        fetchWith('X', xConfig(true, 'secret-token'), mock);

        Assert.areEqual('Bearer {!$Credential.Password}', mock.authorizationHeader,
            'The credential is resolved by the platform, so no token is built in Apex');
        Assert.isFalse(mock.requestedEndpoint.contains('secret-token'),
            'The token must never leak into the URL, where it would reach debug logs');
    }

    @IsTest
    static void xAsksForAtLeastFiveResults() {
        ApiMock mock = new ApiMock(200, xTimeline(new List<Map<String, Object>>(), null));

        // A Social Fetch Limit of 3 is the sensible setting, but X 400s below 5.
        fetchWith('X', xConfig(true, 'token', X_HANDLE, 3), mock);

        Assert.isTrue(mock.requestedEndpoint.contains('max_results=5'),
            'A fetch limit below X\'s floor of 5 must be raised, not sent verbatim');
        Assert.isTrue(mock.requestedEndpoint.contains('exclude=retweets,replies'),
            'Retweets carry someone else\'s content and must never reach the alumni band');
    }

    @IsTest
    static void xTrimsResultsBackToFetchLimit() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        List<Map<String, Object>> mediaItems = new List<Map<String, Object>>();
        for (Integer i = 1; i <= 5; i++) {
            rows.add(xRow(String.valueOf(i), 'Post ' + i, new List<String>{ '3_' + i }));
            mediaItems.add(xMedia('3_' + i, 'photo', X_PHOTO_URL));
        }
        ApiMock mock = new ApiMock(200, xTimeline(rows, mediaItems));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('X', xConfig(true, 'token', X_HANDLE, 3), mock);

        Assert.areEqual(3, posts.size(),
            'Over-asking to clear X\'s floor must not store more than the fetch limit');
        Assert.areEqual('X:1', posts[0].externalId, 'The newest posts are the ones kept');
    }

    @IsTest
    static void xDropsVideoPosts() {
        // A video carries preview_image_url rather than url, so it would ship as
        // a still that looks like a photo and plays nothing.
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{
                xRow('222', 'Watch this', new List<String>{ '7_222' })
            },
            new List<Map<String, Object>>{ xMedia('7_222', 'video', null) }
        ));

        Assert.isTrue(fetchWith('X', xConfig(true, 'token'), mock).isEmpty(),
            'Only still photos are shown for v1');
    }

    @IsTest
    static void xDropsTextOnlyPosts() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{ xRow('333', 'Just a thought', null) },
            null
        ));

        Assert.isTrue(fetchWith('X', xConfig(true, 'token'), mock).isEmpty(),
            'A post with no attachments has nothing to render');
    }

    @IsTest
    static void xDropsPostWhoseMediaKeyIsMissingFromIncludes() {
        // X omits an entry from includes.media when the media is unavailable,
        // leaving the post pointing at a key that resolves to nothing.
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{
                xRow('444', 'Orphaned key', new List<String>{ '3_444' })
            },
            new List<Map<String, Object>>()
        ));

        Assert.isTrue(fetchWith('X', xConfig(true, 'token'), mock).isEmpty(),
            'An unresolvable media key must not become a broken card');
    }

    @IsTest
    static void xPicksFirstPhotoFromAMixedPost() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{
                xRow('555', 'Album', new List<String>{ '7_vid', '3_pic' })
            },
            new List<Map<String, Object>>{
                xMedia('7_vid', 'video', null),
                xMedia('3_pic', 'photo', X_PHOTO_URL)
            }
        ));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('X', xConfig(true, 'token'), mock);

        Assert.areEqual(1, posts.size(), 'A post mixing video and photo is still renderable');
        Assert.areEqual(X_PHOTO_URL, posts[0].sourceImageUrl,
            'The video key must be skipped rather than ending the search');
    }

    @IsTest
    static void xStripsTrailingMediaShortlinkFromBody() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{
                xRow('666', 'Graduation photos https://t.co/AbCdEfGhIj',
                    new List<String>{ '3_666' })
            },
            new List<Map<String, Object>>{ xMedia('3_666', 'photo', X_PHOTO_URL) }
        ));

        Assert.areEqual('Graduation photos',
            fetchWith('X', xConfig(true, 'token'), mock)[0].body,
            'The trailing t.co link points at the image the card already shows');
    }

    @IsTest
    static void xKeepsLinksTheAuthorWroteMidSentence() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{
                xRow('777', 'Apply at https://t.co/AbCdEf before Friday',
                    new List<String>{ '3_777' })
            },
            new List<Map<String, Object>>{ xMedia('3_777', 'photo', X_PHOTO_URL) }
        ));

        Assert.areEqual('Apply at https://t.co/AbCdEf before Friday',
            fetchWith('X', xConfig(true, 'token'), mock)[0].body,
            'Only a TRAILING shortlink is X\'s own; one mid-sentence belongs to the author');
    }

    @IsTest
    static void xNullsOutABodyThatWasNothingButAShortlink() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{
                xRow('888', 'https://t.co/AbCdEf', new List<String>{ '3_888' })
            },
            new List<Map<String, Object>>{ xMedia('3_888', 'photo', X_PHOTO_URL) }
        ));

        Assert.isNull(fetchWith('X', xConfig(true, 'token'), mock)[0].body,
            'An empty string would still cost the card its 1rem flex gap; the LWC hides null');
    }

    @IsTest
    static void xStripsLeadingAtFromHandleInPostUrl() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{ xRow('999', 'Hello', new List<String>{ '3_999' }) },
            new List<Map<String, Object>>{ xMedia('3_999', 'photo', X_PHOTO_URL) }
        ));

        Assert.areEqual('https://x.com/' + X_HANDLE + '/status/999',
            fetchWith('X', xConfig(true, 'token', '@' + X_HANDLE, 3), mock)[0].postUrl,
            'Admins type the handle with an @; it must not double up in the path');
    }

    @IsTest
    static void xLeavesPostUrlNullWhenHandleIsBlank() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{ xRow('1010', 'Hello', new List<String>{ '3_1010' }) },
            new List<Map<String, Object>>{ xMedia('3_1010', 'photo', X_PHOTO_URL) }
        ));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('X', xConfig(true, 'token', null, 3), mock);

        Assert.areEqual(1, posts.size(), 'A missing handle must not cost us the post itself');
        Assert.isNull(posts[0].postUrl,
            'A half-built URL would show the wrong account; the LWC drops a null href');
    }

    @IsTest
    static void xReturnsEmptyWhenSwitchedOff() {
        ApiMock mock = new ApiMock(200, xTimeline(
            new List<Map<String, Object>>{ xRow('111', 'Hello', new List<String>{ '3_111' }) },
            new List<Map<String, Object>>{ xMedia('3_111', 'photo', X_PHOTO_URL) }
        ));

        Assert.isTrue(fetchWith('X', xConfig(false, 'token'), mock).isEmpty(),
            'Is_Active__c false must stop the platform entirely');
        Assert.isNull(mock.requestedEndpoint,
            'X bills per post read, so a dormant platform must not call out at all');
    }

    @IsTest
    static void xReturnsEmptyWhenTokenMissing() {
        ApiMock mock = new ApiMock(200, xTimeline(new List<Map<String, Object>>(), null));

        Assert.isTrue(fetchWith('X', noConnection(xConfig(true, null)), mock).isEmpty(),
            'No token means nothing to fetch');
        Assert.isNull(mock.requestedEndpoint, 'An unconfigured platform should not call out');
    }

    @IsTest
    static void xReturnsEmptyWhenTimelineHasNoPosts() {
        // An account with nothing to return omits `data` rather than sending [].
        ApiMock mock = new ApiMock(200, '{"meta":{"result_count":0}}');

        Assert.isTrue(fetchWith('X', xConfig(true, 'token'), mock).isEmpty(),
            'An absent data array is normal, not a fault');
    }

    @IsTest
    static void xReturnsEmptyOnPartialErrorResponse() {
        ApiMock mock = new ApiMock(200,
            '{"errors":[{"message":"Sorry, that page does not exist"}]}');

        Assert.isTrue(fetchWith('X', xConfig(true, 'token'), mock).isEmpty(),
            'X answers some failures with HTTP 200 and an errors array');
    }

    @IsTest
    static void xReturnsEmptyOnProblemDocument() {
        ApiMock mock = new ApiMock(200,
            '{"title":"Unauthorized","detail":"Unauthorized","status":401}');

        Assert.isTrue(fetchWith('X', xConfig(true, 'token'), mock).isEmpty(),
            'An RFC 7807 problem document is the other way X reports failure');
    }

    @IsTest
    static void xReturnsEmptyOnHttpFailure() {
        ApiMock mock = new ApiMock(429, '{"title":"Too Many Requests"}');

        Assert.isTrue(fetchWith('X', xConfig(true, 'token'), mock).isEmpty(),
            'One platform failing must not throw at the sync service');
    }

    // ═════════════════════ Threads ═════════════════════

    private static Ken_Alm_Integration_Settings__mdt threadsConfig(Boolean isActive, String token) {
        return new Ken_Alm_Integration_Settings__mdt(
            Service__c       = 'Threads',
            Connection__c    = 'Test_Social',
            Is_Active__c      = isActive,
            Account_Id__c     = TH_USER_ID,
            Account_Handle__c = '@kenversealumni',
            API_Version__c    = 'v1.0'
        );
    }

    private static Map<String, Object> threadsRow(String id, String mediaType, String mediaUrl) {
        Map<String, Object> entry = new Map<String, Object>{
            'id'         => id,
            'text'       => 'Caption for ' + id,
            'media_type' => mediaType,
            'permalink'  => 'https://www.threads.net/@kenversealumni/post/' + id,
            'timestamp'  => '2026-08-13T10:00:00+0000'
        };
        if (mediaUrl != null) {
            entry.put('media_url', mediaUrl);
        }
        return entry;
    }

    @IsTest
    static void threadsMapsImagePostOntoFetchedPost() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            threadsRow('111', 'IMAGE', TH_IMG)
        }));

        List<KenSocialSync.FetchedPost> posts =
            fetchWith('Threads', threadsConfig(true, 'token'), mock);

        Assert.areEqual(1, posts.size(), 'An image post should ship');
        KenSocialSync.FetchedPost post = posts[0];
        Assert.areEqual('Threads:111', post.externalId,
            'External id must be platform-prefixed so the dedup key cannot collide');
        Assert.areEqual('Threads', post.platform,
            'Platform must match the Ken_Social_Media_Post__c picklist value');
        Assert.areEqual('Caption for 111', post.body, 'text becomes the card body');
        Assert.areEqual(TH_IMG, post.sourceImageUrl, 'media_url is the image to rehost');
        Assert.areEqual('https://www.threads.net/@kenversealumni/post/111', post.postUrl,
            'Threads returns its own permalink, so no URL has to be built');
        Assert.areEqual(DateTime.newInstanceGmt(2026, 8, 13, 10, 0, 0), post.postedAt,
            'timestamp should normalise to the same GMT instant');
    }

    @IsTest
    static void threadsKeepsCarouselAlbums() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            threadsRow('222', 'CAROUSEL_ALBUM', TH_IMG)
        }));

        Assert.areEqual(1, fetchWith('Threads', threadsConfig(true, 'token'), mock).size(),
            'A carousel album is usable as a single-image card');
    }

    @IsTest
    static void threadsDropsRepostsOfOtherPeoplesPosts() {
        // The important one. A REPOST_FACADE is SOMEONE ELSE'S post on our
        // timeline, so letting it through would show a stranger's photo as though
        // the institute had posted it - the same hazard as an X retweet or a
        // Facebook visitor post.
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            threadsRow('333', 'REPOST_FACADE', TH_IMG)
        }));

        Assert.isTrue(fetchWith('Threads', threadsConfig(true, 'token'), mock).isEmpty(),
            'A repost is not our content and must never reach the alumni band');
    }

    @IsTest
    static void threadsDropsTextVideoAndAudioPosts() {
        // TEXT_POST also covers GIFs and polls, so all three arrive under types
        // that carry nothing renderable.
        //
        // The loop calls the service directly rather than through fetchWith,
        // because Test.startTest can only be called once per test method - the
        // helper would throw "Testing already started" on the second pass.
        KenSocialSync.overrides.put('Threads', threadsConfig(true, 'token'));

        Test.startTest();
        for (String type : new List<String>{ 'TEXT_POST', 'VIDEO', 'AUDIO' }) {
            Test.setMock(HttpCalloutMock.class, new ApiMock(200,
                dataBody(new List<Map<String, Object>>{ threadsRow('444', type, TH_IMG) })));

            Assert.isTrue(KenSocialSync.fetchRecent('Threads').isEmpty(),
                type + ' must not ship as a photo card');
        }
        Test.stopTest();
    }

    @IsTest
    static void threadsDropsPostsWithNoImage() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            threadsRow('555', 'IMAGE', null)
        }));

        Assert.isTrue(fetchWith('Threads', threadsConfig(true, 'token'), mock).isEmpty(),
            'An IMAGE post with no media_url has nothing to render');
    }

    @IsTest
    static void threadsRequestsTheOwnTimelineOnTheThreadsHost() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));

        fetchWith('Threads', threadsConfig(true, 'tok en'), mock);

        Assert.isTrue(mock.requestedEndpoint.startsWith('callout:'),
            'Threads is addressed through its own Named Credential');
        Assert.isTrue(mock.requestedEndpoint.contains('/' + TH_USER_ID + '/threads'),
            'Threads is addressed by its own numeric user id, with no Facebook Page involved');
        Assert.isFalse(mock.requestedEndpoint.contains('access_token'),
            'The credential is supplied by the Named Credential header, never in the URL');
    }

    @IsTest
    static void threadsHonoursTheOrgWideFetchLimit() {
        KenSocialSync.fetchLimitOverride = 11;
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));

        fetchWith('Threads', threadsConfig(true, 'token'), mock);

        Assert.isTrue(mock.requestedEndpoint.contains('limit=11'),
            'Threads must use the same org-wide Social Fetch Limit as every other platform');
    }

    @IsTest
    static void threadsReturnsEmptyWhenSwitchedOff() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>{
            threadsRow('666', 'IMAGE', TH_IMG)
        }));

        Assert.isTrue(fetchWith('Threads', threadsConfig(false, 'token'), mock).isEmpty(),
            'Is_Active__c false must stop the platform entirely');
        Assert.isNull(mock.requestedEndpoint, 'A dormant platform should not call out at all');
    }

    @IsTest
    static void threadsReturnsEmptyWhenTokenMissing() {
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));

        Assert.isTrue(fetchWith('Threads', noConnection(threadsConfig(true, null)), mock).isEmpty(),
            'No token means nothing to fetch');
        Assert.isNull(mock.requestedEndpoint, 'An unconfigured platform should not call out');
    }

    @IsTest
    static void threadsReturnsEmptyOnApiError() {
        ApiMock mock = new ApiMock(200,
            '{"error":{"message":"Invalid OAuth access token","code":190}}');

        Assert.isTrue(fetchWith('Threads', threadsConfig(true, 'token'), mock).isEmpty(),
            'Meta hosts answer some failures with HTTP 200 and an error body');
    }

    @IsTest
    static void threadsReturnsEmptyOnHttpFailure() {
        ApiMock mock = new ApiMock(500, 'Internal Server Error');

        Assert.isTrue(fetchWith('Threads', threadsConfig(true, 'token'), mock).isEmpty(),
            'One platform failing must not throw at the sync service');
    }

    // ═════════════════ platform routing itself ═════════════════

    @IsTest
    static void anUnconfiguredPlatformFetchesNothingAndDoesNotThrow() {
        // A typo'd platform name has no config record, so it stops at the isUsable
        // guard - the same path a dormant platform takes.
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<KenSocialSync.FetchedPost> posts =
            KenSocialSync.fetchRecent('Myspace');
        Test.stopTest();

        Assert.isTrue(posts.isEmpty(), 'An unknown platform must fetch nothing');
        Assert.isNull(mock.requestedEndpoint,
            'and must not call out, since there is no endpoint to call');
    }

    @IsTest
    static void aConfiguredButUnroutablePlatformFetchesNothingAndDoesNotThrow() {
        // The genuinely dangerous case, and the one the isUsable guard does NOT
        // catch: a healthy-looking config record whose DeveloperName matches no
        // branch of buildEndpoint. It must log and exit rather than throw, because
        // a thrown exception here would break the whole chain.
        ApiMock mock = new ApiMock(200, dataBody(new List<Map<String, Object>>()));
        Ken_Alm_Integration_Settings__mdt orphan = usable();
        orphan.Service__c = 'Myspace';
        stub(orphan);

        List<KenSocialSync.FetchedPost> posts = fetchWith('Myspace', orphan, mock);

        Assert.isTrue(posts.isEmpty(),
            'A config record with no matching endpoint must fetch nothing');
        Assert.isNull(mock.requestedEndpoint,
            'and must not call out, since buildEndpoint returned null');
    }

    // ═════════════════════════ LinkedIn ═════════════════════════

    /*
     * LinkedIn gets a section of its own because it shares no request shape, no
     * response shape and no authentication model with the other four - see the
     * divergence list in KenSocialSync. Every test below pins one of those
     * differences, since each is a place the platform can fail alone while the
     * band keeps rendering and nobody notices.
     */

    private static final String LI_ORG_ID    = '18726543';
    private static final String LI_POST_URN  = 'urn:li:share:7231234567890123456';
    private static final String LI_IMAGE_URN = 'urn:li:image:D4D22AQHxKenAlumni';
    private static final String LI_CREDENTIAL = 'Ken_LinkedIn_Social';
    private static final Long   LI_PUBLISHED_AT = 1786000000000L;
    private static final String LI_IMAGE_URL =
        'https://media.licdn.com/dms/image/v2/D4D22AQ/feedshare-shrink_2048/x.jpg?e=1&v=beta&t=sig';

    /**
     * Answers the timeline and the image batch separately, and remembers what each
     * was asked for.
     *
     * Counting the image callouts is the point of the class rather than a detail:
     * resolving images is a SECOND request no other platform makes, so "was it
     * made at all" is the assertion that catches a post being dropped late instead
     * of early.
     */
    private class LinkedInMock implements HttpCalloutMock {
        private String timelineBody;
        private String imagesBody;

        private String timelineEndpoint;
        private String imagesEndpoint;
        private String authorizationHeader;
        private String versionHeader;
        private String restliHeader;
        private Integer imageCallouts = 0;

        private LinkedInMock(String timelineBody, String imagesBody) {
            this.timelineBody = timelineBody;
            this.imagesBody = imagesBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            if (req.getEndpoint().contains('/rest/images')) {
                imagesEndpoint = req.getEndpoint();
                imageCallouts++;
                res.setBody(imagesBody == null
                    ? imageResponse(req.getEndpoint())
                    : imagesBody);
                return res;
            }

            timelineEndpoint = req.getEndpoint();
            authorizationHeader = req.getHeader('Authorization');
            versionHeader = req.getHeader('LinkedIn-Version');
            restliHeader = req.getHeader('X-Restli-Protocol-Version');
            res.setBody(timelineBody);
            return res;
        }
    }

    /** The production shape: a Named Credential and deliberately no stored token. */
    private static Ken_Alm_Integration_Settings__mdt linkedInConfig() {
        return new Ken_Alm_Integration_Settings__mdt(
            Service__c         = 'LinkedIn',
            Is_Active__c        = true,
            Account_Id__c       = LI_ORG_ID,
            Connection__c = LI_CREDENTIAL,
            API_Version__c      = '202508'
        );
    }

    /** An `elements`-wrapped body - the Rest.li envelope, not Meta's `data`. */
    private static String elementsBody(List<Map<String, Object>> rows) {
        return JSON.serialize(new Map<String, Object>{ 'elements' => rows });
    }

    /** One published single-image post: the shape a usable card is built from. */
    private static Map<String, Object> linkedInRow() {
        return new Map<String, Object>{
            'id'             => LI_POST_URN,
            'commentary'     => 'Convocation 2026',
            'lifecycleState' => 'PUBLISHED',
            'publishedAt'    => LI_PUBLISHED_AT,
            'content'        => new Map<String, Object>{
                'media' => new Map<String, Object>{ 'id' => LI_IMAGE_URN }
            }
        };
    }

    /**
     * The /rest/images answer for ONE image.
     *
     * Keyed off the endpoint rather than returning a constant, so a test can prove
     * WHICH urn was requested - otherwise the carousel test would pass even if the
     * mapper had picked the second image.
     */
    private static String imageResponse(String endpoint) {
        String wanted = EncodingUtil.urlEncode(LI_IMAGE_URN, 'UTF-8');
        return JSON.serialize(new Map<String, Object>{
            'downloadUrl' => endpoint.contains(wanted)
                ? LI_IMAGE_URL
                : 'https://media.licdn.com/dms/image/SOMEOTHERIMAGE.jpg'
        });
    }

    private static LinkedInMock mockReturning(Map<String, Object> row) {
        return new LinkedInMock(
            elementsBody(new List<Map<String, Object>>{ row }),
            null
        );
    }

    private static List<KenSocialSync.FetchedPost> fetchLinkedIn(
        Ken_Alm_Integration_Settings__mdt config,
        LinkedInMock mock
    ) {
        KenSocialSync.overrides.put('LinkedIn', config);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<KenSocialSync.FetchedPost> posts = KenSocialSync.fetchRecent('LinkedIn');
        Test.stopTest();
        return posts;
    }

    @IsTest
    static void aPublishedLinkedInPostBecomesACard() {
        LinkedInMock mock = mockReturning(linkedInRow());

        List<KenSocialSync.FetchedPost> posts = fetchLinkedIn(linkedInConfig(), mock);

        Assert.areEqual(1, posts.size(),
            'A published, single-image post is renderable and must survive both callouts');

        KenSocialSync.FetchedPost post = posts[0];
        Assert.areEqual('LinkedIn:' + LI_POST_URN, post.externalId,
            'The external id is platform-prefixed, so it cannot collide with another platform');
        Assert.areEqual('Convocation 2026', post.body,
            'commentary carries the text - LinkedIn has no caption, message or text field');
        Assert.areEqual(LI_IMAGE_URL, post.sourceImageUrl,
            'The image URL comes from the SECOND callout; the post itself carried only a URN');
        Assert.areEqual(
            'https://www.linkedin.com/feed/update/' + LI_POST_URN + '/',
            post.postUrl,
            'The permalink is built from the URN, since /rest/posts returns none');
        Assert.areEqual(DateTime.newInstance(LI_PUBLISHED_AT), post.postedAt,
            'publishedAt is epoch milliseconds, not the ISO string every other platform sends');
    }

    @IsTest
    static void aNamedCredentialAddressesTheCallAndSuppliesItsOwnAuthorization() {
        LinkedInMock mock = mockReturning(linkedInRow());

        fetchLinkedIn(linkedInConfig(), mock);

        Assert.isTrue(
            mock.timelineEndpoint.startsWith('callout:' + LI_CREDENTIAL + '/rest/posts'),
            'A configured Named Credential names the host, so the endpoint is a callout: URL');
        Assert.areEqual('Bearer {!$Credential.Password}', mock.authorizationHeader,
            'The header carries the credential merge field, so the platform resolves the '
            + 'token and no secret is built in Apex');
        Assert.areEqual('202508', mock.versionHeader,
            'LinkedIn-Version comes from API_Version__c; a versionless /rest request is 426');
        Assert.areEqual('2.0.0', mock.restliHeader,
            'LinkedIn requires the Rest.li version on every /rest call');
    }

    @IsTest
    static void theAuthorIsSentAsAnEncodedOrganizationUrn() {
        LinkedInMock mock = mockReturning(linkedInRow());

        fetchLinkedIn(linkedInConfig(), mock);

        Assert.isTrue(
            mock.timelineEndpoint.contains('author=urn%3Ali%3Aorganization%3A' + LI_ORG_ID),
            'The author is a URN and its colons must be percent encoded, or the finder 400s');
    }

    @IsTest
    static void anAccountIdPastedAsAFullUrnIsNotDoublePrefixed() {
        // LinkedIn's own documentation shows both forms, so an admin pasting either
        // is not making a mistake.
        Ken_Alm_Integration_Settings__mdt config = linkedInConfig();
        config.Account_Id__c = 'urn:li:organization:' + LI_ORG_ID;

        LinkedInMock mock = mockReturning(linkedInRow());
        fetchLinkedIn(config, mock);

        Assert.isTrue(
            mock.timelineEndpoint.contains('author=urn%3Ali%3Aorganization%3A' + LI_ORG_ID),
            'A full URN must be used as-is');
        Assert.isFalse(mock.timelineEndpoint.contains('organization%3Aurn'),
            'and must not be prefixed a second time');
    }

    @IsTest
    static void aResharedPostIsRejected() {
        Map<String, Object> reshare = linkedInRow();
        reshare.put('reshareContext',
            new Map<String, Object>{ 'parent' => 'urn:li:share:999' });

        List<KenSocialSync.FetchedPost> posts =
            fetchLinkedIn(linkedInConfig(), mockReturning(reshare));

        Assert.isTrue(posts.isEmpty(),
            'A reshare is SOMEONE ELSE\'S post on our timeline. Letting it through would put '
            + 'a stranger\'s photo on the alumni band under the institute\'s name - the same '
            + 'hazard as a Threads REPOST_FACADE, an X retweet and a Facebook visitor post');
    }

    @IsTest
    static void aDraftPostIsRejected() {
        Map<String, Object> draft = linkedInRow();
        draft.put('lifecycleState', 'DRAFT');

        List<KenSocialSync.FetchedPost> posts =
            fetchLinkedIn(linkedInConfig(), mockReturning(draft));

        Assert.isTrue(posts.isEmpty(),
            'A draft is returned to us because the token is a page admin\'s, but not to a '
            + 'visitor - the card would link to a 404 for everyone who clicked it');
    }

    @IsTest
    static void aPostWithNoLifecycleStateIsTreatedAsPublished() {
        Map<String, Object> row = linkedInRow();
        row.remove('lifecycleState');

        List<KenSocialSync.FetchedPost> posts =
            fetchLinkedIn(linkedInConfig(), mockReturning(row));

        Assert.areEqual(1, posts.size(),
            'Older API versions omit the field on live posts, so absence must not be read '
            + 'as "not published" and empty the band on a version bump');
    }

    @IsTest
    static void aVideoPostIsDroppedWithoutAskingTheImageEndpointAboutIt() {
        Map<String, Object> video = linkedInRow();
        video.put('content', new Map<String, Object>{
            'media' => new Map<String, Object>{ 'id' => 'urn:li:video:D4D10AQKenVideo' }
        });

        LinkedInMock mock = mockReturning(video);
        List<KenSocialSync.FetchedPost> posts = fetchLinkedIn(linkedInConfig(), mock);

        Assert.isTrue(posts.isEmpty(),
            'A video carries content.media.id exactly as an image does - only the URN type '
            + 'separates them, and a video card would look like a photo and play nothing');
        Assert.areEqual(0, mock.imageCallouts,
            'and the prefix already says so, so no callout should be spent finding out');
    }

    @IsTest
    static void aCarouselUsesItsFirstImage() {
        Map<String, Object> carousel = linkedInRow();
        carousel.put('content', new Map<String, Object>{
            'multiImage' => new Map<String, Object>{
                'images' => new List<Object>{
                    new Map<String, Object>{ 'id' => LI_IMAGE_URN },
                    new Map<String, Object>{ 'id' => 'urn:li:image:SECONDIMAGE' }
                }
            }
        });

        List<KenSocialSync.FetchedPost> posts =
            fetchLinkedIn(linkedInConfig(), mockReturning(carousel));

        Assert.areEqual(1, posts.size(), 'A carousel is usable as a single-image card');
        Assert.areEqual(LI_IMAGE_URL, posts[0].sourceImageUrl,
            'The band shows one image per card, so the first wins - as it does for an '
            + 'Instagram album and an X post carrying four photos');
    }

    @IsTest
    static void anArticleShareIsDroppedBecauseItsThumbnailIsNotLinkedInHosted() {
        Map<String, Object> article = linkedInRow();
        article.put('content', new Map<String, Object>{
            'article' => new Map<String, Object>{
                'source'    => 'https://example.edu/news',
                'thumbnail' => 'urn:li:image:ARTICLETHUMB'
            }
        });

        LinkedInMock mock = mockReturning(article);
        List<KenSocialSync.FetchedPost> posts = fetchLinkedIn(linkedInConfig(), mock);

        Assert.isTrue(posts.isEmpty(), 'Only media and multiImage carry a usable image');
        Assert.areEqual(0, mock.imageCallouts, 'and neither shape was present to resolve');
    }

    @IsTest
    static void anExpiredTokenYieldsNothingRatherThanALookAlikeEmptyFeed() {
        String errorBody = JSON.serialize(new Map<String, Object>{
            'status'           => 401,
            'serviceErrorCode' => 65600,
            'message'          => 'Invalid access token'
        });

        LinkedInMock mock = new LinkedInMock(errorBody, null);
        List<KenSocialSync.FetchedPost> posts = fetchLinkedIn(linkedInConfig(), mock);

        Assert.isTrue(posts.isEmpty(),
            'LinkedIn reports failure under serviceErrorCode and status, never `error`. Read '
            + 'by the default branch a 401 would look like a clean response carrying no rows, '
            + 'and the band would go quietly empty when the credential lapsed');
        Assert.areEqual(0, mock.imageCallouts,
            'and an error body must not lead to an image batch');
    }

    @IsTest
    static void aTextOnlyTimelineSpendsNoCalloutResolvingImages() {
        Map<String, Object> textOnly = linkedInRow();
        textOnly.remove('content');

        LinkedInMock mock = mockReturning(textOnly);
        List<KenSocialSync.FetchedPost> posts = fetchLinkedIn(linkedInConfig(), mock);

        Assert.isTrue(posts.isEmpty(), 'A post with no image cannot become a card');
        Assert.areEqual(0, mock.imageCallouts,
            'and a timeline with nothing to resolve must not spend a request learning that');
    }

    @IsTest
    static void eachImageIsResolvedByItsOwnRequestNotABatch() {
        LinkedInMock mock = mockReturning(linkedInRow());

        fetchLinkedIn(linkedInConfig(), mock);

        Assert.areEqual(1, mock.imageCallouts, 'One request for this post\'s one image');
        Assert.isTrue(mock.imagesEndpoint.contains('/rest/images/urn%3Ali%3Aimage%3A'),
            'The URN is a path segment now, so its colons must be percent encoded');
        Assert.isFalse(mock.imagesEndpoint.contains('ids=List'),
            'NOT the batch form. It is throttled as a separate resource and answers 429 '
            + 'APPLICATION DAY limit while the single-id form answers 200 for the same '
            + 'URN in the same second');
    }

    @IsTest
    static void anUnresolvableImageDropsItsCardWithoutThrowing() {
        LinkedInMock mock = new LinkedInMock(
            elementsBody(new List<Map<String, Object>>{ linkedInRow() }),
            JSON.serialize(new Map<String, Object>{ 'id' => LI_IMAGE_URN })
        );

        List<KenSocialSync.FetchedPost> posts = fetchLinkedIn(linkedInConfig(), mock);

        Assert.isTrue(posts.isEmpty(),
            'An unresolvable image drops its card. It must not throw: the sync walks the '
            + 'platforms in a chain, so LinkedIn failing would otherwise take the rest down');
    }

    @IsTest
    static void epochMillisIsReadWhicheverNumericTypeItDeserialisesAs() {
        // JSON.deserializeUntyped picks the narrowest type each number fits, so the
        // same field arrives as a different Apex type depending on the value. A
        // straight cast to Long would throw a TypeException on two of the three.
        DateTime expected = DateTime.newInstance(LI_PUBLISHED_AT);
        Decimal asDecimal = 1786000000000.0;
        Double asDouble = Double.valueOf('1786000000000');

        Assert.areEqual(expected, KenSocialSync.fromEpochMillis(LI_PUBLISHED_AT), 'Long');
        Assert.areEqual(expected, KenSocialSync.fromEpochMillis(asDecimal), 'Decimal');
        Assert.areEqual(expected, KenSocialSync.fromEpochMillis(asDouble), 'Double');
        Assert.areEqual(DateTime.newInstance(1000L), KenSocialSync.fromEpochMillis(1000),
            'Integer, which is what a small number deserialises as');
        Assert.isNull(KenSocialSync.fromEpochMillis('1786000000000'),
            'A string is not a LinkedIn timestamp and must return null rather than throw');
        Assert.isNull(KenSocialSync.fromEpochMillis(null), 'and neither is a missing field');
    }

    @IsTest
    static void aNamedCredentialAloneMakesLinkedInUsable() {
        stub(linkedInConfig());

        Assert.isTrue(KenSocialSync.isUsable('LinkedIn'),
            'With a Named Credential there IS no stored token - Salesforce holds it - so '
            + 'insisting on a stored token would leave LinkedIn permanently dormant');
    }

    @IsTest
    static void linkedInWithNeitherCredentialIsDormant() {
        Ken_Alm_Integration_Settings__mdt config = linkedInConfig();
        config.Connection__c = null;

        stub(config);

        Assert.isFalse(KenSocialSync.isUsable('LinkedIn'),
            'Neither a credential nor a token is unconfigured, not a failed callout');
    }

    @IsTest
    static void aBlankApiVersionStillSendsAVersionHeader() {
        Ken_Alm_Integration_Settings__mdt config = linkedInConfig();
        config.API_Version__c = null;

        LinkedInMock mock = mockReturning(linkedInRow());
        fetchLinkedIn(config, mock);

        Assert.isNotNull(mock.versionHeader,
            'LinkedIn answers a versionless /rest request with 426, so a blank field must '
            + 'fall back rather than become an empty header and take the platform down');
    }

    @IsTest
    static void aMetaStyleVersionPrefixIsStripped() {
        Ken_Alm_Integration_Settings__mdt config = linkedInConfig();
        config.API_Version__c = 'v202508';

        LinkedInMock mock = mockReturning(linkedInRow());
        fetchLinkedIn(config, mock);

        Assert.areEqual('202508', mock.versionHeader,
            'The other four platforms all use a v-prefix, so typing one here is a habit '
            + 'worth absorbing rather than answering with a 426');
    }

    @IsTest
    static void linkedInMarkupIsTurnedIntoReadableText() {
        // `commentary` is LinkedIn's own markup, not plain text. Rendered raw, a
        // card reads "Today at @[TsquaredC](urn:li:organization:88395943) HQ".
        String raw = 'Today at @[TsquaredC](urn:li:organization:88395943) HQ we met '
            + '@[Vijeta Soni](urn:li:person:JEjDwcO5Hn).<br><br>It&#39;s a wrap '
            + '{hashtag|\\#|Innovation} {hashtag|\\#|AI}';

        String clean = KenSocialSync.cleanLinkedInText(raw);

        Assert.isTrue(clean.contains('Today at TsquaredC HQ'),
            'A mention keeps the display name and loses the URN');
        Assert.isTrue(clean.contains('we met Vijeta Soni.'),
            'including person mentions');
        Assert.isTrue(clean.contains('#Innovation') && clean.contains('#AI'),
            'a hashtag becomes a plain #tag');
        Assert.isFalse(clean.contains('urn:li:'), 'no URN survives');
        Assert.isFalse(clean.contains('hashtag|'), 'and no hashtag wrapper');
        Assert.isFalse(clean.contains('<br>'), '<br> becomes a real line break');
        Assert.isTrue(clean.contains('It\'s a wrap'),
            'and &#39; is decoded back to an apostrophe');
    }

    @IsTest
    static void cleaningEmptyTextIsSafe() {
        Assert.isNull(KenSocialSync.cleanLinkedInText(null),
            'A post with no commentary is normal - an image-only post has none');
        Assert.areEqual('', KenSocialSync.cleanLinkedInText(''), 'and so is empty text');
    }

    @IsTest
    static void anOverlongBodyIsAbbreviatedNotDropped() {
        // Body__c stops at 2000; LinkedIn allows 3000 and its pages use it. An
        // untrimmed body fails the whole UPSERT with STRING_TOO_LONG, which takes
        // every other post in that batch down with it.
        String huge = 'x'.repeat(2500);

        String fitted = KenSocialSync.fitBody(huge);

        Assert.areEqual(2000, fitted.length(), 'It must fit the field exactly');
        Assert.isTrue(fitted.endsWith('...'),
            'and end in an ellipsis, so a shortened card reads as shortened rather '
            + 'than as a sentence that stops mid-word');
    }

    @IsTest
    static void aBodyThatAlreadyFitsIsUntouched() {
        String ok = 'Convocation 2026';

        Assert.areEqual(ok, KenSocialSync.fitBody(ok), 'Nothing to trim, nothing changed');
        Assert.isNull(KenSocialSync.fitBody(null), 'and a blank body stays blank');
    }

    // ═══════════════ reading the live cadence ═══════════════

    /*
     * These guard the one way the schedule can change without anyone deciding to
     * change it: a job recreated at DEFAULT_CRON instead of at whatever it was
     * actually running. The org runs weekly and the constant says monthly, so the
     * mistake retunes the band by 4x and shows up only as staleness.
     */

    @IsTest
    static void currentCronIsNullWhenNothingIsScheduled() {
        useTestJobName();

        Assert.isNull(KenSocialSync.currentCron(),
            'No job means no cadence to report - and null is what tells rescheduleSame() '
            + 'there is nothing to restart');
    }

    @IsTest
    static void currentCronReadsWhatTheJobIsActuallyRunning() {
        useTestJobName();

        Test.startTest();
        KenSocialSync.schedule('0 0 0 ? * SUN');
        Test.stopTest();

        Assert.areEqual('0 0 0 ? * SUN', KenSocialSync.currentCron(),
            'The answer must come from the CronTrigger, not from DEFAULT_CRON - the two '
            + 'deliberately differ in the real org');
    }

    @IsTest
    static void rescheduleSameKeepsTheCadenceItFound() {
        useTestJobName();

        Test.startTest();
        KenSocialSync.schedule('0 0 0 ? * SUN');
        Id restarted = KenSocialSync.rescheduleSame();
        Test.stopTest();

        Assert.isNotNull(restarted, 'A running job is restartable');
        Assert.areEqual('0 0 0 ? * SUN', scheduledCron(restarted),
            'Recreating the job must not move it. reschedule(DEFAULT_CRON) here would turn a '
            + 'weekly sync into a monthly one silently');
    }

    @IsTest
    static void rescheduleSameDoesNothingWhenNoJobExists() {
        useTestJobName();

        Test.startTest();
        Id restarted = KenSocialSync.rescheduleSame();
        Test.stopTest();

        Assert.isNull(restarted,
            'With no job to read a cadence from, inventing one from the constant is exactly '
            + 'the guess this method exists to avoid');
        Assert.isNull(KenSocialSync.currentCron(), 'and nothing should have been scheduled');
    }

    @IsTest
    static void aRejectedRescheduleLeavesTheRunningJobAlone() {
        useTestJobName();

        Test.startTest();
        KenSocialSync.schedule('0 0 0 ? * SUN');
        Boolean threw = false;
        try {
            KenSocialSync.reschedule('   ');
        } catch (IllegalArgumentException ex) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A blank cadence is rejected here too');
        Assert.areEqual('0 0 0 ? * SUN', KenSocialSync.currentCron(),
            'and the job must SURVIVE. reschedule aborts before it schedules, so validating '
            + 'late would answer bad input by leaving the org with no sync at all');
    }
}