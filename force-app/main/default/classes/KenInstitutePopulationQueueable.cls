/**
 * @description Carries the institute fan-out out of the ConstituentRole trigger transaction.
 *              Processes a bounded chunk of person Accounts per execute and chains itself for
 *              the remainder, so a single transaction that touches thousands of roles still
 *              completes without breaching query-row or DML limits.
 */
public without sharing class KenInstitutePopulationQueueable implements Queueable {

    /**
     * Person Accounts recalculated per execute. Kept small because a single alumnus can own a
     * large number of notification and booking rows, and every configured object is queried once.
     */
    @TestVisible
    private static Integer chunkSize = 50;

    private final List<Id> accountIds;

    public KenInstitutePopulationQueueable(Set<Id> accountIds) {
        this(new List<Id>(accountIds));
    }

    private KenInstitutePopulationQueueable(List<Id> accountIds) {
        this.accountIds = accountIds;
    }

    public void execute(QueueableContext context) {

        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }

        Integer take = Math.min(chunkSize, accountIds.size());

        Set<Id> current = new Set<Id>();
        List<Id> remaining = new List<Id>();

        for (Integer i = 0; i < accountIds.size(); i++) {
            if (i < take) {
                current.add(accountIds[i]);
            } else {
                remaining.add(accountIds[i]);
            }
        }

        KenInstitutePopulationService.recalcForAccounts(current);

        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new KenInstitutePopulationQueueable(remaining));
        }
    }
}