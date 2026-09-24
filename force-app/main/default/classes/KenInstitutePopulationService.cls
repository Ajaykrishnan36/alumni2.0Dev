/**
 * @description Denormalises the institute of an alumnus onto every related alumni record so that
 *              institute-based sharing rules have a real, filterable field to work with.
 *              ConstituentRole.Institution_Name__c is a formula and formula fields can be used
 *              neither in criteria-based sharing rules nor in SOQL GROUP BY, which is why the
 *              value is stamped into a stored Text field instead.
 *
 *              Values are stored as the provider's 18-character record id, bare for one institute
 *              and semicolon separated for several, which is what a sharing rule filters on with
 *              "contains 001Ta00000V7FOgIAN". The rule is still SHARED TO a readable group
 *              (Alumni_Institute_KJSPOLY); only the matched value is an id.
 *
 *              Ids are used rather than short codes because every id is exactly 18 characters and
 *              none contains the delimiter, so no token can be a substring of another and a match
 *              cannot straddle a token boundary. Short codes made that a rule someone had to
 *              remember: "KJSIT" sits inside "KJSITI", and the over-match was silent. Ids also
 *              survive an institute being renamed, which the source data does routinely.
 *
 *              The institute token is read from one configurable field path, so changing which
 *              field on the provider carries the token is a one-line edit.
 *
 *              The field is Institute_Name__c on every object except Account, which uses
 *              Institution_Name__c because the Admissions module already owns Institute_Name__c
 *              on Account as a picklist in the KJS orgs.
 */
