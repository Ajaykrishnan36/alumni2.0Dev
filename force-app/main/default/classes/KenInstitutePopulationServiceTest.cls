/**
 * @description Coverage for the institute population stack: the ConstituentRole before-trigger
 *              stamp, the person-Account aggregation, the fan-out to related records, the
 *              re-sync entry points and the batch.
 */
@IsTest
private class KenInstitutePopulationServiceTest {

    private static Id kenCampusId;

    /**
     * KJS orgs add a required Campus__c lookup (-> Location) on LearningProgram.
     * Populate it only where the field exists so the tests still run in every
     * other org, and reuse one Location so a helper called in a loop does not
     * spend a DML statement per programme.
     */
    private static void kenAssignCampus(SObject record) {
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey('campus__c')) {
            return;
        }
        if (kenCampusId == null) {
            Schema.Location campus = new Schema.Location(Name = 'Ken Test Campus');
            for (Schema.PicklistEntry entry : Schema.Location.LocationType.getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    campus.LocationType = entry.getValue();
                    break;
                }
            }
            insert campus;
            kenCampusId = campus.Id;
        }
        record.put('Campus__c', kenCampusId);
    }

    private static Id personRecordTypeId {
        get {
            if (personRecordTypeId == null) {
                for (RecordType rt : [
                    SELECT Id FROM RecordType
                    WHERE SobjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
                    LIMIT 1
                ]) {
                    personRecordTypeId = rt.Id;
                }
            }
            return personRecordTypeId;
        }
        set;
    }

    /**
     * Provider record id per institute code, recorded as each plan is built. The service stamps
     * the provider's id, not the code, so the expected token can only be known after insert.
     */
    private static Map<String, Id> providerIdByCode = new Map<String, Id>();

    /**
     * @description The token the service is expected to stamp for one institute code.
     */
    private static String tok(String code) {
        return String.valueOf(providerIdByCode.get(code));
    }

    /**
     * @description The packed token for several institute codes. The service sorts what it packs,
     *              and it packs ids, so the order follows the ids and not the codes.
     */
    private static String toks(List<String> codes) {
        List<String> ids = new List<String>();
        for (String code : codes) {
            ids.add(tok(code));
        }
        ids.sort();
        return String.join(ids, KenInstitutePopulationService.DELIMITER);
    }

    /**
     * @description Builds a provider Account carrying an institute code and a program plan that
     *              points at it, which is the chain the service walks. The code stays on the
     *              provider because User.Institute_Code__c is still resolved through it.
     */
    private static LearningProgramPlan makePlan(String providerName, String code) {

        Account provider = new Account(Name = providerName, Institution_Name__c = code);
        insert provider;
        providerIdByCode.put(code, provider.Id);

        Learning learning = new Learning(Name = providerName + ' Learning');
        insert learning;

        LearningProgram program = new LearningProgram(Name = providerName + ' Program', LearningId = learning.Id);
        kenAssignCampus(program);
        insert program;

        LearningProgramPlan plan = new LearningProgramPlan(
            Name = providerName + ' Plan',
            LearningProgramId = program.Id,
            ProviderId = provider.Id
        );
        insert plan;

        return plan;
    }

    /**
     * @description A plan with no provider at all. Since the token IS the provider's record id,
     *              this is the only remaining way for an institute to resolve to nothing — a
     *              provider that exists always has an id, so it always has a token.
     */
    private static LearningProgramPlan makePlanWithoutProvider(String planName) {

        Learning learning = new Learning(Name = planName + ' Learning');
        insert learning;

        LearningProgram program = new LearningProgram(Name = planName + ' Program', LearningId = learning.Id);
        kenAssignCampus(program);
        insert program;

        LearningProgramPlan plan = new LearningProgramPlan(
            Name = planName + ' Plan',
            LearningProgramId = program.Id
        );
        insert plan;

        return plan;
    }

    private static Account makePerson(String lastName) {
        Account person = new Account(LastName = lastName, RecordTypeId = personRecordTypeId);
        insert person;
        return person;
    }

    private static ConstituentRole makeRole(Id personId, Id planId) {
        ConstituentRole role = new ConstituentRole(
            PersonId = personId,
            RoleType = 'Alumni', Status = 'Active',
            Program_Plan__c = planId
        );
        insert role;
        return role;
    }

    @IsTest
    static void stampsCodeOnInsert() {

        LearningProgramPlan plan = makePlan('Somaiya Medical', 'KJSMED');
        Account person = makePerson('Stamped');

        Test.startTest();
        ConstituentRole role = makeRole(person.Id, plan.Id);
        Test.stopTest();

        ConstituentRole saved = [SELECT Institute_Name__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertEquals(tok('KJSMED'), saved.Institute_Name__c,
            'The role should carry its own single institute code, with no delimiters');

        Account savedPerson = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSMED'), savedPerson.Institution_Name__c,
            'The person Account should aggregate the code from its alumni role');
    }

    @IsTest
    static void aggregatesMultipleInstitutesSorted() {

        LearningProgramPlan dental = makePlan('Somaiya Dental', 'KJSDEN');
        LearningProgramPlan medical = makePlan('Somaiya Medical', 'KJSMED');
        Account person = makePerson('MultiRole');

        Test.startTest();
        insert new List<ConstituentRole>{
            new ConstituentRole(PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = medical.Id),
            new ConstituentRole(PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = dental.Id)
        };
        Test.stopTest();

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(toks(new List<String>{'KJSDEN','KJSMED'}), saved.Institution_Name__c,
            'Codes should be de-duplicated and sorted so the stored value is deterministic');
    }

    /**
     * Now that the token IS the provider's record id, an institute cannot be missing a code the
     * way it used to be: having a provider means having a token. The only remaining way to get
     * no token is a plan with no provider at all, so that is what this asserts.
     */
    @IsTest
    static void planWithoutProviderLeavesFieldNull() {

        LearningProgramPlan plan = makePlanWithoutProvider('Unmapped');
        Account person = makePerson('NoProvider');

        Test.startTest();
        ConstituentRole role = makeRole(person.Id, plan.Id);
        Test.stopTest();

        ConstituentRole saved = [SELECT Institute_Name__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertEquals(null, saved.Institute_Name__c,
            'A plan without a provider must leave the field null rather than store a partial value');
    }

    @IsTest
    static void fansOutToRoleAnchoredRecord() {

        LearningProgramPlan plan = makePlan('Somaiya Engineering', 'KJSENG');
        Account person = makePerson('EventOwner');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Reunion',
            Constituent_Role__c = role.Id,
            Person_Account__c = person.Id
        );
        insert event;

        Test.startTest();
        KenInstitutePopulationService.recalcByConstituentRole(new Set<Id>{ role.Id });
        Test.stopTest();

        Ken_Event_Master__c saved = [SELECT Institute_Name__c FROM Ken_Event_Master__c WHERE Id = :event.Id];
        System.assertEquals(tok('KJSENG'), saved.Institute_Name__c,
            'A record anchored on a ConstituentRole takes that role single institute');
    }

    @IsTest
    static void fansOutToPersonAnchoredRecord() {

        LearningProgramPlan dental = makePlan('Somaiya Dental', 'KJSDEN');
        LearningProgramPlan medical = makePlan('Somaiya Medical', 'KJSMED');
        Account person = makePerson('GroupOwner');

        insert new List<ConstituentRole>{
            new ConstituentRole(PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = medical.Id),
            new ConstituentRole(PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = dental.Id)
        };

        Ken_Group__c grp = new Ken_Group__c(Name = 'Alumni Cricket', Created_By__c = person.Id);
        insert grp;

        Test.startTest();
        KenInstitutePopulationService.recalcByAccount(new Set<Id>{ person.Id });
        Test.stopTest();

        Ken_Group__c saved = [SELECT Institute_Name__c FROM Ken_Group__c WHERE Id = :grp.Id];
        System.assertEquals(toks(new List<String>{'KJSDEN','KJSMED'}), saved.Institute_Name__c,
            'A person anchored record takes the union of the creator institutes');
    }

    @IsTest
    static void programPlanChangeRestampsAndFansOut() {

        LearningProgramPlan before = makePlan('Somaiya Arts', 'KJSART');
        LearningProgramPlan after = makePlan('Somaiya Commerce', 'KJSCOM');
        Account person = makePerson('Transferred');
        ConstituentRole role = makeRole(person.Id, before.Id);

        Ken_Fundraise__c fundraise = new Ken_Fundraise__c(Name = 'Library Fund', Constituent_Role__c = role.Id);
        insert fundraise;

        Test.startTest();
        update new ConstituentRole(Id = role.Id, Program_Plan__c = after.Id);
        Test.stopTest();

        ConstituentRole savedRole = [SELECT Institute_Name__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertEquals(tok('KJSCOM'), savedRole.Institute_Name__c, 'Changing the plan must restamp the role');

        Ken_Fundraise__c savedFundraise = [SELECT Institute_Name__c FROM Ken_Fundraise__c WHERE Id = :fundraise.Id];
        System.assertEquals(tok('KJSCOM'), savedFundraise.Institute_Name__c,
            'The change must reach records anchored on that role');
    }

    @IsTest
    static void copiesFromParentEvent() {

        LearningProgramPlan plan = makePlan('Somaiya Polytechnic', 'KJSPOL');
        Account person = makePerson('SessionOwner');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Tech Fest', Constituent_Role__c = role.Id, Person_Account__c = person.Id
        );
        insert event;

        Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(Event_Reference__c = event.Id);
        insert session;

        Test.startTest();
        KenInstitutePopulationService.recalcByConstituentRole(new Set<Id>{ role.Id });
        Test.stopTest();

        Ken_Schedule_Sessions__c saved = [SELECT Institute_Name__c FROM Ken_Schedule_Sessions__c WHERE Id = :session.Id];
        System.assertEquals(tok('KJSPOL'), saved.Institute_Name__c,
            'A child session must inherit the value stamped on its parent event');
    }

    @IsTest
    static void recalcByAccountAcceptsContactId() {

        LearningProgramPlan plan = makePlan('Somaiya Nursing', 'KJSNUR');
        Account person = makePerson('ByContact');
        makeRole(person.Id, plan.Id);

        Account withContact = [SELECT PersonContactId FROM Account WHERE Id = :person.Id];

        Test.startTest();
        Integer processed = KenInstitutePopulationService.recalcByAccount(
            new Set<Id>{ withContact.PersonContactId }
        );
        Test.stopTest();

        System.assertEquals(1, processed, 'A Contact id must resolve to its person Account');

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSNUR'), saved.Institution_Name__c, 'The resolved Account should be stamped');
    }

    @IsTest
    static void truncatesBeyondFieldLength() {

        Account person = makePerson('Overflowing');
        List<ConstituentRole> roles = new List<ConstituentRole>();

        for (Integer i = 0; i < 18; i++) {
            String code = 'CODE' + String.valueOf(100 + i).leftPad(11, 'X');
            LearningProgramPlan plan = makePlan('Provider ' + i, code);
            roles.add(new ConstituentRole(PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = plan.Id));
        }

        Test.startTest();
        insert roles;
        Test.stopTest();

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assert(saved.Institution_Name__c.length() <= KenInstitutePopulationService.MAX_LENGTH,
            'The packed value must never exceed the field length');
    }

    @IsTest
    static void handlesBulkInsertWithinLimits() {

        LearningProgramPlan plan = makePlan('Somaiya Bulk', 'KJSBLK');

        List<Account> people = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            people.add(new Account(LastName = 'Bulk ' + i, RecordTypeId = personRecordTypeId));
        }
        insert people;

        List<ConstituentRole> roles = new List<ConstituentRole>();
        for (Account person : people) {
            roles.add(new ConstituentRole(PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = plan.Id));
        }

        Test.startTest();
        insert roles;
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        System.assert(queriesUsed < Limits.getLimitQueries(),
            'A 200 row insert must not approach the SOQL ceiling');

        String bulkToken = tok('KJSBLK');
        Integer stamped = [
            SELECT COUNT() FROM ConstituentRole
            WHERE Id IN :roles AND Institute_Name__c = :bulkToken
        ];
        System.assertEquals(200, stamped, 'Every role in a bulk insert must be stamped');
    }

    @IsTest
    static void skipFanoutSuppressesAsyncWork() {

        LearningProgramPlan plan = makePlan('Somaiya Import', 'KJSIMP');
        Account person = makePerson('Imported');

        Test.startTest();
        KenInstitutePopulationService.skipFanout = true;
        ConstituentRole role = makeRole(person.Id, plan.Id);
        Test.stopTest();

        KenInstitutePopulationService.skipFanout = false;

        ConstituentRole saved = [SELECT Institute_Name__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertEquals(tok('KJSIMP'), saved.Institute_Name__c,
            'The synchronous stamp must still run when the fan-out is suppressed');

        Account savedPerson = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(null, savedPerson.Institution_Name__c,
            'Suppressing the fan-out must leave the Account for the batch to fix');
    }

    @IsTest
    static void batchRepairsSuppressedRecords() {

        LearningProgramPlan plan = makePlan('Somaiya Batch', 'KJSBAT');
        Account person = makePerson('Repairable');

        KenInstitutePopulationService.skipFanout = true;
        makeRole(person.Id, plan.Id);
        KenInstitutePopulationService.skipFanout = false;

        Test.startTest();
        KenInstitutePopulationBatch.runForAll();
        Test.stopTest();

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSBAT'), saved.Institution_Name__c,
            'The batch must repair whatever the suppressed fan-out left behind');
    }

    @IsTest
    static void batchAcceptsExplicitScopes() {

        LearningProgramPlan plan = makePlan('Somaiya Scoped', 'KJSSCP');
        Account person = makePerson('Scoped');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Test.startTest();
        KenInstitutePopulationBatch.runForConstituentRoles(new Set<Id>{ role.Id });
        Test.stopTest();

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSSCP'), saved.Institution_Name__c,
            'Running the batch for a role subset must still stamp the person');
    }

    /**
     * @description The account-mode entry point takes person ids instead of role ids and drives a
     *              different start() query, so it needs a run of its own — a test method may only
     *              ever drive one executeBatch.
     */
    @IsTest
    static void batchAcceptsAccountScopes() {

        LearningProgramPlan plan = makePlan('Somaiya Accounts', 'KJSACC');
        Account person = makePerson('AccountScoped');

        KenInstitutePopulationService.skipFanout = true;
        makeRole(person.Id, plan.Id);
        KenInstitutePopulationService.skipFanout = false;

        Test.startTest();
        KenInstitutePopulationBatch.runForAccounts(new Set<Id>{ person.Id });
        Test.stopTest();

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSACC'), saved.Institution_Name__c,
            'Running the batch for a person subset must stamp that person');
    }

    @IsTest
    static void oneUnsavableRecordDoesNotBlockTheRest() {

        LearningProgramPlan plan = makePlan('Somaiya Resilient', 'KJSRES');
        Account person = makePerson('Resilient');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Survives', Constituent_Role__c = role.Id, Person_Account__c = person.Id
        );
        insert event;

        Ken_Notification__c blocked = new Ken_Notification__c(
            Recipient__c = person.Id,
            Title__c = 'Legacy row',
            Category__c = 'Network'
        );
        insert blocked;
        blocked.Category__c = null;
        Database.update(blocked, false);

        Test.startTest();
        KenInstitutePopulationService.recalcByConstituentRole(new Set<Id>{ role.Id });
        Test.stopTest();

        Ken_Event_Master__c saved = [SELECT Institute_Name__c FROM Ken_Event_Master__c WHERE Id = :event.Id];
        System.assertEquals(tok('KJSRES'), saved.Institute_Name__c,
            'A record that cannot be saved must not stop the rest of the fan-out');

        Account savedPerson = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSRES'), savedPerson.Institution_Name__c,
            'The person Account must still be stamped');
    }

    @IsTest
    static void providerTokenSurvivesBeingPassedIn() {

        LearningProgramPlan plan = makePlan('Somaiya Guarded', 'KJSGRD');
        Id providerId = [SELECT ProviderId FROM LearningProgramPlan WHERE Id = :plan.Id].ProviderId;

        Account person = makePerson('Guarded');
        makeRole(person.Id, plan.Id);

        Test.startTest();
        KenInstitutePopulationService.recalcByAccount(new Set<Id>{ providerId, person.Id });
        Test.stopTest();

        Account provider = [SELECT Institution_Name__c FROM Account WHERE Id = :providerId];
        System.assertEquals('KJSGRD', provider.Institution_Name__c,
            'An institution Account passed in by mistake must keep its own code, which is the'
            + ' readable lookup key and not the packed id the fan-out writes to person Accounts');

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSGRD'), saved.Institution_Name__c, 'The person must still be stamped');
    }

    @IsTest
    static void roleAnchoredRecordIgnoresPersonUnionWhenRoleHasNoCode() {

        LearningProgramPlan coded = makePlan('Somaiya Coded', 'KJSCOD');
        LearningProgramPlan uncoded = makePlanWithoutProvider('Somaiya Unprovided');
        Account person = makePerson('MixedCodes');

        insert new ConstituentRole(
            PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = coded.Id
        );
        ConstituentRole blankRole = new ConstituentRole(
            PersonId = person.Id, RoleType = 'Alumni', Status = 'Active', Program_Plan__c = uncoded.Id
        );
        insert blankRole;

        Ken_Fundraise__c fundraise = new Ken_Fundraise__c(
            Name = 'Anchored On Blank', Constituent_Role__c = blankRole.Id
        );
        insert fundraise;

        Test.startTest();
        KenInstitutePopulationService.recalcByAccount(new Set<Id>{ person.Id });
        Test.stopTest();

        Account saved = [SELECT Institution_Name__c FROM Account WHERE Id = :person.Id];
        System.assertEquals(tok('KJSCOD'), saved.Institution_Name__c,
            'The person aggregates only the institutes that resolved to a token');

        Ken_Fundraise__c savedFundraise = [
            SELECT Institute_Name__c FROM Ken_Fundraise__c WHERE Id = :fundraise.Id
        ];
        System.assertEquals(null, savedFundraise.Institute_Name__c,
            'A role anchored record must take its own role token, not the person union');
    }

    @IsTest
    static void emptyInputIsANoOp() {

        Test.startTest();
        System.assertEquals(0, KenInstitutePopulationService.recalcByAccount(new Set<Id>()),
            'An empty Account set should do nothing');
        System.assertEquals(0, KenInstitutePopulationService.recalcByConstituentRole(new Set<Id>()),
            'An empty role set should do nothing');
        KenInstitutePopulationService.stampConstituentRoles(new List<ConstituentRole>());
        KenInstitutePopulationService.stampInstitute(null, null);
        KenInstitutePopulationService.stampInstitute(new List<Ken_Address__c>(), null);
        KenInstitutePopulationService.enqueueFanout(new Set<Id>());
        Test.stopTest();
    }

    // -------------------------------------------------------------------------------------------
    // Stamp on create: the before-trigger path every object shares
    // -------------------------------------------------------------------------------------------

    @IsTest
    static void roleAnchoredRecordIsStampedAtInsert() {

        LearningProgramPlan plan = makePlan('Somaiya Engineering', 'KJSENG');
        Account person = makePerson('Host');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Test.startTest();
        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Portal Hosted Event',
            Constituent_Role__c = role.Id
        );
        insert event;
        Test.stopTest();

        Ken_Event_Master__c saved = [SELECT Institute_Name__c FROM Ken_Event_Master__c WHERE Id = :event.Id];
        System.assertEquals(tok('KJSENG'), saved.Institute_Name__c,
            'An event created with a host role must carry that institute immediately, not after the next fan-out');
    }

    @IsTest
    static void personAnchoredRecordIsStampedAtInsert() {

        LearningProgramPlan plan = makePlan('Somaiya Polytechnic', 'KJSPOL');
        Account person = makePerson('Resident');
        makeRole(person.Id, plan.Id);

        Test.startTest();
        Ken_Address__c address = new Ken_Address__c(Person_Account__c = person.Id, City__c = 'Mumbai');
        insert address;
        Test.stopTest();

        Ken_Address__c saved = [SELECT Institute_Name__c FROM Ken_Address__c WHERE Id = :address.Id];
        System.assertEquals(tok('KJSPOL'), saved.Institute_Name__c,
            'A person anchored record takes the institute already aggregated on the person Account');
    }

    @IsTest
    static void parentAnchoredRecordIsStampedAtInsert() {

        LearningProgramPlan plan = makePlan('Somaiya Dental', 'KJSDEN');
        Account person = makePerson('Organiser');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Parent Event',
            Constituent_Role__c = role.Id
        );
        insert event;

        Test.startTest();
        Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(Event_Reference__c = event.Id);
        insert session;
        Test.stopTest();

        Ken_Schedule_Sessions__c saved = [
            SELECT Institute_Name__c FROM Ken_Schedule_Sessions__c WHERE Id = :session.Id
        ];
        System.assertEquals(tok('KJSDEN'), saved.Institute_Name__c,
            'A session copies the institute of the event it belongs to');
    }

    @IsTest
    static void adminCreatedRecordFallsBackToTheCreatingUser() {

        User staff = makeInstituteStaff('KJSIMS');

        Test.startTest();
        System.runAs(staff) {
            Ken_Event_Master__c event = new Ken_Event_Master__c(Name = 'Admin Console Event');
            insert event;

            Ken_Event_Master__c saved = [
                SELECT Institute_Name__c FROM Ken_Event_Master__c WHERE Id = :event.Id
            ];
            System.assertEquals(tok('KJSIMS'), saved.Institute_Name__c,
                'An event with no alumni anchor must inherit the institute of the staff member who created it');
        }
        Test.stopTest();
    }

    @IsTest
    static void anInstituteChosenByTheAdminSurvivesTheStamp() {

        makePlan('Somaiya Nursing', 'KJSNUR');
        User staff = makeInstituteStaff('KJSIMS');
        String chosen = tok('KJSNUR');

        Test.startTest();
        System.runAs(staff) {
            Ken_Event_Master__c event = new Ken_Event_Master__c(
                Name = 'Event For Another Institute',
                Institute_Name__c = chosen
            );
            insert event;

            Ken_Event_Master__c saved = [
                SELECT Institute_Name__c FROM Ken_Event_Master__c WHERE Id = :event.Id
            ];
            System.assertEquals(chosen, saved.Institute_Name__c,
                'An institute picked in the admin UI must win over the creating user fallback');
        }
        Test.stopTest();
    }

    @IsTest
    static void theFanOutStillOwnsRoleAnchoredRecords() {

        LearningProgramPlan plan = makePlan('Somaiya Commerce', 'KJSCOM');
        makePlan('Somaiya Nursing', 'KJSNUR');
        Account person = makePerson('Chooser');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Test.startTest();
        insert new Ken_Event_Master__c(
            Name = 'Cross Institute Event',
            Constituent_Role__c = role.Id,
            Institute_Name__c = tok('KJSNUR')
        );
        Test.stopTest();

        Ken_Event_Master__c saved = [
            SELECT Institute_Name__c FROM Ken_Event_Master__c WHERE Constituent_Role__c = :role.Id
        ];
        System.assertEquals(tok('KJSCOM'), saved.Institute_Name__c,
            'A record anchored to an alumnus is owned by that role, so the fan-out overrides a hand-set value');
    }

    @IsTest
    static void changingTheAnchorRestampsTheRecord() {

        LearningProgramPlan first = makePlan('Somaiya Arts', 'KJSART');
        LearningProgramPlan second = makePlan('Somaiya Science', 'KJSSCI');

        Account personOne = makePerson('First');
        Account personTwo = makePerson('Second');
        ConstituentRole roleOne = makeRole(personOne.Id, first.Id);
        ConstituentRole roleTwo = makeRole(personTwo.Id, second.Id);

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Handed Over Event',
            Constituent_Role__c = roleOne.Id
        );
        insert event;

        Test.startTest();
        event.Constituent_Role__c = roleTwo.Id;
        update event;
        Test.stopTest();

        Ken_Event_Master__c saved = [SELECT Institute_Name__c FROM Ken_Event_Master__c WHERE Id = :event.Id];
        System.assertEquals(tok('KJSSCI'), saved.Institute_Name__c,
            'Moving the anchor to another institute must move the stamped code with it');
    }

    @IsTest
    static void leadIsStampedFromItsProgramPlan() {

        LearningProgramPlan plan = makePlan('Somaiya Management', 'KJSMGT');

        Test.startTest();
        Lead lead = new Lead(
            FirstName = 'Institute',
            LastName = 'Applicant',
            Company = 'Ken',
            Email = 'institute.applicant.' + System.currentTimeMillis() + '@example.com',
            Program_Plan__c = plan.Id
        );
        insert lead;
        Test.stopTest();

        Lead saved = [SELECT Institute_Name__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(tok('KJSMGT'), saved.Institute_Name__c,
            'A registration lead carries the institute of the programme it was raised against');
    }

    @IsTest
    static void aFailingStampNeverBlocksTheSave() {

        LearningProgramPlan plan = makePlan('Somaiya Resilience', 'KJSRES');
        Account person = makePerson('Saved Anyway');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        KenInstitutePopulationService.failForTest = true;

        Test.startTest();
        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Event Saved Regardless',
            Constituent_Role__c = role.Id
        );
        insert event;
        Ken_Address__c address = new Ken_Address__c(Person_Account__c = person.Id, City__c = 'Mumbai');
        insert address;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Ken_Event_Master__c WHERE Id = :event.Id],
            'A failure inside the institute stamp must never stop the record being saved');
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Address__c WHERE Id = :address.Id],
            'The same guarantee holds for the stamp-only triggers');
    }

    @IsTest
    static void stampStandsDownWhenTheTransactionIsOutOfQueries() {

        LearningProgramPlan plan = makePlan('Somaiya Limits', 'KJSLIM');
        Account person = makePerson('Query Bound');
        ConstituentRole role = makeRole(person.Id, plan.Id);

        Test.startTest();
        for (Integer i = Limits.getQueries(); i < Limits.getLimitQueries() - 5; i++) {
            // burn the transaction's query budget down past the stamp's headroom
            System.assertNotEquals(null, [SELECT Id FROM Account WHERE Id = :person.Id]);
        }

        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'Query Starved Event',
            Constituent_Role__c = role.Id
        );
        insert event;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Ken_Event_Master__c WHERE Id = :event.Id],
            'Running out of queries must cost the stamp, not the record');
    }

    /**
     * @description A staff user with no ConstituentRole of their own, which is what every internal
     *              admin looks like to the stamp.
     */
    /**
     * @description A staff user carrying a readable institute code, plus the institution Account
     *              that code resolves through. The service translates the code to the provider's
     *              id, so without that Account the fallback has nothing to find. The user insert
     *              runs inside System.runAs so the Account DML above it does not trip mixed DML.
     */
    private static User makeInstituteStaff(String code) {

        if (!providerIdByCode.containsKey(code)) {
            Account provider = new Account(Name = 'Provider ' + code, Institution_Name__c = code);
            insert provider;
            providerIdByCode.put(code, provider.Id);
        }

        Profile standard = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String suffix = String.valueOf(System.currentTimeMillis());

        User staff = new User(
            ProfileId = standard.Id,
            LastName = 'Coordinator',
            Email = 'institute.staff.' + suffix + '@example.com',
            Username = 'institute.staff.' + suffix + '@example.com.kentest',
            Alias = 'instst',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Institute_Code__c = code
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert staff;
        }
        return staff;
    }
}