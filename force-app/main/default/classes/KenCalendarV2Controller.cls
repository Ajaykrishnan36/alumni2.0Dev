public without sharing class KenCalendarV2Controller {

    public class CalendarEvent {
        @AuraEnabled public Integer day;
        @AuraEnabled public String title;
        @AuraEnabled public String location;
        @AuraEnabled public String tone;

        public CalendarEvent(Integer day, String title, String location, String tone) {
            this.day = day;
            this.title = title;
            this.location = location;
            this.tone = tone;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<CalendarEvent> getEvents(String month) {
        // For stub phase, ignore month filter — return the same mock set as the LWC.
        return new List<CalendarEvent>{
            new CalendarEvent(12, 'Bangalore Alumni Meetup',     'The Lalit, Bangalore',  'amber'),
            new CalendarEvent(18, 'Q2 mentor sign-ups close',    'Mentorship portal',     'violet'),
            new CalendarEvent(22, 'AI in Career Building webinar','Online · 6:00 PM',     'sky'),
            new CalendarEvent(25, 'Annual Reunion announcement', 'Campus wide',           'rose'),
            new CalendarEvent(28, 'Living Earth Collaborative',  'Innovation Hub',        'emerald'),
            new CalendarEvent(31, 'Workshop with Tanya J',       'Block C · 11:00 AM',    'amber')
        };
    }
}