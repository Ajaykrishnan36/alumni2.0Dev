public without sharing class KenBusinessController {
  @TestVisible
  private static Id testCurrentAccountId;
  @TestVisible
  private static Id testCurrentRoleId;
  private static final String BUSINESS_ACCOUNT_RT_DEVNAME = 'Business';
  private static final String JUNCTION_RT_OWNER_DEVNAME = 'Business_Owner';
  private static final String JUNCTION_RT_PROSPECT_DEVNAME = 'Business_Prospect';


  public class BusinessRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public String ownerImage;
    @AuraEnabled
    public String featuredImage;
    @AuraEnabled
    public String logo;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String rejectionReason;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String website;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String mapUrl;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Id ownerAccountId;
    @AuraEnabled
    public Boolean isOwner;
    // Featured-business fields
    @AuraEnabled
    public String featureStatus;
    @AuraEnabled
    public Date featuredFrom;
    @AuraEnabled
    public Date featuredTo;
    @AuraEnabled
    public Boolean isCurrentlyFeatured;
    @AuraEnabled
    public String featureRejectionReason;
    @AuraEnabled
    public Boolean interestExpressed;
    @AuraEnabled
    public String approvalStatus;
    @AuraEnabled
    public String featureSubject;
    @AuraEnabled
    public String featureMessage;
  }

  @AuraEnabled
  public static List<BusinessRow> getAllBusinesses(Id constituentRoleId) {
    Id businessRtId = getBusinessAccountRecordTypeId();
    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);

    List<Account> rows = [
      SELECT
        Id,
        Name,
        Business_Type__c,
        Business_Address__c,
        Business_Approval__c,
        Is_Active__c,
        Phone,
        Hide_Business_Phone__c,
        Business_Email__c,
        Hide_Business_Email__c,
        Website,
        Location_URL__c,
        Description,
        Cover_Image_Url__c,
        Logo_URL__c,
        Featured_Business__c,
        Business_Feature_Approval__c,
        Featured_From__c,
        Featured_To__c,
        Is_Currently_Featured__c,
        Feature_Subject__c,
        Feature_Message__c,
        Business_Owner_Role__c
      FROM Account
      WHERE RecordTypeId = :businessRtId
        AND Business_Approval__c = 'Approved'
        AND Is_Active__c = true
        AND (Business_Owner_Role__c = NULL OR Business_Owner_Role__c != :effectiveRoleId)
      ORDER BY CreatedDate DESC NULLS LAST
      LIMIT 500
    ];
    Set<Id> ids = new Map<Id, Account>(rows).keySet();
    return buildBusinessRows(
      rows,
      fetchOwnerNameByBusinessId(ids),
      fetchOwnerPhotoByBusinessId(ids)
    );
  }

  @AuraEnabled
  public static List<BusinessRow> getMyBusinesses(Id constituentRoleId) {
    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null) {
      return new List<BusinessRow>();
    }

    Id businessRtId = getBusinessAccountRecordTypeId();
    Id ownerRtId = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);

    Set<Id> businessAccountIds = new Set<Id>();
    for (Ken_Business_Directory__c link : [
      SELECT Business_Account__c
      FROM Ken_Business_Directory__c
      WHERE Constituent_Role__c = :effectiveRoleId AND RecordTypeId = :ownerRtId
    ]) {
      if (link.Business_Account__c != null)
        businessAccountIds.add(link.Business_Account__c);
    }

    if (businessAccountIds.isEmpty())
      return new List<BusinessRow>();

    List<Account> rows = [
      SELECT
        Id,
        Name,
        Business_Type__c,
        Business_Address__c,
        Business_Approval__c,
        Is_Active__c,
        Phone,
        Hide_Business_Phone__c,
        Business_Email__c,
        Hide_Business_Email__c,
        Website,
        Location_URL__c,
        Description,
        Cover_Image_Url__c,
        Logo_URL__c,
        Featured_Business__c,
        Business_Feature_Approval__c,
        Featured_From__c,
        Featured_To__c,
        Is_Currently_Featured__c,
        Feature_Subject__c,
        Feature_Message__c,
        Business_Owner_Role__c
      FROM Account
      WHERE Id IN :businessAccountIds AND RecordTypeId = :businessRtId
      ORDER BY CreatedDate DESC NULLS LAST
      LIMIT 200
    ];

    Map<Id, String> ownerNameByBusinessId = new Map<Id, String>();
    ownerNameByBusinessId.putAll(
      fetchOwnerNameByBusinessId(businessAccountIds)
    );
    List<BusinessRow> result = buildBusinessRows(rows, ownerNameByBusinessId, fetchOwnerPhotoByBusinessId(businessAccountIds));

    Set<Id> featRejected = new Set<Id>();
    Set<Id> bizRejected = new Set<Id>();
    for (BusinessRow r : result) {
      if (r.featureStatus == 'Rejected')
        featRejected.add(r.id);
      if (r.status == 'Rejected')
        bizRejected.add(r.id);
    }
    if (!featRejected.isEmpty()) {
      Map<Id, String> fc = fetchFeatureRejectionComments(featRejected);
      for (BusinessRow r : result) {
        if (fc.containsKey(r.id))
          r.featureRejectionReason = fc.get(r.id);
      }
    }
    if (!bizRejected.isEmpty()) {
      Map<Id, String> bc = fetchBusinessRejectionComments(bizRejected);
      for (BusinessRow r : result) {
        if (bc.containsKey(r.id))
          r.rejectionReason = bc.get(r.id);
      }
    }
    return result;
  }

  @AuraEnabled
  public static BusinessRow getBusinessById(Id businessId, Id constituentRoleId) {
    if (businessId == null)
      return null;

    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    Id businessRtId = getBusinessAccountRecordTypeId();
    List<Account> rows = [
      SELECT
        Id,
        Name,
        Business_Type__c,
        Business_Address__c,
        Business_Approval__c,
        Is_Active__c,
        Phone,
        Hide_Business_Phone__c,
        Business_Email__c,
        Hide_Business_Email__c,
        Website,
        Location_URL__c,
        Description,
        Cover_Image_Url__c,
        Logo_URL__c,
        Featured_Business__c,
        Business_Feature_Approval__c,
        Featured_From__c,
        Featured_To__c,
        Is_Currently_Featured__c,
        Feature_Subject__c,
        Feature_Message__c,
        Business_Owner_Role__c
      FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId
      LIMIT 1
    ];
    if (rows.isEmpty())
      return null;
    Map<Id, String> ownerNameByBusinessId = fetchOwnerNameByBusinessId(new Set<Id>{ businessId });
    Map<Id, String> ownerPhotoByBusinessId = fetchOwnerPhotoByBusinessId(new Set<Id>{ businessId });
    BusinessRow row = buildBusinessRow(rows[0], ownerNameByBusinessId.get(businessId), ownerPhotoByBusinessId.get(businessId));
    if (row.featureStatus == 'Rejected') {
      row.featureRejectionReason = fetchFeatureRejectionComment(businessId);
    }
    if (row.status == 'Rejected') {
      row.rejectionReason = fetchBusinessRejectionComments(new Set<Id>{ businessId }).get(businessId);
    }
    if (effectiveRoleId != null && !row.isOwner) {
      Id prospectRtId = getJunctionRecordTypeId(JUNCTION_RT_PROSPECT_DEVNAME);
      row.interestExpressed = [
        SELECT COUNT()
        FROM Ken_Business_Directory__c
        WHERE Constituent_Role__c = :effectiveRoleId
          AND Business_Account__c = :businessId
          AND RecordTypeId = :prospectRtId
      ] > 0;
    }
    return row;
  }

  private static String fetchFeatureRejectionComment(Id businessId) {
    return fetchRejectionComments(new Set<Id>{ businessId }, 'Business_Feature_Approval_Process').get(businessId);
  }

  private static Map<Id, String> fetchFeatureRejectionComments(Set<Id> bizIds) {
    return fetchRejectionComments(bizIds, 'Business_Feature_Approval_Process');
  }

  private static Map<Id, String> fetchBusinessRejectionComments(Set<Id> bizIds) {
    return fetchRejectionComments(bizIds, 'Business_Approval_Process');
  }

  // Bulk: latest rejection comment per business id for a given approval process.
  private static Map<Id, String> fetchRejectionComments(Set<Id> bizIds, String processDevName) {
    Map<Id, String> out = new Map<Id, String>();
    if (bizIds == null || bizIds.isEmpty())
      return out;
    for (ProcessInstanceStep step : [
      SELECT ProcessInstance.TargetObjectId, Comments
      FROM ProcessInstanceStep
      WHERE ProcessInstance.TargetObjectId IN :bizIds
        AND ProcessInstance.ProcessDefinition.DeveloperName = :processDevName
        AND StepStatus = 'Rejected'
      ORDER BY CreatedDate ASC
    ]) {
      out.put((Id) step.ProcessInstance.TargetObjectId, step.Comments);
    }
    return out;
  }

  // Approved businesses in the SAME category (for the "Similar businesses" panel),
  // excluding the business currently being viewed.
  @AuraEnabled
  public static List<BusinessRow> getSimilarBusinesses(Id businessId, String category, Id constituentRoleId) {
    if (String.isBlank(category)) {
      return new List<BusinessRow>();
    }
    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    Id businessRtId = getBusinessAccountRecordTypeId();
    List<Account> rows = [
      SELECT
        Id,
        Name,
        Business_Type__c,
        Business_Address__c,
        Business_Approval__c,
        Is_Active__c,
        Phone,
        Hide_Business_Phone__c,
        Business_Email__c,
        Hide_Business_Email__c,
        Website,
        Location_URL__c,
        Description,
        Cover_Image_Url__c,
        Logo_URL__c,
        Featured_Business__c,
        Business_Feature_Approval__c,
        Featured_From__c,
        Featured_To__c,
        Is_Currently_Featured__c,
        Feature_Subject__c,
        Feature_Message__c,
        Business_Owner_Role__c
      FROM Account
      WHERE RecordTypeId = :businessRtId
        AND Business_Approval__c = 'Approved'
        AND Is_Active__c = true
        AND Business_Type__c = :category
        AND Id != :businessId
      ORDER BY CreatedDate DESC NULLS LAST
      LIMIT 20
    ];
    Set<Id> ids2 = new Map<Id, Account>(rows).keySet();
    return buildBusinessRows(rows, fetchOwnerNameByBusinessId(ids2), fetchOwnerPhotoByBusinessId(ids2));
  }


  @AuraEnabled
  public static Id createBusiness(Map<String, Object> req, Id constituentRoleId) {
    if (req == null)
      throw new AuraHandledException('Request is required.');
    String businessName = getString(req, 'businessName');
    String businessType = getString(req, 'businessType');
    if (String.isBlank(businessName))
      throw new AuraHandledException('Business name is required.');
    if (String.isBlank(businessType))
      throw new AuraHandledException('Business type is required.');

    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null && !isInternalUser())
      throw new AuraHandledException('ConstituentRoleId is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();

    Account b = new Account();
    b.RecordTypeId = businessRtId;
    b.Name = businessName;
    b.Business_Type__c = businessType;
    b.Phone = getString(req, 'phone');
    b.Hide_Business_Phone__c = getBoolean(req, 'hidePhone');
    b.Business_Email__c = getString(req, 'email');
    b.Hide_Business_Email__c = getBoolean(req, 'hideEmail');
    b.Website = getString(req, 'website');
    b.Business_Address__c = getString(req, 'address');
    b.Location_URL__c = getString(req, 'mapUrl');
    b.Description = getString(req, 'description');
    b.Business_Approval__c = 'Pending';
    b.Is_Active__c = false;

    String coverName = getString(req, 'coverPictureName');
    String coverBase64 = getString(req, 'coverPictureBase64');
    if (String.isNotBlank(coverName) && String.isNotBlank(coverBase64)) {
      b.Cover_Image_Url__c = uploadAndGetPublicUrl(coverName, coverBase64);
    }
    String logoName = getString(req, 'logoName');
    String logoBase64 = getString(req, 'logoBase64');
    if (String.isNotBlank(logoName) && String.isNotBlank(logoBase64)) {
      b.Logo_URL__c = uploadAndGetPublicUrl(logoName, logoBase64);
    }

    insert b;

    Id ownerRtId = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);
    insert new Ken_Business_Directory__c(
      RecordTypeId = ownerRtId,
      Constituent_Role__c = effectiveRoleId,
      Business_Account__c = b.Id
    );

    return b.Id;
  }

  @AuraEnabled
  public static Id updateBusiness(Map<String, Object> req, Id constituentRoleId) {
    if (req == null)
      throw new AuraHandledException('Request is required.');
    Id businessId = getId(req, 'id');
    if (businessId == null)
      throw new AuraHandledException('Business ID is required.');

    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null && !isInternalUser())
      throw new AuraHandledException('ConstituentRoleId is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();
    Id ownerRtId = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);

    List<Ken_Business_Directory__c> links = [
      SELECT Id
      FROM Ken_Business_Directory__c
      WHERE
        Constituent_Role__c = :effectiveRoleId
        AND Business_Account__c = :businessId
        AND RecordTypeId = :ownerRtId
      LIMIT 1
    ];
    if (links.isEmpty())
      throw new AuraHandledException('Access denied.');

    List<Account> existing = [
      SELECT Id, Name, OwnerId, Business_Approval__c, Business_Feature_Approval__c
      FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Business not found.');

    Account b = new Account(Id = businessId);
    String businessName = getString(req, 'businessName');
    String businessType = getString(req, 'businessType');
    if (String.isNotBlank(businessName))
      b.Name = businessName;
    if (String.isNotBlank(businessType))
      b.Business_Type__c = businessType;
    b.Phone = getString(req, 'phone');
    b.Hide_Business_Phone__c = getBoolean(req, 'hidePhone');
    b.Business_Email__c = getString(req, 'email');
    b.Hide_Business_Email__c = getBoolean(req, 'hideEmail');
    b.Website = getString(req, 'website');
    b.Business_Address__c = getString(req, 'address');
    b.Location_URL__c = getString(req, 'mapUrl');
    b.Description = getString(req, 'description');

    String coverName = getString(req, 'coverPictureName');
    String coverBase64 = getString(req, 'coverPictureBase64');
    if (String.isNotBlank(coverName) && String.isNotBlank(coverBase64)) {
      b.Cover_Image_Url__c = uploadAndGetPublicUrl(coverName, coverBase64);
    }
    String logoName = getString(req, 'logoName');
    String logoBase64 = getString(req, 'logoBase64');
    if (String.isNotBlank(logoName) && String.isNotBlank(logoBase64)) {
      b.Logo_URL__c = uploadAndGetPublicUrl(logoName, logoBase64);
    }

    String priorApproval = existing[0].Business_Approval__c;
    String priorFeatureApproval = existing[0].Business_Feature_Approval__c;

    List<ProcessInstance> allPending = [
      SELECT Id, (SELECT Id FROM Workitems)
      FROM ProcessInstance
      WHERE TargetObjectId = :businessId AND Status = 'Pending'
    ];
    for (ProcessInstance pi : allPending) {
      if (!pi.Workitems.isEmpty()) {
        try {
          Approval.ProcessWorkitemRequest recall = new Approval.ProcessWorkitemRequest();
          recall.setWorkitemId(pi.Workitems[0].Id);
          recall.setAction('Removed');
          recall.setComments('Recalled for owner re-edit');
          Approval.process(recall);
        } catch (Exception ex) {
          System.debug('Recall tolerated: ' + ex.getMessage());
        }
      }
    }

    if (priorFeatureApproval == 'Pending Approval') {
      b.Business_Feature_Approval__c = null;
      b.Feature_Subject__c = null;
      b.Feature_Message__c = null;
    }

    if (priorApproval == 'Approved') {
      b.Business_Approval__c = 'Pending';
    }

    update b;

    if (priorApproval == 'Pending') {
      KenApprovalProcessHelper.submitForApproval(
        businessId, 'Business_Approval_Process', existing[0].OwnerId, 'Resubmitted after owner edit'
      );
    }

    return businessId;
  }

  // Request to be a Featured Business — Subject + Message, no dates.
  // Keyed off Business_Feature_Approval__c (a SEPARATE field) so it never
  // disturbs the normal Business_Approval__c flow.
  @AuraEnabled
  public static void requestFeature(Id businessId, String subject, String message, Date featuredFrom, Date featuredTo, Id constituentRoleId) {
    if (businessId == null)
      throw new AuraHandledException('Business is required.');
    if (String.isBlank(subject) || String.isBlank(message))
      throw new AuraHandledException('Please enter both a subject and a message.');
    if (featuredFrom == null || featuredTo == null)
      throw new AuraHandledException('Please select a feature date range.');
    if (featuredTo < featuredFrom)
      throw new AuraHandledException('End date must be on or after the start date.');

    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null && !isInternalUser())
      throw new AuraHandledException('ConstituentRoleId is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();
    Id ownerRtId = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);

    List<Ken_Business_Directory__c> links = [
      SELECT Id
      FROM Ken_Business_Directory__c
      WHERE Constituent_Role__c = :effectiveRoleId
        AND Business_Account__c = :businessId
        AND RecordTypeId = :ownerRtId
      LIMIT 1
    ];
    if (links.isEmpty())
      throw new AuraHandledException('Access denied.');

    List<Account> existing = [
      SELECT Id, Business_Approval__c, Business_Feature_Approval__c
      FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Business not found.');
    if (existing[0].Business_Approval__c != 'Approved')
      throw new AuraHandledException('Only approved businesses can request to be featured.');
    if (existing[0].Business_Feature_Approval__c == 'Pending Approval')
      throw new AuraHandledException('A feature request is already pending approval for this business.');

    update new Account(
      Id = businessId,
      Feature_Subject__c = subject,
      Feature_Message__c = message,
      Featured_From__c = featuredFrom,
      Featured_To__c = featuredTo,
      Business_Feature_Approval__c = 'Pending Approval'
    );
  }

  // Toggle Is_Active__c — De-Activate (false) or Re-Activate (true).
  // Blocked while any approval is in-flight.
  @AuraEnabled
  public static void setBusinessActive(Id businessId, Boolean isActive, Id constituentRoleId) {
    if (businessId == null)
      throw new AuraHandledException('Business is required.');

    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null && !isInternalUser())
      throw new AuraHandledException('ConstituentRoleId is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();
    Id ownerRtId    = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);

    List<Ken_Business_Directory__c> links = [
      SELECT Id FROM Ken_Business_Directory__c
      WHERE Constituent_Role__c = :effectiveRoleId
        AND Business_Account__c = :businessId
        AND RecordTypeId = :ownerRtId
      LIMIT 1
    ];
    if (links.isEmpty())
      throw new AuraHandledException('Access denied.');

    List<Account> existing = [
      SELECT Id, Business_Approval__c, Business_Feature_Approval__c
      FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Business not found.');
    if (existing[0].Business_Approval__c == 'Pending')
      throw new AuraHandledException('This business is under review and cannot be modified.');
    if (existing[0].Business_Feature_Approval__c == 'Pending Approval')
      throw new AuraHandledException('A feature request is pending. The business cannot be modified until the admin decides.');

    update new Account(Id = businessId, Is_Active__c = (isActive == true));
  }

  // Owner-requested deletion — parks the business as Pending Deletion for admin review.
  // Blocked while any approval is in-flight.
  @AuraEnabled
  public static void deleteBusiness(Id businessId, Id constituentRoleId) {
    if (businessId == null)
      throw new AuraHandledException('Business is required.');

    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null && !isInternalUser())
      throw new AuraHandledException('ConstituentRoleId is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();
    Id ownerRtId    = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);

    List<Ken_Business_Directory__c> ownerLinks = [
      SELECT Id FROM Ken_Business_Directory__c
      WHERE Constituent_Role__c = :effectiveRoleId
        AND Business_Account__c = :businessId
        AND RecordTypeId = :ownerRtId
      LIMIT 1
    ];
    if (ownerLinks.isEmpty())
      throw new AuraHandledException('Access denied.');

    List<Account> existing = [
      SELECT Id, Business_Approval__c, Business_Feature_Approval__c
      FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Business not found.');
    if (existing[0].Business_Approval__c == 'Pending')
      throw new AuraHandledException('This business is under review and cannot be deleted.');
    if (existing[0].Business_Approval__c == 'Pending Deletion')
      throw new AuraHandledException('A deletion request is already pending admin review.');
    if (existing[0].Business_Feature_Approval__c == 'Pending Approval')
      throw new AuraHandledException('A feature request is pending. The business cannot be deleted until the admin decides.');

    existing[0].Business_Approval__c = 'Pending Deletion';
    update existing[0];
  }

  @AuraEnabled
  public static void approveBusinessDeletion(Id businessId, Id constituentRoleId) {
    if (businessId == null)
      throw new AuraHandledException('Business is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();
    List<Account> existing = [
      SELECT Id, Business_Approval__c, Is_Active__c FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Business not found.');

    existing[0].Business_Approval__c = 'Deleted';
    existing[0].Is_Active__c         = false;
    update existing[0];
  }

  @AuraEnabled
  public static void dismissBusinessDeletion(Id businessId, Id constituentRoleId) {
    if (businessId == null)
      throw new AuraHandledException('Business is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();
    List<Account> existing = [
      SELECT Id, Business_Approval__c FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Business not found.');

    existing[0].Business_Approval__c = 'Approved';
    update existing[0];
  }

  // Remove the Featured status — clears Business_Feature_Approval__c back to null.
  // Only callable when the business is Featured (Approved); blocked while Pending.
  @AuraEnabled
  public static void removeFeature(Id businessId, Id constituentRoleId) {
    if (businessId == null)
      throw new AuraHandledException('Business is required.');

    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null && !isInternalUser())
      throw new AuraHandledException('ConstituentRoleId is required.');

    Id businessRtId = getBusinessAccountRecordTypeId();
    Id ownerRtId    = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);

    List<Ken_Business_Directory__c> links = [
      SELECT Id FROM Ken_Business_Directory__c
      WHERE Constituent_Role__c = :effectiveRoleId
        AND Business_Account__c = :businessId
        AND RecordTypeId = :ownerRtId
      LIMIT 1
    ];
    if (links.isEmpty())
      throw new AuraHandledException('Access denied.');

    List<Account> existing = [
      SELECT Id, Business_Feature_Approval__c
      FROM Account
      WHERE Id = :businessId AND RecordTypeId = :businessRtId
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Business not found.');
    if (existing[0].Business_Feature_Approval__c == 'Pending Approval')
      throw new AuraHandledException('A feature request is pending and cannot be removed.');
    if (existing[0].Business_Feature_Approval__c != 'Approved')
      throw new AuraHandledException('This business is not currently featured.');

    update new Account(
      Id = businessId,
      Business_Feature_Approval__c = null,
      Feature_Subject__c = null,
      Feature_Message__c = null
    );
  }

  // Approved businesses currently within their featured window — for the carousel.
  @AuraEnabled
  public static List<BusinessRow> getFeaturedBusinesses(Id constituentRoleId) {
    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    Id businessRtId = getBusinessAccountRecordTypeId();
    Integer lim = 10;
    List<Account> rows = [
      SELECT
        Id,
        Name,
        Business_Type__c,
        Business_Address__c,
        Business_Approval__c,
        Is_Active__c,
        Phone,
        Hide_Business_Phone__c,
        Business_Email__c,
        Hide_Business_Email__c,
        Website,
        Location_URL__c,
        Description,
        Cover_Image_Url__c,
        Logo_URL__c,
        Featured_Business__c,
        Business_Feature_Approval__c,
        Featured_From__c,
        Featured_To__c,
        Is_Currently_Featured__c,
        Feature_Subject__c,
        Feature_Message__c,
        Business_Owner_Role__c
      FROM Account
      WHERE RecordTypeId = :businessRtId
        AND Business_Approval__c = 'Approved'
        AND Business_Feature_Approval__c = 'Approved'
        AND Is_Active__c = true
      ORDER BY LastModifiedDate DESC NULLS LAST
      LIMIT :lim
    ];
    Set<Id> ids2 = new Map<Id, Account>(rows).keySet();
    return buildBusinessRows(rows, fetchOwnerNameByBusinessId(ids2), fetchOwnerPhotoByBusinessId(ids2));
  }

  // Admin: all Business RT accounts regardless of owner or approval status.
  @AuraEnabled
  public static List<BusinessRow> getAdminBusinessList(Id constituentRoleId) {
    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    Id businessRtId = getBusinessAccountRecordTypeId();
    List<Account> rows = [
        SELECT
            Id, Name, Business_Type__c, Business_Address__c,
            Business_Approval__c, Is_Active__c,
            Phone, Hide_Business_Phone__c,
            Business_Email__c, Hide_Business_Email__c,
            Website, Location_URL__c, Description,
            Cover_Image_Url__c, Logo_URL__c,
            Featured_Business__c, Business_Feature_Approval__c,
            Featured_From__c, Featured_To__c,
            Is_Currently_Featured__c,
            Feature_Subject__c, Feature_Message__c,
            Business_Owner_Role__c
        FROM Account
        WHERE RecordTypeId = :businessRtId
        ORDER BY CreatedDate DESC NULLS LAST
        LIMIT 500
    ];
    Set<Id> ownerIds = new Map<Id, Account>(rows).keySet();
    Map<Id, String> ownerNames = fetchOwnerNameByBusinessId(ownerIds);
    List<BusinessRow> result = buildBusinessRows(rows, ownerNames, fetchOwnerPhotoByBusinessId(ownerIds));
    Set<Id> bizRejected = new Set<Id>();
    for (BusinessRow r : result) {
        if (r.status == 'Rejected') bizRejected.add(r.id);
    }
    if (!bizRejected.isEmpty()) {
        Map<Id, String> bc = fetchBusinessRejectionComments(bizRejected);
        for (BusinessRow r : result) {
            if (bc.containsKey(r.id)) r.rejectionReason = bc.get(r.id);
        }
    }
    return result;
  }

  // Admin: all Business RT accounts that have any feature approval status set.
  @AuraEnabled
  public static List<BusinessRow> getAdminFeatureList(Id constituentRoleId) {
    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    Id businessRtId = getBusinessAccountRecordTypeId();
    List<Account> rows = [
        SELECT
            Id, Name, Business_Type__c, Business_Address__c,
            Business_Approval__c, Is_Active__c,
            Phone, Hide_Business_Phone__c,
            Business_Email__c, Hide_Business_Email__c,
            Website, Location_URL__c, Description,
            Cover_Image_Url__c, Logo_URL__c,
            Featured_Business__c, Business_Feature_Approval__c,
            Featured_From__c, Featured_To__c,
            Is_Currently_Featured__c,
            Feature_Subject__c, Feature_Message__c,
            Business_Owner_Role__c
        FROM Account
        WHERE RecordTypeId = :businessRtId
            AND Business_Feature_Approval__c != null
        ORDER BY LastModifiedDate DESC NULLS LAST
        LIMIT 500
    ];
    Set<Id> ownerIds = new Map<Id, Account>(rows).keySet();
    Map<Id, String> ownerNames = fetchOwnerNameByBusinessId(ownerIds);
    List<BusinessRow> result = buildBusinessRows(rows, ownerNames, fetchOwnerPhotoByBusinessId(ownerIds));
    Set<Id> featRejected = new Set<Id>();
    for (BusinessRow r : result) {
        if (r.featureStatus == 'Rejected') featRejected.add(r.id);
    }
    if (!featRejected.isEmpty()) {
        Map<Id, String> fc = fetchFeatureRejectionComments(featRejected);
        for (BusinessRow r : result) {
            if (fc.containsKey(r.id)) r.featureRejectionReason = fc.get(r.id);
        }
    }
    return result;
  }

  private static String uploadAndGetPublicUrl(
    String fileName,
    String base64Data
  ) {
    String content = base64Data != null ? base64Data.substringAfter(',') : null;
    if (String.isBlank(content))
      return null;
    return KenCreateContentVersion.createContentVersion(fileName, content);
  }

  // Express interest in someone else's business — stored as a Business_Prospect junction.
  // The owner cannot express interest in their own business. No approval; just stored.
  @AuraEnabled
  public static void expressInterest(Id businessId, String subject, String message, Id constituentRoleId) {
    if (businessId == null) {
      throw new AuraHandledException('Business is required.');
    }
    Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
    if (effectiveRoleId == null && !isInternalUser()) {
      throw new AuraHandledException('ConstituentRoleId is required.');
    }

    List<Account> bizList = [
      SELECT Id, Business_Owner_Role__c FROM Account WHERE Id = :businessId LIMIT 1
    ];
    if (bizList.isEmpty()) {
      throw new AuraHandledException('Business not found.');
    }
    if (bizList[0].Business_Owner_Role__c != null && bizList[0].Business_Owner_Role__c == effectiveRoleId) {
      throw new AuraHandledException('You cannot express interest in your own business.');
    }

    Id prospectRtId = getJunctionRecordTypeId(JUNCTION_RT_PROSPECT_DEVNAME);

    List<Ken_Business_Directory__c> existing = [
      SELECT Id
      FROM Ken_Business_Directory__c
      WHERE Business_Account__c = :businessId
        AND Constituent_Role__c = :effectiveRoleId
        AND RecordTypeId = :prospectRtId
      LIMIT 1
    ];
    Ken_Business_Directory__c link = existing.isEmpty()
      ? new Ken_Business_Directory__c(
          RecordTypeId = prospectRtId,
          Business_Account__c = businessId,
          Constituent_Role__c = effectiveRoleId
        )
      : existing[0];
    link.Subject__c = subject;
    link.Message__c = message;
    upsert link;
  }

  private static List<BusinessRow> buildBusinessRows(
    List<Account> records,
    Map<Id, String> ownerNameByBusinessId
  ) {
    return buildBusinessRows(records, ownerNameByBusinessId, new Map<Id, String>());
  }

  private static List<BusinessRow> buildBusinessRows(
    List<Account> records,
    Map<Id, String> ownerNameByBusinessId,
    Map<Id, String> ownerPhotoByBusinessId
  ) {
    List<BusinessRow> out = new List<BusinessRow>();
    for (Account b : records)
      out.add(buildBusinessRow(
        b,
        ownerNameByBusinessId != null ? ownerNameByBusinessId.get(b.Id) : null,
        ownerPhotoByBusinessId != null ? ownerPhotoByBusinessId.get(b.Id) : null
      ));
    return out;
  }

  private static BusinessRow buildBusinessRow(Account b, String ownerName) {
    return buildBusinessRow(b, ownerName, null);
  }

  private static BusinessRow buildBusinessRow(Account b, String ownerName, String ownerPhoto) {
    BusinessRow r = new BusinessRow();
    r.id = b.Id;
    r.name = b.Name;
    r.category = b.Business_Type__c;
    r.location = b.Business_Address__c;
    r.featuredImage = b.Cover_Image_Url__c;
    r.logo = b.Logo_URL__c;
    r.status = buildUiStatus(b.Business_Approval__c, b.Is_Active__c);
    r.rejectionReason = null;
    r.ownerAccountId = null;
    r.ownerName = ownerName;
    r.ownerImage = ownerPhoto;

    Boolean isOwner = (b.Business_Owner_Role__c != null && b.Business_Owner_Role__c == resolveConstituentRoleId(null));
    r.isOwner = isOwner;
    String phoneVal = (b.Hide_Business_Phone__c == true && !isOwner) ? maskPhone(b.Phone) : b.Phone;
    r.phone = String.isBlank(phoneVal) ? '—' : phoneVal;
    String emailVal = (b.Hide_Business_Email__c == true && !isOwner) ? maskEmail(b.Business_Email__c) : b.Business_Email__c;
    r.email = String.isBlank(emailVal) ? '—' : emailVal;

    r.website = b.Website;
    r.address = b.Business_Address__c;
    r.mapUrl = b.Location_URL__c;
    r.description = b.Description;

    Boolean isActiveBusiness = (b.Business_Approval__c == 'Approved' && b.Is_Active__c == true);
    r.featureStatus = isActiveBusiness ? b.Business_Feature_Approval__c : null;
    r.featuredFrom = isActiveBusiness ? b.Featured_From__c : null;
    r.featuredTo = isActiveBusiness ? b.Featured_To__c : null;
    r.isCurrentlyFeatured = (isActiveBusiness && b.Is_Currently_Featured__c == true);
    r.approvalStatus = b.Business_Approval__c;
    r.featureSubject = b.Feature_Subject__c;
    r.featureMessage = b.Feature_Message__c;
    return r;
  }

  // Effective ConstituentRole for the running user — test hook first, then the explicit
  // param from the LWC, else the latest Alumni role on the user's Person Account
  // (resolved once per transaction).
  private static Boolean currentRoleResolved = false;
  private static Id currentRoleIdCache;
  private static Id resolveConstituentRoleId(Id constituentRoleId) {
    if (Test.isRunningTest() && testCurrentRoleId != null) {
      currentRoleResolved = true;
      currentRoleIdCache = testCurrentRoleId;
      return currentRoleIdCache;
    }
    if (constituentRoleId != null) {
      currentRoleResolved = true;
      currentRoleIdCache = constituentRoleId;
      return currentRoleIdCache;
    }
    if (!currentRoleResolved) {
      currentRoleResolved = true;
      currentRoleIdCache = fetchLatestAlumniRoleId(getCurrentUserAccountId());
    }
    return currentRoleIdCache;
  }

  // Latest Alumni ConstituentRole for the given Person Account.
  private static Id fetchLatestAlumniRoleId(Id accountId) {
    if (accountId == null)
      return null;
    List<ConstituentRole> roles = [
      SELECT Id
      FROM ConstituentRole
      WHERE PersonId = :accountId AND RoleType = 'Alumni'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return roles.isEmpty() ? null : roles[0].Id;
  }

  // Internal Salesforce users (System Admin, internal staff) have no AccountId and no
  // ConstituentRole, so admin-facing flows tolerate a null role for them.
  private static Boolean isInternalUser() {
    User u = [SELECT Id, UserType, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    return u.AccountId == null || u.UserType == 'Standard';
  }

  // Mask all but the last 2 digits of a phone, e.g. "1234567890" -> "********90".
  // Returns null when blank (caller renders "-").
  private static String maskPhone(String phone) {
    if (String.isBlank(phone)) {
      return null;
    }
    String p = phone.trim();
    if (p.length() <= 2) {
      return '**';
    }
    String stars = '';
    for (Integer i = 0; i < p.length() - 2; i++) {
      stars += '*';
    }
    return stars + p.substring(p.length() - 2);
  }

  // Mask the local part of an email, keeping the first char + domain, e.g. "sam@gmail.com" -> "s****@gmail.com".
  // Returns null when blank (caller renders "-").
  private static String maskEmail(String email) {
    if (String.isBlank(email)) {
      return null;
    }
    Integer at = email.indexOf('@');
    if (at <= 0) {
      return '*****';
    }
    return email.substring(0, 1) + '****' + email.substring(at);
  }

  private static String buildUiStatus(String approval, Boolean isActive) {
    if (approval == 'Deleted')
      return 'Deleted';
    if (approval == 'Pending Deletion')
      return 'Deletion Under Review';
    if (approval == 'Rejected')
      return 'Rejected';
    if (approval != 'Approved')
      return 'In review';
    if (isActive == false)
      return 'De-activated';
    return 'Active';
  }

  private static Id getCurrentUserAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null)
      return testCurrentAccountId;
    List<User> users = [
      SELECT Id, AccountId, ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (users.isEmpty())
      return null;
    User u = users[0];
    if (u.AccountId != null)
      return u.AccountId;
    if (u.ContactId != null) {
      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :u.ContactId
        LIMIT 1
      ];
      if (!contacts.isEmpty() && contacts[0].AccountId != null)
        return contacts[0].AccountId;
    }
    return null;
  }

  private static String getString(Map<String, Object> m, String key) {
    if (
      m == null ||
      String.isBlank(key) ||
      !m.containsKey(key) ||
      m.get(key) == null
    )
      return null;
    return String.valueOf(m.get(key));
  }

  private static Boolean getBoolean(Map<String, Object> m, String key) {
    if (
      m == null ||
      String.isBlank(key) ||
      !m.containsKey(key) ||
      m.get(key) == null
    )
      return false;
    Object v = m.get(key);
    if (v instanceof Boolean)
      return (Boolean) v;
    String s = String.valueOf(v).trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  private static Id getId(Map<String, Object> m, String key) {
    String s = getString(m, key);
    if (String.isBlank(s))
      return null;
    try {
      return (Id) s;
    } catch (Exception e) {
      return null;
    }
  }

  private static Id getBusinessAccountRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get(BUSINESS_ACCOUNT_RT_DEVNAME)
      .getRecordTypeId();
  }

  private static Id getJunctionRecordTypeId(String developerName) {
    return Schema.SObjectType.Ken_Business_Directory__c.getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }

  private static Map<Id, String> fetchOwnerNameByBusinessId(
    Set<Id> businessAccountIds
  ) {
    Map<Id, String> ownerNameByBusinessId = new Map<Id, String>();
    if (businessAccountIds == null || businessAccountIds.isEmpty())
      return ownerNameByBusinessId;

    Id ownerRtId = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);

    Set<Id> personAccountIds = new Set<Id>();
    Map<Id, Id> businessToPerson = new Map<Id, Id>();
    for (Ken_Business_Directory__c link : [
      SELECT Business_Account__c, Constituent_Role__c, Constituent_Role__r.PersonId
      FROM Ken_Business_Directory__c
      WHERE
        Business_Account__c IN :businessAccountIds
        AND RecordTypeId = :ownerRtId
      ORDER BY CreatedDate DESC
    ]) {
      if (link.Business_Account__c == null || link.Constituent_Role__c == null || link.Constituent_Role__r.PersonId == null)
        continue;
      if (!businessToPerson.containsKey(link.Business_Account__c)) {
        businessToPerson.put(link.Business_Account__c, link.Constituent_Role__r.PersonId);
        personAccountIds.add(link.Constituent_Role__r.PersonId);
      }
    }

    if (personAccountIds.isEmpty())
      return ownerNameByBusinessId;

    Map<Id, Account> personById = new Map<Id, Account>(
      [
        SELECT Id, FirstName, LastName, Name
        FROM Account
        WHERE Id IN :personAccountIds
      ]
    );

    for (Id businessId : businessToPerson.keySet()) {
      Account p = personById.get(businessToPerson.get(businessId));
      if (p == null)
        continue;
      String nm = String.isNotBlank(p.FirstName) ||
        String.isNotBlank(p.LastName)
        ? (String.valueOf(p.FirstName) +
            ' ' +
            String.valueOf(p.LastName))
            .trim()
        : p.Name;
      ownerNameByBusinessId.put(businessId, nm);
    }

    return ownerNameByBusinessId;
  }

  private static Map<Id, String> fetchOwnerPhotoByBusinessId(Set<Id> businessAccountIds) {
    Map<Id, String> result = new Map<Id, String>();
    if (businessAccountIds == null || businessAccountIds.isEmpty()) return result;
    Id ownerRtId = getJunctionRecordTypeId(JUNCTION_RT_OWNER_DEVNAME);
    Set<Id> personIds = new Set<Id>();
    Map<Id, Id> bizToPerson = new Map<Id, Id>();
    for (Ken_Business_Directory__c link : [
      SELECT Business_Account__c, Constituent_Role__c, Constituent_Role__r.PersonId
      FROM Ken_Business_Directory__c
      WHERE Business_Account__c IN :businessAccountIds AND RecordTypeId = :ownerRtId
      ORDER BY CreatedDate DESC
    ]) {
      if (link.Business_Account__c == null || link.Constituent_Role__c == null || link.Constituent_Role__r.PersonId == null) continue;
      if (!bizToPerson.containsKey(link.Business_Account__c)) {
        bizToPerson.put(link.Business_Account__c, link.Constituent_Role__r.PersonId);
        personIds.add(link.Constituent_Role__r.PersonId);
      }
    }
    if (personIds.isEmpty()) return result;
    Map<Id, Account> personById = new Map<Id, Account>(
      [SELECT Id, PhotoUrl FROM Account WHERE Id IN :personIds]
    );
    String baseUrl = URL.getOrgDomainUrl().toExternalForm();
    for (Id bizId : bizToPerson.keySet()) {
      Account p = personById.get(bizToPerson.get(bizId));
      if (p != null && String.isNotBlank(p.PhotoUrl))
        result.put(bizId, baseUrl + p.PhotoUrl);
    }
    return result;
  }
}