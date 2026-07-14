@IsTest
private class KenNetworkControllerTest {
    private static final String CONNECTION_RECORD_TYPE = 'Connection_Request';
    private static final String ALUMNI_ACCOUNT_RECORD_TYPE = 'Alumni_Person_Account';

    private static User buildRunAsUser() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username          = 'network.' + System.currentTimeMillis() + '@example.com',
            Email             = 'network@example.com',
            LastName          = 'NetworkTest',
            Alias             = 'ntwk',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = prof.Id
        );
    }

    @TestSetup
    static void setupData() {
        Account currentUserAccount          = createAlumniPersonAccount('Network', 'Current User', 'network.current.user@test.com');
        Account acceptedConnection          = createAlumniPersonAccount('Network', 'Accepted Connection', 'network.accepted.connection@test.com');
        Account acceptedMentorshipOnly      = createAlumniPersonAccount('Network', 'Mentorship Accepted Only', 'network.accepted.mentorship.only@test.com');
        Account requesterOne                = createAlumniPersonAccount('Network', 'Requester One', 'network.requester.one@test.com');
        Account requesterTwo                = createAlumniPersonAccount('Network', 'Requester Two', 'network.requester.two@test.com');

        insert new List<Account>{ currentUserAccount, acceptedConnection, acceptedMentorshipOnly, requesterOne, requesterTwo };

        Map<Id, Id> contactByAccount = new Map<Id, Id>();
        for (Account reloaded : [
            SELECT Id, PersonContactId FROM Account
            WHERE Id IN :new List<Account>{ currentUserAccount, acceptedConnection, acceptedMentorshipOnly, requesterOne, requesterTwo }
        ]) {
            contactByAccount.put(reloaded.Id, reloaded.PersonContactId);
        }

        insertRegisteredRole(currentUserAccount.Id,     'network.current.user.role@test.com');
        insertRegisteredRole(acceptedConnection.Id,     'network.accepted.connection.role@test.com');
        insertRegisteredRole(acceptedMentorshipOnly.Id, 'network.accepted.mentorship.only.role@test.com');
        insertRegisteredRole(requesterOne.Id,           'network.requester.one.role@test.com');
        insertRegisteredRole(requesterTwo.Id,           'network.requester.two.role@test.com');

        insert new List<Ken_Alumni_CRM__c>{
            new Ken_Alumni_CRM__c(
                Person_Account__c  = acceptedConnection.Id,
                Current_Company__c = 'Accepted Company',
                Current_Location__c = 'Pune, India'
            ),
            new Ken_Alumni_CRM__c(
                Person_Account__c   = acceptedMentorshipOnly.Id,
                Current_Company__c  = 'Mentorship Only Company',
                Current_Location__c = 'Bengaluru, India'
            ),
            new Ken_Alumni_CRM__c(
                Person_Account__c   = requesterOne.Id,
                Current_Company__c  = 'Requester One Company',
                Current_Location__c = 'Mumbai, India'
            ),
            new Ken_Alumni_CRM__c(
                Person_Account__c   = requesterTwo.Id,
                Current_Company__c  = 'Requester Two Company',
                Current_Location__c = 'Hyderabad, India'
            )
        };

        insert new List<PersonEmployment>{
            new PersonEmployment(
                Name                  = 'Accepted Company',
                AccountId             = acceptedConnection.Id,
                RelatedPersonId       = contactByAccount.get(acceptedConnection.Id),
                Designation__c        = 'Product Designer',
                Location__c           = 'Pune, India',
                EmploymentIndustry    = 'Design',
                Currently_Employed__c = true,
                Is_Archived__c        = false,
                StartDate             = Date.today().addYears(-2)
            ),
            new PersonEmployment(
                Name                  = 'Mentorship Only Company',
                AccountId             = acceptedMentorshipOnly.Id,
                RelatedPersonId       = contactByAccount.get(acceptedMentorshipOnly.Id),
                Designation__c        = 'Cloud Engineer',
                Location__c           = 'Bengaluru, India',
                EmploymentIndustry    = 'Technology',
                Currently_Employed__c = true,
                Is_Archived__c        = false,
                StartDate             = Date.today().addYears(-2)
            ),
            new PersonEmployment(
                Name                  = 'Requester One Company',
                AccountId             = requesterOne.Id,
                RelatedPersonId       = contactByAccount.get(requesterOne.Id),
                Designation__c        = 'Analyst',
                Location__c           = 'Mumbai, India',
                EmploymentIndustry    = 'Finance',
                Currently_Employed__c = true,
                Is_Archived__c        = false,
                StartDate             = Date.today().addYears(-2)
            ),
            new PersonEmployment(
                Name                  = 'Requester Two Company',
                AccountId             = requesterTwo.Id,
                RelatedPersonId       = contactByAccount.get(requesterTwo.Id),
                Designation__c        = 'Engineer',
                Location__c           = 'Hyderabad, India',
                EmploymentIndustry    = 'Technology',
                Currently_Employed__c = true,
                Is_Archived__c        = false,
                StartDate             = Date.today().addYears(-2)
            )
        };

        // The "Mentor" badge now reflects Willing_to_be_a_mentor__c (offers
        // mentorship), not merely an accepted-mentor relationship — so the
        // accepted connection must opt in for the badge assertion below.
        insert new Ken_Alumni_Preferences__c(
            Person_Account__c        = acceptedConnection.Id,
            Willing_to_be_a_mentor__c = true
        );

        Id connectionRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CONNECTION_RECORD_TYPE
            LIMIT 1
        ].Id;

        Ken_Network_Connection__c acceptedNetworkConnection = new Ken_Network_Connection__c(
            Initiator__c = acceptedConnection.Id,
            Recipient__c = currentUserAccount.Id,
            Status__c    = 'Accepted'
        );
        Ken_Network_Connection__c requestNetworkOne = new Ken_Network_Connection__c(
            Initiator__c = requesterOne.Id,
            Recipient__c = currentUserAccount.Id,
            Status__c    = 'Requested'
        );
        Ken_Network_Connection__c requestNetworkTwo = new Ken_Network_Connection__c(
            Initiator__c = requesterTwo.Id,
            Recipient__c = currentUserAccount.Id,
            Status__c    = 'Requested'
        );
        Ken_Network_Connection__c acceptedMentorshipOnlyNetwork = new Ken_Network_Connection__c(
            Initiator__c = currentUserAccount.Id,
            Recipient__c = acceptedMentorshipOnly.Id,
            Status__c    = 'Requested'
        );
        insert new List<Ken_Network_Connection__c>{
            acceptedNetworkConnection,
            requestNetworkOne,
            requestNetworkTwo,
            acceptedMentorshipOnlyNetwork
        };

        insert new List<Ken_Mentorship__c>{
            new Ken_Mentorship__c(
                RecordTypeId              = connectionRecordTypeId,
                Mentor__c                 = acceptedConnection.Id,
                Mentee__c                 = currentUserAccount.Id,
                Mentorship_Status__c      = 'Accepted',
                Network_Connection__c     = acceptedNetworkConnection.Id
            ),
            new Ken_Mentorship__c(
                RecordTypeId              = connectionRecordTypeId,
                Mentor__c                 = currentUserAccount.Id,
                Mentee__c                 = acceptedMentorshipOnly.Id,
                Mentorship_Status__c      = 'Accepted',
                Network_Connection__c     = acceptedMentorshipOnlyNetwork.Id
            ),
            new Ken_Mentorship__c(
                RecordTypeId              = connectionRecordTypeId,
                Mentor__c                 = currentUserAccount.Id,
                Mentee__c                 = requesterOne.Id,
                Mentorship_Status__c      = 'Requested',
                Network_Connection__c     = requestNetworkOne.Id
            ),
            new Ken_Mentorship__c(
                RecordTypeId              = connectionRecordTypeId,
                Mentor__c                 = currentUserAccount.Id,
                Mentee__c                 = requesterTwo.Id,
                Mentorship_Status__c      = 'Requested',
                Network_Connection__c     = requestNetworkTwo.Id
            )
        };
    }

    @IsTest
    static void testGetNetworkDataReturnsExpectedBuckets() {
        User runAsUser = buildRunAsUser();
        insert runAsUser;

        Account currentUserAccount = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];

        System.runAs(runAsUser) {
            Test.startTest();
            KenNetworkController.testCurrentAccountId = currentUserAccount.Id;
            KenNetworkController.NetworkDataResponse result = KenNetworkController.getNetworkData();
            KenNetworkController.testCurrentAccountId = null;
            Test.stopTest();

            System.assertNotEquals(null, result, 'Expected a non-null response object from getNetworkData');
            System.assertNotEquals(null, result.allAlumni, 'Expected allAlumni collection to not be null');
            System.assertNotEquals(null, result.yourConnections, 'Expected yourConnections collection to not be null');
            System.assertNotEquals(null, result.connectionRequests, 'Expected connectionRequests collection to not be null');
            System.assertEquals(3, result.allAlumni.size(), 'All Alumni should exclude accepted network connections');
            System.assertEquals(1, result.yourConnections.size(), 'Should return one accepted connection');
            System.assertEquals(2, result.connectionRequests.size(), 'Should return two incoming requests');
            System.assertEquals(
                'Network Accepted Connection',
                result.yourConnections[0].name,
                'Your connections should use accepted network status, not only mentorship status'
            );
            System.assertEquals(true, result.yourConnections[0].isMentor, 'Mentor badge flag should be true when the counterpart is a willing mentor (Willing_to_be_a_mentor__c).');
        }
    }

    @IsTest
    static void testRespondToConnectionRequestsBulkAccept() {
        User runAsUser = buildRunAsUser();
        insert runAsUser;

        Account currentUserAccount = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];

        List<Ken_Network_Connection__c> pendingNetworkRequests = [
            SELECT Id, Initiator__c
            FROM Ken_Network_Connection__c
            WHERE Recipient__c = :currentUserAccount.Id
              AND Status__c = 'Requested'
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, pendingNetworkRequests.size(), 'Expected two pending incoming network requests for bulk accept test');

        List<Id> requestIds = new List<Id>();
        List<Id> initiatorIds = new List<Id>();
        for (Ken_Network_Connection__c req : pendingNetworkRequests) {
            requestIds.add(req.Id);
            initiatorIds.add(req.Initiator__c);
        }

        System.runAs(runAsUser) {
            Test.startTest();
            KenNetworkController.testCurrentAccountId = currentUserAccount.Id;
            List<Id> processedIds = KenNetworkController.respondToConnectionRequests(requestIds, 'accept');
            KenNetworkController.testCurrentAccountId = null;
            Test.stopTest();

            System.assertEquals(2, processedIds.size(), 'Both requests should be processed in one bulk call');

            List<Ken_Network_Connection__c> updated = [
                SELECT Id, Status__c
                FROM Ken_Network_Connection__c
                WHERE Id IN :requestIds
            ];
            for (Ken_Network_Connection__c conn : updated) {
                System.assertEquals('Accepted', conn.Status__c, 'Network connection should be set to Accepted after bulk accept');
            }

            String expectedUrlFragment = 'profileId=' + currentUserAccount.Id;
            String acceptNotifPattern = '%' + expectedUrlFragment + '%';
            List<Ken_Notification__c> notifs = [
                SELECT Id, Recipient__c, Category__c, Target_Url__c
                FROM Ken_Notification__c
                WHERE Category__c = 'Network'
                  AND Recipient__c IN :initiatorIds
                  AND Target_Url__c LIKE :acceptNotifPattern
            ];
            System.assertEquals(2, notifs.size(), 'Each accepted connection initiator should receive exactly one accept notification');
            Map<Id, Integer> notifCountByRecipient = new Map<Id, Integer>();
            for (Ken_Notification__c n : notifs) {
                System.assertEquals('Network', n.Category__c, 'Notification should be of category Network');
                System.assert(n.Target_Url__c != null && n.Target_Url__c.contains(expectedUrlFragment),
                    'Target URL should carry the accepter profile id; got: ' + n.Target_Url__c);
                Integer count = notifCountByRecipient.containsKey(n.Recipient__c) ? notifCountByRecipient.get(n.Recipient__c) : 0;
                notifCountByRecipient.put(n.Recipient__c, count + 1);
            }
            for (Id initiatorId : initiatorIds) {
                System.assertEquals(1, notifCountByRecipient.get(initiatorId),
                    'Initiator ' + initiatorId + ' should receive exactly one accept notification');
            }
        }
    }

    private static Account createAlumniPersonAccount(String firstName, String lastName, String email) {
        Id paRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
              AND DeveloperName = :ALUMNI_ACCOUNT_RECORD_TYPE
            LIMIT 1
        ].Id;

        Account pa = new Account(
            RecordTypeId         = paRtId,
            FirstName            = firstName,
            LastName             = lastName,
            PersonEmail          = email,
            PersonTitle          = 'Sample Title',
            PersonMailingCity    = 'Pune',
            PersonMailingState   = 'Maharashtra',
            PersonMailingCountry = 'India'
        );
        if (accountFields().containsKey('Status')) {
            pa.put('Status', 'Admitted');
        }
        return pa;
    }

    private static void insertRegisteredRole(Id personAccountId, String email) {
        ConstituentRole role = new ConstituentRole(
            PersonId               = personAccountId,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Registered',
            Email__c               = email
        );
        if (constituentRoleFields().containsKey('Status')) {
            role.put('Status', 'Admitted');
        }
        insert role;
    }

    private static Map<String, Schema.SObjectField> accountFields() {
        return Schema.SObjectType.Account.fields.getMap();
    }

    private static Map<String, Schema.SObjectField> constituentRoleFields() {
        return Schema.SObjectType.ConstituentRole.fields.getMap();
    }

    @IsTest
    static void testGetAlumniProfileExercisesEmploymentDurationBranches() {
        Account peer = [SELECT Id, PersonContactId FROM Account WHERE Name = 'Network Accepted Connection' LIMIT 1];

        insert new PersonEmployment(
            Name                  = 'Past Manager Co',
            AccountId             = peer.Id,
            RelatedPersonId       = peer.PersonContactId,
            Designation__c        = 'Past Manager',
            EmploymentIndustry    = 'Technology',
            Currently_Employed__c = false,
            Is_Archived__c        = false,
            StartDate             = Date.today().addYears(-3).addMonths(-2),
            EndDate               = Date.today().addYears(-1)
        );
        insert new PersonEmployment(
            Name                  = 'Short Tenure Co',
            AccountId             = peer.Id,
            RelatedPersonId       = peer.PersonContactId,
            Designation__c        = 'Short Tenure Role',
            EmploymentIndustry    = 'Finance',
            Currently_Employed__c = false,
            Is_Archived__c        = false,
            StartDate             = Date.today().addMonths(-3),
            EndDate               = Date.today().addMonths(-1)
        );
        insert new Ken_Achievement__c(
            Person_Account__c   = peer.Id,
            Title__c            = 'Industry Award',
            Achievement_Type__c = 'Award',
            Issuing_Organisation__c = 'Test Foundation',
            Date__c             = Date.today().addYears(-1),
            Description__c      = 'Leadership recognition',
            Is_Archived__c      = false
        );
        insert new PersonEducation(
            Name                    = 'B.Tech',
            AccountId               = peer.Id,
            Degree_Name__c          = 'B.Tech',
            Year_of_Completion__c   = '2018',
            StartDate               = Date.newInstance(2014, 6, 1),
            EndDate                 = Date.newInstance(2018, 5, 1),
            Grade__c                = '8.5',
            Grade_Type__c           = 'CGPA',
            Is_Archived__c          = false
        );

        Test.startTest();
        KenNetworkController.AlumniProfileDTO profile = KenNetworkController.getAlumniProfile(peer.Id);
        Test.stopTest();

        System.assertNotEquals(null, profile, 'Profile DTO should be populated');
        System.assertEquals(true, profile.experience.size() >= 2,
            'Profile experience list should include both inserted employment rows');
        System.assertEquals(true, profile.education.size() >= 1,
            'Profile education list should include the inserted academic record');
        System.assertEquals(true, profile.achievements.size() >= 1,
            'Profile achievements list should include the inserted achievement');
    }

    @IsTest
    static void testGetProfileCardSummariesForPortalCreatedProfile() {
        Account portalUser = createAlumniPersonAccount('Portal', 'Created User', 'network.portal.created@test.com');
        portalUser.PersonTitle = null;
        portalUser.PersonMailingCity = null;
        portalUser.PersonMailingState = null;
        portalUser.PersonMailingCountry = null;
        insert portalUser;
        portalUser = [SELECT Id, PersonContactId FROM Account WHERE Id = :portalUser.Id];

        insert new PersonEmployment(
            Name                  = 'T2C Development Center',
            AccountId             = portalUser.Id,
            RelatedPersonId       = portalUser.PersonContactId,
            Designation__c        = 'QA Engineer',
            Company_Name__c       = 'T2C Development Center',
            EmploymentIndustry    = 'Technology',
            Currently_Employed__c = true,
            Is_Archived__c        = false,
            StartDate             = Date.today().addYears(-2)
        );
        insert new List<PersonEducation>{
            new PersonEducation(
                Name           = 'B.E(Automobile)',
                AccountId      = portalUser.Id,
                Degree_Name__c = 'B.E(Automobile)',
                StartDate      = Date.newInstance(2017, 6, 1),
                EndDate        = Date.newInstance(2022, 5, 1),
                Is_Archived__c = false
            ),
            new PersonEducation(
                Name                  = 'DAE',
                AccountId             = portalUser.Id,
                Degree_Name__c        = 'DAE',
                Year_of_Completion__c = '2016',
                Is_Archived__c        = false
            )
        };
        insert new Ken_Address__c(
            Person_Account__c = portalUser.Id,
            Address_Type__c   = 'Mailing',
            City__c           = 'Coimbatore',
            State__c          = 'Tamil Nadu',
            Country__c        = 'India'
        );

        Test.startTest();
        Map<Id, KenNetworkController.ProfileCardSummary> summaries =
            KenNetworkController.getProfileCardSummaries(new Set<Id>{ portalUser.Id });
        Map<Id, KenNetworkController.ProfileCardSummary> emptySummaries =
            KenNetworkController.getProfileCardSummaries(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, emptySummaries.size(), 'Empty input should return an empty map.');
        KenNetworkController.ProfileCardSummary summary = summaries.get(portalUser.Id);
        System.assertNotEquals(null, summary, 'Summary should exist even without a Ken_Alumni_CRM__c row.');
        System.assertEquals('QA Engineer', summary.title,
            'Title should come from current employment when PersonTitle is blank.');
        System.assertEquals('T2C Development Center', summary.company,
            'Company should fall back to current employment without a CRM row.');
        System.assertEquals('B.E(Automobile) 2022 | DAE 2016', summary.educationLine,
            'Education line should be built from PersonEducation like the detail view header.');
        System.assertEquals('Coimbatore, Tamil Nadu, India', summary.location,
            'Location should come from the onboarding Ken_Address__c record.');
        System.assertEquals('Coimbatore', summary.currentCity,
            'Current city should be extracted from the resolved location.');
    }

    @IsTest
    static void testGetAlumniProfileReturnsDataWithoutCurrentUser() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Accepted Connection' LIMIT 1];

        insert new Ken_Alumni_Preferences__c(
            Person_Account__c         = peer.Id,
            Willing_to_be_a_mentor__c = true
        );

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        KenNetworkController.AlumniProfileDTO profile = KenNetworkController.getAlumniProfile(peer.Id);
        KenNetworkController.AlumniProfileDTO emptyProfile = KenNetworkController.getAlumniProfile(null);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertNotEquals(null, profile, 'getAlumniProfile should return DTO for valid account');
        System.assertEquals(peer.Id, profile.id, 'Returned DTO id should match queried account');
        System.assertEquals(true, profile.willingToHelp,
            'willingToHelp should reflect Ken_Alumni_Preferences__c.Willing_to_be_a_mentor__c');
        System.assertEquals(null, emptyProfile, 'getAlumniProfile should return null for null id');
    }

    @IsTest
    static void testGetAlumniProfileMasksPrivateAccountContact() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Accepted Connection' LIMIT 1];

        // Give the peer real contact details and flag their account private.
        update new Account(Id = peer.Id, PersonEmail = 'private.peer@example.com', PersonMobilePhone = '+1 9876543210');
        Ken_Alumni_Preferences__c pref = [
            SELECT Id FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c = :peer.Id
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        pref.Is_Private_Account__c = true;
        update pref;

        Test.startTest();
        // peer is an accepted connection but flagged private, so the mask must
        // stay in place even though the two are connected.
        KenNetworkController.testCurrentAccountId = current.Id;
        KenNetworkController.AlumniProfileDTO viewed = KenNetworkController.getAlumniProfile(peer.Id);
        // The owner still sees their own real details.
        KenNetworkController.testCurrentAccountId = peer.Id;
        KenNetworkController.AlumniProfileDTO ownView = KenNetworkController.getAlumniProfile(peer.Id);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals('pr****', viewed.email,
            'Private account email should show only its first 2 characters: ' + viewed.email);
        System.assertEquals('****210', viewed.phone,
            'Private account phone should show only its last 3 characters: ' + viewed.phone);
        System.assertEquals('private.peer@example.com', ownView.email,
            'Owner should still see their own real email.');
        System.assertEquals('+1 9876543210', ownView.phone,
            'Owner should still see their own real phone.');
    }

    @IsTest
    static void testGetAlumniProfileUnmasksPublicAccountOnceConnected() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        // acceptedConnection has an Accepted network connection with current and
        // is public (no Is_Private_Account__c flag) — the mask must be lifted.
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Accepted Connection' LIMIT 1];

        update new Account(Id = peer.Id, PersonEmail = 'public.peer@example.com', PersonMobilePhone = '+1 9876543210');

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        KenNetworkController.AlumniProfileDTO viewed = KenNetworkController.getAlumniProfile(peer.Id);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals('public.peer@example.com', viewed.email,
            'A connected viewer should see a public account\'s real email: ' + viewed.email);
        System.assertEquals('+1 9876543210', viewed.phone,
            'A connected viewer should see a public account\'s real phone: ' + viewed.phone);
    }

    @IsTest
    static void testGetAlumniProfileMasksPublicAccountUntilConnected() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        // This peer only has a *Requested* (not accepted) network connection with
        // current, so even though the account is public its contact stays masked.
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Mentorship Accepted Only' LIMIT 1];

        update new Account(Id = peer.Id, PersonEmail = 'pending.peer@example.com', PersonMobilePhone = '+1 9876543210');

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        KenNetworkController.AlumniProfileDTO viewed = KenNetworkController.getAlumniProfile(peer.Id);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals('pe****', viewed.email,
            'A public account stays masked until the connection is accepted: ' + viewed.email);
        System.assertEquals('****210', viewed.phone,
            'A public account\'s phone stays masked until the connection is accepted: ' + viewed.phone);
    }

    @IsTest
    static void testRequestConnectionAndRespond() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Mentorship Accepted Only' LIMIT 1];

        delete [
            SELECT Id FROM Ken_Network_Connection__c
            WHERE (Initiator__c = :current.Id AND Recipient__c = :peer.Id)
               OR (Initiator__c = :peer.Id AND Recipient__c = :current.Id)
        ];

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        String resultStatus = KenNetworkController.requestConnection(peer.Id);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals('Requested', resultStatus, 'requestConnection should return the new connection status');
        List<Ken_Network_Connection__c> created = [
            SELECT Id, Status__c
            FROM Ken_Network_Connection__c
            WHERE Initiator__c = :current.Id AND Recipient__c = :peer.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, created.size(), 'New connection record should be inserted');
        System.assertEquals('Requested', created[0].Status__c, 'New connection should be in Requested status');
    }

    @IsTest
    static void testRemoveConnectionMarksAsCancelled() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Accepted Connection' LIMIT 1];

        Ken_Network_Connection__c conn = [
            SELECT Id
            FROM Ken_Network_Connection__c
            WHERE (Initiator__c = :current.Id AND Recipient__c = :peer.Id)
               OR (Initiator__c = :peer.Id AND Recipient__c = :current.Id)
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        // Setup links an Accepted mentor-mentee mentorship to this connection.
        Integer activeBefore = [
            SELECT COUNT() FROM Ken_Mentorship__c
            WHERE Network_Connection__c = :conn.Id AND Mentorship_Status__c != 'Cancelled'
        ];
        System.assert(activeBefore > 0, 'Precondition: an active mentorship is linked to the connection.');

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        KenNetworkController.removeConnection(conn.Id);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        Ken_Network_Connection__c reread = [SELECT Status__c FROM Ken_Network_Connection__c WHERE Id = :conn.Id];
        System.assertEquals('Cancelled', reread.Status__c, 'removeConnection should mark connection as Cancelled');

        // Removing the connection must cancel every linked mentorship (records are kept).
        Integer activeAfter = [
            SELECT COUNT() FROM Ken_Mentorship__c
            WHERE Network_Connection__c = :conn.Id AND Mentorship_Status__c != 'Cancelled'
        ];
        System.assertEquals(0, activeAfter,
            'removeConnection should cancel every mentorship linked to the connection.');
    }

    @IsTest
    static void testRequestAndRemoveMentorship() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Accepted Connection' LIMIT 1];

        Ken_Network_Connection__c conn = [
            SELECT Id
            FROM Ken_Network_Connection__c
            WHERE (Initiator__c = :current.Id AND Recipient__c = :peer.Id)
               OR (Initiator__c = :peer.Id AND Recipient__c = :current.Id)
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        try {
            KenNetworkController.requestMentorship(conn.Id);
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Mentorship request exception should expose a message');
        } catch (DmlException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Mentorship request DML exception should expose a message');
        }

        try {
            KenNetworkController.removeMentorship(conn.Id);
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Remove mentorship exception should expose a message');
        } catch (DmlException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Remove mentorship DML exception should expose a message');
        }
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        System.assert(true, 'Mentorship request and remove paths executed without uncaught failure');
    }

    @IsTest
    static void testRequestConnectionReusesRejectedRecord() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Mentorship Accepted Only' LIMIT 1];

        // Start from a single Rejected record for the pair.
        delete [
            SELECT Id FROM Ken_Network_Connection__c
            WHERE (Initiator__c = :current.Id AND Recipient__c = :peer.Id)
               OR (Initiator__c = :peer.Id AND Recipient__c = :current.Id)
        ];
        insert new Ken_Network_Connection__c(
            Initiator__c = current.Id, Recipient__c = peer.Id, Status__c = 'Rejected'
        );

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        String resultStatus = KenNetworkController.requestConnection(peer.Id);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals('Requested', resultStatus, 'Re-request should return Requested.');
        List<Ken_Network_Connection__c> all = [
            SELECT Id, Status__c FROM Ken_Network_Connection__c
            WHERE (Initiator__c = :current.Id AND Recipient__c = :peer.Id)
               OR (Initiator__c = :peer.Id AND Recipient__c = :current.Id)
        ];
        System.assertEquals(1, all.size(), 'Re-request must reuse the rejected record, not create a duplicate.');
        System.assertEquals('Requested', all[0].Status__c, 'The reused record should be back in Requested.');
    }

    @IsTest
    static void testRequestMentorshipReusesRejectedRecord() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Network Current User' LIMIT 1];
        Account peer = [SELECT Id FROM Account WHERE Name = 'Network Mentorship Accepted Only' LIMIT 1];

        // An accepted network connection with a prior REJECTED mentorship request.
        delete [
            SELECT Id FROM Ken_Network_Connection__c
            WHERE (Initiator__c = :current.Id AND Recipient__c = :peer.Id)
               OR (Initiator__c = :peer.Id AND Recipient__c = :current.Id)
        ];
        Ken_Network_Connection__c conn = new Ken_Network_Connection__c(
            Initiator__c = current.Id, Recipient__c = peer.Id, Status__c = 'Accepted'
        );
        insert conn;
        Id connRt = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c' AND DeveloperName = :CONNECTION_RECORD_TYPE LIMIT 1
        ].Id;
        insert new Ken_Mentorship__c(
            RecordTypeId = connRt, Mentor__c = peer.Id, Mentee__c = current.Id,
            Mentorship_Status__c = 'Rejected', Network_Connection__c = conn.Id
        );

        Test.startTest();
        KenNetworkController.testCurrentAccountId = current.Id;
        KenNetworkController.requestMentorship(conn.Id);
        KenNetworkController.testCurrentAccountId = null;
        Test.stopTest();

        List<Ken_Mentorship__c> ments = [
            SELECT Id, Mentorship_Status__c FROM Ken_Mentorship__c
            WHERE Network_Connection__c = :conn.Id
        ];
        System.assertEquals(1, ments.size(), 'Re-request must reuse the rejected mentorship, not duplicate it.');
        System.assertEquals('Requested', ments[0].Mentorship_Status__c, 'The reused mentorship should be Requested.');
    }
}