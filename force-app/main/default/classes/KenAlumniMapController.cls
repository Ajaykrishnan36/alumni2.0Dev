/**
 * Serves aggregated alumni location counts for the portal map view (kenAlumniMap).
 * Counts are grouped by country/state/city on the alumni's mailing Ken_Address__c
 * records; coordinate resolution happens client-side against a bundled gazetteer,
 * so no external geocoding service is involved.
 */
public without sharing class KenAlumniMapController {
    private static final String CONSTITUENT_ROLE_TYPE_ALUMNI = 'Alumni';
    private static final String ADDRESS_TYPE_MAILING = 'Mailing';
    private static final Integer MAX_LOCATION_ROWS = 2000;
    private static final Integer MAX_DUPLICATE_PEOPLE = 5000;
    private static final Integer MAX_DUPLICATE_ROWS = 20000;
    private static final String KEY_SEPARATOR = String.fromCharArray(new List<Integer>{ 1 });

    public class LocationCount {
        @AuraEnabled public String country;
        @AuraEnabled public String state;
        @AuraEnabled public String city;
        @AuraEnabled public Integer total;
    }

    /**
     * A single alumnus surfaced in the map's location sidebar. personId is the
     * Person Account Id — it drives both the admin Alumni 360 (polymorphic
     * recordId) and the portal network detail view.
     */
    public class AlumniAtLocation {
        @AuraEnabled public String personId;
        @AuraEnabled public String constituentRoleId;
        @AuraEnabled public String name;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String profileImage;
    }

    /**
     * People whose mailing address falls in the clicked map location. The LWC
     * passes the raw City__c / Country__c strings that composed the clicked
     * bubble (a single bubble can merge several source spellings that normalise
     * to the same place), so we match those exact values rather than re-deriving
     * them here. Guests get nothing — the portal shows them a login/register
     * prompt instead — so the query is also skipped server-side for the guest
     * user, preventing a direct-call bypass.
     */
    @AuraEnabled(cacheable=true)
    public static List<AlumniAtLocation> getAlumniAtLocation(List<String> cities, List<String> countries) {
        List<AlumniAtLocation> out = new List<AlumniAtLocation>();
        if (UserInfo.getUserType() == 'Guest') {
            return out;
        }
        if (cities == null || cities.isEmpty()) {
            return out;
        }

        Set<String> citySet = new Set<String>(cities);
        Set<String> countrySet = (countries == null) ? new Set<String>() : new Set<String>(countries);
        Map<Id, AlumniAtLocation> byPerson = new Map<Id, AlumniAtLocation>();

        String orgDomain = URL.getOrgDomainUrl().toExternalForm();
        for (Ken_Address__c addr : [
            SELECT Person_Account__c, Person_Account__r.Name, Person_Account__r.PhotoUrl,
                   City__c, State__c, Country__c
            FROM Ken_Address__c
            WHERE Person_Account__c IN (
                    SELECT PersonId
                    FROM ConstituentRole
                    WHERE RoleType = :CONSTITUENT_ROLE_TYPE_ALUMNI
                      AND PersonId != null
                  )
              AND Address_Type__c = :ADDRESS_TYPE_MAILING
              AND City__c IN :citySet
            WITH SYSTEM_MODE
            ORDER BY Person_Account__r.Name
            LIMIT :MAX_LOCATION_ROWS
        ]) {
            if (!countrySet.isEmpty() && addr.Country__c != null && !countrySet.contains(addr.Country__c)) {
                continue;
            }
            if (addr.Person_Account__c == null || byPerson.containsKey(addr.Person_Account__c)) {
                continue;
            }
            AlumniAtLocation person = new AlumniAtLocation();
            person.personId = addr.Person_Account__c;
            person.name = addr.Person_Account__r.Name;
            person.subtitle = buildSubtitle(addr.City__c, addr.State__c, addr.Country__c);
            if (String.isNotBlank(addr.Person_Account__r.PhotoUrl)) {
                person.profileImage = orgDomain + addr.Person_Account__r.PhotoUrl;
            }
            byPerson.put(addr.Person_Account__c, person);
            out.add(person);
        }

        // Stamp each person's Alumni ConstituentRole Id — the admin Alumni 360
        // resolves cleanest from the CR (portal-registered alumni may have no
        // Ken_Alumni_CRM__c row to hop to from the Account alone).
        if (!byPerson.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT Id, PersonId
                FROM ConstituentRole
                WHERE RoleType = :CONSTITUENT_ROLE_TYPE_ALUMNI
                  AND PersonId IN :byPerson.keySet()
            WITH SYSTEM_MODE
            ]) {
                AlumniAtLocation person = byPerson.get(cr.PersonId);
                if (person != null && person.constituentRoleId == null) {
                    person.constituentRoleId = cr.Id;
                }
            }

            Map<Id, String> photoByAccountId = KenGroupFeedService.lookupProfileImages(byPerson.keySet());
            for (Id accId : photoByAccountId.keySet()) {
                AlumniAtLocation person = byPerson.get(accId);
                if (person != null && String.isNotBlank(photoByAccountId.get(accId))) {
                    person.profileImage = photoByAccountId.get(accId);
                }
            }
        }
        return out;
    }

    private static String buildSubtitle(String city, String state, String country) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        if (String.isNotBlank(country)) parts.add(country);
        return String.join(parts, ', ');
    }

    /**
     * Returns alumni counts grouped by country, state and city of their mailing
     * Ken_Address__c record (the current-address type in this schema; the only
     * other picklist value is Permanent). Scope matches the admin regional
     * demographics: every person with an Alumni ConstituentRole, regardless of
     * portal registration status. Rows are capped at MAX_LOCATION_ROWS ordered
     * by descending count, so the long tail of single-alumni locations is what
     * gets truncated first.
     *
     * Two governor-limit rules drive the shape of this method, both measured
     * against KJS production (152,784 alumni roles, 138,280 mailing addresses):
     *
     * 1. The alumni scope MUST be a semi-join. Materialising the PersonIds into
     *    a bound Set costs one query row per alumnus and on its own exhausts the
     *    50,000-row transaction limit.
     * 2. COUNT_DISTINCT charges every row it scans against that limit, while a
     *    plain GROUP BY charges only the groups it returns (1,000 here versus
     *    138,280). So the grouping uses COUNT(Id) and the handful of people who
     *    hold more than one mailing address are subtracted afterwards, which
     *    reproduces COUNT_DISTINCT exactly at a cost of groups + duplicates.
     *
     * System.LimitException is uncatchable, so exceeding either limit takes the
     * whole map down rather than degrading it.
     */
    @AuraEnabled(cacheable=true)
    public static List<LocationCount> getAlumniLocationCounts() {
        List<LocationCount> results = new List<LocationCount>();
        Map<String, LocationCount> byLocation = new Map<String, LocationCount>();

        for (AggregateResult row : [
            SELECT Country__c country,
                   State__c state,
                   City__c city,
                   COUNT(Id) cnt
            FROM Ken_Address__c
            WHERE Person_Account__c IN (
                    SELECT PersonId
                    FROM ConstituentRole
                    WHERE RoleType = :CONSTITUENT_ROLE_TYPE_ALUMNI
                      AND PersonId != null
                  )
              AND Address_Type__c = :ADDRESS_TYPE_MAILING
              AND (Country__c != null OR City__c != null)
            WITH SYSTEM_MODE
            GROUP BY Country__c, State__c, City__c
            ORDER BY COUNT(Id) DESC
            LIMIT :MAX_LOCATION_ROWS
        ]) {
            LocationCount lc = new LocationCount();
            lc.country = (String) row.get('country');
            lc.state = (String) row.get('state');
            lc.city = (String) row.get('city');
            lc.total = (Integer) row.get('cnt');
            results.add(lc);
            byLocation.put(locationKey(lc.country, lc.state, lc.city), lc);
        }

        if (!results.isEmpty()) {
            subtractRepeatedAddresses(byLocation);
        }
        return results;
    }

    /**
     * Restores COUNT_DISTINCT semantics on the counts built by
     * getAlumniLocationCounts. Only people with more than one qualifying mailing
     * address can inflate a group, and HAVING keeps that lookup priced at the
     * number of such people (zero in every org measured so far), so the two
     * queries here normally cost nothing at all.
     */
    private static void subtractRepeatedAddresses(Map<String, LocationCount> byLocation) {
        Set<Id> personIds = new Set<Id>();
        for (AggregateResult row : [
            SELECT Person_Account__c personId
            FROM Ken_Address__c
            WHERE Person_Account__c IN (
                    SELECT PersonId
                    FROM ConstituentRole
                    WHERE RoleType = :CONSTITUENT_ROLE_TYPE_ALUMNI
                      AND PersonId != null
                  )
              AND Address_Type__c = :ADDRESS_TYPE_MAILING
              AND (Country__c != null OR City__c != null)
            WITH SYSTEM_MODE
            GROUP BY Person_Account__c
            HAVING COUNT(Id) > 1
            LIMIT :MAX_DUPLICATE_PEOPLE
        ]) {
            personIds.add((Id) row.get('personId'));
        }
        if (personIds.isEmpty()) {
            return;
        }

        Set<String> counted = new Set<String>();
        for (Ken_Address__c addr : [
            SELECT Person_Account__c, City__c, State__c, Country__c
            FROM Ken_Address__c
            WHERE Person_Account__c IN :personIds
              AND Address_Type__c = :ADDRESS_TYPE_MAILING
              AND (Country__c != null OR City__c != null)
            WITH SECURITY_ENFORCED
            LIMIT :MAX_DUPLICATE_ROWS
        ]) {
            String key = locationKey(addr.Country__c, addr.State__c, addr.City__c);
            LocationCount lc = byLocation.get(key);
            if (lc == null) {
                continue;
            }
            if (counted.add(String.valueOf(addr.Person_Account__c) + KEY_SEPARATOR + key)) {
                continue;
            }
            lc.total = lc.total - 1;
        }
    }

    private static String locationKey(String country, String state, String city) {
        return String.valueOf(country) + KEY_SEPARATOR
            + String.valueOf(state) + KEY_SEPARATOR
            + String.valueOf(city);
    }

    /**
     * CARTO requires an API key on its raster basemaps, so the map asks for one
     * before it builds its tile layer. The key lives in Ken_Alm_Org_Parameters__c
     * rather than as an LWC constant because each institution's org holds its
     * own value and it has to be rotatable without a deploy.
     *
     * Blank is a supported state, not an error: the map still draws, CARTO just
     * stamps a watermark across every tile. Returning null for that case keeps
     * the decision on the client, which appends the key only when there is one.
     */
    @AuraEnabled(cacheable=true)
    public static String getBasemapKey() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        return (params == null || String.isBlank(params.Carto_Basemap_Client_Id__c))
            ? null
            : params.Carto_Basemap_Client_Id__c.trim();
    }
}