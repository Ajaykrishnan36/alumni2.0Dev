/**
 * One-shot cleanup: merge duplicate 1:1 Ken_Chat_Thread__c into the oldest thread per pair.
 * Deploy, run KenChatV2CleanupOneShot.mergeDupes() from anon Apex, then optionally delete this class.
 * Uses `without sharing` so the running admin doesn't need explicit FLS on every chat field.
 */
public without sharing class KenChatV2CleanupOneShot {
    public static String mergeDupes(Boolean dryRun) {
        Map<Id, List<Id>> partsByThread = new Map<Id, List<Id>>();
        for (Ken_Chat_Participant__c p : [
            SELECT Thread__c, Contact__c FROM Ken_Chat_Participant__c
            WHERE Thread__r.Is_Group__c = false AND Contact__c != null
        ]) {
            if (!partsByThread.containsKey(p.Thread__c)) partsByThread.put(p.Thread__c, new List<Id>());
            partsByThread.get(p.Thread__c).add(p.Contact__c);
        }
        Map<Id, Ken_Chat_Thread__c> tm = new Map<Id, Ken_Chat_Thread__c>([
            SELECT Id, CreatedDate FROM Ken_Chat_Thread__c WHERE Id IN :partsByThread.keySet()]);

        Map<String, List<Id>> threadsByPair = new Map<String, List<Id>>();
        for (Id tid : partsByThread.keySet()) {
            List<Id> parts = partsByThread.get(tid);
            if (parts.size() != 2 || parts[0] == parts[1]) continue;
            String a = String.valueOf(parts[0]); String b = String.valueOf(parts[1]);
            String key = (a.compareTo(b) < 0) ? (a + '|' + b) : (b + '|' + a);
            if (!threadsByPair.containsKey(key)) threadsByPair.put(key, new List<Id>());
            threadsByPair.get(key).add(tid);
        }

        Map<Id, Id> orphanToKeeper = new Map<Id, Id>();
        Integer pairCount = 0, orphanCount = 0;
        for (String key : threadsByPair.keySet()) {
            List<Id> tids = threadsByPair.get(key);
            if (tids.size() < 2) continue;
            pairCount++;
            Id keeperId = null; DateTime keeperCD = null;
            for (Id tid : tids) {
                DateTime cd = tm.get(tid).CreatedDate;
                if (keeperId == null || cd < keeperCD
                    || (cd == keeperCD && String.valueOf(tid).compareTo(String.valueOf(keeperId)) < 0)) {
                    keeperId = tid; keeperCD = cd;
                }
            }
            for (Id tid : tids) {
                if (tid != keeperId) { orphanToKeeper.put(tid, keeperId); orphanCount++; }
            }
        }

        if (orphanCount == 0) return 'Nothing to do (pairs=' + pairCount + ').';

        List<Ken_Chat_Message__c> originals = [
            SELECT Body__c, Sender__c, Sent_At__c, Thread__c
            FROM Ken_Chat_Message__c
            WHERE Thread__c IN :orphanToKeeper.keySet()
            ORDER BY Sent_At__c ASC NULLS LAST, CreatedDate ASC];
        List<Ken_Chat_Message__c> clones = new List<Ken_Chat_Message__c>();
        for (Ken_Chat_Message__c m : originals) {
            clones.add(new Ken_Chat_Message__c(
                Thread__c = orphanToKeeper.get(m.Thread__c),
                Body__c   = m.Body__c,
                Sender__c = m.Sender__c,
                Sent_At__c= m.Sent_At__c));
        }
        if (dryRun) {
            return 'DRY RUN: pairs=' + pairCount + ' orphans=' + orphanCount
                 + ' messages_to_migrate=' + clones.size();
        }
        Savepoint sp = Database.setSavepoint();
        try {
            if (!clones.isEmpty()) insert clones;
            delete [SELECT Id FROM Ken_Chat_Thread__c WHERE Id IN :orphanToKeeper.keySet()];
        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
        return 'MERGE COMPLETE: pairs=' + pairCount + ' orphans_deleted=' + orphanCount
             + ' messages_migrated=' + clones.size();
    }
}