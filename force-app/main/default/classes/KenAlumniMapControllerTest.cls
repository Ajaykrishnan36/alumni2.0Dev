@IsTest
private class KenAlumniMapControllerTest {
    private static final String ALUMNI_ACCOUNT_RECORD_TYPE = 'PersonAccount';
    private static Id cachedPersonAccountRecordTypeId;

    @TestSetup
    static void setupData() {
        Account mumbaiOne  = createAlumniPersonAccount('Map', 'Mumbai One', 'map.mumbai.one@test.com');
        Account mumbaiTwo  = createAlumniPersonAccount('Map', 'Mumbai Two', 'map.mumbai.two@test.com');
        Account puneOne    = createAlumniPersonAccount('Map', 'Pune One', 'map.pune.one@test.com');
        Account londonOne  = createAlumniPersonAccount('Map', 'London One', 'map.london.one@test.com');
        Account cityOnly   = createAlumniPersonAccount('Map', 'City Only', 'map.city.only@test.com');
        Account noLocation = createAlumniPersonAccount('Map', 'No Location', 'map.no.location@test.com');
        Account noRole     = createAlumniPersonAccount('Map', 'No Role', 'map.no.role@test.com');
        insert new List<Account>{ mumbaiOne, mumbaiTwo, puneOne, londonOne, cityOnly, noLocation, noRole };

        insertAlumniRole(mumbaiOne.Id, 'map.mumbai.one.role@test.com');
        insertAlumniRole(mumbaiTwo.Id, 'map.mumbai.two.role@test.com');
        insertAlumniRole(puneOne.Id, 'map.pune.one.role@test.com');
        insertAlumniRole(londonOne.Id, 'map.london.one.role@test.com');
        insertAlumniRole(cityOnly.Id, 'map.city.only.role@test.com');
        insertAlumniRole(noLocation.Id, 'map.no.location.role@test.com');

        insert new List<Ken_Address__c>{
            mailingAddress(mumbaiOne.Id, 'Mumbai', 'Maharashtra', 'India'),
            mailingAddress(mumbaiOne.Id, 'Mumbai', 'Maharashtra', 'India'),
            mailingAddress(mumbaiTwo.Id, 'Mumbai', 'Maharashtra', 'India'),
            mailingAddress(puneOne.Id, 'Pune', 'Maharashtra', 'India'),
            mailingAddress(londonOne.Id, 'London', null, 'United Kingdom'),
            mailingAddress(cityOnly.Id, 'Chennai', null, null),
            mailingAddress(noLocation.Id, null, null, null),
            mailingAddress(noRole.Id, 'Delhi', 'Delhi', 'India'),
            address(mumbaiOne.Id, 'Permanent', 'Delhi', 'Delhi', 'India')
        };
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

        System.assertEquals(2, mumbaiCount, 'Two distinct alumni in Mumbai expected; duplicate mailing rows must dedupe');
        System.assertEquals(1, puneCount, 'One alumnus in Pune expected');
        System.assertEquals(1, londonCount, 'One alumnus in London expected');
        System.assertEquals(1, chennaiCount, 'City-only address should still be returned');
        System.assertEquals(0, delhiCount, 'Non-alumni addresses and Permanent-type addresses must be excluded');
        System.assertEquals(5, totalRecords, 'Address rows with no location data must be excluded from totals');
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

    /**
     * Guards the governor-limit shape of getAlumniLocationCounts. COUNT_DISTINCT
     * charges every row it scans, a plain GROUP BY charges only the groups it
     * returns, and a bound Set of alumni PersonIds charges one row per alumnus —
     * any of those reintroduced blows the 50,000-row limit in a real org, which
     * is what took the KJS production map down. Loading one city with far more
     * alumni than there are locations makes rows and groups diverge enough to
     * tell the two costs apart.
     */
    @IsTest
    static void testLocationCountsAreChargedPerGroupNotPerRow() {
        List<Account> people = new List<Account>();
        for (Integer i = 0; i < 30; i++) {
            people.add(createAlumniPersonAccount('Bulk', 'Nagpur ' + i, 'map.bulk.' + i + '@test.com'));
        }
        insert people;

        List<ConstituentRole> roles = new List<ConstituentRole>();
        List<Ken_Address__c> addresses = new List<Ken_Address__c>();
        for (Integer i = 0; i < people.size(); i++) {
            roles.add(alumniRole(people[i].Id, 'map.bulk.' + i + '.role@test.com'));
            addresses.add(mailingAddress(people[i].Id, 'Nagpur', 'Maharashtra', 'India'));
        }
        insert roles;
        insert addresses;

        Test.startTest();
        Integer before = Limits.getQueryRows();
        List<KenAlumniMapController.LocationCount> rows = KenAlumniMapController.getAlumniLocationCounts();
        Integer consumed = Limits.getQueryRows() - before;
        Test.stopTest();

        Integer nagpurCount = 0;
        for (KenAlumniMapController.LocationCount row : rows) {
            if (row.city == 'Nagpur') nagpurCount = row.total;
        }
        System.assertEquals(30, nagpurCount, 'All 30 Nagpur alumni should be counted');
        System.assert(consumed <= 15,
            'Location counts must be charged per group, not per address or per alumni role. Query rows consumed: '
            + consumed);
    }

    @IsTest
    static void testGetAlumniAtLocationReturnsPeopleWithRoleIds() {
        Test.startTest();
        List<KenAlumniMapController.AlumniAtLocation> people =
            KenAlumniMapController.getAlumniAtLocation(new List<String>{ 'Mumbai' }, new List<String>{ 'India' });
        Test.stopTest();

        System.assertEquals(2, people.size(), 'Both distinct Mumbai alumni should be returned, deduped by person');
        for (KenAlumniMapController.AlumniAtLocation person : people) {
            System.assertNotEquals(null, person.personId, 'Person Account Id should be populated');
            System.assertNotEquals(null, person.constituentRoleId, 'ConstituentRole Id should be stamped for the 360');
            System.assert(String.isNotBlank(person.name), 'Name should be populated');
            System.assert(person.subtitle.contains('Mumbai'), 'Subtitle should carry the city');
        }
    }

    @IsTest
    static void testGetAlumniAtLocationExcludesNonAlumniAndPermanent() {
        Test.startTest();
        List<KenAlumniMapController.AlumniAtLocation> delhi =
            KenAlumniMapController.getAlumniAtLocation(new List<String>{ 'Delhi' }, new List<String>{ 'India' });
        List<KenAlumniMapController.AlumniAtLocation> none =
            KenAlumniMapController.getAlumniAtLocation(new List<String>(), null);
        Test.stopTest();

        System.assertEquals(0, delhi.size(),
            'Delhi has only a non-alumni mailing address and a Permanent-type address — both excluded');
        System.assertEquals(0, none.size(), 'Empty city list should return no people');
    }

    private static Account createAlumniPersonAccount(String firstName, String lastName, String email) {
        Account pa = new Account(
            RecordTypeId = personAccountRecordTypeId(),
            FirstName    = firstName,
            LastName     = lastName,
            PersonEmail  = email
        );
        if (accountFields().containsKey('Status')) {
            pa.put('Status', 'Admitted');
        }
        return pa;
    }

    private static Ken_Address__c mailingAddress(Id personAccountId, String city, String state, String country) {
        return address(personAccountId, 'Mailing', city, state, country);
    }

    private static Ken_Address__c address(Id personAccountId, String addressType, String city, String state, String country) {
        return new Ken_Address__c(
            Person_Account__c = personAccountId,
            Address_Type__c   = addressType,
            City__c           = city,
            State__c          = state,
            Country__c        = country
        );
    }

    private static void insertAlumniRole(Id personAccountId, String email) {
        insert alumniRole(personAccountId, email);
    }

    private static ConstituentRole alumniRole(Id personAccountId, String email) {
        ConstituentRole role = new ConstituentRole(
            PersonId               = personAccountId,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Registered',
            Email__c               = email
        );
        if (constituentRoleFields().containsKey('Status')) {
            role.put('Status', 'Admitted');
        }
        return role;
    }

    private static Id personAccountRecordTypeId() {
        if (cachedPersonAccountRecordTypeId == null) {
            cachedPersonAccountRecordTypeId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Account'
                  AND DeveloperName = :ALUMNI_ACCOUNT_RECORD_TYPE
                LIMIT 1
            ].Id;
        }
        return cachedPersonAccountRecordTypeId;
    }

