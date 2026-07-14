@isTest
public class KenDiagTest {
    @isTest static void run() {
        User u = [SELECT Id FROM User WHERE Username='alumnitestuser1@yopmail.com' LIMIT 1];
        System.runAs(u) {
            try { KenPortalEventController.getAllEvents(); System.debug('>>> EVENTS OK'); }
            catch (Exception e) { System.debug('>>> EVENTS FAIL: ' + e.getMessage()); }
            try { KenNetworkController.getNetworkData(); System.debug('>>> NETWORK OK'); }
            catch (Exception e) { System.debug('>>> NETWORK FAIL: ' + e.getMessage()); }
            try { KenMentorshipController.getMentorshipConnections(); System.debug('>>> MENTORSHIP OK'); }
            catch (Exception e) { System.debug('>>> MENTORSHIP FAIL: ' + e.getMessage()); }
            try { KenMyProfileController.getMyProfile(); System.debug('>>> PROFILE OK'); }
            catch (Exception e) { System.debug('>>> PROFILE FAIL: ' + e.getMessage()); }
            try { KenNavBarController.getUserContactDetails(); System.debug('>>> NAVBAR OK'); }
            catch (Exception e) { System.debug('>>> NAVBAR FAIL: ' + e.getMessage()); }
            try { KenHomeController.getUserDashboardState(); System.debug('>>> HOME OK'); }
            catch (Exception e) { System.debug('>>> HOME FAIL: ' + e.getMessage()); }
        }
    }
}