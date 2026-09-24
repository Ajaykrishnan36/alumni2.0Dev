@IsTest
private class KenLeadLifecycleServiceTest {

    @TestSetup
    static void seed() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
        ]) { paRtId = rt.Id; }

        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 7; i++) {
            Account a = new Account();
            if (paRtId != null) {
                a.RecordTypeId = paRtId;
                a.FirstName = 'Life';
                a.LastName = 'Stage' + i;
                a.PersonEmail = 'life' + i + '@example.test';
            } else {
                a.Name = 'Life Stage ' + i;
            }
            accs.add(a);
        }
        insert accs;

        List<String> regStatuses = new List<String>{
            'Unregistered', 'Unregistered', 'Registered', 'Onboarding In Progress', 'Registered', 'Onboarding In Progress', 'Initial Login Done'
        };
        List<String> sources = new List<String>{
            'Campaign Lead', 'Historical Upload', 'Historical Upload', 'Historical Upload', 'Historical Upload', 'Historical Upload', 'Historical Upload'
        };
        List<ConstituentRole> roles = new List<ConstituentRole>();
        for (Integer i = 0; i < 7; i++) {
            ConstituentRole cr = new ConstituentRole(
                PersonId = accs[i].Id,
                RoleType = 'Alumni',
                Registration_Status__c = regStatuses[i],
                Source_Funnel__c = sources[i]
            );
            cr.put('Status', 'Active');
            roles.add(cr);
        }
        insert roles;

    }

    @IsTest
    static void testGetStages() {
        List<KenLeadLifecycleService.StageMeta> stages = KenLeadLifecycleService.getStages();
        System.assertEquals(5, stages.size(), 'Five lifecycle stages expected.');
        System.assertEquals(KenLeadLifecycleService.STAGE_LEAD, stages[0].stage);
        System.assertEquals(KenLeadLifecycleService.STAGE_ACTIVE, stages[stages.size() - 1].stage);
        for (KenLeadLifecycleService.StageMeta s : stages) {
            System.assertNotEquals(null, s.filterKey);
            System.assert(!s.subStatuses.isEmpty());
        }
    }

    @IsTest
    static void testPredicateAndCount() {
        Test.startTest();
        for (KenLeadLifecycleService.StageMeta s : KenLeadLifecycleService.getStages()) {
            System.assertNotEquals(null, KenLeadLifecycleService.predicateFor(s.filterKey));
            Integer c = KenLeadLifecycleService.countFor(s.filterKey);
            System.assert(c >= 0, 'Count must be non-negative for ' + s.stage);
        }
        Test.stopTest();
        System.assertEquals(null, KenLeadLifecycleService.predicateFor('bogus-key'));
        System.assertEquals(0, KenLeadLifecycleService.countFor('bogus-key'));
    }

    @IsTest
    static void testGetFunnelSteps() {
        List<KenLeadLifecycleService.StageMeta> steps = KenLeadLifecycleService.getFunnelSteps();
        System.assertEquals(4, steps.size(), 'Four uniform funnel steps expected.');
        System.assertEquals('Leads', steps[0].label);
        System.assertEquals('Active', steps[steps.size() - 1].label);
        for (KenLeadLifecycleService.StageMeta s : steps) {
            System.assertNotEquals(null, KenLeadLifecycleService.predicateFor(s.filterKey));
            System.assert(KenLeadLifecycleService.countFor(s.filterKey) >= 0);
        }
    }

    @IsTest
    static void testResolveStageAndSubStatus() {
        Map<Id, ConstituentRole> crById = new Map<Id, ConstituentRole>([
            SELECT Id, Registration_Status__c, Source_Funnel__c
            FROM ConstituentRole WHERE RoleType = 'Alumni'
        ]);

        Map<String, String> stageBySub = new Map<String, String>();
        for (ConstituentRole cr : crById.values()) {
            String stage = KenLeadLifecycleService.resolveStage(cr);
            String sub = KenLeadLifecycleService.resolveSubStatus(cr);
            System.assertNotEquals(null, stage);
            if (String.isNotBlank(stage)) stageBySub.put(stage, sub);
        }

        System.assertEquals('Campaign', stageBySub.get(KenLeadLifecycleService.STAGE_LEAD));
        System.assertEquals('Awaiting Verification', stageBySub.get(KenLeadLifecycleService.STAGE_UNVERIFIED));
        System.assertEquals('New Registration', stageBySub.get(KenLeadLifecycleService.STAGE_REGISTERED));
        System.assertEquals('In Progress', stageBySub.get(KenLeadLifecycleService.STAGE_ONBOARDING_IN_PROGRESS));
        System.assertEquals('Active', stageBySub.get(KenLeadLifecycleService.STAGE_ACTIVE));
    }

    @IsTest
    static void testResolveStageNullSafe() {
        System.assertEquals(
            KenLeadLifecycleService.STAGE_UNVERIFIED,
            KenLeadLifecycleService.resolveStage(new ConstituentRole())
        );
        System.assertEquals('Awaiting Verification', KenLeadLifecycleService.resolveSubStatus(null));
    }
}