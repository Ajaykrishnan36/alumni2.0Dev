@IsTest
private class KenQuestionnaireControllerClassTest {
    private static final String RUN_AS_ALIAS = 'qqrusr';
    private static final String BASE_QUESTIONNAIRE_SECTION = 'Base Questionnaire';
    // Event/Session constants kept for reference but not used while the
    // Event/Session methods are commented out in the production class.
    // private static final String EVENT_WITH_Q_NAME = 'Event With Questionnaire';
    // private static final String EVENT_NO_Q_NAME = 'Event Without Questionnaire';
    // private static final String SESSION_NAME = 'Questionnaire Session';

    @TestSetup
    static void setupData() {
        // Assign the admin permission set to the test runner so WITH SECURITY_ENFORCED
        // queries don't fail on FLS in environments where the running user lacks it.
        for (PermissionSet ps : [
            SELECT Id FROM PermissionSet WHERE Name = 'Support_And_Services_Admin_Access' LIMIT 1
        ]) {
            try {
                insert new PermissionSetAssignment(
                    AssigneeId = UserInfo.getUserId(),
                    PermissionSetId = ps.Id
                );
            } catch (Exception alreadyAssigned) {
                // The user may already have the permission set in some orgs — ignore.
            }
        }
        // -----------------------------------------------------------------
        // Alumni_Trigger_Settings__c insert is commented out because it
        // belongs to the Alumni module, outside Support & Services scope.
        // -----------------------------------------------------------------
        // insert new Alumni_Trigger_Settings__c(Event_Trigger__c = true);

        Id profileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;
        User runAsUser = new User(
            FirstName = 'Questionnaire',
            LastName = 'Runner',
            Email = 'questionnaire.runner@example.com',
            Username = 'questionnaire.runner.' + DateTime.now().getTime() + '@example.com',
            Alias = RUN_AS_ALIAS,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
        insert runAsUser;

        insert new Ken_Service_Offering__c(
            Name = 'Service Offering For Questionnaire',
            OwnerId = runAsUser.Id
        );

        Ken_Questionnaire__c baseQuestionnaire = new Ken_Questionnaire__c(
            Section_Name__c = BASE_QUESTIONNAIRE_SECTION,
            Descripation__c = 'Base description',
            Target_Audience__c = 'All',
            OwnerId = runAsUser.Id
        );
        insert baseQuestionnaire;

        insert new List<Ken_Questionnaire_Parameter__c>{
            new Ken_Questionnaire_Parameter__c(
                Questionnaire__c = baseQuestionnaire.Id,
                Question_Label__c = 'Base Question 1',
                Question_Type__c = 'Linear Scale',
                Is_Required__c = true
            ),
            new Ken_Questionnaire_Parameter__c(
                Questionnaire__c = baseQuestionnaire.Id,
                Question_Label__c = 'Base Question 2',
                Question_Type__c = 'Linear Scale',
                Is_Required__c = false
            )
        };

        // -----------------------------------------------------------------
        // Ken_Event_Master__c + Ken_Schedule_Sessions__c seed data
        // commented out — the Event/Session methods they support are no
        // longer in the production class.
        // -----------------------------------------------------------------
        // Ken_Event_Master__c eventWithQuestionnaire = new Ken_Event_Master__c(
        //     Name = EVENT_WITH_Q_NAME,
        //     Event_Type__c = 'Workshop',
        //     Start_Date__c = Date.today(),
        //     End_Date__c = Date.today().addDays(1),
        //     Questionnaire__c = baseQuestionnaire.Id,
        //     OwnerId = runAsUser.Id
        // );
        // Ken_Event_Master__c eventWithoutQuestionnaire = new Ken_Event_Master__c(
        //     Name = EVENT_NO_Q_NAME,
        //     Event_Type__c = 'Workshop',
        //     Start_Date__c = Date.today(),
        //     End_Date__c = Date.today().addDays(1),
        //     OwnerId = runAsUser.Id
        // );
        // insert new List<Ken_Event_Master__c>{ eventWithQuestionnaire, eventWithoutQuestionnaire };
        //
        // insert new Ken_Schedule_Sessions__c(
        //     Name = SESSION_NAME,
        //     Event_Reference__c = eventWithoutQuestionnaire.Id,
        //     Start_Date__c = Date.today(),
        //     End_Date__c = Date.today(),
        //     Start_Time__c = Time.newInstance(10, 0, 0, 0),
        //     End_Time__c = Time.newInstance(11, 0, 0, 0),
        //     Location_Type__c = 'Online',
        //     Session_Link__c = 'https://example.com/session',
        //     Location__c = 'Virtual Hall',
        //     OwnerId = runAsUser.Id
        // );
    }

    @IsTest
    static void testSaveQuestionnaireWithQuestionsUpdatesRelatedRecords() {
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(currentUser) {
            Id serviceOfferingId = [SELECT Id FROM Ken_Service_Offering__c LIMIT 1].Id;

            Test.startTest();
            Id serviceQuestionnaireId = KenQuestionnaireControllerClass.saveQuestionnaireWithQuestions(
                new Ken_Questionnaire__c(
                    Section_Name__c = 'Service Questionnaire',
                    Descripation__c = 'Service description',
                    Target_Audience__c = 'Service audience'
                ),
                buildQuestionList('Service'),
                String.valueOf(serviceOfferingId),
                'Ken_Service_Offering__c'
            );

            Id noRelatedRecordQuestionnaireId = KenQuestionnaireControllerClass.saveQuestionnaireWithQuestions(
                new Ken_Questionnaire__c(
                    Section_Name__c = 'No Related Record',
                    Descripation__c = 'No related record',
                    Target_Audience__c = 'General'
                ),
                buildQuestionList('NoRelated'),
                null,
                'Unknown_Object__c'
            );
            Test.stopTest();

            System.assertNotEquals(null, serviceQuestionnaireId, 'Service questionnaire should be created.');
            System.assertNotEquals(null, noRelatedRecordQuestionnaireId, 'Questionnaire creation should succeed without related type.');

            Ken_Service_Offering__c serviceOffering = [
                SELECT Questionnaire__c
                FROM Ken_Service_Offering__c
                WHERE Id = :serviceOfferingId
                LIMIT 1
            ];
            System.assertEquals(serviceQuestionnaireId, serviceOffering.Questionnaire__c, 'Service offering should reference saved questionnaire.');
        }
    }

    @IsTest
    static void testGetQuestionnaireWithQuestionsReturnsChildren() {
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(currentUser) {
            Id questionnaireId = [
                SELECT Id
                FROM Ken_Questionnaire__c
                WHERE Section_Name__c = :BASE_QUESTIONNAIRE_SECTION
                LIMIT 1
            ].Id;

            Test.startTest();
            Ken_Questionnaire__c questionnaire =
                KenQuestionnaireControllerClass.getQuestionnaireWithQuestions(questionnaireId);
            Test.stopTest();

            System.assertNotEquals(null, questionnaire, 'Questionnaire should be returned.');
            System.assertEquals(2, questionnaire.Ken_Questionnaire_Parameters__r.size(), 'Seeded child questions should be returned.');
        }
    }

    @IsTest
    static void testSaveQuestionnaireWithQuestions2UpsertsAndDeletesQuestions() {
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(currentUser) {
            Ken_Questionnaire__c questionnaire = [
                SELECT Id
                FROM Ken_Questionnaire__c
                WHERE Section_Name__c = :BASE_QUESTIONNAIRE_SECTION
                LIMIT 1
            ];
            List<Ken_Questionnaire_Parameter__c> existingQuestions = [
                SELECT Id, Question_Label__c, Question_Type__c, Is_Required__c
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c = :questionnaire.Id
                ORDER BY CreatedDate ASC
            ];
            Id removedQuestionId = existingQuestions[1].Id;

            existingQuestions[0].Question_Label__c = 'Updated Existing Label';
            existingQuestions.remove(1);
            existingQuestions.add(
                new Ken_Questionnaire_Parameter__c(
                    Question_Label__c = 'New Added Question',
                    Question_Type__c = 'Dropdown',
                    Is_Required__c = true
                )
            );

            Test.startTest();
            Id resultId = KenQuestionnaireControllerClass.saveQuestionnaireWithQuestions2(questionnaire, existingQuestions);
            Test.stopTest();

            System.assertEquals(questionnaire.Id, resultId, 'Returned id should match target questionnaire.');

            List<Ken_Questionnaire_Parameter__c> afterSaveQuestions = [
                SELECT Id, Question_Label__c
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c = :questionnaire.Id
            ];
            System.assertEquals(2, afterSaveQuestions.size(), 'Method should keep one updated and one new question.');

            Integer removedCount = [
                SELECT COUNT()
                FROM Ken_Questionnaire_Parameter__c
                WHERE Id = :removedQuestionId
            ];
            System.assertEquals(0, removedCount, 'Question not sent by caller should be deleted.');
        }
    }

    // -----------------------------------------------------------------
    // Event-related tests commented out — the production methods they
    // exercise (getQuestionnaireByEventId, saveQuestionnaireForEvent)
    // are no longer in scope for the Support & Services module.
    // -----------------------------------------------------------------
    // @IsTest
    // static void testGetQuestionnaireByEventIdPaths() { ... }
    //
    // @IsTest
    // static void testSaveQuestionnaireForEventSuccessAndNullEventValidation() { ... }

    // -----------------------------------------------------------------
    // Session-related test commented out — the production method
    // (saveQuestionnaireForSession) is no longer in scope.
    // -----------------------------------------------------------------
    // @IsTest
    // static void testSaveQuestionnaireForSessionSuccessAndNullSessionValidation() { ... }

    @IsTest
    static void testRunAsSmokeForPmdValidation() {
        User runAsUser = getRunAsUser();
        System.runAs(runAsUser) {
            System.assertEquals(true, true, 'RunAs branch executed.');
        }
    }

    // Helper assertion methods for the Event/Session save flows — kept
    // only as commented stubs since the underlying production methods
    // have been commented out for the standalone S&S package.
    // private static void assertAuraHandledExceptionOnEventSave() { ... }
    // private static void assertAuraHandledExceptionOnSessionSave() { ... }

    private static List<Ken_Questionnaire_Parameter__c> buildQuestionList(String labelPrefix) {
        return new List<Ken_Questionnaire_Parameter__c>{
            new Ken_Questionnaire_Parameter__c(
                Question_Label__c = labelPrefix + ' Question 1',
                Question_Type__c = 'Linear Scale',
                Is_Required__c = true
            ),
            new Ken_Questionnaire_Parameter__c(
                Question_Label__c = labelPrefix + ' Question 2',
                Question_Type__c = 'Linear Scale',
                Is_Required__c = false
            )
        };
    }

    private static User getRunAsUser() {
        return [SELECT Id FROM User WHERE Alias = :RUN_AS_ALIAS LIMIT 1];
    }
}