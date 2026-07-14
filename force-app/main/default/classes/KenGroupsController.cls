public without sharing class KenGroupsController {

    @TestVisible
    private static Id testCurrentAccountId;

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class GroupRow {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String rules;
        @AuraEnabled public String tags;
        @AuraEnabled public String groupType;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public String bannerImage;
        @AuraEnabled public Integer memberCount;
        @AuraEnabled public String  memberCountFormatted;
        @AuraEnabled public List<String> friendsImages;
        @AuraEnabled public String  friendsText;
        @AuraEnabled public Boolean isJoined;
        @AuraEnabled public Boolean isPending;
        @AuraEnabled public Boolean isCreated;
        @AuraEnabled public Boolean isFeatured;
        @AuraEnabled public Boolean isPublic;
        @AuraEnabled public Id      memberRecordId;
        @AuraEnabled public String  createdByName;
        @AuraEnabled public String  createdByPhotoUrl;
        @AuraEnabled public String  createdDate;
    }

    public class GroupDataResponse {
        @AuraEnabled public List<GroupRow> discoverGroups;
        @AuraEnabled public List<GroupRow> joinedGroups;
        @AuraEnabled public List<GroupRow> createdGroups;
        @AuraEnabled public List<GroupRow> suggestedGroups;
    }

    public class MemberRow {
        @AuraEnabled public Id     memberRecordId;
        @AuraEnabled public Id     accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String batch;
        @AuraEnabled public String role;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isAdminInvite;
        @AuraEnabled public String invitedByName;
    }

    public class AlumniSearchRow {
        @AuraEnabled public Id     accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String batch;
    }

    // ── Main data fetch ───────────────────────────────────────────────────────

    @AuraEnabled
    public static GroupDataResponse getGroupsData() {
        GroupDataResponse response = new GroupDataResponse();
        response.discoverGroups  = new List<GroupRow>();
        response.joinedGroups    = new List<GroupRow>();
        response.createdGroups   = new List<GroupRow>();
        response.suggestedGroups = new List<GroupRow>();

        Id currentAccountId = getCurrentUserAccountId();

        List<Ken_Group__c> approvedGroups = [
            SELECT Id, Name, Description__c, Rules__c, Tags__c, Group_Type__c, Status__c, Category__c,
                   Banner_Image_URL__c, Member_Count__c, Created_By__c, Is_Active__c, Is_Featured__c
            FROM Ken_Group__c
            WHERE Is_Active__c = true
              AND Status__c = 'Approved'
            ORDER BY CreatedDate DESC NULLS LAST
            LIMIT 200
        ];

        List<Ken_Group__c> myCreatedGroups = new List<Ken_Group__c>();
        if (currentAccountId != null) {
            myCreatedGroups = [
                SELECT Id, Name, Description__c, Rules__c, Tags__c, Group_Type__c, Status__c, Category__c,
                       Banner_Image_URL__c, Member_Count__c, Created_By__c, Is_Active__c, Is_Featured__c
                FROM Ken_Group__c
                WHERE Created_By__c = :currentAccountId
                ORDER BY CreatedDate DESC
            ];
        }

        Set<Id> approvedGroupIds = (new Map<Id, Ken_Group__c>(approvedGroups)).keySet();

        if (approvedGroups.isEmpty() && myCreatedGroups.isEmpty()) {
            return response;
        }

        Map<Id, Set<Id>> segIdsByGroup = new Map<Id, Set<Id>>();
        Set<Id> allSegIds = new Set<Id>();
        if (!approvedGroupIds.isEmpty()) {
            for (Ken_Group_Segmentation__c link : [
                SELECT Group__c, Segmentation__c
                FROM Ken_Group_Segmentation__c
                WHERE Group__c IN :approvedGroupIds AND Segmentation__c != null
            ]) {
                if (!segIdsByGroup.containsKey(link.Group__c)) {
                    segIdsByGroup.put(link.Group__c, new Set<Id>());
                }
                segIdsByGroup.get(link.Group__c).add(link.Segmentation__c);
                allSegIds.add(link.Segmentation__c);
            }
        }

        Map<Id, Boolean> matchBySegId = new Map<Id, Boolean>();
        if (currentAccountId != null && !allSegIds.isEmpty()) {
            for (Ken_Segmentation__c seg : [
                SELECT Id, Definition_JSON__c FROM Ken_Segmentation__c WHERE Id IN :allSegIds
            ]) {
                Boolean matched = false;
                try {
                    matched = KenAudienceEngineService.isAccountMatchedByPayload(
                        currentAccountId, seg.Definition_JSON__c
                    );
                } catch (Exception e) {
                    matched = false;
                }
                matchBySegId.put(seg.Id, matched);
            }
        }

        Set<Id> groupIds = new Set<Id>(approvedGroupIds);

        Map<Id, Ken_Group_Member__c> myMembershipByGroupId = new Map<Id, Ken_Group_Member__c>();
        if (currentAccountId != null) {
            for (Ken_Group_Member__c m : [
                SELECT Id, Group__c, Role__c, Status__c
                FROM Ken_Group_Member__c
                WHERE Member__c = :currentAccountId
                  AND Group__c IN :groupIds
                  AND Status__c = 'Approved'
            ]) {
                myMembershipByGroupId.put(m.Group__c, m);
            }
        }

        Map<Id, List<String>> friendImagesByGroupId = new Map<Id, List<String>>();
        Map<Id, String>       friendsTextByGroupId  = new Map<Id, String>();

        if (currentAccountId != null) {
            Set<Id> connectedAccountIds = new Set<Id>();
            for (Ken_Network_Connection__c conn : [
                SELECT Initiator__c, Recipient__c
                FROM Ken_Network_Connection__c
                WHERE (Initiator__c = :currentAccountId OR Recipient__c = :currentAccountId)
                  AND Status__c = 'Accepted'
            ]) {
                Id otherId = conn.Initiator__c == currentAccountId
                    ? conn.Recipient__c : conn.Initiator__c;
                connectedAccountIds.add(otherId);
            }

            Map<Id, Id>      mostRecentFriendByGroup  = new Map<Id, Id>();
            Map<Id, Integer> friendCountByGroupId      = new Map<Id, Integer>();
            Map<Id, Set<Id>> friendAccsByGroupId       = new Map<Id, Set<Id>>();
            Set<Id>          allFriendAccountIds        = new Set<Id>();

            if (!connectedAccountIds.isEmpty()) {
                for (Ken_Group_Member__c m : [
                    SELECT Id, Group__c, Member__c, Joined_Date__c
                    FROM Ken_Group_Member__c
                    WHERE Group__c IN :groupIds
                      AND Member__c IN :connectedAccountIds
                      AND Status__c = 'Approved'
                    ORDER BY Joined_Date__c DESC NULLS LAST
                ]) {
                    if (!friendCountByGroupId.containsKey(m.Group__c)) {
                        friendCountByGroupId.put(m.Group__c, 0);
                        mostRecentFriendByGroup.put(m.Group__c, m.Member__c);
                        friendAccsByGroupId.put(m.Group__c, new Set<Id>());
                    }
                    friendCountByGroupId.put(m.Group__c, friendCountByGroupId.get(m.Group__c) + 1);
                    friendAccsByGroupId.get(m.Group__c).add(m.Member__c);
                    allFriendAccountIds.add(m.Member__c);
                }
            }

            Map<Id, String> firstNameByAccountId = new Map<Id, String>();
            if (!allFriendAccountIds.isEmpty()) {
                for (Account acc : [SELECT Id, FirstName, Name FROM Account WHERE Id IN :allFriendAccountIds]) {
                    firstNameByAccountId.put(acc.Id, String.isNotBlank(acc.FirstName) ? acc.FirstName : acc.Name);
                }
            }

            Map<Id, String> photoByAccountId = new Map<Id, String>();
            if (!allFriendAccountIds.isEmpty()) {
                for (Ken_Alumni_CRM__c alum : [
                    SELECT Person_Account__c, Profile_Photo_URL__c
                    FROM Ken_Alumni_CRM__c
                    WHERE Person_Account__c IN :allFriendAccountIds
                    ORDER BY LastModifiedDate DESC
                ]) {
                    if (String.isNotBlank(alum.Profile_Photo_URL__c) && !photoByAccountId.containsKey(alum.Person_Account__c)) {
                        photoByAccountId.put(alum.Person_Account__c, alum.Profile_Photo_URL__c);
                    }
                }
                Set<Id> stillNeedPhoto = new Set<Id>();
                for (Id accId : allFriendAccountIds) {
                    if (!photoByAccountId.containsKey(accId)) stillNeedPhoto.add(accId);
                }
                if (!stillNeedPhoto.isEmpty()) {
                    String orgDomain = URL.getOrgDomainUrl().toExternalForm();
                    for (Account acc : [SELECT Id, PhotoUrl FROM Account WHERE Id IN :stillNeedPhoto AND PhotoUrl != null]) {
                        photoByAccountId.put(acc.Id, orgDomain + acc.PhotoUrl);
                    }
                }
            }

            if (!connectedAccountIds.isEmpty()) {
                for (Ken_Group_Member__c m : [
                    SELECT Id, Group__c, Member__c
                    FROM Ken_Group_Member__c
                    WHERE Group__c IN :groupIds
                      AND Member__c IN :connectedAccountIds
                      AND Status__c = 'Approved'
                    ORDER BY Joined_Date__c DESC NULLS LAST
                ]) {
                    if (!friendImagesByGroupId.containsKey(m.Group__c)) {
                        friendImagesByGroupId.put(m.Group__c, new List<String>());
                    }
                    List<String> imgs = friendImagesByGroupId.get(m.Group__c);
                    if (imgs.size() < 3) {
                        String photo = photoByAccountId.containsKey(m.Member__c) ? photoByAccountId.get(m.Member__c) : '';
                        imgs.add(photo);
                    }
                }
            }

            for (Id gId : friendCountByGroupId.keySet()) {
                Integer cnt    = friendCountByGroupId.get(gId);
                Id recentAccId = mostRecentFriendByGroup.get(gId);
                String name    = firstNameByAccountId.containsKey(recentAccId) ? firstNameByAccountId.get(recentAccId) : 'A friend';
                friendsTextByGroupId.put(gId, buildFriendsText(cnt, name));
            }

            Set<Id> groupsNeedingFiller = new Set<Id>();
            for (Id gId : groupIds) {
                Integer existingCount = friendImagesByGroupId.containsKey(gId) ? friendImagesByGroupId.get(gId).size() : 0;
                if (existingCount < 3) groupsNeedingFiller.add(gId);
            }

            if (!groupsNeedingFiller.isEmpty()) {
                List<Ken_Group_Member__c> candidateMembers = [
                    SELECT Id, Group__c, Member__c
                    FROM Ken_Group_Member__c
                    WHERE Group__c IN :groupsNeedingFiller
                      AND Member__c != :currentAccountId
                      AND Status__c = 'Approved'
                    ORDER BY Joined_Date__c DESC NULLS LAST
                ];
                Set<Id> candidateAccIds = new Set<Id>();
                for (Ken_Group_Member__c m : candidateMembers) candidateAccIds.add(m.Member__c);

                Set<Id> nonPrivateAccIds = new Set<Id>();
                Map<Id, String> fillerPhotoByAccId = new Map<Id, String>();
                for (Ken_Alumni_CRM__c crm : [
                    SELECT Person_Account__c, Profile_Photo_URL__c
                    FROM Ken_Alumni_CRM__c
                    WHERE Person_Account__c IN :candidateAccIds
                      AND (Is_Private__c = false OR Is_Private__c = null)
                ]) {
                    nonPrivateAccIds.add(crm.Person_Account__c);
                    if (String.isNotBlank(crm.Profile_Photo_URL__c)) {
                        fillerPhotoByAccId.put(crm.Person_Account__c, crm.Profile_Photo_URL__c);
                    }
                }

                Set<Id> fillerNeedPhoto = new Set<Id>();
                for (Id accId : nonPrivateAccIds) {
                    if (!fillerPhotoByAccId.containsKey(accId)) fillerNeedPhoto.add(accId);
                }
                if (!fillerNeedPhoto.isEmpty()) {
                    String orgDomain = URL.getOrgDomainUrl().toExternalForm();
                    for (Account acc : [SELECT Id, PhotoUrl FROM Account WHERE Id IN :fillerNeedPhoto AND PhotoUrl != null]) {
                        fillerPhotoByAccId.put(acc.Id, orgDomain + acc.PhotoUrl);
                    }
                }

                for (Ken_Group_Member__c m : candidateMembers) {
                    if (!nonPrivateAccIds.contains(m.Member__c)) continue;
                    Set<Id> alreadyAdded = friendAccsByGroupId.containsKey(m.Group__c) ? friendAccsByGroupId.get(m.Group__c) : new Set<Id>();
                    if (alreadyAdded.contains(m.Member__c)) continue;
                    if (!friendImagesByGroupId.containsKey(m.Group__c)) friendImagesByGroupId.put(m.Group__c, new List<String>());
                    List<String> imgs = friendImagesByGroupId.get(m.Group__c);
                    if (imgs.size() >= 3) continue;
                    String photo = fillerPhotoByAccId.containsKey(m.Member__c) ? fillerPhotoByAccId.get(m.Member__c) : '';
                    imgs.add(photo);
                }
            }
        }

        Set<Id> createdGroupIdSet = currentAccountId != null
            ? (new Map<Id, Ken_Group__c>([SELECT Id FROM Ken_Group__c WHERE Created_By__c = :currentAccountId])).keySet()
            : new Set<Id>();

        for (Ken_Group__c grp : approvedGroups) {
            if (createdGroupIdSet.contains(grp.Id)) continue;
            GroupRow row = buildRow(grp, currentAccountId, friendImagesByGroupId, friendsTextByGroupId);
            Ken_Group_Member__c membership = myMembershipByGroupId.get(grp.Id);
            row.isJoined       = membership != null;
            row.isCreated      = false;
            row.memberRecordId = membership != null ? membership.Id : null;
            if (row.isJoined) {
                response.joinedGroups.add(row);
            } else if (isGroupVisibleToAccount(grp.Id, currentAccountId, segIdsByGroup, matchBySegId)) {
                response.discoverGroups.add(row);
            }
        }

        for (Ken_Group__c grp : myCreatedGroups) {
            GroupRow row = buildRow(grp, currentAccountId, friendImagesByGroupId, friendsTextByGroupId);
            Ken_Group_Member__c membership = myMembershipByGroupId.get(grp.Id);
            row.isJoined       = membership != null;
            row.isCreated      = true;
            row.memberRecordId = membership != null ? membership.Id : null;
            response.createdGroups.add(row);
        }

        Set<Id> joinedGroupIds = myMembershipByGroupId.keySet();
        List<Ken_Group__c> featuredGroups = [
            SELECT Id, Name, Description__c, Rules__c, Tags__c, Group_Type__c, Status__c, Category__c,
                   Banner_Image_URL__c, Member_Count__c, Created_By__c, Is_Active__c, Is_Featured__c
            FROM Ken_Group__c
            WHERE Is_Featured__c = true AND Is_Active__c = true AND Status__c = 'Approved' AND Id NOT IN :joinedGroupIds
            ORDER BY CreatedDate DESC NULLS LAST LIMIT 6
        ];
        Set<Id> featuredIds = new Set<Id>();
        for (Ken_Group__c grp : featuredGroups) featuredIds.add(grp.Id);
        Map<Id, Set<Id>> featuredSegIdsByGroup = new Map<Id, Set<Id>>();
        if (!featuredIds.isEmpty()) {
            for (Ken_Group_Segmentation__c link : [
                SELECT Group__c, Segmentation__c FROM Ken_Group_Segmentation__c
                WHERE Group__c IN :featuredIds AND Segmentation__c != null
            ]) {
                if (!featuredSegIdsByGroup.containsKey(link.Group__c)) {
                    featuredSegIdsByGroup.put(link.Group__c, new Set<Id>());
                }
                featuredSegIdsByGroup.get(link.Group__c).add(link.Segmentation__c);
                if (!matchBySegId.containsKey(link.Segmentation__c) && currentAccountId != null) {
                    Boolean matched = false;
                    try {
                        List<Ken_Segmentation__c> segs = [
                            SELECT Definition_JSON__c FROM Ken_Segmentation__c WHERE Id = :link.Segmentation__c LIMIT 1
                        ];
                        if (!segs.isEmpty()) {
                            matched = KenAudienceEngineService.isAccountMatchedByPayload(
                                currentAccountId, segs[0].Definition_JSON__c
                            );
                        }
                    } catch (Exception e) {
                        matched = false;
                    }
                    matchBySegId.put(link.Segmentation__c, matched);
                }
            }
        }
        for (Ken_Group__c grp : featuredGroups) {
            if (!isGroupVisibleToAccount(grp.Id, currentAccountId, featuredSegIdsByGroup, matchBySegId)) continue;
            response.suggestedGroups.add(buildRow(grp, currentAccountId, friendImagesByGroupId, friendsTextByGroupId));
        }
        return response;
    }

    public class GroupEventRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String location;
        @AuraEnabled public String eventType;
        @AuraEnabled public String bannerImage;
        @AuraEnabled public Boolean isPaid;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String startTime;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String timeLabel;
    }

    @AuraEnabled(cacheable=true)
    public static List<GroupEventRow> getEventsForGroup(Id groupId) {
        List<GroupEventRow> out = new List<GroupEventRow>();
        if (groupId == null) return out;

        // A saved audience can be reused across events, so a single segmentation
        // may link to many events — collect them all, not just the last one.
        Set<Id> linkedSegIds = new Set<Id>();
        Map<Id, Set<Id>> eventsBySegId = new Map<Id, Set<Id>>();
        for (Ken_Event_Segmentation__c link : [
            SELECT Event_Master__c, Segmentation__c FROM Ken_Event_Segmentation__c
            WHERE Event_Master__c != null AND Segmentation__c != null
        ]) {
            linkedSegIds.add(link.Segmentation__c);
            if (!eventsBySegId.containsKey(link.Segmentation__c)) {
                eventsBySegId.put(link.Segmentation__c, new Set<Id>());
            }
            eventsBySegId.get(link.Segmentation__c).add(link.Event_Master__c);
        }
        if (linkedSegIds.isEmpty()) return out;

        Set<Id> eventIds = new Set<Id>();
        for (Ken_Segmentation__c seg : [
            SELECT Id, Definition_JSON__c FROM Ken_Segmentation__c WHERE Id IN :linkedSegIds
        ]) {
            String payload = seg.Definition_JSON__c;
            if (String.isBlank(payload) || !payload.contains('"type":"GROUP"')) continue;
            if (!segmentationContainsGroupItem(payload, groupId)) continue;
            Set<Id> evIds = eventsBySegId.get(seg.Id);
            if (evIds != null) eventIds.addAll(evIds);
        }
        if (eventIds.isEmpty()) return out;

        for (Ken_Event_Master__c ev : [
            SELECT Id, Name, Location__c, Event_Type__c, Event_banner__c, Event_Pricing__c, No_Fee__c,
                   Start_Date__c, End_Date__c, Start_Time__c
            FROM Ken_Event_Master__c
            WHERE Id IN :eventIds AND Is_Active__c = true AND Is_Archived__c = false
            ORDER BY Start_Date__c ASC NULLS LAST, Name ASC
        ]) {
            GroupEventRow row = new GroupEventRow();
            row.id = ev.Id;
            row.title = ev.Name;
            row.location = ev.Location__c;
            row.eventType = ev.Event_Type__c;
            row.bannerImage = ev.Event_banner__c;
            row.isPaid = ev.No_Fee__c != true && !String.isBlank(ev.Event_Pricing__c);
            row.startDate = ev.Start_Date__c;
            row.endDate = ev.End_Date__c;
            row.startTime = ev.Start_Time__c == null ? null : String.valueOf(ev.Start_Time__c);
            row.dateLabel = formatEventDateLabel(ev.Start_Date__c, ev.End_Date__c);
            row.timeLabel = formatEventTimeLabel(ev.Start_Time__c);
            out.add(row);
        }
        return out;
    }

    private static Boolean segmentationContainsGroupItem(String payloadJson, Id groupId) {
        if (String.isBlank(payloadJson)) return false;
        Object raw;
        try { raw = JSON.deserializeUntyped(payloadJson); } catch (Exception e) { return false; }
        if (!(raw instanceof Map<String, Object>)) return false;
        Object itemsRaw = ((Map<String, Object>)raw).get('items');
        if (!(itemsRaw instanceof List<Object>)) return false;
        String gid15 = String.valueOf(groupId).substring(0, 15);
        String gid18 = String.valueOf(groupId);
        for (Object itemRaw : (List<Object>)itemsRaw) {
            if (!(itemRaw instanceof Map<String, Object>)) continue;
            Map<String, Object> item = (Map<String, Object>)itemRaw;
            String type = (String)item.get('type');
            String id = (String)item.get('id');
            if (String.isBlank(type) || String.isBlank(id)) continue;
            if (!type.equalsIgnoreCase('GROUP')) continue;
            // Direct selection stores the raw group id; a group added via a saved
            // audience wraps it as 'saved_<groupId>_<ts>_<idx>'. Match either form.
            if (id == gid18 || id == gid15 || id.contains(gid18) || id.contains(gid15)) return true;
        }
        return false;
    }

    private static String formatEventDateLabel(Date startDate, Date endDate) {
        if (startDate == null) return '';
        DateTime sdt = DateTime.newInstance(startDate.year(), startDate.month(), startDate.day());
        String startLabel = sdt.format('d MMM yyyy');
        if (endDate == null || endDate == startDate) {
            return startLabel;
        }
        DateTime edt = DateTime.newInstance(endDate.year(), endDate.month(), endDate.day());
        if (startDate.year() == endDate.year() && startDate.month() == endDate.month()) {
            return startDate.day() + ', ' + endDate.day() + ' ' + edt.format('MMM yyyy');
        }
        return startLabel + ' - ' + edt.format('d MMM yyyy');
    }

    private static String formatEventTimeLabel(Time t) {
        if (t == null) return '';
        Integer h = t.hour();
        Integer m = t.minute();
        String ampm = h >= 12 ? 'PM' : 'AM';
        Integer disp = Math.mod(h, 12);
        if (disp == 0) disp = 12;
        return m == 0 ? disp + ampm : disp + ':' + String.valueOf(m).leftPad(2, '0') + ampm;
    }

    private static Boolean isGroupVisibleToAccount(
        Id groupId,
        Id currentAccountId,
        Map<Id, Set<Id>> segIdsByGroup,
        Map<Id, Boolean> matchBySegId
    ) {
        Set<Id> segIds = segIdsByGroup == null ? null : segIdsByGroup.get(groupId);
        if (segIds == null || segIds.isEmpty()) {
            return true;
        }
        if (currentAccountId == null) {
            return false;
        }
        for (Id segId : segIds) {
            Boolean matched = matchBySegId == null ? null : matchBySegId.get(segId);
            if (matched == true) return true;
        }
        return false;
    }

    // ── Shared row builder ────────────────────────────────────────────────────

    private static GroupRow buildRow(Ken_Group__c grp, Id currentAccountId,
        Map<Id, List<String>> friendImagesByGroupId, Map<Id, String> friendsTextByGroupId) {
        GroupRow row = new GroupRow();
        row.id                   = grp.Id;
        row.name                 = grp.Name;
        row.description          = grp.Description__c;
        row.rules                = grp.Rules__c;
        row.tags                 = grp.Tags__c;
        row.groupType            = String.isNotBlank(grp.Group_Type__c) ? grp.Group_Type__c : 'Private';
        row.status               = String.isNotBlank(grp.Status__c) ? grp.Status__c : 'In Review';
        row.category             = grp.Category__c;
        row.bannerImage          = grp.Banner_Image_URL__c;
        row.memberCount          = grp.Member_Count__c != null ? grp.Member_Count__c.intValue() : 0;
        row.memberCountFormatted = formatMemberCount(row.memberCount);
        row.friendsImages        = friendImagesByGroupId.containsKey(grp.Id) ? friendImagesByGroupId.get(grp.Id) : new List<String>();
        row.friendsText          = friendsTextByGroupId.containsKey(grp.Id) ? friendsTextByGroupId.get(grp.Id) : null;
        row.isFeatured           = grp.Is_Featured__c == true;
        row.isPublic             = grp.Group_Type__c == 'Public';
        return row;
    }

    // ── Join group ────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Id joinGroup(Id groupId) {
        if (groupId == null) throw new AuraHandledException('Group ID is required.');
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) throw new AuraHandledException('Unable to determine current user.');

        List<Ken_Group_Member__c> existing = [
            SELECT Id, Status__c FROM Ken_Group_Member__c
            WHERE Group__c = :groupId AND Member__c = :currentAccountId LIMIT 1
        ];
        if (!existing.isEmpty()) {
            if (existing[0].Status__c == 'Left' || existing[0].Status__c == 'Rejected') {
                List<Ken_Group__c> grpList = [SELECT Group_Type__c FROM Ken_Group__c WHERE Id = :groupId LIMIT 1];
                String memberStatus = (!grpList.isEmpty() && grpList[0].Group_Type__c == 'Public') ? 'Approved' : 'Pending';
                existing[0].Status__c = memberStatus;
                existing[0].Is_Admin_Invite__c = false;
                update existing[0];
                if (memberStatus == 'Approved') updateMemberCount(groupId);
            }
            return existing[0].Id;
        }

        List<Ken_Group__c> grpList = [SELECT Group_Type__c FROM Ken_Group__c WHERE Id = :groupId LIMIT 1];
        String memberStatus = (!grpList.isEmpty() && grpList[0].Group_Type__c == 'Public') ? 'Approved' : 'Pending';

        Ken_Group_Member__c member = new Ken_Group_Member__c(
            Group__c           = groupId,
            Member__c          = currentAccountId,
            Role__c            = 'Member',
            Status__c          = memberStatus,
            Is_Admin_Invite__c = false,
            Joined_Date__c     = Date.today()
        );
        insert member;
        if (memberStatus == 'Approved') updateMemberCount(groupId);
        return member.Id;
    }

    // ── Leave group ───────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static void leaveGroup(Id memberRecordId) {
        if (memberRecordId == null) throw new AuraHandledException('Member record ID is required.');
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) throw new AuraHandledException('Unable to determine current user.');

        List<Ken_Group_Member__c> records = [
            SELECT Id, Group__c, Member__c, Status__c FROM Ken_Group_Member__c
            WHERE Id = :memberRecordId AND Member__c = :currentAccountId LIMIT 1
        ];
        if (records.isEmpty()) throw new AuraHandledException('Member record not found or access denied.');

        Id gId = records[0].Group__c;
        records[0].Status__c = 'Left';
        update records[0];
        updateMemberCount(gId);
    }

    // ── Get single group detail ───────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static GroupRow getGroupDetail(Id groupId) {
        if (groupId == null) throw new AuraHandledException('Group ID is required.');
        Id currentAccountId = getCurrentUserAccountId();

        List<Ken_Group__c> groups = [
            SELECT Id, Name, Description__c, Rules__c, Tags__c, Group_Type__c, Status__c, Category__c,
                   Banner_Image_URL__c, Member_Count__c, Created_By__c,
                   Is_Active__c, Is_Featured__c, CreatedDate, Created_By__r.Name
            FROM Ken_Group__c
            WHERE Id = :groupId LIMIT 1
        ];
        if (groups.isEmpty()) throw new AuraHandledException('Group not found.');
        Ken_Group__c grp = groups[0];

        Boolean isJoinedFlag  = false;
        Boolean isPendingFlag = false;
        Boolean isCreatedFlag = currentAccountId != null && grp.Created_By__c == currentAccountId;
        Id      memberRecId   = null;

        if (currentAccountId != null) {
            List<Ken_Group_Member__c> membership = [
                SELECT Id, Status__c FROM Ken_Group_Member__c
                WHERE Group__c = :groupId AND Member__c = :currentAccountId LIMIT 1
            ];
            if (!membership.isEmpty()) {
                if (membership[0].Status__c == 'Approved') {
                    isJoinedFlag = true;
                    memberRecId  = membership[0].Id;
                } else if (membership[0].Status__c == 'Pending') {
                    isPendingFlag = true;
                    memberRecId   = membership[0].Id;
                }
            }
        }

        String creatorPhotoUrl = null;
        if (grp.Created_By__c != null) {
            List<Ken_Alumni_CRM__c> crms = [
                SELECT Profile_Photo_URL__c FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c = :grp.Created_By__c
                ORDER BY LastModifiedDate DESC LIMIT 1
            ];
            if (!crms.isEmpty() && String.isNotBlank(crms[0].Profile_Photo_URL__c)) {
                creatorPhotoUrl = crms[0].Profile_Photo_URL__c;
            }
            if (String.isBlank(creatorPhotoUrl)) {
                List<Account> accs = [SELECT PhotoUrl FROM Account WHERE Id = :grp.Created_By__c AND PhotoUrl != null LIMIT 1];
                if (!accs.isEmpty()) {
                    creatorPhotoUrl = URL.getOrgDomainUrl().toExternalForm() + accs[0].PhotoUrl;
                }
            }
        }

        GroupRow row          = new GroupRow();
        row.id                = grp.Id;
        row.name              = grp.Name;
        row.description       = grp.Description__c;
        row.rules             = grp.Rules__c;
        row.tags              = grp.Tags__c;
        row.groupType         = String.isNotBlank(grp.Group_Type__c) ? grp.Group_Type__c : 'Private';
        row.status            = String.isNotBlank(grp.Status__c) ? grp.Status__c : '';
        row.category          = grp.Category__c;
        row.bannerImage       = grp.Banner_Image_URL__c;
        row.memberCount       = grp.Member_Count__c != null ? grp.Member_Count__c.intValue() : 0;
        row.memberCountFormatted = formatMemberCount(row.memberCount);
        row.friendsImages     = new List<String>();
        row.friendsText       = null;
        row.isFeatured        = grp.Is_Featured__c == true;
        row.isPublic          = grp.Group_Type__c == 'Public';
        row.isJoined          = isJoinedFlag;
        row.isPending         = isPendingFlag;
        row.isCreated         = isCreatedFlag;
        row.memberRecordId    = memberRecId;
        row.createdByName     = (grp.Created_By__r != null && String.isNotBlank(grp.Created_By__r.Name)) ? grp.Created_By__r.Name : null;
        row.createdByPhotoUrl = creatorPhotoUrl;
        row.createdDate       = grp.CreatedDate != null ? grp.CreatedDate.format('dd MMM yyyy') : null;
        return row;
    }

    // ── Get group members ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<MemberRow> getGroupMembers(Id groupId) {
        if (groupId == null) throw new AuraHandledException('Group ID is required.');

        List<Ken_Group__c> grps = [SELECT Created_By__c FROM Ken_Group__c WHERE Id = :groupId LIMIT 1];
        Id creatorAccountId = grps.isEmpty() ? null : grps[0].Created_By__c;

        List<Ken_Group_Member__c> allMembers = [
            SELECT Id, Member__c, Role__c, Status__c, Is_Admin_Invite__c, Member__r.Name
            FROM Ken_Group_Member__c
            WHERE Group__c = :groupId AND Status__c = 'Approved'
            ORDER BY Role__c ASC, Joined_Date__c ASC NULLS LAST
        ];
        List<Ken_Group_Member__c> members = new List<Ken_Group_Member__c>();
        for (Ken_Group_Member__c m : allMembers) {
            if (creatorAccountId == null || m.Member__c != creatorAccountId) members.add(m);
        }

        Set<Id> accountIds = new Set<Id>();
        for (Ken_Group_Member__c m : members) accountIds.add(m.Member__c);

        Map<Id, String> photoByAccountId = new Map<Id, String>();
        Map<Id, String> batchByAccountId = new Map<Id, String>();

        if (!accountIds.isEmpty()) {
            for (Ken_Alumni_CRM__c crm : [
                SELECT Person_Account__c, Profile_Photo_URL__c, Year_of_Graduation__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c IN :accountIds
                ORDER BY LastModifiedDate DESC
            ]) {
                if (!photoByAccountId.containsKey(crm.Person_Account__c) && String.isNotBlank(crm.Profile_Photo_URL__c)) {
                    photoByAccountId.put(crm.Person_Account__c, crm.Profile_Photo_URL__c);
                }
                if (!batchByAccountId.containsKey(crm.Person_Account__c) && crm.Year_of_Graduation__c != null) {
                    batchByAccountId.put(crm.Person_Account__c, 'Batch - ' + crm.Year_of_Graduation__c);
                }
            }
            Set<Id> needPhoto = new Set<Id>();
            for (Id accId : accountIds) { if (!photoByAccountId.containsKey(accId)) needPhoto.add(accId); }
            if (!needPhoto.isEmpty()) {
                String orgDomain = URL.getOrgDomainUrl().toExternalForm();
                for (Account acc : [SELECT Id, PhotoUrl FROM Account WHERE Id IN :needPhoto AND PhotoUrl != null]) {
                    photoByAccountId.put(acc.Id, orgDomain + acc.PhotoUrl);
                }
            }
        }

        List<MemberRow> result = new List<MemberRow>();
        for (Ken_Group_Member__c m : members) {
            MemberRow row              = new MemberRow();
            row.memberRecordId         = m.Id;
            row.accountId              = m.Member__c;
            row.name                   = m.Member__r != null ? m.Member__r.Name : '';
            row.photoUrl               = photoByAccountId.containsKey(m.Member__c) ? photoByAccountId.get(m.Member__c) : null;
            row.batch                  = batchByAccountId.containsKey(m.Member__c) ? batchByAccountId.get(m.Member__c) : '';
            row.role                   = m.Role__c;
            row.status                 = m.Status__c;
            row.isAdminInvite          = m.Is_Admin_Invite__c == true;
            result.add(row);
        }
        return result;
    }

    // ── Get pending join requests (admin only) ────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<MemberRow> getPendingRequests(Id groupId) {
        if (groupId == null) throw new AuraHandledException('Group ID is required.');
        assertIsAdmin(groupId);

        List<Ken_Group_Member__c> members = [
            SELECT Id, Member__c, Role__c, Status__c, Member__r.Name
            FROM Ken_Group_Member__c
            WHERE Group__c = :groupId AND Status__c = 'Pending' AND Is_Admin_Invite__c = false
            ORDER BY CreatedDate ASC
        ];

        Set<Id> accountIds = new Set<Id>();
        for (Ken_Group_Member__c m : members) accountIds.add(m.Member__c);

        Map<Id, String> photoByAccountId = new Map<Id, String>();
        Map<Id, String> batchByAccountId = new Map<Id, String>();
        if (!accountIds.isEmpty()) {
            for (Ken_Alumni_CRM__c crm : [
                SELECT Person_Account__c, Profile_Photo_URL__c, Year_of_Graduation__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c IN :accountIds
                ORDER BY LastModifiedDate DESC
            ]) {
                if (!photoByAccountId.containsKey(crm.Person_Account__c) && String.isNotBlank(crm.Profile_Photo_URL__c)) {
                    photoByAccountId.put(crm.Person_Account__c, crm.Profile_Photo_URL__c);
                }
                if (!batchByAccountId.containsKey(crm.Person_Account__c) && crm.Year_of_Graduation__c != null) {
                    batchByAccountId.put(crm.Person_Account__c, 'Batch - ' + crm.Year_of_Graduation__c);
                }
            }
        }

        List<MemberRow> result = new List<MemberRow>();
        for (Ken_Group_Member__c m : members) {
            MemberRow row     = new MemberRow();
            row.memberRecordId = m.Id;
            row.accountId      = m.Member__c;
            row.name           = m.Member__r != null ? m.Member__r.Name : '';
            row.photoUrl       = photoByAccountId.containsKey(m.Member__c) ? photoByAccountId.get(m.Member__c) : null;
            row.batch          = batchByAccountId.containsKey(m.Member__c) ? batchByAccountId.get(m.Member__c) : '';
            row.role           = m.Role__c;
            row.status         = m.Status__c;
            result.add(row);
        }
        return result;
    }

    // ── Get invites sent (admin only) ─────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<MemberRow> getInvitesSent(Id groupId) {
        if (groupId == null) throw new AuraHandledException('Group ID is required.');
        assertIsAdmin(groupId);

        List<Ken_Group_Member__c> members = [
            SELECT Id, Member__c, Role__c, Status__c, Member__r.Name, Invited_By__r.Name
            FROM Ken_Group_Member__c
            WHERE Group__c = :groupId AND Status__c IN ('Invited', 'Invite Declined', 'Invite Accepted') AND Is_Admin_Invite__c = true
            ORDER BY CreatedDate DESC
        ];

        Set<Id> accountIds = new Set<Id>();
        for (Ken_Group_Member__c m : members) accountIds.add(m.Member__c);

        Map<Id, String> photoByAccountId = new Map<Id, String>();
        Map<Id, String> batchByAccountId = new Map<Id, String>();
        if (!accountIds.isEmpty()) {
            for (Ken_Alumni_CRM__c crm : [
                SELECT Person_Account__c, Profile_Photo_URL__c, Year_of_Graduation__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c IN :accountIds
                ORDER BY LastModifiedDate DESC
            ]) {
                if (!photoByAccountId.containsKey(crm.Person_Account__c) && String.isNotBlank(crm.Profile_Photo_URL__c)) {
                    photoByAccountId.put(crm.Person_Account__c, crm.Profile_Photo_URL__c);
                }
                if (!batchByAccountId.containsKey(crm.Person_Account__c) && crm.Year_of_Graduation__c != null) {
                    batchByAccountId.put(crm.Person_Account__c, 'Batch - ' + crm.Year_of_Graduation__c);
                }
            }
        }

        List<MemberRow> result = new List<MemberRow>();
        for (Ken_Group_Member__c m : members) {
            MemberRow row     = new MemberRow();
            row.memberRecordId = m.Id;
            row.accountId      = m.Member__c;
            row.name           = m.Member__r != null ? m.Member__r.Name : '';
            row.photoUrl       = photoByAccountId.containsKey(m.Member__c) ? photoByAccountId.get(m.Member__c) : null;
            row.batch          = batchByAccountId.containsKey(m.Member__c) ? batchByAccountId.get(m.Member__c) : '';
            row.role           = m.Role__c;
            row.status         = m.Status__c;
            row.isAdminInvite  = true;
            row.invitedByName  = (m.Invited_By__r != null) ? m.Invited_By__r.Name : null;
            result.add(row);
        }
        return result;
    }

    // ── Approve join request ──────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static void approveJoinRequest(Id memberRecordId) {
        if (memberRecordId == null) throw new AuraHandledException('Member record ID is required.');
        List<Ken_Group_Member__c> records = [
            SELECT Id, Group__c, Status__c FROM Ken_Group_Member__c WHERE Id = :memberRecordId LIMIT 1
        ];
        if (records.isEmpty()) throw new AuraHandledException('Member record not found.');
        assertIsAdmin(records[0].Group__c);
        records[0].Status__c              = 'Approved';
        records[0].Approved_Rejected_By__c = UserInfo.getUserId();
        records[0].Joined_Date__c         = Date.today();
        update records[0];
        updateMemberCount(records[0].Group__c);
    }

    // ── Reject join request ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static void rejectJoinRequest(Id memberRecordId) {
        if (memberRecordId == null) throw new AuraHandledException('Member record ID is required.');
        List<Ken_Group_Member__c> records = [
            SELECT Id, Group__c, Status__c FROM Ken_Group_Member__c WHERE Id = :memberRecordId LIMIT 1
        ];
        if (records.isEmpty()) throw new AuraHandledException('Member record not found.');
        assertIsAdmin(records[0].Group__c);
        records[0].Status__c               = 'Rejected';
        records[0].Approved_Rejected_By__c = UserInfo.getUserId();
        update records[0];
    }

    // ── Remove member (admin) ─────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static void removeMember(Id memberRecordId) {
        if (memberRecordId == null) throw new AuraHandledException('Member record ID is required.');
        Id currentAccountId = getCurrentUserAccountId();
        List<Ken_Group_Member__c> records = [
            SELECT Id, Group__c, Member__c, Status__c FROM Ken_Group_Member__c WHERE Id = :memberRecordId LIMIT 1
        ];
        if (records.isEmpty()) throw new AuraHandledException('Member record not found.');
        if (records[0].Member__c == currentAccountId) throw new AuraHandledException('Admins cannot remove themselves.');
        assertIsAdmin(records[0].Group__c);
        Id gId = records[0].Group__c;
        Boolean wasApproved = records[0].Status__c == 'Approved';
        records[0].Status__c = 'Removed';
        update records[0];
        if (wasApproved) updateMemberCount(gId);
    }

    // ── Search alumni to invite ───────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<AlumniSearchRow> searchAlumniToInvite(Id groupId, String searchTerm) {
        if (groupId == null) throw new AuraHandledException('Group ID is required.');

        Set<Id> existingMemberAccountIds = new Set<Id>();
        for (Ken_Group_Member__c m : [
            SELECT Member__c FROM Ken_Group_Member__c
            WHERE Group__c = :groupId AND Status__c NOT IN ('Left', 'Rejected', 'Removed')
        ]) {
            existingMemberAccountIds.add(m.Member__c);
        }

        String searchPattern = String.isNotBlank(searchTerm) ? '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%' : '%';
        List<Account> accounts = [
            SELECT Id, Name, PhotoUrl
            FROM Account
            WHERE Name LIKE :searchPattern AND Id NOT IN :existingMemberAccountIds
            LIMIT 20
        ];

        Set<Id> accountIds = new Set<Id>();
        for (Account a : accounts) accountIds.add(a.Id);

        Map<Id, String> photoByAccountId = new Map<Id, String>();
        Map<Id, String> batchByAccountId = new Map<Id, String>();
        if (!accountIds.isEmpty()) {
            for (Ken_Alumni_CRM__c crm : [
                SELECT Person_Account__c, Profile_Photo_URL__c, Year_of_Graduation__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c IN :accountIds
                ORDER BY LastModifiedDate DESC
            ]) {
                if (!photoByAccountId.containsKey(crm.Person_Account__c) && String.isNotBlank(crm.Profile_Photo_URL__c)) {
                    photoByAccountId.put(crm.Person_Account__c, crm.Profile_Photo_URL__c);
                }
                if (!batchByAccountId.containsKey(crm.Person_Account__c) && crm.Year_of_Graduation__c != null) {
                    batchByAccountId.put(crm.Person_Account__c, 'Batch - ' + crm.Year_of_Graduation__c);
                }
            }
            String orgDomain = URL.getOrgDomainUrl().toExternalForm();
            for (Account acc : accounts) {
                if (!photoByAccountId.containsKey(acc.Id) && String.isNotBlank(acc.PhotoUrl)) {
                    photoByAccountId.put(acc.Id, orgDomain + acc.PhotoUrl);
                }
            }
        }

        List<AlumniSearchRow> result = new List<AlumniSearchRow>();
        for (Account acc : accounts) {
            AlumniSearchRow row = new AlumniSearchRow();
            row.accountId = acc.Id;
            row.name      = acc.Name;
            row.photoUrl  = photoByAccountId.containsKey(acc.Id) ? photoByAccountId.get(acc.Id) : null;
            row.batch     = batchByAccountId.containsKey(acc.Id) ? batchByAccountId.get(acc.Id) : '';
            result.add(row);
        }
        return result;
    }

    // ── Send invite ───────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Id sendInvite(Id groupId, Id accountId) {
        if (groupId == null || accountId == null) throw new AuraHandledException('Group ID and Account ID are required.');
        assertIsAdmin(groupId);

        List<Ken_Group_Member__c> existing = [
            SELECT Id, Status__c FROM Ken_Group_Member__c
            WHERE Group__c = :groupId AND Member__c = :accountId LIMIT 1
        ];
        Id inviterAccountId = getCurrentUserAccountId();
        if (!existing.isEmpty()) {
            if (existing[0].Status__c == 'Left' || existing[0].Status__c == 'Rejected' || existing[0].Status__c == 'Removed') {
                existing[0].Status__c          = 'Invited';
                existing[0].Is_Admin_Invite__c = true;
                existing[0].Invited_By__c      = inviterAccountId;
                update existing[0];
                return existing[0].Id;
            }
            throw new AuraHandledException('This person is already a member or has a pending request.');
        }

        Ken_Group_Member__c member = new Ken_Group_Member__c(
            Group__c           = groupId,
            Member__c          = accountId,
            Role__c            = 'Member',
            Status__c          = 'Invited',
            Is_Admin_Invite__c = true,
            Invited_By__c      = inviterAccountId,
            Joined_Date__c     = null
        );
        insert member;
        return member.Id;
    }

    // ── Resend invite ─────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static void resendInvite(Id memberRecordId) {
        if (memberRecordId == null) throw new AuraHandledException('Member record ID is required.');
        List<Ken_Group_Member__c> records = [
            SELECT Id, Group__c, Status__c FROM Ken_Group_Member__c WHERE Id = :memberRecordId LIMIT 1
        ];
        if (records.isEmpty()) throw new AuraHandledException('Member record not found.');
        assertIsAdmin(records[0].Group__c);
        records[0].Status__c = 'Invited';
        update records[0];
    }

    // ── Create group ──────────────────────────────────────────────────────────

    @AuraEnabled
    public static Id createGroup(String name, String description, String groupType, String category) {
        if (String.isBlank(name)) throw new AuraHandledException('Group name is required.');
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) throw new AuraHandledException('Unable to determine current user.');

        Ken_Group__c grp = new Ken_Group__c(
            Name            = name,
            Description__c  = description,
            Group_Type__c   = String.isNotBlank(groupType) ? groupType : 'Private',
            Category__c     = String.isNotBlank(category)  ? category  : null,
            Status__c       = 'In Review',
            Is_Active__c    = false,
            Is_Featured__c  = isCurrentUserSystemAdministrator(),
            Created_By__c   = currentAccountId,
            Member_Count__c = 0
        );
        insert grp;

        insert new Ken_Group_Member__c(
            Group__c       = grp.Id,
            Member__c      = currentAccountId,
            Role__c        = 'Admin',
            Status__c      = 'Approved',
            Joined_Date__c = Date.today()
        );
        return grp.Id;
    }

    // ── Save group draft ──────────────────────────────────────────────────────

    @AuraEnabled
    public static Id saveDraftGroup(Id groupId, String name, String description, String groupType,
        String category, String bannerImageUrl, String tags, String rules) {
        if (String.isBlank(name)) throw new AuraHandledException('Group name is required.');
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) throw new AuraHandledException('Unable to determine current user.');

        String resolvedType = String.isNotBlank(groupType)
            ? groupType.substring(0, 1).toUpperCase() + groupType.substring(1).toLowerCase() : 'Private';

        if (groupId != null) {
            List<Ken_Group__c> existing = [SELECT Id FROM Ken_Group__c WHERE Id = :groupId AND Created_By__c = :currentAccountId LIMIT 1];
            if (existing.isEmpty()) throw new AuraHandledException('Group record not found or access denied.');
            Ken_Group__c grp = existing[0];
            grp.Name              = name.trim();
            grp.Description__c    = String.isNotBlank(description) ? description : null;
            grp.Group_Type__c     = resolvedType;
            grp.Category__c       = String.isNotBlank(category) ? category : null;
            grp.Banner_Image_URL__c = String.isNotBlank(bannerImageUrl) ? bannerImageUrl : null;
            grp.Tags__c           = String.isNotBlank(tags) ? tags.trim() : null;
            grp.Rules__c          = String.isNotBlank(rules) ? rules : null;
            grp.Status__c         = 'Draft';
            update grp;
            return grp.Id;
        }

        Ken_Group__c grp = new Ken_Group__c(
            Name              = name.trim(),
            Description__c    = String.isNotBlank(description) ? description : null,
            Group_Type__c     = resolvedType,
            Category__c       = String.isNotBlank(category) ? category : null,
            Banner_Image_URL__c = String.isNotBlank(bannerImageUrl) ? bannerImageUrl : null,
            Tags__c           = String.isNotBlank(tags) ? tags.trim() : null,
            Rules__c          = String.isNotBlank(rules) ? rules : null,
            Status__c         = 'Draft',
            Is_Active__c      = false,
            Is_Featured__c    = false,
            Created_By__c     = currentAccountId,
            Member_Count__c   = 0
        );
        insert grp;
        insert new Ken_Group_Member__c(
            Group__c       = grp.Id,
            Member__c      = currentAccountId,
            Role__c        = 'Admin',
            Status__c      = 'Approved',
            Joined_Date__c = Date.today()
        );
        return grp.Id;
    }

    // ── Get group draft ───────────────────────────────────────────────────────

    @AuraEnabled
    public static Ken_Group__c getDraftGroup(Id groupId) {
        if (groupId == null) return null;
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) throw new AuraHandledException('Unable to determine current user.');
        List<Ken_Group__c> groups = [
            SELECT Id, Name, Description__c, Group_Type__c, Banner_Image_URL__c, Tags__c, Rules__c
            FROM Ken_Group__c
            WHERE Id = :groupId AND Created_By__c = :currentAccountId LIMIT 1
        ];
        return groups.isEmpty() ? null : groups[0];
    }

    // ── Submit group for approval ─────────────────────────────────────────────

    @AuraEnabled
    public static void submitGroupForApproval(Id groupId) {
        if (groupId == null) throw new AuraHandledException('Group ID is required.');
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) throw new AuraHandledException('Unable to determine current user.');
        List<Ken_Group__c> groups = [SELECT Id, Status__c FROM Ken_Group__c WHERE Id = :groupId AND Created_By__c = :currentAccountId LIMIT 1];
        if (groups.isEmpty()) throw new AuraHandledException('Group not found or access denied.');
        groups[0].Status__c = 'In Review';
        update groups[0];
    }

    // ── Create group–segmentation junction ───────────────────────────────────

    @AuraEnabled
    public static Id createGroupSegmentation(Id groupId, Id segmentationId) {
        if (groupId == null || segmentationId == null) throw new AuraHandledException('Group Id and Segmentation Id are required.');
        if (!Schema.sObjectType.Ken_Group_Segmentation__c.isCreateable()) throw new AuraHandledException('No permission to create group segmentation.');
        List<Ken_Group_Segmentation__c> existing = [SELECT Id FROM Ken_Group_Segmentation__c WHERE Group__c = :groupId AND Segmentation__c = :segmentationId LIMIT 1];
        if (!existing.isEmpty()) return existing[0].Id;
        Ken_Group_Segmentation__c link = new Ken_Group_Segmentation__c(Group__c = groupId, Segmentation__c = segmentationId);
        insert link;
        return link.Id;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static void updateMemberCount(Id groupId) {
        KenGroupMemberTriggerHandler.recalculateMemberCounts(new Set<Id>{ groupId });
    }

    private static void assertIsAdmin(Id groupId) {
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) throw new AuraHandledException('Unable to determine current user.');
        List<Ken_Group__c> groups = [SELECT Created_By__c FROM Ken_Group__c WHERE Id = :groupId LIMIT 1];
        if (groups.isEmpty()) throw new AuraHandledException('Group not found.');
        if (groups[0].Created_By__c != currentAccountId) {
            List<Ken_Group_Member__c> adminCheck = [
                SELECT Id FROM Ken_Group_Member__c
                WHERE Group__c = :groupId AND Member__c = :currentAccountId AND Role__c = 'Admin' AND Status__c = 'Approved' LIMIT 1
            ];
            if (adminCheck.isEmpty()) throw new AuraHandledException('Access denied. Admin permission required.');
        }
    }

    private static String formatMemberCount(Integer count) {
        if (count == null || count == 0) return '0';
        if (count >= 1000) {
            Decimal val = Decimal.valueOf(count) / 1000;
            String s = val.setScale(1).toPlainString();
            return (s.endsWith('.0') ? s.substring(0, s.length() - 2) : s) + 'k';
        }
        return String.valueOf(count);
    }

    private static String buildFriendsText(Integer friendCount, String friendName) {
        if (friendCount == null || friendCount == 0) return null;
        if (String.isBlank(friendName)) friendName = 'A friend';
        if (friendCount == 1) return friendName + ' is a member';
        return friendName + ' and ' + (friendCount - 1) + ' friends are members';
    }

    private static Id getCurrentUserAccountId() {
        if (Test.isRunningTest() && testCurrentAccountId != null) return testCurrentAccountId;
        List<User> users = [SELECT Id, AccountId, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (users.isEmpty()) return null;
        User u = users[0];
        if (u.AccountId != null) return u.AccountId;
        if (u.ContactId != null) {
            List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :u.ContactId LIMIT 1];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) return contacts[0].AccountId;
        }
        return null;
    }

    private static Boolean isCurrentUserSystemAdministrator() {
        List<Profile> profiles = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        return !profiles.isEmpty() && profiles[0].Name == 'System Administrator';
    }
}