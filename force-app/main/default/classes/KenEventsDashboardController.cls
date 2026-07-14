public with sharing class KenEventsDashboardController {

    private static final Integer MAX_CHART_ITEMS = 15;
    private static final Integer MAX_EVENT_LIST  = 200;

    private static final String[] MONTH_NAMES = new String[]{
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
    };

    // ── Inner wrapper classes ────────────────────────────────────────────────

    public class ChartItem implements Comparable {
        @AuraEnabled public String  label;
        @AuraEnabled public Integer value;

        public ChartItem(String lbl, Integer val) {
            this.label = String.isBlank(lbl) ? 'Not Specified' : lbl;
            this.value = val == null ? 0 : val;
        }

        public Integer compareTo(Object other) {
            ChartItem o = (ChartItem) other;
            if (this.value > o.value) return -1;
            if (this.value < o.value) return  1;
            return 0;
        }
    }

    public class SummaryStats {
        @AuraEnabled public Integer totalEvents        = 0;
        @AuraEnabled public Integer totalRegistrations = 0;
        @AuraEnabled public Integer publishedEvents    = 0;
        @AuraEnabled public Integer cancelledBookings  = 0;
    }

    public class FilterOptions {
        @AuraEnabled public List<PicklistOption> eventTypes = new List<PicklistOption>();
        @AuraEnabled public List<PicklistOption> statuses   = new List<PicklistOption>();
        @AuraEnabled public List<PicklistOption> years      = new List<PicklistOption>();
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String lbl, String val) { this.label = lbl; this.value = val; }
    }

    public class EventListRecord {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  eventType;
        @AuraEnabled public String  status;
        @AuraEnabled public String  startDate;
        @AuraEnabled public String  location;
        @AuraEnabled public Integer registrations;
    }

    public class BookingListRecord {
        @AuraEnabled public String  id;
        @AuraEnabled public String  attendeeName;
        @AuraEnabled public String  eventName;
        @AuraEnabled public String  bookingStatus;
        @AuraEnabled public String  bookedDate;
        @AuraEnabled public Integer attendeeCount;
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static String buildWhereClause(String fType, String fStatus, String fYear) {
        String w = 'Is_Archived__c = false';
        if (String.isNotBlank(fType))
            w += ' AND Event_Type__c INCLUDES (\'' + String.escapeSingleQuotes(fType) + '\')';
        if (String.isNotBlank(fStatus))
            w += ' AND Event_Status__c = \'' + String.escapeSingleQuotes(fStatus) + '\'';
        if (String.isNotBlank(fYear)) {
            try {
                Integer yr = Integer.valueOf(fYear);
                w += ' AND Start_Date__c >= ' + yr + '-01-01 AND Start_Date__c <= ' + yr + '-12-31';
            } catch (Exception e) { /* invalid year — skip */ }
        }
        return w;
    }

    private static List<Ken_Event_Master__c> queryEvents(String fType, String fStatus, String fYear, String extraFields) {
        String fields = 'Id' + (String.isNotBlank(extraFields) ? ', ' + extraFields : '');
        String q = 'SELECT ' + fields + ' FROM Ken_Event_Master__c WHERE '
                 + buildWhereClause(fType, fStatus, fYear) + ' LIMIT 50000';
        return Database.query(q);
    }

    private static Set<Id> toIdSet(List<Ken_Event_Master__c> events) {
        Set<Id> ids = new Set<Id>();
        for (Ken_Event_Master__c e : events) ids.add(e.Id);
        return ids;
    }

    private static Set<Id> getSessionIds(Set<Id> eventIds) {
        Set<Id> sIds = new Set<Id>();
        if (eventIds == null || eventIds.isEmpty()) return sIds;
        for (Ken_Schedule_Sessions__c s : [
            SELECT Id FROM Ken_Schedule_Sessions__c
            WHERE Event_Reference__c IN :eventIds LIMIT 50000
        ]) sIds.add(s.Id);
        return sIds;
    }

    private static List<ChartItem> trimChartItems(List<ChartItem> items) {
        if (items.size() <= MAX_CHART_ITEMS) return items;
        List<ChartItem> trimmed = new List<ChartItem>();
        for (Integer i = 0; i < MAX_CHART_ITEMS; i++) trimmed.add(items[i]);
        return trimmed;
    }

    private static List<ChartItem> mapToChartItems(Map<String, Integer> m) {
        List<ChartItem> items = new List<ChartItem>();
        for (String k : m.keySet()) items.add(new ChartItem(k, m.get(k)));
        items.sort();
        return trimChartItems(items);
    }

    private static Map<String, Integer> parseMultiselect(List<SObject> records, String fieldName) {
        Map<String, Integer> m = new Map<String, Integer>();
        for (SObject s : records) {
            String raw = (String) s.get(fieldName);
            if (String.isBlank(raw)) {
                m.put('Not Specified', (m.containsKey('Not Specified') ? m.get('Not Specified') : 0) + 1);
                continue;
            }
            for (String t : raw.split(';')) {
                String k = t.trim();
                if (String.isBlank(k)) continue;
                m.put(k, (m.containsKey(k) ? m.get(k) : 0) + 1);
            }
        }
        return m;
    }

    // ── getFilterOptions ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        try {
            FilterOptions opts = new FilterOptions();

            // Event types — parse multipicklist from actual data
            Set<String> typeSet = new Set<String>();
            for (Ken_Event_Master__c e : [
                SELECT Event_Type__c FROM Ken_Event_Master__c
                WHERE Event_Type__c != null AND Is_Archived__c = false LIMIT 50000
            ]) {
                for (String t : e.Event_Type__c.split(';')) {
                    String k = t.trim();
                    if (String.isNotBlank(k)) typeSet.add(k);
                }
            }
            List<String> sortedTypes = new List<String>(typeSet);
            sortedTypes.sort();
            for (String t : sortedTypes) opts.eventTypes.add(new PicklistOption(t, t));

            // Statuses — fixed known picklist values
            for (String s : new String[]{
                'Approved','In Progress','In review','Pending Approval',
                'Submitted','Rejected','Cancelled'
            }) opts.statuses.add(new PicklistOption(s, s));

            // Years — from actual Start_Date__c data
            Set<String> yearSet = new Set<String>();
            for (Ken_Event_Master__c e : [
                SELECT Start_Date__c FROM Ken_Event_Master__c
                WHERE Start_Date__c != null AND Is_Archived__c = false LIMIT 50000
            ]) yearSet.add(String.valueOf(e.Start_Date__c.year()));
            List<String> sortedYears = new List<String>(yearSet);
            sortedYears.sort();
            for (String yr : sortedYears) opts.years.add(new PicklistOption(yr, yr));

            return opts;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getSummaryStats ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String filterType, String filterStatus, String filterYear) {
        try {
            SummaryStats stats = new SummaryStats();
            List<Ken_Event_Master__c> events = queryEvents(filterType, filterStatus, filterYear, 'Is_Published__c');
            stats.totalEvents = events.size();
            for (Ken_Event_Master__c e : events) if (e.Is_Published__c) stats.publishedEvents++;

            Set<Id> sessionIds = getSessionIds(toIdSet(events));
            if (!sessionIds.isEmpty()) {
                stats.totalRegistrations = [
                    SELECT COUNT() FROM Ken_Event_Booking__c
                    WHERE Schedules_Sessions__c IN :sessionIds AND Type__c = 'Registered'
                ];
                stats.cancelledBookings = [
                    SELECT COUNT() FROM Ken_Event_Booking__c
                    WHERE Schedules_Sessions__c IN :sessionIds AND Type__c = 'Cancelled'
                ];
            }
            return stats;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getEventsByStatus ────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getEventsByStatus(String filterType, String filterStatus, String filterYear) {
        try {
            String wClause = buildWhereClause(filterType, filterStatus, filterYear);
            String q = 'SELECT Event_Status__c, COUNT(Id) cnt FROM Ken_Event_Master__c WHERE '
                     + wClause + ' GROUP BY Event_Status__c ORDER BY COUNT(Id) DESC LIMIT 50';
            List<ChartItem> items = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q))
                items.add(new ChartItem((String)ar.get('Event_Status__c'), (Integer)ar.get('cnt')));
            return items;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getEventsByType (multipicklist — in-memory parse) ────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getEventsByType(String filterType, String filterStatus, String filterYear) {
        try {
            List<SObject> records = queryEvents(filterType, filterStatus, filterYear, 'Event_Type__c');
            return mapToChartItems(parseMultiselect(records, 'Event_Type__c'));
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getEventPricingDistribution ──────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getEventPricingDistribution(String filterType, String filterStatus, String filterYear) {
        try {
            String wClause = buildWhereClause(filterType, filterStatus, filterYear);
            String q = 'SELECT No_Fee__c, COUNT(Id) cnt FROM Ken_Event_Master__c WHERE '
                     + wClause + ' GROUP BY No_Fee__c';
            List<ChartItem> items = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q)) {
                Boolean isFree = (Boolean) ar.get('No_Fee__c');
                items.add(new ChartItem(isFree == true ? 'Free' : 'Paid', (Integer) ar.get('cnt')));
            }
            return items;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getBookingStatusBreakdown ────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getBookingStatusBreakdown(String filterType, String filterStatus, String filterYear) {
        try {
            Set<Id> sessionIds = getSessionIds(toIdSet(queryEvents(filterType, filterStatus, filterYear, null)));
            if (sessionIds.isEmpty()) return new List<ChartItem>();
            List<ChartItem> items = new List<ChartItem>();
            for (AggregateResult ar : [
                SELECT Type__c, COUNT(Id) cnt FROM Ken_Event_Booking__c
                WHERE Schedules_Sessions__c IN :sessionIds
                GROUP BY Type__c ORDER BY COUNT(Id) DESC
            ]) items.add(new ChartItem((String)ar.get('Type__c'), (Integer)ar.get('cnt')));
            return items;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getRegistrationTrends ────────────────────────────────────────────────
    // Groups by the session's event year (Start_Date__c) so backdated event data
    // shows meaningful multi-year trends regardless of when bookings were created.

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getRegistrationTrends(String filterType, String filterStatus, String filterYear) {
        try {
            Set<Id> sessionIds = getSessionIds(toIdSet(queryEvents(filterType, filterStatus, filterYear, null)));
            if (sessionIds.isEmpty()) return new List<ChartItem>();

            // Map each session to its event's year
            Map<Id, Integer> sessionYearMap = new Map<Id, Integer>();
            for (Ken_Schedule_Sessions__c s : [
                SELECT Id, Start_Date__c FROM Ken_Schedule_Sessions__c
                WHERE Id IN :sessionIds AND Start_Date__c != null
            ]) sessionYearMap.put(s.Id, s.Start_Date__c.year());

            // Aggregate registered bookings per session, then roll up by year
            Map<Integer, Integer> yearCounts = new Map<Integer, Integer>();
            for (AggregateResult ar : [
                SELECT Schedules_Sessions__c sid, COUNT(Id) cnt FROM Ken_Event_Booking__c
                WHERE Schedules_Sessions__c IN :sessionIds AND Type__c = 'Registered'
                GROUP BY Schedules_Sessions__c
            ]) {
                Integer yr = sessionYearMap.get((Id) ar.get('sid'));
                if (yr == null) continue;
                yearCounts.put(yr, (yearCounts.containsKey(yr) ? yearCounts.get(yr) : 0) + (Integer) ar.get('cnt'));
            }

            List<Integer> sortedYrs = new List<Integer>(yearCounts.keySet());
            sortedYrs.sort();
            List<ChartItem> items = new List<ChartItem>();
            for (Integer yr : sortedYrs) items.add(new ChartItem(String.valueOf(yr), yearCounts.get(yr)));
            return items;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getTopEventsByRegistrations ──────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getTopEventsByRegistrations(String filterType, String filterStatus, String filterYear) {
        try {
            Set<Id> eventIds   = toIdSet(queryEvents(filterType, filterStatus, filterYear, null));
            Set<Id> sessionIds = getSessionIds(eventIds);
            if (sessionIds.isEmpty()) return new List<ChartItem>();

            // Bookings per session
            Map<Id, Integer> sessionBookings = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Schedules_Sessions__c sid, COUNT(Id) cnt FROM Ken_Event_Booking__c
                WHERE Schedules_Sessions__c IN :sessionIds AND Type__c = 'Registered'
                GROUP BY Schedules_Sessions__c
            ]) sessionBookings.put((Id)ar.get('sid'), (Integer)ar.get('cnt'));
            if (sessionBookings.isEmpty()) return new List<ChartItem>();

            // Map sessions → events
            Map<Id, Id> sessionToEvent = new Map<Id, Id>();
            for (Ken_Schedule_Sessions__c s : [
                SELECT Id, Event_Reference__c FROM Ken_Schedule_Sessions__c
                WHERE Id IN :sessionBookings.keySet()
            ]) sessionToEvent.put(s.Id, s.Event_Reference__c);

            // Aggregate per event
            Map<Id, Integer> eventBookings = new Map<Id, Integer>();
            for (Id sid : sessionBookings.keySet()) {
                Id eid = sessionToEvent.get(sid);
                if (eid == null) continue;
                eventBookings.put(eid, (eventBookings.containsKey(eid) ? eventBookings.get(eid) : 0) + sessionBookings.get(sid));
            }

            // Sort descending and take top MAX_CHART_ITEMS
            List<ChartItem> all = new List<ChartItem>();
            for (Id eid : eventBookings.keySet()) all.add(new ChartItem(String.valueOf(eid), eventBookings.get(eid)));
            all.sort();
            all = trimChartItems(all);

            // Resolve event names
            Set<Id> topIds = new Set<Id>();
            for (ChartItem ci : all) topIds.add(Id.valueOf(ci.label));
            Map<Id, String> names = new Map<Id, String>();
            for (Ken_Event_Master__c e : [SELECT Id, Name FROM Ken_Event_Master__c WHERE Id IN :topIds])
                names.put(e.Id, e.Name);

            List<ChartItem> items = new List<ChartItem>();
            for (ChartItem ci : all) {
                Id eid = Id.valueOf(ci.label);
                items.add(new ChartItem(names.containsKey(eid) ? names.get(eid) : ci.label, ci.value));
            }
            return items;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getTargetAudienceBreakdown (multipicklist — in-memory parse) ─────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getTargetAudienceBreakdown(String filterType, String filterStatus, String filterYear) {
        try {
            List<SObject> records = queryEvents(filterType, filterStatus, filterYear, 'Target_Audience_Applicable__c');
            return mapToChartItems(parseMultiselect(records, 'Target_Audience_Applicable__c'));
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getMonthlyEventActivity ──────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getMonthlyEventActivity(String filterType, String filterStatus, String filterYear) {
        try {
            String wClause = buildWhereClause(filterType, filterStatus, filterYear) + ' AND Start_Date__c != null';
            String q = 'SELECT CALENDAR_YEAR(Start_Date__c) yr, CALENDAR_MONTH(Start_Date__c) mon, COUNT(Id) cnt'
                     + ' FROM Ken_Event_Master__c WHERE ' + wClause
                     + ' GROUP BY CALENDAR_YEAR(Start_Date__c), CALENDAR_MONTH(Start_Date__c)'
                     + ' ORDER BY CALENDAR_YEAR(Start_Date__c), CALENDAR_MONTH(Start_Date__c) LIMIT 36';
            List<ChartItem> items = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q)) {
                Integer mon = (Integer) ar.get('mon');
                Integer yr  = (Integer) ar.get('yr');
                String  lbl = MONTH_NAMES[mon - 1] + ' ' + yr;
                items.add(new ChartItem(lbl, (Integer) ar.get('cnt')));
            }
            return items;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getEventLocationDistribution ─────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getEventLocationDistribution(String filterType, String filterStatus, String filterYear) {
        try {
            String wClause = buildWhereClause(filterType, filterStatus, filterYear)
                           + ' AND Location__c != null AND Location__c != \'\'';
            String q = 'SELECT Location__c, COUNT(Id) cnt FROM Ken_Event_Master__c WHERE '
                     + wClause + ' GROUP BY Location__c ORDER BY COUNT(Id) DESC LIMIT 50';
            List<ChartItem> items = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q))
                items.add(new ChartItem((String)ar.get('Location__c'), (Integer)ar.get('cnt')));
            return trimChartItems(items);
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getTopRecurringAttendees ──────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getTopRecurringAttendees(String filterType, String filterStatus, String filterYear) {
        try {
            Set<Id> sessionIds = getSessionIds(toIdSet(queryEvents(filterType, filterStatus, filterYear, null)));
            if (sessionIds.isEmpty()) return new List<ChartItem>();

            List<AggregateResult> results = [
                SELECT Person_Account__c pid, COUNT(Id) cnt FROM Ken_Event_Booking__c
                WHERE Schedules_Sessions__c IN :sessionIds
                  AND Type__c = 'Registered'
                  AND Person_Account__c != null
                GROUP BY Person_Account__c
                ORDER BY COUNT(Id) DESC
                LIMIT 15
            ];
            if (results.isEmpty()) return new List<ChartItem>();

            Set<Id> accountIds = new Set<Id>();
            for (AggregateResult ar : results) accountIds.add((Id) ar.get('pid'));
            Map<Id, String> accountNames = new Map<Id, String>();
            for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :accountIds])
                accountNames.put(a.Id, a.Name);

            List<ChartItem> items = new List<ChartItem>();
            for (AggregateResult ar : results) {
                Id     pid = (Id) ar.get('pid');
                String nm  = accountNames.containsKey(pid) ? accountNames.get(pid) : String.valueOf(pid);
                items.add(new ChartItem(nm, (Integer) ar.get('cnt')));
            }
            return items;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getBookingList (modal drill-down — bookings) ────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<BookingListRecord> getBookingList(
            String dimension, String dimensionValue,
            String filterType, String filterStatus, String filterYear) {
        try {
            List<Ken_Event_Master__c> events = queryEvents(filterType, filterStatus, filterYear, 'Name');
            Set<Id> eventIds = toIdSet(events);
            if (eventIds.isEmpty()) return new List<BookingListRecord>();

            // For top_events, narrow to the specific event by name
            if (dimension == 'top_events' && String.isNotBlank(dimensionValue)) {
                Set<Id> matched = new Set<Id>();
                for (Ken_Event_Master__c e : events) {
                    if (e.Name == dimensionValue) matched.add(e.Id);
                }
                eventIds = matched;
                if (eventIds.isEmpty()) return new List<BookingListRecord>();
            }

            Set<Id> sessionIds = getSessionIds(eventIds);
            if (sessionIds.isEmpty()) return new List<BookingListRecord>();

            // For trends, narrow sessions to the clicked year
            if (dimension == 'trends' && String.isNotBlank(dimensionValue)) {
                try {
                    Integer yr = Integer.valueOf(dimensionValue);
                    Date d1 = Date.newInstance(yr, 1, 1);
                    Date d2 = Date.newInstance(yr, 12, 31);
                    Set<Id> yearSessions = new Set<Id>();
                    for (Ken_Schedule_Sessions__c s : [
                        SELECT Id FROM Ken_Schedule_Sessions__c
                        WHERE Id IN :sessionIds
                          AND Start_Date__c >= :d1
                          AND Start_Date__c <= :d2
                    ]) yearSessions.add(s.Id);
                    sessionIds = yearSessions;
                } catch (Exception ex) { /* invalid year — skip */ }
                if (sessionIds.isEmpty()) return new List<BookingListRecord>();
            }

            String bType = (dimension == 'cancellations') ? 'Cancelled' : 'Registered';
            List<Ken_Event_Booking__c> bookings = [
                SELECT Id, Type__c, Booked_for_No_of_Attendees__c,
                       Person_Account__r.Name,
                       Schedules_Sessions__r.Event_Reference__r.Name,
                       Schedules_Sessions__r.Start_Date__c
                FROM Ken_Event_Booking__c
                WHERE Schedules_Sessions__c IN :sessionIds
                  AND Type__c = :bType
                ORDER BY Schedules_Sessions__r.Start_Date__c DESC NULLS LAST
                LIMIT 500
            ];

            List<BookingListRecord> records = new List<BookingListRecord>();
            for (Ken_Event_Booking__c b : bookings) {
                BookingListRecord r = new BookingListRecord();
                r.id            = b.Id;
                r.attendeeName  = (b.Person_Account__r != null)
                                  ? b.Person_Account__r.Name : '—';
                r.eventName     = (b.Schedules_Sessions__r != null
                                   && b.Schedules_Sessions__r.Event_Reference__r != null)
                                  ? b.Schedules_Sessions__r.Event_Reference__r.Name : '—';
                r.bookingStatus = String.isNotBlank(b.Type__c) ? b.Type__c : '—';
                r.bookedDate    = (b.Schedules_Sessions__r != null
                                   && b.Schedules_Sessions__r.Start_Date__c != null)
                                  ? b.Schedules_Sessions__r.Start_Date__c.format() : '—';
                r.attendeeCount = (b.Booked_for_No_of_Attendees__c != null)
                                  ? Integer.valueOf(b.Booked_for_No_of_Attendees__c) : 1;
                records.add(r);
            }
            return records;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    // ── getEventList (modal drill-down) ──────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<EventListRecord> getEventList(
            String dimension, String dimensionValue,
            String filterType, String filterStatus, String filterYear) {
        try {
            String wClause = buildWhereClause(filterType, filterStatus, filterYear);

            if (String.isNotBlank(dimension) && String.isNotBlank(dimensionValue)) {
                if (dimension == 'status') {
                    wClause += ' AND Event_Status__c = \'' + String.escapeSingleQuotes(dimensionValue) + '\'';
                } else if (dimension == 'type') {
                    wClause += ' AND Event_Type__c INCLUDES (\'' + String.escapeSingleQuotes(dimensionValue) + '\')';
                } else if (dimension == 'pricing') {
                    wClause += (dimensionValue == 'Free' ? ' AND No_Fee__c = true' : ' AND No_Fee__c = false');
                } else if (dimension == 'location') {
                    wClause += ' AND Location__c = \'' + String.escapeSingleQuotes(dimensionValue) + '\'';
                } else if (dimension == 'audience') {
                    wClause += ' AND Target_Audience_Applicable__c INCLUDES (\'' + String.escapeSingleQuotes(dimensionValue) + '\')';
                } else if (dimension == 'top_events') {
                    wClause += ' AND Name = \'' + String.escapeSingleQuotes(dimensionValue) + '\'';
                } else if (dimension == 'trends') {
                    try {
                        Integer yr = Integer.valueOf(dimensionValue);
                        wClause += ' AND Start_Date__c >= ' + yr + '-01-01 AND Start_Date__c <= ' + yr + '-12-31';
                    } catch (Exception ex) { /* skip invalid year */ }
                }
            }

            String q = 'SELECT Id, Name, Event_Type__c, Event_Status__c, Start_Date__c, Location__c, Is_Published__c'
                     + ' FROM Ken_Event_Master__c WHERE ' + wClause
                     + ' ORDER BY Start_Date__c DESC NULLS LAST LIMIT ' + MAX_EVENT_LIST;
            List<Ken_Event_Master__c> events = Database.query(q);

            // Fetch registration counts via sessions
            Set<Id> evIds      = toIdSet(events);
            Set<Id> sessionIds = getSessionIds(evIds);
            Map<Id, Integer> regCounts = new Map<Id, Integer>();
            if (!sessionIds.isEmpty()) {
                Map<Id, Id> sessionToEvent = new Map<Id, Id>();
                for (Ken_Schedule_Sessions__c s : [
                    SELECT Id, Event_Reference__c FROM Ken_Schedule_Sessions__c WHERE Id IN :sessionIds
                ]) sessionToEvent.put(s.Id, s.Event_Reference__c);

                for (AggregateResult ar : [
                    SELECT Schedules_Sessions__c sid, COUNT(Id) cnt FROM Ken_Event_Booking__c
                    WHERE Schedules_Sessions__c IN :sessionIds AND Type__c = 'Registered'
                    GROUP BY Schedules_Sessions__c
                ]) {
                    Id eid = sessionToEvent.get((Id)ar.get('sid'));
                    if (eid != null)
                        regCounts.put(eid, (regCounts.containsKey(eid) ? regCounts.get(eid) : 0) + (Integer)ar.get('cnt'));
                }
            }

            List<EventListRecord> records = new List<EventListRecord>();
            for (Ken_Event_Master__c e : events) {
                EventListRecord r = new EventListRecord();
                r.id            = e.Id;
                r.name          = e.Name;
                r.eventType     = String.isNotBlank(e.Event_Type__c) ? e.Event_Type__c.replace(';', ', ') : '—';
                r.status        = String.isNotBlank(e.Event_Status__c) ? e.Event_Status__c : '—';
                r.startDate     = e.Start_Date__c != null ? e.Start_Date__c.format() : '—';
                r.location      = String.isNotBlank(e.Location__c) ? e.Location__c : '—';
                r.registrations = regCounts.containsKey(e.Id) ? regCounts.get(e.Id) : 0;
                records.add(r);
            }
            return records;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }
}