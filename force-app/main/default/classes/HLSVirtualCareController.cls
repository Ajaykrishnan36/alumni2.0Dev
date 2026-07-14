public class HLSVirtualCareController {
    @AuraEnabled
    public static List<xDOEventWrapper> getAppointments(){
        Id currentUserId = UserInfo.getUserId();
        List<xDOEventWrapper> currentAppointments = null;
        DateTime aDayFromNow = System.now().addDays(1);
        try{
            List<Contact> contacts = [SELECT Id,
                                             Name,
                                             Birthdate,
                                             xDO_Preferred_First_Name__c,
                                             xDO_Preferred_Last_Name__c,
                                             xDO_Image_URL__c
                                             FROM Contact];
            List<Event> events = [SELECT Id,
                                          WhatId,
                                          What.Name,
                                          What.FirstName,
                                          What.LastName,
                                          xDO_Call_Completed__c,
                                          xDO_Subject__c,
                                          xDO_Subject_Description__c,
                                          StartDateTime,
                                          EndDateTime,
                                          ActivityDate,
                                          DurationInMinutes
                                          FROM Event
                                          WHERE Type = 'Virtual Care Appointment'
                                          AND WhatId <> ''
                                          AND OwnerId = :currentUserId
                                          ORDER BY StartDateTime ASC
                                          LIMIT 100];
            if(events == null || events.size() == 0){
                return null;
            }

            currentAppointments = new List<xDOEventWrapper>();
            for(Event event : events){
                Boolean appointmentWithin24Hours = false;
                Boolean appointmentToday = false;
               
                if(event.StartDateTime < aDayFromNow){
                    appointmentWithin24Hours = true;
                }
                if(event.StartDateTime.day() == System.now().day()){
                    appointmentToday = true;
                }

                xDOEventWrapper eventWrapper = new xDOEventWrapper();
                eventWrapper.eventId = event.Id;
                eventWrapper.personAccountId = event.WhatId;
                eventWrapper.meetingWithName = event.What.Name;
                eventWrapper.meetingWithFirstName = event.What.FirstName;
                eventWrapper.meetingWithLastName = event.What.LastName;
                
                for (Integer i = 0; i < contacts.size(); i++) {
                    Contact contact = contacts.get(i);
                    if(contact.Name == event.What.Name){
                        eventWrapper.meetingWithDOB = contact.Birthdate;
                        eventWrapper.meetingWithPreferredFirstName = contact.xDO_Preferred_First_Name__c;
                        eventWrapper.meetingWithPreferredLastName = contact.xDO_Preferred_Last_Name__c;
                        eventWrapper.meetingWithImageURL = contact.xDO_Image_URL__c;
                        break;
                    }
                }

                eventWrapper.subject = event.xDO_Subject__c;
                eventWrapper.subjectDescription = event.xDO_Subject_Description__c;
                // eventWrapper.eventNotificationCleared = event.xDO_Event_Notification_Cleared;
                eventWrapper.startDateTime = event.StartDateTime;
                eventWrapper.endDateTime = event.EndDateTime;
                eventWrapper.activityDate = event.ActivityDate;
                eventWrapper.durationInMinutes = event.DurationInMinutes;
                eventWrapper.appointmentWithin24Hours = appointmentWithin24Hours;
                if(event.StartDateTime < System.now()){
                    eventWrapper.appointmentStarted = true;
                } else{
                    eventWrapper.appointmentStarted = false;
                }
                if(event.EndDateTime < System.now()){
                    eventWrapper.appointmentEnded = true;
                } else if(event.xDO_Call_Completed__c == true){
                    eventWrapper.appointmentEnded = true;
                } else{
                    eventWrapper.appointmentEnded = false;
                }
                eventWrapper.appointmentToday = appointmentToday;
                eventWrapper.formattedDate = getMonthName(event.StartDateTime.month()) + ' ' + event.StartDateTime.day() + ', ' + event.StartDateTime.year();

                Integer startHour = event.StartDateTime.hour();
                String amPM = 'AM';
                if(startHour >= 12){
                    startHour -= 12;
                    if(startHour == 0){
                        startHour = 12;
                    }
                    amPM = 'PM';
                }
                if(startHour == 0){
                    startHour = 12;
                }
                String minutes = String.valueOf(event.startDateTime.minute());
                if(event.startDateTime.minute() == 0){
                    minutes = 0 + minutes;
                }
                eventWrapper.formattedStartTime = startHour + ':' + minutes + ' ' + amPM;

                String fullTimeZone = UserInfo.getTimeZone().getDisplayName();
                String timeZone;
                if(fullTimeZone.contains('Eastern Standard Time')){
                    timeZone = 'EST';
                } else if(fullTimeZone.contains('Central Standard Time')){
                    timeZone = 'CST';
                }
                else if(fullTimeZone.contains('Mountain Standard Time')){
                    timeZone = 'MST';
                }
                else if(fullTimeZone.contains('Pacific Standard Time')){
                    timeZone = 'PST';
                }
                else{
                    timeZone = 'Other time zone';
                }
                eventWrapper.timeZone = timeZone;
                currentAppointments.add(eventWrapper);
            }
        }
        catch(QueryException e){
            System.debug('error: ' + e);
        }
        return currentAppointments;
    }

    @AuraEnabled
    public static String endVideoCall(String eventId){
        Event event = [SELECT Id, xDO_Call_Completed__c FROM Event WHERE Id = :eventId LIMIT 1];
        event.xDO_Call_Completed__c = true;
        String eventUpdated = 'Event updated!';
        try{
            update event;
        } catch(DmlException e){
            eventUpdated = 'Error updating event: ' + e.getMessage();
            System.debug('Error updating event: ' + e.getMessage());
        }
        return eventUpdated;
    }

    public static String getMonthName(Integer monthNumber){
        if(monthNumber == 1){
            return 'January';
        } else if (monthNumber == 2){
            return 'February';
        }
        else if (monthNumber == 3){
            return 'March';
        }
        else if (monthNumber == 4){
            return 'April';
        }
        else if (monthNumber == 5){
            return 'May';
        }
        else if (monthNumber == 6){
            return 'June';
        }
        else if (monthNumber == 7){
            return 'July';
        }
        else if (monthNumber == 8){
            return 'August';
        }
        else if (monthNumber == 9){
            return 'September';
        }
        else if (monthNumber == 10){
            return 'October';
        }
        else if (monthNumber == 11){
            return 'November';
        }
        else if (monthNumber == 12){
            return 'December';
        }
        return null;
    }
}