public without sharing class KenInstitutePopulationService {

    /**
     * Field path, relative to LearningProgramPlan, that yields the institute token.
     * This is the single swap point for what identifies an institute: point it at
     * 'Provider.Name' for names, or at any other provider field, and the whole stack follows.
     *
     * It reads the provider's record id rather than a human-readable code, because criteria
     * sharing rules match with CONTAINS on this packed value. Every id is exactly 18 characters
     * and no id contains the delimiter, so no token can ever be a substring of another and a
     * match cannot straddle a token boundary. A shorter, variable-length code cannot offer that:
     * 'KJSIT' sits inside 'KJSITI' and would silently over-match. The 18-character form is also
     * required rather than the 15-character one, since sharing-rule CONTAINS is case-insensitive
     * and only the three-character suffix distinguishes ids that differ by capitalisation.
     *
     * Provider ids are never written by this service, so an institution's own record is never
     * touched by the fan-out; automation only writes to Accounts reached through
     * ConstituentRole.PersonId.
     */
    private static final String INSTITUTE_SOURCE_PATH = 'ProviderId';

    public static final String DELIMITER = ';';
    public static final Integer MAX_LENGTH = 255;

    /**
     * Queries the stamp must be able to make without competing with the business logic around it.
     * One resolution needs at most four; the rest is margin.
     */
    private static final Integer QUERY_HEADROOM = 12;

    /**
     * Field carrying the token on every object except Account, which uses Institution_Name__c.
     */
    private static final String FIELD = KenNamespaceUtil.qualifyCustom('Institute_Name__c');

    private static final String ALUMNI_ROLE_TYPE = 'Alumni';

    /**
     * Set by bulk-import style callers that will run KenInstitutePopulationBatch themselves once
     * the load finishes. Suppresses the asynchronous fan-out only; the synchronous before-trigger
     * stamp on ConstituentRole always runs because it costs one SOQL and no DML.
     */
    public static Boolean skipFanout = false;

    /**
     * Guards against the Account update issued by the fan-out re-entering this service.
     */
    private static Boolean fanoutRunning = false;

    /**
     * The creating user's institute, resolved at most once per transaction.
     */
    @TestVisible
    private static String userInstitute;
    @TestVisible
    private static Boolean userInstituteResolved = false;

    /**
     * Proves the save-never-blocks guarantee from a test; there is no other way to force a
     * failure inside the stamp.
     */
    @TestVisible
    private static Boolean failForTest = false;

    // ---------------------------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------------------------

    /**
     * @description One entry per object that carries Institute_Name__c. Order matters: objects
     *              that copy from a parent must be declared after the parent they read from.
     */
    private class ObjectConfig {
        String objectName;
        String roleField;
        List<String> personFields = new List<String>();
        String parentField;
        String parentObject;
        String planField;
        Boolean allowUserFallback = false;

        ObjectConfig(String objectName) {
            this.objectName = KenNamespaceUtil.qualifyCustom(objectName);
        }
        ObjectConfig role(String f) {
            this.roleField = KenNamespaceUtil.qualifyCustom(f);
            return this;
        }
        ObjectConfig person(String f) {
            this.personFields.add(KenNamespaceUtil.qualifyCustom(f));
            return this;
        }
        ObjectConfig parent(String f, String parentObjectName) {
            this.parentField = KenNamespaceUtil.qualifyCustom(f);
            this.parentObject = KenNamespaceUtil.qualifyCustom(parentObjectName);
            return this;
        }
        ObjectConfig plan(String f) {
            this.planField = KenNamespaceUtil.qualifyCustom(f);
            return this;
        }
        ObjectConfig userFallback() {
            this.allowUserFallback = true;
            return this;
        }
    }

    private static final List<ObjectConfig> CONFIGS = new List<ObjectConfig>{
        new ObjectConfig('Ken_Event_Master__c').role('Constituent_Role__c').person('Person_Account__c').userFallback(),
        new ObjectConfig('Ken_Survey__c').role('Constituent_Role__c').person('Survey_Created_By__c').userFallback(),
        new ObjectConfig('Ken_Fundraise__c').role('Constituent_Role__c').userFallback(),
        new ObjectConfig('Ken_Business_Directory__c').role('Constituent_Role__c').person('Business_Account__c').userFallback(),
        new ObjectConfig('Ken_Event_Booking__c').role('Constituent_Role__c').person('Person_Account__c'),
        new ObjectConfig('Ken_Group__c').person('Created_By__c').userFallback(),
        new ObjectConfig('Ken_Group_Member__c').person('Member__c'),
        new ObjectConfig('Ken_Events_Sessions_Enrollment__c').person('Person_Account__c'),
        new ObjectConfig('Ken_Mentorship__c').person('Mentor__c').person('Mentee__c'),
        new ObjectConfig('Ken_Network_Connection__c').person('Initiator__c').person('Recipient__c'),
        new ObjectConfig('Ken_Notification__c').person('Recipient__c').userFallback(),
        new ObjectConfig('Ken_Achievement__c').person('Person_Account__c'),
        new ObjectConfig('Ken_Address__c').person('Person_Account__c'),
        new ObjectConfig('Ken_Alumni_Preferences__c').person('Person_Account__c'),
        new ObjectConfig('Ken_Schedule_Sessions__c').parent('Event_Reference__c', 'Ken_Event_Master__c'),
        new ObjectConfig('ConstituentRole').plan('Program_Plan__c'),
        new ObjectConfig('Lead').plan('Program_Plan__c').userFallback()
    };

    /**
     * Program plan is the institute source of record, not a denormalised copy, so a plan-anchored
     * object is stamped at insert and never touched by the person fan-out.
     */
    private static Map<String, ObjectConfig> configByObject {
        get {
            if (configByObject == null) {
                configByObject = new Map<String, ObjectConfig>();
                for (ObjectConfig config : CONFIGS) {
                    configByObject.put(config.objectName.toLowerCase(), config);
                }
            }
            return configByObject;
        }
        set;
    }

    // ---------------------------------------------------------------------------------------
    // Trigger entry points
    // ---------------------------------------------------------------------------------------

    /**
     * @description The one call every before-trigger makes, whatever the object:
     *              KenInstitutePopulationService.stampInstitute(Trigger.new, Trigger.oldMap).
     *
     *              Resolves the institute from the record's own anchor and writes it in memory,
     *              so a record is visible to its institute's sharing rules the instant it is
     *              created rather than whenever the next fan-out happens to reach it.
     *
     *              Anchors are tried in order and the first one that is populated decides the
     *              answer outright, even if that anchor turns out to carry no institute:
     *              ConstituentRole, program plan, parent record, person Account. Only a record
     *              with no populated anchor at all falls back to the creating user's own
     *              institute, and only on insert, for the objects that opt into it - which is
     *              what gives admin-console records an institute they could never otherwise have.
     *
     *              Costs at most one SOQL per anchor type per invocation regardless of how many
     *              records are in the trigger, does no DML, and cannot recurse.
     *
     *              Sharing is a denormalisation, never a precondition of the business record, so
     *              nothing in here is allowed to stop a save: every failure is swallowed and
     *              logged, and the record goes through unstamped. An unstamped record is visible
     *              to its owner and to admins, and self-heals on the next save because a blank
     *              institute always makes a record a candidate again.
     *
     * @param records Trigger.new
     * @param oldMap  Trigger.oldMap, or null on insert
     */
    public static void stampInstitute(List<SObject> records, Map<Id, SObject> oldMap) {

        if (records == null || records.isEmpty()) {
            return;
        }

        try {
            resolveAndStamp(records, oldMap);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenInstitutePopulationService left ' + records.size() + ' '
                + records[0].getSObjectType() + ' record(s) unstamped: '
                + e.getTypeName() + ': ' + e.getMessage()
                + ' (line ' + e.getLineNumber() + ')');
        }
    }

    /**
     * @description The resolution itself. Never call this from a trigger - go through
     *              stampInstitute so a failure cannot reach the record being saved.
     */
    private static void resolveAndStamp(List<SObject> records, Map<Id, SObject> oldMap) {

        if (failForTest) {
            throw new KenCustomException('Simulated institute stamp failure');
        }

        String objectName = String.valueOf(records[0].getSObjectType());
        ObjectConfig config = configByObject.get(objectName.toLowerCase());

        if (config == null || !hasInstituteField(objectName)) {
            return;
        }

        List<SObject> candidates = candidatesToStamp(records, oldMap, config);
        if (candidates.isEmpty()) {
            return;
        }

        // A LimitException cannot be caught, so the only way to keep the stamp from being the
        // thing that tips a busy transaction over the SOQL ceiling is to stand down before it.
        if (Limits.getLimitQueries() - Limits.getQueries() < QUERY_HEADROOM) {
            System.debug(LoggingLevel.ERROR,
                'KenInstitutePopulationService skipped stamping ' + candidates.size() + ' '
                + objectName + ' record(s): only ' + (Limits.getLimitQueries() - Limits.getQueries())
                + ' SOQL queries left in this transaction.');
            return;
        }

        Set<Id> roleIds = new Set<Id>();
        Set<Id> planIds = new Set<Id>();
        Set<Id> parentIds = new Set<Id>();
        Set<Id> personIds = new Set<Id>();

        for (SObject record : candidates) {
            collectId(roleIds, record, config.roleField);
            collectId(planIds, record, config.planField);
            collectId(parentIds, record, config.parentField);
            for (String personField : config.personFields) {
                collectId(personIds, record, personField);
            }
        }

        Map<Id, String> tokenByRole = tokensByRole(roleIds);
        Map<Id, String> tokenByPlan = resolveTokensByProgramPlan(planIds);
        Map<Id, String> tokenByParent = tokensByParent(config, parentIds);
        Map<Id, String> tokenByPerson = tokensByPerson(personIds);

        Boolean isInsert = oldMap == null;

        for (SObject record : candidates) {
            record.put(FIELD, resolveToken(
                record, config, isInsert, tokenByRole, tokenByPlan, tokenByParent, tokenByPerson
            ));
        }
    }

    /**
     * @description Narrows the trigger set to the records worth resolving. On insert that is any
     *              record the caller did not already give an institute to, so an explicit choice
     *              made in the UI is never second-guessed. On update it is the records whose
     *              anchor moved, plus any left blank so a later edit self-heals them.
     */
    private static List<SObject> candidatesToStamp(
        List<SObject> records,
        Map<Id, SObject> oldMap,
        ObjectConfig config
    ) {
        List<SObject> candidates = new List<SObject>();

        for (SObject record : records) {

            if (oldMap == null) {
                if (String.isBlank((String) record.get(FIELD))) {
                    candidates.add(record);
                }
                continue;
            }

            SObject previous = oldMap.get((Id) record.get('Id'));

            if (previous == null
                || String.isBlank((String) record.get(FIELD))
                || anchorChanged(record, previous, config)) {
                candidates.add(record);
            }
        }
        return candidates;
    }

    private static Boolean anchorChanged(SObject record, SObject previous, ObjectConfig config) {

        List<String> anchors = new List<String>(config.personFields);
        if (String.isNotBlank(config.roleField)) {
            anchors.add(config.roleField);
        }
        if (String.isNotBlank(config.planField)) {
            anchors.add(config.planField);
        }
        if (String.isNotBlank(config.parentField)) {
            anchors.add(config.parentField);
        }

        for (String anchor : anchors) {
            if (record.get(anchor) != previous.get(anchor)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Applies the anchor precedence for a single record. An anchor that is populated
     *              settles the answer even when it carries no institute, which is what stops a
     *              record belonging to a code-less role from silently inheriting someone else's.
     */
    private static String resolveToken(
        SObject record,
        ObjectConfig config,
        Boolean isInsert,
        Map<Id, String> tokenByRole,
        Map<Id, String> tokenByPlan,
        Map<Id, String> tokenByParent,
        Map<Id, String> tokenByPerson
    ) {
        Id roleId = lookupId(record, config.roleField);
        if (roleId != null) {
            return tokenByRole.get(roleId);
        }

        Id planId = lookupId(record, config.planField);
        if (planId != null) {
            return tokenByPlan.get(planId);
        }

        Id parentId = lookupId(record, config.parentField);
        if (parentId != null) {
            return tokenByParent.get(parentId);
        }

        Set<String> union = new Set<String>();
        Boolean personAnchored = false;

        for (String personField : config.personFields) {
            Id personId = lookupId(record, personField);
            if (personId == null) {
                continue;
            }
            personAnchored = true;
            union.addAll(unwrapAll(tokenByPerson.get(personId)));
        }

        if (personAnchored) {
            return pack(union).value;
        }

        return (isInsert && config.allowUserFallback) ? currentUserInstitute() : null;
    }

    /**
     * @description The creating user's own institute, used only when a record has no alumni to
     *              inherit from. Internal staff carry it on User.Institute_Code__c; a portal user
     *              is resolved through their Contact to the person Account the fan-out maintains.
     *              Resolved once per transaction and never allowed to throw, because a guest user
     *              creating a Lead may not be able to read either object.
     */
    @TestVisible
    private static String currentUserInstitute() {

        if (userInstituteResolved) {
            return userInstitute;
        }
        userInstituteResolved = true;

        try {
            Id userId = UserInfo.getUserId();
            Boolean hasCode = hasField('User', 'Institute_Code__c');

            List<String> fields = new List<String>{ 'ContactId' };
            if (hasCode) {
                fields.add('Institute_Code__c');
            }

            List<SObject> users = Database.query(
                'SELECT ' + String.join(fields, ', ') + ' FROM User WHERE Id = :userId'
            );
            if (users.isEmpty()) {
                return userInstitute;
            }

            if (hasCode) {
                String code = (String) users[0].get(KenNamespaceUtil.qualifyCustom('Institute_Code__c'));
                if (String.isNotBlank(code)) {
                    userInstitute = pack(providerIdsForCodes(unwrapAll(code))).value;
                    if (String.isNotBlank(userInstitute)) {
                        return userInstitute;
                    }
                }
            }

            Id contactId = (Id) users[0].get('ContactId');
            if (contactId == null) {
                return userInstitute;
            }

            for (Contact contact : [
                SELECT Account.Institution_Name__c
                FROM Contact
                WHERE Id = :contactId AND AccountId != NULL
            WITH SYSTEM_MODE
            ]) {
                userInstitute = contact.Account.Institution_Name__c;
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'KenInstitutePopulationService could not resolve the running user institute: ' + e.getMessage());
        }

        return userInstitute;
    }

    /**
     * @description Translates the human-readable institute codes an admin types into
     *              User.Institute_Code__c to the provider record ids this service actually stores.
     *              The code stays on the User because nobody should be hand-copying an 18-character
     *              id, and the institution Account carries the same code in Institution_Name__c,
     *              which makes it the lookup key. Unknown codes are dropped rather than stamped,
     *              so a typo leaves a record unstamped instead of mis-shared.
     */
    private static Set<String> providerIdsForCodes(List<String> codes) {

        Set<String> providerIds = new Set<String>();
        if (codes == null || codes.isEmpty()) {
            return providerIds;
        }

        Set<String> wanted = new Set<String>();
        for (String code : codes) {
            if (String.isNotBlank(code)) {
                wanted.add(code.trim());
            }
        }
        if (wanted.isEmpty()) {
            return providerIds;
        }

        for (Account provider : [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = FALSE
            AND Institution_Name__c IN :wanted
        WITH SYSTEM_MODE
        ]) {
            providerIds.add(String.valueOf(provider.Id));
        }
        return providerIds;
    }

    private static Map<Id, String> tokensByRole(Set<Id> roleIds) {

        Map<Id, String> result = new Map<Id, String>();
        if (roleIds.isEmpty()) {
            return result;
        }

        for (ConstituentRole role : [
            SELECT Id, Institute_Name__c FROM ConstituentRole WHERE Id IN :roleIds
        WITH SYSTEM_MODE
        ]) {
            result.put(role.Id, unwrapSingle(role.Institute_Name__c));
        }
        return result;
    }

    private static Map<Id, String> tokensByPerson(Set<Id> personIds) {

        Map<Id, String> result = new Map<Id, String>();
        if (personIds.isEmpty()) {
            return result;
        }

        for (Account account : [
            SELECT Id, Institution_Name__c FROM Account WHERE Id IN :personIds
        WITH SYSTEM_MODE
        ]) {
            result.put(account.Id, account.Institution_Name__c);
        }
        return result;
    }

    private static Map<Id, String> tokensByParent(ObjectConfig config, Set<Id> parentIds) {

        Map<Id, String> result = new Map<Id, String>();
        if (parentIds.isEmpty() || String.isBlank(config.parentObject) || !hasInstituteField(config.parentObject)) {
            return result;
        }

        String soql = 'SELECT Id, ' + FIELD + ' FROM ' + config.parentObject + ' WHERE Id IN :parentIds';

        for (SObject parent : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'parentIds' => parentIds },
                AccessLevel.SYSTEM_MODE)) {
            result.put((Id) parent.get('Id'), (String) parent.get(FIELD));
        }
        return result;
    }

    private static void collectId(Set<Id> target, SObject record, String fieldName) {
        Id value = lookupId(record, fieldName);
        if (value != null) {
            target.add(value);
        }
    }

    private static Id lookupId(SObject record, String fieldName) {
        return String.isBlank(fieldName) ? null : (Id) record.get(fieldName);
    }

    private static Boolean hasInstituteField(String objectName) {
        return hasField(objectName, FIELD);
    }

    private static Boolean hasField(String objectName, String fieldName) {
        Schema.SObjectType sot = KenNamespaceUtil.resolveSObjectType(objectName);
        return sot != null && KenNamespaceUtil.hasField(sot.getDescribe().fields.getMap(), fieldName);
    }

    /**
     * @description Stamps each ConstituentRole's own single institute in memory. Safe for
     *              before insert and before update: one SOQL, no DML, no recursion.
     * @param roles ConstituentRole records from Trigger.new
     */
    public static void stampConstituentRoles(List<ConstituentRole> roles) {

        if (roles == null || roles.isEmpty()) {
            return;
        }

        Set<Id> planIds = new Set<Id>();
        for (ConstituentRole role : roles) {
            if (role.Program_Plan__c != null) {
                planIds.add(role.Program_Plan__c);
            }
        }

        Map<Id, String> tokenByPlan = resolveTokensByProgramPlan(planIds);

        for (ConstituentRole role : roles) {
            String token = role.Program_Plan__c == null ? null : tokenByPlan.get(role.Program_Plan__c);
            role.Institute_Name__c = String.isBlank(token) ? null : token;
        }
    }

    /**
     * @description Fans the institute change out to the person Account and every related record.
     *              Called from the ConstituentRole after triggers when the stamped value changed.
     * @param accountIds person Account ids whose ConstituentRole set changed
     */
    public static void enqueueFanout(Set<Id> accountIds) {

        if (skipFanout || fanoutRunning || accountIds == null || accountIds.isEmpty()) {
            return;
        }

        // Runs inside the saving transaction, so a full queueable slot or a failure downstream
        // would otherwise roll back the record that triggered it.
        try {
            if (System.isQueueable() || System.isBatch() || System.isFuture()) {
                recalcForAccounts(accountIds);
                return;
            }
            System.enqueueJob(new KenInstitutePopulationQueueable(accountIds));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenInstitutePopulationService could not fan out to ' + accountIds.size()
                + ' account(s): ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }

    // ---------------------------------------------------------------------------------------
    // Public re-sync entry points
    // ---------------------------------------------------------------------------------------

    /**
     * @description Recalculates everything for the people behind the supplied ConstituentRoles.
     *              The roles themselves are re-stamped first, then their people are fanned out.
     * @param roleIds ConstituentRole ids
     * @return number of person Accounts recalculated
     */
    public static Integer recalcByConstituentRole(Set<Id> roleIds) {

        if (roleIds == null || roleIds.isEmpty()) {
            return 0;
        }

        List<ConstituentRole> roles = [
            SELECT Id, PersonId, Program_Plan__c, Institute_Name__c
            FROM ConstituentRole
            WHERE Id IN :roleIds
        WITH SYSTEM_MODE
        ];

        Set<Id> accountIds = new Set<Id>();
        for (ConstituentRole role : roles) {
            if (role.PersonId != null) {
                accountIds.add(role.PersonId);
            }
        }

        restampRoles(roles);
        return recalcForAccounts(accountIds);
    }

    /**
     * @description Recalculates everything for the supplied people. Accepts person Account ids or
     *              Contact ids in the same set; Contact ids are resolved to their person Account.
     * @param personIds Account and/or Contact ids
     * @return number of person Accounts recalculated
     */
    public static Integer recalcByAccount(Set<Id> personIds) {

        if (personIds == null || personIds.isEmpty()) {
            return 0;
        }

        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (Id personId : personIds) {
            if (personId == null) {
                continue;
            }
            Schema.SObjectType sot = personId.getSObjectType();
            if (sot == Contact.SObjectType) {
                contactIds.add(personId);
            } else if (sot == Account.SObjectType) {
                accountIds.add(personId);
            } else if (sot == ConstituentRole.SObjectType) {
                return recalcByConstituentRole(personIds);
            }
        }

        if (!contactIds.isEmpty()) {
            for (Contact contact : [SELECT AccountId FROM Contact WHERE Id IN :contactIds AND AccountId != NULL WITH SYSTEM_MODE]) {
                accountIds.add(contact.AccountId);
            }
        }

        Set<Id> roleIds = new Set<Id>();
        for (ConstituentRole role : [
            SELECT Id FROM ConstituentRole WHERE PersonId IN :accountIds
        WITH SYSTEM_MODE
        ]) {
            roleIds.add(role.Id);
        }
        if (!roleIds.isEmpty()) {
            restampRoles([
                SELECT Id, PersonId, Program_Plan__c, Institute_Name__c
                FROM ConstituentRole
                WHERE Id IN :roleIds
            WITH SYSTEM_MODE
            ]);
        }

        return recalcForAccounts(accountIds);
    }

    // ---------------------------------------------------------------------------------------
    // Core
    // ---------------------------------------------------------------------------------------

    /**
     * @description Recomputes Account.Institution_Name__c from every Alumni ConstituentRole of the
     *              person, then pushes the result across every configured related object.
     *              Runs entirely synchronously so a Batch execute can call it directly.
     *              Only person Accounts are written, which is what keeps an institution Account's
     *              own token safe when a caller passes it in by mistake.
     * @param accountIds person Account ids
     * @return number of person Accounts processed
     */
    public static Integer recalcForAccounts(Set<Id> accountIds) {

        if (accountIds == null || accountIds.isEmpty()) {
            return 0;
        }

        Boolean outermost = !fanoutRunning;
        fanoutRunning = true;

        try {
            Map<Id, String> tokenByRole = new Map<Id, String>();
            Map<Id, Set<String>> tokensByAccount = new Map<Id, Set<String>>();
            Set<Id> roleIds = new Set<Id>();

            for (Id accountId : accountIds) {
                tokensByAccount.put(accountId, new Set<String>());
            }

            for (ConstituentRole role : [
                SELECT Id, PersonId, RoleType, Institute_Name__c
                FROM ConstituentRole
                WHERE PersonId IN :accountIds
            WITH SYSTEM_MODE
            ]) {
                roleIds.add(role.Id);
                String token = unwrapSingle(role.Institute_Name__c);
                if (String.isBlank(token)) {
                    continue;
                }
                tokenByRole.put(role.Id, token);
                if (role.RoleType == ALUMNI_ROLE_TYPE) {
                    tokensByAccount.get(role.PersonId).add(token);
                }
            }

            Map<Id, String> packedByAccount = new Map<Id, String>();
            List<Account> accountUpdates = new List<Account>();

            for (Account account : [
                SELECT Id, Institution_Name__c
                FROM Account
                WHERE Id IN :accountIds AND IsPersonAccount = TRUE
            WITH SYSTEM_MODE
            ]) {
                PackResult packed = pack(tokensByAccount.get(account.Id));
                packedByAccount.put(account.Id, packed.value);

                if (packed.truncated) {
                    System.debug(LoggingLevel.ERROR,
                        'KenInstitutePopulationService: institute list exceeded ' + MAX_LENGTH
                        + ' characters for Account ' + account.Id
                        + '. Sharing for the dropped institutes will be incomplete.');
                }

                if (account.Institution_Name__c != packed.value) {
                    accountUpdates.add(new Account(Id = account.Id, Institution_Name__c = packed.value));
                }
            }

            saveAll(accountUpdates, 'Account');

            Map<String, Map<Id, String>> valuesByObject = new Map<String, Map<Id, String>>();
            for (ObjectConfig config : CONFIGS) {
                fanOut(config, accountIds, roleIds, tokenByRole, packedByAccount, valuesByObject);
            }

            return accountIds.size();

        } finally {
            if (outermost) {
                fanoutRunning = false;
            }
        }
    }

    /**
     * @description Recomputes and writes Institute_Name__c for one configured object.
     *              Records already holding the correct value are never included in the DML.
     *
     *              A record anchored on a ConstituentRole takes that role's token and nothing else,
     *              even when the token is blank. If the anchoring role belongs to someone outside
     *              the current chunk the record is skipped, so a chunk never clobbers a value that
     *              another chunk owns. Only records with no anchoring role fall back to the union
     *              of their person's institutes.
     */
    private static void fanOut(
        ObjectConfig config,
        Set<Id> accountIds,
        Set<Id> roleIds,
        Map<Id, String> tokenByRole,
        Map<Id, String> packedByAccount,
        Map<String, Map<Id, String>> valuesByObject
    ) {
        if (KenNamespaceUtil.resolveSObjectType(config.objectName) == null) {
            return;
        }

        List<String> selectFields = new List<String>{ 'Id', FIELD };
        Map<Id, String> parentValues = new Map<Id, String>();
        Set<Id> parentIds = new Set<Id>();
        String soql;

        if (String.isNotBlank(config.parentField)) {

            if (valuesByObject.containsKey(config.parentObject)) {
                parentValues = valuesByObject.get(config.parentObject);
            }
            if (parentValues.isEmpty()) {
                return;
            }
            parentIds = parentValues.keySet();

            selectFields.add(config.parentField);
            soql = 'SELECT ' + String.join(selectFields, ', ')
                + ' FROM ' + config.objectName
                + ' WHERE ' + config.parentField + ' IN :parentIds';

        } else {

            List<String> filters = new List<String>();

            if (String.isNotBlank(config.roleField)) {
                selectFields.add(config.roleField);
                filters.add(config.roleField + ' IN :roleIds');
            }
            for (String personField : config.personFields) {
                selectFields.add(personField);
                filters.add(personField + ' IN :accountIds');
            }
            if (filters.isEmpty()) {
                return;
            }

            soql = 'SELECT ' + String.join(selectFields, ', ')
                + ' FROM ' + config.objectName
                + ' WHERE ' + String.join(filters, ' OR ');
        }

        Schema.SObjectType targetType = KenNamespaceUtil.resolveSObjectType(config.objectName);
        Map<Id, String> computed = new Map<Id, String>();
        List<SObject> updates = new List<SObject>();

        Map<String, Object> fanOutBinds = new Map<String, Object>{
            'parentIds' => parentIds,
            'roleIds' => roleIds,
            'accountIds' => accountIds
        };

        for (SObject record : Database.queryWithBinds(soql, fanOutBinds, AccessLevel.SYSTEM_MODE)) {

            Id recordId = (Id) record.get('Id');
            String desired;

            if (String.isNotBlank(config.parentField)) {
                Id parentId = (Id) record.get(config.parentField);
                desired = parentId == null ? null : parentValues.get(parentId);
            } else {
                Id roleId = String.isBlank(config.roleField) ? null : (Id) record.get(config.roleField);

                if (roleId != null) {
                    if (!roleIds.contains(roleId)) {
                        continue;
                    }
                    desired = tokenByRole.get(roleId);
                } else {
                    Set<String> union = new Set<String>();
                    for (String personField : config.personFields) {
                        Id personId = (Id) record.get(personField);
                        if (personId == null) {
                            continue;
                        }
                        union.addAll(unwrapAll(packedByAccount.get(personId)));
                    }
                    desired = pack(union).value;
                }
            }

            computed.put(recordId, desired);

            if ((String) record.get(FIELD) != desired) {
                SObject dto = targetType.newSObject();
                dto.put('Id', recordId);
                dto.put(FIELD, desired);
                updates.add(dto);
            }
        }

        valuesByObject.put(config.objectName, computed);

        saveAll(updates, config.objectName);
    }

    /**
     * @description Writes with partial success so that one record failing an unrelated validation
     *              cannot abort institute population for everything else in the chunk. Legacy rows
     *              holding a null value in a since-required field are the common case, and they
     *              reject any update at all even when it does not touch that field.
     * @param records narrow DTOs carrying only Id and the institute field
     * @param context object name used in the failure log
     */
    private static void saveAll(List<SObject> records, String context) {

        if (records == null || records.isEmpty()) {
            return;
        }

        Database.SaveResult[] results = Database.update(records, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                continue;
            }
            String reasons = '';
            for (Database.Error err : results[i].getErrors()) {
                reasons += err.getStatusCode() + ': ' + err.getMessage() + ' ' + err.getFields() + '; ';
            }
            System.debug(LoggingLevel.ERROR,
                'KenInstitutePopulationService could not stamp ' + context + ' '
                + records[i].Id + ' -> ' + reasons);
        }
    }

    /**
     * @description Re-derives each role's own single institute from its program plan and writes
     *              back only the rows whose value actually moved.
     */
    private static void restampRoles(List<ConstituentRole> roles) {

        if (roles == null || roles.isEmpty()) {
            return;
        }

        Map<Id, String> before = new Map<Id, String>();
        for (ConstituentRole role : roles) {
            before.put(role.Id, role.Institute_Name__c);
        }

        stampConstituentRoles(roles);

        List<ConstituentRole> updates = new List<ConstituentRole>();
        for (ConstituentRole role : roles) {
            if (before.get(role.Id) != role.Institute_Name__c) {
                updates.add(new ConstituentRole(Id = role.Id, Institute_Name__c = role.Institute_Name__c));
            }
        }

        saveAll(updates, 'ConstituentRole');
    }

    // ---------------------------------------------------------------------------------------
    // Token resolution and packing
    // ---------------------------------------------------------------------------------------

    /**
     * @description Reads the institute token for each program plan. The only place that knows
     *              which field on the provider carries the token.
     */
    private static Map<Id, String> resolveTokensByProgramPlan(Set<Id> planIds) {

        Map<Id, String> result = new Map<Id, String>();
        if (planIds == null || planIds.isEmpty()) {
            return result;
        }

        String soql = 'SELECT Id, ' + INSTITUTE_SOURCE_PATH
            + ' FROM LearningProgramPlan WHERE Id IN :planIds';

        for (SObject plan : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'planIds' => planIds },
                AccessLevel.SYSTEM_MODE)) {
            String raw = (String) resolvePath(plan, INSTITUTE_SOURCE_PATH);
            String token = unwrapSingle(raw);
            if (String.isNotBlank(token)) {
                result.put((Id) plan.get('Id'), token);
            }
        }
        return result;
    }

    /**
     * @description Walks a dotted field path across parent relationships.
     */
    private static Object resolvePath(SObject record, String path) {

        List<String> parts = path.split('\\.');
        SObject cursor = record;

        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (cursor == null) {
                return null;
            }
            cursor = cursor.getSObject(parts[i]);
        }
        return cursor == null ? null : cursor.get(parts[parts.size() - 1]);
    }

    private class PackResult {
        String value;
        Boolean truncated = false;
    }

    /**
     * @description Sorts, de-duplicates and semicolon-separates the tokens, dropping any that
     *              would push the value past the field length and flagging that it happened.
     *              One token yields a bare code, several yield "A;B;C".
     */
    private static PackResult pack(Set<String> tokens) {

        PackResult result = new PackResult();
        if (tokens == null || tokens.isEmpty()) {
            return result;
        }

        List<String> sorted = new List<String>(tokens);
        sorted.sort();

        String value = '';
        for (String token : sorted) {
            String candidate = String.isEmpty(value) ? token : value + DELIMITER + token;
            if (candidate.length() > MAX_LENGTH) {
                result.truncated = true;
                continue;
            }
            value = candidate;
        }

        result.value = String.isEmpty(value) ? null : value;
        return result;
    }

    private static String unwrapSingle(String packed) {
        List<String> tokens = unwrapAll(packed);
        return tokens.isEmpty() ? null : tokens[0];
    }

    private static List<String> unwrapAll(String packed) {
        List<String> tokens = new List<String>();
        if (String.isBlank(packed)) {
            return tokens;
        }
        for (String token : packed.split(DELIMITER)) {
            if (String.isNotBlank(token)) {
                tokens.add(token.trim());
            }
        }
        return tokens;
    }
}