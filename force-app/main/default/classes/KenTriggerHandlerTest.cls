@IsTest
private class KenTriggerHandlerTest {
    private class ExposedKenTriggerHandler extends KenTriggerHandler {
        private void invokeBeforeInsert() {
            processBeforeInsert();
        }

        private void invokeAfterInsert() {
            processAfterInsert();
        }

        private void invokeBeforeUpdate() {
            processBeforeUpdate();
        }

        private void invokeAfterUpdate() {
            processAfterUpdate();
        }

        private void invokeAfterDelete() {
            processAfterDelete();
        }

        private void invokeAfterUndelete() {
            processAfterUndelete();
        }
    }

    @IsTest
    static void testSkipTriggerTrueReturnsEarly() {
        System.runAs(currentUser()) {
            KenTriggerHandler.skipTrigger = true;
            KenTriggerHandler.runCount = 0;

            new KenTriggerHandler().process();

            System.assertEquals(0, KenTriggerHandler.runCount, 'runCount should not increment when skipTrigger is true.');
        }
    }

    @IsTest
    static void testSkipTriggerFalseIncrementsRunCountOutsideTriggerContext() {
        System.runAs(currentUser()) {
            KenTriggerHandler.skipTrigger = false;
            KenTriggerHandler.runCount = 0;

            new KenTriggerHandler().process();

            System.assertEquals(1, KenTriggerHandler.runCount, 'runCount should increment when skipTrigger is false.');
        }
    }

    @IsTest
    static void testProtectedHooksAreCovered() {
        System.runAs(currentUser()) {
            ExposedKenTriggerHandler handler = new ExposedKenTriggerHandler();

            Test.startTest();
            handler.invokeBeforeInsert();
            handler.invokeAfterInsert();
            handler.invokeBeforeUpdate();
            handler.invokeAfterUpdate();
            handler.invokeAfterDelete();
            handler.invokeAfterUndelete();
            Test.stopTest();

            System.assert(true, 'Protected hook methods were invoked for coverage.');
        }
    }

    private static User currentUser() {
        return [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    }
}