/**
 * Auto-materializes a real Salesforce Campaign for each Ken_Gift_Campaign_Request__c that
 * reaches a 'Submitted' or 'Approved' status and does not yet have a linked Campaign.
 *
 * Fixes Bug D ("Create new campaign flow is not there / Record type did not create in
 * backend"): the Campaign is created with an EXPLICIT Giving RecordTypeId, and the
 * resulting Campaign Id is stamped back onto the request (Campaign__c) for dedupe.
 *
 * `without sharing` so the automation runs in system context. Campaign insert failures are
 * caught & logged (System.debug) and never roll back the request — the request is the
 * record of truth; an admin can re-trigger materialization later via the update path.
 */
public without sharing class KenGiftCampaignRequestTriggerHandler {

    // Recursion guard: the post-insert stamp of Campaign__c fires the after-update again.
    private static Boolean isStamping = false;

    public void handleAfter(List<Ken_Gift_Campaign_Request__c> newList,
                            Map<Id, Ken_Gift_Campaign_Request__c> oldMap) {
        if (isStamping) return;

        // Collect requests that should get a Campaign (Submitted/Approved, no Campaign yet).
        List<Ken_Gift_Campaign_Request__c> toMaterialize = new List<Ken_Gift_Campaign_Request__c>();
        for (Ken_Gift_Campaign_Request__c r : newList) {
            Boolean statusOk = (r.Status__c == 'Submitted' || r.Status__c == 'Approved');
            if (statusOk && r.Campaign__c == null) {
                toMaterialize.add(r);
            }
        }
        if (toMaterialize.isEmpty()) return;

        materialize(toMaterialize);
    }

    private void materialize(List<Ken_Gift_Campaign_Request__c> requests) {
        Id givingRtId = resolveGivingRecordTypeId();

        // Discover which optional Campaign fields actually exist (defensive — org variance).
        Map<String, Schema.SObjectField> campFields = Schema.SObjectType.Campaign.fields.getMap();
        Boolean hasGoal     = campFields.containsKey('ken_giving_goal_amount__c');
        Boolean hasCategory = campFields.containsKey('ken_giving_category__c');
        Boolean hasStory    = campFields.containsKey('ken_giving_story__c');
        Boolean hasHero     = campFields.containsKey('ken_giving_hero_image_url__c');
        Boolean hasInitiator= campFields.containsKey('ken_giving_initiator__c');
        Boolean hasPortalVis= campFields.containsKey('ken_giving_is_portal_visible__c');

        List<Campaign> campaignsToInsert = new List<Campaign>();
        // Parallel list: campaignsToInsert[i] belongs to requestsForInsert[i].
        List<Ken_Gift_Campaign_Request__c> requestsForInsert = new List<Ken_Gift_Campaign_Request__c>();

        for (Ken_Gift_Campaign_Request__c r : requests) {
            Campaign c = new Campaign();
            c.Name = (r.Name != null ? r.Name : 'Giving Campaign').left(80);
            if (givingRtId != null) c.RecordTypeId = givingRtId;   // <-- the core ask
            c.IsActive    = true;
            c.Status      = 'Planned';
            c.Type        = 'Other';
            c.Description  = r.Description__c;
            c.ExpectedRevenue = r.Goal_Amount__c;

            if (hasGoal)      c.put('Ken_Giving_Goal_Amount__c', r.Goal_Amount__c);
            if (hasCategory)  c.put('Ken_Giving_Category__c', r.Category__c);
            if (hasStory)     c.put('Ken_Giving_Story__c', r.Story__c);
            if (hasHero)      c.put('Ken_Giving_Hero_Image_URL__c', r.Hero_Image_URL__c);
            if (hasInitiator) c.put('Ken_Giving_Initiator__c', r.Requested_By__c);
            // Not portal-visible until an admin reviews/publishes.
            if (hasPortalVis) c.put('Ken_Giving_Is_Portal_Visible__c', false);

            campaignsToInsert.add(c);
            requestsForInsert.add(r);
        }

        if (campaignsToInsert.isEmpty()) return;

        // Insert allowing partial success; never throw out of the trigger.
        List<Database.SaveResult> results;
        try {
            results = Database.insert(campaignsToInsert, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenGiftCampaignRequestTriggerHandler: Campaign insert failed: ' + e.getMessage());
            return;
        }

        // Stamp Campaign__c back onto successfully-created requests.
        List<Ken_Gift_Campaign_Request__c> stamps = new List<Ken_Gift_Campaign_Request__c>();
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            if (sr.isSuccess()) {
                stamps.add(new Ken_Gift_Campaign_Request__c(
                    Id = requestsForInsert[i].Id,
                    Campaign__c = sr.getId()
                ));
            } else {
                System.debug(LoggingLevel.ERROR,
                    'KenGiftCampaignRequestTriggerHandler: Campaign not created for request '
                    + requestsForInsert[i].Id + ': ' + sr.getErrors());
            }
        }

        if (!stamps.isEmpty()) {
            isStamping = true;
            try {
                Database.update(stamps, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'KenGiftCampaignRequestTriggerHandler: stamping Campaign__c failed: ' + e.getMessage());
            } finally {
                isStamping = false;
            }
        }
    }

    /**
     * Resolve the Giving Campaign RecordType Id. Prefers a record type whose DeveloperName
     * mentions Giving/Fundrais/Gift; otherwise falls back to the object's default record type
     * (returns null when the org has no Campaign record types at all — caller skips the field).
     */
    public static Id resolveGivingRecordTypeId() {
        // Query directly so we don't depend on the record type being assigned to the running
        // user's profile (a freshly-deployed RT is not yet profile-visible, but is still a
        // valid Id to stamp on the Campaign).
        List<RecordType> giving = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Campaign' AND IsActive = true
              AND (DeveloperName LIKE '%Giving%'
                   OR DeveloperName LIKE '%Fundrais%'
                   OR DeveloperName LIKE '%Gift%')
            ORDER BY DeveloperName LIMIT 1
        ];
        if (!giving.isEmpty()) return giving[0].Id;

        // Fallback: profile-default record type (if any non-master exists).
        Map<String, Schema.RecordTypeInfo> byDevName =
            Schema.SObjectType.Campaign.getRecordTypeInfosByDeveloperName();
        for (Schema.RecordTypeInfo info : byDevName.values()) {
            if (info.isDefaultRecordTypeMapping() && info.isAvailable() && !info.isMaster()) {
                return info.getRecordTypeId();
            }
        }
        return null;
    }
}