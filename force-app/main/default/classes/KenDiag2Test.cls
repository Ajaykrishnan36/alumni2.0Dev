@isTest(SeeAllData=true)
public class KenDiag2Test {
    @isTest static void run() {
        User u = [SELECT Id FROM User WHERE Username='alumnitestuser1@yopmail.com' LIMIT 1];
        String results = '';
        System.runAs(u) {
            try {
                KenNetworkController.NetworkDataResponse r = KenNetworkController.getNetworkData();
                results += 'NETWORK[all=' + (r.allAlumni == null ? 0 : r.allAlumni.size()) + ',conn=' + (r.yourConnections == null ? 0 : r.yourConnections.size()) + '];';
            } catch (Exception e) { results += 'NETWORK_FAIL[' + e.getMessage() + '];'; }
            try {
                results += 'MENT_CONN=' + KenMentorshipController.getMentorshipConnections().size() + ';';
            } catch (Exception e) { results += 'MENT_FAIL[' + e.getMessage() + '];'; }
            try {
                List<KenAlumniOnboardingService.AlumniRoleInfo> roles = KenAlumniOnboardingService.getAlumniRolesForPerson([SELECT AccountId FROM User WHERE Id=:UserInfo.getUserId()].AccountId);
                if (roles.isEmpty()) {
                    results += 'SURV_NO_ROLE;';
                } else {
                    Id rid = roles[0].constituentRoleId;
                    results += 'SURV[all=' + KenSurveyController.getSurveys(rid).size() + ',my=' + KenSurveyController.getMySurveys(rid).size() + '];';
                }
            } catch (Exception e) { results += 'SURV_FAIL[' + e.getMessage() + '];'; }
            try {
                results += 'BIZ[all=' + KenBusinessController.getAllBusinesses().size() + ',mine=' + KenBusinessController.getMyBusinesses().size() + '];';
            } catch (Exception e) { results += 'BIZ_FAIL[' + e.getMessage() + '];'; }
            results += 'RAW[ev=' + [SELECT COUNT() FROM Ken_Event_Master__c WHERE Is_Active__c=true AND Event_Status__c='Approved']
                + ',gr=' + [SELECT COUNT() FROM Ken_Group__c WHERE Is_Active__c=true]
                + ',nc=' + [SELECT COUNT() FROM Ken_Network_Connection__c]
                + ',sv=' + [SELECT COUNT() FROM Ken_Survey__c]
                + ',bz=' + [SELECT COUNT() FROM Ken_Business_Directory__c] + '];';
        }
        System.assertEquals('FORCE_FAIL', results);
    }
}