@IsTest
private class KenAdminAlumniControllerTest {

    /**
     * The org's Lead name validation rule rejects digits in FirstName/LastName,
     * so index test names with a letter rather than the loop counter.
     */
    private static String kenAlpha(Integer index) {
        return 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.substring(index, index + 1);
    }

    /**
     * A country the org will accept that no other record in this test uses.
     * Orgs with State & Country picklists enabled reject an invented label, so
     * pick a real, rarely-populated entry from the restricted picklist there and
     * keep the invented one everywhere else.
     */
    private static String kenDistinctiveCountry() {
        Map<String, Schema.SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
        if (!accountFields.containsKey('personmailingcountrycode')) {
            return 'Atlantis';
        }
        String chosen = null;
        for (Schema.PicklistEntry entry :
            accountFields.get('personmailingcountrycode').getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getLabel() != 'India') {
                chosen = entry.getLabel();
            }
        }
        return chosen;
    }

    @TestSetup
    static void seed() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
        ]) { paRtId = rt.Id; }

        // 4 Person Accounts, one per ConstituentRole.
        // a2 deliberately has no email/phone to drive the "issues" tab.
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 4; i++) {
            Account a = new Account();
            if (paRtId != null) {
                a.RecordTypeId = paRtId;
                a.FirstName = 'Test';
                a.LastName = 'Alumni' + kenAlpha(i);
                if (i != 1) {
                    a.PersonEmail = 'alum' + i + '@example.test';
                    a.PersonMobilePhone = '987650000' + i;
                }
                a.PersonMailingCountry = 'India';
            } else {
                a.Name = 'Bridge Alumni ' + i;
            }
            accts.add(a);
        }
        insert accts;

        // One Lead linked to cr2 so convertLeads has something to flip. The Leads tab
        // only ever lists RecordType.DeveloperName = 'Alumni_Lead', and the running
        // user's DEFAULT Lead record type is not that in every org (KJS UAT defaults to
        // Contract_Lead), so stamp it rather than inherit whatever the profile hands out.
        Lead l = new Lead(
            FirstName = 'Lead', LastName = 'Pending',
            Email = 'lead.pending@example.test',
            Company = 'Self-Declared',
            Institution_Name__c = 'Test University'
        );
        Id alumniLeadRt = alumniLeadRecordTypeId();
        if (alumniLeadRt != null) l.RecordTypeId = alumniLeadRt;
        insert l;

        List<String> sources = new List<String>{
            'Historical Upload', 'Self-Declared Lead', 'Alumni Referral', 'Old Portal Record'
        };
        List<String> statuses = new List<String>{
            'Initial Login Done', 'Unregistered', 'Onboarding In Progress', 'Initial Login Done'
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
        // Silence the trigger via Ken_Alm_Bypass_Settings__c — the convertLeads()
        // logic itself is the unit under test here.
        Ken_Alm_Bypass_Settings__c s = KenSettings.bypass();
        if (s == null || s.Id == null) {
            s = new Ken_Alm_Bypass_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.Skip_ConstituentRole_Trigger__c = true;
        upsert s;
        Test.startTest();
        KenAdminAlumniController.ConvertResult res =
            KenAdminAlumniController.convertLeads(new List<Id>{ leadRoleId });
        Test.stopTest();
        // Convert button now leaves the ConstituentRole at 'Unregistered' —
        // converting the Lead directly — the downstream admin flow handles the rest.
        System.assertEquals(1, res.converted);
        ConstituentRole updatedRole = [
            SELECT Registration_Status__c FROM ConstituentRole WHERE Id = :leadRoleId LIMIT 1
        ];
        System.assertEquals('Unregistered', updatedRole.Registration_Status__c);
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
        Ken_Alm_Bypass_Settings__c s = KenSettings.bypass();
        if (s == null || s.Id == null) {
            s = new Ken_Alm_Bypass_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.Skip_ConstituentRole_Trigger__c = true;
        s.Skip_Lead_Trigger__c = true;
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
            Phone = '9000000000',
            Company = 'Self-Declared',
            Status = 'New',
            Year_of_Graduation__c = '2010'
        );
        insert l;

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(l.Id, masterId, null);
        Test.stopTest();

        System.assertEquals(true, res.success, 'Merge should succeed for a lead + master role. Actual message: ' + res.message);
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
            KenAdminAlumniController.mergeLeadIntoMaster(crId, masterId, null);
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
            KenAdminAlumniController.mergeLeadIntoMaster(l.Id, null, null);
        Test.stopTest();
        System.assertEquals(false, res.success, 'Merge must require a master record.');
    }

    @IsTest
    static void testMergeAbsorbsSiblingLeads() {
        Id masterId = roleId('REG-0');
        String sharedEmail = 'sibling.test@example.test';
        Lead primary = new Lead(
            FirstName = 'Primary', LastName = 'Lead',
            Email = sharedEmail, Phone = '9000000001',
            Company = 'Self-Declared', Status = 'New',
            Year_of_Graduation__c = '2012'
        );
        insert primary;
        Lead sibling = new Lead(
            FirstName = 'Sibling', LastName = 'Lead',
            Email = sharedEmail, Phone = '9000000002',
            Company = 'Self-Declared', Status = 'New',
            Registration_Number__c = 'SIB-001'
        );
        insert sibling;

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(primary.Id, masterId, null);
        Test.stopTest();

        System.assertEquals(true, res.success, 'Merge with sibling should succeed.');
        Lead updatedPrimary = [SELECT Status FROM Lead WHERE Id = :primary.Id LIMIT 1];
        Lead updatedSibling = [SELECT Status FROM Lead WHERE Id = :sibling.Id LIMIT 1];
        System.assertEquals('Merged', updatedPrimary.Status, 'Primary lead should be Merged.');
        System.assertEquals('Merged', updatedSibling.Status, 'Sibling lead sharing the email should also be Merged.');
    }

    @IsTest
    static void testGetMergeFieldComparisonDefaultSides() {
        // REG-0's master already has a Graduation_Year__c (2010) but no Referred_By__c
        // (never set in @TestSetup) — good stand-ins for the "existing wins" /
        // "incoming fills the gap" cases respectively.
        Id masterId = roleId('REG-0');
        Id referrerId = [SELECT Id FROM Account LIMIT 1].Id;
        Lead l = new Lead(
            FirstName = 'Compare', LastName = 'Me',
            Email = 'compare.me@example.test',
            Company = 'Self-Declared', Status = 'New',
            Year_of_Graduation__c = '2025',
            Referred_By__c = referrerId
        );
        insert l;

        Test.startTest();
        List<KenAdminAlumniController.MergeFieldRow> rows =
            KenAdminAlumniController.getMergeFieldComparison(l.Id, masterId);
        Test.stopTest();

        Map<String, KenAdminAlumniController.MergeFieldRow> byKey = new Map<String, KenAdminAlumniController.MergeFieldRow>();
        for (KenAdminAlumniController.MergeFieldRow r : rows) byKey.put(r.fieldKey, r);

        // Not asserting an exact row count on purpose — the field list is
        // auto-discovered from schema, so it's expected to grow if someone adds
        // a same-named __c field to both Lead and ConstituentRole later. What
        // matters is that today's known fields are still present.
        System.assert(byKey.containsKey(KenNamespaceUtil.qualifyCustom('Registration_Number__c')), 'Auto-discovered fields should include Registration_Number__c. Keys present: ' + String.join(new List<String>(byKey.keySet()), ','));
        System.assert(byKey.containsKey(KenNamespaceUtil.qualifyCustom('Program_Plan__c')), 'Auto-discovered fields should include Program_Plan__c.');
        System.assert(byKey.containsKey(KenNamespaceUtil.qualifyCustom('Referred_By__c')), 'Auto-discovered fields should include Referred_By__c.');
        System.assert(!byKey.containsKey(KenNamespaceUtil.qualifyCustom('Institution_Name__c')), 'Institution_Name__c is a formula on ConstituentRole and should be excluded.');

        System.assertEquals('existing', byKey.get('gradYear').defaultSide,
            'Master already has a graduation year, so existing should win by default.');
        System.assertEquals('2010', byKey.get('gradYear').existingRaw);
        System.assertEquals('2025', byKey.get('gradYear').incomingRaw);

        System.assertEquals('incoming', byKey.get(KenNamespaceUtil.qualifyCustom('Referred_By__c')).defaultSide,
            'Master has no referrer, so the lead should fill the gap by default.');
        System.assertEquals(referrerId, byKey.get(KenNamespaceUtil.qualifyCustom('Referred_By__c')).incomingRaw);

        System.assertEquals('existing', byKey.get('firstName').defaultSide,
            'Master already has a first name (from @TestSetup), so existing should win by default.');
        System.assertEquals('Test', byKey.get('firstName').existingRaw);
        System.assertEquals('Alumni' + kenAlpha(0), byKey.get('lastName').existingRaw);
        // Lead-sourced values are compared case-insensitively: some orgs run a
        // trigger that normalises lead name capitalisation on insert.
        System.assertEquals('compare', byKey.get('firstName').incomingRaw.toLowerCase());
        System.assertEquals('me', byKey.get('lastName').incomingRaw.toLowerCase());
    }

    @IsTest
    static void testMergeLeadIntoMasterHonorsFieldChoice() {
        // REG-0's master already has Graduation_Year__c = '2010'. Explicitly choosing
        // 'incoming' for gradYear should overwrite it with the lead's '2025' — something
        // the default gap-fill rule alone would never do.
        Id masterId = roleId('REG-0');
        Lead l = new Lead(
            FirstName = 'Override', LastName = 'Me',
            Email = 'override.me@example.test',
            Company = 'Self-Declared', Status = 'New',
            Year_of_Graduation__c = '2025'
        );
        insert l;

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeLeadIntoMaster(
            l.Id, masterId, '{"gradYear":"incoming"}'
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'Merge with a field choice should succeed.');
        ConstituentRole cr = [SELECT Graduation_Year__c FROM ConstituentRole WHERE Id = :masterId LIMIT 1];
        System.assertEquals('2025', cr.Graduation_Year__c,
            'Explicit incoming choice should overwrite the master value.');
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
            KenAdminAlumniController.getMergeCandidates('Alumni', null, null);
        Test.stopTest();
        System.assertNotEquals(null, candidates);
    }

    @IsTest
    static void testGetMergeCandidatesBlank() {
        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> candidates =
            KenAdminAlumniController.getMergeCandidates(null, null, null);
        Test.stopTest();
        System.assertEquals(0, candidates.size());
    }

    @IsTest
    static void testGetMergeSuggestionsMatchesByRegistrationNumber() {
        Lead l = new Lead(
            FirstName = 'Suggest', LastName = 'ByReg',
            Company = 'Self-Declared', Status = 'New',
            Registration_Number__c = 'REG-0'
        );
        insert l;

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(l.Id);
        Test.stopTest();

        Boolean found = false;
        for (KenAdminAlumniController.MergeCandidate c : suggestions) {
            if (c.registrationNumber == 'REG-0') {
                found = true;
                System.assertEquals('Registration number', c.matchedOn);
                System.assertEquals(1, c.matchCount);
                // Lead carries reg number + name as comparable fields; only reg matched.
                System.assertEquals(50, c.matchPercent);
            }
        }
        System.assert(found, 'A lead carrying REG-0 as its own registration number should surface that master as a suggestion.');
    }

    @IsTest
    static void testGetMergeSuggestionsMatchesByEmail() {
        Lead l = new Lead(
            FirstName = 'Suggest', LastName = 'ByEmail',
            Company = 'Self-Declared', Status = 'New',
            Email = 'alum0@example.test' // matches accts[0]'s PersonEmail from @TestSetup
        );
        insert l;

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(l.Id);
        Test.stopTest();

        Boolean found = false;
        for (KenAdminAlumniController.MergeCandidate c : suggestions) {
            if (c.registrationNumber == 'REG-0') found = true;
        }
        System.assert(found, 'Matching the master\'s Person Account email should surface REG-0 even with no registration number on the lead.');
    }

    @IsTest
    static void testGetMergeSuggestionsScoresAndOrdersByMatchPercent() {
        Lead l = new Lead(
            FirstName = 'Test', LastName = 'Alumni' + kenAlpha(0),
            Company = 'Self-Declared', Status = 'New',
            Email = 'alum0@example.test',
            Phone = '9876500000',
            Registration_Number__c = 'REG-3'
        );
        insert l;

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(l.Id);
        Test.stopTest();

        Integer idxReg0 = -1, idxReg3 = -1;
        for (Integer i = 0; i < suggestions.size(); i++) {
            if (suggestions[i].registrationNumber == 'REG-0') idxReg0 = i;
            if (suggestions[i].registrationNumber == 'REG-3') idxReg3 = i;
        }
        System.assert(idxReg3 >= 0, 'REG-3 should surface via the registration-number match.');
        System.assertEquals(1, suggestions[idxReg3].matchCount);
        System.assertEquals(25, suggestions[idxReg3].matchPercent);
        System.assertEquals('Registration number', suggestions[idxReg3].matchedOn);
        if (idxReg0 >= 0) {
            System.assertEquals(3, suggestions[idxReg0].matchCount);
            System.assertEquals(75, suggestions[idxReg0].matchPercent);
            System.assertEquals('Name, Email, Phone', suggestions[idxReg0].matchedOn);
            System.assert(idxReg0 < idxReg3, 'The candidate with the higher match percent should be listed first.');
        }
    }

    @IsTest
    static void testGetMergeSuggestionsNoMatch() {
        Lead l = new Lead(
            FirstName = 'Nobody', LastName = 'Matches',
            Company = 'Self-Declared', Status = 'New',
            Registration_Number__c = 'NO-SUCH-REG',
            Email = 'nomatch@example.test'
        );
        insert l;

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(l.Id);
        Test.stopTest();

        System.assertEquals(0, suggestions.size(), 'Nothing in the lead\'s captured fields matches any master, so suggestions should be empty.');
    }

    @IsTest
    static void testGetMergeFieldComparisonMultiAlignsColumnsToInputOrder() {
        Id masterId0 = roleId('REG-0');
        Id masterId2 = roleId('REG-2');
        Lead l = new Lead(
            FirstName = 'Multi', LastName = 'Compare',
            Email = 'multi.compare@example.test',
            Company = 'Self-Declared', Status = 'New',
            Year_of_Graduation__c = '2099'
        );
        insert l;

        Test.startTest();
        List<KenAdminAlumniController.MergeFieldRowMulti> rows =
            KenAdminAlumniController.getMergeFieldComparisonMulti(l.Id, new List<Id>{ masterId0, masterId2 });
        Test.stopTest();

        Map<String, KenAdminAlumniController.MergeFieldRowMulti> byKey = new Map<String, KenAdminAlumniController.MergeFieldRowMulti>();
        for (KenAdminAlumniController.MergeFieldRowMulti r : rows) byKey.put(r.fieldKey, r);

        KenAdminAlumniController.MergeFieldRowMulti gradYearRow = byKey.get('gradYear');
        System.assertEquals(2, gradYearRow.existingValues.size());
        System.assertEquals('2010', gradYearRow.existingValues[0], 'First column should be REG-0 (2010), matching the order masterRoleIds was passed in.');
        System.assertEquals('2012', gradYearRow.existingValues[1], 'Second column should be REG-2 (2012), matching the order masterRoleIds was passed in.');
        System.assertEquals('2099', gradYearRow.incomingValue);
    }

    @IsTest
    static void testGetMergeFieldComparisonMultiKeepsBlankValuesInPlace() {
        // REG-1's Person Account has no PersonMobilePhone (per @TestSetup, i==1
        // skips setting phone/email) — a blank value in the MIDDLE of the
        // selection must still occupy its own slot in existingValues rather
        // than being dropped and shifting every column after it in that row.
        Id masterId0 = roleId('REG-0');
        Id masterId1 = roleId('REG-1');
        Id masterId2 = roleId('REG-2');
        Lead l = new Lead(
            FirstName = 'Multi', LastName = 'Blank',
            Company = 'Self-Declared', Status = 'New',
            Phone = '9000000000'
        );
        insert l;

        Test.startTest();
        List<KenAdminAlumniController.MergeFieldRowMulti> rows = KenAdminAlumniController.getMergeFieldComparisonMulti(
            l.Id, new List<Id>{ masterId0, masterId1, masterId2 }
        );
        Test.stopTest();

        Map<String, KenAdminAlumniController.MergeFieldRowMulti> byKey = new Map<String, KenAdminAlumniController.MergeFieldRowMulti>();
        for (KenAdminAlumniController.MergeFieldRowMulti r : rows) byKey.put(r.fieldKey, r);

        KenAdminAlumniController.MergeFieldRowMulti phoneRow = byKey.get('phone');
        System.assertEquals(3, phoneRow.existingValues.size(),
            'A blank value in the middle of the selection must not shrink the array — every candidate keeps its own slot.');
        System.assertNotEquals(null, phoneRow.existingValues[0], 'No element should ever be a literal null.');
        System.assertEquals('', phoneRow.existingValues[1], 'REG-1 has no phone on file, so its slot should be an empty string, not null and not skipped.');
        System.assertNotEquals(null, phoneRow.existingValues[2], 'No element should ever be a literal null.');
    }

    @IsTest
    static void testGetMergeFieldComparisonMultiEmptyInputsReturnEmpty() {
        Test.startTest();
        List<KenAdminAlumniController.MergeFieldRowMulti> rows =
            KenAdminAlumniController.getMergeFieldComparisonMulti(null, new List<Id>());
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void testMergeCandidatesIntoOneAppliesResolvedValueFromNonTargetCandidate() {
        // The admin compared REG-0, REG-1, REG-2 on the N-way screen and picked
        // REG-0 as the target, but chose REG-2's graduation year (2012) to win
        // for that field — the write must land on REG-0 using REG-2's value,
        // proving a resolved choice can come from a candidate other than the
        // one actually being written to.
        Id targetId = roleId('REG-0');
        Lead l = new Lead(
            FirstName = 'Multi', LastName = 'Commit',
            Company = 'Self-Declared', Status = 'New'
        );
        insert l;

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            l.Id, targetId, '{"gradYear":"2012"}', null
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'Merge into a chosen target should succeed. Message: ' + res.message);
        ConstituentRole cr = [SELECT Graduation_Year__c, Lead__c FROM ConstituentRole WHERE Id = :targetId LIMIT 1];
        System.assertEquals('2012', cr.Graduation_Year__c,
            'The resolved value (from REG-2) should be written onto the target (REG-0), overwriting its own existing value.');
        System.assertEquals(l.Id, cr.Lead__c, 'Target should be linked to the merged lead.');
        Lead updated = [SELECT Status FROM Lead WHERE Id = :l.Id LIMIT 1];
        System.assertEquals('Merged', updated.Status);
    }

    @IsTest
    static void testMergeCandidatesIntoOneFallsBackToGapFillWhenFieldNotResolved() {
        // REG-0 already has Registration_Number__c = 'REG-0'. No choice is
        // supplied for that field, so it must fall back to the same
        // never-overwrite gap-fill rule as the single-candidate flow.
        Id targetId = roleId('REG-0');
        Lead l = new Lead(
            FirstName = 'Multi', LastName = 'GapFill',
            Company = 'Self-Declared', Status = 'New'
        );
        insert l;

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            l.Id, targetId, '{"gradYear":"2012"}', null
        );
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        ConstituentRole cr = [SELECT Registration_Number__c FROM ConstituentRole WHERE Id = :targetId LIMIT 1];
        System.assertEquals('REG-0', cr.Registration_Number__c,
            'Unresolved fields should keep the target\'s existing value untouched, same as the gap-fill rule elsewhere.');
    }

    @IsTest
    static void testMergeCandidatesIntoOneRequiresTarget() {
        Lead l = new Lead(FirstName = 'No', LastName = 'Target', Company = 'Self-Declared', Status = 'New');
        insert l;
        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(l.Id, null, null, null);
        Test.stopTest();
        System.assertEquals(false, res.success, 'Merge must require a target candidate.');
    }

    @IsTest
    static void testMergeCandidatesIntoOneRefusesNonLead() {
        Id crId = roleId('REG-0');
        Id targetId = roleId('REG-2');
        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(crId, targetId, null, null);
        Test.stopTest();
        System.assertEquals(false, res.success, 'Merge must refuse a non-lead source.');
    }

    @IsTest
    static void testMergeCandidatesIntoOneMarksOthersOwnLeadsSuperseded() {
        // Two OTHER candidates, each with its own distinct linked Lead (not the
        // primary lead being merged). Both of those other leads should end up
        // with Master_Lead__c pointing at the SAME primary lead — the field
        // lives on Lead, lead-to-lead, not on the candidate ConstituentRole.
        Id targetId = roleId('REG-0');
        Lead otherLead1 = new Lead(FirstName = 'Other', LastName = 'One', Company = 'Self-Declared', Status = 'New');
        Lead otherLead2 = new Lead(FirstName = 'Other', LastName = 'Two', Company = 'Self-Declared', Status = 'New');
        insert new List<Lead>{ otherLead1, otherLead2 };

        // Person accounts need the person-type RecordType explicitly — without it
        // the insert is rejected (INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY).
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
        ]) { paRtId = rt.Id; }
        Account otherAcct1 = new Account(RecordTypeId = paRtId, FirstName = 'Other', LastName = 'CandidateOne');
        Account otherAcct2 = new Account(RecordTypeId = paRtId, FirstName = 'Other', LastName = 'CandidateTwo');
        insert new List<Account>{ otherAcct1, otherAcct2 };
        ConstituentRole otherRole1 = new ConstituentRole(PersonId = otherAcct1.Id, RoleType = 'Alumni', Lead__c = otherLead1.Id);
        ConstituentRole otherRole2 = new ConstituentRole(PersonId = otherAcct2.Id, RoleType = 'Alumni', Lead__c = otherLead2.Id);
        otherRole1.put('Status', 'Active');
        otherRole2.put('Status', 'Active');
        insert new List<ConstituentRole>{ otherRole1, otherRole2 };

        Lead primaryLead = new Lead(FirstName = 'Multi', LastName = 'Supersede', Company = 'Self-Declared', Status = 'New');
        insert primaryLead;

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            primaryLead.Id, targetId, null, new List<Id>{ targetId, otherRole1.Id, otherRole2.Id }
        );
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        Map<Id, Lead> leadsById = new Map<Id, Lead>(
            [SELECT Id, Master_Lead__c FROM Lead WHERE Id IN :new List<Id>{ otherLead1.Id, otherLead2.Id, primaryLead.Id }]
        );
        System.assertEquals(primaryLead.Id, leadsById.get(otherLead1.Id).Master_Lead__c,
            'First other candidate\'s own lead should point at the primary lead that was actually merged.');
        System.assertEquals(primaryLead.Id, leadsById.get(otherLead2.Id).Master_Lead__c,
            'Second other candidate\'s own lead should point at the SAME primary lead.');
        System.assertEquals(null, leadsById.get(primaryLead.Id).Master_Lead__c,
            'The primary lead itself is what everything else points to — it should not point at itself.');
    }

    @IsTest
    static void testMergeCandidatesIntoOneMarksOtherCandidatesOwnLeadAsMerged() {
        // REG-1 (per @TestSetup) is linked via Lead__c to a separate Lead
        // ("Lead Pending") — distinct from the lead actually being merged here.
        // Picking REG-0 as target and REG-1 as a non-chosen "other" should flip
        // THAT other Lead's Status to Merged too, reusing the same value Status
        // already supports (Lead.Status already has 'Merged' as a real value).
        Id targetId = roleId('REG-0');
        Id otherId1 = roleId('REG-1');
        ConstituentRole otherRole = [SELECT Lead__c FROM ConstituentRole WHERE Id = :otherId1 LIMIT 1];
        System.assertNotEquals(null, otherRole.Lead__c, 'REG-1 should have its own linked Lead from @TestSetup.');
        Lead otherLeadBefore = [SELECT Status FROM Lead WHERE Id = :otherRole.Lead__c LIMIT 1];
        System.assertNotEquals('Merged', otherLeadBefore.Status, 'Sanity check: this other lead should not already be Merged before the test runs.');

        Lead primaryLead = new Lead(FirstName = 'Multi', LastName = 'OtherLeadCheck', Company = 'Self-Declared', Status = 'New');
        insert primaryLead;

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            primaryLead.Id, targetId, null, new List<Id>{ targetId, otherId1 }
        );
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        Lead otherLeadAfter = [SELECT Status, Master_Lead__c FROM Lead WHERE Id = :otherRole.Lead__c LIMIT 1];
        System.assertEquals('Merged', otherLeadAfter.Status,
            'REG-1 was compared but not chosen, so its own linked lead should be marked Merged too.');
        System.assertEquals(primaryLead.Id, otherLeadAfter.Master_Lead__c,
            'That other lead should also point Master_Lead__c at the primary lead that was actually merged.');
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
        // Registration_Status='Onboarding In Progress' -> cr2 only
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

        System.assertNotEquals(null, opts.employmentTypePairs, 'Employment type pairs must be populated, not left undefined');
        System.assertNotEquals(null, opts.genderPairs, 'Gender pairs must be populated, not left undefined');
        System.assertNotEquals(null, opts.employmentTypes, 'Employment type list must be populated');
        System.assertNotEquals(null, opts.genders, 'Gender list must be populated');
        System.assertEquals(2, opts.statuses.size(), 'Status options are derived from the status pairs');

        for (KenAdminAlumniController.FilterOptionPair p : opts.sourcePairs) {
            System.assertNotEquals(null, p.count, 'Grouped options must carry a count');
            System.assertEquals(p.value + ' (' + p.count + ')', p.label, 'Label keeps the "value (count)" shape');
        }
    }

    /**
     * getFilterOptions used to retrieve every matching row per field (twice, via
     * a duplicate helper) to work out distinct values, which blew the 50,000
     * query-row limit on a real org and returned nothing for every dropdown.
     * Aggregate GROUP BY keeps the cost proportional to distinct values.
     */
    @IsTest
    static void testGetFilterOptionsStaysWellUnderQueryRowLimit() {
        Test.startTest();
        Integer rowsBefore = Limits.getQueryRows();
        KenAdminAlumniController.FilterOptions opts = KenAdminAlumniController.getFilterOptions('all', null);
        Integer rowsUsed = Limits.getQueryRows() - rowsBefore;
        Test.stopTest();

        System.assertNotEquals(null, opts, 'Filter options should be returned');
        System.assert(rowsUsed < 5000,
            'Filter options must not scan raw rows per field — used ' + rowsUsed + ' query rows');
    }

    /**
     * Location / City options came from PersonEmployment.Location__c only, so in
     * an org where most alumni have no employment row the dropdown listed a
     * handful of values and ignored every imported mailing city.
     */
    @IsTest
    static void testLocationOptionsIncludeMailingCityAndEmploymentLocation() {
        Account pa = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        pa.PersonMailingCity = 'Pune';
        update pa;

        Test.startTest();
        KenAdminAlumniController.FilterOptions opts = KenAdminAlumniController.getFilterOptions('all', null);
        KenAdminAlumniController.AlumniList byCity = KenAdminAlumniController.getAlumniRecords(
            'all', null, null, null, 25, 1, null, '{"location":"Pune"}');
        Test.stopTest();

        System.assert(opts.locations.contains('Pune'),
            'Mailing city should appear in the Location / City options. Got: ' + opts.locations);
        System.assert(byCity.totalRecords > 0, 'Filtering on a mailing city should return the alumnus');
    }

    /**
     * Filter dropdown counts must describe the ALUMNI in scope, not every row on
     * the source object — a person account with no Alumni ConstituentRole (a
     * student, staff member, or other role type) used to be counted, so the
     * dropdown advertised more records than applying the filter returned.
     */
    @IsTest
    static void testFilterOptionCountsExcludeNonAlumniPersonAccounts() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
        ]) { paRtId = rt.Id; }
        if (paRtId == null) return; // org has no person accounts — nothing to assert

        String outsiderCountry = kenDistinctiveCountry();
        Account outsider = new Account(
            RecordTypeId = paRtId, FirstName = 'Not', LastName = 'AnAlumnus',
            PersonMailingCountry = outsiderCountry, PersonMailingCity = 'Lemuria'
        );
        insert outsider; // deliberately NO ConstituentRole

        Test.startTest();
        KenAdminAlumniController.FilterOptions opts = KenAdminAlumniController.getFilterOptions('all', null);
        KenAdminAlumniController.AlumniList applied = KenAdminAlumniController.getAlumniRecords(
            'all', null, null, null, 25, 1, null, '{"country":"' + outsiderCountry + '"}');
        Test.stopTest();

        System.assertEquals(false, opts.countries.contains(outsiderCountry),
            'A person account with no Alumni role must not contribute a country option. Got: ' + opts.countries);
        System.assertEquals(false, opts.locations.contains('Lemuria'),
            'A person account with no Alumni role must not contribute a location option. Got: ' + opts.locations);
        System.assertEquals(0, applied.totalRecords,
            'Applying the filter returns nothing, which is exactly why the option must not be offered.');
    }

    /**
     * Intake options are grouped from the roles, not from LearningProgramPlan —
     * grouping the plan object listed every cohort in the org and counted plans
     * (always 1) instead of how many alumni are in that intake.
     */
    @IsTest
    static void testIntakeOptionsCountAlumniNotProgramPlans() {
        List<LearningProgramPlan> plans = [SELECT Id, Name FROM LearningProgramPlan LIMIT 1];
        if (plans.isEmpty()) return; // no plan data in this org

        List<ConstituentRole> roles = [SELECT Id FROM ConstituentRole WHERE RoleType = 'Alumni' LIMIT 2];
        for (ConstituentRole cr : roles) cr.Program_Plan__c = plans[0].Id;
        update roles;

        Test.startTest();
        KenAdminAlumniController.FilterOptions opts = KenAdminAlumniController.getFilterOptions('all', null);
        Test.stopTest();

        Boolean found = false;
        for (KenAdminAlumniController.FilterOptionPair p : opts.intakePairs) {
            if (p.value == plans[0].Name) {
                found = true;
                System.assertEquals(roles.size(), p.count,
                    'Intake count should be the number of alumni in the cohort, not the number of plan records.');
            }
        }
        System.assert(found, 'The cohort the alumni belong to should be an intake option.');
    }

    private static Id alumniLeadRecordTypeId() {
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Lead' AND DeveloperName = 'Alumni_Lead' LIMIT 1
        ]) { return rt.Id; }
        return null;
    }

    /**
     * The Leads tab lists Lead records, so its dropdowns must be grouped from
     * Lead. They used to be grouped from ConstituentRole like every other tab,
     * which offered programs and institutes belonging to roles — the option
     * advertised a count and applying it returned nothing.
     */
    @IsTest
    static void testLeadsTabFilterOptionsComeFromTheLeadObject() {
        Id rtId = alumniLeadRecordTypeId();
        if (rtId == null) return; // org has no Alumni Lead record type

        insert new Lead(
            RecordTypeId = rtId, FirstName = 'Filter', LastName = 'Source',
            Company = 'Self-Declared', Status = 'New',
            Institution_Name__c = 'Lead Institute', Country = kenDistinctiveCountry()
        );

        Test.startTest();
        KenAdminAlumniController.FilterOptions opts =
            KenAdminAlumniController.getFilterOptions('leads', null);
        KenAdminAlumniController.AlumniList applied = KenAdminAlumniController.getAlumniRecords(
            'leads', null, null, null, 25, 1, null, '{"institute":"Lead Institute"}');
        Test.stopTest();

        System.assert(opts.institutes.contains('Lead Institute'),
            'A lead\'s institution should be offered on the Leads tab. Got: ' + opts.institutes);
        // The sentinel has to be a value only a ConstituentRole can hold. A country
        // is useless for this: orgs with State & Country picklists default
        // Lead.CountryCode (KJS production defaults it to IN), so every lead carries
        // a country of its own and 'India' proves nothing. Source_Funnel__c values
        // and the roles' graduation years exist on no Lead field, so they can only
        // appear here if the options were grouped from ConstituentRole.
        System.assertEquals(false, opts.sources.contains('Historical Upload'),
            'A ConstituentRole source funnel must not leak into the Leads tab options. Got: ' + opts.sources);
        System.assertEquals(false, opts.graduationYears.contains('2010'),
            'A ConstituentRole graduation year must not leak into the Leads tab options. Got: ' + opts.graduationYears);
        System.assertEquals(1, applied.totalRecords,
            'Applying an offered Leads option must return the lead behind it.');
    }

    /**
     * The count beside an option is a promise about what applying it returns.
     */
    @IsTest
    static void testLeadsTabOptionCountsMatchAppliedResults() {
        Id rtId = alumniLeadRecordTypeId();
        if (rtId == null) return;

        List<Lead> batch = new List<Lead>();
        for (Integer i = 0; i < 3; i++) {
            batch.add(new Lead(
                RecordTypeId = rtId, FirstName = 'Count', LastName = 'Lead' + kenAlpha(i),
                Company = 'Self-Declared', Status = 'New',
                Institution_Name__c = 'Count Institute'
            ));
        }
        insert batch;

        Test.startTest();
        KenAdminAlumniController.FilterOptions opts =
            KenAdminAlumniController.getFilterOptions('leads', null);
        KenAdminAlumniController.AlumniList applied = KenAdminAlumniController.getAlumniRecords(
            'leads', null, null, null, 25, 1, null, '{"institute":"Count Institute"}');
        Test.stopTest();

        Integer advertised = null;
        for (KenAdminAlumniController.FilterOptionPair p : opts.institutePairs) {
            if (p.value == 'Count Institute') advertised = p.count;
        }
        System.assertEquals(3, advertised, 'The option should count the leads carrying that institution.');
        System.assertEquals(advertised, applied.totalRecords,
            'The count in the dropdown must equal what applying the filter returns.');
    }

    /**
     * Program option values are names. The Leads tab used to treat any 15- or
     * 18-character value as a record Id, and program names hit that length
     * ("B.A.Yogashastra" is exactly 15) — the resulting lookup comparison throws
     * a malformed-Id error instead of filtering.
     */
    @IsTest
    static void testLeadsTabProgramFilterAcceptsA15CharacterName() {
        Test.startTest();
        KenAdminAlumniController.AlumniList r = KenAdminAlumniController.getAlumniRecords(
            'leads', null, null, null, 25, 1, null, '{"program":"B.A.Yogashastra"}');
        Test.stopTest();
        System.assertEquals(0, r.totalRecords,
            'A 15-character program NAME must be matched as a name, not parsed as a record Id.');
    }

    /**
     * Person-side filters have no Lead counterpart, so the Leads tab hides them.
     * The option lists still have to come back as empty lists rather than null —
     * the LWC reads .length on them.
     */
    @IsTest
    static void testLeadsTabReturnsEmptyPersonFilterLists() {
        Test.startTest();
        KenAdminAlumniController.FilterOptions opts =
            KenAdminAlumniController.getFilterOptions('leads', null);
        Test.stopTest();

        System.assertEquals(0, opts.genderPairs.size(), 'Gender is a Person Account field — no options on Leads.');
        System.assertEquals(0, opts.employmentTypePairs.size(), 'Employment type has no Lead counterpart.');
        System.assertEquals(0, opts.preferencePairs.size(), 'Engagement preference has no Lead counterpart.');
        System.assertEquals(0, opts.statusPairs.size(), 'Every row on the Leads tab is an unconverted lead.');
        System.assertNotEquals(null, opts.languagePairs, 'Lists must be empty, never null.');
        System.assertNotEquals(null, opts.skillPairs, 'Lists must be empty, never null.');
    }

    @IsTest
    static void testGetFilterOptionsForEveryTabKey() {
        for (String tabKey : new List<String>{ 'all', 'oldportal', 'referrals' }) {
            KenAdminAlumniController.FilterOptions opts = KenAdminAlumniController.getFilterOptions(tabKey, null);
            System.assertNotEquals(null, opts, 'Tab ' + tabKey + ' should return filter options');
            System.assertNotEquals(null, opts.programPairs, 'Tab ' + tabKey + ' should return program pairs');
            System.assertEquals(2, opts.statusPairs.size(), 'Tab ' + tabKey + ' should return both status options');
        }
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
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
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
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1
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

    /**
     * The kill-switch silences the ConstituentRole provisioning side effects this
     * lean fixture cannot support. Moving a role to a provisioning status makes the
     * trigger create a community user, and System.setPassword refuses in an org
     * whose Experience site has no email settings, which rolls the update back.
     * This test is about the field history, not about provisioning.
     */
    @IsTest
    static void testGetFieldUpdateHistory() {
        Ken_Alm_Bypass_Settings__c triggerSettings = KenSettings.bypass();
        if (triggerSettings == null || triggerSettings.Id == null) {
            triggerSettings = new Ken_Alm_Bypass_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        triggerSettings.Skip_ConstituentRole_Trigger__c = true;
        upsert triggerSettings;

        Id id0 = roleId('REG-0');
        ConstituentRole cr = [SELECT Id, Registration_Status__c FROM ConstituentRole WHERE Id = :id0];
        cr.Registration_Status__c = 'Onboarding In Progress';
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

    /* ---- Lead Workspace: owner ---- */
    @IsTest
    static void testGetAlumniDetailIncludesOwner() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.AlumniDetail d = KenAdminAlumniController.getAlumniDetail(id0);
        Test.stopTest();
        System.assertNotEquals(null, d.ownerId, 'Detail should carry the record owner.');
        System.assertNotEquals(null, d.ownerName, 'Detail should carry the owner name.');
        System.assertNotEquals(null, d.ownerInitials, 'Detail should carry owner initials for the avatar chip.');
    }

    @IsTest
    static void testGetAssignableOwners() {
        String uname = [SELECT Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Name;
        Test.startTest();
        List<KenAdminAlumniController.OwnerOption> all = KenAdminAlumniController.getAssignableOwners(null);
        List<KenAdminAlumniController.OwnerOption> byName =
            KenAdminAlumniController.getAssignableOwners(uname.substring(0, 2));
        Test.stopTest();
        System.assert(all.size() >= 1, 'A blank search should still return active users.');
        System.assert(byName.size() >= 1, 'Searching by a name fragment should return at least the running user.');
        System.assertEquals('User', byName[byName.size() - 1].ownerType, 'User options should be typed as User.');
    }

    @IsTest
    static void testChangeLeadOwner() {
        Id id0 = roleId('REG-0');
        // Owner changes are a plain field update; silence the CR trigger so the
        // lean fixture doesn't trip unrelated onboarding side-effects.
        Ken_Alm_Bypass_Settings__c s = KenSettings.bypass();
        if (s == null || s.Id == null) {
            s = new Ken_Alm_Bypass_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.Skip_ConstituentRole_Trigger__c = true;
        upsert s;
        Id me = UserInfo.getUserId();
        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.changeLeadOwner(id0, me, 'regional routing');
        Test.stopTest();
        System.assertEquals(true, res.success, res.message);
        ConstituentRole cr = [SELECT OwnerId FROM ConstituentRole WHERE Id = :id0 LIMIT 1];
        System.assertEquals(me, cr.OwnerId, 'Owner should be reassigned to the chosen user.');
        // The change should also be logged as a Task on the person account.
        Id personId = [SELECT PersonId FROM ConstituentRole WHERE Id = :id0 LIMIT 1].PersonId;
        List<Task> logged = [SELECT Subject FROM Task WHERE WhatId = :personId AND Subject LIKE '[Owner]%'];
        System.assert(!logged.isEmpty(), 'An owner change should be logged to activity as a Task.');
    }

    @IsTest
    static void testChangeLeadOwnerRequiresInputs() {
        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.changeLeadOwner(null, null, null);
        Test.stopTest();
        System.assertEquals(false, res.success, 'Owner change must require a record and a new owner.');
    }

    /* ---- Lead Workspace: communication ---- */
    @IsTest
    static void testLogCommunicationAndReadLog() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.logCommunication(
            id0, 'email', 'Verification invite', 'Please confirm your batch.', 'sent');
        List<KenAdminAlumniController.CommEntry> log = KenAdminAlumniController.getCommunicationLog(id0);
        Test.stopTest();
        System.assertEquals(true, res.success, res.message);
        System.assert(!log.isEmpty(), 'The logged communication should appear in the outreach log.');
        System.assertEquals('Email', log[0].channel, 'Channel should be parsed back from the subject prefix.');
        System.assertEquals('Verification invite', log[0].title, 'Title should strip the channel prefix.');
    }

    @IsTest
    static void testLogCommunicationRequiresChannel() {
        Id id0 = roleId('REG-0');
        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.logCommunication(id0, '', 'x', 'y', null);
        Test.stopTest();
        System.assertEquals(false, res.success, 'A channel is required to log a communication.');
    }

    @IsTest
    static void testGetCommunicationLogNullGuard() {
        Test.startTest();
        List<KenAdminAlumniController.CommEntry> log = KenAdminAlumniController.getCommunicationLog(null);
        Test.stopTest();
        System.assertEquals(0, log.size(), 'A null id should return an empty log, not throw.');
    }

    @IsTest
    static void testActivityTimelineIncludesLoggedCommunication() {
        Id id0 = roleId('REG-0');
        KenAdminAlumniController.logCommunication(id0, 'call', 'Left voicemail', 'No answer.', null);
        Test.startTest();
        List<KenAdminAlumniController.TimelineEntry> tl =
            KenAdminAlumniController.getActivityTimeline(id0);
        Test.stopTest();
        Boolean foundComm = false;
        for (KenAdminAlumniController.TimelineEntry e : tl) {
            if (e.kind == 'communication') foundComm = true;
        }
        System.assert(foundComm, 'A logged communication should surface in the activity timeline as a communication event.');
    }

    /* ---- Lead Workspace: Lead-Id path (Leads/Referrals tabs pass a Lead Id) ---- */
    @IsTest
    static void testGetAlumniDetailForLeadId() {
        Id leadId = [SELECT Id FROM Lead WHERE Email = 'lead.pending@example.test' LIMIT 1].Id;
        Test.startTest();
        KenAdminAlumniController.AlumniDetail d = KenAdminAlumniController.getAlumniDetail(leadId);
        Test.stopTest();
        System.assertNotEquals(null, d, 'Detail should resolve for a Lead Id, not just a ConstituentRole Id.');
        System.assertEquals(leadId, d.alumniId);
        System.assertEquals('lead.pending@example.test', d.email, 'Lead email should populate the rail.');
        System.assertEquals('Test University', d.institute, 'Rail should carry the lead-form institute.');
        System.assertNotEquals(null, d.ownerName, 'Lead owner should resolve so the rail is not "Unassigned".');
    }

    @IsTest
    static void testChangeOwnerForLeadId() {
        Id leadId = [SELECT Id FROM Lead WHERE Email = 'lead.pending@example.test' LIMIT 1].Id;
        Id me = UserInfo.getUserId();
        Ken_Alm_Bypass_Settings__c s = KenSettings.bypass();
        if (s == null || s.Id == null) {
            s = new Ken_Alm_Bypass_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.Skip_Lead_Trigger__c = true;
        upsert s;
        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.changeLeadOwner(leadId, me, 'testing');
        Test.stopTest();
        System.assertEquals(true, res.success, res.message);
        Lead updated = [SELECT OwnerId FROM Lead WHERE Id = :leadId LIMIT 1];
        System.assertEquals(me, updated.OwnerId, 'A Lead-Id owner change should update Lead.OwnerId.');
        List<Task> logged = [SELECT Id FROM Task WHERE WhoId = :leadId AND Subject LIKE '[Owner]%'];
        System.assert(!logged.isEmpty(), 'Owner change on a lead should log a Task against the lead.');
    }

    @IsTest
    static void testCommunicationForLeadId() {
        Id leadId = [SELECT Id FROM Lead WHERE Email = 'lead.pending@example.test' LIMIT 1].Id;
        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.logCommunication(leadId, 'sms', 'Verify link', 'Sent link.', null);
        List<KenAdminAlumniController.CommEntry> log = KenAdminAlumniController.getCommunicationLog(leadId);
        List<KenAdminAlumniController.TimelineEntry> tl = KenAdminAlumniController.getActivityTimeline(leadId);
        Test.stopTest();
        System.assertEquals(true, res.success, res.message);
        System.assert(!log.isEmpty(), 'A communication logged against a lead should read back from the lead.');
        System.assertEquals('SMS', log[0].channel);
        Boolean sawCapture = false;
        for (KenAdminAlumniController.TimelineEntry e : tl) {
            if (e.title != null && e.title.startsWith('Lead captured')) sawCapture = true;
        }
        System.assert(sawCapture, 'Lead activity timeline should include the capture event.');
    }

    /* ============================================================
       Lead-to-lead merge — a duplicate pair of pending registrations,
       where neither record has an identity yet and there is no master
       to merge into.
       ============================================================ */

    private static Lead pendingLead(String first, String last, String email, String phone, String regNum, String gradYear) {
        return new Lead(
            FirstName = first, LastName = last, Email = email, Phone = phone,
            Company = 'Self-Declared', Status = 'New',
            Registration_Number__c = regNum, Year_of_Graduation__c = gradYear
        );
    }

    private static KenAdminAlumniController.MergeCandidate candidateFor(
        List<KenAdminAlumniController.MergeCandidate> candidates, Id recordId
    ) {
        for (KenAdminAlumniController.MergeCandidate c : candidates) {
            if (c.alumniId == recordId) return c;
        }
        return null;
    }

    @IsTest
    static void testGetMergeSuggestionsIncludesPendingLeads() {
        Lead source = pendingLead('Dup', 'Source', 'dup.source@example.test', '9000010001', 'DUP-100', '2015');
        Lead twin = pendingLead('Dup', 'Twin', 'dup.twin@example.test', '9000010002', 'DUP-100', '2015');
        insert new List<Lead>{ source, twin };

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(source.Id);
        Test.stopTest();

        KenAdminAlumniController.MergeCandidate twinRow = candidateFor(suggestions, twin.Id);
        System.assertNotEquals(null, twinRow,
            'A pending lead sharing the registration number should be offered as a merge candidate.');
        System.assertEquals('lead', twinRow.candidateType,
            'A lead candidate must be badged as a lead so the UI can tell it apart from a master.');
        System.assertEquals('New', twinRow.statusLabel, 'Lead candidates carry their own Status.');
        System.assert(twinRow.matchedOn != null && twinRow.matchedOn.contains('Registration number'),
            'The registration-number match should be reported. Actual: ' + twinRow.matchedOn);
        System.assertEquals(null, candidateFor(suggestions, source.Id),
            'A lead must never be offered as a candidate for merging into itself.');
    }

    @IsTest
    static void testGetMergeSuggestionsSkipsLeadsThatAlreadyHaveARole() {
        // The @TestSetup lead is linked to REG-1's ConstituentRole, so it is
        // reachable as a MASTER candidate through that role — offering it as a
        // lead candidate too would both duplicate the row and let an admin write
        // to the lead while leaving the role stale.
        Lead linked = [SELECT Id, Email FROM Lead WHERE Email = 'lead.pending@example.test' LIMIT 1];
        Lead source = pendingLead('Same', 'Email', linked.Email, '9000010003', 'DUP-200', '2016');
        insert source;

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(source.Id);
        Test.stopTest();

        KenAdminAlumniController.MergeCandidate linkedRow = candidateFor(suggestions, linked.Id);
        System.assertEquals(null, linkedRow,
            'A lead that already has a ConstituentRole must not appear as a lead candidate.');
    }

    @IsTest
    static void testGetMergeCandidatesSearchFindsPendingLeads() {
        Lead twin = pendingLead('Searchable', 'Duplicate', 'searchable.dup@example.test', '9000010004', 'SRCH-1', '2017');
        insert twin;

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> candidates =
            KenAdminAlumniController.getMergeCandidates('Searchable', null, null);
        Test.stopTest();

        KenAdminAlumniController.MergeCandidate row = candidateFor(candidates, twin.Id);
        System.assertNotEquals(null, row, 'The free-text search should reach pending leads, not only masters.');
        System.assertEquals('lead', row.candidateType);
    }

    @IsTest
    static void testGetMergeFieldComparisonAgainstALeadTarget() {
        // The target lead has a graduation year but no phone; the incoming lead
        // is the other way round — so one row must default to 'existing' and the
        // other to 'incoming' off the same comparison.
        Lead target = pendingLead('Target', 'Lead', 'target.lead@example.test', null, 'CMP-1', '2013');
        Lead incoming = pendingLead('Incoming', 'Lead', 'incoming.lead@example.test', '9000010005', null, null);
        insert new List<Lead>{ target, incoming };

        Test.startTest();
        List<KenAdminAlumniController.MergeFieldRow> rows =
            KenAdminAlumniController.getMergeFieldComparison(incoming.Id, target.Id);
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'A lead target must produce a comparison, same as a master target.');
        Map<String, KenAdminAlumniController.MergeFieldRow> byKey =
            new Map<String, KenAdminAlumniController.MergeFieldRow>();
        for (KenAdminAlumniController.MergeFieldRow r : rows) byKey.put(r.fieldKey, r);

        KenAdminAlumniController.MergeFieldRow gradYear = byKey.get('gradYear');
        System.assertNotEquals(null, gradYear, 'Graduation year should be comparable against a lead target.');
        System.assertEquals('2013', gradYear.existingValue, 'The target lead supplies the existing value.');
        System.assertEquals('existing', gradYear.defaultSide,
            'The target already has a graduation year, so existing wins by default.');

        KenAdminAlumniController.MergeFieldRow phone = byKey.get('phone');
        System.assertNotEquals(null, phone);
        System.assertEquals('9000010005', phone.incomingValue);
        System.assertEquals('incoming', phone.defaultSide,
            'The target lead has no phone, so the incoming value should fill the gap.');

        KenAdminAlumniController.MergeFieldRow email = byKey.get('email');
        System.assertEquals('target.lead@example.test', email.existingValue,
            'Email on a lead target reads from Lead.Email.');
    }

    @IsTest
    static void testGetMergeFieldComparisonRefusesSelfComparison() {
        Lead solo = pendingLead('Solo', 'Lead', 'solo.lead@example.test', null, 'SOLO-1', '2014');
        insert solo;
        Test.startTest();
        List<KenAdminAlumniController.MergeFieldRow> rows =
            KenAdminAlumniController.getMergeFieldComparison(solo.Id, solo.Id);
        Test.stopTest();
        System.assert(rows.isEmpty(), 'Comparing a lead against itself must produce nothing.');
    }

    @IsTest
    static void testMergeLeadIntoAnotherLeadGapFills() {
        Lead target = pendingLead('Keep', 'Me', 'keep.me@example.test', null, null, '2011');
        Lead incoming = pendingLead('Fold', 'Me', 'fold.me@example.test', '9000010006', 'FOLD-1', '2099');
        insert new List<Lead>{ target, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(incoming.Id, target.Id, null);
        Test.stopTest();

        System.assertEquals(true, res.success, 'A lead-to-lead merge should succeed. Message: ' + res.message);

        Lead survivor = [
            SELECT Status, Is_Converted__c, Phone, Registration_Number__c, Year_of_Graduation__c
            FROM Lead WHERE Id = :target.Id LIMIT 1
        ];
        System.assertEquals('New', survivor.Status, 'The surviving lead stays pending — it was not merged away.');
        System.assertNotEquals(true, survivor.Is_Converted__c,
            'The survivor must stay provisionable; only the folded lead is flagged converted.');
        System.assertEquals('9000010006', survivor.Phone, 'A blank field on the survivor is gap-filled.');
        System.assertEquals('FOLD-1', survivor.Registration_Number__c, 'A blank registration number is gap-filled.');
        System.assertEquals('2011', survivor.Year_of_Graduation__c,
            'A value the survivor already holds is never overwritten by default.');

        Lead folded = [SELECT Status, Is_Converted__c, Master_Lead__c FROM Lead WHERE Id = :incoming.Id LIMIT 1];
        System.assertEquals('Merged', folded.Status, 'The folded lead is marked Merged.');
        System.assertEquals(true, folded.Is_Converted__c,
            'Is_Converted__c stops the folded lead from provisioning a Person Account of its own.');
        System.assertEquals(target.Id, folded.Master_Lead__c,
            'Master_Lead__c on the folded lead must point at the surviving lead.');
    }

    @IsTest
    static void testMergeLeadIntoAnotherLeadHonorsFieldChoice() {
        Lead target = pendingLead('Choice', 'Target', 'choice.target@example.test', null, null, '2011');
        Lead incoming = pendingLead('Choice', 'Incoming', 'choice.incoming@example.test', null, null, '2020');
        insert new List<Lead>{ target, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeLeadIntoMaster(
            incoming.Id, target.Id, '{"gradYear":"incoming"}'
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'Merge with a field choice should succeed. Message: ' + res.message);
        Lead survivor = [SELECT Year_of_Graduation__c FROM Lead WHERE Id = :target.Id LIMIT 1];
        System.assertEquals('2020', survivor.Year_of_Graduation__c,
            'An explicit incoming pick overwrites the survivor even though it already had a value.');
    }

    @IsTest
    static void testMergeLeadRefusesItself() {
        Lead solo = pendingLead('Self', 'Merge', 'self.merge@example.test', null, null, '2012');
        insert solo;
        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(solo.Id, solo.Id, null);
        Test.stopTest();
        System.assertEquals(false, res.success, 'A lead must not be mergeable into itself.');
    }

    @IsTest
    static void testMergeLeadIntoLeadRefusesAClosedTarget() {
        Lead target = pendingLead('Closed', 'Target', 'closed.target@example.test', null, null, '2012');
        target.Status = 'Rejected';
        Lead incoming = pendingLead('Live', 'Incoming', 'live.incoming@example.test', null, null, '2013');
        insert new List<Lead>{ target, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(incoming.Id, target.Id, null);
        Test.stopTest();

        System.assertEquals(false, res.success,
            'Merging into a rejected/merged/converted lead must be refused, not silently written.');
        Lead untouched = [SELECT Status FROM Lead WHERE Id = :incoming.Id LIMIT 1];
        System.assertEquals('New', untouched.Status, 'A refused merge must leave the incoming lead alone.');
    }

    @IsTest
    static void testSiblingAbsorptionNeverSwallowsTheTargetLead() {
        // Target and incoming share an email, which is exactly the shape the
        // same-email absorption pass looks for. It must skip the survivor, or the
        // merge would mark the very record it just merged into as Merged.
        String sharedEmail = 'shared.pair@example.test';
        Lead target = pendingLead('Shared', 'Survivor', sharedEmail, null, null, '2010');
        Lead incoming = pendingLead('Shared', 'Folded', sharedEmail, '9000010007', null, null);
        insert new List<Lead>{ target, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(incoming.Id, target.Id, null);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        Lead survivor = [SELECT Status, Master_Lead__c FROM Lead WHERE Id = :target.Id LIMIT 1];
        System.assertEquals('New', survivor.Status,
            'The survivor shares the email but must never be absorbed as its own sibling.');
        System.assertEquals(null, survivor.Master_Lead__c,
            'The survivor must not be pointed at anything — it is the record being kept.');
    }

    @IsTest
    static void testMergeCandidatesIntoOneKeepsTheMasterAndSupersedesAPendingLead() {
        // The mixed comparison that IS allowed: the master is kept (it owns the
        // Person Account, so it must be the survivor) and a pending lead that was
        // compared alongside it loses. That lead is superseded directly — not via
        // any Lead__c link, since it has no role of its own.
        Id keptRoleId = roleId('REG-0');
        Lead losingLead = pendingLead('Losing', 'Candidate', 'losing.candidate@example.test', null, null, '2018');
        Lead incoming = pendingLead('Folded', 'Lead', 'folded.lead@example.test', '9000010008', 'WIN-1', null);
        insert new List<Lead>{ losingLead, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            incoming.Id, keptRoleId, '{"gradYear":"2018"}', new List<Id>{ losingLead.Id }
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'Keeping the master should succeed. Message: ' + res.message);

        ConstituentRole kept = [
            SELECT Lead__c, Registration_Number__c, Graduation_Year__c
            FROM ConstituentRole WHERE Id = :keptRoleId LIMIT 1
        ];
        System.assertEquals(incoming.Id, kept.Lead__c, 'The kept master links to the lead just merged.');
        System.assertEquals('REG-0', kept.Registration_Number__c,
            'An unresolved field the master already holds is never overwritten by the incoming lead.');
        System.assertEquals('2018', kept.Graduation_Year__c, 'The resolved value should be written as chosen.');

        Lead folded = [SELECT Status, Master_Lead__c FROM Lead WHERE Id = :incoming.Id LIMIT 1];
        System.assertEquals('Merged', folded.Status);
        System.assertEquals(null, folded.Master_Lead__c,
            'The merged lead IS the surviving lead for a master target, so it points at nothing.');

        Lead superseded = [SELECT Status, Is_Converted__c, Master_Lead__c FROM Lead WHERE Id = :losingLead.Id LIMIT 1];
        System.assertEquals('Merged', superseded.Status, 'A pending lead that lost is superseded directly.');
        System.assertEquals(true, superseded.Is_Converted__c,
            'A superseded lead must not go on to provision an identity of its own.');
        System.assertEquals(incoming.Id, superseded.Master_Lead__c,
            'It should point at the lead now linked to the surviving master.');
    }

    @IsTest
    static void testGetMergeFieldComparisonMultiMixesLeadAndMasterColumns() {
        Id masterId = roleId('REG-0');
        Lead leadCandidate = pendingLead('Mixed', 'Candidate', 'mixed.candidate@example.test', null, 'MIX-1', '2021');
        Lead incoming = pendingLead('Mixed', 'Incoming', 'mixed.incoming@example.test', null, null, '2022');
        insert new List<Lead>{ leadCandidate, incoming };

        Test.startTest();
        List<KenAdminAlumniController.MergeFieldRowMulti> rows =
            KenAdminAlumniController.getMergeFieldComparisonMulti(
                incoming.Id, new List<Id>{ masterId, leadCandidate.Id }
            );
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'A mixed master + lead comparison should return rows.');
        Map<String, KenAdminAlumniController.MergeFieldRowMulti> byKey =
            new Map<String, KenAdminAlumniController.MergeFieldRowMulti>();
        for (KenAdminAlumniController.MergeFieldRowMulti r : rows) byKey.put(r.fieldKey, r);

        KenAdminAlumniController.MergeFieldRowMulti gradYear = byKey.get('gradYear');
        System.assertNotEquals(null, gradYear);
        System.assertEquals(2, gradYear.existingValues.size(),
            'One column per candidate, in the order they were passed.');
        System.assertEquals('2010', gradYear.existingValues[0], 'Column 0 is the master (REG-0, 2010).');
        System.assertEquals('2021', gradYear.existingValues[1], 'Column 1 is the pending lead.');
        System.assertEquals('2022', gradYear.incomingValue);
    }

    /* ============================================================
       No double-listing. A lead that has produced (or is producing) a
       ConstituentRole must never appear as a lead candidate as well —
       otherwise the same person shows up twice in one comparison.
       ============================================================ */

    /** Silences KenLeadTrigger so a Verified/Converted fixture doesn't kick off real provisioning. */
    private static void bypassLeadTrigger() {
        Ken_Alm_Bypass_Settings__c settings = KenSettings.bypass();
        settings.Skip_Lead_Trigger__c = true;
        upsert settings;
    }

    @IsTest
    static void testConvertedLeadIsNotOfferedAlongsideItsOwnMaster() {
        // The exact double-listing case: a converted lead still exists next to the
        // ConstituentRole it produced, and both match the incoming lead on
        // registration number. Only the role may be offered.
        bypassLeadTrigger();
        Id masterId = roleId('REG-2');

        Lead converted = pendingLead('Already', 'Converted', 'already.converted@example.test', '9000020001', 'REG-2', '2012');
        converted.Status = 'Converted';
        converted.Is_Converted__c = true;
        insert converted;
        update new ConstituentRole(Id = masterId, Lead__c = converted.Id);

        Lead source = pendingLead('Dup', 'Source', 'dup.of.converted@example.test', '9000020009', 'REG-2', '2012');
        insert source;

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(source.Id);
        Test.stopTest();

        System.assertEquals(null, candidateFor(suggestions, converted.Id),
            'A converted lead must not be offered — the ConstituentRole it produced represents it.');
        System.assertNotEquals(null, candidateFor(suggestions, masterId),
            'The role the converted lead produced is the candidate that should appear.');
    }

    @IsTest
    static void testVerifiedLeadIsNotOfferedAsAPendingCandidate() {
        // 'Verified' is the window between convertLeads() approving a lead and
        // provisioning stamping 'Converted'. The lead is no longer pending, so it
        // must be excluded on status alone — without relying on a
        // ConstituentRole.Lead__c link existing yet.
        bypassLeadTrigger();

        Lead verified = pendingLead('Mid', 'Flight', 'mid.flight@example.test', '9000020002', 'VER-1', '2019');
        verified.Status = 'Verified';
        Database.DMLOptions allowDupes = new Database.DMLOptions();
        allowDupes.DuplicateRuleHeader.AllowSave = true;
        Database.insert(verified, allowDupes);

        Lead source = pendingLead('Mid', 'Flight', 'source.midflight@example.test', '9000020003', 'VER-1', '2019');
        Database.DMLOptions allowDuplicates = new Database.DMLOptions();
        allowDuplicates.DuplicateRuleHeader.AllowSave = true;
        Database.insert(source, allowDuplicates);

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(source.Id);
        List<KenAdminAlumniController.MergeCandidate> searched =
            KenAdminAlumniController.getMergeCandidates('Mid', null, source.Id);
        Test.stopTest();

        System.assertEquals(null, candidateFor(suggestions, verified.Id),
            'A verified lead is mid-provisioning and must not be suggested.');
        System.assertEquals(null, candidateFor(searched, verified.Id),
            'The free-text search must apply the same eligibility rule as the suggestions.');
    }

    @IsTest
    static void testMergeRefusesAVerifiedLeadAsTarget() {
        bypassLeadTrigger();

        Lead target = pendingLead('Verified', 'Target', 'verified.target@example.test', null, null, '2013');
        target.Status = 'Verified';
        Lead incoming = pendingLead('Pending', 'Incoming', 'pending.incoming@example.test', null, null, '2014');
        insert new List<Lead>{ target, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(incoming.Id, target.Id, null);
        Test.stopTest();

        System.assertEquals(false, res.success,
            'Merging into a verified lead must be refused — provisioning is already under way on it.');
        Lead untouched = [SELECT Status FROM Lead WHERE Id = :incoming.Id LIMIT 1];
        System.assertEquals('New', untouched.Status, 'A refused merge must leave the incoming lead alone.');
    }

    @IsTest
    static void testSiblingAbsorptionSkipsVerifiedDuplicates() {
        // A same-email duplicate that is already verified is mid-provisioning;
        // absorbing it would fight the trigger working on it.
        bypassLeadTrigger();
        Id masterId = roleId('REG-3');
        String sharedEmail = 'verified.sibling@example.test';

        Lead verifiedSibling = pendingLead('Verified', 'Sibling', sharedEmail, null, 'VSIB-1', '2015');
        verifiedSibling.Status = 'Verified';
        Lead primary = pendingLead('Primary', 'Merging', sharedEmail, '9000020004', null, null);
        insert new List<Lead>{ verifiedSibling, primary };

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(primary.Id, masterId, null);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        Lead sibling = [SELECT Status, Master_Lead__c FROM Lead WHERE Id = :verifiedSibling.Id LIMIT 1];
        System.assertEquals('Verified', sibling.Status,
            'A verified same-email duplicate must be left for provisioning, not absorbed.');
        System.assertEquals(null, sibling.Master_Lead__c,
            'An untouched verified duplicate should not be pointed at anything.');
    }

    @IsTest
    static void testCannotKeepALeadWhenAMasterIsInTheSameComparison() {
        // A master owns a Person Account, a portal user and related records that
        // have nowhere to go on a Lead. Keeping the lead would strand that identity
        // while marking its linked lead Merged, so this combination is refused.
        Id masterId = roleId('REG-0');
        Lead leadCandidate = pendingLead('Strand', 'Risk', 'strand.risk@example.test', null, null, '2018');
        Lead incoming = pendingLead('Strand', 'Incoming', 'strand.incoming@example.test', null, null, '2019');
        insert new List<Lead>{ leadCandidate, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            incoming.Id, leadCandidate.Id, null, new List<Id>{ masterId }
        );
        Test.stopTest();

        System.assertEquals(false, res.success,
            'Keeping a pending lead while a master is in the comparison must be refused.');

        Lead untouchedIncoming = [SELECT Status FROM Lead WHERE Id = :incoming.Id LIMIT 1];
        System.assertEquals('New', untouchedIncoming.Status, 'A refused merge writes nothing to the incoming lead.');
        Lead untouchedCandidate = [SELECT Year_of_Graduation__c FROM Lead WHERE Id = :leadCandidate.Id LIMIT 1];
        System.assertEquals('2018', untouchedCandidate.Year_of_Graduation__c,
            'A refused merge writes nothing to the would-be survivor either.');
    }

    @IsTest
    static void testKeepingALeadIsAllowedWhenOnlyLeadsAreInTheComparison() {
        // The counterpart to the guard above: with no master on the table there is
        // nothing to strand, so lead-only comparisons must still go through.
        Lead survivor = pendingLead('OnlyLeads', 'Survivor', 'onlyleads.survivor@example.test', null, null, '2018');
        Lead otherLead = pendingLead('OnlyLeads', 'Other', 'onlyleads.other@example.test', null, 'OL-2', null);
        Lead incoming = pendingLead('OnlyLeads', 'Incoming', 'onlyleads.incoming@example.test', '9000020005', null, null);
        insert new List<Lead>{ survivor, otherLead, incoming };

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            incoming.Id, survivor.Id, null, new List<Id>{ otherLead.Id }
        );
        Test.stopTest();

        System.assertEquals(true, res.success, 'A lead-only comparison should still merge. Message: ' + res.message);
        Lead kept = [SELECT Status, Phone FROM Lead WHERE Id = :survivor.Id LIMIT 1];
        System.assertEquals('New', kept.Status);
        System.assertEquals('9000020005', kept.Phone, 'Gap-fill still applies to the surviving lead.');
        Lead superseded = [SELECT Status, Master_Lead__c FROM Lead WHERE Id = :otherLead.Id LIMIT 1];
        System.assertEquals('Merged', superseded.Status, 'The lead that lost is superseded.');
        System.assertEquals(survivor.Id, superseded.Master_Lead__c);
    }

    @IsTest
    static void testLeadCandidatesAreScopedToTheIncomingRecordType() {
        // Several orgs share the Lead object with Admissions. A lead on a different
        // record type is a different module's record, not an alumni duplicate.
        List<RecordType> leadTypes = [
            SELECT Id FROM RecordType WHERE SobjectType = 'Lead' AND IsActive = true LIMIT 2
        ];
        if (leadTypes.size() < 2) return; // org has no second Lead record type to prove it with

        Lead source = pendingLead('CrossType', 'Source', 'crosstype.source@example.test', '9000020006', 'XT-1', '2020');
        source.RecordTypeId = leadTypes[0].Id;
        Lead otherType = pendingLead('CrossType', 'Other', 'crosstype.other@example.test', '9000020006', 'XT-1', '2020');
        otherType.RecordTypeId = leadTypes[1].Id;
        Lead sameType = pendingLead('CrossType', 'Same', 'crosstype.same@example.test', '9000020006', 'XT-1', '2020');
        sameType.RecordTypeId = leadTypes[0].Id;
        insert new List<Lead>{ source, otherType, sameType };

        Test.startTest();
        List<KenAdminAlumniController.MergeCandidate> suggestions =
            KenAdminAlumniController.getMergeSuggestions(source.Id);
        Test.stopTest();

        System.assertEquals(null, candidateFor(suggestions, otherType.Id),
            'A lead on another record type must not be offered as an alumni duplicate.');
        System.assertNotEquals(null, candidateFor(suggestions, sameType.Id),
            'A duplicate on the same record type must still be offered.');
    }

    @IsTest
    static void testMergeRefusesAMasterWithNoReachablePersonAccount() {
        // Name, phone and email live on the Person Account. With none reachable the
        // merge would write the role fields and silently drop the rest, so it is
        // refused outright rather than half-applied.
        ConstituentRole orphan = new ConstituentRole(RoleType = 'Alumni', Source_Funnel__c = 'Self-Declared Lead');
        orphan.put('Status', 'Active');
        Boolean personIdIsOptional = true;
        try {
            insert orphan;
        } catch (Exception e) {
            personIdIsOptional = false; // PersonId is required in this org — the case is unreachable
        }
        if (!personIdIsOptional) return;

        Lead incoming = pendingLead('Orphan', 'Target', 'orphan.target@example.test', '9000020007', 'ORPH-1', '2016');
        insert incoming;

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(incoming.Id, orphan.Id, null);
        Test.stopTest();

        System.assertEquals(false, res.success,
            'A master with no reachable Person Account must be refused, not partially written.');
        Lead untouched = [SELECT Status FROM Lead WHERE Id = :incoming.Id LIMIT 1];
        System.assertEquals('New', untouched.Status, 'A refused merge leaves the incoming lead alone.');
    }

    @IsTest
    static void testMergeReportsHowManyDuplicatesWereAbsorbed() {
        // The count matters: silently folding away three extra records and reporting
        // only "merged" leaves the admin with no idea what the merge touched.
        Id masterId = roleId('REG-0');
        String sharedEmail = 'counted.dupes@example.test';
        Lead primary = pendingLead('Counted', 'Primary', sharedEmail, '9000020008', null, null);
        List<Lead> batch = new List<Lead>{ primary };
        for (Integer i = 0; i < 3; i++) {
            batch.add(pendingLead('Counted', 'Sib' + kenAlpha(i), sharedEmail, null, 'CNT-' + i, null));
        }
        insert batch;

        Test.startTest();
        KenAdminAlumniController.SaveResult res =
            KenAdminAlumniController.mergeLeadIntoMaster(primary.Id, masterId, null);
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        System.assert(res.message.contains('3 further duplicates'),
            'The result should state how many duplicates were absorbed. Actual: ' + res.message);
        Integer stillOpen = [
            SELECT COUNT() FROM Lead WHERE Email = :sharedEmail AND Status != 'Merged'
        ];
        System.assertEquals(0, stillOpen, 'Every same-email duplicate should end up Merged.');
    }

    @IsTest
    static void testSupersededVerifiedLeadKeepsItsStatusButGetsTheTrail() {
        // A verified lead is mid-provisioning. Superseding its candidate should
        // record where it went WITHOUT rewriting the status the provisioning flow
        // owns — the trail is safe to set, the status is not.
        bypassLeadTrigger();
        Id keptRoleId = roleId('REG-0');
        Id losingRoleId = roleId('REG-3');

        Lead verifiedLinked = pendingLead('Verified', 'Linked', 'verified.linked@example.test', null, 'VLK-1', '2013');
        verifiedLinked.Status = 'Verified';
        insert verifiedLinked;
        update new ConstituentRole(Id = losingRoleId, Lead__c = verifiedLinked.Id);

        Lead incoming = pendingLead('Trail', 'Incoming', 'trail.incoming@example.test', null, null, '2014');
        insert incoming;

        Test.startTest();
        KenAdminAlumniController.SaveResult res = KenAdminAlumniController.mergeCandidatesIntoOne(
            incoming.Id, keptRoleId, null, new List<Id>{ losingRoleId }
        );
        Test.stopTest();

        System.assertEquals(true, res.success, res.message);
        Lead superseded = [SELECT Status, Master_Lead__c FROM Lead WHERE Id = :verifiedLinked.Id LIMIT 1];
        System.assertEquals('Verified', superseded.Status,
            'A verified lead keeps the status its provisioning flow owns.');
        System.assertEquals(incoming.Id, superseded.Master_Lead__c,
            'The trail back to the surviving lead is still recorded.');
    }
}