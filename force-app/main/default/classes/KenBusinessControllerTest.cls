@IsTest
private class KenBusinessControllerTest {

    private static final String ALUMNI_RT   = 'PersonAccount';
    private static final String BUSINESS_RT = 'Business';
    private static final String OWNER_RT    = 'Business_Owner';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
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

    private static Id getBusinessRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :BUSINESS_RT LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Id getOwnerJunctionRtId() {
        return Schema.SObjectType.Ken_Business_Directory__c.getRecordTypeInfosByDeveloperName().get(OWNER_RT)?.getRecordTypeId();
    }

    private static Boolean hasPersonAccountField = Ken_Business_Directory__c.SObjectType
        .getDescribe().fields.getMap().containsKey('Person_Account__c');

    /**
     * Stamps the person side of a business-directory junction. Person_Account__c is a
     * required field in the KJS orgs but does not exist in every client org, so it is
     * set dynamically to keep this class compiling and inserting everywhere.
     */
    private static void stampPersonAccount(Ken_Business_Directory__c link, Id personAccountId) {
        if (hasPersonAccountField && personAccountId != null) {
            link.put('Person_Account__c', personAccountId);
        }
    }

    /**
     * Resolves the person account behind a constituent role, only in orgs that
     * actually have Person_Account__c so no query is burned elsewhere.
     */
    private static Id personAccountForRole(Id roleId) {
        if (!hasPersonAccountField || roleId == null) {
            return null;
        }
        List<ConstituentRole> roles = [SELECT PersonId FROM ConstituentRole WHERE Id = :roleId LIMIT 1];
        return roles.isEmpty() ? null : roles[0].PersonId;
    }

    private static Id createAlumniRole(Id personAccountId) {
        ConstituentRole role = new ConstituentRole(
            PersonId = personAccountId,
            RoleType = 'Alumni',
            Status = 'Active'
        );
        insert role;
        return role.Id;
    }