    private static Map<String, Schema.SObjectField> accountFields() {
        return Schema.SObjectType.Account.fields.getMap();
    }

    private static Map<String, Schema.SObjectField> constituentRoleFields() {
        return Schema.SObjectType.ConstituentRole.fields.getMap();
    }

    @IsTest
    static void testGetBasemapKeyReturnsConfiguredKey() {
        insert new Ken_Alm_Org_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Carto_Basemap_Client_Id__c = 'test_carto_key_123'
        );

        Test.startTest();
        String key = KenAlumniMapController.getBasemapKey();
        Test.stopTest();

        System.assertEquals('test_carto_key_123', key, 'The configured CARTO key should be returned to the map');
    }

    @IsTest
    static void testGetBasemapKeyIsNullWhenUnset() {
        // No org parameters record at all: an org that has not been given a key
        // yet must still load the map, just with watermarked tiles.
        Test.startTest();
        String key = KenAlumniMapController.getBasemapKey();
        Test.stopTest();

        System.assertEquals(null, key, 'An unset key should come back as null, not an empty string');
    }

    @IsTest
    static void testGetBasemapKeyIsNullWhenBlank() {
        insert new Ken_Alm_Org_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Carto_Basemap_Client_Id__c = '   '
        );

        Test.startTest();
        String key = KenAlumniMapController.getBasemapKey();
        Test.stopTest();

        System.assertEquals(null, key, 'A whitespace-only key should be treated as unset');
    }

    @IsTest
    static void testGetBasemapKeyIsTrimmed() {
        // A key pasted from the CARTO dashboard commonly carries a trailing
        // space; it would otherwise be encoded into the tile URL as %20.
        insert new Ken_Alm_Org_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Carto_Basemap_Client_Id__c = '  test_carto_key_123  '
        );

        Test.startTest();
        String key = KenAlumniMapController.getBasemapKey();
        Test.stopTest();

        System.assertEquals('test_carto_key_123', key, 'Surrounding whitespace should be trimmed off the key');
    }
}