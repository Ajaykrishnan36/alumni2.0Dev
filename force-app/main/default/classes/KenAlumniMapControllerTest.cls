@IsTest
private class KenAlumniMapControllerTest {
    private static final String ALUMNI_ACCOUNT_RECORD_TYPE = 'Alumni_Person_Account';

    @TestSetup
    static void setupData() {
        Account mumbaiOne  = createAlumniPersonAccount('Map', 'Mumbai One', 'map.mumbai.one@test.com', 'Mumbai', 'Maharashtra', 'India');
        Account mumbaiTwo  = createAlumniPersonAccount('Map', 'Mumbai Two', 'map.mumbai.two@test.com', 'Mumbai', 'Maharashtra', 'India');
        Account puneOne    = createAlumniPersonAccount('Map', 'Pune One', 'map.pune.one@test.com', 'Pune', 'Maharashtra', 'India');
        Account londonOne  = createAlumniPersonAccount('Map', 'London One', 'map.london.one@test.com', 'London', null, 'United Kingdom');
        Account cityOnly   = createAlumniPersonAccount('Map', 'City Only', 'map.city.only@test.com', 'Chennai', null, null);
        Account noLocation = createAlumniPersonAccount('Map', 'No Location', 'map.no.location@test.com', null, null, null);
        Account noRole     = createAlumniPersonAccount('Map', 'No Role', 'map.no.role@test.com', 'Delhi', 'Delhi', 'India');
        insert new List<Account>{ mumbaiOne, mumbaiTwo, puneOne, londonOne, cityOnly, noLocation, noRole };

        insertAlumniRole(mumbaiOne.Id, 'map.mumbai.one.role@test.com');
        insertAlumniRole(mumbaiTwo.Id, 'map.mumbai.two.role@test.com');
        insertAlumniRole(puneOne.Id, 'map.pune.one.role@test.com');
        insertAlumniRole(londonOne.Id, 'map.london.one.role@test.com');
        insertAlumniRole(cityOnly.Id, 'map.city.only.role@test.com');
        insertAlumniRole(noLocation.Id, 'map.no.location.role@test.com');
    }

    @IsTest
    static void testReturnsGroupedCountsForAlumniWithLocations() {
        Test.startTest();
        List<KenAlumniMapController.LocationCount> rows = KenAlumniMapController.getAlumniLocationCounts();
        Test.stopTest();

        Integer mumbaiCount = 0;
        Integer puneCount = 0;
        Integer londonCount = 0;
        Integer chennaiCount = 0;
        Integer delhiCount = 0;
        Integer totalRecords = 0;
        for (KenAlumniMapController.LocationCount row : rows) {
            totalRecords += row.total;
            if (row.city == 'Mumbai') mumbaiCount = row.total;
            if (row.city == 'Pune') puneCount = row.total;
            if (row.city == 'London') londonCount = row.total;
            if (row.city == 'Chennai') chennaiCount = row.total;
            if (row.city == 'Delhi') delhiCount = row.total;
        }

        System.assertEquals(2, mumbaiCount, 'Two alumni in Mumbai should be grouped into one row');
        System.assertEquals(1, puneCount, 'One alumnus in Pune expected');
        System.assertEquals(1, londonCount, 'One alumnus in London expected');
        System.assertEquals(1, chennaiCount, 'City-only record should still be returned');
        System.assertEquals(0, delhiCount, 'Person account without an Alumni role must be excluded');
        System.assertEquals(5, totalRecords, 'Record with no location data must be excluded from totals');
    }

    @IsTest
    static void testCountryAndStateArePassedThrough() {
        List<KenAlumniMapController.LocationCount> rows = KenAlumniMapController.getAlumniLocationCounts();

        Boolean foundMumbaiRow = false;
        for (KenAlumniMapController.LocationCount row : rows) {
            if (row.city == 'Mumbai') {
                foundMumbaiRow = true;
                System.assertEquals('India', row.country, 'Country should be carried on the row');
                System.assertEquals('Maharashtra', row.state, 'State should be carried on the row');
            }
        }
        System.assert(foundMumbaiRow, 'Mumbai row expected in the results');
    }

    @IsTest
    static void testReturnsEmptyListWhenNoAlumniRolesExist() {
        delete [SELECT Id FROM ConstituentRole WHERE Email__c LIKE 'map.%.role@test.com'];

        Test.startTest();
        List<KenAlumniMapController.LocationCount> rows = KenAlumniMapController.getAlumniLocationCounts();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'No rows expected when no alumni roles exist');
    }

    private static Account createAlumniPersonAccount(String firstName, String lastName, String email, String city, String state, String country) {
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
            PersonMailingCity    = city,
            PersonMailingState   = state,
            PersonMailingCountry = country
        );
        if (accountFields().containsKey('Status')) {
            pa.put('Status', 'Admitted');
        }
        return pa;
    }

    private static void insertAlumniRole(Id personAccountId, String email) {
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
}