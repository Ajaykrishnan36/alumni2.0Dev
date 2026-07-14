/**
 * Portal-owned helper for the Host-an-Event wizard. Persists the Step 4
 * Pre-Event Survey / Meals state as a JSON blob on the event record
 * (Survey_JSON__c) — the established JSON serialization pattern, avoiding
 * edits to the deployed KenEventFormController.
 */
public without sharing class KenEventHostExtras {
    @AuraEnabled
    public static void saveEventSurveyJson(Id eventId, String surveyJson) {
        if (eventId == null) {
            throw new AuraHandledException('Event Id is required.');
        }
        update new Ken_Event_Master__c(Id = eventId, Survey_JSON__c = surveyJson);
    }

    /**
     * Sends a simple plain-text "you're invited to speak" email to each speaker.
     * invitesJson: [{ name, email, eventName, eventDate, sessionTitle }, ...]
     * Returns the number of emails dispatched. Invalid/blank emails are skipped.
     */
    @AuraEnabled
    public static Integer sendSpeakerInvites(String invitesJson) {
        if (String.isBlank(invitesJson)) {
            return 0;
        }
        List<Object> raw;
        try {
            raw = (List<Object>) JSON.deserializeUntyped(invitesJson);
        } catch (Exception e) {
            return 0;
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Object o : raw) {
            if (!(o instanceof Map<String, Object>)) continue;
            Map<String, Object> m = (Map<String, Object>) o;

            String email = (String) m.get('email');
            if (String.isBlank(email) || !email.contains('@')) continue;

            String name = (String) m.get('name');
            String eventName = (String) m.get('eventName');
            String eventDate = (String) m.get('eventDate');
            String sessionTitle = (String) m.get('sessionTitle');
            String evt = String.isBlank(eventName) ? 'our event' : eventName;

            String body = (String.isBlank(name) ? 'Hello,' : 'Hello ' + name + ',') + '\n\n'
                + 'You have been invited as a speaker for "' + evt + '".\n'
                + (String.isBlank(sessionTitle) ? '' : 'Session: ' + sessionTitle + '\n')
                + (String.isBlank(eventDate) ? '' : 'Date: ' + eventDate + '\n')
                + '\nWe look forward to your participation.\n\nThank you.';

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ email });
            msg.setSubject('You\'re invited to speak at ' + evt);
            msg.setPlainTextBody(body);
            msg.setSaveAsActivity(false);
            emails.add(msg);
        }

        if (emails.isEmpty()) {
            return 0;
        }
        Messaging.sendEmail(emails, false);
        return emails.size();
    }
}