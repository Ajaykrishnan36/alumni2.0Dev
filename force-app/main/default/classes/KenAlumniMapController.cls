/**
 * Serves aggregated alumni location counts for the portal map view (kenAlumniMap).
 * Counts are grouped by mailing country/state/city on the alumni Person Accounts;
 * coordinate resolution happens client-side against a bundled gazetteer, so no
 * external geocoding service is involved.
 */
public without sharing class KenAlumniMapController {
    private static final String CONSTITUENT_ROLE_TYPE_ALUMNI = 'Alumni';
    private static final Integer ROLE_SCAN_LIMIT = 50000;
    private static final Integer MAX_LOCATION_ROWS = 2000;

    public class LocationCount {
        @AuraEnabled public String country;
        @AuraEnabled public String state;
        @AuraEnabled public String city;
        @AuraEnabled public Integer total;
    }

    /**
     * Returns alumni counts grouped by mailing country, state and city.
     * Scope matches the admin regional demographics: every person with an
     * Alumni ConstituentRole, regardless of portal registration status.
     * Rows are capped at MAX_LOCATION_ROWS ordered by descending count, so
     * the long tail of single-alumni locations is what gets truncated first.
     */
    @AuraEnabled(cacheable=true)
    public static List<LocationCount> getAlumniLocationCounts() {
        Set<Id> alumniPersonIds = new Set<Id>();
        for (ConstituentRole cr : [
            SELECT PersonId
            FROM ConstituentRole
            WHERE RoleType = :CONSTITUENT_ROLE_TYPE_ALUMNI
              AND PersonId != null
            LIMIT :ROLE_SCAN_LIMIT
        ]) {
            alumniPersonIds.add(cr.PersonId);
        }

        List<LocationCount> results = new List<LocationCount>();
        if (alumniPersonIds.isEmpty()) {
            return results;
        }

        for (AggregateResult row : [
            SELECT PersonMailingCountry country,
                   PersonMailingState state,
                   PersonMailingCity city,
                   COUNT(Id) cnt
            FROM Account
            WHERE IsPersonAccount = true
              AND Id IN :alumniPersonIds
              AND (PersonMailingCountry != null OR PersonMailingCity != null)
            GROUP BY PersonMailingCountry, PersonMailingState, PersonMailingCity
            ORDER BY COUNT(Id) DESC
            LIMIT :MAX_LOCATION_ROWS
        ]) {
            LocationCount lc = new LocationCount();
            lc.country = (String) row.get('country');
            lc.state = (String) row.get('state');
            lc.city = (String) row.get('city');
            lc.total = (Integer) row.get('cnt');
            results.add(lc);
        }
        return results;
    }
}