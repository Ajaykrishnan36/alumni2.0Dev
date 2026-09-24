/**
 * @description The entire social media feed behind the landing page's "From the
 *              Alumni Community" band: what to sync, when to sync it, how to
 *              reach each platform's API, and how to store what comes back.
 *
 *              ONE class by deliberate consolidation. This began as eleven -
 *              four per-platform fetchers, five per-platform settings readers, a
 *              sync service and a scheduler - and each split cost more than it
 *              explained. What survives here is the only division that Apex
 *              itself forces: the inner Runner, because a Schedulable class may
 *              not also be Queueable.
 *
 *              Read it in four parts, in the order a run happens:
 *                1. scheduling      - schedule/reschedule/unschedule, the cron
 *                2. the run         - Runner, one platform per transaction
 *                3. fetch           - the callouts, and what differs per platform
 *                4. save            - dedup, image rehosting, the upsert
 *
 *              The landing page does NOT read this class. It reads the stored
 *              records through KenLandingPageController, alongside the page's
 *              other content.
 *
 *              without sharing: this is a system sync, run from a scheduler or by
 *              an admin, and must write posts regardless of who triggered it.
 */
public without sharing class KenSocialSync implements Schedulable {

    /** Shown in Setup > Scheduled Jobs; also the key for unschedule(). */
    @TestVisible
    private static final String JOB_NAME = 'Ken Social Media Sync';

    /**
     * Lets a test schedule under its own name.
     *
     * Scheduled jobs are NOT isolated in Apex tests - System.schedule sees the
     * org's real CronTrigger rows and rejects a duplicate name. So once this
     * scheduler is genuinely scheduled in an org, every test that called
     * schedule() under the production name would fail with
     * "The Apex job named ... is already scheduled for execution", breaking
     * every subsequent deploy and CI run in an org where the feature is live.
     *
     * Scheduling under a distinct name also means a test's unschedule() can
     * never abort the org's real job.
     */
    @TestVisible
    private static String jobNameOverride;

    private static String jobName() {
        return jobNameOverride == null ? JOB_NAME : jobNameOverride;
    }

    /**
     * Every platform the sync knows about, newest-first order irrelevant since
     * the landing page re-sorts by Posted_At__c.
     *
     * A dormant platform costs nothing to include - the fetch reads
     * Is_Active__c and returns an empty list WITHOUT calling out - so this list
     * stays complete rather than tracking which credentials happen to be live.
     */
    @TestVisible
    private static final List<String> ALL_PLATFORMS = new List<String>{
        'Instagram', 'Facebook', 'LinkedIn', 'X', 'Threads'
    };

    // ═════════════════════════ 1. scheduling ═════════════════════════

    // ───────────────────────── scheduled entry ─────────────────────────

    /**
     * @description Wakes on the cron tick and starts a sync.
     *
     *              Hands off to a queued job rather than syncing inline: the
     *              chain needs one transaction per platform, and a Schedulable
     *              transaction cannot provide that.
     *
     *              The cron IS the cadence - there is no second gate in Apex
     *              deciding whether a tick counts. Set the cron to how often you
     *              actually want to sync and that is what happens, which means the
     *              schedule an admin reads in Setup > Scheduled Jobs is the whole
     *              truth rather than half of it.
     *
     *              A days-since-last-run gate used to sit here, letting a daily
     *              cron stand in for "every N days". It was removed deliberately:
     *              two places controlled one behaviour, and the cron on the job
     *              disagreed with the real cadence, which is worse than the
     *              scheduling limitation it worked around.
     *
     *              A Social_Sync_Last_Run__c stamp outlived that gate and was
     *              deleted on 2026-08-14. It was written here on every run and
     *              read by nothing, and "when did the feed last sync?" is already
     *              answered natively by CronTrigger.PreviousFireTime and
     *              TimesTriggered - so it bought a DML per run and no information.
     */
    public void execute(SchedulableContext context) {
        enqueueAll();
    }

    // ═══════════════════════════ 2. the run ═══════════════════════════

    /**
     * @description Starts a sync of every platform. The single entry point for
     *              the cron tick and for a manual run from anonymous Apex.
     *
     * @return the enqueued job id
     */
    public static Id enqueueAll() {
        return System.enqueueJob(new Runner(ALL_PLATFORMS.clone()));
    }

    /**
     * @description One transaction's worth of syncing: does the head of its list,
     *              then queues a fresh Runner for the tail.
     *
     *              Inner rather than top-level because Apex will not let the outer
     *              Schedulable class carry Queueable too - see the class header.
     */
    public class Runner implements Queueable, Database.AllowsCallouts {

        /** What THIS instance still has to sync, head first. */
        private final List<String> platforms;

        @TestVisible
        private Runner(List<String> platforms) {
            this.platforms = platforms;
        }

        public void execute(QueueableContext context) {

            if (platforms == null || platforms.isEmpty()) {
                return;
            }

            List<String> remaining = platforms.clone();
            String platform = remaining.remove(0);

            syncOne(platform);

            // Test contexts allow only one level of chaining, so the guard is what
            // lets a test assert this execute's own work without the chain running
            // away. Production always chains.
            if (!remaining.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new Runner(remaining));
            }
        }
    }

    /**
     * @description Syncs one platform, swallowing any failure.
     *
     *              The SyncResult is written to the debug log because it is the
     *              only record a scheduled run leaves behind. Its counts are what
     *              distinguish the three states that all look identical from the
     *              landing page: nothing new (alreadyStored), nothing working
     *              (fetched 0 with a note), and images failing (imageFailed).
     *              Without it a dead credential shows up only as a band that
     *              quietly stopped getting newer.
     */
    @TestVisible
    private static void syncOne(String platform) {
        // Guarded rather than passed straight through: an unrecognised name would
        // otherwise reach KenSocialSync, find no config, and return an
        // empty run that looks identical to a dormant platform - hiding the typo.
        if (!ALL_PLATFORMS.contains(platform)) {
            System.debug(LoggingLevel.ERROR,
                'KenSocialSync: unknown platform ' + platform);
            return;
        }

        try {
            SyncResult result =
                sync(platform);
            System.debug(LoggingLevel.INFO,
                'KenSocialSync: ' + JSON.serialize(result));
        } catch (Exception ex) {
            // Reached only if sync() itself fails outside its own guards - an
            // unexpected DML or governor problem. The chain must survive it.
            System.debug(LoggingLevel.ERROR,
                'KenSocialSync: ' + platform + ' failed: '
                + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }

    // ───────────────────── scheduling, the cron ─────────────────────

    /**
     * @description Schedules the sync at a cron expression of your choosing.
     *
     *              The cadence is NOT stored in a custom setting. It used to be,
     *              in Ken_Alm_Org_Parameters__c.Social_Sync_Cron__c, and that field
     *              was deleted on 2026-08-14 because it earned nothing: the live
     *              cadence already lives on the CronTrigger, editing the setting
     *              never moved the running job, and applying a change meant
     *              running reschedule() from anonymous Apex anyway - at which
     *              point the admin may as well pass the expression here. Two
     *              copies of one value that could silently disagree, for no gain.
     *
     *              There is NO default. This class holds no cron of its own, so
     *              the cadence can only ever come from the running CronTrigger or
     *              from the expression handed in here - never from a constant that
     *              might disagree with what the org is actually doing. A blank
     *              value is therefore rejected rather than quietly filled in: a
     *              fallback would apply a cadence nobody asked for and leave the
     *              caller believing a schedule they do not have.
     *
     *              A malformed expression throws too, from System.schedule itself.
     *              Failing loudly is the kinder answer for both.
     *
     *              Trimmed, because an expression pasted out of documentation or a
     *              spreadsheet routinely carries whitespace System.schedule rejects.
     *
     * @param cronExpression a Salesforce cron expression, e.g. '0 0 2 ? * MON'
     * @return the CronTrigger id
     * @throws IllegalArgumentException when no expression is supplied
     */
    public static Id schedule(String cronExpression) {
        if (String.isBlank(cronExpression)) {
            throw new IllegalArgumentException(
                'KenSocialSync.schedule needs a cron expression - there is no default. '
                + 'Read the running cadence with currentCron(), or use rescheduleSame() '
                + 'to restart the job without moving it.');
        }
        return System.schedule(jobName(), cronExpression.trim(), new KenSocialSync());
    }

    /**
     * @description Moves the running job to a new cadence.
     *
     *              Unschedule-then-schedule because System.schedule throws on a
     *              duplicate job name and a CronTrigger's expression cannot be
     *              edited in place.
     *
     * @param cronExpression the new cadence, e.g. '0 0 2 ? * MON'
     * @return the CronTrigger id of the new job
     */
    public static Id reschedule(String cronExpression) {
        // Validated BEFORE the abort. schedule() rejects a blank expression, and
        // reaching that check after unschedule() had already run would leave the
        // org with no scheduled job at all - a worse outcome than the bad input.
        if (String.isBlank(cronExpression)) {
            throw new IllegalArgumentException(
                'KenSocialSync.reschedule needs a cron expression - there is no default. '
                + 'The existing job has been left running. Use rescheduleSame() to restart '
                + 'it without moving the cadence.');
        }
        unschedule();
        return schedule(cronExpression);
    }

    /**
     * @description The cadence the job is ACTUALLY running at, read from its
     *              CronTrigger.
     *
     *              The running schedule is the only source of truth for cadence,
     *              and since this class no longer carries a cron of its own it is
     *              the only source there is. Only the job can answer "what is it
     *              set to?".
     *
     *              Worth calling BEFORE unschedule() ahead of a deploy: aborting the
     *              job deletes the row, and with it the only record of the cadence.
     *              Retyping it from memory afterwards is how a weekly job silently
     *              becomes a monthly one.
     *
     * @return the cron expression, or null when the job is not scheduled
     */
    public static String currentCron() {
        // A SOQL bind variable cannot be a method call, hence the local.
        String name = jobName();

        List<CronTrigger> jobs = [
            SELECT CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = :name
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0].CronExpression;
    }

    /**
     * @description Restarts the job at the cadence it is already running at.
     *
     *              For when the job must be recreated but the schedule must not
     *              move. Retyping the expression from memory is how a weekly job
     *              silently becomes something else, and that is invisible until
     *              someone notices the band has gone stale weeks later.
     *
     *              The cron is read BEFORE the abort, because abortJob deletes the
     *              CronTrigger. Doing it the other way round reads null and reveals
     *              nothing.
     *
     *              This does NOT survive a class deploy - the transaction ends
     *              between unscheduling and redeploying - so for that case print
     *              currentCron() first and pass it back to schedule() by hand.
     *
     * @return the new CronTrigger id, or null when there was no job to restart
     */
    public static Id rescheduleSame() {
        String cron = currentCron();
        if (String.isBlank(cron)) {
            return null;
        }
        unschedule();
        return schedule(cron);
    }

    /**
     * @description Removes the scheduled job, if it exists.
     *
     *              Also needed before deploying any class the sync touches:
     *              Salesforce refuses to deploy a class that a pending
     *              schedulable job depends on, unless the org has enabled
     *              "Allow deployments of components when corresponding Apex jobs
     *              are pending or in progress" in Deployment Settings.
     *
     * @return true if a job was found and aborted
     */
    public static Boolean unschedule() {
        // A SOQL bind variable cannot be a method call, hence the local.
        String name = jobName();

        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :name
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (jobs.isEmpty()) {
            return false;
        }
        System.abortJob(jobs[0].Id);
        return true;
    }

    // ═══════════════════════════ 4. save ═══════════════════════════

    /**
     * Apex heap is 6MB sync / 12MB async and a heap LimitException CANNOT be
     * caught - it kills the whole job. Base64 encoding costs another ~1.33x on
     * top of the blob, so an uncapped download is a real risk. Instagram images
     * are typically well under 1MB, so this ceiling should never be reached; it
     * exists so that one oversized image degrades to "no card" instead of
     * destroying the run.
     */
    @TestVisible private static final Integer MAX_IMAGE_BYTES = 4 * 1024 * 1024;

    /** Fallback when the response carries no usable Content-Type. */
    @TestVisible private static final String DEFAULT_IMAGE_EXTENSION = 'jpg';

    /** Used when Ken_Alm_Org_Parameters__c has no usable Social Fetch Limit. */
    @TestVisible private static final Integer DEFAULT_FETCH_LIMIT = 3;

    /**
     * A run costs one callout to fetch plus one image download per post, and
     * Apex allows 100 callouts per transaction. An admin typing 100 into the
     * setting would therefore abort the entire sync with an uncatchable limit
     * exception, so the value is clamped rather than trusted. 25 is far more
     * than the three-card band can display while leaving ample headroom.
     */
    @TestVisible private static final Integer MAX_FETCH_LIMIT = 25;

    /** Lets a test choose a limit without writing to the org's parameters. */
    @TestVisible private static Integer fetchLimitOverride;

    /**
     * @description How many recent posts to ask a platform for, shared by every
     *              fetcher.
     *
     *              Deliberately ONE value for all platforms, held on
     *              Ken_Alm_Org_Parameters__c alongside the portal's other
     *              admin-tunable numbers, rather than a Fetch_Limit__c on each
     *              platform's own settings. Three separate fields invited three
     *              different values for a band that shows three cards in total,
     *              and meant checking three places to answer "how many do we
     *              pull?".
     *
     *              getOrgDefaults() costs no SOQL query and needs no object
     *              permission, so this is safe to call from a scheduled job and
     *              from the guest-facing landing page alike.
     *
     * @return a sane post count, never null and never outside 1..25
     */
    public static Integer fetchLimit() {
        if (fetchLimitOverride != null) {
            return fetchLimitOverride;
        }

        Decimal configured = Ken_Alm_Org_Parameters__c.getOrgDefaults().Social_Fetch_Limit__c;
        if (configured == null || configured < 1) {
            return DEFAULT_FETCH_LIMIT;
        }
        return configured > MAX_FETCH_LIMIT
            ? MAX_FETCH_LIMIT
            : Integer.valueOf(configured);
    }

    /**
     * @description One post as the platform described it, before we have
     *              rehosted its image or saved anything.
     */
    public class FetchedPost {
        /** Platform-prefixed dedup key, e.g. "Instagram:17841400000000000". */
        public String externalId;
        /** Stamped onto the record; drives the card icon only. */
        public String platform;
        /** Caption, normalised from whatever the platform calls it. */
        public String body;
        /** The platform's OWN image URL - expires, never stored. */
        public String sourceImageUrl;
        /**
         * Public deep link to the post on the platform, for the card to open.
         * Unlike sourceImageUrl this is a permanent page and IS stored.
         */
        public String postUrl;
        /** Post time, already normalised to GMT. */
        public DateTime postedAt;
    }

    /**
     * @description What a run did, so a caller (or a log) can tell the
     *              difference between "nothing new" and "nothing worked".
     */
    public class SyncResult {
        @AuraEnabled public String platform;
        @AuraEnabled public Integer fetched = 0;
        @AuraEnabled public Integer alreadyStored = 0;
        @AuraEnabled public Integer imageFailed = 0;
        @AuraEnabled public Integer saved = 0;
        @AuraEnabled public List<String> notes = new List<String>();
    }

    /**
     * @description Fetches one platform's recent posts and stores the new ones.
     *
     *              Ordering is forced by two Apex rules working against each
     *              other: a callout cannot follow DML in the same transaction,
     *              and images must be downloaded before they can be saved. So
     *              every download happens first, then every insert.
     *
     * @param platform Ken_Alm_Integration_Settings__mdt DeveloperName, e.g. 'Instagram'
     * @return         counts describing the run
     */
    public static SyncResult sync(String platform) {
        SyncResult result = new SyncResult();
        result.platform = platform;

        // ---- 1. callout: ask the platform what it has ----
        List<FetchedPost> fetched;
        try {
            fetched = fetchRecent(platform);
        } catch (Exception ex) {
            result.notes.add('Fetch failed: ' + ex.getMessage());
            return result;
        }
        if (fetched == null || fetched.isEmpty()) {
            result.notes.add('Platform returned no usable posts.');
            return result;
        }
        result.fetched = fetched.size();

        // ---- 2. SOQL: drop anything already stored ----
        // Mandatory. The upsert on External_Post_Id__c would dedup the RECORDS
        // either way, so skipping this looks harmless - but every run would
        // re-download the same images and create fresh ContentVersions, quietly
        // filling file storage with duplicates while the page looks perfect.
        List<FetchedPost> fresh = withoutAlreadyStored(fetched);
        result.alreadyStored = fetched.size() - fresh.size();
        if (fresh.isEmpty()) {
            result.notes.add('All fetched posts were already stored.');
            return result;
        }

        // ---- 3. callouts: download every image BEFORE any DML ----
        Map<String, String> base64ByExternalId = new Map<String, String>();
        Map<String, String> extensionByExternalId = new Map<String, String>();
        for (FetchedPost post : fresh) {
            DownloadedImage image = downloadImage(post.sourceImageUrl);
            if (image == null) {
                result.imageFailed++;
                result.notes.add('Image download failed for ' + post.externalId);
                continue;
            }
            base64ByExternalId.put(post.externalId, image.base64Data);
            extensionByExternalId.put(post.externalId, image.extension);
        }
        if (base64ByExternalId.isEmpty()) {
            result.notes.add('No image could be downloaded; nothing saved.');
            return result;
        }

        // ---- 4. DML: rehost each image, then save the posts ----
        List<Ken_Social_Media_Post__c> toSave = new List<Ken_Social_Media_Post__c>();
        for (FetchedPost post : fresh) {
            String base64Data = base64ByExternalId.get(post.externalId);
            if (base64Data == null) {
                continue;
            }
            String publicUrl = rehost(post, base64Data, extensionByExternalId.get(post.externalId));
            if (publicUrl == null) {
                result.imageFailed++;
                result.notes.add('Could not publish image for ' + post.externalId);
                continue;
            }
            toSave.add(toRecord(post, publicUrl));
        }

        if (!toSave.isEmpty()) {
            if (!Schema.sObjectType.Ken_Social_Media_Post__c.isCreateable() || !Schema.sObjectType.Ken_Social_Media_Post__c.isUpdateable()) {
                throw new KenCrudException('Ken_Social_Media_Post__c is not upsertable by the current user.');
            }
            upsert toSave External_Post_Id__c;
            result.saved = toSave.size();
        }
        return result;
    }

    /**
     * @description Keeps only posts whose external id is not already on a
     *              record, so images are downloaded exactly once.
     */
    private static List<FetchedPost> withoutAlreadyStored(List<FetchedPost> posts) {
        Set<String> candidateIds = new Set<String>();
        for (FetchedPost post : posts) {
            if (String.isNotBlank(post.externalId)) {
                candidateIds.add(post.externalId);
            }
        }

        Set<String> stored = new Set<String>();
        for (Ken_Social_Media_Post__c existing : [
            SELECT External_Post_Id__c
            FROM Ken_Social_Media_Post__c
            WHERE External_Post_Id__c IN :candidateIds
        WITH SECURITY_ENFORCED
        ]) {
            stored.add(existing.External_Post_Id__c);
        }

        List<FetchedPost> fresh = new List<FetchedPost>();
        for (FetchedPost post : posts) {
            if (String.isNotBlank(post.externalId) && !stored.contains(post.externalId)) {
                fresh.add(post);
            }
        }
        return fresh;
    }

    /** An image we successfully downloaded, ready to hand to Salesforce. */
    private class DownloadedImage {
        String base64Data;
        String extension;
    }

    /**
     * @description Downloads an image and returns it base64 encoded.
     *
     *              Content-Length is checked before reading the body where the
     *              server provides it, and the actual size is checked again
     *              afterwards because that header is advisory. The blob is
     *              dropped as soon as it is encoded so both copies are never
     *              held at once.
     *
     * @param imageUrl the platform's own (expiring) image URL
     * @return         the encoded image, or null if it could not be fetched
     */
    private static DownloadedImage downloadImage(String imageUrl) {
        if (String.isBlank(imageUrl)) {
            return null;
        }
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(canonicalMediaHost(imageUrl));
            req.setMethod('GET');
            req.setTimeout(60000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                return null;
            }

            String declaredLength = res.getHeader('Content-Length');
            if (String.isNotBlank(declaredLength)
                    && Integer.valueOf(declaredLength) > MAX_IMAGE_BYTES) {
                return null;
            }

            Blob body = res.getBodyAsBlob();
            // Under ~100 bytes is an error page or a tracking pixel, not a photo.
            if (body == null || body.size() < 100 || body.size() > MAX_IMAGE_BYTES) {
                return null;
            }

            DownloadedImage image = new DownloadedImage();
            image.extension = extensionFor(res.getHeader('Content-Type'));
            image.base64Data = EncodingUtil.base64Encode(body);
            return image;
        } catch (Exception ex) {
            // A single unreachable image must not end the run.
            return null;
        }
    }

    /**
     * @description Rewrites a Meta CDN host to the one canonical host that
     *              Remote Site Settings authorise.
     *
     *              Meta serves media from rotating, region-based hosts
     *              (scontent-nrt1-2, scontent-bom1-1, scontent-lhr8-1, ...) and
     *              picks a different one per response. Remote Site Settings
     *              match an exact host and reject wildcards - "Unable to parse
     *              URI" - and registering the bare domain does not cover
     *              subdomains. Whitelisting whichever host appeared first would
     *              therefore work until Meta answered from another edge node,
     *              then fail with an Unauthorized endpoint error that looks
     *              nothing like a CDN rotation.
     *
     *              Rewriting is safe because the signature in the query string
     *              validates the path and parameters, not the hostname:
     *              verified by fetching the same signed URL from three
     *              different scontent hosts and getting byte-identical 200s.
     *
     *              Anything that is not a recognised Meta CDN host is returned
     *              untouched, so a future platform is unaffected.
     *
     * @param imageUrl the platform's own image URL
     * @return         the same URL pointed at an authorised host
     */
    @TestVisible
    private static String canonicalMediaHost(String imageUrl) {
        if (String.isBlank(imageUrl)) {
            return imageUrl;
        }
        // scontent-nrt1-2.cdninstagram.com -> scontent.cdninstagram.com
        String rewritten = imageUrl.replaceFirst(
            '^https://[^/]*\\.cdninstagram\\.com',
            'https://scontent.cdninstagram.com'
        );
        // scontent-bom1-2.xx.fbcdn.net -> scontent.xx.fbcdn.net
        rewritten = rewritten.replaceFirst(
            '^https://[^/]*\\.fbcdn\\.net',
            'https://scontent.xx.fbcdn.net'
        );
        return rewritten;
    }

    /**
     * @description File extension for a downloaded image, from its Content-Type.
     *
     *              This is load-bearing, not cosmetic. Salesforce derives
     *              ContentVersion.FileType from the extension in the title, and
     *              the public download URL's Content-Type follows that. With no
     *              extension the file is served as
     *              application/octet-stream alongside a nosniff header, and the
     *              browser refuses to render it in an <img> - the record saves,
     *              the URL is valid, the guard passes, curl returns 200, and the
     *              card is still blank.
     *
     * @param contentType response header, possibly null or with charset suffix
     * @return            bare extension, never blank
     */
    @TestVisible
    private static String extensionFor(String contentType) {
        String type = String.isBlank(contentType)
            ? ''
            : contentType.toLowerCase().split(';')[0].trim();

        if (type == 'image/png')  { return 'png'; }
        if (type == 'image/gif')  { return 'gif'; }
        if (type == 'image/webp') { return 'webp'; }
        if (type == 'image/jpeg' || type == 'image/jpg') { return 'jpg'; }
        return DEFAULT_IMAGE_EXTENSION;
    }

    /**
     * @description Stores the image on Salesforce and returns its permanent
     *              public URL.
     *
     *              KenCreateContentVersion.createContentVersion ends in
     *              `catch (Exception ex) { return ex.getMessage(); }`, so on
     *              failure it returns its own ERROR TEXT in place of the URL.
     *              Media_Share_URL__c is a Url field and the landing page
     *              filters on it, so an error string must never reach it - hence
     *              the explicit protocol check rather than a null check.
     *
     * @return the public URL, or null if anything went wrong
     */
    private static String rehost(FetchedPost post, String base64Data, String extension) {
        String title = post.platform + ' ' + post.externalId.right(12) + '.' + extension;
        String publicUrl = KenCreateContentVersion.createContentVersion(title, base64Data);

        if (String.isBlank(publicUrl) || !publicUrl.startsWith('https://')) {
            return null;
        }
        // Url fields stop at 255. A ContentDownloadUrl measured 202 in the
        // AlumniDev sandbox and is shorter in production, so this should never
        // trigger - but a silent truncation would be worse than no card.
        if (publicUrl.length() > 255) {
            return null;
        }
        return publicUrl;
    }

    /**
     * @description Maps a fetched post onto the record shape.
     *
     *              Is_Active__c is deliberately not set here. The sync upserts
     *              on External_Post_Id__c, so writing it every run would undo an
     *              admin who had unticked a post to hide it - the field default
     *              covers genuinely new records.
     */
    private static Ken_Social_Media_Post__c toRecord(FetchedPost post, String publicUrl) {
        return new Ken_Social_Media_Post__c(
            External_Post_Id__c = post.externalId,
            Platform__c         = post.platform,
            // Body__c stops at 2000. LinkedIn allows 3000 and its pages use it -
            // an untrimmed one fails the whole UPSERT with STRING_TOO_LONG, taking
            // the other posts in the batch down with it, so this is not cosmetic.
            Body__c             = fitBody(post.body),
            Media_Share_URL__c = publicUrl,
            // Url fields stop at 255. Platform permalinks measure well under
            // that (40 for Instagram, 63 for Facebook), but a truncation would
            // save a link that leads nowhere, so drop it instead.
            Post_URL__c         = post.postUrl != null && post.postUrl.length() > 255
                ? null
                : post.postUrl,
            Posted_At__c        = post.postedAt
        );
    }

    /** Body__c's ceiling. A post longer than this is abbreviated, never dropped. */
    @TestVisible private static final Integer MAX_BODY_LENGTH = 2000;

    /**
     * @description The post text, cut to what Body__c can hold.
     *
     *              abbreviate() rather than left(): it ends the text with an
     *              ellipsis, so a card that was cut short reads as cut short
     *              instead of as a sentence that stops mid-word.
     */
    @TestVisible
    private static String fitBody(String body) {
        if (String.isBlank(body) || body.length() <= MAX_BODY_LENGTH) {
            return body;
        }
        return body.abbreviate(MAX_BODY_LENGTH);
    }

    // ═══════════════════════════ 3. fetch ═══════════════════════════

    // ───────────────────────── configuration ─────────────────────────


    /**
     * Lets a test supply configuration without touching the org's real records.
     *
     * Keyed by platform. This is the single test seam that replaced a separate
     * configOverride static on each of the four fetchers.
     */
    @TestVisible
    private static Map<String, Ken_Alm_Integration_Settings__mdt> overrides =
        new Map<String, Ken_Alm_Integration_Settings__mdt>();

    /**
     * Every config row, read once per transaction.
     *
     * Custom metadata SOQL does not count against the query limit, so this is
     * about not issuing five near-identical queries rather than about governors.
     */
    @TestVisible
    private static Map<String, Ken_Alm_Integration_Settings__mdt> cache;

    /**
     * @description This platform's configuration.
     *
     *              Returns an EMPTY record rather than null when the platform has
     *              no record at all, so a missing configuration surfaces as a
     *              blank token - which every caller already treats as "dormant" -
     *              instead of a NullPointerException halfway through a sync.
     *
     *              Looked up by the record's DeveloperName, which is why
     *              Service__c and the DeveloperName must agree.
     *
     *              SOQL, NOT getInstance(). getInstance silently truncates Long
     *              Text Area fields to 255 characters, and it does it without an
     *              error of any kind - the record shows the whole value in Setup,
     *              SOQL returns the whole value, and only this one access path
     *              hands back a shortened string.
     *
     *              That cost a real outage. LinkedIn access and refresh tokens run
     *              to about 350 characters, so every one of them arrived cut off
     *              and LinkedIn answered `invalid_grant` - which reads exactly like
     *              an expired or revoked token, sending the investigation to the
     *              LinkedIn portal instead of to this line. The other platforms
     *              never exposed it because Meta and X tokens fit inside 255.
     *
     *              Every row is read in ONE query and cached for the transaction,
     *              so the five platforms the landing page asks about cost one query
     *              between them rather than five.
     *
     * @param platform record DeveloperName, e.g. 'Instagram'
     * @return the record, or an empty one when absent
     */
    public static Ken_Alm_Integration_Settings__mdt forPlatform(String platform) {
        if (overrides.containsKey(platform)) {
            return overrides.get(platform);
        }

        if (cache == null) {
            cache = new Map<String, Ken_Alm_Integration_Settings__mdt>();
            for (Ken_Alm_Integration_Settings__mdt row : [
                SELECT DeveloperName, Service__c, Is_Active__c,
                       Account_Id__c, Account_Handle__c, Profile_URL__c,
                       API_Version__c, Connection__c
                FROM Ken_Alm_Integration_Settings__mdt
            WITH SYSTEM_MODE
            ]) {
                cache.put(row.DeveloperName, row);
            }
        }

        Ken_Alm_Integration_Settings__mdt config = cache.get(platform);
        return config == null ? new Ken_Alm_Integration_Settings__mdt() : config;
    }

    /**
     * @description Whether this platform should be synced at all.
     *
     *              Checked before any callout, so a dormant or half-configured
     *              platform costs nothing and cannot fail the others. A blank
     *              token counts as unconfigured even when Is_Active__c is ticked,
     *              because an admin ticking the box before pasting a credential
     *              is the normal order of events, not an error worth logging.
     *
     *              Every platform authenticates through a Named Credential named by
     *              Connection__c. A blank Connection__c means the platform has not
     *              been configured and nothing is fetched for it, so no token is
     *              stored in this org and none can go stale in it.
     *
     * @param platform record DeveloperName
     * @return true when active and carrying enough to make a request
     */
    public static Boolean isUsable(String platform) {
        Ken_Alm_Integration_Settings__mdt config = forPlatform(platform);

        return config.Is_Active__c == true
            && String.isNotBlank(config.Account_Id__c)
            && String.isNotBlank(config.Connection__c);
    }

    // ───────────────────────── the callouts ─────────────────────────

    /*
     * Replaced four near-identical classes - KenInstagramFetcher,
     * KenFacebookFetcher, KenXFetcher, KenThreadsFetcher - which between them
     * carried the same skeleton four times over: load config, bail if dormant,
     * GET, deserialise, check for an error envelope, walk `data`, map each row.
     * That skeleton exists once here, and each platform contributes only what is
     * genuinely its own.
     *
     * The consolidation only became possible once the five platform custom
     * settings objects collapsed into Ken_Alm_Integration_Settings__mdt. While every
     * platform read its own sObject type with its own field names (Page_Id__c vs
     * IG_Business_Account_Id__c vs X_User_Id__c), even the config read could not
     * be shared.
     *
     * The platform name is also the Ken_Alm_Integration_Settings__mdt DeveloperName and the
     * Ken_Social_Media_Post__c.Platform__c picklist value, so one string
     * addresses config, storage and the card's icon.
     *
     * WHAT STAYS PER-PLATFORM, and why none of it can be generalised away:
     *
     * | | Instagram | Facebook | X | Threads |
     * |---|---|---|---|---|
     * | edge | /media | /feed | /users/{id}/tweets | /threads |
     * | auth | ?access_token | ?access_token | Bearer HEADER | ?access_token |
     * | error | `error` | `error` | `errors` or `title` | `error` |
     * | image | media_url | full_picture | joined from includes.media | media_url |
     * | body | caption | message | text, minus the t.co tail | text |
     * | link | permalink | permalink_url | BUILT from the handle | permalink |
     * | date | timestamp | created_time | created_at | timestamp |
     * | junk to reject | VIDEO | visitor posts, added_video | non-photo media | REPOST_FACADE, AUDIO, TEXT_POST |
     *
     * LinkedIn is deliberately absent from that table: it shares not one row with
     * the other four, so a fifth column would be a column of exceptions. It is the
     * only platform that
     *
     *   - wraps its rows in `elements` rather than `data` (the Rest.li envelope);
     *   - versions by HEADER (LinkedIn-Version) rather than by URL path;
     *   - sends epoch MILLISECONDS as a number rather than an ISO date string;
     *   - reports errors under `serviceErrorCode`/`status`, not `error`;
     *   - returns no image URL AT ALL - a post carries a urn:li:image: handle that
     *     costs a SECOND callout to resolve, which is why resolveLinkedInImages
     *     exists and no other platform needed anything like it;
     *   - authenticates through a Named Credential rather than a stored token,
     *     because its access token expires every 60 days.
     *
     * Each of those is one branch, and each branch is named for LinkedIn where it
     * sits, so the divergence is visible at every point rather than summarised
     * here and forgotten.
     */

    @TestVisible private static final String INSTAGRAM = 'Instagram';
    @TestVisible private static final String FACEBOOK  = 'Facebook';
    @TestVisible private static final String LINKEDIN  = 'LinkedIn';
    @TestVisible private static final String X         = 'X';
    @TestVisible private static final String THREADS   = 'Threads';

    /**
     * A DRAFT post is returned to an authorised caller but is invisible to the
     * logged-out visitor the band is built for, so a card linking to one would
     * 404 for every person who saw it.
     */
    @TestVisible private static final String LI_PUBLISHED = 'PUBLISHED';

    /**
     * A LinkedIn video post carries content.media.id exactly as an image post
     * does - only the URN type tells them apart. Left unchecked the video URN
     * would be sent to /rest/images, which does not resolve it, costing a callout
     * to learn what the prefix already says. Same trap as FB_STATUS_VIDEO.
     */
    @TestVisible private static final String LI_IMAGE_URN_PREFIX = 'urn:li:image:';

    @TestVisible private static final String LI_ORG_URN_PREFIX = 'urn:li:organization:';

    /**
     * Used only when API_Version__c is blank. LinkedIn answers a versionless /rest
     * request with 426 Upgrade Required, so a blank field must not be allowed to
     * become an empty header - it would take the whole platform down rather than
     * degrade.
     */
    @TestVisible private static final String LI_DEFAULT_VERSION = '202508';

    /**
     * Only still images reach the band for v1.
     *
     * Instagram and Threads share this vocabulary because Threads is an Instagram
     * product, which is the one place the two genuinely converge - a carousel's
     * first child is a still image, so an album is usable as a single-image card.
     */
    @TestVisible private static final String META_TYPE_IMAGE = 'IMAGE';
    @TestVisible private static final String META_TYPE_ALBUM = 'CAROUSEL_ALBUM';

    /**
     * A Facebook video post still carries a full_picture - its thumbnail. Left
     * alone it would ship as a card that looks like a photo and plays nothing.
     */
    @TestVisible private static final String FB_STATUS_VIDEO = 'added_video';

    /**
     * X's media type for a still. A video or animated GIF carries
     * preview_image_url instead of url, so it would otherwise land as a still that
     * looks like a photo and plays nothing - the same trap as FB_STATUS_VIDEO.
     */
    @TestVisible private static final String X_MEDIA_PHOTO = 'photo';

    /**
     * X rejects max_results below 5 with a 400, so a Social Fetch Limit of 3 -
     * sensible, given the band shows three cards - cannot be sent as-is. The
     * request asks for this floor and mapRows trims the surplus away.
     */
    @TestVisible private static final Integer X_MIN_MAX_RESULTS = 5;

    /**
     * @description Newest image posts from the platform's configured account.
     *
     *              Every failure mode returns an empty list rather than throwing:
     *              one dead credential or one API outage must not take the other
     *              platforms down with it, because the sync walks them in a chain.
     *
     * @param platform Ken_Alm_Integration_Settings__mdt DeveloperName, e.g. 'Instagram'
     * @return posts worth storing; empty when switched off, unconfigured or failing
     */
    @TestVisible
    private static List<FetchedPost> fetchRecent(String platform) {
        List<FetchedPost> posts = new List<FetchedPost>();

        // isUsable covers all three old guards at once - active, an account to
        // address, and a credential to send - so a dormant platform costs nothing
        // and makes no callout.
        if (!isUsable(platform)) {
            return posts;
        }
        Ken_Alm_Integration_Settings__mdt config = forPlatform(platform);

        String endpoint = buildEndpoint(platform, config);
        if (String.isBlank(endpoint)) {
            // An unrecognised platform name. Worth a log line, because the config
            // record exists and looks healthy - the mistake is a typo'd
            // DeveloperName, which is otherwise invisible.
            System.debug(LoggingLevel.ERROR,
                'KenSocialSync: no endpoint defined for platform ' + platform);
            return posts;
        }

        HttpResponse res = call(platform, endpoint, config);
        if (res == null || res.getStatusCode() != 200) {
            return posts;
        }

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (hasApiError(platform, body)) {
            return posts;
        }
        // Four platforms wrap their rows in "data"; LinkedIn uses "elements", the
        // Rest.li collection envelope. An account with nothing to return omits the
        // key entirely rather than sending an empty array, so its absence is
        // normal, not a fault.
        String rowsKey = LINKEDIN.equals(platform) ? 'elements' : 'data';
        if (!(body.get(rowsKey) instanceof List<Object>)) {
            return posts;
        }

        return mapRows(platform, (List<Object>) body.get(rowsKey), body, config);
    }

    // ───────────────────────── request ─────────────────────────

    /**
     * @description The platform's own timeline request, or null if the platform is
     *              unrecognised.
     *
     *              The Meta-family endpoints request only plain scalar fields.
     *              Graph's nested syntax - attachments{media_type} - would say more
     *              about a post, but it needs braces in the query string and Graph
     *              reports a bad field expression only when the edge has rows to
     *              return, so a syntax mistake would sit undetected until the first
     *              real post arrived and then produce an empty feed.
     */
    private static String buildEndpoint(String platform, Ken_Alm_Integration_Settings__mdt config) {
        String host = platformHost(config);
        if (host == null) {
            return null;
        }
        String base = host + '/' + config.API_Version__c;
        Integer limitToFetch = fetchLimit();

        switch on platform {
            when 'Instagram' {
                // Instagram is addressed by its BUSINESS ACCOUNT id on the media
                // edge, not by the Facebook Page it hangs off.
                return base + '/' + config.Account_Id__c + '/media'
                    + '?fields=id,caption,media_type,media_url,permalink,timestamp'
                    + '&limit=' + limitToFetch;
            }
            when 'Facebook' {
                return base + '/' + config.Account_Id__c + '/feed'
                    + '?fields=id,message,created_time,full_picture,permalink_url,status_type,from'
                    + '&limit=' + limitToFetch;
            }
            when 'Threads' {
                return base + '/' + config.Account_Id__c + '/threads'
                    + '?fields=id,media_type,media_url,permalink,text,timestamp'
                    + '&limit=' + limitToFetch;
            }
            when 'LinkedIn' {
                // The one endpoint here versioned by HEADER instead of by path,
                // which is why it ignores `base`: /rest carries no version segment
                // and appending API_Version__c to it returns 404.
                //
                // sortBy=LAST_MODIFIED is the only sort this finder supports. It is
                // not the same as newest-published - editing an old post lifts it -
                // but the band re-sorts by Posted_At__c, so this decides only WHICH
                // posts come back, never the order they are shown in.
                return host + '/rest/posts'
                    + '?q=author'
                    + '&author=' + EncodingUtil.urlEncode(organizationUrn(config), 'UTF-8')
                    + '&count=' + limitToFetch
                    + '&sortBy=LAST_MODIFIED';
            }
            when 'X' {
                // exclude=retweets,replies is what keeps other people's content off
                // the band: a retweet is returned as OUR post carrying SOMEONE
                // ELSE'S text and image. The exclusions are applied AFTER
                // max_results is counted, so a timeline heavy with replies can
                // return fewer posts than asked for - the fetch limit is a ceiling,
                // not a promise.
                return base + '/users/' + config.Account_Id__c + '/tweets'
                    + '?max_results=' + xMaxResults()
                    + '&exclude=retweets,replies'
                    + '&tweet.fields=created_at'
                    + '&expansions=attachments.media_keys'
                    + '&media.fields=url,type';
            }
            when else {
                return null;
            }
        }
    }

    /**
     * @description Where this platform's requests are addressed.
     *
     *              Always a Named Credential. Blank means the platform is not
     *              configured and nothing is fetched for it.
     */
    private static String platformHost(Ken_Alm_Integration_Settings__mdt config) {
        String connection = KenSettings.connectionFor(config);
        return connection == null ? null : 'callout:' + connection;
    }

    private static Integer xMaxResults() {
        return Math.max(fetchLimit(), X_MIN_MAX_RESULTS);
    }

    /**
     * @description Sends the request, returning null on any transport failure.
     *
     *              Every platform is addressed through its Named Credential and
     *              authenticates with the merge field it resolves, so no token
     *              appears here. LinkedIn additionally needs two headers that
     *              /rest refuses to work without.
     */
    private static HttpResponse call(
        String platform,
        String endpoint,
        Ken_Alm_Integration_Settings__mdt config
    ) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer {!$Credential.Password}');
            if (LINKEDIN.equals(platform)) {
                // Both are mandatory on /rest. A missing LinkedIn-Version is a
                // loud 426 NONEXISTENT_VERSION - and note that a version LinkedIn
                // has RETIRED fails the same way, so API_Version__c is a value
                // that goes stale on its own about a year after it is set.
                req.setHeader('LinkedIn-Version', linkedInVersion(config));
                req.setHeader('X-Restli-Protocol-Version', '2.0.0');
            }
            req.setTimeout(60000);
            return new Http().send(req);
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * @description Whether the body is an error envelope rather than usable data.
     *
     *              Meta and Threads answer some failures with HTTP 200 and an
     *              `error` object, so the status code alone is not enough.
     *
     *              X reports failure two different ways: a partial success carries
     *              an `errors` array alongside usable data, while an auth or quota
     *              refusal is an RFC 7807 document with `title`/`detail` and no data
     *              at all. Neither is worth partially trusting.
     *
     *              LinkedIn returns `serviceErrorCode`, `status` and `message`, and
     *              never the word `error` - so the default branch would read a 401
     *              from an expired token as a clean response with no rows, and the
     *              band would go quietly empty instead of logging anything. A
     *              healthy /rest/posts body carries only `elements` and `paging`,
     *              so neither key can appear on a success.
     */
    private static Boolean hasApiError(String platform, Map<String, Object> body) {
        if (X.equals(platform)) {
            return body.containsKey('errors') || body.containsKey('title');
        }
        if (LINKEDIN.equals(platform)) {
            return body.containsKey('serviceErrorCode') || body.containsKey('status');
        }
        return body.containsKey('error');
    }

    // ───────────────────────── mapping ─────────────────────────

    /**
     * @description Maps the response rows onto FetchedPosts, newest first.
     *
     *              Only X trims here. It is forced to over-ask by
     *              X_MIN_MAX_RESULTS, and the trim happens AFTER the photo filter
     *              so that text-only posts do not consume the quota and leave the
     *              band short. The Meta family gets exactly what `limit` asked for,
     *              so there is nothing to trim.
     */
    private static List<FetchedPost> mapRows(
        String platform,
        List<Object> rows,
        Map<String, Object> body,
        Ken_Alm_Integration_Settings__mdt config
    ) {
        List<FetchedPost> posts = new List<FetchedPost>();

        Boolean isX = X.equals(platform);
        Integer keep = isX ? fetchLimit() : null;

        // Two platforms keep their image URLs somewhere other than the post row, so
        // both are joined back by key here rather than inside a mapper. X's arrive
        // in a sibling includes.media array of the SAME response, costing nothing.
        // LinkedIn's need a second callout, which is why this happens once for the
        // whole batch and not once per post.
        Map<String, String> mediaByKey = null;
        if (isX) {
            mediaByKey = indexXMedia(body);
        } else if (LINKEDIN.equals(platform)) {
            mediaByKey = resolveLinkedInImages(rows, config);
        }

        for (Object row : rows) {
            if (keep != null && posts.size() >= keep) {
                break;
            }
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            FetchedPost post = toPost(platform, (Map<String, Object>) row, mediaByKey, config);
            if (post != null) {
                posts.add(post);
            }
        }
        return posts;
    }

    /** Routes one row to its platform's mapper, or null if unrenderable. */
    private static FetchedPost toPost(
        String platform,
        Map<String, Object> row,
        Map<String, String> mediaByKey,
        Ken_Alm_Integration_Settings__mdt config
    ) {
        switch on platform {
            // Instagram and Threads differ by ONE field name - the caption - so
            // they share a mapper rather than duplicating the media_type filter.
            when 'Instagram' { return metaImagePost(platform, row, 'caption'); }
            when 'Threads'   { return metaImagePost(platform, row, 'text'); }
            when 'Facebook'  { return facebookPost(platform, row, config.Account_Id__c); }
            when 'LinkedIn'  { return linkedInPost(platform, row, mediaByKey); }
            when 'X'         { return xPost(platform, row, mediaByKey, config.Account_Handle__c); }
            when else        { return null; }
        }
    }

    /**
     * @description Maps an Instagram or Threads row.
     *
     *              media_type is the filter both platforms share. Instagram returns
     *              IMAGE, VIDEO and CAROUSEL_ALBUM; Threads adds TEXT_POST, AUDIO
     *              and REPOST_FACADE. Only the two still-image values survive.
     *
     *              REPOST_FACADE matters most: it is SOMEONE ELSE'S post appearing
     *              on our timeline, so letting it through would put a stranger's
     *              photo on the alumni band as though the institute had posted it.
     *              That is the same hazard as an X retweet and a Facebook visitor
     *              post - each platform needs its own guard, and this is Threads'.
     *
     *              Note TEXT_POST also covers GIFs and polls, so those are dropped
     *              here rather than arriving as a type of their own.
     *
     * @param bodyField `caption` on Instagram, `text` on Threads
     */
    private static FetchedPost metaImagePost(
        String platform,
        Map<String, Object> row,
        String bodyField
    ) {
        String mediaType = (String) row.get('media_type');
        if (mediaType != META_TYPE_IMAGE && mediaType != META_TYPE_ALBUM) {
            return null;
        }

        String mediaUrl = (String) row.get('media_url');
        String externalId = (String) row.get('id');
        if (String.isBlank(mediaUrl) || String.isBlank(externalId)) {
            return null;
        }

        // Both return an offset form, e.g. "2026-08-10T11:34:30+0000"; parseInstant
        // normalises to GMT, which is what the portal stores.
        DateTime postedAt = KenDateTimeUtil.parseInstant((String) row.get('timestamp'));
        if (postedAt == null) {
            return null;
        }

        // permalink is the public post page, which stays reachable after the signed
        // media_url has expired.
        return build(
            platform,
            externalId,
            (String) row.get(bodyField),
            mediaUrl,
            (String) row.get('permalink'),
            postedAt
        );
    }

    /**
     * @description Maps a Facebook /feed row.
     *
     * @param pageId the configured Page, used to reject visitor posts
     */
    private static FetchedPost facebookPost(
        String platform,
        Map<String, Object> row,
        String pageId
    ) {
        // /feed is the Page's WHOLE timeline, so visitors' posts belong to it too.
        // They are withheld today because the token lacks
        // pages_read_user_content, but that scope could be added for some other
        // integration at any time.
        if (!isOwnFacebookPost(row, pageId)) {
            return null;
        }
        if (FB_STATUS_VIDEO.equals((String) row.get('status_type'))) {
            return null;
        }

        String mediaUrl = (String) row.get('full_picture');
        String externalId = (String) row.get('id');
        if (String.isBlank(mediaUrl) || String.isBlank(externalId)) {
            return null;
        }

        DateTime postedAt = KenDateTimeUtil.parseInstant((String) row.get('created_time'));
        if (postedAt == null) {
            return null;
        }

        // Facebook calls this permalink_url, where Instagram calls the same idea
        // permalink - the single most gratuitous difference between the two.
        return build(
            platform,
            externalId,
            (String) row.get('message'),
            mediaUrl,
            (String) row.get('permalink_url'),
            postedAt
        );
    }

    /**
     * @description Whether the Page itself wrote this post.
     *
     *              An absent author is treated as ours: `from` is only withheld when
     *              the token cannot read other people's content, which is exactly
     *              the case where every row returned is already the Page's own.
     */
    private static Boolean isOwnFacebookPost(Map<String, Object> row, String pageId) {
        Object author = row.get('from');
        if (!(author instanceof Map<String, Object>)) {
            return true;
        }
        String authorId = (String) ((Map<String, Object>) author).get('id');
        return String.isBlank(authorId) || authorId == pageId;
    }

    /**
     * @description Maps a LinkedIn /rest/posts element.
     *
     *              The mapper itself is thin because the two things that make
     *              LinkedIn awkward are handled elsewhere - the image URN is
     *              already resolved by resolveLinkedInImages, and the epoch
     *              timestamp by fromEpochMillis. What is left here is the same
     *              shape as every other mapper: reject what cannot be rendered,
     *              then build.
     */
    private static FetchedPost linkedInPost(
        String platform,
        Map<String, Object> row,
        Map<String, String> urlByUrn
    ) {
        String externalId = (String) row.get('id');
        if (String.isBlank(externalId)) {
            return null;
        }

        // A reshare is SOMEONE ELSE'S post carried on our page's timeline. Letting
        // it through would put a stranger's photo on the alumni band under the
        // institute's name - the same hazard as a Threads REPOST_FACADE, an X
        // retweet and a Facebook visitor post. This is LinkedIn's guard, and it is
        // the presence of the key that matters, not its contents.
        if (row.containsKey('reshareContext')) {
            return null;
        }

        // DRAFT is returned to us because the token is a page admin's; it is not
        // returned to a visitor, so the card would link to a 404 for everyone who
        // clicked it. An absent lifecycleState is treated as published, since
        // older API versions omit the field on live posts.
        Object lifecycle = row.get('lifecycleState');
        if (lifecycle != null && LI_PUBLISHED != String.valueOf(lifecycle)) {
            return null;
        }

        // Map.get(null) is null, so a post with no resolvable image falls out here
        // rather than needing its own branch.
        String mediaUrl = urlByUrn == null
            ? null
            : urlByUrn.get(firstLinkedInImageUrn(row));
        if (String.isBlank(mediaUrl)) {
            return null;
        }

        // publishedAt is when it went live; createdAt is when the draft was made.
        // The band sorts by date and shows a date, so the visitor-facing one wins
        // wherever both are present.
        DateTime postedAt = fromEpochMillis(
            row.get('publishedAt') != null ? row.get('publishedAt') : row.get('createdAt')
        );
        if (postedAt == null) {
            return null;
        }

        return build(
            platform,
            externalId,
            cleanLinkedInText((String) row.get('commentary')),
            mediaUrl,
            buildLinkedInPostUrl(externalId),
            postedAt
        );
    }

    /**
     * @description Strips LinkedIn's authoring markup out of post text.
     *
     *              `commentary` is not plain text - it is LinkedIn's own markup, and
     *              rendered raw a card reads
     *              "Today at @[TsquaredC](urn:li:organization:88395943) HQ" and
     *              "{hashtag|\#|Innovation}". No other platform does this; Meta and
     *              X return the text as written.
     *
     *              Three forms, each turned into what the author meant:
     *              a mention keeps its display name, a hashtag becomes a plain #tag,
     *              and <br> becomes a real line break. Entities are then decoded, so
     *              &amp;#39; is an apostrophe and the emoji LinkedIn escapes come back
     *              as emoji.
     */
    @TestVisible
    private static String cleanLinkedInText(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String cleaned = text;

        // @[Display Name](urn:li:person:ABC) -> Display Name
        cleaned = cleaned.replaceAll('@\\[([^\\]]*)\\]\\(urn:li:[^)]*\\)', '$1');

        // {hashtag|\#|Innovation} -> #Innovation   (the backslash is LinkedIn's own)
        cleaned = cleaned.replaceAll('\\{hashtag\\|\\\\?#\\|([^}]*)\\}', '#$1');

        // <br> and <br/> are the only tags LinkedIn emits here.
        cleaned = cleaned.replaceAll('(?i)<br\\s*/?>', '\n');

        cleaned = cleaned.unescapeHtml4();
        return cleaned.trim();
    }

    /**
     * @description Image URN -> download URL for the posts worth building a card
     *              from.
     *
     *              LinkedIn is the only platform whose post does not carry its own
     *              image URL: content.media.id is a urn:li:image: handle and the
     *              bytes sit behind /rest/images, so a card cannot be built from
     *              the timeline response alone.
     *
     *              ONE REQUEST PER IMAGE, deliberately. The batch form,
     *              /rest/images?ids=List(a,b,c), is the obvious choice and it does
     *              not work here: it answers 429 TOO_MANY_REQUESTS with
     *              "APPLICATION DAY limit for calls to this resource is reached"
     *              while the single-id form answers 200 for the very same URN in
     *              the very same second. The two are throttled as SEPARATE
     *              resources, and the batch quota is far smaller.
     *
     *              Rows that cannot become a card are filtered out BEFORE any
     *              request, because each one now costs a callout: reshares and
     *              drafts are dropped for the same reasons linkedInPost drops them,
     *              and documents and videos never had an image URN to resolve.
     *
     *              Returns an empty map on any failure, which drops LinkedIn's
     *              cards for this run and leaves the other platforms untouched.
     */
    private static Map<String, String> resolveLinkedInImages(
        List<Object> rows,
        Ken_Alm_Integration_Settings__mdt config
    ) {
        Map<String, String> urlByUrn = new Map<String, String>();

        Set<String> urns = new Set<String>();
        for (Object row : rows) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> r = (Map<String, Object>) row;

            // The same two rejections linkedInPost makes, applied early so a post
            // that is going to be thrown away does not cost a callout first.
            if (r.containsKey('reshareContext')) {
                continue;
            }
            Object lifecycle = r.get('lifecycleState');
            if (lifecycle != null && LI_PUBLISHED != String.valueOf(lifecycle)) {
                continue;
            }

            String urn = firstLinkedInImageUrn(r);
            if (String.isNotBlank(urn)) {
                urns.add(urn);
            }
        }
        if (urns.isEmpty()) {
            return urlByUrn;
        }

        for (String urn : urns) {
            // Each URN is its own resource path, so the colons must be encoded.
            String endpoint = platformHost(config)
                + '/rest/images/' + EncodingUtil.urlEncode(urn, 'UTF-8');

            HttpResponse res = call(LINKEDIN, endpoint, config);
            if (res == null || res.getStatusCode() != 200) {
                // One unreadable image costs one card, not the run.
                continue;
            }
            try {
                Map<String, Object> body =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String url = str(body.get('downloadUrl'));
                if (String.isNotBlank(url)) {
                    urlByUrn.put(urn, url);
                }
            } catch (Exception ex) {
                continue;
            }
        }
        return urlByUrn;
    }

    /**
     * @description The post's image URN, or null when it has no still image.
     *
     *              Two content shapes carry one: `media` for a single image and
     *              `multiImage` for a carousel. The band shows one image per card,
     *              so the first of a carousel wins - exactly as it does for an
     *              Instagram album and for an X post carrying four photos.
     *
     *              Every other shape yields null and the post is dropped:
     *              `article` is a link preview whose thumbnail is hosted by the
     *              linked site rather than by LinkedIn, `poll` and a bare
     *              commentary have no image at all, and a video's id is a
     *              urn:li:video: that LI_IMAGE_URN_PREFIX rejects here rather than
     *              wasting a callout to discover.
     */
    @TestVisible
    private static String firstLinkedInImageUrn(Map<String, Object> row) {
        Object content = row.get('content');
        if (!(content instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> contentMap = (Map<String, Object>) content;

        Object media = contentMap.get('media');
        if (media instanceof Map<String, Object>) {
            return imageUrnOrNull((String) ((Map<String, Object>) media).get('id'));
        }

        Object multi = contentMap.get('multiImage');
        if (multi instanceof Map<String, Object>) {
            Object images = ((Map<String, Object>) multi).get('images');
            if (images instanceof List<Object> && !((List<Object>) images).isEmpty()) {
                Object first = ((List<Object>) images)[0];
                if (first instanceof Map<String, Object>) {
                    return imageUrnOrNull((String) ((Map<String, Object>) first).get('id'));
                }
            }
        }
        return null;
    }

    /** Keeps only image handles, so a video URN never reaches /rest/images. */
    private static String imageUrnOrNull(String urn) {
        return String.isNotBlank(urn) && urn.startsWith(LI_IMAGE_URN_PREFIX)
            ? urn
            : null;
    }

    /**
     * @description LinkedIn's timestamps as a DateTime.
     *
     *              LinkedIn is the only platform here that sends epoch
     *              MILLISECONDS as a JSON number rather than an ISO string, so
     *              KenDateTimeUtil.parseInstant - which every other mapper uses -
     *              has nothing to parse.
     *
     *              The instanceof ladder is not defensive padding.
     *              JSON.deserializeUntyped picks the narrowest type each value
     *              fits, so the same field arrives as Integer, Long or Decimal
     *              depending on the number, and a straight cast to Long throws a
     *              TypeException on the other two - taking down the whole platform
     *              over a timestamp.
     */
    @TestVisible
    private static DateTime fromEpochMillis(Object value) {
        if (value instanceof Long) {
            return DateTime.newInstance((Long) value);
        }
        if (value instanceof Integer) {
            Long millis = (Integer) value;
            return DateTime.newInstance(millis);
        }
        if (value instanceof Decimal) {
            return DateTime.newInstance(((Decimal) value).longValue());
        }
        if (value instanceof Double) {
            return DateTime.newInstance(((Double) value).longValue());
        }
        return null;
    }

    /**
     * @description The public post page, e.g.
     *              "https://www.linkedin.com/feed/update/urn:li:share:7123456789/".
     *
     *              Built rather than read, since /rest/posts returns no permalink -
     *              the same situation as X. Unlike X's it needs no handle, because
     *              the URN alone addresses the post, so this can never return null
     *              and a LinkedIn card always links somewhere.
     *
     *              The trailing slash is load-bearing: without it LinkedIn answers
     *              with the visitor's own feed rather than the post.
     */
    private static String buildLinkedInPostUrl(String externalId) {
        return 'https://www.linkedin.com/feed/update/' + externalId + '/';
    }

    /**
     * @description The page's author URN.
     *
     *              Account_Id__c may hold either the bare numeric page id or the
     *              full urn:li:organization:... form, because LinkedIn's own
     *              documentation shows both and an admin copying either is not
     *              making a mistake. The bare id is the likelier paste, since that
     *              is what the page's admin URL shows.
     */
    private static String organizationUrn(Ken_Alm_Integration_Settings__mdt config) {
        String accountId = config.Account_Id__c == null
            ? ''
            : config.Account_Id__c.trim();

        return accountId.startsWith(LI_ORG_URN_PREFIX)
            ? accountId
            : LI_ORG_URN_PREFIX + accountId;
    }

    /**
     * @description The LinkedIn-Version header value, e.g. "202508".
     *
     *              Reuses API_Version__c, which holds "v21.0" for the Meta family:
     *              the same concept in a different notation, and one shared field
     *              beats a second that only one platform would ever populate. The
     *              leading "v" is stripped so an admin who types "v202508" out of
     *              Meta habit gets a working request rather than a 426.
     *
     *              LinkedIn retires each version roughly a year after release, so
     *              this is a value someone must revisit - which is exactly why it
     *              is configuration and not a constant in this file.
     */
    private static String linkedInVersion(Ken_Alm_Integration_Settings__mdt config) {
        return String.isBlank(config.API_Version__c)
            ? LI_DEFAULT_VERSION
            : config.API_Version__c.trim().removeStart('v');
    }

    /** A JSON value as a real String, with the literal "null" read as absent. */
    private static String str(Object value) {
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value);
        return text == 'null' ? null : text;
    }

    /** Maps an X timeline row, whose image has to be joined in by media key. */
    private static FetchedPost xPost(
        String platform,
        Map<String, Object> row,
        Map<String, String> urlByKey,
        String handle
    ) {
        String externalId = (String) row.get('id');
        if (String.isBlank(externalId)) {
            return null;
        }

        String mediaUrl = firstXPhotoUrl(row, urlByKey);
        if (String.isBlank(mediaUrl)) {
            return null;
        }

        // X returns "2026-08-13T10:00:00.000Z" - the millisecond Zulu form.
        // parseInstant takes that and Meta's "+0000" offset form alike.
        DateTime postedAt = KenDateTimeUtil.parseInstant((String) row.get('created_at'));
        if (postedAt == null) {
            return null;
        }

        return build(
            platform,
            externalId,
            cleanText((String) row.get('text')),
            mediaUrl,
            buildXPostUrl(handle, externalId),
            postedAt
        );
    }

    /**
     * @description Photo URLs from the response's includes block, by media key.
     *
     *              Only photos are indexed - see X_MEDIA_PHOTO. includes is absent
     *              altogether on a text-only timeline, which is why every step is
     *              instanceof-guarded rather than cast.
     */
    private static Map<String, String> indexXMedia(Map<String, Object> body) {
        Map<String, String> urlByKey = new Map<String, String>();

        Object includes = body.get('includes');
        if (!(includes instanceof Map<String, Object>)) {
            return urlByKey;
        }
        Object media = ((Map<String, Object>) includes).get('media');
        if (!(media instanceof List<Object>)) {
            return urlByKey;
        }

        for (Object entry : (List<Object>) media) {
            if (!(entry instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> item = (Map<String, Object>) entry;
            if (X_MEDIA_PHOTO != (String) item.get('type')) {
                continue;
            }
            String mediaKey = (String) item.get('media_key');
            String url = (String) item.get('url');
            if (String.isNotBlank(mediaKey) && String.isNotBlank(url)) {
                urlByKey.put(mediaKey, url);
            }
        }
        return urlByKey;
    }

    /**
     * @description The post's first still image, or null if it has none.
     *
     *              A post can carry up to four media keys; the band shows one image
     *              per card, so the first photo wins. The keys are checked against
     *              urlByKey rather than assumed present, because a post whose only
     *              attachment is a video contributes keys indexXMedia deliberately
     *              skipped.
     */
    private static String firstXPhotoUrl(
        Map<String, Object> row,
        Map<String, String> urlByKey
    ) {
        Object attachments = row.get('attachments');
        if (!(attachments instanceof Map<String, Object>)) {
            return null;
        }
        Object keys = ((Map<String, Object>) attachments).get('media_keys');
        if (!(keys instanceof List<Object>)) {
            return null;
        }

        for (Object key : (List<Object>) keys) {
            String url = urlByKey.get(String.valueOf(key));
            if (String.isNotBlank(url)) {
                return url;
            }
        }
        return null;
    }

    /**
     * @description Strips the trailing t.co shortlink X appends to the text of any
     *              post carrying media.
     *
     *              That link points at the post's own image, which the card is
     *              already showing, so left in place every X card would end in a
     *              meaningless "https://t.co/AbCdEf". Only a TRAILING link is
     *              removed - a link the author wrote mid-sentence is theirs.
     */
    @TestVisible
    private static String cleanText(String text) {
        if (String.isBlank(text)) {
            return text;
        }
        String cleaned = text.replaceFirst('\\s*https://t\\.co/\\S+\\s*$', '');
        return String.isBlank(cleaned) ? null : cleaned.trim();
    }

    /**
     * @description The public post page, e.g. "https://x.com/kenalumni/status/123".
     *
     *              Built rather than read, since X returns no permalink at all. The
     *              path segment is not validated by X - any handle resolves to the
     *              right post and redirects - but a wrong one would show visitors
     *              the wrong account name in the address bar, so a blank handle
     *              yields null instead of a half-built URL. The LWC drops an href
     *              bound to undefined, so such a card simply does not link anywhere.
     *
     *              This is why Account_Handle__c is FUNCTIONAL for X and merely
     *              cosmetic for the other three.
     */
    private static String buildXPostUrl(String handle, String externalId) {
        if (String.isBlank(handle)) {
            return null;
        }
        return 'https://x.com/' + handle.trim().removeStart('@')
            + '/status/' + externalId;
    }

    /**
     * @description Assembles a FetchedPost. Shared by all four platforms - the one
     *              part of mapping that never varied.
     *
     *              The external id is platform-prefixed so the dedup key cannot
     *              collide across platforms, which matters because two platforms
     *              can legitimately return the same numeric id.
     */
    private static FetchedPost build(
        String platform,
        String externalId,
        String body,
        String imageUrl,
        String postUrl,
        DateTime postedAt
    ) {
        FetchedPost post = new FetchedPost();
        post.externalId     = platform + ':' + externalId;
        post.platform       = platform;
        post.body           = body;
        post.sourceImageUrl = imageUrl;
        post.postUrl        = postUrl;
        post.postedAt       = postedAt;
        return post;
    }
}