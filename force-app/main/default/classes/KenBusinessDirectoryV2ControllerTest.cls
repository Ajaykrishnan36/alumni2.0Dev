@isTest
private class KenBusinessDirectoryV2ControllerTest {
    @isTest static void testGetAll() {
        List<KenBusinessDirectoryV2Controller.BusinessItem> all = KenBusinessDirectoryV2Controller.getBusinesses('All');
        System.assertEquals(6, all.size());
        System.assertNotEquals(0, KenBusinessDirectoryV2Controller.getBusinesses(null).size());
    }
    @isTest static void testGetByCategory() {
        List<KenBusinessDirectoryV2Controller.BusinessItem> tech = KenBusinessDirectoryV2Controller.getBusinesses('Technology');
        System.assertEquals(1, tech.size());
        System.assertEquals('Vortex', tech[0].name);
    }
    @isTest static void testGetOne() {
        KenBusinessDirectoryV2Controller.BusinessItem b = KenBusinessDirectoryV2Controller.getBusiness('1');
        System.assertNotEquals(null, b);
        System.assertEquals('Quill World', b.name);
        System.assertEquals(null, KenBusinessDirectoryV2Controller.getBusiness('999'));
        System.assertEquals(null, KenBusinessDirectoryV2Controller.getBusiness(null));
        System.assertEquals(null, KenBusinessDirectoryV2Controller.getBusiness('abc'));
    }
}