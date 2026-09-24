/**
 * LinkedIn profile enrichment — single class for the whole feature.
 *
 * Public surface:
 *  - @AuraEnabled entry points used by portal/admin LWCs (syncAlumni, syncAlumniSync,
 *    syncCurrentUserFromLinkedIn, syncForRoleFromLinkedIn, fetchProfilePreview,
 *    syncAlumniBulk, getLinkedInData).
 *  - @future enqueue() for fire-and-forget callouts outside the triggering txn.
 *  - syncAccounts(Set<Id>) / syncAccountSync(Id) / fetchProfileByUrl(String) for
 *    direct Apex callers (and tests).
 *
 * Adapted from the KIS LinkedInRestApi (Contact-based) to the EXP Cloud 2.0
 * Person-Account model. Provider contract unchanged: POST {urls:[...]} with
 * Named Credential, response { results:[ { url, profile:{ ... } } ] }. All
 * callouts (enrichment + image downloads) run BEFORE any DML so the work is
 * callout-safe. Re-sync is safe: rows previously created by the sync
 * (LinkedIn_Sourced__c = true) are archived, then fresh rows inserted, so
 * manual entries are never touched.
 */
public with sharing class KenLinkedInController {

    private static final String ENRICH_PATH = '/api/v1/enrich/batch';
    private static final String ENRICH_HEADER_NAME = 'X-API-Key';
    private static final String ENRICH_HEADER_VALUE = '{!$Credential.Password}';
    @TestVisible private static final Integer MAX_URLS_PER_REQUEST = 25;

    public class KenLinkedInSyncException extends Exception {}

    public class ProfilePreview {
        @AuraEnabled public Integer experiencesCount;
        @AuraEnabled public Integer educationCount;
        @AuraEnabled public Integer certificationsCount;
        @AuraEnabled public String  profilePicUrl;
        @AuraEnabled public String  rawJson;
    }

    // ============================================================
    /**
     * What actually reached the database. Counts come from inspected DML results,
     * never from the provider payload, so the UI can never report rows it did not
     * save - that mismatch was the whole reason a sync could claim success while
     * writing nothing.
     */
    public class SyncResult {
        @AuraEnabled public Integer jobsSaved           { get; set; }
        @AuraEnabled public Integer educationSaved      { get; set; }
        @AuraEnabled public Integer certificationsSaved { get; set; }
        @AuraEnabled public Integer rowsFailed          { get; set; }
        @AuraEnabled public String  firstError          { get; set; }
        public SyncResult() {
            jobsSaved = 0; educationSaved = 0; certificationsSaved = 0; rowsFailed = 0;
        }
    }

    // @AuraEnabled entry points
    // ============================================================

    @AuraEnabled
    public static void getLinkedInData(String accountId, String email) {
        try {
            Id resolvedId = resolveAccountId(accountId, email);
            if (resolvedId == null) {
                throw new AuraHandledException('No alumni Person Account found to sync.');
            }
            enqueue(new Set<Id>{ resolvedId });
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void syncAlumni(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('No alumni record provided.');
        }
        enqueue(new Set<Id>{ accountId });
    }

    /**
     * SYNCHRONOUS single-account sync used by the record-page quick action.
     * Propagates the real provider error (401, missing key, empty response, etc.)
     * so the UI can show it rather than falsely toasting "started" while the
     * @future failed silently.
     */
    @AuraEnabled
    public static SyncResult syncAlumniSync(Id accountId) {
        try {
            return syncAccountSync(accountId);
        } catch (KenLinkedInSyncException kse) {
            throw new AuraHandledException(kse.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static SyncResult syncCurrentUserFromLinkedIn(String linkedInUrl) {
        return syncForRoleFromLinkedIn(linkedInUrl, null);
    }

    /**
     * @description Syncs the alumnus behind roleId - or the running user's Person
     *              Account - from a LinkedIn URL that is not stored yet. The URL is
     *              passed down rather than saved first: any DML ahead of the provider
     *              callout makes Salesforce throw "You have uncommitted work pending",
     *              which silently failed every onboarding import. storeProfiles writes
     *              the URL together with the synced rows, once all callouts are done.
     * @return      What actually committed, never the provider's own counts.
     */
    @AuraEnabled
    public static SyncResult syncForRoleFromLinkedIn(String linkedInUrl, String roleId) {
        if (String.isBlank(linkedInUrl)) {
            throw new AuraHandledException('LinkedIn URL is required.');
        }
        Id acctId;
        if (String.isNotBlank(roleId)) {
            try {
                Id parsed = (Id) roleId.trim();
                if (Schema.sObjectType.ConstituentRole.isAccessible()) {
                    List<ConstituentRole> roles = [SELECT PersonId FROM ConstituentRole WHERE Id = :parsed LIMIT 1];
                    if (!roles.isEmpty()) acctId = roles[0].PersonId;
                }
            } catch (Exception e) { /* fall through */ }
        }
        if (acctId == null) {
            try {
                User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
                acctId = u.AccountId;
            } catch (Exception e) { /* swallow */ }
        }
        if (acctId == null) {
            throw new AuraHandledException('No alumni Person Account is linked to this user yet — try again after the first profile save.');
        }
        try {
            return syncAccountSync(acctId, linkedInUrl.trim());

        } catch (KenLinkedInSyncException kse) {
            throw new AuraHandledException(kse.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static ProfilePreview fetchProfilePreview(String linkedInUrl) {
        try {
            Map<String, Object> profile = fetchProfileByUrl(linkedInUrl);
            ProfilePreview p = new ProfilePreview();
            p.profilePicUrl = (String) profile.get('profile_pic_url');
            List<Object> exps = (List<Object>) profile.get('experiences');
            List<Object> edus = (List<Object>) profile.get('education');
            List<Object> certs = (List<Object>) profile.get('certifications');
            p.experiencesCount    = exps  == null ? 0 : exps.size();
            p.educationCount      = edus  == null ? 0 : edus.size();
            p.certificationsCount = certs == null ? 0 : certs.size();
            p.rawJson = JSON.serialize(profile);
            return p;
        } catch (KenLinkedInSyncException kse) {
            throw new AuraHandledException(kse.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void syncAlumniBulk(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        enqueue(new Set<Id>(accountIds));
    }

    // ============================================================
    // Async wrapper (fire-and-forget)
    // ============================================================

    @future(callout=true)
    public static void enqueue(Set<Id> accountIds) {
        syncAccounts(accountIds);
    }

    // ============================================================
    // Sync service — direct Apex entry points
    // ============================================================

    /**
     * Synchronous single-account sync that PROPAGATES provider errors to the caller.
     * Used by the UI quick action so a 401, missing key or empty response surfaces
     * to the user instead of being swallowed by an @future. Performs all callouts
     * before any DML.
     */
    public static SyncResult syncAccountSync(Id accountId) {
        return syncAccountSync(accountId, null);
    }

    /**
     * @description overrideUrl lets a caller sync a URL that is not saved on the
     *              Account yet, so no DML has to run before the provider callout.
     */
    public static SyncResult syncAccountSync(Id accountId, String overrideUrl) {
        if (accountId == null) {
            throw new KenLinkedInSyncException('No alumnus selected.');
        }
        List<Account> accounts = [
            SELECT Id, PersonContactId, Linkedin_Profile_URL__c, Profile_Photo_URL__c
            FROM Account WHERE Id = :accountId AND IsPersonAccount = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new KenLinkedInSyncException('Alumnus record not found.');
        }
        Account acc = accounts[0];
        String rawUrl = String.isNotBlank(overrideUrl) ? overrideUrl : acc.Linkedin_Profile_URL__c;
        if (String.isBlank(rawUrl)) {
            throw new KenLinkedInSyncException('No LinkedIn URL set on this alumnus.');
        }
        rawUrl = rawUrl.trim();
        String urlKey = normalizeUrlKey(rawUrl);

        Map<String, Object> profile = callProviderStrict(rawUrl, urlKey);

        Blob imageBlob = null;
        String picUrl = str(profile.get('profile_pic_url'));
        if (String.isNotBlank(picUrl) && String.isBlank(acc.Profile_Photo_URL__c)) {
            imageBlob = fetchImageBlob(picUrl);
        }
        Map<Id, Blob> imageByAccount = imageBlob == null
            ? new Map<Id, Blob>()
            : new Map<Id, Blob>{ accountId => imageBlob };

        return storeProfiles(
            new Map<Id, Map<String, Object>>{ accountId => profile },
            new Map<Id, Account>{ accountId => acc },
            imageByAccount,
            new Map<Id, String>{ accountId => rawUrl }
        );
    }

    /**
     * Fetches the LinkedIn profile by URL and returns the raw provider response —
     * no DML, no Account required. Used by the onboarding "Import from LinkedIn"
     * dialog so the alumnus can validate their URL before the post-signup sync runs.
     */
    public static Map<String, Object> fetchProfileByUrl(String linkedInUrl) {
        if (String.isBlank(linkedInUrl)) {
            throw new KenLinkedInSyncException('LinkedIn URL is required.');
        }
        String urlKey = normalizeUrlKey(linkedInUrl);
        return callProviderStrict(linkedInUrl.trim(), urlKey);
    }

    /**
     * Syncs every Person Account in the set that has a LinkedIn URL.
     */
    public static void syncAccounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accountById = new Map<Id, Account>([
            SELECT Id, PersonContactId, Linkedin_Profile_URL__c, Profile_Photo_URL__c
            FROM Account
            WHERE Id IN :accountIds AND IsPersonAccount = true AND Linkedin_Profile_URL__c != null
        WITH USER_MODE
        ]);
        if (accountById.isEmpty()) {
            return;
        }

        Map<String, List<Id>> accountIdsByUrlKey = new Map<String, List<Id>>();
        Map<String, String> rawUrlByKey = new Map<String, String>();
        for (Account acc : accountById.values()) {
            String rawUrl = acc.Linkedin_Profile_URL__c.trim();
            String key = normalizeUrlKey(rawUrl);
            if (String.isBlank(key)) continue;
            if (!accountIdsByUrlKey.containsKey(key)) {
                accountIdsByUrlKey.put(key, new List<Id>());
                rawUrlByKey.put(key, rawUrl);
            }
            accountIdsByUrlKey.get(key).add(acc.Id);
        }
        if (rawUrlByKey.isEmpty()) return;

        // ---- PHASE 1: all callouts (no DML) ----
        Map<String, Map<String, Object>> profileByKey = new Map<String, Map<String, Object>>();
        List<String> urlKeys = new List<String>(rawUrlByKey.keySet());
        for (Integer i = 0; i < urlKeys.size(); i += MAX_URLS_PER_REQUEST) {
            Integer endIndex = Math.min(i + MAX_URLS_PER_REQUEST, urlKeys.size());
            List<String> rawChunk = new List<String>();
            for (Integer j = i; j < endIndex; j++) rawChunk.add(rawUrlByKey.get(urlKeys[j]));
            profileByKey.putAll(fetchProfiles(rawChunk));
        }

        Map<Id, Map<String, Object>> profileByAccount = new Map<Id, Map<String, Object>>();
        for (String key : accountIdsByUrlKey.keySet()) {
            Map<String, Object> profile = profileByKey.get(key);
            if (profile == null) continue;
            for (Id accId : accountIdsByUrlKey.get(key)) {
                profileByAccount.put(accId, profile);
            }
        }
        if (profileByAccount.isEmpty()) return;

        Map<Id, Blob> imageByAccount = new Map<Id, Blob>();
        for (Id accId : profileByAccount.keySet()) {
            Account existingAcct = accountById.get(accId);
            Boolean alreadyHasPhoto = existingAcct != null && String.isNotBlank(existingAcct.Profile_Photo_URL__c);
            String picUrl = str(profileByAccount.get(accId).get('profile_pic_url'));
            if (String.isNotBlank(picUrl) && !alreadyHasPhoto) {
                Blob imageBlob = fetchImageBlob(picUrl);
                if (imageBlob != null) imageByAccount.put(accId, imageBlob);
            }
        }

        // ---- PHASE 2: all DML ----
        storeProfiles(profileByAccount, accountById, imageByAccount, new Map<Id, String>());
    }

    // ============================================================
    // Private helpers
    // ============================================================

    private static Id resolveAccountId(String accountId, String email) {
        if (String.isNotBlank(accountId)) {
            List<Account> accounts = [
                SELECT Id FROM Account WHERE Id = :accountId AND IsPersonAccount = true
                WITH USER_MODE
                LIMIT 1
            ];
            return accounts.isEmpty() ? null : accounts[0].Id;
        }
        if (String.isNotBlank(email)) {
            List<Account> accounts = [
                SELECT Id FROM Account WHERE PersonEmail = :email AND IsPersonAccount = true
                WITH USER_MODE
                LIMIT 1
            ];
            return accounts.isEmpty() ? null : accounts[0].Id;
        }
        return null;
    }

    private static Map<String, Object> callProviderStrict(String rawUrl, String urlKey) {
        String connection = KenSettings.linkedInEnrichmentConnection();
        String endpoint = KenSettings.endpoint(connection, ENRICH_PATH);
        if (endpoint == null) {
            throw new KenLinkedInSyncException('LinkedIn enrichment is not configured. Set Ken_Alm_Org_Parameters__c.LinkedIn_Enrichment_Connection__c to a Named Credential and retry.');
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader(ENRICH_HEADER_NAME, ENRICH_HEADER_VALUE);
        request.setTimeout(120000);
        request.setBody(JSON.serialize(new Map<String, Object>{ 'urls' => new List<String>{ rawUrl } }));

        HttpResponse response = new Http().send(request);
        Integer status = response.getStatusCode();
        if (status < 200 || status >= 300) {
            String detail = '';
            if (status == 401 || status == 403) {
                detail = ' Check the credential behind LinkedIn_Enrichment_Connection__c.';
            } else if (status == 404) {
                detail = ' Verify the Named Credential URL behind LinkedIn_Enrichment_Connection__c.';
            } else if (status == 429) {
                detail = ' The provider is rate-limiting; try again shortly.';
            }
            throw new KenLinkedInSyncException('LinkedIn provider returned HTTP ' + status + '.' + detail);
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> results = payload == null ? null : (List<Object>) payload.get('results');
        if (results == null && payload != null) {
            results = new List<Object>{ new Map<String, Object>{ 'url' => rawUrl, 'profile' => payload } };
        }
        if (results == null) {
            throw new KenLinkedInSyncException('Provider returned an unexpected response (no results).');
        }
        for (Object resultObj : results) {
            Map<String, Object> result = asMap(resultObj);
            if (result == null) continue;
            String key = normalizeUrlKey((String) result.get('url'));
            if (String.isNotBlank(key) && key == urlKey) {
                Map<String, Object> profile = asMap(result.get('profile'));
                if (profile != null && !profile.isEmpty()) return profile;
            }
        }
        throw new KenLinkedInSyncException('Provider returned no LinkedIn profile for this URL.');
    }

    @TestVisible
    private static Map<String, Map<String, Object>> fetchProfiles(List<String> urls) {
        Map<String, Map<String, Object>> profileByKey = new Map<String, Map<String, Object>>();
        if (urls == null || urls.isEmpty()) return profileByKey;

        String endpoint = KenSettings.endpoint(
            KenSettings.linkedInEnrichmentConnection(),
            ENRICH_PATH
        );
        if (endpoint == null) {
            return profileByKey;
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader(ENRICH_HEADER_NAME, ENRICH_HEADER_VALUE);
        request.setTimeout(120000);
        request.setBody(JSON.serialize(new Map<String, Object>{ 'urls' => urls }));

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) return profileByKey;

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        List<Object> results = payload == null ? null : (List<Object>) payload.get('results');
        if (results == null && urls.size() == 1 && payload != null) {
            results = new List<Object>{ new Map<String, Object>{ 'url' => urls[0], 'profile' => payload } };
        }
        if (results == null) return profileByKey;

        for (Object resultObj : results) {
            Map<String, Object> result = asMap(resultObj);
            if (result == null) continue;
            String key = normalizeUrlKey((String) result.get('url'));
            Map<String, Object> profile = asMap(result.get('profile'));
            if (String.isNotBlank(key) && profile != null && !profile.isEmpty()) {
                profileByKey.put(key, profile);
            }
        }
        return profileByKey;
    }

    private static Blob fetchImageBlob(String imageUrl) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(imageUrl);
            req.setMethod('GET');
            req.setTimeout(60000);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) return null;
            Blob body = res.getBodyAsBlob();
            return (body != null && body.size() >= 100) ? body : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static SyncResult storeProfiles(
        Map<Id, Map<String, Object>> profileByAccount,
        Map<Id, Account> accountById,
        Map<Id, Blob> imageByAccount,
        Map<Id, String> urlByAccount
    ) {
        Set<Id> accountIds = profileByAccount.keySet();

        Map<Id, Id> contactIdByAccount = new Map<Id, Id>();
        for (Id accId : accountIds) {
            Account acc = accountById.get(accId);
            if (acc != null && acc.PersonContactId != null) {
                contactIdByAccount.put(accId, acc.PersonContactId);
            }
        }

        List<PersonEmployment> employmentsToArchive = new List<PersonEmployment>();
        for (PersonEmployment pe : [
            SELECT Id FROM PersonEmployment
            WHERE AccountId IN :accountIds AND LinkedIn_Sourced__c = true AND Is_Archived__c = false
        WITH USER_MODE
        ]) {
            employmentsToArchive.add(new PersonEmployment(Id = pe.Id, Is_Archived__c = true));
        }
        List<PersonEducation> educationToArchive = new List<PersonEducation>();
        for (PersonEducation ed : [
            SELECT Id FROM PersonEducation
            WHERE AccountId IN :accountIds AND LinkedIn_Sourced__c = true AND Is_Archived__c = false
        WITH USER_MODE
        ]) {
            educationToArchive.add(new PersonEducation(Id = ed.Id, Is_Archived__c = true));
        }
        List<Ken_Certificate_Details__c> certsToArchive = new List<Ken_Certificate_Details__c>();
        if (!contactIdByAccount.isEmpty()) {
            for (Ken_Certificate_Details__c cert : [
                SELECT Id FROM Ken_Certificate_Details__c
                WHERE Contact__c IN :contactIdByAccount.values() AND LinkedIn_Sourced__c = true AND Is_Archived__c = false
            WITH USER_MODE
            ]) {
                certsToArchive.add(new Ken_Certificate_Details__c(Id = cert.Id, Is_Archived__c = true));
            }
        }

        List<PersonEmployment> employmentsToInsert = new List<PersonEmployment>();
        List<PersonEducation> educationToInsert = new List<PersonEducation>();
        List<Ken_Certificate_Details__c> certsToInsert = new List<Ken_Certificate_Details__c>();
        List<Account> accountsToUpdate = new List<Account>();

        for (Id accId : accountIds) {
            Map<String, Object> profile = profileByAccount.get(accId);
            Id contactId = contactIdByAccount.get(accId);

            for (Object expObj : asList(profile.get('experiences'))) {
                Map<String, Object> exp = asMap(expObj);
                if (exp == null) continue;
                Date startDate = toDate(exp.get('starts_at'));
                Date endDate = toDate(exp.get('ends_at'));
                String company = truncateText(str(exp.get('company')), 225);
                PersonEmployment emp = new PersonEmployment(
                    Name = String.isNotBlank(company) ? company.left(80) : 'Employer',
                    AccountId = accId,
                    Designation__c = truncateText(str(exp.get('title')), 225),
                    Company_Name__c = company,
                    Location__c = truncateText(str(exp.get('location')), 255),
                    StartDate = startDate,
                    EndDate = endDate,
                    Currently_Employed__c = (startDate != null && endDate == null),
                    Is_Archived__c = false,
                    LinkedIn_Sourced__c = true
                );
                if (contactId != null) emp.RelatedPersonId = contactId;
                employmentsToInsert.add(emp);
            }

            for (Object eduObj : asList(profile.get('education'))) {
                Map<String, Object> edu = asMap(eduObj);
                if (edu == null) continue;
                Date startDate = toDate(edu.get('starts_at'));
                Date endDate = toDate(edu.get('ends_at'));
                String degree = truncateText(str(edu.get('degree_name')), 255);
                PersonEducation eduRow = new PersonEducation(
                    Name = String.isNotBlank(degree) ? degree.left(80) : 'Degree',
                    AccountId = accId,
                    Institute_Name__c = truncateText(str(edu.get('school')), 255),
                    Degree_Name__c = degree,
                    Grade__c = truncateText(str(edu.get('grade')), 40),
                    StartDate = startDate,
                    EndDate = endDate,
                    Year_of_Completion__c = endDate != null ? String.valueOf(endDate.year()) : null,
                    Is_Archived__c = false,
                    LinkedIn_Sourced__c = true
                );
                if (contactId != null) eduRow.ContactId = contactId;
                educationToInsert.add(eduRow);
            }

            if (contactId != null) {
                for (Object certObj : asList(profile.get('certifications'))) {
                    Map<String, Object> cert = asMap(certObj);
                    if (cert == null) continue;
                    certsToInsert.add(new Ken_Certificate_Details__c(
                        Contact__c = contactId,
                        Uploaded_File_Name__c = truncateText(str(cert.get('name')), 255),
                        Award_Id__c = truncateText(str(cert.get('license_number')), 255),
                        Qualification_URL__c = str(cert.get('url')),
                        Issue_Date__c = toDate(cert.get('starts_at')),
                        Expiration_Date__c = toDate(cert.get('ends_at')),
                        LinkedIn_Sourced__c = true,
                        Is_Archived__c = false
                    ));
                }
            }

            Account acctUpdate = new Account(Id = accId, Last_LinkedIn_Sync__c = System.now());
            if (urlByAccount != null && String.isNotBlank(urlByAccount.get(accId))) {
                acctUpdate.Linkedin_Profile_URL__c = urlByAccount.get(accId);
            }
            accountsToUpdate.add(acctUpdate);
        }

        if (!employmentsToArchive.isEmpty()) {
            if (!Schema.sObjectType.PersonEmployment.isUpdateable()) {
                throw new KenCrudException('PersonEmployment is not updateable by the current user.');
            }
            Database.update(employmentsToArchive, false);
        }
        if (!educationToArchive.isEmpty()) {
            if (!Schema.sObjectType.PersonEducation.isUpdateable()) {
                throw new KenCrudException('PersonEducation is not updateable by the current user.');
            }
            Database.update(educationToArchive, false);
        }
        if (!certsToArchive.isEmpty()) {
            if (!Schema.sObjectType.Ken_Certificate_Details__c.isUpdateable()) {
                throw new KenCrudException('Ken_Certificate_Details__c is not updateable by the current user.');
            }
            Database.update(certsToArchive, false);
        }

        SyncResult result = new SyncResult();
        result.jobsSaved           = countSaved(Database.insert(employmentsToInsert, false), result);
        result.educationSaved      = countSaved(Database.insert(educationToInsert, false), result);
        result.certificationsSaved = countSaved(Database.insert(certsToInsert, false), result);
        if (!accountsToUpdate.isEmpty()) {
            if (!Schema.sObjectType.Account.isUpdateable()) {
                throw new KenCrudException('Account is not updateable by the current user.');
            }
            Database.update(accountsToUpdate, false);
        }

        storeProfilePhotos(imageByAccount);
        return result;
    }

    /**
     * @description Counts the rows that actually committed and keeps the first
     *              failure message. allOrNone = false stops one bad row from losing
     *              the whole batch, but the results MUST be read - discarding them
     *              is what let a sync report rows it never wrote.
     */
    private static Integer countSaved(List<Database.SaveResult> results, SyncResult result) {
        Integer saved = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                saved++;
                continue;
            }
            result.rowsFailed++;
            if (String.isBlank(result.firstError) && !sr.getErrors().isEmpty()) {
                result.firstError = sr.getErrors()[0].getStatusCode() + ': ' + sr.getErrors()[0].getMessage();
            }
        }
        return saved;
    }

    /**
     * @description Stores the LinkedIn photo as a Salesforce public (ContentDistribution)
     *              URL on Account.Profile_Photo_URL__c, but ONLY for people who have no
     *              photo yet - an existing picture is never overwritten, because the one
     *              the alumnus uploaded outranks whatever LinkedIn happens to hold. The
     *              callers already skip the image download for these accounts; this is the
     *              second guard that also covers the bulk path.
     */
    private static void storeProfilePhotos(Map<Id, Blob> imageByAccount) {
        if (imageByAccount == null || imageByAccount.isEmpty()) return;

        Set<Id> needsPhoto = new Set<Id>();
        for (Account a : [
            SELECT Id, Profile_Photo_URL__c FROM Account WHERE Id IN :imageByAccount.keySet()
        WITH USER_MODE
        ]) {
            if (String.isBlank(a.Profile_Photo_URL__c)) needsPhoto.add(a.Id);
        }
        if (needsPhoto.isEmpty()) return;

        Map<Id, String> publicUrlByAccount = new Map<Id, String>();
        for (Id accId : needsPhoto) {
            try {
                ContentVersion cv = new ContentVersion(
                    Title = 'LinkedIn Profile ' + accId,
                    PathOnClient = 'linkedin_profile_' + accId + '.jpg',
                    VersionData = imageByAccount.get(accId),
                    IsMajorVersion = false
                );
                Database.insert(cv, true, AccessLevel.USER_MODE);
                ContentDistribution cd = new ContentDistribution(
                    Name = 'LinkedIn Profile ' + accId,
                    ContentVersionId = cv.Id,
                    PreferencesAllowViewInBrowser = true,
                    PreferencesLinkLatestVersion = true,
                    PreferencesNotifyOnVisit = false,
                    PreferencesPasswordRequired = false
                );
                Database.insert(cd, false, AccessLevel.USER_MODE);
                ContentDistribution stored = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id WITH SYSTEM_MODE LIMIT 1];
                if (String.isNotBlank(stored.ContentDownloadUrl)) {
                    publicUrlByAccount.put(accId, stored.ContentDownloadUrl);
                }
            } catch (Exception ex) {
                // Image storage failures must never block the data sync.
            }
        }
        if (publicUrlByAccount.isEmpty()) return;
        List<Account> accountsToUpdate = new List<Account>();
        for (Id accId : publicUrlByAccount.keySet()) {
            accountsToUpdate.add(new Account(Id = accId, Profile_Photo_URL__c = publicUrlByAccount.get(accId)));
        }
        if (!accountsToUpdate.isEmpty()) {
            if (!Schema.sObjectType.Account.isUpdateable()) {
                throw new KenCrudException('Account is not updateable by the current user.');
            }
            Database.update(accountsToUpdate, false);
        }
    }

    // ----------------------------------------------------------------------
    private static String normalizeUrlKey(String url) {
        if (String.isBlank(url)) return null;
        String normalized = url.trim().toLowerCase();
        Integer q = normalized.indexOf('?');
        if (q > -1) { normalized = normalized.substring(0, q); }
        Integer h = normalized.indexOf('#');
        if (h > -1) { normalized = normalized.substring(0, h); }
        while (normalized.endsWith('/')) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized;
    }

    private static Map<String, Object> asMap(Object value) {
        if (value == null) return null;
        if (value instanceof Map<String, Object>) return (Map<String, Object>) value;
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(value));
    }

    private static List<Object> asList(Object value) {
        if (value instanceof List<Object>) return (List<Object>) value;
        return new List<Object>();
    }

    private static String str(Object value) {
        if (value == null) return null;
        String s = String.valueOf(value).trim();
        return String.isBlank(s) ? null : s;
    }

    private static String truncateText(String value, Integer maxLen) {
        if (value == null) return null;
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }

    private static Date toDate(Object value) {
        Map<String, Object> dateMap = asMap(value);
        if (dateMap == null || dateMap.isEmpty()) return null;
        Integer day = toInt(dateMap.get('day'));
        Integer month = toInt(dateMap.get('month'));
        Integer year = toInt(dateMap.get('year'));
        if (year == null || year <= 0) return null;
        if (month == null || month <= 0) month = 1;
        if (day == null || day <= 0) day = 1;
        try {
            return Date.newInstance(year, month, day);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Integer toInt(Object value) {
        if (value == null) return null;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Decimal) return ((Decimal) value).intValue();
        if (value instanceof Long) return ((Long) value).intValue();
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }
}