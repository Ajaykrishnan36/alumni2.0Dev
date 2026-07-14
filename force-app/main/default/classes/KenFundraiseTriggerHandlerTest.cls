@IsTest
private class KenFundraiseTriggerHandlerTest {

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
     * @description Fetches the setup owner person account.
     */
    private static Account getOwnerAccount() {
        return [SELECT Id FROM Account WHERE LastName = 'TrgOwner' LIMIT 1];
    }

    /**
     * @description Fetches the setup owner's Alumni role.
     */
    private static Id getOwnerRoleId() {
        return [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :getOwnerAccount().Id AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC LIMIT 1
        ].Id;
    }

    /**
     * @description Builds an unsaved campaign in the given approval status.
     */
    private static Ken_Fundraise__c buildCampaign(String name, String approvalStatus, Id roleId) {
        return new Ken_Fundraise__c(
            Name                = name,
            Approval_Status__c  = approvalStatus,
            Campaign_Status__c  = 'Upcoming',
            Fundraising_Goal__c = 1000,
            Constituent_Role__c = roleId
        );
    }

    @TestSetup
    static void setupData() {
        insert new Alumni_Trigger_Settings__c(Fundraise_Trigger__c = false);

        Id paRtId = getPersonAccountRtId();
        Account ownerAcc = new Account(
            FirstName   = 'Fundraise',
            LastName    = 'TrgOwner',
            PersonEmail = 'fundraise.trgowner@test.example.com'
        );
        if (paRtId != null) {
            ownerAcc.RecordTypeId = paRtId;
        }
        insert ownerAcc;
        createAlumniRole(ownerAcc.Id);
    }

    @IsTest
    static void insertInReviewRunsSubmissionPath() {
        Id roleId = getOwnerRoleId();
        Integer runsBefore = KenTriggerHandler.runCount;

        Test.startTest();
        Ken_Fundraise__c campaign = buildCampaign('Trg Submit Campaign', 'In Review', roleId);
        insert campaign;
        campaign.Description__c = 'Edited without a status change';
        update campaign;
        Test.stopTest();

        System.assertEquals(true, KenTriggerHandler.runCount > runsBefore, 'Handler should run when the kill-switch is off');
        System.assertEquals(
            'In Review',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :campaign.Id].Approval_Status__c,
            'Campaign should stay In Review after the submission path runs'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :campaign.Id],
            'KenApprovalProcessHelper bypasses Approval.process in tests, so no ProcessInstance is expected'
        );
    }

    @IsTest
    static void insertAndDecisionWithoutRoleAreIgnored() {
        Ken_Fundraise__c campaign = buildCampaign('Trg No Role Campaign', 'In Review', null);

        Test.startTest();
        insert campaign;
        campaign.Approval_Status__c = 'Approved';
        update campaign;
        Test.stopTest();

        System.assertEquals(
            'Approved',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :campaign.Id].Approval_Status__c,
            'Role-less campaign should update without errors'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Ken_Notification__c],
            'No notification should be created when the campaign has no constituent role'
        );
    }

    @IsTest
    static void approvedTransitionNotifiesCreator() {
        Account ownerAcc = getOwnerAccount();
        Ken_Fundraise__c campaign = buildCampaign('Trg Approved Campaign', 'In Review', getOwnerRoleId());
        insert campaign;

        Test.startTest();
        campaign.Approval_Status__c = 'Approved';
        update campaign;
        Test.stopTest();

        System.assertEquals(
            'Approved',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :campaign.Id].Approval_Status__c,
            'Campaign should be Approved after the transition'
        );

        Ken_Notification_Template__mdt tpl = Ken_Notification_Template__mdt.getInstance('Fundraise_Approved');
        List<Ken_Notification__c> notifs = [
            SELECT Id, Title__c, Category__c FROM Ken_Notification__c WHERE Recipient__c = :ownerAcc.Id
        ];
        if (tpl != null && tpl.Active__c == true) {
            System.assertEquals(1, notifs.size(), 'Creator should receive one approval notification');
            System.assertEquals(
                true,
                notifs[0].Title__c.contains('Trg Approved Campaign'),
                'Notification title should merge the campaign name'
            );
            System.assertEquals(tpl.Category__c, notifs[0].Category__c, 'Notification should carry the template category');
        } else {
            System.assertEquals(0, notifs.size(), 'Without an active template the handler tolerates and creates nothing');
        }
    }

    @IsTest
    static void rejectedTransitionNotifiesCreator() {
        Account ownerAcc = getOwnerAccount();
        Ken_Fundraise__c campaign = buildCampaign('Trg Rejected Campaign', 'In Review', getOwnerRoleId());
        insert campaign;

        Test.startTest();
        campaign.Approval_Status__c = 'Rejected';
        update campaign;
        Test.stopTest();

        System.assertEquals(
            'Rejected',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :campaign.Id].Approval_Status__c,
            'Campaign should be Rejected after the transition'
        );

        Ken_Notification_Template__mdt tpl = Ken_Notification_Template__mdt.getInstance('Fundraise_Rejected');
        List<Ken_Notification__c> notifs = [
            SELECT Id, Category__c FROM Ken_Notification__c WHERE Recipient__c = :ownerAcc.Id
        ];
        if (tpl != null && tpl.Active__c == true) {
            System.assertEquals(1, notifs.size(), 'Creator should receive one rejection notification');
            System.assertEquals(tpl.Category__c, notifs[0].Category__c, 'Notification should carry the template category');
        } else {
            System.assertEquals(0, notifs.size(), 'Without an active template the handler tolerates and creates nothing');
        }
    }

    @IsTest
    static void unchangedStatusUpdateDoesNotNotify() {
        Ken_Fundraise__c campaign = buildCampaign('Trg Quiet Campaign', 'Approved', getOwnerRoleId());
        insert campaign;

        Test.startTest();
        campaign.Fundraising_Goal__c = 2500;
        update campaign;
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Ken_Notification__c],
            'An update without an approval-status change must not notify anyone'
        );
    }

    @IsTest
    static void killSwitchSkipsHandler() {
        Alumni_Trigger_Settings__c settings = [
            SELECT Id, Fundraise_Trigger__c FROM Alumni_Trigger_Settings__c LIMIT 1
        ];
        settings.Fundraise_Trigger__c = true;
        update settings;

        Id roleId = getOwnerRoleId();
        Integer runsBefore = KenTriggerHandler.runCount;

        Test.startTest();
        Ken_Fundraise__c campaign = buildCampaign('Trg Bypassed Campaign', 'In Review', roleId);
        insert campaign;
        Test.stopTest();

        System.assertEquals(runsBefore, KenTriggerHandler.runCount, 'Handler must not run when the kill-switch is on');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :campaign.Id],
            'No approval submission should happen when the trigger is bypassed'
        );
        System.assertEquals(
            'In Review',
            [SELECT Approval_Status__c FROM Ken_Fundraise__c WHERE Id = :campaign.Id].Approval_Status__c,
            'Campaign should still be inserted with its requested status'
        );
    }
}