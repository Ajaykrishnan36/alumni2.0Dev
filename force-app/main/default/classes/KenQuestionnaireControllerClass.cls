public with sharing class KenQuestionnaireControllerClass {
    @AuraEnabled
    public static Id saveQuestionnaireWithQuestions(Ken_Questionnaire__c questionnaire, List<Ken_Questionnaire_Parameter__c> questions, String relatedRecordId,String relatedObjectType) {
        try {
            // Insert the questionnaire record to get the new ID
            if (Schema.sObjectType.Ken_Questionnaire__c.isCreateable()) {
                insert questionnaire;
            }

            // Set the Questionnaire__c field on each question to the new questionnaire ID
            for (Ken_Questionnaire_Parameter__c question : questions) {
                question.Questionnaire__c = questionnaire.Id;
            }

            // Insert the questions to get their IDs
            if (!questions.isEmpty() && Schema.sObjectType.Ken_Questionnaire_Parameter__c.isCreateable()) {
                insert questions;
            }

            SObject relatedRecord;

            if(relatedObjectType == 'Ken_Service_Offering__c'){
                relatedRecord = new Ken_Service_Offering__c(Id=relatedRecordId, Questionnaire__c = questionnaire.Id);
            }
            // -----------------------------------------------------------------
            // Ken_Schedule_Sessions__c branch commented out — Sessions module is
            // outside the Support & Services scope. Restore the block below if
            // the Sessions module is reintroduced.
            // -----------------------------------------------------------------
            // else if(relatedObjectType == 'Ken_Schedule_Sessions__c'){
            //     relatedRecord = new Ken_Schedule_Sessions__c(Id=relatedRecordId, Questionnaire__c = questionnaire.Id);
            // }

            if (relatedRecord != null) {
                if (relatedRecord instanceof Ken_Service_Offering__c) {
                    if (Schema.sObjectType.Ken_Service_Offering__c.isUpdateable()) {
                        update relatedRecord;
                    }
                }
                // -----------------------------------------------------------------
                // Sessions branch commented out — see note above.
                // -----------------------------------------------------------------
                // else if (relatedRecord instanceof Ken_Schedule_Sessions__c) {
                //     if (Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
                //         update relatedRecord;
                //     }
                // }
            }

            // Return the new questionnaire ID
            return questionnaire.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Ken_Questionnaire__c getQuestionnaireWithQuestions(Id questionnaireId) {
        try {
            return [SELECT Id, Section_Name__c, Descripation__c, Target_Audience__c,
                    (SELECT Id, Question_Label__c, Question_Type__c, Is_Required__c, MCQ_Options__c,Section_Name__c,Section_Header__c
                     FROM Ken_Questionnaire_Parameters__r)
                    FROM Ken_Questionnaire__c
                    WHERE Id = :questionnaireId WITH SECURITY_ENFORCED];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id saveQuestionnaireWithQuestions2(Ken_Questionnaire__c questionnaire, List<Ken_Questionnaire_Parameter__c> questions) {
        try {

            // Serialize the questions list to JSON and save to the questionnaire
            String questionsJson = JSON.serialize(questions);
            questionnaire.Questions_JSON__c = questionsJson;

            // Upsert the questionnaire record
            if (Schema.sObjectType.Ken_Questionnaire__c.isCreateable() &&
                Schema.sObjectType.Ken_Questionnaire__c.isUpdateable()) {
                upsert questionnaire;
            }

            // Retrieve existing questions from the database
            List<Ken_Questionnaire_Parameter__c> existingQuestions = [
                SELECT Id FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c = :questionnaire.Id WITH SECURITY_ENFORCED
            ];

            // Get the IDs of the questions sent from the LWC component
            Set<Id> incomingQuestionIds = new Set<Id>();
            for (Ken_Questionnaire_Parameter__c question : questions) {
                if (question.Id != null) {
                    incomingQuestionIds.add(question.Id);
                }
            }

            // Identify the questions to delete
            List<Ken_Questionnaire_Parameter__c> questionsToDelete = new List<Ken_Questionnaire_Parameter__c>();
            for (Ken_Questionnaire_Parameter__c existingQuestion : existingQuestions) {
                if (!incomingQuestionIds.contains(existingQuestion.Id)) {
                    questionsToDelete.add(existingQuestion);
                }
            }

            // Delete the identified questions
            if (!questionsToDelete.isEmpty() && Schema.sObjectType.Ken_Questionnaire_Parameter__c.isDeletable()) {
                delete questionsToDelete;
            }

            // Handle new or updated questions
            for (Ken_Questionnaire_Parameter__c question : questions) {
                if (question.Id == null) {
                    question.Questionnaire__c = questionnaire.Id;
                }
            }
            if (!questions.isEmpty() &&
                Schema.sObjectType.Ken_Questionnaire_Parameter__c.isCreateable() &&
                Schema.sObjectType.Ken_Questionnaire_Parameter__c.isUpdateable()) {
                    upsert questions;
                }

            // Return the questionnaire Id
            return questionnaire.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // -----------------------------------------------------------------
    // getQuestionnaireByEventId — commented out. Depends on Ken_Event_Master__c
    // which belongs to the Events module, outside the Support & Services scope.
    // Restore the entire method if the Events module is reintroduced.
    // -----------------------------------------------------------------
    // @AuraEnabled(cacheable=true)
    // public static Ken_Questionnaire__c getQuestionnaireByEventId(Id eventId) {
    //     try {
    //         if (eventId == null) {
    //             return null;
    //         }
    //         Ken_Event_Master__c eventRecord = [
    //             SELECT Id, Questionnaire__c
    //             FROM Ken_Event_Master__c
    //             WHERE Id = :eventId WITH SECURITY_ENFORCED
    //             LIMIT 1
    //         ];
    //         if (eventRecord.Questionnaire__c == null) {
    //             return null;
    //         }
    //         return [
    //             SELECT Id, Section_Name__c, Descripation__c, Target_Audience__c,
    //                    (SELECT Id, Question_Label__c, Question_Type__c, Is_Required__c, MCQ_Options__c, Section_Name__c, Section_Header__c
    //                     FROM Ken_Questionnaire_Parameters__r
    //                     ORDER BY CreatedDate ASC)
    //             FROM Ken_Questionnaire__c
    //             WHERE Id = :eventRecord.Questionnaire__c WITH SECURITY_ENFORCED
    //             LIMIT 1
    //         ];
    //     } catch (Exception e) {
    //         throw new AuraHandledException(e.getMessage());
    //     }
    // }

    // -----------------------------------------------------------------
    // saveQuestionnaireForEvent — commented out. Depends on Ken_Event_Master__c
    // which belongs to the Events module, outside the Support & Services scope.
    // Restore the entire method if the Events module is reintroduced.
    // -----------------------------------------------------------------
    // @AuraEnabled
    // public static Id saveQuestionnaireForEvent(Id eventId, Ken_Questionnaire__c questionnaire, List<Ken_Questionnaire_Parameter__c> questions) {
    //     try {
    //         if (eventId == null) {
    //             throw new AuraHandledException('Event Id is required.');
    //         }
    //         Ken_Event_Master__c eventRecord = [
    //             SELECT Id, Name, Questionnaire__c
    //             FROM Ken_Event_Master__c
    //             WHERE Id = :eventId WITH SECURITY_ENFORCED
    //             LIMIT 1
    //         ];
    //
    //         if (questionnaire == null) {
    //             questionnaire = new Ken_Questionnaire__c();
    //         }
    //         if (questionnaire.Id == null && eventRecord.Questionnaire__c != null) {
    //             questionnaire.Id = eventRecord.Questionnaire__c;
    //         }
    //         questionnaire.Section_Name__c = eventRecord.Name;
    //
    //         String questionsJson = JSON.serialize(questions);
    //         questionnaire.Questions_JSON__c = questionsJson;
    //
    //         if (Schema.sObjectType.Ken_Questionnaire__c.isCreateable() &&
    //             Schema.sObjectType.Ken_Questionnaire__c.isUpdateable()) {
    //             upsert questionnaire;
    //         }
    //
    //         List<Ken_Questionnaire_Parameter__c> existingQuestions = [
    //             SELECT Id
    //             FROM Ken_Questionnaire_Parameter__c
    //             WHERE Questionnaire__c = :questionnaire.Id WITH SECURITY_ENFORCED
    //         ];
    //
    //         Set<Id> incomingQuestionIds = new Set<Id>();
    //         for (Ken_Questionnaire_Parameter__c question : questions) {
    //             if (question.Id != null) {
    //                 incomingQuestionIds.add(question.Id);
    //             }
    //         }
    //
    //         List<Ken_Questionnaire_Parameter__c> questionsToDelete = new List<Ken_Questionnaire_Parameter__c>();
    //         for (Ken_Questionnaire_Parameter__c existingQuestion : existingQuestions) {
    //             if (!incomingQuestionIds.contains(existingQuestion.Id)) {
    //                 questionsToDelete.add(existingQuestion);
    //             }
    //         }
    //
    //         if (!questionsToDelete.isEmpty() && Schema.sObjectType.Ken_Questionnaire_Parameter__c.isDeletable()) {
    //             delete questionsToDelete;
    //         }
    //
    //         for (Ken_Questionnaire_Parameter__c question : questions) {
    //             if (question.Id == null) {
    //                 question.Questionnaire__c = questionnaire.Id;
    //             }
    //         }
    //         if (!questions.isEmpty() &&
    //             Schema.sObjectType.Ken_Questionnaire_Parameter__c.isCreateable() &&
    //             Schema.sObjectType.Ken_Questionnaire_Parameter__c.isUpdateable()) {
    //             upsert questions;
    //         }
    //
    //         if (Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
    //             Ken_Event_Master__c updateEvent = new Ken_Event_Master__c(
    //                 Id = eventRecord.Id,
    //                 Questionnaire__c = questionnaire.Id
    //             );
    //             update updateEvent;
    //         }
    //
    //         return questionnaire.Id;
    //     } catch (Exception e) {
    //         throw new AuraHandledException(e.getMessage());
    //     }
    // }

    // -----------------------------------------------------------------
    // saveQuestionnaireForSession — commented out. Depends on Ken_Schedule_Sessions__c
    // which belongs to the Sessions module, outside the Support & Services scope.
    // Restore the entire method if the Sessions module is reintroduced.
    // -----------------------------------------------------------------
    // @AuraEnabled
    // public static Id saveQuestionnaireForSession(Id sessionId, Ken_Questionnaire__c questionnaire, List<Ken_Questionnaire_Parameter__c> questions) {
    //     try {
    //         if (sessionId == null) {
    //             throw new AuraHandledException('Session Id is required.');
    //         }
    //         Ken_Schedule_Sessions__c sessionRecord = [
    //             SELECT Id, Name, Questionnaire__c
    //             FROM Ken_Schedule_Sessions__c
    //             WHERE Id = :sessionId WITH SECURITY_ENFORCED
    //             LIMIT 1
    //         ];
    //
    //         if (questionnaire == null) {
    //             questionnaire = new Ken_Questionnaire__c();
    //         }
    //         if (questionnaire.Id == null && sessionRecord.Questionnaire__c != null) {
    //             questionnaire.Id = sessionRecord.Questionnaire__c;
    //         }
    //
    //         if (String.isBlank(questionnaire.Section_Name__c)) {
    //             questionnaire.Section_Name__c = sessionRecord.Name;
    //         }
    //
    //         String questionsJson = JSON.serialize(questions);
    //         questionnaire.Questions_JSON__c = questionsJson;
    //
    //         if (Schema.sObjectType.Ken_Questionnaire__c.isCreateable() &&
    //             Schema.sObjectType.Ken_Questionnaire__c.isUpdateable()) {
    //             upsert questionnaire;
    //         }
    //
    //         List<Ken_Questionnaire_Parameter__c> existingQuestions = [
    //             SELECT Id
    //             FROM Ken_Questionnaire_Parameter__c
    //             WHERE Questionnaire__c = :questionnaire.Id WITH SECURITY_ENFORCED
    //         ];
    //
    //         Set<Id> incomingQuestionIds = new Set<Id>();
    //         if (questions != null) {
    //             for (Ken_Questionnaire_Parameter__c question : questions) {
    //                 if (question.Id != null) {
    //                     incomingQuestionIds.add(question.Id);
    //                 }
    //             }
    //         }
    //
    //         List<Ken_Questionnaire_Parameter__c> questionsToDelete = new List<Ken_Questionnaire_Parameter__c>();
    //         for (Ken_Questionnaire_Parameter__c existingQuestion : existingQuestions) {
    //             if (!incomingQuestionIds.contains(existingQuestion.Id)) {
    //                 questionsToDelete.add(existingQuestion);
    //             }
    //         }
    //
    //         if (!questionsToDelete.isEmpty() && Schema.sObjectType.Ken_Questionnaire_Parameter__c.isDeletable()) {
    //             delete questionsToDelete;
    //         }
    //
    //         if (questions != null) {
    //             for (Ken_Questionnaire_Parameter__c question : questions) {
    //                 if (question.Id == null) {
    //                     question.Questionnaire__c = questionnaire.Id;
    //                 }
    //             }
    //         }
    //
    //         if (questions != null && !questions.isEmpty() &&
    //             Schema.sObjectType.Ken_Questionnaire_Parameter__c.isCreateable() &&
    //             Schema.sObjectType.Ken_Questionnaire_Parameter__c.isUpdateable()) {
    //             upsert questions;
    //         }
    //
    //         if (Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
    //             Ken_Schedule_Sessions__c updateSession = new Ken_Schedule_Sessions__c(
    //                 Id = sessionRecord.Id,
    //                 Questionnaire__c = questionnaire.Id
    //             );
    //             update updateSession;
    //         }
    //
    //         return questionnaire.Id;
    //     } catch (Exception e) {
    //         throw new AuraHandledException(e.getMessage());
    //     }
    // }
}