@isTest
private class KenCalendarV2ControllerTest {
    @isTest static void testGetEvents() {
        List<KenCalendarV2Controller.CalendarEvent> e = KenCalendarV2Controller.getEvents('2026-05');
        System.assertEquals(6, e.size());
        System.assertEquals('Bangalore Alumni Meetup', e[0].title);
        System.assertNotEquals(0, KenCalendarV2Controller.getEvents(null).size());
    }
}