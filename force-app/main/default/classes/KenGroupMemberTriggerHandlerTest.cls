@isTest
private class KenGroupMemberTriggerHandlerTest {

    @testSetup
    static void setupData() {
        Id paRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Alumni_Person_Account' LIMIT 1
        ].Id;
        List<Account> people = new List<Account>{
            new Account(RecordTypeId = paRtId, FirstName = 'Admin',  LastName = 'Test', PersonEmail = 'gmadmin@ttest.example'),
            new Account(RecordTypeId = paRtId, FirstName = 'Member', LastName = 'Test', PersonEmail = 'gmmember@ttest.example'),
            new Account(RecordTypeId = paRtId, FirstName = 'Inviter',LastName = 'Test', PersonEmail = 'gminviter@ttest.example')
        };
        insert people;

        Account admin = [SELECT Id FROM Account WHERE FirstName = 'Admin' LIMIT 1];
        insert new Ken_Group__c(
            Name = 'GMTest Group',
            Created_By__c = admin.Id,
            Status__c = 'Approved',
            Group_Type__c = 'Public'
        );
    }

    private static Ken_Group__c getGroup() {
        return [SELECT Id, Name, Created_By__c FROM Ken_Group__c WHERE Name = 'GMTest Group' LIMIT 1];
    }

    @isTest
    static void insert_bypass_suppresses_notification() {
        Account admin  = [SELECT Id FROM Account WHERE FirstName = 'Admin'  LIMIT 1];
        Account member = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Ken_Group__c grp = getGroup();
        insert new Alumni_Trigger_Settings__c(Group_Member_Trigger__c = true);
        Test.startTest();
        insert new Ken_Group_Member__c(
            Group__c  = grp.Id,
            Member__c = member.Id,
            Status__c = 'Pending'
        );
        Test.stopTest();
        System.assertEquals(0,
            [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :admin.Id AND Category__c = 'Group'],
            'Trigger bypass flag should suppress the admin notification.');
    }

    @isTest
    static void insert_pending_notifies_admin() {
        Account admin   = [SELECT Id FROM Account WHERE FirstName = 'Admin'  LIMIT 1];
        Account member  = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Ken_Group__c grp = getGroup();

        Test.startTest();
        insert new Ken_Group_Member__c(
            Group__c  = grp.Id,
            Member__c = member.Id,
            Status__c = 'Pending'
        );
        Test.stopTest();

        Integer notifs = [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :admin.Id AND Category__c = 'Group'];
        System.assertEquals(1, notifs, 'Admin should get one join-request-received notification');
    }

    @isTest
    static void insert_invited_notifies_member() {
        Account member  = [SELECT Id FROM Account WHERE FirstName = 'Member'  LIMIT 1];
        Account inviter = [SELECT Id FROM Account WHERE FirstName = 'Inviter' LIMIT 1];
        Ken_Group__c grp = getGroup();

        Test.startTest();
        insert new Ken_Group_Member__c(
            Group__c     = grp.Id,
            Member__c    = member.Id,
            Status__c    = 'Invited',
            Invited_By__c = inviter.Id
        );
        Test.stopTest();

        Integer notifs = [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :member.Id AND Category__c = 'Group'];
        System.assertEquals(1, notifs, 'Invitee should get one invite-received notification');
    }

    @isTest
    static void pending_to_approved_notifies_member() {
        Account admin  = [SELECT Id FROM Account WHERE FirstName = 'Admin'  LIMIT 1];
        Account member = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Ken_Group__c grp = getGroup();

        Ken_Group_Member__c gm = new Ken_Group_Member__c(
            Group__c  = grp.Id,
            Member__c = member.Id,
            Status__c = 'Pending'
        );
        insert gm;
        delete [SELECT Id FROM Ken_Notification__c];

        Test.startTest();
        gm.Status__c = 'Approved';
        gm.Approved_Rejected_By__c = UserInfo.getUserId();
        update gm;
        Test.stopTest();

        Integer notifs = [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :member.Id];
        System.assertEquals(1, notifs, 'Member should get one join-approved notification');
    }

    @isTest
    static void pending_to_rejected_notifies_member() {
        Account admin  = [SELECT Id FROM Account WHERE FirstName = 'Admin'  LIMIT 1];
        Account member = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Ken_Group__c grp = getGroup();

        Ken_Group_Member__c gm = new Ken_Group_Member__c(
            Group__c  = grp.Id,
            Member__c = member.Id,
            Status__c = 'Pending'
        );
        insert gm;
        delete [SELECT Id FROM Ken_Notification__c];

        Test.startTest();
        gm.Status__c = 'Rejected';
        gm.Approved_Rejected_By__c = UserInfo.getUserId();
        update gm;
        Test.stopTest();

        Integer notifs = [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :member.Id];
        System.assertEquals(1, notifs, 'Member should get one join-rejected notification');
    }

    @isTest
    static void invited_to_accepted_notifies_admin() {
        Account admin   = [SELECT Id FROM Account WHERE FirstName = 'Admin'  LIMIT 1];
        Account member  = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Account inviter = [SELECT Id FROM Account WHERE FirstName = 'Inviter'LIMIT 1];
        Ken_Group__c grp = getGroup();

        Ken_Group_Member__c gm = new Ken_Group_Member__c(
            Group__c     = grp.Id,
            Member__c    = member.Id,
            Status__c    = 'Invited',
            Invited_By__c = inviter.Id
        );
        insert gm;
        delete [SELECT Id FROM Ken_Notification__c];

        Test.startTest();
        gm.Status__c = 'Invite Accepted';
        update gm;
        Test.stopTest();

        Integer notifs = [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :admin.Id];
        System.assertEquals(1, notifs, 'Admin should get one invite-accepted notification');
    }

    @isTest
    static void invited_to_declined_notifies_admin() {
        Account admin   = [SELECT Id FROM Account WHERE FirstName = 'Admin'  LIMIT 1];
        Account member  = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Account inviter = [SELECT Id FROM Account WHERE FirstName = 'Inviter'LIMIT 1];
        Ken_Group__c grp = getGroup();

        Ken_Group_Member__c gm = new Ken_Group_Member__c(
            Group__c     = grp.Id,
            Member__c    = member.Id,
            Status__c    = 'Invited',
            Invited_By__c = inviter.Id
        );
        insert gm;
        delete [SELECT Id FROM Ken_Notification__c];

        Test.startTest();
        gm.Status__c = 'Invite Declined';
        update gm;
        Test.stopTest();

        Integer notifs = [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :admin.Id];
        System.assertEquals(1, notifs, 'Admin should get one invite-declined notification');
    }

    // ── Member_Count__c roll-up behaviour ──────────────────────────────────────

    private static Decimal countFor(Id groupId) {
        return [SELECT Member_Count__c FROM Ken_Group__c WHERE Id = :groupId LIMIT 1].Member_Count__c;
    }

    @isTest
    static void member_count_includes_approved_and_invite_accepted_excludes_creator() {
        Account admin   = [SELECT Id FROM Account WHERE FirstName = 'Admin'  LIMIT 1];
        Account member  = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Account inviter = [SELECT Id FROM Account WHERE FirstName = 'Inviter'LIMIT 1];
        Ken_Group__c grp = getGroup();

        Test.startTest();
        insert new List<Ken_Group_Member__c>{
            new Ken_Group_Member__c(Group__c = grp.Id, Member__c = member.Id,  Status__c = 'Approved'),
            new Ken_Group_Member__c(Group__c = grp.Id, Member__c = inviter.Id, Status__c = 'Invite Accepted'),
            // The creator's own membership must NOT be counted.
            new Ken_Group_Member__c(Group__c = grp.Id, Member__c = admin.Id,   Status__c = 'Approved')
        };
        Test.stopTest();

        System.assertEquals(2, countFor(grp.Id),
            'Count should include Approved + Invite Accepted but exclude the group creator');
    }

    @isTest
    static void member_count_ignores_pending_and_invited() {
        Account member  = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Account inviter = [SELECT Id FROM Account WHERE FirstName = 'Inviter'LIMIT 1];
        Ken_Group__c grp = getGroup();

        Test.startTest();
        insert new List<Ken_Group_Member__c>{
            new Ken_Group_Member__c(Group__c = grp.Id, Member__c = member.Id,  Status__c = 'Pending'),
            new Ken_Group_Member__c(Group__c = grp.Id, Member__c = inviter.Id, Status__c = 'Invited')
        };
        Test.stopTest();

        System.assertEquals(0, countFor(grp.Id), 'Pending and Invited members should not be counted');
    }

    @isTest
    static void member_count_updates_when_status_changes_to_approved() {
        Account member = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Ken_Group__c grp = getGroup();
        Ken_Group_Member__c gm = new Ken_Group_Member__c(
            Group__c = grp.Id, Member__c = member.Id, Status__c = 'Pending'
        );
        insert gm;
        System.assertEquals(0, countFor(grp.Id), 'Pending should not be counted yet');

        Test.startTest();
        gm.Status__c = 'Approved';
        gm.Approved_Rejected_By__c = UserInfo.getUserId();
        update gm;
        Test.stopTest();

        System.assertEquals(1, countFor(grp.Id), 'Approving a request should increment the count');
    }

    @isTest
    static void member_count_recalculates_on_delete_and_undelete() {
        Account member  = [SELECT Id FROM Account WHERE FirstName = 'Member' LIMIT 1];
        Account inviter = [SELECT Id FROM Account WHERE FirstName = 'Inviter'LIMIT 1];
        Ken_Group__c grp = getGroup();

        Ken_Group_Member__c gm1 = new Ken_Group_Member__c(Group__c = grp.Id, Member__c = member.Id,  Status__c = 'Approved');
        Ken_Group_Member__c gm2 = new Ken_Group_Member__c(Group__c = grp.Id, Member__c = inviter.Id, Status__c = 'Approved');
        insert new List<Ken_Group_Member__c>{ gm1, gm2 };
        System.assertEquals(2, countFor(grp.Id), 'Both approved members should be counted');

        Test.startTest();
        delete gm2;
        System.assertEquals(1, countFor(grp.Id), 'Count should drop after a member is deleted');
        undelete gm2;
        Test.stopTest();

        System.assertEquals(2, countFor(grp.Id), 'Count should be restored after undelete');
    }
}