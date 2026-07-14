@isTest(SeeAllData=true)
public class KenDiag3Test {
    @isTest static void verifySurveys() {
        User u = [SELECT Id FROM User WHERE Username='alumnitestuser1@yopmail.com' LIMIT 1];
        String results = '';
        System.runAs(u) {
            Id rid = '0vyIl0000004ChUIAU';
            try {
                List<KenSurveyController.SurveyData> all = KenSurveyController.getSurveys(rid);
                results += 'getSurveys=' + all.size() + '; titles=[';
                Integer i = 0;
                for (KenSurveyController.SurveyData s : all) {
                    if (i++ >= 5) break;
                    results += s.name + ',';
                }
                results += ']; getMySurveys=' + KenSurveyController.getMySurveys(rid).size();
            } catch (Exception e) { results += 'FAIL[' + e.getMessage() + ']'; }
        }
        System.assertEquals('FORCE', results);
    }
}