@IsTest
private class KenAdminAlumniControllerTest {

    @TestSetup
    static void seed() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        // 4 Person Accounts, one per ConstituentRole.
        // a2 deliberately has no email/phone to drive the "issues" tab.
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 4; i++) {
            Account a = new Account();
            if (paRtId != null) {
                a.RecordTypeId = paRtId;
                a.FirstName = 'Test';
                a.LastName = 'Alumni' + i;
                if (i != 1) {
                    a.PersonEmail = 'alum' + i + '@example.test';
                    a.PersonMobilePhone = '+91 9876500' + i;
                }
                a.PersonMailingCountry = 'India';
            } else {
                a.Name = 'Bridge Alumni ' + i;
            }
            accts.add(a);
        }
        insert accts;

        // One Lead linked to cr2 so convertLeads has something to flip.
        Lead l = new Lead(
            FirstName = 'Lead', LastName = 'Pending',
            Email = 'lead.pending@example.test',
            Company = 'Self-Declared',
            Institution_Name__c = 'Test University'
        );
        insert l;

        List<String> sources = new List<String>{
            'Historical Upload', 'Self-Declared Lead', 'Alumni Referral', 'Old Portal Record'
        };
        List<String> statuses = new List<String>{
            'Initial Login Done', 'Unregistered', 'Verified', 'Initial Login Done'
        };

        List<ConstituentRole> roles = new List<ConstituentRole>();
        for (Integer i = 0; i < 4; i++) {
            ConstituentRole cr = new ConstituentRole(
                PersonId = accts[i].Id,
                RoleType = 'Alumni',
                Source_Funnel__c = sources[i],
                Registration_Status__c = statuses[i],
                Graduation_Year__c = String.valueOf(2010 + i),
                Registration_Number__c = 'REG-' + i
            );
            cr.put('Status', 'Active');
            if (i == 1) cr.Lead__c = l.Id;
            roles.add(cr);
        }
        insert roles;
    }

    private static Id roleId(String regNum) {
        return [SELECT Id FROM ConstituentRole WHERE Registration_Number__c = :regNum LIMIT 1].Id;
    }

    @IsTest
    static void testGetAlumniRecordsAll() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 50, 1, null, null);
        Test.stopTest();
        System.assertEquals(4, r.totalRecords);
        System.assertEquals(4, r.rows.size());
        System.assertEquals(1, r.pageNumber);
    }

    @IsTest
    static void testGetAlumniRecordsRegistered() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('registered', null, null, null, 25, 1, null, null);
        Test.stopTest();
        // cr0 + cr3 are 'Initial Login Done'
        System.assertEquals(2, r.totalRecords);
    }

    @IsTest
    static void testGetAlumniRecordsOldPortal() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('oldportal', null, null, null, 25, 1, null, null);
        Test.stopTest();
        System.assertEquals(1, r.totalRecords);
    }

    @IsTest
    static void testGetAlumniRecordsIssuesAll() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('issues', null, 'all', null, 25, 1, null, null);
        Test.stopTest();
        // a1 (cr2 in indexing) has no email + no phone â†’ counts here
        System.assert(r.totalRecords >= 1, 'Issues tab should surface the contact-incomplete row.');
    }

    @IsTest
    static void testGetAlumniRecordsLeads() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('leads', null, null, null, 25, 1, null, null);
        Test.stopTest();
        System.assertEquals(1, r.totalRecords);
        System.assertEquals('Test University', r.rows[0].institution, 'Lead row should expose its Institution Name.');
    }

    @IsTest
    static void testGetAlumniRecordsReferrals() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('referrals', null, null, null, 25, 1, null, null);
        Test.stopTest();
        System.assertEquals(1, r.totalRecords);
    }

    @IsTest
    static void testGetAlumniRecordsRecent() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('recent', null, null, null, 25, 1, null, null);
        Test.stopTest();
        // Both Initial Login Done rows were just inserted â†’ both within LAST_N_DAYS:30
        System.assertEquals(2, r.totalRecords);
    }

    @IsTest
    static void testGetTabCounts() {
        Test.startTest();
        KenAdminAlumniController.TabCounts c = KenAdminAlumniController.getTabCounts(null);
        Test.stopTest();
        System.assertEquals(4, c.all);
        System.assertEquals(2, c.registered);
        System.assertEquals(1, c.oldPortal);
        System.assertEquals(1, c.leads);
        System.assertEquals(1, c.referrals);
        System.assert(c.issues >= 1);
    }

    @IsTest
    static void testConvertLeads() {
        Id leadRoleId = roleId('REG-1');
        // The ConstituentRole trigger fires onboarding side-effects on a Verified
        // transition that need a fuller fixture than this lean test setup carries.
        // Silence the trigger via Alumni_Trigger_Settings__c — the convertLeads()
        // logic itself is the unit under test here.
        Alumni_Trigger_Settings__c s = Alumni_Trigger_Settings__c.getInstance();
        if (s == null || s.Id == null) {
            s = new Alumni_Trigger_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.ConstituentRole_Trigger__c = true;
        upsert s;
        Test.startTest();
        KenAdminAlumniController.ConvertResult res =
            KenAdminAlumniController.convertLeads(new List<Id>{ leadRoleId });
        Test.stopTest();
        // Convert button now advances the ConstituentRole to 'Verified' instead of
        // converting the Lead directly — the downstream admin flow handles the rest.
        System.assertEquals(1, res.converted);
        ConstituentRole updatedRole = [
            SELECT Registration_Status__c FROM ConstituentRole WHERE Id = :leadRoleId LIMIT 1
        ];
        System.assertEquals('Verified', updatedRole.Registration_Status__c);
    }

    @IsTest
    static void testConvertLeadsSkipsNonLeads() {
        Id alumniRoleId = roleId('REG-0'); // Historical Upload
        Test.startTest();
        KenAdminAlumniController.ConvertResult res =
            KenAdminAlumniController.convertLeads(new List<Id>{ alumniRoleId });
        Test.stopTest();
        System.assertEquals(0, res.converted);
        System.assertEquals(1, res.skipped);
    }

    @IsTest
    static void testConvertLeadsEmpty() {
        Test.startTest();
        KenAdminAlumniController.ConvertResult res =
            KenAdminAlumniController.convertLeads(new List<Id>());
        Test.stopTest();
        System.assertEquals(0, res.converted);
    }

    /**
     * @description The Leads tab is Lead-driven (Status = 'New'). Converting via the
     *              Lead Id flips Lead.Status to 'Verified', so the row must drop off
     *              the tab. Trigger kill-switches silence lead/role side effects the
     *              lean fixture cannot support.
     */
    @IsTest
    static void testConvertedLeadsDropFromLeadsTab() {
        Id pendingLeadId = [SELECT Id FROM Lead WHERE Email = 'lead.pending@example.test' LIMIT 1].Id;
        Alumni_Trigger_Settings__c s = Alumni_Trigger_Settings__c.getInstance();
        if (s == null || s.Id == null) {
            s = new Alumni_Trigger_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.ConstituentRole_Trigger__c = true;
        s.Lead_Trigger__c = true;
        upsert s;
        KenAdminAlumniController.AlumniList before =
            KenAdminAlumniController.getAlumniRecords('leads', null, null, null, 25, 1, null, null);
        System.assertEquals(1, before.totalRecords, 'New lead should appear on Leads tab.');
        KenAdminAlumniController.convertLeads(new List<Id>{ pendingLeadId });
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('leads', null, null, null, 25, 1, null, null);
        Test.stopTest();
        Lead convertedLead = [SELECT Status FROM Lead WHERE Id = :pendingLeadId LIMIT 1];
        System.assertEquals('Verified', convertedLead.Status, 'Convert should flip the lead from New to Verified.');
        System.assertEquals(0, r.totalRecords, 'Verified lead should drop off the Leads tab after conversion.');
    }

    @IsTest
    static void testRejectLead() {
        Lead l = new Lead(
            FirstName = 'Reject', LastName = 'Me',
            Email = 'reject.me@example.test',
            Company = 'Self-Declared',
            Status = 'New'
        );
        insert l;
        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.rejectLead(l.Id);
        Test.stopTest();
        System.assertEquals(true, res.success, 'Reject should succeed for a lead.');
        Lead updated = [SELECT Status FROM Lead WHERE Id = :l.Id LIMIT 1];
        System.assertEquals('Rejected', updated.Status, 'Rejected lead should carry the Rejected status.');
    }

    @IsTest
    static void testRejectLeadRefusesNonLead() {
        Id crId = roleId('REG-0'); // a ConstituentRole Id, not a Lead
        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.rejectLead(crId);
        Test.stopTest();
        System.assertEquals(false, res.success, 'Reject must refuse a non-lead record.');
    }

    @IsTest
    static void testMergeLeadIntoMaster() {
        // REG-1's master role (cr1) has a blank reg number scenario? It has REG-1.
        // Use REG-0 as the target master and link a fresh lead carrying gap data.
        Id masterId = roleId('REG-0');
        Lead l = new Lead(
            FirstName = 'Merge', LastName = 'Me',
            Email = 'merge.me@example.test',
            Phone = '+91 90000 00000',
            Company = 'Self-Declared',
            Status = 'New',
            Year_of_Graduation__c = '2010'
        );
        insert l;

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(l.Id, masterId);
        Test.stopTest();

        System.assertEquals(true, res.success, 'Merge should succeed for a lead + master role.');
        Lead updated = [SELECT Status, Is_Converted__c FROM Lead WHERE Id = :l.Id LIMIT 1];
        System.assertEquals('Merged', updated.Status, 'Merged lead should carry the Merged status.');
        ConstituentRole cr = [SELECT Lead__c FROM ConstituentRole WHERE Id = :masterId LIMIT 1];
        System.assertEquals(l.Id, cr.Lead__c, 'Master role should be linked to the merged lead.');
    }

    @IsTest
    static void testMergeLeadRefusesNonLead() {
        Id crId = roleId('REG-0');      // source is a ConstituentRole, not a Lead
        Id masterId = roleId('REG-2');
        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(crId, masterId);
        Test.stopTest();
        System.assertEquals(false, res.success, 'Merge must refuse a non-lead source.');
    }

    @IsTest
    static void testMergeLeadRequiresMaster() {
        Lead l = new Lead(FirstName = 'No', LastName = 'Master',
            Email = 'no.master@example.test', Status = 'New');
        insert l;
        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(l.Id, null);
        Test.stopTest();
        System.assertEquals(false, res.success, 'Merge must require a master record.');
    }

    @IsTest
    static void testMergeAbsorbsSiblingLeads() {
        Id masterId = roleId('REG-0');
        String sharedEmail = 'sibling.test@example.test';
        Lead primary = new Lead(
            FirstName = 'Primary', LastName = 'Lead',
            Email = sharedEmail, Phone = '+91 90000 00001',
            Company = 'Self-Declared', Status = 'New',
            Year_of_Graduation__c = '2012'
        );
        insert primary;
        Lead sibling = new Lead(
            FirstName = 'Sibling', LastName = 'Lead',
            Email = sharedEmail, Phone = '+91 90000 00002',
            Company = 'Self-Declared', Status = 'New',
            Registration_Number__c = 'SIB-001'
        );
        insert sibling;

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(primary.Id, masterId);
        Test.stopTest();

        System.assertEquals(true, res.success, 'Merge with sibling should succeed.');
        Lead updatedPrimary = [SELECT Status FROM Lead WHERE Id = :primary.Id LIMIT 1];
        Lead updatedSibling = [SELECT Status FROM Lead WHERE Id = :sibling.Id LIMIT 1];
        System.assertEquals('Merged', updatedPrimary.Status, 'Primary lead should be Merged.');
        System.assertEquals('Merged', updatedSibling.Status, 'Sibling lead sharing the email should also be Merged.');
    }

    @IsTest
    static void testGetAlumniDetail() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.AlumniDetail d = KenAdminAlumniController.getAlumniDetail(id0);
        Test.stopTest();
        System.assertEquals('2010', d.batch);
        System.assertEquals('REG-0', d.registrationNumber);
        System.assertEquals('High', d.engagementScore);
        System.assertEquals(true, d.hasLoggedInOnce);
    }

    @IsTest
    static void testGetMergeCandidates() {
        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> candidates =
            KenAdminAlumniController.getMergeCandidates('Alumni', null);
        Test.stopTest();
        System.assertNotEquals(null, candidates);
    }

    @IsTest
    static void testGetMergeCandidatesBlank() {
        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> candidates =
            KenAdminAlumniController.getMergeCandidates(null, null);
        Test.stopTest();
        System.assertEquals(0, candidates.size());
    }

    @IsTest
    static void testPaginationDefaults() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, null, null, null, null);
        Test.stopTest();
        System.assertEquals(25, r.pageSize);
        System.assertEquals(1, r.pageNumber);
    }

    @IsTest
    static void testDashboardFilterUploadRegistered() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, 'upload-registered', null);
        Test.stopTest();
        // Registration_Status IN (Registered, Initial Login Done) â†’ cr0 + cr3
        System.assertEquals(2, r.totalRecords);
    }

    @IsTest
    static void testDashboardFilterUploadActive() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, 'upload-active', null);
        Test.stopTest();
        // Initial Login Done â†’ cr0 + cr3
        System.assertEquals(2, r.totalRecords);
    }

    @IsTest
    static void testDashboardFilterUploadAvailable() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, 'upload-available', null);
        Test.stopTest();
        // Verified + Registered + Initial Login Done â†’ cr0 + cr2 (Verified) + cr3
        System.assertEquals(3, r.totalRecords);
    }

    @IsTest
    static void testDashboardFilterLeadsBucket() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, 'leads-leads', null);
        Test.stopTest();
        // Self-Declared Lead + Alumni Referral â†’ cr1 + cr2
        System.assertEquals(2, r.totalRecords);
    }

    @IsTest
    static void testDashboardFilterKpiVerified() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, 'kpi-verified', null);
        Test.stopTest();
        System.assertEquals(3, r.totalRecords);
    }

    @IsTest
    static void testDashboardFilterKpiPending() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, 'kpi-pending', null);
        Test.stopTest();
        // Registration_Status='Verified' â†’ cr2 only
        System.assertEquals(1, r.totalRecords);
    }

    @IsTest
    static void testDashboardFilterUnknownKeyIsNoOp() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, 'no-such-key', null);
        Test.stopTest();
        System.assertEquals(4, r.totalRecords);
    }

    @IsTest
    static void testAlumniRowsHaveMatchMergeAndLastUpdated() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r =
            KenAdminAlumniController.getAlumniRecords('all', null, null, null, 25, 1, null, null);
        Test.stopTest();
        System.assert(r.rows.size() > 0);
        for (KenAdminAlumniController.AlumniRow row : r.rows) {
            System.assertNotEquals(null, row.matchMerge);
            System.assertNotEquals(null, row.lastUpdated);
        }
    }

    @IsTest
    static void testGetFilterOptions() {
        Test.startTest();
        KenAdminAlumniController.FilterOptions opts = KenAdminAlumniController.getFilterOptions(null, null);
        Test.stopTest();
        System.assertNotEquals(null, opts, 'Filter options should be returned');
        System.assert(opts.sources.contains('Self-Declared Lead'), 'Sources should include seeded values');
        System.assert(opts.countries.contains('India'), 'Countries should include seeded value');
    }

    @IsTest
    static void testDirectFilterBySource() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r = KenAdminAlumniController.getAlumniRecords(
            'all', null, null, null, 25, 1, null, '{"source":"Self-Declared Lead"}');
        Test.stopTest();
        System.assertEquals(1, r.totalRecords, 'Exactly one seeded role is Self-Declared Lead');
    }

    @IsTest
    static void testPersonFilterByCountry() {
        Test.startTest();
        KenAdminAlumniController.AlumniList match = KenAdminAlumniController.getAlumniRecords(
            'all', null, null, null, 25, 1, null, '{"country":"India"}');
        KenAdminAlumniController.AlumniList none = KenAdminAlumniController.getAlumniRecords(
            'all', null, null, null, 25, 1, null, '{"country":"Narnia"}');
        Test.stopTest();
        System.assert(match.totalRecords > 0, 'Country filter should match seeded India accounts');
        System.assertEquals(0, none.totalRecords, 'Non-matching country should return no rows');
    }

    @IsTest
    static void testGetContactIssueMissingEmailPhone() {
        Id id1 = roleId('REG-1');
        Test.startTest();
        KenAdminAlumniController.ContactIssue ci = KenAdminAlumniController.getContactIssue(id1);
        Test.stopTest();
        System.assertNotEquals(null, ci);
        System.assertEquals(true, ci.emailMissing);
        System.assertEquals(true, ci.phoneMissing);
        System.assertEquals(2, ci.issuesRemaining);
    }

    @IsTest
    static void testSaveEmailRejectsBlank() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.SaveResult sr =
            KenAdminAlumniController.saveContactEmail(id0, '');
        Test.stopTest();
        System.assertEquals(false, sr.success);
    }

    @IsTest
    static void testSaveEmailRejectsInvalid() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.SaveResult sr =
            KenAdminAlumniController.saveContactEmail(id0, 'notanemail');
        Test.stopTest();
        System.assertEquals(false, sr.success);
    }

    @IsTest
    static void testSaveEmailSucceedsOnPersonAccount() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }
        if (paRtId == null) return;

        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.SaveResult sr =
            KenAdminAlumniController.saveContactEmail(id0, 'updated@example.test');
        Test.stopTest();

        System.assertEquals(true, sr.success, sr.message);
        ConstituentRole cr = [SELECT PersonId FROM ConstituentRole WHERE Id = :id0];
        Account refetched = [SELECT PersonEmail FROM Account WHERE Id = :cr.PersonId];
        System.assertEquals('updated@example.test', refetched.PersonEmail);
    }

    @IsTest
    static void testSavePhoneRejectsBlank() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.SaveResult sr =
            KenAdminAlumniController.saveContactPhone(id0, '');
        Test.stopTest();
        System.assertEquals(false, sr.success);
    }

    @IsTest
    static void testSavePhoneSucceedsOnPersonAccount() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }
        if (paRtId == null) return;

        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.SaveResult sr =
            KenAdminAlumniController.saveContactPhone(id0, '+91 98765 43210');
        Test.stopTest();
        System.assertEquals(true, sr.success, sr.message);
    }

    @IsTest
    static void testGetActivityTimeline() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        List<KenAdminAlumniController.TimelineEntry> tl =
            KenAdminAlumniController.getActivityTimeline(id0);
        Test.stopTest();
        System.assert(tl != null && tl.size() >= 1);
        System.assertNotEquals(null, tl[0].title);
    }

    @IsTest
    static void testGetFieldUpdateHistory() {
        Id id0 = roleId('REG-0');
        ConstituentRole cr = [SELECT Id, Registration_Status__c FROM ConstituentRole WHERE Id = :id0];
        cr.Registration_Status__c = 'Verified';
        update cr;
        Test.startTest();
        List<KenAdminAlumniController.FieldUpdate> hist =
            KenAdminAlumniController.getFieldUpdateHistory(id0);
        Test.stopTest();
        System.assertNotEquals(null, hist);
    }

    @IsTest
    static void testNullAlumniIdGuards() {
        // The kenAdminAlumni LWC fires these wires with alumniId=null on mount
        // before any row is selected. Confirm each method returns gracefully
        // instead of throwing QueryException.
        Test.startTest();
        System.assertEquals(null, KenAdminAlumniController.getAlumniDetail(null));
        System.assertEquals(null, KenAdminAlumniController.getContactIssue(null));
        System.assertEquals(0, KenAdminAlumniController.getActivityTimeline(null).size());
        System.assertEquals(0, KenAdminAlumniController.getFieldUpdateHistory(null).size());
        Test.stopTest();
    }

    @IsTest
    static void testPreferenceFilterAndOptions() {
        // Options come from the configurable Ken_Engagement_Preference__c object;
        // the person filter matches the semicolon text on Ken_Alumni_CRM__c.
        insert new Ken_Engagement_Preference__c(
            Name = 'Learn from fellow alumni', Is_Active__c = true, Sort_Order__c = 1
        );

        Test.startTest();
        KenAdminAlumniController.FilterOptions opts = KenAdminAlumniController.getFilterOptions(null, null);
        KenAdminAlumniController.AlumniList none = KenAdminAlumniController.getAlumniRecords(
            'all', null, null, null, 25, 1, null, '{"preference":"Learn from fellow alumni"}');
        Test.stopTest();

        System.assertNotEquals(null, opts.preferencePairs, 'Preference pairs should be returned');
        Boolean found = false;
        for (KenAdminAlumniController.FilterOptionPair p : opts.preferencePairs) {
            if (p.value == 'Learn from fellow alumni') found = true;
        }
        System.assert(found, 'Configured engagement preference should appear as a filter option');
        System.assertEquals(0, none.totalRecords, 'No alumni stored this preference, so the filter should return zero rows');
    }
}