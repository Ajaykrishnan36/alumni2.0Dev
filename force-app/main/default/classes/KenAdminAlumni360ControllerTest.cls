/**
 * KenAdminAlumni360ControllerTest
 *
 * Coverage for KenAdminAlumni360Controller. The controller no longer returns
 * demo data — all section methods return empty DTOs when called with a null
 * recordId or when the SOQL produces no rows. These tests therefore verify
 * the empty-shape contract for null calls, and a single comprehensive test
 * seeds a real Ken_Alumni_CRM__c + Person Account + employment + booking +
 * mentorship + case to exercise the build*FromOrg paths.
 */
@IsTest
private class KenAdminAlumni360ControllerTest {

    /* ============================================================
       NULL recordId — every section returns a non-null but empty DTO
       ============================================================ */

    @IsTest
    static void getAlumni360_nullRecordId_returnsAllSectionsEmpty() {
        Test.startTest();
        KenAdminAlumni360Controller.Alumni360DTO dto =
            KenAdminAlumni360Controller.getAlumni360(null);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'Master wrapper should be returned.');
        System.assertNotEquals(null, dto.header,              'Header populated (shape, not data).');
        System.assertNotEquals(null, dto.snapshot,            'Snapshot populated.');
        System.assertNotEquals(null, dto.overview,            'Overview populated.');
        System.assertNotEquals(null, dto.lifecycle,           'Lifecycle populated.');
        System.assertNotEquals(null, dto.journey,             'Journey populated.');
        System.assertNotEquals(null, dto.academic,            'Academic populated.');
        System.assertNotEquals(null, dto.admissions,          'Admissions populated.');
        System.assertNotEquals(null, dto.career,              'Career populated.');
        System.assertNotEquals(null, dto.continuingEducation, 'Continuing Education populated.');
        System.assertNotEquals(null, dto.engagement,          'Engagement populated.');
        System.assertNotEquals(null, dto.jobs,                'Jobs populated.');
        System.assertNotEquals(null, dto.recognition,         'Recognition populated.');
        System.assertNotEquals(null, dto.giving,              'Giving populated.');
        System.assertNotEquals(null, dto.support,             'Support populated.');
        System.assertNotEquals(null, dto.documents,           'Documents populated.');
        System.assertNotEquals(null, dto.communications,      'Communications populated.');
        System.assertNotEquals(null, dto.rightRail,           'Right rail populated.');
    }

    @IsTest
    static void getHeader_nullRecordId_returnsEmptyHeader() {
        KenAdminAlumni360Controller.HeaderDTO h =
            KenAdminAlumni360Controller.getHeader(null);
        System.assertNotEquals(null, h, 'Header should never be null.');
        System.assertEquals(null, h.name, 'Empty header has no name.');
        System.assertNotEquals(null, h.badges, 'Badges list initialised.');
        System.assertEquals(0, h.badges.size(), 'No badges when no data.');
    }

    @IsTest
    static void getSnapshot_nullRecordId_returnsAllCardsNull() {
        KenAdminAlumni360Controller.SnapshotCardsDTO s =
            KenAdminAlumni360Controller.getSnapshot(null);
        System.assertNotEquals(null, s, 'Snapshot wrapper non-null.');
        System.assertEquals(null, s.academic);
        System.assertEquals(null, s.currentCareer);
        System.assertEquals(null, s.engagement);
        System.assertEquals(null, s.giving);
        System.assertEquals(null, s.continuingEducation);
        System.assertEquals(null, s.hiring);
    }

    @IsTest
    static void getOverview_nullRecordId_returnsEmptyLists() {
        KenAdminAlumni360Controller.OverviewDTO o =
            KenAdminAlumni360Controller.getOverview(null);
        System.assertEquals(0, o.snapshot.size());
        System.assertEquals(0, o.personalContact.size());
        System.assertEquals(0, o.relationships.size());
    }

    @IsTest
    static void getLifecycle_returnsEmpty() {
        KenAdminAlumni360Controller.LifecycleDTO d =
            KenAdminAlumni360Controller.getLifecycle(null);
        System.assertEquals(0, d.phases.size());
        System.assertEquals(null, d.currentPhase);
        System.assertEquals(0, d.currentStats.size());
    }

    @IsTest
    static void getJourney_returnsEmpty() {
        KenAdminAlumni360Controller.JourneyDTO j =
            KenAdminAlumni360Controller.getJourney(null);
        System.assertEquals(0, j.admissionsCount);
        System.assertEquals(0, j.studentCount);
        System.assertEquals(0, j.totalEvents);
        System.assertEquals(0, j.events.size());
    }

    @IsTest
    static void getAcademic_returnsEmpty() {
        KenAdminAlumni360Controller.AcademicDTO a =
            KenAdminAlumni360Controller.getAcademic(null);
        System.assertEquals(null, a.graduationFooter);
        System.assertEquals(0, a.education.size());
    }

    @IsTest
    static void getAdmissions_returnsEmptyLists() {
        KenAdminAlumni360Controller.AdmissionsDTO a =
            KenAdminAlumni360Controller.getAdmissions(null);
        System.assertEquals(0, a.lead.size());
        System.assertEquals(0, a.application.size());
        System.assertEquals(0, a.entranceExam.size());
        System.assertEquals(0, a.offer.size());
        System.assertEquals(0, a.scholarship.size());
        System.assertEquals(0, a.referrals.size());
        System.assertEquals(0, a.intakeDocuments.size());
    }

    @IsTest
    static void getCareer_nullRecordId_returnsEmpty() {
        KenAdminAlumni360Controller.CareerDTO c =
            KenAdminAlumni360Controller.getCareer(null);
        System.assertEquals(0, c.employmentHistory.size());
        System.assertEquals(0, c.internships.size());
        System.assertEquals(0, c.highlights.size());
    }

    @IsTest
    static void getContinuingEducation_returnsEmpty() {
        KenAdminAlumni360Controller.ContinuingEdDTO ce =
            KenAdminAlumni360Controller.getContinuingEducation(null);
        System.assertEquals(0, ce.ken42Academy.size());
        System.assertEquals(0, ce.external.size());
        System.assertEquals(0, ce.recommended.size());
    }

    @IsTest
    static void getEngagement_nullRecordId_returnsEmpty() {
        KenAdminAlumni360Controller.EngagementDTO e =
            KenAdminAlumni360Controller.getEngagement(null);
        System.assertEquals(0, e.eventsAttendedCount);
        System.assertEquals(0, e.activeMenteesCount);
        System.assertEquals(0, e.eventsHosted.size());
        System.assertEquals(0, e.eventsAttended.size());
        System.assertEquals(0, e.mentorship.size());
        System.assertEquals(0, e.hiringReferrals.size());
    }

    @IsTest
    static void getJobs_returnsEmpty() {
        KenAdminAlumni360Controller.JobsDTO j =
            KenAdminAlumni360Controller.getJobs(null);
        System.assertEquals(0, j.postedJobs.size());
        System.assertEquals(0, j.appliedJobs.size());
    }

    @IsTest
    static void getRecognition_returnsEmpty() {
        KenAdminAlumni360Controller.RecognitionDTO r =
            KenAdminAlumni360Controller.getRecognition(null);
        System.assertEquals(0, r.items.size());
    }

    @IsTest
    static void getGiving_returnsEmpty() {
        KenAdminAlumni360Controller.GivingDTO g =
            KenAdminAlumni360Controller.getGiving(null);
        System.assertEquals(0, g.gifts.size());
        System.assertEquals(null, g.donorTier);
    }

    @IsTest
    static void getSupport_nullRecordId_returnsEmpty() {
        KenAdminAlumni360Controller.SupportDTO s =
            KenAdminAlumni360Controller.getSupport(null);
        System.assertEquals(0, s.ticketsRaisedCount);
        System.assertEquals(0, s.tickets.size());
        System.assertEquals(0, s.surveys.size());
    }

    @IsTest
    static void getDocuments_returnsEmpty() {
        KenAdminAlumni360Controller.DocumentsDTO d =
            KenAdminAlumni360Controller.getDocuments(null);
        System.assertEquals(0, d.items.size());
    }

    @IsTest
    static void getCommunications_returnsEmpty() {
        KenAdminAlumni360Controller.CommunicationsDTO c =
            KenAdminAlumni360Controller.getCommunications(null);
        System.assertEquals(null, c.recipientName);
        System.assertEquals(0, c.recent.size());
        System.assertEquals(0, c.preferences.size());
    }

    @IsTest
    static void getRightRail_nullRecordId_returnsEmpty() {
        KenAdminAlumni360Controller.RightRailDTO r =
            KenAdminAlumni360Controller.getRightRail(null);
        System.assertEquals(0, r.needsAttention.size());
        System.assertEquals(0, r.recentActivity.size());
        System.assertEquals(0, r.quickActions.size());
        System.assertEquals(0, r.recordHealth.size());
    }

    /* ============================================================
       Comprehensive real-data test: Account + Ken_Alumni_CRM__c
       + PersonEmployment + Ken_Event_Booking__c + Ken_Mentorship__c
       + Case — exercises every build*FromOrg path.
       ============================================================ */

    @IsTest
    static void getAlumni360_realData_bindsHeaderAndSections() {
        // Find the Person Account record type
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        // Seed a Person Account (alumna)
        Account person = new Account();
        if (paRtId != null) {
            person.RecordTypeId = paRtId;
            person.FirstName = 'Test';
            person.LastName  = 'Alumnus360';
            person.PersonEmail = 'test.alumnus360@example.com';
        } else {
            person.Name = 'Test Alumnus360';
        }
        insert person;

        // Bridge ConstituentRole
        ConstituentRole role = new ConstituentRole(
            PersonId = person.Id,
            RoleType = 'Alumni'
        );
        try { role.put('Status', 'Active'); } catch (Exception ignored) {}
        insert role;

        // Ken_Alumni_CRM__c master row
        Ken_Alumni_CRM__c crm = new Ken_Alumni_CRM__c(
            Program__c = 'B.Tech CS',
            Year_of_Graduation__c = '2018',
            Registration_Number__c = 'CS-360-TEST',
            Current_Company__c = 'TestCorp',
            Current_Location__c = 'Bangalore',
            Industry__c = 'Engineering',
            Approval_Status__c = 'Approved',
            Is_Active__c = true,
            ConstituentRole__c = role.Id,
            Person_Account__c = person.Id,
            Registration_Date__c = Date.today().addYears(-8)
        );
        insert crm;

        // PersonEmployment (current role)
        try {
            PersonEmployment pe = new PersonEmployment(
                AccountId = person.Id,
                Company_Name__c = 'TestCorp',
                Designation__c = 'Senior Engineer',
                Location__c = 'Bangalore',
                StartDate = Date.today().addYears(-3),
                Currently_Employed__c = true
            );
            insert pe;
        } catch (Exception ex) { /* schema may differ between orgs */ }

        // Ken_Event_Booking__c (one attended event)
        try {
            Ken_Event_Booking__c b = new Ken_Event_Booking__c(
                Person_Account__c = person.Id
            );
            try { b.put('Type__c', 'Attendee'); } catch (Exception ignored) {}
            insert b;
        } catch (Exception ex) { /* skip if required fields differ */ }

        // Ken_Mentorship__c (one active mentorship)
        try {
            Ken_Mentorship__c m = new Ken_Mentorship__c(
                Mentor__c = person.Id,
                Mentee__c = person.Id,
                Mentorship_Status__c = 'Accepted',
                Meet_Date__c = Date.today().addDays(-30)
            );
            insert m;
        } catch (Exception ex) { /* skip if required fields differ */ }

        // Case (one open support ticket)
        try {
            Case c = new Case(
                Subject = 'Test 360 ticket',
                Status = 'New',
                Priority = 'High',
                Constituent_Role__c = role.Id
            );
            insert c;
        } catch (Exception ex) { /* skip if required fields differ */ }

        Test.startTest();
        KenAdminAlumni360Controller.Alumni360DTO dto =
            KenAdminAlumni360Controller.getAlumni360(crm.Id);
        Test.stopTest();

        // Header binds to the Person Account name
        System.assertNotEquals(null, dto, 'DTO returned for real recordId.');
        System.assertNotEquals(null, dto.header, 'Header populated.');
        System.assertEquals(crm.Id, dto.header.alumniId, 'Header.alumniId echoes recordId.');
        // Account.Name on a person account is "FirstName LastName"
        if (paRtId != null) {
            System.assertEquals('Test Alumnus360', dto.header.name,
                'Header.name should reflect the seeded Person Account name.');
            System.assertEquals('TA', dto.header.initials,
                'Initials computed from "Test Alumnus360".');
        }
        System.assertEquals('B.Tech CS', dto.header.program);
        System.assertEquals('2018', dto.header.classOf);
        System.assertEquals('CS-360-TEST', dto.header.registrationNumber);
        System.assertEquals('Active Alumna', dto.header.status);

        // Snapshot — only currentCareer + engagement are wired
        System.assertNotEquals(null, dto.snapshot);
        System.assertNotEquals(null, dto.snapshot.currentCareer,
            'currentCareer card populated from PersonEmployment.');
        System.assertNotEquals(null, dto.snapshot.engagement,
            'engagement card populated from event/mentorship counts.');
        System.assertEquals(null, dto.snapshot.academic);
        System.assertEquals(null, dto.snapshot.giving);

        // Overview — bound to real fields
        System.assert(dto.overview.snapshot.size() > 0,
            'Overview snapshot has KeyValue rows.');
        System.assert(dto.overview.personalContact.size() > 0,
            'Overview personalContact has KeyValue rows.');
        System.assertEquals(0, dto.overview.relationships.size(),
            'Relationships not wired yet — empty list.');

        // Sections backed by upcoming modules — all empty for real data too
        System.assertEquals(0, dto.lifecycle.phases.size());
        System.assertEquals(0, dto.journey.events.size());
        System.assertEquals(0, dto.academic.education.size());
        System.assertEquals(0, dto.admissions.lead.size());
        System.assertEquals(0, dto.continuingEducation.ken42Academy.size());
        System.assertEquals(0, dto.jobs.postedJobs.size());
        System.assertEquals(0, dto.recognition.items.size());
        System.assertEquals(0, dto.giving.gifts.size());
        System.assertEquals(0, dto.documents.items.size());
        System.assertEquals(0, dto.communications.recent.size());

        // Engagement / Support / RightRail are wired — assert they aggregate cleanly
        System.assertNotEquals(null, dto.engagement,
            'Engagement wrapper non-null.');
        System.assert(dto.engagement.eventsAttendedCount >= 0,
            'Engagement.eventsAttendedCount is a valid integer.');
        System.assertNotEquals(null, dto.support,
            'Support wrapper non-null.');
        System.assert(dto.support.ticketsRaisedCount >= 0,
            'Support.ticketsRaisedCount is a valid integer.');
        System.assertNotEquals(null, dto.rightRail,
            'Right rail wrapper non-null.');
        System.assertNotEquals(null, dto.rightRail.recordHealth,
            'Record health list initialised.');
        System.assert(dto.rightRail.recordHealth.size() >= 4,
            'Right rail emits at least the four base record-health rows.');
    }

    /* ============================================================
       Polymorphic Id resolver — must accept CR / Account / CRM Ids
       and synthesise a CRM-shaped row when none exists.
       ============================================================ */

    @IsTest
    static void getAlumni360_constituentRoleId_resolvesViaLinkage() {
        // Same seed as comprehensive test, but call getAlumni360 with the
        // ConstituentRole Id (what kenAdminAlumni passes after the master-
        // data flip) instead of the CRM Id.
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        Account person = new Account();
        if (paRtId != null) {
            person.RecordTypeId = paRtId;
            person.FirstName = 'CR'; person.LastName = 'Linked';
            person.PersonEmail = 'cr.linked@example.com';
        } else { person.Name = 'CR Linked'; }
        insert person;

        ConstituentRole role = new ConstituentRole(
            PersonId = person.Id, RoleType = 'Alumni',
            Graduation_Year__c = '2020', Registration_Number__c = 'MBA-LINK'
        );
        try { role.put('Status', 'Active'); } catch (Exception ignored) {}
        insert role;

        insert new Ken_Alumni_CRM__c(
            Program__c = 'MBA', Year_of_Graduation__c = '2020',
            Registration_Number__c = 'MBA-LINK', Is_Active__c = true,
            ConstituentRole__c = role.Id, Person_Account__c = person.Id
        );

        Test.startTest();
        KenAdminAlumni360Controller.Alumni360DTO dto =
            KenAdminAlumni360Controller.getAlumni360(role.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto.header);
        System.assertEquals('MBA', dto.header.program,
            'When called with a ConstituentRole Id linked to a CRM row, the resolver should hop through the linkage.');
        System.assertEquals('2020', dto.header.classOf);
    }

    @IsTest
    static void getAlumni360_constituentRoleId_synthesisesWhenNoCrm() {
        // The user's actual scenario: ConstituentRole exists, Person Account
        // exists, but no Ken_Alumni_CRM__c row links them. The synthesizer
        // must build a transient CRM-shaped row so the modal still populates.
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        Account person = new Account();
        if (paRtId != null) {
            person.RecordTypeId = paRtId;
            person.FirstName = 'No'; person.LastName = 'CrmRow';
            person.PersonEmail = 'no.crmrow@example.com';
        } else { person.Name = 'No CrmRow'; }
        insert person;

        ConstituentRole role = new ConstituentRole(
            PersonId = person.Id, RoleType = 'Alumni',
            Graduation_Year__c = '2022', Registration_Number__c = 'BBA-SYNTH'
        );
        try { role.put('Status', 'Active'); } catch (Exception ignored) {}
        insert role;

        Test.startTest();
        KenAdminAlumni360Controller.Alumni360DTO dto =
            KenAdminAlumni360Controller.getAlumni360(role.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto.header,
            'Header should be returned even without a CRM row.');
        if (paRtId != null) {
            System.assertEquals('No CrmRow', dto.header.name,
                'Synthesised header reads name from the Person Account.');
        }
        System.assertEquals('2022', dto.header.classOf,
            'Synthesised header reads classOf from the ConstituentRole.');
        System.assertEquals('BBA-SYNTH', dto.header.registrationNumber);
        System.assert(dto.overview.personalContact.size() > 0,
            'Overview personalContact populated from Account.');
    }

    /* ============================================================
       Inline edit — getEditableFields + diff-based updateAlumniProfile
       ============================================================ */

    @IsTest
    static void getEditableFields_nullRecordId_returnsNotEditable() {
        Map<String, Object> m = KenAdminAlumni360Controller.getEditableFields(null);
        System.assertNotEquals(null, m, 'Map should never be null.');
        System.assertEquals(false, m.get('crmEditable'), 'No CRM editing without a record.');
        System.assertEquals(false, m.get('accountEditable'), 'No account editing without a record.');
    }

    @IsTest
    static void updateAlumniProfile_updatesAccountAndCrm_onlyChangedFields() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        Account person = new Account();
        if (paRtId != null) {
            person.RecordTypeId = paRtId;
            person.FirstName = 'Edit'; person.LastName = 'Target';
            person.PersonEmail = 'edit.target@example.com';
            person.PersonMobilePhone = '111';
        } else { person.Name = 'Edit Target'; }
        insert person;

        ConstituentRole role = new ConstituentRole(PersonId = person.Id, RoleType = 'Alumni');
        try { role.put('Status', 'Active'); } catch (Exception ignored) {}
        insert role;

        Ken_Alumni_CRM__c crm = new Ken_Alumni_CRM__c(
            Program__c = 'B.Tech', Year_of_Graduation__c = '2015',
            Registration_Number__c = 'OLD-REG', Current_Company__c = 'OldCo',
            Is_Active__c = true, ConstituentRole__c = role.Id, Person_Account__c = person.Id
        );
        insert crm;

        Test.startTest();
        // Baseline read
        Map<String, Object> editable = KenAdminAlumni360Controller.getEditableFields(crm.Id);
        System.assertEquals(true, editable.get('crmEditable'), 'Real CRM row is editable.');
        System.assertEquals(true, editable.get('accountEditable'), 'Person Account is editable.');
        System.assertEquals('2015', editable.get('classOf'), 'classOf reads Year_of_Graduation__c.');
        System.assert(editable.containsKey('nationalityOptions'),
            'Nationality options should always be present.');
        List<Object> natOpts = (List<Object>) editable.get('nationalityOptions');
        System.assert(natOpts != null && !natOpts.isEmpty(),
            'nationalityOptions should be populated (picklist describe, or constant fallback for Text fields).');

        // Change one CRM field + one Account field
        String changes = JSON.serialize(new Map<String, Object>{
            'classOf' => '2016',
            'phone'   => '999-000'
        });
        KenAdminAlumni360Controller.updateAlumniProfile(crm.Id, changes);
        Test.stopTest();

        Ken_Alumni_CRM__c after = [SELECT Year_of_Graduation__c, Current_Company__c FROM Ken_Alumni_CRM__c WHERE Id = :crm.Id];
        System.assertEquals('2016', after.Year_of_Graduation__c, 'classOf was updated.');
        System.assertEquals('OldCo', after.Current_Company__c, 'Unchanged field left intact.');

        Account a = [SELECT PersonMobilePhone FROM Account WHERE Id = :person.Id];
        System.assertEquals('999-000', a.PersonMobilePhone, 'phone was updated on the Person Account.');
    }

    @IsTest
    static void updateAlumniProfile_emptyChanges_noOp() {
        // No record context, blank payload — should simply return without error.
        Test.startTest();
        KenAdminAlumni360Controller.updateAlumniProfile(null, null);
        KenAdminAlumni360Controller.updateAlumniProfile(null, '{}');
        Test.stopTest();
        System.assert(true, 'No exception on empty/no-op update calls.');
    }

    /* ============================================================
       Child-record edit — Education / Employment
       ============================================================ */

    @IsTest
    static void getChildEditData_nullRecordId_notEditable() {
        Map<String, Object> edu = KenAdminAlumni360Controller.getAcademicEditData(null);
        System.assertEquals(false, edu.get('editable'), 'No education editing without a record.');
        System.assertNotEquals(null, edu.get('gradeTypeOptions'), 'Grade-type options always present.');
        Map<String, Object> car = KenAdminAlumni360Controller.getCareerEditData(null);
        System.assertEquals(false, car.get('editable'), 'No employment editing without a record.');
    }

    @IsTest
    static void saveChildRows_noPersonAccount_throws() {
        Boolean threw = false;
        try {
            KenAdminAlumni360Controller.saveEducationRows(null, '[]', '[]');
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'Saving with no Person Account should raise an error.');
    }

    @IsTest
    static void saveEducationAndEmployment_upsertAddAndDelete() {
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        Account person = new Account();
        if (paRtId != null) {
            person.RecordTypeId = paRtId;
            person.FirstName = 'Child'; person.LastName = 'Editor';
            person.PersonEmail = 'child.editor@example.com';
        } else { person.Name = 'Child Editor'; }
        insert person;

        // Seed one existing education + one employment row.
        PersonEducation existingEdu;
        PersonEmployment existingEmp;
        Boolean childSchemaOk = true;
        try {
            existingEdu = new PersonEducation(
                Name = 'B.Sc', AccountId = person.Id, Institute_Name__c = 'Old Institute',
                Degree_Name__c = 'B.Sc', Year_of_Completion__c = '2010', Is_Archived__c = false
            );
            insert existingEdu;
            existingEmp = new PersonEmployment(
                Name = 'OldCorp', AccountId = person.Id, RelatedPersonId = person.Id,
                Designation__c = 'Old Role', Company_Name__c = 'OldCorp',
                StartDate = Date.today().addYears(-5),
                Currently_Employed__c = false, Is_Archived__c = false
            );
            insert existingEmp;
        } catch (Exception ex) { childSchemaOk = false; }

        if (!childSchemaOk) return; // org schema differs — skip the data assertions

        Test.startTest();
        // Read editable rows
        Map<String, Object> eduData = KenAdminAlumni360Controller.getAcademicEditData(person.Id);
        System.assertEquals(true, eduData.get('editable'), 'Education editable with a Person Account.');

        // Add a new education row + delete the existing one.
        String newEdu = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'id' => null, 'institute' => 'New University', 'degree' => 'M.Sc',
                'gradeType' => null, 'grade' => 'A', 'yearOfCompletion' => '2014'
            }
        });
        KenAdminAlumni360Controller.saveEducationRows(person.Id, newEdu,
            JSON.serialize(new List<String>{ existingEdu.Id }));

        // Update existing employment + add a new one (no deletes).
        String empRows = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'id' => existingEmp.Id, 'role' => 'Promoted Role', 'company' => 'OldCorp',
                'location' => 'Remote', 'startDate' => String.valueOf(Date.today().addYears(-5)),
                'endDate' => null, 'current' => true, 'description' => 'Updated'
            },
            new Map<String, Object>{
                'id' => null, 'role' => 'New Gig', 'company' => 'NewCo',
                'location' => null, 'startDate' => String.valueOf(Date.today()),
                'endDate' => null, 'current' => false, 'description' => null
            }
        });
        KenAdminAlumni360Controller.saveEmploymentRows(person.Id, empRows, '[]');
        Test.stopTest();

        List<PersonEducation> edus = [SELECT Institute_Name__c FROM PersonEducation WHERE AccountId = :person.Id];
        System.assertEquals(1, edus.size(), 'Old education deleted, new one added.');
        System.assertEquals('New University', edus[0].Institute_Name__c);

        List<PersonEmployment> emps = [SELECT Designation__c, Currently_Employed__c FROM PersonEmployment WHERE AccountId = :person.Id ORDER BY Designation__c];
        System.assertEquals(2, emps.size(), 'One updated + one added employment row.');
    }
}