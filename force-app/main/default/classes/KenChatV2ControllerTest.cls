@isTest
private class KenChatV2ControllerTest {

    // Build a portal User linked to a Contact so currentContactId() works.
    // Must use a community/portal profile - Standard User can't be linked to a Contact.
    private static User buildUserForContact(Id contactId) {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'CspLitePortal' AND Name = 'Customer Community Login User' LIMIT 1];
        String uniq = String.valueOf(DateTime.now().getTime());
        return new User(
            FirstName='Test', LastName='ChatUser',
            Email='chat.test+' + uniq + '@example.com',
            Username='chat.test+' + uniq + '@example.com.invalid',
            Alias='chttst', TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US', EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US', ProfileId=p.Id,
            ContactId=contactId
        );
    }

    @testSetup
    static void setup() {
        // Portal account owner needs a UserRole, otherwise insert of portal user fails with
        // "portal account owner must have a role". Assign the running user a role inside
        // System.runAs to avoid MIXED_DML_OPERATION with the Account/Contact inserts below.
        User running = [SELECT Id, UserRoleId FROM User WHERE Id = :UserInfo.getUserId()];
        if (running.UserRoleId == null) {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                List<UserRole> roles = [SELECT Id FROM UserRole WHERE PortalType = 'None' LIMIT 1];
                UserRole r;
                if (roles.isEmpty()) {
                    r = new UserRole(Name = 'TestPortalOwnerRole', DeveloperName = 'TestPortalOwnerRole');
                    insert r;
                } else {
                    r = roles[0];
                }
                running.UserRoleId = r.Id;
                update running;
            }
        }
        Account a = new Account(Name='Acme');
        insert a;
        Contact me = new Contact(FirstName='Me', LastName='User', AccountId=a.Id);
        Contact other = new Contact(FirstName='Other', LastName='User', AccountId=a.Id);
        insert new List<Contact>{ me, other };
    }

    @isTest
    static void coversReadsWritesNoUserContext() {
        // Without a User linked to a Contact, reads return empty and writes throw.
        Test.startTest();
        List<KenChatV2Controller.ThreadItem> threads = KenChatV2Controller.getThreads();
        List<KenChatV2Controller.MessageItem> msgs = KenChatV2Controller.getMessages(null, 50);
        System.assertEquals(0, msgs.size());
        Boolean threw = false;
        try {
            KenChatV2Controller.sendMessage(null, 'hi');
        } catch (Exception e) { threw = true; }
        System.assert(threw, 'sendMessage with null threadId should throw');
        Test.stopTest();
        System.assertNotEquals(null, threads, 'getThreads should return a list');
    }

    @isTest
    static void coversFullFlowAsLinkedUser() {
        Contact me = [SELECT Id FROM Contact WHERE FirstName='Me' LIMIT 1];
        Contact other = [SELECT Id FROM Contact WHERE FirstName='Other' LIMIT 1];

        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            u = buildUserForContact(me.Id);
            insert u;
        }

        System.runAs(u) {
            Test.startTest();
            Ken_Chat_Thread__c thr = new Ken_Chat_Thread__c(Name = 'Test Thread', Is_Group__c = false);
            insert thr;
            insert new List<Ken_Chat_Participant__c>{
                new Ken_Chat_Participant__c(Thread__c = thr.Id, Contact__c = me.Id, Unread_Count__c = 0, Is_Online__c = false),
                new Ken_Chat_Participant__c(Thread__c = thr.Id, Contact__c = other.Id, Unread_Count__c = 0, Is_Online__c = false)
            };
            Id threadId = thr.Id;
            System.assertNotEquals(null, threadId);

            Id msgId = KenChatV2Controller.sendMessage(threadId, 'hello there');
            System.assertNotEquals(null, msgId);

            List<KenChatV2Controller.ThreadItem> threads = KenChatV2Controller.getThreads();
            System.assertEquals(1, threads.size());
            System.assertEquals(threadId, threads[0].id);

            List<KenChatV2Controller.MessageItem> msgs = KenChatV2Controller.getMessages(threadId, 50);
            System.assertEquals(1, msgs.size());
            System.assertEquals(true, msgs[0].fromMe);

            KenChatV2Controller.markRead(threadId);
            Test.stopTest();
        }
    }
}