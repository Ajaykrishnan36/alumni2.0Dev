/**
 * @description Re-derives Institute_Name__c across the whole alumni data model. Runs the same
 *              service path as the ConstituentRole trigger, so a re-run repairs whatever drifted
 *              without a second implementation to keep in step.
 *
 *              Intended to be called from anonymous Apex after a bulk import, after institute
 *              codes are edited on provider Accounts, or to repair a subset of people:
 *
 *                  KenInstitutePopulationBatch.runForAll();
 *                  KenInstitutePopulationBatch.runForConstituentRoles(roleIds);
 *                  KenInstitutePopulationBatch.runForAccounts(accountOrContactIds);
 */
public without sharing class KenInstitutePopulationBatch implements Database.Batchable<SObject>, Database.Stateful {

    /**
     * Records per execute. Deliberately small: every configured object is queried once per chunk
     * and a single alumnus can own many notification rows.
     */
    public static final Integer DEFAULT_SCOPE = 50;

    private final Boolean accountMode;
    private final Set<Id> filterIds;

    public Integer recordsProcessed = 0;
    public Integer peopleRecalculated = 0;

    private KenInstitutePopulationBatch(Boolean accountMode, Set<Id> filterIds) {
        this.accountMode = accountMode;
        this.filterIds = filterIds;
    }

    // ---------------------------------------------------------------------------------------
    // Entry points
    // ---------------------------------------------------------------------------------------

    /**
     * @description Recalculates every alumnus in the org.
     * @return the AsyncApexJob id
     */
    public static Id runForAll() {
        return runForAll(DEFAULT_SCOPE);
    }

    public static Id runForAll(Integer scopeSize) {
        return Database.executeBatch(new KenInstitutePopulationBatch(false, null), scopeSize);
    }

    /**
     * @description Recalculates only the supplied ConstituentRoles and the people behind them.
     * @param roleIds ConstituentRole ids
     * @return the AsyncApexJob id
     */
    public static Id runForConstituentRoles(Set<Id> roleIds) {
        return runForConstituentRoles(roleIds, DEFAULT_SCOPE);
    }

    public static Id runForConstituentRoles(Set<Id> roleIds, Integer scopeSize) {
        return Database.executeBatch(new KenInstitutePopulationBatch(false, roleIds), scopeSize);
    }

    /**
     * @description Recalculates the supplied people. Accepts person Account ids or Contact ids.
     * @param personIds Account and/or Contact ids
     * @return the AsyncApexJob id
     */
    public static Id runForAccounts(Set<Id> personIds) {
        return runForAccounts(personIds, DEFAULT_SCOPE);
    }

    public static Id runForAccounts(Set<Id> personIds, Integer scopeSize) {
        return Database.executeBatch(new KenInstitutePopulationBatch(true, personIds), scopeSize);
    }

    // ---------------------------------------------------------------------------------------
    // Batchable
    // ---------------------------------------------------------------------------------------

    public Database.QueryLocator start(Database.BatchableContext context) {

        Set<Id> ids = filterIds;

        if (accountMode) {
            return Database.getQueryLocator([
                SELECT Id FROM Account WHERE Id IN :ids
            WITH SECURITY_ENFORCED
            ]);
        }

        if (ids == null) {
            return Database.getQueryLocator([
                SELECT Id, PersonId
                FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND PersonId != NULL
            WITH SECURITY_ENFORCED
            ]);
        }

        return Database.getQueryLocator([
            SELECT Id, PersonId
            FROM ConstituentRole
            WHERE Id IN :ids AND PersonId != NULL
        WITH SECURITY_ENFORCED
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {

        recordsProcessed += scope.size();

        Set<Id> ids = new Set<Id>();
        for (SObject record : scope) {
            ids.add((Id) record.get('Id'));
        }

        try {
            peopleRecalculated += accountMode
                ? KenInstitutePopulationService.recalcByAccount(ids)
                : KenInstitutePopulationService.recalcByConstituentRole(ids);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenInstitutePopulationBatch chunk failed: ' + e.getMessage() + ' | ' + e.getStackTraceString());
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO,
            'KenInstitutePopulationBatch finished. Scope records: ' + recordsProcessed
            + ', people recalculated: ' + peopleRecalculated);
    }
}