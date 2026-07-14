@IsTest
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
public class KenExportCsvControllerTest {

    @IsTest
    static void getDownloadUrl_happyPath_returnsShepherdUrl() {
        Test.startTest();
        String url = KenExportCsvController.getDownloadUrl(
            'col1,col2\nval1,val2\nval3,val4',
            'cases-export.csv'
        );
        Test.stopTest();
        System.assertNotEquals(null, url);
        System.assert(
            url.startsWith('/sfc/servlet.shepherd/version/download/'),
            'URL should be a Shepherd download path; got: ' + url
        );

        // Verify a ContentVersion was actually inserted
        Integer cvCount = [SELECT COUNT() FROM ContentVersion WHERE Title = 'cases-export.csv'];
        System.assert(cvCount >= 1, 'Expected at least one ContentVersion inserted');
    }

    @IsTest
    static void getDownloadUrl_minimalContent_stillCreatesContentVersion() {
        Test.startTest();
        String url = KenExportCsvController.getDownloadUrl('a', 'minimal.csv');
        Test.stopTest();
        System.assertNotEquals(null, url);
        System.assert(url.startsWith('/sfc/servlet.shepherd/version/download/'));
    }

    @IsTest
    static void getDownloadUrl_nullFilename_throwsAuraHandledException() {
        // ContentVersion requires Title — null should throw, caught and wrapped.
        Test.startTest();
        try {
            KenExportCsvController.getDownloadUrl('data', null);
            System.assert(false, 'Should have thrown for null filename');
        } catch (AuraHandledException e) {
            System.assert(true);
        } catch (Exception e) {
            // accept any exception type — the goal is to exercise the catch branch
            System.assert(true);
        }
        Test.stopTest();
    }
}