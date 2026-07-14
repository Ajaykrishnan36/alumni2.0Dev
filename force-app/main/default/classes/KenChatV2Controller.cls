// NOTE: `without sharing` — alumni-portal pattern is community-wide directory.
// Aligned with the 11 other portal controllers (KenNetworkController, KenMyProfileController,
// etc.) so cross-alumnus lookups work with Account External OWD = Private.
public without sharing class KenChatV2Controller {

    /* ===================== DTOs =====================
     * Field names match the LWC mock shape so kenChatV2.html / sub-components
     * render with no template changes:
     *   Thread:  { id, name, lastMsg, time, unread, initial, color, online, group }
     *   Message: { id, fromMe, text, time }
     */
    public class ThreadItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String lastMsg;
        @AuraEnabled public String timeLabel;
        @AuraEnabled public Integer unread;
        @AuraEnabled public String initial;
        @AuraEnabled public String color;
        @AuraEnabled public Boolean online;
        @AuraEnabled public Boolean isGroup; // serialized as "isGroup"; LWC reads .group via mapper
    }

    public class MessageItem {
        @AuraEnabled public String id;
        @AuraEnabled public Boolean fromMe;
        @AuraEnabled public String text;
        @AuraEnabled public String timeLabel;
    }

    /* ===================== Helpers ===================== */

    /** Current portal user's linked Contact Id. Throws AuraHandledException if missing. */
    private static Id currentContactId() {
        User u = [SELECT Id, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.ContactId == null) {
            throw new AuraHandledException('Current user has no linked Contact.');
        }
        return u.ContactId;
    }

    /** Format Last_Message_At into a short label similar to the mock data. */
    private static String formatTimeLabel(DateTime dt) {
        if (dt == null) return '';
        DateTime now = DateTime.now();
        Date today = now.dateGmt();
        Date d = dt.dateGmt();
        Integer dayDiff = today.daysBetween(d);
        if (dayDiff == 0) {
            return dt.format('hh:mm a');
        }
        if (dayDiff == -1) {
            return 'Yesterday';
        }
        if (dayDiff > -7 && dayDiff < 0) {
            return dt.format('EEE');
        }
        return dt.format('d MMM');
    }

    private static String snippet(String body) {
        if (body == null) return '';
        String s = body.replaceAll('\\s+', ' ').trim();
        return s.length() > 120 ? s.substring(0, 120) + '…' : s;
    }

    private static String pickColor(Id seed) {
        List<String> palette = new List<String>{
            '#E8B4D6','#B033C8','#1A1A1A','#3061FF','#67A1C8','#F59E0B','#19A974','#DC5959'
        };
        String s = String.valueOf(seed);
        Integer hash = 0;
        for (Integer i = 0; i < s.length(); i++) {
            hash = (hash * 31 + s.charAt(i));
        }
        return palette[Math.mod(Math.abs(hash), palette.size())];
    }

    private static String firstChar(String s) {
        if (String.isBlank(s)) return '?';
        return s.substring(0, 1).toUpperCase();
    }

    /* ===================== Reads ===================== */

    @AuraEnabled(cacheable=true)
    public static List<ThreadItem> getThreads() {
        List<ThreadItem> result = new List<ThreadItem>();
        Id me;
        try { me = currentContactId(); } catch (Exception e) { return result; }

        // Threads I participate in
        List<Ken_Chat_Thread__c> threads = [
            SELECT Id, Name, Is_Group__c, Avatar_Initial__c, Avatar_Color__c,
                   Last_Message_Snippet__c, Last_Message_Time_Label__c, Last_Message_At__c
            FROM Ken_Chat_Thread__c
            WHERE Id IN (
                SELECT Thread__c FROM Ken_Chat_Participant__c WHERE Contact__c = :me
            )
            ORDER BY Last_Message_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 200
        ];
        if (threads.isEmpty()) return result;

        Set<Id> threadIds = new Set<Id>();
        for (Ken_Chat_Thread__c t : threads) threadIds.add(t.Id);

        // Current user's participant rows (for unread counts)
        Map<Id, Ken_Chat_Participant__c> myPartByThread = new Map<Id, Ken_Chat_Participant__c>();
        for (Ken_Chat_Participant__c p : [
            SELECT Id, Thread__c, Unread_Count__c, Is_Online__c
            FROM Ken_Chat_Participant__c
            WHERE Thread__c IN :threadIds AND Contact__c = :me
        ]) {
            myPartByThread.put(p.Thread__c, p);
        }

        // For 1:1 threads, find the "other" participant for name/avatar/online status
        Map<Id, Contact> otherContactByThread = new Map<Id, Contact>();
        Map<Id, Boolean> otherOnlineByThread = new Map<Id, Boolean>();
        for (Ken_Chat_Participant__c p : [
            SELECT Thread__c, Contact__c, Contact__r.Name, Contact__r.FirstName, Is_Online__c
            FROM Ken_Chat_Participant__c
            WHERE Thread__c IN :threadIds AND Contact__c != :me
        ]) {
            // Just first other we see — fine for 1:1, for groups Name field will be used anyway
            if (!otherContactByThread.containsKey(p.Thread__c)) {
                otherContactByThread.put(p.Thread__c, p.Contact__r);
                otherOnlineByThread.put(p.Thread__c, p.Is_Online__c);
            }
        }

        for (Ken_Chat_Thread__c t : threads) {
            ThreadItem ti = new ThreadItem();
            ti.id = t.Id;
            ti.isGroup = (t.Is_Group__c == true);
            String displayName = t.Name;
            String initial = t.Avatar_Initial__c;
            Boolean online = false;
            if (!ti.isGroup) {
                Contact other = otherContactByThread.get(t.Id);
                if (other != null) {
                    displayName = other.Name;
                    if (String.isBlank(initial)) initial = firstChar(other.FirstName != null ? other.FirstName : other.Name);
                }
                Boolean ob = otherOnlineByThread.get(t.Id);
                online = (ob == true);
            }
            ti.name = displayName;
            ti.initial = String.isBlank(initial) ? firstChar(displayName) : initial;
            ti.color = String.isBlank(t.Avatar_Color__c) ? pickColor(t.Id) : t.Avatar_Color__c;
            ti.lastMsg = t.Last_Message_Snippet__c;
            ti.timeLabel = String.isBlank(t.Last_Message_Time_Label__c)
                ? formatTimeLabel(t.Last_Message_At__c)
                : t.Last_Message_Time_Label__c;
            ti.online = online;
            Ken_Chat_Participant__c myP = myPartByThread.get(t.Id);
            ti.unread = (myP != null && myP.Unread_Count__c != null) ? Integer.valueOf(myP.Unread_Count__c) : 0;
            result.add(ti);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<MessageItem> getMessages(Id threadId, Integer pageSize) {
        List<MessageItem> result = new List<MessageItem>();
        if (threadId == null) return result;
        Id me;
        try { me = currentContactId(); } catch (Exception e) { return result; }
        Integer lim = (pageSize == null || pageSize <= 0) ? 200 : pageSize;

        // Sharing filter: only return messages from threads the user participates in
        List<Ken_Chat_Message__c> msgs = [
            SELECT Id, Sender__c, Body__c, Sent_At__c
            FROM Ken_Chat_Message__c
            WHERE Thread__c = :threadId
              AND Thread__c IN (
                  SELECT Thread__c FROM Ken_Chat_Participant__c WHERE Contact__c = :me
              )
            ORDER BY Sent_At__c ASC, CreatedDate ASC
            LIMIT :lim
        ];
        for (Ken_Chat_Message__c m : msgs) {
            MessageItem mi = new MessageItem();
            mi.id = m.Id;
            mi.fromMe = (m.Sender__c == me);
            mi.text = m.Body__c;
            mi.timeLabel = m.Sent_At__c == null ? '' : m.Sent_At__c.format('hh:mm a');
            result.add(mi);
        }
        return result;
    }

    /* ===================== Writes ===================== */

    @AuraEnabled
    public static Id sendMessage(Id threadId, String body) {
        if (threadId == null) throw new AuraHandledException('threadId required');
        if (String.isBlank(body)) throw new AuraHandledException('Message body required');
        Id me = currentContactId();

        // Verify membership
        List<Ken_Chat_Participant__c> myP = [
            SELECT Id FROM Ken_Chat_Participant__c
            WHERE Thread__c = :threadId AND Contact__c = :me LIMIT 1
        ];
        if (myP.isEmpty()) throw new AuraHandledException('Not a participant of this thread');

        DateTime now = DateTime.now();
        Ken_Chat_Message__c msg = new Ken_Chat_Message__c(
            Thread__c = threadId,
            Sender__c = me,
            Body__c = body,
            Sent_At__c = now
        );
        insert msg;

        // Update thread Last_Message_*
        Ken_Chat_Thread__c thr = new Ken_Chat_Thread__c(
            Id = threadId,
            Last_Message_Snippet__c = snippet(body),
            Last_Message_At__c = now,
            Last_Message_Time_Label__c = 'Just now'
        );
        update thr;

        // Bump unread on other participants
        List<Ken_Chat_Participant__c> others = [
            SELECT Id, Unread_Count__c
            FROM Ken_Chat_Participant__c
            WHERE Thread__c = :threadId AND Contact__c != :me
        ];
        for (Ken_Chat_Participant__c p : others) {
            p.Unread_Count__c = (p.Unread_Count__c == null ? 0 : p.Unread_Count__c) + 1;
        }
        if (!others.isEmpty()) update others;

        return msg.Id;
    }

    /**
     * Resolves an inbound id (Contact or Person Account) to a Contact Id, then returns the
     * Id of an existing 1:1 thread between the current user and that contact — or creates one.
     *
     * Accepts Account Ids because callers (Network grid, Business detail) hold Person Account
     * Ids; we look up Account.PersonContactId server-side rather than forcing client refactors.
     */
    @AuraEnabled
    public static Id getOrCreateThreadWithContact(Id targetId) {
        if (targetId == null) throw new AuraHandledException('targetId required');
        Id me = currentContactId();

        // Resolve target — accept either an Account Id (001) or a Contact Id (003).
        // For an Account, prefer PersonContactId; fall back to any Contact on the account
        // (covers non-Person Account models + data integrity gaps).
        Id targetContactId = targetId;
        String prefix = String.valueOf(targetId).substring(0, 3);
        String tail = String.valueOf(targetId).right(6); // last 6 chars for diagnostic logging without leaking full Id

        if (prefix == '001') {
            // Account lookup
            List<Account> accs = [SELECT Id, Name, IsPersonAccount, PersonContactId FROM Account WHERE Id = :targetId LIMIT 1];
            if (accs.isEmpty()) {
                // Diagnostic: explain what was searched. Could be a real-but-invisible Account (sharing/OWD), a deleted record, or a wrong-id type.
                System.debug(LoggingLevel.WARN, 'KenChatV2.getOrCreateThreadWithContact: Account lookup returned 0 rows for targetId ending in ...' + tail);
                throw new AuraHandledException(
                    'Cannot start chat — Account record (id ending …' + tail + ') was not found or is not accessible to you.'
                );
            }
            Account acc = accs[0];
            if (acc.PersonContactId != null) {
                targetContactId = acc.PersonContactId;
            } else {
                // Fallback: any Contact attached to this Account
                List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :targetId ORDER BY CreatedDate ASC LIMIT 1];
                if (!contacts.isEmpty()) {
                    targetContactId = contacts[0].Id;
                } else {
                    throw new AuraHandledException(
                        'Cannot start chat — ' + (acc.Name != null ? acc.Name : 'this user') +
                        ' doesn\'t have a contact record yet. (Account id ending …' + tail + ', IsPersonAccount=' + acc.IsPersonAccount + ')'
                    );
                }
            }
        } else if (prefix == '003') {
            // Contact lookup — verify it exists so we throw early with a useful message instead of letting downstream DML fail.
            List<Contact> contacts = [SELECT Id FROM Contact WHERE Id = :targetId LIMIT 1];
            if (contacts.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'KenChatV2.getOrCreateThreadWithContact: Contact lookup returned 0 rows for targetId ending in ...' + tail);
                throw new AuraHandledException(
                    'Cannot start chat — Contact record (id ending …' + tail + ') was not found or is not accessible to you.'
                );
            }
            // targetContactId already = targetId
        } else {
            throw new AuraHandledException(
                'Invalid recipient id — expected Account (001) or Contact (003) prefix, got "' + prefix + '". Please try again from the alumni directory.'
            );
        }

        if (me == targetContactId) throw new AuraHandledException('Cannot chat with yourself');

        // Threads I participate in
        Set<Id> myThreadIds = new Set<Id>();
        for (Ken_Chat_Participant__c p : [
            SELECT Thread__c FROM Ken_Chat_Participant__c WHERE Contact__c = :me
        ]) {
            myThreadIds.add(p.Thread__c);
        }
        // Find a 1:1 thread that target also participates in. Prefer non-group threads.
        if (!myThreadIds.isEmpty()) {
            for (Ken_Chat_Participant__c p : [
                SELECT Thread__c, Thread__r.Is_Group__c
                FROM Ken_Chat_Participant__c
                WHERE Contact__c = :targetContactId AND Thread__c IN :myThreadIds
            ]) {
                if (p.Thread__r.Is_Group__c != true) {
                    return p.Thread__c;
                }
            }
        }

        // No existing 1:1 — create
        Ken_Chat_Thread__c t = new Ken_Chat_Thread__c(Is_Group__c = false);
        insert t;
        insert new List<Ken_Chat_Participant__c>{
            new Ken_Chat_Participant__c(Thread__c = t.Id, Contact__c = me),
            new Ken_Chat_Participant__c(Thread__c = t.Id, Contact__c = targetContactId)
        };
        return t.Id;
    }

    @AuraEnabled
    public static void markRead(Id threadId) {
        if (threadId == null) return;
        Id me = currentContactId();
        List<Ken_Chat_Participant__c> mine = [
            SELECT Id, Unread_Count__c, Last_Read_At__c
            FROM Ken_Chat_Participant__c
            WHERE Thread__c = :threadId AND Contact__c = :me LIMIT 1
        ];
        if (mine.isEmpty()) return;
        Ken_Chat_Participant__c p = mine[0];
        p.Unread_Count__c = 0;
        p.Last_Read_At__c = DateTime.now();
        update p;
    }

    /* ===================== Provisioning (server-to-server) ===================== */

    /**
     * Resolve an Account (001) or Contact (003) Id to its Contact Id.
     * Returns null when it cannot be resolved (no Person Contact, no child Contact).
     */
    private static Id resolveContactId(Id partyId) {
        if (partyId == null) return null;
        String prefix = String.valueOf(partyId).substring(0, 3);
        if (prefix == '003') {
            return partyId;
        }
        if (prefix == '001') {
            List<Account> accs = [SELECT Id, PersonContactId FROM Account WHERE Id = :partyId LIMIT 1];
            if (accs.isEmpty()) return null;
            if (accs[0].PersonContactId != null) return accs[0].PersonContactId;
            List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :partyId ORDER BY CreatedDate ASC LIMIT 1];
            return contacts.isEmpty() ? null : contacts[0].Id;
        }
        return null;
    }

    /**
     * Get-or-create the 1:1 chat thread between two participants, identified by either
     * Account (001) or Contact (003) Id. Invoked from connection/mentorship accept flows
     * so the chat room is provisioned the moment a connection is accepted (rather than
     * lazily on first click). Idempotent: returns the existing thread if one already exists.
     * Returns null when either party can't be resolved to a Contact — callers treat
     * provisioning as best-effort and never let it break the accept transaction.
     */
    public static Id ensureDirectThreadForParticipants(Id partyA, Id partyB) {
        Id contactA = resolveContactId(partyA);
        Id contactB = resolveContactId(partyB);
        if (contactA == null || contactB == null || contactA == contactB) {
            return null;
        }
        // Strict deterministic resolution: always return the OLDEST existing 1:1 thread
        // that has exactly these two participants. Prevents nondeterministic "first match"
        // returns when historical dupes still exist, and guards against a race-condition
        // double-insert by re-querying after the insert.
        Id existing = findOldestDirectThread(contactA, contactB);
        if (existing != null) return existing;

        Ken_Chat_Thread__c t = new Ken_Chat_Thread__c(Is_Group__c = false);
        insert t;
        insert new List<Ken_Chat_Participant__c>{
            new Ken_Chat_Participant__c(Thread__c = t.Id, Contact__c = contactA),
            new Ken_Chat_Participant__c(Thread__c = t.Id, Contact__c = contactB)
        };

        // Race-safety: if two concurrent callers both inserted, keep the older row and
        // delete ours. Net effect: no new duplicates can ever be created from this path.
        Id oldest = findOldestDirectThread(contactA, contactB);
        if (oldest != null && oldest != t.Id) {
            try { delete new Ken_Chat_Thread__c(Id = t.Id); } catch (Exception ignore) { /* tolerate */ }
            return oldest;
        }
        return t.Id;
    }

    /**
     * Returns the Id of the OLDEST 1:1 Ken_Chat_Thread__c whose participant set is
     * exactly {contactA, contactB}. Null if no such thread exists. Strict pair check
     * (rejects threads that contain a superset of participants).
     */
    private static Id findOldestDirectThread(Id contactA, Id contactB) {
        Set<Id> aThreadIds = new Set<Id>();
        for (Ken_Chat_Participant__c p : [
            SELECT Thread__c FROM Ken_Chat_Participant__c WHERE Contact__c = :contactA
        ]) {
            aThreadIds.add(p.Thread__c);
        }
        if (aThreadIds.isEmpty()) return null;

        // Candidate 1:1 threads that also contain contactB, oldest-first.
        Set<Id> candidates = new Set<Id>();
        for (Ken_Chat_Participant__c p : [
            SELECT Thread__c
            FROM Ken_Chat_Participant__c
            WHERE Contact__c = :contactB
              AND Thread__c IN :aThreadIds
              AND Thread__r.Is_Group__c = false
        ]) {
            candidates.add(p.Thread__c);
        }
        if (candidates.isEmpty()) return null;

        // Strict pair check: count participants per candidate; only those with exactly 2 qualify.
        Map<Id, Integer> partCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Thread__c tid, COUNT(Id) c
            FROM Ken_Chat_Participant__c
            WHERE Thread__c IN :candidates
            GROUP BY Thread__c
        ]) {
            partCount.put((Id) ar.get('tid'), (Integer) ar.get('c'));
        }
        Set<Id> strict = new Set<Id>();
        for (Id tid : partCount.keySet()) {
            if (partCount.get(tid) == 2) strict.add(tid);
        }
        if (strict.isEmpty()) return null;

        for (Ken_Chat_Thread__c t : [
            SELECT Id FROM Ken_Chat_Thread__c
            WHERE Id IN :strict ORDER BY CreatedDate ASC, Id ASC LIMIT 1
        ]) {
            return t.Id;
        }
        return null;
    }
}