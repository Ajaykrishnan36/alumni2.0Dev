@isTest(SeeAllData=true)
public class KenChatDiagTest {
    @isTest static void verifyResolver() {
        User u = [SELECT Id FROM User WHERE Username='alumnitestuser1@yopmail.com' LIMIT 1];
        String results = '';
        System.runAs(u) {
            // Pick a real Person Account (not the test user's)
            Account target = [SELECT Id, Name, PersonContactId FROM Account WHERE IsPersonAccount=true AND Id != '001F700001rSVQ7IAO' AND PersonContactId != null LIMIT 1];
            try {
                Id threadId = KenChatV2Controller.getOrCreateThreadWithContact(target.Id);
                results += 'PERSON_ACCOUNT_OK: thread=' + threadId + ';';
            } catch (Exception e) { results += 'PERSON_FAIL[' + e.getMessage() + '];'; }
            
            // Pick a non-Person Account (Company, etc.) — should now degrade gracefully
            List<Account> nonPerson = [SELECT Id, Name FROM Account WHERE IsPersonAccount=false LIMIT 1];
            if (!nonPerson.isEmpty()) {
                try {
                    Id threadId2 = KenChatV2Controller.getOrCreateThreadWithContact(nonPerson[0].Id);
                    results += 'NON_PERSON_FALLBACK_OK: thread=' + threadId2 + ';';
                } catch (Exception e) { results += 'NON_PERSON_MSG[' + e.getMessage() + '];'; }
            }
        }
        System.assertEquals('FORCE', results);
    }
}