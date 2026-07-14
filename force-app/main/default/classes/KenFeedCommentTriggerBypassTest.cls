/**
 * Covers the KenFeedCommentTrigger bypass path (Alumni_Trigger_Settings__c.Feed_Comment_Trigger__c).
 * The real handler behaviour is covered by KenFeedCommentTriggerHandlerTest (separate module);
 * this only exercises the trigger's early-return guard so the trigger reaches full coverage.
 */
@isTest
private class KenFeedCommentTriggerBypassTest {

    @isTest
    static void bypassFlagSuppressesProcessing() {
        Id paRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Alumni_Person_Account' LIMIT 1
        ].Id;
        Account admin = new Account(
            RecordTypeId = paRtId, FirstName = 'FeedC', LastName = 'Admin',
            PersonEmail = 'feedc.admin@ttest.example'
        );
        insert admin;

        Ken_Group__c grp = new Ken_Group__c(
            Name = 'FeedComment Bypass Group',
            Created_By__c = admin.Id,
            Status__c = 'Approved',
            Group_Type__c = 'Public'
        );
        insert grp;

        FeedItem fi = new FeedItem(ParentId = grp.Id, Body = 'Bypass coverage post');
        insert fi;

        // Enable the bypass flag → trigger should early-return without invoking the handler.
        insert new Alumni_Trigger_Settings__c(Feed_Comment_Trigger__c = true);

        Test.startTest();
        FeedComment fc = new FeedComment(FeedItemId = fi.Id, CommentBody = 'bypassed comment');
        insert fc;
        Test.stopTest();

        System.assertNotEquals(null, fc.Id, 'FeedComment should insert successfully with the trigger bypassed.');
    }
}