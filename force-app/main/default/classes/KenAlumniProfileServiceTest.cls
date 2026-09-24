@isTest
private class KenAlumniProfileServiceTest {

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'PersonAccount' LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account' AND IsActive = true]) {
            if (rt.IsPersonType) {
                return rt.Id;
            }
        }
        return null;
    }

    private static Account createPersonAccount(String lastName) {
        Account acc = new Account(
            FirstName = 'Profile',
            LastName = lastName,
            PersonEmail = lastName.toLowerCase() + '@test.example.com'
        );
        Id rtId = getPersonAccountRtId();
        if (rtId != null) {
            acc.RecordTypeId = rtId;
        }
        insert acc;
        return acc;
    }

    private static PersonEmployment buildEmployment(
        Id personAcctId, String company, String industry, Boolean current, Date startDate, Boolean archived
    ) {
        return new PersonEmployment(
            AccountId = personAcctId,
            RelatedPersonId = personAcctId,
            Name = company,
            Company_Name__c = company,
            Industry__c = industry,
            Designation__c = 'Engineer',
            Location__c = 'Pune',
            Currently_Employed__c = current,
            StartDate = startDate,
            Is_Archived__c = archived
        );
    }

    @isTest
    static void currentlyEmployedRowWinsOverMoreRecentStartDate() {
        Account acc = createPersonAccount('EmpFlagWins');
        insert new List<PersonEmployment>{
            buildEmployment(acc.Id, 'Older Current Co', 'Manufacturing', true, Date.newInstance(2019, 1, 1), false),
            buildEmployment(acc.Id, 'Newer Past Co', 'Retail', false, Date.newInstance(2024, 1, 1), false)
        };

        Test.startTest();
        KenAlumniProfileService.EmploymentSnapshot snap = KenAlumniProfileService.currentEmployment(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, snap, 'Expected an employment snapshot.');
        System.assertEquals('Older Current Co', snap.company, 'Currently_Employed__c row must win.');
        System.assertEquals('Manufacturing', snap.industry, 'Industry must come from the same row as the company.');
    }

    @isTest
    static void latestStartDateWinsWhenNobodyIsFlaggedCurrent() {
        Account acc = createPersonAccount('EmpFallback');
        insert new List<PersonEmployment>{
            buildEmployment(acc.Id, 'Oldest Co', 'Retail', false, Date.newInstance(2015, 1, 1), false),
            buildEmployment(acc.Id, 'Most Recent Co', 'Consulting', false, Date.newInstance(2022, 6, 1), false)
        };

        Test.startTest();
        KenAlumniProfileService.EmploymentSnapshot snap = KenAlumniProfileService.currentEmployment(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, snap, 'Expected a snapshot from the fallback path.');
        System.assertEquals('Most Recent Co', snap.company, 'Latest StartDate must win when no row is current.');
        System.assertEquals('Consulting', snap.industry, 'Industry must follow the resolved row.');
    }

    @isTest
    static void archivedRowsAreIgnored() {
        Account acc = createPersonAccount('EmpArchived');
        insert new List<PersonEmployment>{
            buildEmployment(acc.Id, 'Archived Co', 'Retail', true, Date.newInstance(2023, 1, 1), true),
            buildEmployment(acc.Id, 'Live Co', 'Education', false, Date.newInstance(2020, 1, 1), false)
        };

        Test.startTest();
        KenAlumniProfileService.EmploymentSnapshot snap = KenAlumniProfileService.currentEmployment(acc.Id);
        Test.stopTest();

        System.assertEquals('Live Co', snap.company, 'Archived rows must not be resolved.');
    }

    @isTest
    static void employmentResolvesInBulkWithOneQuery() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 25; i++) {
            Account acc = new Account(
                FirstName = 'Bulk',
                LastName = 'Emp' + i,
                PersonEmail = 'bulkemp' + i + '@test.example.com'
            );
            Id rtId = getPersonAccountRtId();
            if (rtId != null) {
                acc.RecordTypeId = rtId;
            }
            accounts.add(acc);
        }
        insert accounts;

        List<PersonEmployment> employments = new List<PersonEmployment>();
        for (Integer i = 0; i < accounts.size(); i++) {
            employments.add(buildEmployment(
                accounts[i].Id, 'Co ' + i, 'Industry ' + i, true, Date.newInstance(2021, 1, 1), false
            ));
        }
        insert employments;

        Set<Id> ids = new Set<Id>();
        for (Account acc : accounts) {
            ids.add(acc.Id);
        }

        Test.startTest();
        Integer before = Limits.getQueries();
        Map<Id, KenAlumniProfileService.EmploymentSnapshot> resolved =
            KenAlumniProfileService.currentEmployment(ids);
        Integer used = Limits.getQueries() - before;
        Test.stopTest();

        System.assertEquals(25, resolved.size(), 'Every account should resolve.');
        System.assertEquals(1, used, 'Bulk resolution must use a single query.');
        System.assertEquals('Co 0', resolved.get(accounts[0].Id).company, 'Snapshots must map to the right account.');
    }

    @isTest
    static void locationFormatsCityAndCountryFromMailingAddress() {
        Account acc = createPersonAccount('LocBoth');
        insert new Ken_Address__c(
            Person_Account__c = acc.Id,
            Address_Type__c = 'Mailing',
            City__c = 'Mumbai',
            Country__c = 'India'
        );

        Test.startTest();
        String location = KenAlumniProfileService.currentLocation(acc.Id);
        Test.stopTest();

        System.assertEquals('Mumbai, India', location, 'Expected "City, Country".');
    }

    @isTest
    static void locationIgnoresNonMailingAddresses() {
        Account acc = createPersonAccount('LocNonMailing');
        insert new Ken_Address__c(
            Person_Account__c = acc.Id,
            Address_Type__c = 'Permanent',
            City__c = 'Chennai',
            Country__c = 'India'
        );

        Test.startTest();
        String location = KenAlumniProfileService.currentLocation(acc.Id);
        Test.stopTest();

        System.assertEquals(null, location, 'Only the Mailing address should be resolved.');
    }

    @isTest
    static void locationFallsBackToWhicheverPartIsPresent() {
        Account cityOnly = createPersonAccount('LocCityOnly');
        Account countryOnly = createPersonAccount('LocCountryOnly');
        Account neither = createPersonAccount('LocNeither');
        insert new List<Ken_Address__c>{
            new Ken_Address__c(Person_Account__c = cityOnly.Id, Address_Type__c = 'Mailing', City__c = 'Delhi'),
            new Ken_Address__c(Person_Account__c = countryOnly.Id, Address_Type__c = 'Mailing', Country__c = 'Nepal'),
            new Ken_Address__c(Person_Account__c = neither.Id, Address_Type__c = 'Mailing')
        };

        Test.startTest();
        Map<Id, String> resolved = KenAlumniProfileService.currentLocation(
            new Set<Id>{ cityOnly.Id, countryOnly.Id, neither.Id }
        );
        Test.stopTest();

        System.assertEquals('Delhi', resolved.get(cityOnly.Id), 'City-only address should return the city.');
        System.assertEquals('Nepal', resolved.get(countryOnly.Id), 'Country-only address should return the country.');
        System.assertEquals(false, resolved.containsKey(neither.Id), 'An empty address must not produce an entry.');
    }

    @isTest
    static void emptyAndNullInputsAreSafe() {
        Test.startTest();
        Map<Id, KenAlumniProfileService.EmploymentSnapshot> emptyEmp =
            KenAlumniProfileService.currentEmployment(new Set<Id>());
        Map<Id, KenAlumniProfileService.EmploymentSnapshot> nullEmp =
            KenAlumniProfileService.currentEmployment((Set<Id>) null);
        Map<Id, String> emptyLoc = KenAlumniProfileService.currentLocation(new Set<Id>());
        Map<Id, String> nullLoc = KenAlumniProfileService.currentLocation((Set<Id>) null);
        KenAlumniProfileService.EmploymentSnapshot nullOne =
            KenAlumniProfileService.currentEmployment((Id) null);
        String nullLocOne = KenAlumniProfileService.currentLocation((Id) null);
        Test.stopTest();

        System.assertEquals(true, emptyEmp.isEmpty(), 'Empty input should return an empty map.');
        System.assertEquals(true, nullEmp.isEmpty(), 'Null input should return an empty map.');
        System.assertEquals(true, emptyLoc.isEmpty(), 'Empty input should return an empty map.');
        System.assertEquals(true, nullLoc.isEmpty(), 'Null input should return an empty map.');
        System.assertEquals(null, nullOne, 'Null Id should resolve to null.');
        System.assertEquals(null, nullLocOne, 'Null Id should resolve to null.');
    }

    @isTest
    static void accountWithNoEmploymentIsAbsentFromTheMap() {
        Account acc = createPersonAccount('EmpNone');

        Test.startTest();
        Map<Id, KenAlumniProfileService.EmploymentSnapshot> resolved =
            KenAlumniProfileService.currentEmployment(new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertEquals(true, resolved.isEmpty(), 'No employment means no map entry.');
    }
}