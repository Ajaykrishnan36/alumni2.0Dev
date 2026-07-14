@isTest
private class KenLogServiceTest {
    @isTest
    static void buildPopulatesAllFields() {
        Ken_Logs__c logRecord = KenLogService.build(
            KenLogService.CATEGORY_IMPORT,
            KenLogService.TYPE_ERROR,
            'Alumni Bulk Import',
            'Class:Test',
            '707000000000000',
            'Something failed',
            'line 1\nline 2'
        );
        System.assertEquals(KenLogService.CATEGORY_IMPORT, logRecord.Category__c, 'Category should be set');
        System.assertEquals(KenLogService.TYPE_ERROR, logRecord.Log_Type__c, 'Type should be set');
        System.assertEquals('Alumni Bulk Import', logRecord.Process__c, 'Process should be set');
        System.assertEquals('Something failed', logRecord.Message__c, 'Message should be set');
    }

    @isTest
    static void logInsertsRecord() {
        Test.startTest();
        KenLogService.log(
            KenLogService.CATEGORY_EMAIL,
            KenLogService.TYPE_WARNING,
            'Email Send',
            'Class:Test',
            'ref-1',
            'Email bounced',
            null
        );
        Test.stopTest();
        List<Ken_Logs__c> logs = [SELECT Id, Category__c, Message__c FROM Ken_Logs__c WHERE Reference_Id__c = 'ref-1'];
        System.assertEquals(1, logs.size(), 'One log should be inserted');
        System.assertEquals('Email bounced', logs[0].Message__c, 'Message should persist');
    }

    @isTest
    static void logExceptionInsertsRecord() {
        Test.startTest();
        try {
            throw new IllegalArgumentException('boom');
        } catch (Exception ex) {
            KenLogService.logException(KenLogService.CATEGORY_GENERAL, 'Proc', 'Src', 'ref-ex', ex);
        }
        Test.stopTest();
        List<Ken_Logs__c> logs = [SELECT Id, Message__c FROM Ken_Logs__c WHERE Reference_Id__c = 'ref-ex'];
        System.assertEquals(1, logs.size(), 'Exception log should be inserted');
        System.assert(logs[0].Message__c.contains('boom'), 'Message should contain the exception message');
    }

    @isTest
    static void insertLogsHandlesEmptyAndNull() {
        Test.startTest();
        KenLogService.insertLogs(null);
        KenLogService.insertLogs(new List<Ken_Logs__c>());
        KenLogService.logException(KenLogService.CATEGORY_GENERAL, 'P', 'S', 'r', null);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Ken_Logs__c], 'No logs should be created');
    }

    @isTest
    static void truncateHandlesLongText() {
        String longText = 'x'.repeat(131080);
        Ken_Logs__c logRecord = KenLogService.build(
            KenLogService.CATEGORY_GENERAL,
            KenLogService.TYPE_INFO,
            'P', 'S', 'ref-long', longText, longText
        );
        System.assertEquals(131072, logRecord.Message__c.length(), 'Message should be truncated to max length');
    }
}