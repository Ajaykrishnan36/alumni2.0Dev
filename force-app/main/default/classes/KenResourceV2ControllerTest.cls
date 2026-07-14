@isTest
private class KenResourceV2ControllerTest {
    @isTest static void testGetCategoriesEmpty() {
        List<KenResourceV2Controller.FolderItem> cats = KenResourceV2Controller.getCategories();
        System.assertNotEquals(null, cats);
    }
    @isTest static void testCreateFolderAndResource() {
        Map<String, Object> fp = new Map<String, Object>{
            'name' => 'Test Folder', 'owner' => 'QA', 'color' => '#3061FF',
            'icon' => 'F', 'updated' => '01 Jan 2026', 'privacy' => 'Public'
        };
        Id folderId = KenResourceV2Controller.createFolder(fp);
        System.assertNotEquals(null, folderId);

        Map<String, Object> rp = new Map<String, Object>{
            'name' => 'Doc.pdf', 'folderId' => folderId, 'size' => '1 MB',
            'fileDate' => '01 Jan 2026', 'ext' => 'PDF', 'notes' => 'n'
        };
        Id rId = KenResourceV2Controller.createResource(rp);
        System.assertNotEquals(null, rId);

        List<KenResourceV2Controller.ResourceItem> items = KenResourceV2Controller.getResources(folderId);
        System.assertEquals(1, items.size());

        KenResourceV2Controller.ResourceItem one = KenResourceV2Controller.getResource(rId);
        System.assertEquals('Doc.pdf', one.name);

        KenResourceV2Controller.archiveResource(rId);
        System.assertEquals(0, KenResourceV2Controller.getResources(folderId).size());
    }
}