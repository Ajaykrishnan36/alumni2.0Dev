@IsTest
private class KenFundraiseControllerTest {

    private static final String ALUMNI_RT = 'Alumni_Person_Account';

    /**
     * @description Resolves the Person Account record type, falling back to any person type.
     */
    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
            if (rt.IsPersonType) {
                return rt.Id;
            }
        }
        return null;
    }

    /**
     * @description Creates an active Alumni ConstituentRole for the given person account.
     */
    private static Id createAlumniRole(Id personAccountId) {
        ConstituentRole role = new ConstituentRole(
            PersonId = personAccountId,
            RoleType = 'Alumni',
            Status = 'Active'
        );
        insert role;
        return role.Id;
    }

    /**
     * @description Fetches the latest Alumni role for a person account.
     */
    private static Id getRoleIdFor(Id personAccountId) {
        List<ConstituentRole> roles = [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :personAccountId AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return roles.isEmpty() ? null : roles[0].Id;
    }

    /**
     * @description Fetches a setup person account by last name.
     */
    private static Account getAccountByLastName(String lastName) {
        return [SELECT Id FROM Account WHERE LastName = :lastName LIMIT 1];
    }

    /**
     * @description Fetches a setup campaign by name.
     */
    private static Ken_Fundraise__c getCampaignByName(String name) {
        return [
            SELECT Id, Name, Approval_Status__c, Campaign_Status__c, Constituent_Role__c,
                   Currency__c, Fundraising_Goal__c, Cover_Image__c, Is_Active__c, Is_Published__c,
                   Start_Date__c, End_Date__c
            FROM Ken_Fundraise__c
            WHERE Name = :name LIMIT 1
        ];
    }

    /**
     * @description Builds a fully populated FundraiseRequest DTO.
     */
    private static KenFundraiseController.FundraiseRequest buildRequest(String name) {
        KenFundraiseController.FundraiseRequest req = new KenFundraiseController.FundraiseRequest();
        req.name             = name;
        req.categoryId       = [SELECT Id FROM Ken_Fundraise_Category__c WHERE Name = 'Education Fund' LIMIT 1].Id;
        req.description      = 'Test campaign description';
        req.currencyCode     = 'USD';
        req.fundraisingGoal  = 10000;
        req.collectionMethod = 'External Link';
        req.externalLink     = 'https://donate.example.com';
        req.startDate        = String.valueOf(Date.today());
        req.endDate          = String.valueOf(Date.today().addDays(30));
        req.coverImageUrl    = 'https://example.com/cover.png';
        return req;
    }

    @TestSetup
    static void setupData() {
        insert new Alumni_Trigger_Settings__c(Fundraise_Trigger__c = false);

        Id paRtId = getPersonAccountRtId();
        Account ownerAcc = new Account(
            FirstName   = 'Fund',
            LastName    = 'Owner',
            PersonEmail = 'fund.owner@test.example.com'
        );
        if (paRtId != null) {
            ownerAcc.RecordTypeId = paRtId;
        }
        insert ownerAcc;
        Id ownerRoleId = createAlumniRole(ownerAcc.Id);

        Account otherAcc = new Account(
            FirstName   = 'Fund',
            LastName    = 'Other',
            PersonEmail = 'fund.other@test.example.com'
        );
        if (paRtId != null) {
            otherAcc.RecordTypeId = paRtId;
        }
        insert otherAcc;
        createAlumniRole(otherAcc.Id);

        insert new List<Ken_Fundraise_Category__c>{
            new Ken_Fundraise_Category__c(Name = 'Education Fund', Active__c = true, Description__c = 'Active category'),
            new Ken_Fundraise_Category__c(Name = 'Retired Fund', Active__c = false, Description__c = 'Inactive category')
        };

        insert new List<Ken_Fundraise__c>{
            new Ken_Fundraise__c(
                Name                = 'Draft Campaign',
                Campaign_Status__c  = 'Upcoming',
                Fundraising_Goal__c = 5000,
                Constituent_Role__c = ownerRoleId
            ),
            new Ken_Fundraise__c(
                Name                = 'Live Campaign',
                Approval_Status__c  = 'Approved',
                Campaign_Status__c  = 'Ongoing',
                Is_Active__c        = true,
                Is_Published__c     = true,
                Currency__c         = 'USD',
                Fundraising_Goal__c = 20000,
                Start_Date__c       = Date.today().addDays(-5),
                End_Date__c         = Date.today().addDays(30),
                Constituent_Role__c = ownerRoleId
            )
        };
    }

    @IsTest
    static void getFundraiseCategoriesReturnsActiveOnly() {
        Test.startTest();
        List<KenFundraiseController.CategoryOption> options = KenFundraiseController.getFundraiseCategories();
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (KenFundraiseController.CategoryOption opt : options) {
            names.add(opt.name);
        }
        System.assertEquals(true, names.contains('Education Fund'), 'Active category should be returned');
        System.assertEquals(false, names.contains('Retired Fund'), 'Inactive category should be excluded');
    }

    @IsTest
    static void createCampaignHappyPathStampsRoleAndDefaults() {
        Account ownerAcc = getAccountByLastName('Owner');
        Id ownerRoleId = getRoleIdFor(ownerAcc.Id);
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = ownerRoleId;

        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Test Segment');
        insert seg;

        KenFundraiseController.FundraiseRequest req = buildRequest('  Scholarship Drive  ');
        req.currencyCode = null;
        req.segmentationIds = new List<String>{ seg.Id, '' };

        Test.startTest();
        Id campaignId = KenFundraiseController.createCampaign(req, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;
        System.assertNotEquals(null, campaignId, 'createCampaign should return the new campaign Id');

        Ken_Fundraise__c created = [
            SELECT Name, Constituent_Role__c, Approval_Status__c, Campaign_Status__c,
                   Currency__c, Is_Active__c, Is_Published__c, Cover_Image__c,
                   Start_Date__c, End_Date__c, Fundraising_Goal__c
            FROM Ken_Fundraise__c WHERE Id = :campaignId
        ];
        System.assertEquals('Scholarship Drive', created.Name, 'Campaign name should be trimmed');
        System.assertEquals(ownerRoleId, created.Constituent_Role__c, 'Constituent role should be stamped');
        System.assertEquals(null, created.Approval_Status__c, 'New campaign should have no approval status');
        System.assertEquals('Upcoming', created.Campaign_Status__c, 'New campaign should be Upcoming');
        System.assertEquals('INR', created.Currency__c, 'Blank currency should default to INR');
        System.assertEquals(false, created.Is_Published__c, 'New campaign should not be published');
        System.assertEquals('https://example.com/cover.png', created.Cover_Image__c, 'Plain cover URL should be stored as-is');
        System.assertEquals(Date.today(), created.Start_Date__c, 'Start date should be parsed');
        System.assertEquals(Date.today().addDays(30), created.End_Date__c, 'End date should be parsed');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Ken_Fundraise_Segmentation__c WHERE Fundraise__c = :campaignId],
            'One segmentation link should be created and the blank id skipped'
        );
    }

    @IsTest
    static void createCampaignUploadsDataUriCover() {
        Account ownerAcc = getAccountByLastName('Owner');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        KenFundraiseController.FundraiseRequest req = buildRequest('Cover Upload Drive');
        req.coverImageUrl = 'data:image/png;base64,aGVsbG8=';

        Test.startTest();
        Id campaignId = KenFundraiseController.createCampaign(req, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;

        Ken_Fundraise__c created = [SELECT Cover_Image__c FROM Ken_Fundraise__c WHERE Id = :campaignId];
        System.assertNotEquals(null, created.Cover_Image__c, 'Cover image URL should be populated from the upload');
        System.assertEquals(
            true,
            created.Cover_Image__c.contains('/sfc/servlet.shepherd/version/download/'),
            'Cover image should point to the uploaded ContentVersion'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :campaignId],
            'Uploaded cover should be linked to the campaign'
        );
    }

    @IsTest
    static void createCampaignNullRequestThrows() {
        Account ownerAcc = getAccountByLastName('Owner');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        try {
            Test.startTest();
            KenFundraiseController.createCampaign(null, null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for null request');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenFundraiseController.testCurrentAccountId = null;
            KenFundraiseController.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void createCampaignBlankNameThrows() {
        Account ownerAcc = getAccountByLastName('Owner');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        KenFundraiseController.FundraiseRequest req = new KenFundraiseController.FundraiseRequest();
        req.name = '   ';

        try {
            Test.startTest();
            KenFundraiseController.createCampaign(req, null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for blank campaign name');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenFundraiseController.testCurrentAccountId = null;
            KenFundraiseController.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void updateCampaignHappyPath() {
        Account ownerAcc = getAccountByLastName('Owner');
        Ken_Fundraise__c draft = getCampaignByName('Draft Campaign');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        KenFundraiseController.FundraiseRequest req = buildRequest('Draft Campaign Updated');
        req.fundraisingGoal = 7500;
        req.coverImageUrl = 'https://example.com/updated.png';

        Test.startTest();
        KenFundraiseController.updateCampaign(draft.Id, req, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;

        Ken_Fundraise__c updated = [
            SELECT Name, Fundraising_Goal__c, Currency__c, Cover_Image__c
            FROM Ken_Fundraise__c WHERE Id = :draft.Id
        ];
        System.assertEquals('Draft Campaign Updated', updated.Name, 'Campaign name should be updated');
        System.assertEquals(7500, updated.Fundraising_Goal__c, 'Fundraising goal should be updated');
        System.assertEquals('USD', updated.Currency__c, 'Currency should be updated');
        System.assertEquals('https://example.com/updated.png', updated.Cover_Image__c, 'Cover URL should be replaced');
    }

    @IsTest
    static void updateCampaignValidatesInput() {
        Ken_Fundraise__c draft = getCampaignByName('Draft Campaign');
        Boolean nullIdThrew = false;
        Boolean nullReqThrew = false;

        Test.startTest();
        try {
            KenFundraiseController.updateCampaign(null, buildRequest('x'), null);
        } catch (AuraHandledException ex) {
            nullIdThrew = true;
        }
        try {
            KenFundraiseController.updateCampaign(draft.Id, null, null);
        } catch (AuraHandledException ex) {
            nullReqThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, nullIdThrew, 'Null campaign Id should be rejected');
        System.assertEquals(true, nullReqThrew, 'Null request should be rejected');
    }

    @IsTest
    static void updateCampaignOwnershipDeniedThrows() {
        Account otherAcc = getAccountByLastName('Other');
        Ken_Fundraise__c draft = getCampaignByName('Draft Campaign');
        KenFundraiseController.testCurrentAccountId = otherAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(otherAcc.Id);

        try {
            Test.startTest();
            KenFundraiseController.updateCampaign(draft.Id, buildRequest('Hijacked'), null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for non-owner edit');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenFundraiseController.testCurrentAccountId = null;
            KenFundraiseController.testCurrentRoleId = null;
        }
        System.assertEquals('Draft Campaign', getCampaignByName('Draft Campaign').Name, 'Campaign must remain unchanged');
    }

    @IsTest
    static void finalizeAndSubmitSetsInReviewAndResubmits() {
        Account ownerAcc = getAccountByLastName('Owner');
        Ken_Fundraise__c draft = getCampaignByName('Draft Campaign');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        KenFundraiseController.FundraiseRequest req = buildRequest('Draft Campaign');
        req.coverImageUrl = null;

        Test.startTest();
        KenFundraiseController.finalizeAndSubmitCampaign(draft.Id, req, null);
        System.assertEquals(
            'In Review',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :draft.Id].Approval_Status__c,
            'Finalizing should move the campaign into In Review'
        );
        KenFundraiseController.finalizeAndSubmitCampaign(draft.Id, req, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;

        Ken_Fundraise__c resubmitted = [
            SELECT Approval_Status__c, Cover_Image__c FROM Ken_Fundraise__c WHERE Id = :draft.Id
        ];
        System.assertEquals('In Review', resubmitted.Approval_Status__c, 'Resubmission should keep the campaign In Review');
        System.assertEquals(null, resubmitted.Cover_Image__c, 'Null cover URL should clear the cover image');
    }

    @IsTest
    static void getMyCampaignsReturnsOwnedRows() {
        Account ownerAcc = getAccountByLastName('Owner');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Test.startTest();
        List<KenFundraiseController.CampaignDTO> rows = KenFundraiseController.getMyCampaigns(null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;

        System.assertEquals(2, rows.size(), 'Owner should see both setup campaigns');
        Map<String, KenFundraiseController.CampaignDTO> byName = new Map<String, KenFundraiseController.CampaignDTO>();
        for (KenFundraiseController.CampaignDTO dto : rows) {
            byName.put(dto.name, dto);
        }
        System.assertEquals(true, byName.containsKey('Draft Campaign'), 'Draft campaign should be listed');
        System.assertEquals(true, byName.containsKey('Live Campaign'), 'Live campaign should be listed');
        System.assertEquals('INR', byName.get('Draft Campaign').currencyCode, 'Blank currency should map to INR');
        System.assertEquals('USD', byName.get('Live Campaign').currencyCode, 'Stored currency should be returned');
    }

    @IsTest
    static void getMyCampaignsResolvesRoleFromAccount() {
        Account ownerAcc = getAccountByLastName('Owner');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = null;

        Test.startTest();
        List<KenFundraiseController.CampaignDTO> rows = KenFundraiseController.getMyCampaigns(null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        System.assertEquals(2, rows.size(), 'Role should resolve from the current account when no role id is passed');
    }

    @IsTest
    static void getMyCampaignsEmptyForInternalUserWithoutRole() {
        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;

        Test.startTest();
        List<KenFundraiseController.CampaignDTO> rows = KenFundraiseController.getMyCampaigns(null);
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Internal user without a role should get an empty list, not an error');
        System.assertEquals(0, rows.size(), 'No campaigns should match a null role');
    }

    @IsTest
    static void getPublishedCampaignsReturnsApprovedOnly() {
        Test.startTest();
        List<KenFundraiseController.CampaignDTO> rows = KenFundraiseController.getPublishedCampaigns();
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (KenFundraiseController.CampaignDTO dto : rows) {
            names.add(dto.name);
            System.assertEquals('Approved', dto.approvalStatus, 'Published rows should always be Approved');
        }
        System.assertEquals(true, names.contains('Live Campaign'), 'Approved campaign should be published');
        System.assertEquals(false, names.contains('Draft Campaign'), 'Unapproved campaign must not be published');
    }

    @IsTest
    static void getCampaignByIdReflectsOwnership() {
        Account ownerAcc = getAccountByLastName('Owner');
        Account otherAcc = getAccountByLastName('Other');
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');

        Test.startTest();
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        KenFundraiseController.CampaignDTO ownerView = KenFundraiseController.getCampaignById(live.Id, null);

        KenFundraiseController.testCurrentAccountId = otherAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(otherAcc.Id);
        KenFundraiseController.CampaignDTO otherView = KenFundraiseController.getCampaignById(live.Id, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;

        System.assertEquals('Live Campaign', ownerView.name, 'Campaign name should be returned');
        System.assertEquals(true, ownerView.isOwner, 'Owner should be flagged as owner');
        System.assertEquals(false, otherView.isOwner, 'Non-owner must not be flagged as owner');
        System.assertNotEquals(null, ownerView.isAdmin, 'Admin flag should always be populated');
    }

    @IsTest
    static void deleteCampaignMarksDeletionRequested() {
        Account ownerAcc = getAccountByLastName('Owner');
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Test.startTest();
        KenFundraiseController.deleteCampaign(live.Id, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;
        System.assertEquals(
            'Deletion Requested',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :live.Id].Approval_Status__c,
            'Approved campaign deletion should move it to Deletion Requested'
        );
    }

    @IsTest
    static void deleteCampaignRequiresApprovedStatus() {
        Account ownerAcc = getAccountByLastName('Owner');
        Ken_Fundraise__c draft = getCampaignByName('Draft Campaign');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        try {
            Test.startTest();
            KenFundraiseController.deleteCampaign(draft.Id, null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException when deleting an unapproved campaign');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenFundraiseController.testCurrentAccountId = null;
            KenFundraiseController.testCurrentRoleId = null;
        }
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Ken_Fundraise__c WHERE Id = :draft.Id],
            'Campaign must remain after the rejected delete attempt'
        );
    }

    @IsTest
    static void deleteCampaignNotOwnerThrows() {
        Account otherAcc = getAccountByLastName('Other');
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');
        KenFundraiseController.testCurrentAccountId = otherAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(otherAcc.Id);

        try {
            Test.startTest();
            KenFundraiseController.deleteCampaign(live.Id, null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for non-owner deletion request');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenFundraiseController.testCurrentAccountId = null;
            KenFundraiseController.testCurrentRoleId = null;
        }
        System.assertEquals(
            'Approved',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :live.Id].Approval_Status__c,
            'Campaign approval status must remain Approved'
        );
    }

    @IsTest
    static void closeCampaignCompletesOngoing() {
        Account ownerAcc = getAccountByLastName('Owner');
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);

        Test.startTest();
        KenFundraiseController.closeCampaign(live.Id, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;
        System.assertEquals(
            'Completed',
            [SELECT Campaign_Status__c FROM Ken_Fundraise__c WHERE Id = :live.Id].Campaign_Status__c,
            'Closing an ongoing campaign should mark it Completed'
        );
    }

    @IsTest
    static void closeCampaignNotOwnerThrows() {
        Account otherAcc = getAccountByLastName('Other');
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');
        KenFundraiseController.testCurrentAccountId = otherAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(otherAcc.Id);

        try {
            Test.startTest();
            KenFundraiseController.closeCampaign(live.Id, null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for non-owner close');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenFundraiseController.testCurrentAccountId = null;
            KenFundraiseController.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void closeCampaignRejectsNotOngoing() {
        Account ownerAcc = getAccountByLastName('Owner');
        Id ownerRoleId = getRoleIdFor(ownerAcc.Id);
        Ken_Fundraise__c future = new Ken_Fundraise__c(
            Name                = 'Future Campaign',
            Approval_Status__c  = 'Approved',
            Campaign_Status__c  = 'Upcoming',
            Start_Date__c       = Date.today().addDays(5),
            End_Date__c         = Date.today().addDays(40),
            Constituent_Role__c = ownerRoleId
        );
        insert future;

        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = ownerRoleId;
        try {
            Test.startTest();
            KenFundraiseController.closeCampaign(future.Id, null);
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for a campaign that has not started');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        } finally {
            KenFundraiseController.testCurrentAccountId = null;
            KenFundraiseController.testCurrentRoleId = null;
        }
    }

    @IsTest
    static void approveCampaignFallbackApproves() {
        Account ownerAcc = getAccountByLastName('Owner');
        Ken_Fundraise__c draft = getCampaignByName('Draft Campaign');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        KenFundraiseController.FundraiseRequest req = buildRequest('Draft Campaign');
        KenFundraiseController.finalizeAndSubmitCampaign(draft.Id, req, null);
        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;

        Test.startTest();
        KenFundraiseController.approveCampaign(draft.Id, null);
        Test.stopTest();

        Ken_Fundraise__c approved = [
            SELECT Approval_Status__c, Is_Active__c, Is_Published__c
            FROM Ken_Fundraise__c WHERE Id = :draft.Id
        ];
        System.assertEquals('Approved', approved.Approval_Status__c, 'Campaign should be Approved via the direct fallback');
        System.assertEquals(true, approved.Is_Active__c, 'Approved campaign should become active');
        System.assertEquals(true, approved.Is_Published__c, 'Approved campaign should become published');
    }

    @IsTest
    static void rejectCampaignFallbackRejects() {
        Account ownerAcc = getAccountByLastName('Owner');
        Ken_Fundraise__c draft = getCampaignByName('Draft Campaign');
        KenFundraiseController.testCurrentAccountId = ownerAcc.Id;
        KenFundraiseController.testCurrentRoleId = getRoleIdFor(ownerAcc.Id);
        KenFundraiseController.finalizeAndSubmitCampaign(draft.Id, buildRequest('Draft Campaign'), null);

        Test.startTest();
        KenFundraiseController.rejectCampaign(draft.Id, 'Insufficient detail', null);
        KenFundraiseController.CampaignDTO dto = KenFundraiseController.getCampaignById(draft.Id, null);
        Test.stopTest();

        KenFundraiseController.testCurrentAccountId = null;
        KenFundraiseController.testCurrentRoleId = null;
        System.assertEquals(
            'Rejected',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :draft.Id].Approval_Status__c,
            'Campaign should be Rejected via the direct fallback'
        );
        System.assertEquals('Rejected', dto.approvalStatus, 'DTO should reflect the rejected status');
        System.assertEquals(null, dto.rejectionReason, 'No approval step exists, so no rejection comment is available');
    }

    @IsTest
    static void approveDeletionRemovesCampaign() {
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');
        live.Approval_Status__c = 'Deletion Requested';
        update live;

        Test.startTest();
        KenFundraiseController.approveDeletion(live.Id, null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Ken_Fundraise__c WHERE Id = :live.Id],
            'Approving deletion should hard-delete the campaign'
        );
    }

    @IsTest
    static void rejectDeletionRestoresApproved() {
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');
        live.Approval_Status__c = 'Deletion Requested';
        update live;

        Test.startTest();
        KenFundraiseController.rejectDeletion(live.Id, null);
        Test.stopTest();

        System.assertEquals(
            'Approved',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :live.Id].Approval_Status__c,
            'Rejecting deletion should restore the Approved status'
        );
    }

    @IsTest
    static void getAdminFundraiseListReturnsAllCampaigns() {
        Test.startTest();
        List<KenFundraiseController.CampaignDTO> rows = KenFundraiseController.getAdminFundraiseList(null);
        Test.stopTest();

        Set<String> names = new Set<String>();
        for (KenFundraiseController.CampaignDTO dto : rows) {
            names.add(dto.name);
        }
        System.assertEquals(true, rows.size() >= 2, 'Admin list should include every campaign');
        System.assertEquals(true, names.contains('Draft Campaign'), 'Admin list should include unapproved campaigns');
        System.assertEquals(true, names.contains('Live Campaign'), 'Admin list should include approved campaigns');
    }

    @IsTest
    static void getDeletionRequestsListsPending() {
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');
        live.Approval_Status__c = 'Deletion Requested';
        update live;

        Test.startTest();
        List<KenFundraiseController.CampaignDTO> rows = KenFundraiseController.getDeletionRequests(null);
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Exactly one deletion request should be listed');
        System.assertEquals('Live Campaign', rows[0].name, 'The deletion-requested campaign should be listed');
        System.assertEquals('Deletion Requested', rows[0].approvalStatus, 'Row should carry the Deletion Requested status');
    }

    @IsTest
    static void getFundraiseStatusReturnsNameAndStatus() {
        Ken_Fundraise__c live = getCampaignByName('Live Campaign');

        Test.startTest();
        Map<String, String> status = KenFundraiseController.getFundraiseStatus(live.Id);
        Test.stopTest();

        System.assertEquals('Live Campaign', status.get('name'), 'Status map should carry the campaign name');
        System.assertEquals('Approved', status.get('approvalStatus'), 'Status map should carry the approval status');
    }

    @IsTest
    static void uploadCategoryImageStoresFileUrl() {
        Ken_Fundraise_Category__c category = [
            SELECT Id FROM Ken_Fundraise_Category__c WHERE Name = 'Education Fund' LIMIT 1
        ];

        Test.startTest();
        String imageUrl = KenFundraiseController.uploadCategoryImage(category.Id, 'aGVsbG8=');
        Test.stopTest();

        System.assertNotEquals(null, imageUrl, 'Upload should return the file URL');
        System.assertEquals(
            true,
            imageUrl.contains('/sfc/servlet.shepherd/version/download/'),
            'Returned URL should point to the uploaded ContentVersion'
        );
        System.assertEquals(
            imageUrl,
            [SELECT Image__c FROM Ken_Fundraise_Category__c WHERE Id = :category.Id].Image__c,
            'Category image field should store the returned URL'
        );
    }

    @IsTest
    static void uploadCategoryImageValidatesInput() {
        Ken_Fundraise_Category__c category = [
            SELECT Id FROM Ken_Fundraise_Category__c WHERE Name = 'Education Fund' LIMIT 1
        ];
        Boolean nullIdThrew = false;
        Boolean blankDataThrew = false;

        Test.startTest();
        try {
            KenFundraiseController.uploadCategoryImage(null, 'aGVsbG8=');
        } catch (AuraHandledException ex) {
            nullIdThrew = true;
        }
        try {
            KenFundraiseController.uploadCategoryImage(category.Id, '');
        } catch (AuraHandledException ex) {
            blankDataThrew = true;
        }
        Test.stopTest();

        System.assertEquals(true, nullIdThrew, 'Null category Id should be rejected');
        System.assertEquals(true, blankDataThrew, 'Blank image data should be rejected');
    }
}