    private static Id getRoleIdFor(Id personAccountId) {
        List<ConstituentRole> roles = [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :personAccountId AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return roles.isEmpty() ? null : roles[0].Id;
    }

    private static User buildRunAsUser() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username  = 'bizctrl.' + System.currentTimeMillis() + '@example.com',
            Email     = 'bizctrl@example.com',
            LastName  = 'BizCtrl',
            Alias     = 'bzct',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = prof.Id
        );
    }

    @TestSetup
    static void setupData() {
        Id paRtId = getPersonAccountRtId();
        Account ownerAcc = new Account(
            FirstName    = 'Business',
            LastName     = 'Owner',
            PersonEmail  = 'business.owner@test.example.com'
        );
        if (paRtId != null) {
            ownerAcc.RecordTypeId = paRtId;
        }
        insert ownerAcc;

        Id ownerRoleId = createAlumniRole(ownerAcc.Id);

        Id businessRtId = getBusinessRtId();
        Account bizAcc = new Account(
            Name                = 'Test Business Alpha',
            Business_Type__c    = 'Technology',
            Business_Approval__c = 'Approved',
            Is_Active__c        = true
        );
        if (businessRtId != null) {
            bizAcc.RecordTypeId = businessRtId;
        }
        insert bizAcc;

        Id ownerRtId = getOwnerJunctionRtId();
        Ken_Business_Directory__c link = new Ken_Business_Directory__c(
            Constituent_Role__c = ownerRoleId,
            Business_Account__c = bizAcc.Id
        );
        stampPersonAccount(link, ownerAcc.Id);
        if (ownerRtId != null) {
            link.RecordTypeId = ownerRtId;
        }
        insert link;
    }

    @IsTest
    static void testGetAllBusinessesReturnsRecords() {
        User runAsUser = buildRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            List<KenBusinessController.BusinessRow> rows = KenBusinessController.getAllBusinesses();
            Test.stopTest();

            System.assertNotEquals(null, rows, 'getAllBusinesses should not return null');
            System.assertEquals(true, rows.size() >= 1, 'Should return at least one business record');
        }
    }

    @IsTest
    static void testGetMyBusinessesWithCurrentAccount() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Test.startTest();
        List<KenBusinessController.BusinessRow> rows = KenBusinessController.getMyBusinesses();
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assertNotEquals(null, rows, 'getMyBusinesses should not return null for an owner');
        System.assertEquals(true, rows.size() >= 1, 'Owner should see at least one business');
    }

    @IsTest
    static void testGetMyBusinessesNoCurrentAccount() {
        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;

        Test.startTest();
        List<KenBusinessController.BusinessRow> rows = KenBusinessController.getMyBusinesses();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'getMyBusinesses should return empty list, not null, for no user');
        System.assertEquals(0, rows.size(), 'No current account should return empty list');
    }

    @IsTest
    static void testGetBusinessByIdExistingBusiness() {
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];

        Test.startTest();
        KenBusinessController.BusinessRow row = KenBusinessController.getBusinessById(bizAcc.Id);
        Test.stopTest();

        System.assertNotEquals(null, row, 'getBusinessById should return a row for a valid business Id');
        System.assertEquals('Test Business Alpha', row.name, 'Business name should match');
    }

    @IsTest
    static void testGetBusinessByIdNullId() {
        Test.startTest();
        KenBusinessController.BusinessRow row = KenBusinessController.getBusinessById(null);
        Test.stopTest();

        System.assertEquals(null, row, 'getBusinessById should return null when Id is null');
    }

    @IsTest
    static void testCreateBusinessSuccess() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Map<String, Object> req = new Map<String, Object>{
            'businessName' => 'New Test Business',
            'businessType' => 'Retail',
            'phone'        => '9876543210',
            'hidePhone'    => false,
            'email'        => 'biz@example.com',
            'hideEmail'    => false,
            'website'      => 'https://example.com',
            'address'      => '123 Main St',
            'description'  => 'A test business'
        };

        Test.startTest();
        Id bizId = KenBusinessController.createBusiness(req);
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assertNotEquals(null, bizId, 'createBusiness should return the new business Id');

        Account created = [SELECT Name, Business_Approval__c FROM Account WHERE Id = :bizId LIMIT 1];
        System.assertEquals('New Test Business', created.Name, 'Business name should match');
        System.assertEquals('Pending', created.Business_Approval__c, 'New business should have Pending approval');
    }

    @IsTest
    static void testCreateBusinessNullRequestThrowsException() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        try {
            Test.startTest();
            KenBusinessController.createBusiness(null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for null request');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void testCreateBusinessMissingNameThrowsException() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Map<String, Object> req = new Map<String, Object>{ 'businessType' => 'Retail' };

        try {
            Test.startTest();
            KenBusinessController.createBusiness(req);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException when business name is missing');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void testUpdateBusinessSuccess() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Map<String, Object> req = new Map<String, Object>{
            'id'           => (String) bizAcc.Id,
            'businessName' => 'Test Business Alpha Updated',
            'businessType' => 'Technology',
            'phone'        => '1234567890',
            'hidePhone'    => false,
            'email'        => 'updated@example.com',
            'hideEmail'    => false
        };

        Test.startTest();
        Id result = KenBusinessController.updateBusiness(req);
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assertEquals(bizAcc.Id, result, 'updateBusiness should return the updated business Id');

        Account updated = [SELECT Name FROM Account WHERE Id = :bizAcc.Id LIMIT 1];
        System.assertEquals('Test Business Alpha Updated', updated.Name, 'Business name should be updated');
    }

    @IsTest
    static void testUpdateBusinessClearsPendingFeature() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Feature_Approval__c = 'Pending Approval';
        bizAcc.Feature_Subject__c = 'Please feature us';
        bizAcc.Feature_Message__c = 'We are great';
        update bizAcc;
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Map<String, Object> req = new Map<String, Object>{
            'id'           => (String) bizAcc.Id,
            'businessName' => 'Test Business Alpha',
            'businessType' => 'Technology'
        };
        Test.startTest();
        KenBusinessController.updateBusiness(req);
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        Account after = [
            SELECT Business_Feature_Approval__c, Feature_Subject__c, Feature_Message__c
            FROM Account WHERE Id = :bizAcc.Id
        ];
        System.assertEquals(null, after.Business_Feature_Approval__c, 'Feature approval should be cancelled on edit');
        System.assertEquals(null, after.Feature_Subject__c, 'Feature subject should be cleared on edit');
        System.assertEquals(null, after.Feature_Message__c, 'Feature message should be cleared on edit');
    }

    @IsTest
    static void testUpdateBusinessAccessDeniedThrowsException() {
        Id paRtId = getPersonAccountRtId();
        Account otherAcc = new Account(LastName = 'OtherOwner');
        if (paRtId != null) {
            otherAcc.RecordTypeId = paRtId;
        }
        insert otherAcc;
        Id otherRoleId = createAlumniRole(otherAcc.Id);
        KenConstituentRoleService.testCurrentAccountId = otherAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = otherRoleId;

        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        Map<String, Object> req = new Map<String, Object>{
            'id'           => (String) bizAcc.Id,
            'businessName' => 'Should Not Update'
        };

        try {
            Test.startTest();
            KenBusinessController.updateBusiness(req);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for access denied');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void testBusinessRowHiddenPhoneAndEmail() {
        Id businessRtId = getBusinessRtId();
        Account hiddenBiz = new Account(
            Name                  = 'Hidden Phone Biz',
            Business_Type__c      = 'Finance',
            Business_Approval__c  = 'Approved',
            Is_Active__c          = true,
            Phone                 = '9999999999',
            Hide_Business_Phone__c = true,
            Business_Email__c     = 'hidden@biz.com',
            Hide_Business_Email__c = true
        );
        if (businessRtId != null) {
            hiddenBiz.RecordTypeId = businessRtId;
        }
        insert hiddenBiz;

        Test.startTest();
        KenBusinessController.BusinessRow row = KenBusinessController.getBusinessById(hiddenBiz.Id);
        Test.stopTest();

        System.assertNotEquals(null, row, 'Row should not be null for valid business Id');
        System.assertEquals('********99', row.phone, 'Phone should be masked (last 2 visible) when Hide_Business_Phone__c is true for a non-owner');
        System.assertEquals('h****@biz.com', row.email, 'Email should be masked when Hide_Business_Email__c is true for a non-owner');
    }

    @IsTest
    static void expressInterestStoresProspect() {
        Id paRt = getPersonAccountRtId();
        Account owner = new Account(FirstName = 'Biz', LastName = 'OwnerEI', PersonEmail = 'biz.owner.ei@test.example.com');
        if (paRt != null) { owner.RecordTypeId = paRt; }
        insert owner;
        Id ownerRoleId = createAlumniRole(owner.Id);

        Account interested = new Account(FirstName = 'Inte', LastName = 'RestedEI', PersonEmail = 'interested.ei@test.example.com');
        if (paRt != null) { interested.RecordTypeId = paRt; }
        insert interested;
        Id interestedRoleId = createAlumniRole(interested.Id);

        Id bizRt = getBusinessRtId();
        Account biz = new Account(
            Name = 'EI Biz', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = true,
            Business_Owner_Role__c = ownerRoleId
        );
        if (bizRt != null) { biz.RecordTypeId = bizRt; }
        insert biz;

        KenConstituentRoleService.testCurrentAccountId = interested.Id;
        KenConstituentRoleService.testCurrentRoleId = interestedRoleId;
        Test.startTest();
        KenBusinessController.expressInterest(biz.Id, 'Interested in products', 'Please contact me');
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        List<Ken_Business_Directory__c> prospects = [
            SELECT Subject__c, Message__c, Constituent_Role__c, RecordType.DeveloperName
            FROM Ken_Business_Directory__c
            WHERE Business_Account__c = :biz.Id AND Constituent_Role__c = :interestedRoleId
        ];
        System.assertEquals(1, prospects.size(), 'A prospect junction should be created');
        System.assertEquals('Business_Prospect', prospects[0].RecordType.DeveloperName, 'Should use Business_Prospect record type');
        System.assertEquals('Interested in products', prospects[0].Subject__c, 'Subject stored');
        System.assertEquals('Please contact me', prospects[0].Message__c, 'Message stored');
    }
    @IsTest
    static void expressInterestNotifiesOwner() {
        Id paRt = getPersonAccountRtId();
        Account owner = new Account(FirstName = 'Biz', LastName = 'OwnerNotify', PersonEmail = 'biz.owner.notify@test.example.com');
        if (paRt != null) { owner.RecordTypeId = paRt; }
        insert owner;
        Id ownerRoleId = createAlumniRole(owner.Id);

        Account interested = new Account(FirstName = 'Keen', LastName = 'BuyerNotify', PersonEmail = 'keen.buyer.notify@test.example.com');
        if (paRt != null) { interested.RecordTypeId = paRt; }
        insert interested;
        Id interestedRoleId = createAlumniRole(interested.Id);

        Id bizRt = getBusinessRtId();
        Account biz = new Account(
            Name = 'Notify Biz', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = true,
            Business_Owner_Role__c = ownerRoleId
        );
        if (bizRt != null) { biz.RecordTypeId = bizRt; }
        insert biz;

        KenConstituentRoleService.testCurrentAccountId = interested.Id;
        KenConstituentRoleService.testCurrentRoleId = interestedRoleId;
        Test.startTest();
        KenBusinessController.expressInterest(biz.Id, 'Want to partner', 'Call me');
        Test.stopTest();
        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;

        List<Ken_Notification__c> notifs = [
            SELECT Recipient__c, Category__c, Title__c, Body__c, Target_Url__c, Is_Read__c
            FROM Ken_Notification__c
            WHERE Recipient__c = :owner.Id
        ];
        System.assertEquals(1, notifs.size(), 'The business owner should get exactly one notification');
        System.assertEquals('Business', notifs[0].Category__c, 'Category should be Business');
        System.assert(notifs[0].Title__c.contains('Notify Biz'),
            'Title should name the business, was: ' + notifs[0].Title__c);
        System.assertEquals('Want to partner', notifs[0].Body__c, 'Body carries the subject the alumnus typed');
        System.assert(notifs[0].Target_Url__c.contains(biz.Id),
            'Target URL should deep-link to the business, was: ' + notifs[0].Target_Url__c);
        System.assertEquals(false, notifs[0].Is_Read__c, 'A new notification starts unread');
    }

    @IsTest
    static void expressInterestTwiceNotifiesOnlyOnce() {
        Id paRt = getPersonAccountRtId();
        Account owner = new Account(FirstName = 'Biz', LastName = 'OwnerOnce', PersonEmail = 'biz.owner.once@test.example.com');
        if (paRt != null) { owner.RecordTypeId = paRt; }
        insert owner;
        Id ownerRoleId = createAlumniRole(owner.Id);

        Account interested = new Account(FirstName = 'Repeat', LastName = 'BuyerOnce', PersonEmail = 'repeat.buyer.once@test.example.com');
        if (paRt != null) { interested.RecordTypeId = paRt; }
        insert interested;
        Id interestedRoleId = createAlumniRole(interested.Id);

        Id bizRt = getBusinessRtId();
        Account biz = new Account(
            Name = 'Once Biz', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = true,
            Business_Owner_Role__c = ownerRoleId
        );
        if (bizRt != null) { biz.RecordTypeId = bizRt; }
        insert biz;

        KenConstituentRoleService.testCurrentAccountId = interested.Id;
        KenConstituentRoleService.testCurrentRoleId = interestedRoleId;
        Test.startTest();
        KenBusinessController.expressInterest(biz.Id, 'First go', 'msg one');
        KenBusinessController.expressInterest(biz.Id, 'Second go', 'msg two');
        Test.stopTest();
        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;

        System.assertEquals(1, [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :owner.Id],
            'Re-expressing interest edits the same prospect and must not notify the owner again');
    }


    @IsTest
    static void ownerCannotExpressInterest() {
        Id paRt = getPersonAccountRtId();
        Account owner = new Account(FirstName = 'Biz', LastName = 'Owner2EI', PersonEmail = 'biz.owner2.ei@test.example.com');
        if (paRt != null) { owner.RecordTypeId = paRt; }
        insert owner;
        Id ownerRoleId = createAlumniRole(owner.Id);

        Id bizRt = getBusinessRtId();
        Account biz = new Account(
            Name = 'EI Biz2', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = true,
            Business_Owner_Role__c = ownerRoleId
        );
        if (bizRt != null) { biz.RecordTypeId = bizRt; }
        insert biz;

        KenConstituentRoleService.testCurrentAccountId = owner.Id;
        KenConstituentRoleService.testCurrentRoleId = ownerRoleId;
        Test.startTest();
        Boolean threw = false;
        try {
            KenBusinessController.expressInterest(biz.Id, 'x', 'y');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'Owner should not be able to express interest in their own business');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Ken_Business_Directory__c WHERE Business_Account__c = :biz.Id AND Constituent_Role__c = :ownerRoleId],
            'No prospect should be created for the owner'
        );
    }

    @IsTest
    static void getSimilarBusinessesReturnsSameCategoryApproved() {
        Id bizRt = getBusinessRtId();
        Account current = new Account(Name = 'Current Biz', Business_Type__c = 'Retail', Business_Approval__c = 'Approved', Is_Active__c = true);
        if (bizRt != null) { current.RecordTypeId = bizRt; }
        insert current;

        Account sameApproved = new Account(Name = 'Same Cat Approved', Business_Type__c = 'Retail', Business_Approval__c = 'Approved', Is_Active__c = true);
        if (bizRt != null) { sameApproved.RecordTypeId = bizRt; }
        insert sameApproved;

        Account samePending = new Account(Name = 'Same Cat Pending', Business_Type__c = 'Retail', Business_Approval__c = 'Pending', Is_Active__c = true);
        if (bizRt != null) { samePending.RecordTypeId = bizRt; }
        insert samePending;

        Account diffCat = new Account(Name = 'Diff Cat', Business_Type__c = 'Technology', Business_Approval__c = 'Approved', Is_Active__c = true);
        if (bizRt != null) { diffCat.RecordTypeId = bizRt; }
        insert diffCat;

        Test.startTest();
        List<KenBusinessController.BusinessRow> rows = KenBusinessController.getSimilarBusinesses(current.Id, 'Retail');
        Test.stopTest();

        Set<Id> ids = new Set<Id>();
        for (KenBusinessController.BusinessRow r : rows) { ids.add(r.id); }
        System.assert(ids.contains(sameApproved.Id), 'Same-category approved business should be included');
        System.assert(!ids.contains(current.Id), 'The current business should be excluded');
        System.assert(!ids.contains(samePending.Id), 'Pending business should be excluded');
        System.assert(!ids.contains(diffCat.Id), 'Different-category business should be excluded');
    }

    @IsTest
    static void getFeaturedBusinessesReturnsApprovedFeatured() {
        Id bizRt = getBusinessRtId();
        Account feat = new Account(
            Name = 'Feat Approved', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = true,
            Business_Feature_Approval__c = 'Approved'
        );
        if (bizRt != null) { feat.RecordTypeId = bizRt; }

        Account notFeat = new Account(
            Name = 'Feat Pending', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = true,
            Business_Feature_Approval__c = 'Pending Approval'
        );
        if (bizRt != null) { notFeat.RecordTypeId = bizRt; }
        insert new List<Account>{ feat, notFeat };

        Test.startTest();
        List<KenBusinessController.BusinessRow> rows = KenBusinessController.getFeaturedBusinesses();
        Test.stopTest();

        Set<Id> ids = new Set<Id>();
        for (KenBusinessController.BusinessRow r : rows) { ids.add(r.id); }
        System.assert(ids.contains(feat.Id), 'Feature-approved business should appear');
        System.assert(!ids.contains(notFeat.Id), 'Pending-feature business should not appear');
    }

    @IsTest
    static void requestFeatureSetsPending() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Test.startTest();
        KenBusinessController.requestFeature(bizAcc.Id, 'Please feature us', 'We are launching a new product line.', Date.today().addDays(1), Date.today().addDays(15));
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        Account after = [SELECT Business_Feature_Approval__c, Feature_Subject__c, Feature_Message__c FROM Account WHERE Id = :bizAcc.Id];
        System.assertEquals('Pending Approval', after.Business_Feature_Approval__c, 'Feature request should set status to Pending Approval');
        System.assertEquals('Please feature us', after.Feature_Subject__c, 'Subject should be stored');
        System.assertEquals('We are launching a new product line.', after.Feature_Message__c, 'Message should be stored');
    }

    @IsTest
    static void requestFeatureRequiresSubjectAndMessage() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            KenBusinessController.requestFeature(bizAcc.Id, '', '', null, null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assertEquals(true, threw, 'Blank subject/message should be rejected');
    }


    @IsTest
    static void setBusinessActiveDeactivatesSuccess() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Test.startTest();
        KenBusinessController.setBusinessActive(bizAcc.Id, false);
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assertEquals(false, [SELECT Is_Active__c FROM Account WHERE Id = :bizAcc.Id].Is_Active__c, 'Business should be de-activated');
    }

    @IsTest
    static void setBusinessActiveReactivatesSuccess() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Is_Active__c = false;
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Test.startTest();
        KenBusinessController.setBusinessActive(bizAcc.Id, true);
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assertEquals(true, [SELECT Is_Active__c FROM Account WHERE Id = :bizAcc.Id].Is_Active__c, 'Business should be re-activated');
    }

    @IsTest
    static void setBusinessActiveBlockedWhenInReview() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Approval__c = 'Pending';
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Boolean threw = false;
        Test.startTest();
        try { KenBusinessController.setBusinessActive(bizAcc.Id, false); } catch (Exception e) { threw = true; }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'setBusinessActive must throw when business is in review');
    }

    @IsTest
    static void setBusinessActiveBlockedWhenFeaturePending() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Feature_Approval__c = 'Pending Approval';
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Boolean threw = false;
        Test.startTest();
        try { KenBusinessController.setBusinessActive(bizAcc.Id, false); } catch (Exception e) { threw = true; }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'setBusinessActive must throw when feature approval is pending');
    }


    @IsTest
    static void deleteBusinessSuccess() {
        Id paRtId  = getPersonAccountRtId();
        Id bizRtId = getBusinessRtId();
        Id ownerRtId = getOwnerJunctionRtId();

        Account delOwner = new Account(FirstName = 'Del', LastName = 'Owner3', PersonEmail = 'del.owner3@test.example.com');
        if (paRtId != null) { delOwner.RecordTypeId = paRtId; }
        insert delOwner;
        Id delOwnerRoleId = createAlumniRole(delOwner.Id);

        Account delBiz = new Account(Name = 'To Be Deleted', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = true);
        if (bizRtId != null) { delBiz.RecordTypeId = bizRtId; }
        insert delBiz;

        Ken_Business_Directory__c link = new Ken_Business_Directory__c(
            Constituent_Role__c = delOwnerRoleId, Business_Account__c = delBiz.Id);
        stampPersonAccount(link, delOwner.Id);
        if (ownerRtId != null) { link.RecordTypeId = ownerRtId; }
        insert link;

        KenConstituentRoleService.testCurrentAccountId = delOwner.Id;
        KenConstituentRoleService.testCurrentRoleId = delOwnerRoleId;
        Test.startTest();
        KenBusinessController.deleteBusiness(delBiz.Id);
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        Account afterDelete = [SELECT Business_Approval__c FROM Account WHERE Id = :delBiz.Id];
        System.assertEquals('Pending Deletion', afterDelete.Business_Approval__c, 'Business should be marked Pending Deletion');
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Business_Directory__c WHERE Business_Account__c = :delBiz.Id], 'Junction records should remain until deletion is approved');
    }

    @IsTest
    static void deleteBusinessBlockedWhenInReview() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Approval__c = 'Pending';
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Boolean threw = false;
        Test.startTest();
        try { KenBusinessController.deleteBusiness(bizAcc.Id); } catch (Exception e) { threw = true; }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'deleteBusiness must throw when business is in review');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :bizAcc.Id], 'Business must not be deleted');
    }

    @IsTest
    static void deleteBusinessBlockedWhenFeaturePending() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Feature_Approval__c = 'Pending Approval';
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Boolean threw = false;
        Test.startTest();
        try { KenBusinessController.deleteBusiness(bizAcc.Id); } catch (Exception e) { threw = true; }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'deleteBusiness must throw when feature approval is pending');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :bizAcc.Id], 'Business must not be deleted');
    }

    @IsTest
    static void deleteBusinessAccessDenied() {
        Id paRtId = getPersonAccountRtId();
        Account nonOwner = new Account(LastName = 'NonOwner3');
        if (paRtId != null) { nonOwner.RecordTypeId = paRtId; }
        insert nonOwner;
        Id nonOwnerRoleId = createAlumniRole(nonOwner.Id);

        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = nonOwner.Id;
        KenConstituentRoleService.testCurrentRoleId = nonOwnerRoleId;
        Boolean threw = false;
        Test.startTest();
        try { KenBusinessController.deleteBusiness(bizAcc.Id); } catch (Exception e) { threw = true; }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'Non-owner must not be able to delete');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :bizAcc.Id], 'Business must remain');
    }


    @IsTest
    static void removeFeatureSuccess() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Feature_Approval__c = 'Approved';
        bizAcc.Feature_Subject__c = 'Old subject';
        bizAcc.Feature_Message__c = 'Old message';
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Test.startTest();
        KenBusinessController.removeFeature(bizAcc.Id);
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        Account after = [SELECT Business_Feature_Approval__c, Feature_Subject__c, Feature_Message__c FROM Account WHERE Id = :bizAcc.Id];
        System.assertEquals(null, after.Business_Feature_Approval__c, 'Feature status should be cleared');
        System.assertEquals(null, after.Feature_Subject__c, 'Feature subject should be cleared');
        System.assertEquals(null, after.Feature_Message__c, 'Feature message should be cleared');
    }

    @IsTest
    static void removeFeatureBlockedWhenPending() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Feature_Approval__c = 'Pending Approval';
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Boolean threw = false;
        Test.startTest();
        try { KenBusinessController.removeFeature(bizAcc.Id); } catch (Exception e) { threw = true; }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'removeFeature must throw when feature approval is pending');
    }

    @IsTest
    static void removeFeatureBlockedWhenNotFeatured() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc   = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Boolean threw = false;
        Test.startTest();
        try { KenBusinessController.removeFeature(bizAcc.Id); } catch (Exception e) { threw = true; }
        Test.stopTest();

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        System.assert(threw, 'removeFeature must throw when business is not featured');
    }


    @IsTest
    static void getAllBusinessesExcludesDeactivated() {
        Id bizRtId = getBusinessRtId();
        Account deactivated = new Account(Name = 'Deactivated Biz', Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved', Is_Active__c = false);
        if (bizRtId != null) { deactivated.RecordTypeId = bizRtId; }
        insert deactivated;

        User runAsUser = buildRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            List<KenBusinessController.BusinessRow> rows = KenBusinessController.getAllBusinesses();
            Test.stopTest();

            for (KenBusinessController.BusinessRow r : rows) {
                System.assertNotEquals(deactivated.Id, r.id, 'De-activated business must not appear in the directory');
            }
        }
    }

    @IsTest
    static void getSimilarBusinessesExcludesDeactivated() {
        Id bizRtId = getBusinessRtId();

        Account current = new Account(Name = 'Current Similar Biz', Business_Type__c = 'Finance',
            Business_Approval__c = 'Approved', Is_Active__c = true);
        if (bizRtId != null) { current.RecordTypeId = bizRtId; }
        insert current;

        Account deactivated = new Account(Name = 'Deactivated Similar', Business_Type__c = 'Finance',
            Business_Approval__c = 'Approved', Is_Active__c = false);
        if (bizRtId != null) { deactivated.RecordTypeId = bizRtId; }
        insert deactivated;

        Account active = new Account(Name = 'Active Similar', Business_Type__c = 'Finance',
            Business_Approval__c = 'Approved', Is_Active__c = true);
        if (bizRtId != null) { active.RecordTypeId = bizRtId; }
        insert active;

        Test.startTest();
        List<KenBusinessController.BusinessRow> rows = KenBusinessController.getSimilarBusinesses(current.Id, 'Finance');
        Test.stopTest();

        Set<Id> ids = new Set<Id>();
        for (KenBusinessController.BusinessRow r : rows) { ids.add(r.id); }
        System.assert(ids.contains(active.Id), 'Active similar business should be returned');
        System.assert(!ids.contains(deactivated.Id), 'De-activated business must not appear as similar');
        System.assert(!ids.contains(current.Id), 'Current business must be excluded from similar');
    }

    private static Id getProspectJunctionRtId() {
        return Schema.SObjectType.Ken_Business_Directory__c.getRecordTypeInfosByDeveloperName().get('Business_Prospect')?.getRecordTypeId();
    }

    private static Account createPerson(String firstName, String lastName) {
        Id paRtId = getPersonAccountRtId();
        Account a = new Account(FirstName = firstName, LastName = lastName);
        if (paRtId != null) { a.RecordTypeId = paRtId; }
        insert a;
        return a;
    }

    private static Account createBiz(String name, String bizType, String approval, Boolean active) {
        Id bizRtId = getBusinessRtId();
        Account b = new Account(
            Name = name,
            Business_Type__c = bizType,
            Business_Approval__c = approval,
            Is_Active__c = active
        );
        if (bizRtId != null) { b.RecordTypeId = bizRtId; }
        insert b;
        return b;
    }

    private static void linkOwner(Id roleId, Id accountId) {
        Ken_Business_Directory__c link = new Ken_Business_Directory__c(
            Constituent_Role__c = roleId,
            Business_Account__c = accountId
        );
        stampPersonAccount(link, personAccountForRole(roleId));
        Id ownerRtId = getOwnerJunctionRtId();
        if (ownerRtId != null) { link.RecordTypeId = ownerRtId; }
        insert link;
    }

    @IsTest
    static void getMyBusinessesEmptyWhenNoOwnerLinks() {
        Account lone = createPerson('Lone', 'RoleNoBiz');
        Id loneRoleId = createAlumniRole(lone.Id);
        KenConstituentRoleService.testCurrentAccountId = lone.Id;
        KenConstituentRoleService.testCurrentRoleId = loneRoleId;
        try {
            Test.startTest();
            List<KenBusinessController.BusinessRow> rows = KenBusinessController.getMyBusinesses();
            Test.stopTest();
            System.assertEquals(0, rows.size(), 'Role with no owner junctions should get an empty list');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void getMyBusinessesFlagsRejectedRows() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Id roleId = getRoleIdFor(ownerAcc.Id);
        Account featRej = createBiz('Feature Rejected Biz', 'Technology', 'Approved', true);
        featRej.Business_Feature_Approval__c = 'Rejected';
        update featRej;
        Account bizRej = createBiz('Business Rejected Biz', 'Technology', 'Rejected', true);
        linkOwner(roleId, featRej.Id);
        linkOwner(roleId, bizRej.Id);

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = roleId;
        try {
            Test.startTest();
            List<KenBusinessController.BusinessRow> rows = KenBusinessController.getMyBusinesses();
            Test.stopTest();
            Map<Id, KenBusinessController.BusinessRow> byId = new Map<Id, KenBusinessController.BusinessRow>();
            for (KenBusinessController.BusinessRow r : rows) { byId.put(r.id, r); }
            System.assert(byId.containsKey(featRej.Id), 'Feature-rejected business should be in my businesses');
            System.assert(byId.containsKey(bizRej.Id), 'Rejected business should be in my businesses');
            System.assertEquals('Rejected', byId.get(featRej.Id).featureStatus, 'Feature status should be Rejected');
            System.assertEquals('Rejected', byId.get(bizRej.Id).status, 'Business status should be Rejected');
            System.assertEquals(null, byId.get(featRej.Id).featureRejectionReason, 'No approval steps exist so no feature rejection comment');
            System.assertEquals(null, byId.get(bizRej.Id).rejectionReason, 'No approval steps exist so no business rejection comment');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void getBusinessByIdReturnsNullForNonBusinessAccount() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Test.startTest();
        KenBusinessController.BusinessRow row = KenBusinessController.getBusinessById(ownerAcc.Id);
        Test.stopTest();
        System.assertEquals(null, row, 'A non-business account Id should return null');
    }

    @IsTest
    static void getBusinessByIdPopulatesRejectionFields() {
        Account featRej = createBiz('ById Feature Rejected', 'Technology', 'Approved', true);
        featRej.Business_Feature_Approval__c = 'Rejected';
        update featRej;
        Account bizRej = createBiz('ById Business Rejected', 'Technology', 'Rejected', true);

        Test.startTest();
        KenBusinessController.BusinessRow featRow = KenBusinessController.getBusinessById(featRej.Id);
        KenBusinessController.BusinessRow rejRow = KenBusinessController.getBusinessById(bizRej.Id);
        Test.stopTest();

        System.assertEquals('Rejected', featRow.featureStatus, 'Feature status should be Rejected');
        System.assertEquals(null, featRow.featureRejectionReason, 'No approval steps exist so comment stays null');
        System.assertEquals('Rejected', rejRow.status, 'Business status should be Rejected');
        System.assertEquals(null, rejRow.rejectionReason, 'No approval steps exist so comment stays null');
    }

    @IsTest
    static void getBusinessByIdMarksInterestExpressed() {
        Account viewer = createPerson('View', 'ErInterest');
        Id viewerRoleId = createAlumniRole(viewer.Id);
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];

        Ken_Business_Directory__c prospect = new Ken_Business_Directory__c(
            Constituent_Role__c = viewerRoleId,
            Business_Account__c = bizAcc.Id,
            Subject__c = 'Hi',
            Message__c = 'Interested'
        );
        stampPersonAccount(prospect, viewer.Id);
        Id prospectRtId = getProspectJunctionRtId();
        if (prospectRtId != null) { prospect.RecordTypeId = prospectRtId; }
        insert prospect;

        KenConstituentRoleService.testCurrentAccountId = viewer.Id;
        KenConstituentRoleService.testCurrentRoleId = viewerRoleId;
        try {
            Test.startTest();
            KenBusinessController.BusinessRow row = KenBusinessController.getBusinessById(bizAcc.Id);
            Test.stopTest();
            System.assertEquals(false, row.isOwner, 'Viewer is not the owner');
            System.assertEquals(true, row.interestExpressed, 'Existing prospect junction should mark interest as expressed');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void getBusinessByIdResolvesRoleFromService() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Id roleId = getRoleIdFor(ownerAcc.Id);
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Owner_Role__c = roleId;
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = roleId;
        Test.startTest();
        KenBusinessController.BusinessRow row = KenBusinessController.getBusinessById(bizAcc.Id);
        Test.stopTest();
        KenConstituentRoleService.testCurrentRoleId = null;

        System.assertNotEquals(null, row, 'Row should resolve when the service resolves the role');
        System.assertEquals(true, row.isOwner, 'Resolved role matching Business_Owner_Role__c should mark owner');
    }

    @IsTest
    static void getSimilarBusinessesBlankOrUnknownCategory() {
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        Test.startTest();
        List<KenBusinessController.BusinessRow> blankRows = KenBusinessController.getSimilarBusinesses(bizAcc.Id, '');
        List<KenBusinessController.BusinessRow> unknownRows = KenBusinessController.getSimilarBusinesses(bizAcc.Id, 'ZZZ No Such Category');
        Test.stopTest();
        System.assertEquals(0, blankRows.size(), 'Blank category should short-circuit to an empty list');
        System.assertEquals(0, unknownRows.size(), 'Unknown category should return an empty list');
    }

    @IsTest
    static void createBusinessMissingTypeThrows() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Boolean threw = false;
        try {
            KenBusinessController.createBusiness(new Map<String, Object>{ 'businessName' => 'No Type Biz' });
        } catch (AuraHandledException e) {
            threw = true;
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        System.assert(threw, 'Missing business type must throw');
    }

    @IsTest
    static void createBusinessWithImagesAndStringBooleans() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Map<String, Object> req = new Map<String, Object>{
            'businessName'       => 'Image Upload Biz',
            'businessType'       => 'Technology',
            'hidePhone'          => 'true',
            'hideEmail'          => 'yes',
            'coverPictureName'   => 'cover.png',
            'coverPictureBase64' => 'data:image/png;base64,aGVsbG8=',
            'logoName'           => 'logo.png',
            'logoBase64'         => 'data:image/png;base64,d29ybGQ='
        };
        try {
            Test.startTest();
            Id bizId = KenBusinessController.createBusiness(req);
            Test.stopTest();
            System.assertNotEquals(null, bizId, 'Business should be created');
            Account created = [SELECT Hide_Business_Phone__c, Hide_Business_Email__c FROM Account WHERE Id = :bizId];
            System.assertEquals(true, created.Hide_Business_Phone__c, 'String true should coerce to boolean true');
            System.assertEquals(true, created.Hide_Business_Email__c, 'String yes should coerce to boolean true');
            System.assertEquals(2, [SELECT COUNT() FROM ContentVersion WHERE Title IN ('cover.png', 'logo.png')], 'Cover and logo files should be uploaded');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void updateBusinessRequestValidationThrows() {
        Boolean threwNullReq = false;
        Boolean threwNoId = false;
        Boolean threwBadId = false;
        try {
            KenBusinessController.updateBusiness(null);
        } catch (AuraHandledException e) {
            threwNullReq = true;
        }
        try {
            KenBusinessController.updateBusiness(new Map<String, Object>{ 'businessName' => 'X' });
        } catch (AuraHandledException e) {
            threwNoId = true;
        }
        try {
            KenBusinessController.updateBusiness(new Map<String, Object>{ 'id' => 'not-a-valid-id' });
        } catch (AuraHandledException e) {
            threwBadId = true;
        }
        System.assert(threwNullReq, 'Null request must throw');
        System.assert(threwNoId, 'Missing id must throw');
        System.assert(threwBadId, 'Unparseable id must throw');
    }

    @IsTest
    static void updateBusinessNotFoundThrows() {
        Account editor = createPerson('Upd', 'NotFoundEd');
        Id editorRoleId = createAlumniRole(editor.Id);
        Account target = createPerson('Not', 'ABusiness');
        linkOwner(editorRoleId, target.Id);

        KenConstituentRoleService.testCurrentAccountId = editor.Id;
        KenConstituentRoleService.testCurrentRoleId = editorRoleId;
        Boolean threw = false;
        try {
            KenBusinessController.updateBusiness(new Map<String, Object>{ 'id' => (String) target.Id, 'businessName' => 'X' });
        } catch (AuraHandledException e) {
            threw = true;
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        System.assert(threw, 'Junction pointing at a non-business account must throw Business not found');
    }

    @IsTest
    static void updateBusinessResubmitsWhenPendingAndUploadsImages() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Approval__c = 'Pending';
        update bizAcc;

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        Map<String, Object> req = new Map<String, Object>{
            'id'                 => (String) bizAcc.Id,
            'businessName'       => 'Alpha Pending Edit',
            'businessType'       => 'Technology',
            'coverPictureName'   => 'ucover.png',
            'coverPictureBase64' => 'data:image/png;base64,aGVsbG8=',
            'logoName'           => 'ulogo.png',
            'logoBase64'         => 'data:image/png;base64,d29ybGQ='
        };
        try {
            Test.startTest();
            Id result = KenBusinessController.updateBusiness(req);
            Test.stopTest();
            System.assertEquals(bizAcc.Id, result, 'Update should return the business Id');
            Account after = [SELECT Name, Business_Approval__c FROM Account WHERE Id = :bizAcc.Id];
            System.assertEquals('Alpha Pending Edit', after.Name, 'Name should be updated');
            System.assertEquals('Pending', after.Business_Approval__c, 'Pending business should stay Pending after resubmit');
            System.assertEquals(2, [SELECT COUNT() FROM ContentVersion WHERE Title IN ('ucover.png', 'ulogo.png')], 'Updated cover and logo files should be uploaded');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void requestFeatureDateValidationThrows() {
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        Boolean threwNullBiz = false;
        Boolean threwNullDates = false;
        Boolean threwReversedDates = false;
        try {
            KenBusinessController.requestFeature(null, 's', 'm', Date.today(), Date.today().addDays(5));
        } catch (AuraHandledException e) {
            threwNullBiz = true;
        }
        try {
            KenBusinessController.requestFeature(bizAcc.Id, 's', 'm', null, null);
        } catch (AuraHandledException e) {
            threwNullDates = true;
        }
        try {
            KenBusinessController.requestFeature(bizAcc.Id, 's', 'm', Date.today().addDays(5), Date.today());
        } catch (AuraHandledException e) {
            threwReversedDates = true;
        }
        System.assert(threwNullBiz, 'Null business must throw');
        System.assert(threwNullDates, 'Null dates must throw');
        System.assert(threwReversedDates, 'End before start must throw');
    }

    @IsTest
    static void requestFeatureAccessDeniedForInternalUserWithoutRole() {
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = null;
        KenConstituentRoleService.testCurrentRoleId = null;
        Boolean threw = false;
        Test.startTest();
        try {
            KenBusinessController.requestFeature(bizAcc.Id, 's', 'm', Date.today(), Date.today().addDays(5));
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Internal user with no owner junction should be denied');
    }

    @IsTest
    static void requestFeatureStateValidationThrows() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Id roleId = getRoleIdFor(ownerAcc.Id);
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        Account target = createPerson('Feat', 'NotABiz');
        linkOwner(roleId, target.Id);

        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = roleId;
        Boolean threwNotFound = false;
        Boolean threwNotApproved = false;
        Boolean threwAlreadyPending = false;
        try {
            try {
                KenBusinessController.requestFeature(target.Id, 's', 'm', Date.today(), Date.today().addDays(5));
            } catch (AuraHandledException e) {
                threwNotFound = true;
            }
            bizAcc.Business_Approval__c = 'Pending';
            update bizAcc;
            try {
                KenBusinessController.requestFeature(bizAcc.Id, 's', 'm', Date.today(), Date.today().addDays(5));
            } catch (AuraHandledException e) {
                threwNotApproved = true;
            }
            bizAcc.Business_Approval__c = 'Approved';
            bizAcc.Business_Feature_Approval__c = 'Pending Approval';
            update bizAcc;
            try {
                KenBusinessController.requestFeature(bizAcc.Id, 's', 'm', Date.today(), Date.today().addDays(5));
            } catch (AuraHandledException e) {
                threwAlreadyPending = true;
            }
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        System.assert(threwNotFound, 'Non-business junction target must throw not found');
        System.assert(threwNotApproved, 'Non-approved business must not request feature');
        System.assert(threwAlreadyPending, 'Already pending feature request must throw');
    }

    @IsTest
    static void setBusinessActiveValidationThrows() {
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        Account stranger = createPerson('Set', 'ActiveStranger');
        Id strangerRoleId = createAlumniRole(stranger.Id);
        Account target = createPerson('Set', 'ActiveTarget');
        linkOwner(strangerRoleId, target.Id);

        Boolean threwNullId = false;
        Boolean threwDenied = false;
        Boolean threwNotFound = false;
        try {
            KenBusinessController.setBusinessActive(null, true);
        } catch (AuraHandledException e) {
            threwNullId = true;
        }
        KenConstituentRoleService.testCurrentAccountId = stranger.Id;
        KenConstituentRoleService.testCurrentRoleId = strangerRoleId;
        try {
            try {
                KenBusinessController.setBusinessActive(bizAcc.Id, false);
            } catch (AuraHandledException e) {
                threwDenied = true;
            }
            try {
                KenBusinessController.setBusinessActive(target.Id, true);
            } catch (AuraHandledException e) {
                threwNotFound = true;
            }
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        System.assert(threwNullId, 'Null business must throw');
        System.assert(threwDenied, 'Non-owner must be denied');
        System.assert(threwNotFound, 'Non-business junction target must throw not found');
    }

    @IsTest
    static void deleteBusinessValidationThrows() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Id roleId = getRoleIdFor(ownerAcc.Id);
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        Account target = createPerson('Del', 'NotABizTarget');
        linkOwner(roleId, target.Id);

        Boolean threwNullId = false;
        Boolean threwNotFound = false;
        Boolean threwAlreadyPending = false;
        try {
            KenBusinessController.deleteBusiness(null);
        } catch (AuraHandledException e) {
            threwNullId = true;
        }
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = roleId;
        try {
            try {
                KenBusinessController.deleteBusiness(target.Id);
            } catch (AuraHandledException e) {
                threwNotFound = true;
            }
            bizAcc.Business_Approval__c = 'Pending Deletion';
            update bizAcc;
            try {
                KenBusinessController.deleteBusiness(bizAcc.Id);
            } catch (AuraHandledException e) {
                threwAlreadyPending = true;
            }
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        System.assert(threwNullId, 'Null business must throw');
        System.assert(threwNotFound, 'Non-business junction target must throw not found');
        System.assert(threwAlreadyPending, 'Duplicate deletion request must throw');
    }

    @IsTest
    static void approveBusinessDeletionSuccessAndValidation() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Approval__c = 'Pending Deletion';
        update bizAcc;

        Boolean threwNullId = false;
        Boolean threwNotFound = false;
        try {
            KenBusinessController.approveBusinessDeletion(null);
        } catch (AuraHandledException e) {
            threwNullId = true;
        }
        try {
            KenBusinessController.approveBusinessDeletion(ownerAcc.Id);
        } catch (AuraHandledException e) {
            threwNotFound = true;
        }

        Test.startTest();
        KenBusinessController.approveBusinessDeletion(bizAcc.Id);
        Test.stopTest();

        Account after = [SELECT Business_Approval__c, Is_Active__c FROM Account WHERE Id = :bizAcc.Id];
        System.assert(threwNullId, 'Null business must throw');
        System.assert(threwNotFound, 'Non-business account must throw not found');
        System.assertEquals('Deleted', after.Business_Approval__c, 'Approving deletion should mark the business Deleted');
        System.assertEquals(false, after.Is_Active__c, 'Deleted business should be inactive');
    }

    @IsTest
    static void dismissBusinessDeletionSuccessAndValidation() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        bizAcc.Business_Approval__c = 'Pending Deletion';
        update bizAcc;

        Boolean threwNullId = false;
        Boolean threwNotFound = false;
        try {
            KenBusinessController.dismissBusinessDeletion(null);
        } catch (AuraHandledException e) {
            threwNullId = true;
        }
        try {
            KenBusinessController.dismissBusinessDeletion(ownerAcc.Id);
        } catch (AuraHandledException e) {
            threwNotFound = true;
        }

        Test.startTest();
        KenBusinessController.dismissBusinessDeletion(bizAcc.Id);
        Test.stopTest();

        Account after = [SELECT Business_Approval__c FROM Account WHERE Id = :bizAcc.Id];
        System.assert(threwNullId, 'Null business must throw');
        System.assert(threwNotFound, 'Non-business account must throw not found');
        System.assertEquals('Approved', after.Business_Approval__c, 'Dismissing deletion should restore Approved status');
    }

    @IsTest
    static void removeFeatureValidationThrows() {
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];
        Account stranger = createPerson('Rem', 'FeatStranger');
        Id strangerRoleId = createAlumniRole(stranger.Id);
        Account target = createPerson('Rem', 'FeatTarget');
        linkOwner(strangerRoleId, target.Id);

        Boolean threwNullId = false;
        Boolean threwDenied = false;
        Boolean threwNotFound = false;
        try {
            KenBusinessController.removeFeature(null);
        } catch (AuraHandledException e) {
            threwNullId = true;
        }
        KenConstituentRoleService.testCurrentAccountId = stranger.Id;
        KenConstituentRoleService.testCurrentRoleId = strangerRoleId;
        try {
            try {
                KenBusinessController.removeFeature(bizAcc.Id);
            } catch (AuraHandledException e) {
                threwDenied = true;
            }
            try {
                KenBusinessController.removeFeature(target.Id);
            } catch (AuraHandledException e) {
                threwNotFound = true;
            }
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        System.assert(threwNullId, 'Null business must throw');
        System.assert(threwDenied, 'Non-owner must be denied');
        System.assert(threwNotFound, 'Non-business junction target must throw not found');
    }

    @IsTest
    static void getAdminBusinessListCoversAllStatuses() {
        Account rejBiz = createBiz('Admin Rejected', 'Technology', 'Rejected', true);
        Account delBiz = createBiz('Admin Deleted', 'Technology', 'Deleted', false);
        Account pendDelBiz = createBiz('Admin Pending Deletion', 'Technology', 'Pending Deletion', true);
        Account pendBiz = createBiz('Admin In Review', 'Technology', 'Pending', true);
        Account deactBiz = createBiz('Admin Deactivated', 'Technology', 'Approved', false);
        Account activeBiz = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];

        Test.startTest();
        List<KenBusinessController.BusinessRow> rows = KenBusinessController.getAdminBusinessList();
        Test.stopTest();

        Map<Id, String> statusById = new Map<Id, String>();
        for (KenBusinessController.BusinessRow r : rows) { statusById.put(r.id, r.status); }
        System.assertEquals('Rejected', statusById.get(rejBiz.Id), 'Rejected business maps to Rejected');
        System.assertEquals('Deleted', statusById.get(delBiz.Id), 'Deleted business maps to Deleted');
        System.assertEquals('Deletion Under Review', statusById.get(pendDelBiz.Id), 'Pending Deletion maps to Deletion Under Review');
        System.assertEquals('In review', statusById.get(pendBiz.Id), 'Pending business maps to In review');
        System.assertEquals('De-activated', statusById.get(deactBiz.Id), 'Inactive approved business maps to De-activated');
        System.assertEquals('Active', statusById.get(activeBiz.Id), 'Active approved business maps to Active');
    }

    @IsTest
    static void getAdminFeatureListCoversFeatureStates() {
        Account fRej = createBiz('Admin Feature Rejected', 'Technology', 'Approved', true);
        fRej.Business_Feature_Approval__c = 'Rejected';
        update fRej;
        Account fPend = createBiz('Admin Feature Pending', 'Technology', 'Approved', true);
        fPend.Business_Feature_Approval__c = 'Pending Approval';
        update fPend;
        Account fAppr = createBiz('Admin Feature Approved', 'Technology', 'Approved', true);
        fAppr.Business_Feature_Approval__c = 'Approved';
        update fAppr;
        Account noFeature = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];

        Test.startTest();
        List<KenBusinessController.BusinessRow> rows = KenBusinessController.getAdminFeatureList();
        Test.stopTest();

        Map<Id, KenBusinessController.BusinessRow> byId = new Map<Id, KenBusinessController.BusinessRow>();
        for (KenBusinessController.BusinessRow r : rows) { byId.put(r.id, r); }
        System.assert(byId.containsKey(fRej.Id), 'Feature-rejected business should be listed');
        System.assert(byId.containsKey(fPend.Id), 'Feature-pending business should be listed');
        System.assert(byId.containsKey(fAppr.Id), 'Feature-approved business should be listed');
        System.assert(!byId.containsKey(noFeature.Id), 'Business without feature status must not be listed');
        System.assertEquals('Rejected', byId.get(fRej.Id).featureStatus, 'Feature status should be Rejected');
        System.assertEquals(null, byId.get(fRej.Id).featureRejectionReason, 'No approval steps exist so no rejection comment');
    }

    @IsTest
    static void expressInterestBusinessValidationThrows() {
        Account viewer = createPerson('Exp', 'InterestViewer');
        Id viewerRoleId = createAlumniRole(viewer.Id);
        Account ghost = createBiz('Ghost Biz', 'Technology', 'Approved', true);
        Id ghostId = ghost.Id;
        delete ghost;

        KenConstituentRoleService.testCurrentAccountId = viewer.Id;
        KenConstituentRoleService.testCurrentRoleId = viewerRoleId;
        Boolean threwNullId = false;
        Boolean threwNotFound = false;
        try {
            try {
                KenBusinessController.expressInterest(null, 's', 'm');
            } catch (AuraHandledException e) {
                threwNullId = true;
            }
            try {
                KenBusinessController.expressInterest(ghostId, 's', 'm');
            } catch (AuraHandledException e) {
                threwNotFound = true;
            }
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        System.assert(threwNullId, 'Null business must throw');
        System.assert(threwNotFound, 'Deleted business must throw not found');
    }

    @IsTest
    static void expressInterestTwiceUpdatesExisting() {
        Account viewer = createPerson('Twice', 'InterestViewer');
        Id viewerRoleId = createAlumniRole(viewer.Id);
        Account bizAcc = [SELECT Id FROM Account WHERE Name = 'Test Business Alpha' LIMIT 1];

        KenConstituentRoleService.testCurrentAccountId = viewer.Id;
        KenConstituentRoleService.testCurrentRoleId = viewerRoleId;
        try {
            Test.startTest();
            KenBusinessController.expressInterest(bizAcc.Id, 'First subject', 'First message');
            KenBusinessController.expressInterest(bizAcc.Id, 'Second subject', 'Second message');
            Test.stopTest();
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
        List<Ken_Business_Directory__c> prospects = [
            SELECT Subject__c, Message__c FROM Ken_Business_Directory__c
            WHERE Business_Account__c = :bizAcc.Id AND Constituent_Role__c = :viewerRoleId
        ];
        System.assertEquals(1, prospects.size(), 'Second interest must update the existing prospect, not create another');
        System.assertEquals('Second subject', prospects[0].Subject__c, 'Subject should reflect the latest interest');
        System.assertEquals('Second message', prospects[0].Message__c, 'Message should reflect the latest interest');
    }

    @IsTest
    static void getMyBusinessesResolvesRoleFromAccountSeam() {
        Account ownerAcc = [SELECT Id FROM Account WHERE LastName = 'Owner' LIMIT 1];
        KenConstituentRoleService.testCurrentAccountId = ownerAcc.Id;
        KenConstituentRoleService.testCurrentRoleId = null;
        try {
            Test.startTest();
            List<KenBusinessController.BusinessRow> rows = KenBusinessController.getMyBusinesses();
            Test.stopTest();
            System.assert(rows.size() >= 1, 'Role resolved from the account seam should find the owned business');
        } finally {
            KenConstituentRoleService.testCurrentAccountId = null;
            KenConstituentRoleService.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void maskingHandlesShortAndBlankValues() {
        Id bizRtId = getBusinessRtId();
        Account shortPhoneBiz = new Account(
            Name = 'Short Phone Biz',
            Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved',
            Is_Active__c = true,
            Phone = '12',
            Hide_Business_Phone__c = true,
            Hide_Business_Email__c = true
        );
        if (bizRtId != null) { shortPhoneBiz.RecordTypeId = bizRtId; }
        Account blankPhoneBiz = new Account(
            Name = 'Blank Phone Biz',
            Business_Type__c = 'Technology',
            Business_Approval__c = 'Approved',
            Is_Active__c = true,
            Hide_Business_Phone__c = true
        );
        if (bizRtId != null) { blankPhoneBiz.RecordTypeId = bizRtId; }
        insert new List<Account>{ shortPhoneBiz, blankPhoneBiz };

        Test.startTest();
        KenBusinessController.BusinessRow shortRow = KenBusinessController.getBusinessById(shortPhoneBiz.Id);
        KenBusinessController.BusinessRow blankRow = KenBusinessController.getBusinessById(blankPhoneBiz.Id);
        Test.stopTest();

        System.assertEquals('**', shortRow.phone, 'Phones of 2 or fewer digits should mask to **');
        System.assertEquals('—', shortRow.email, 'Blank hidden email should render the em-dash placeholder');
        System.assertEquals('—', blankRow.phone, 'Blank hidden phone should render the em-dash placeholder');
    }

    @IsTest
    static void ownerNameFallsBackWhenFirstNameBlank() {
        Account solo = createPerson(null, 'SoloOwnerName');
        Id soloRoleId = createAlumniRole(solo.Id);
        Account biz = createBiz('Solo Owned Biz', 'Technology', 'Approved', true);

        Ken_Business_Directory__c nullRoleLink = new Ken_Business_Directory__c(
            Business_Account__c = biz.Id
        );
        stampPersonAccount(nullRoleLink, solo.Id);
        Id ownerRtId = getOwnerJunctionRtId();
        if (ownerRtId != null) { nullRoleLink.RecordTypeId = ownerRtId; }
        insert nullRoleLink;
        linkOwner(soloRoleId, biz.Id);

        Test.startTest();
        KenBusinessController.BusinessRow row = KenBusinessController.getBusinessById(biz.Id);
        Test.stopTest();

        System.assertNotEquals(null, row.ownerName, 'Owner name should resolve from the junction');
        System.assert(row.ownerName.contains('SoloOwnerName'), 'Owner name should include the last name when first name is blank');
    }
}