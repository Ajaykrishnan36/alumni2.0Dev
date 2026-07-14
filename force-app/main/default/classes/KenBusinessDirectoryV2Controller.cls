public without sharing class KenBusinessDirectoryV2Controller {

    // Developer name of the non-person Account record type used for business listings.
    private static final String BUSINESS_ACCOUNT_RT_DEVNAME = 'Business';
    private static final List<String> PALETTE = new List<String>{
        '#3061FF','#B033C8','#19A974','#F59E0B','#E8B4D6','#67A1C8','#8B5CF6','#EF4444'
    };

    public class BusinessItem {
        // Account Id (18-char) for real listings; kept as String so it survives round-trips.
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String owner;
        @AuraEnabled public String category;
        @AuraEnabled public String city;
        @AuraEnabled public String tagline;
        @AuraEnabled public String initial;
        @AuraEnabled public String col;
        @AuraEnabled public String discount;
        @AuraEnabled public String about;
        @AuraEnabled public String products;
        @AuraEnabled public String contact;
        @AuraEnabled public String coverUrl;
    }

    // ── Record type resolution ───────────────────────────────────────────────
    private static Id getBusinessRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(BUSINESS_ACCOUNT_RT_DEVNAME);
        return info == null ? null : info.getRecordTypeId();
    }

    // ── Defensive field-exists check (so we only set fields that are present) ─
    private static Boolean hasField(String apiName) {
        return Schema.SObjectType.Account.fields.getMap().containsKey(apiName.toLowerCase());
    }

    private static Boolean isValidIndustry(String value) {
        if (String.isBlank(value)) return false;
        for (Schema.PicklistEntry e : Account.Industry.getDescribe().getPicklistValues()) {
            if (e.isActive() && e.getValue().equalsIgnoreCase(value)) return true;
        }
        return false;
    }

    private static String getStr(Map<String,Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) return null;
        return String.valueOf(m.get(key));
    }

    // ── PHASE 1: create a real business-listing Account ──────────────────────
    @AuraEnabled
    public static Id createBusinessListing(Map<String,Object> payload) {
        if (payload == null) {
            throw new AuraHandledException('Request is required.');
        }
        String name = getStr(payload, 'name');
        if (String.isBlank(name)) {
            throw new AuraHandledException('Business name is required.');
        }

        String category = getStr(payload, 'category');
        String website  = getStr(payload, 'website');
        String about    = getStr(payload, 'about');
        String tagline  = getStr(payload, 'tagline');
        String city     = getStr(payload, 'city');
        String contact  = getStr(payload, 'contact');
        String owner    = getStr(payload, 'owner');
        String discount = getStr(payload, 'offer');
        String products = getStr(payload, 'products');

        Account acc = new Account();
        acc.Name = name;

        Id rtId = getBusinessRecordTypeId();
        if (rtId != null) {
            acc.RecordTypeId = rtId;
        }

        // Standard fields
        if (String.isNotBlank(website))  acc.Website     = website;
        if (String.isNotBlank(city))     acc.BillingCity = city;
        if (String.isNotBlank(contact))  acc.Phone       = contact;

        // Category → Industry only if it's a valid picklist value, else into Business_Type__c / Description.
        if (isValidIndustry(category)) {
            acc.Industry = category;
        }
        if (String.isNotBlank(category) && hasField('Business_Type__c')) {
            acc.put('Business_Type__c', category);
        }
        if (String.isNotBlank(contact) && hasField('Business_Email__c') && contact.contains('@')) {
            acc.put('Business_Email__c', contact);
        }
        if (String.isNotBlank(city) && hasField('Business_Address__c')) {
            acc.put('Business_Address__c', city);
        }
        if (hasField('Business_Approval__c')) acc.put('Business_Approval__c', 'Pending');
        if (hasField('Is_Active__c'))         acc.put('Is_Active__c', true);

        // Fold anything without a standard home into Description.
        List<String> descParts = new List<String>();
        if (String.isNotBlank(about))    descParts.add(about);
        if (String.isNotBlank(tagline))  descParts.add('Tagline: ' + tagline);
        if (String.isNotBlank(owner))    descParts.add('Owner: ' + owner);
        if (String.isNotBlank(discount)) descParts.add('Alumni offer: ' + discount);
        if (String.isNotBlank(products)) descParts.add('Products / services: ' + products);
        if (!descParts.isEmpty()) {
            acc.Description = String.join(descParts, '\n');
        }

        insert acc;

        // ── PHASE 3: optional cover photo (inline) ───────────────────────────
        String coverName   = getStr(payload, 'coverFileName');
        String coverBase64 = getStr(payload, 'coverBase64');
        if (String.isNotBlank(coverName) && String.isNotBlank(coverBase64)) {
            String url = uploadBusinessCover(acc.Id, coverName, coverBase64);
            if (String.isNotBlank(url) && hasField('Cover_Image_Url__c')) {
                update new Account(Id = acc.Id, Cover_Image_Url__c = url);
            }
        }

        return acc.Id;
    }

    // ── PHASE 3: ContentVersion + ContentDocumentLink against the Account ─────
    @AuraEnabled
    public static String uploadBusinessCover(Id accountId, String fileName, String base64) {
        if (accountId == null || String.isBlank(base64)) {
            throw new AuraHandledException('Account Id and file data are required.');
        }
        // Strip a possible "data:image/...;base64," prefix.
        String content = base64.contains(',') ? base64.substringAfter(',') : base64;

        ContentVersion cv = new ContentVersion();
        cv.Title = String.isBlank(fileName) ? 'Business Cover' : fileName;
        cv.PathOnClient = String.isBlank(fileName) ? 'cover.png' : fileName;
        cv.VersionData = EncodingUtil.base64Decode(content);
        insert cv;

        ContentVersion saved = [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ];

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = saved.ContentDocumentId;
        link.LinkedEntityId    = accountId;
        link.ShareType         = 'V';
        link.Visibility        = 'AllUsers';
        insert link;

        // Return a session-resolvable download URL for the new version.
        return URL.getOrgDomainUrl().toExternalForm()
            + '/sfc/servlet.shepherd/version/download/' + saved.Id;
    }

    // ── Read: scope strictly to business-listing Accounts (no PersonAccounts) ─
    @AuraEnabled(cacheable=true)
    public static List<BusinessItem> getBusinesses(String category) {
        Id rtId = getBusinessRecordTypeId();
        if (rtId == null) return new List<BusinessItem>();

        Boolean hasType = hasField('Business_Type__c');
        Boolean hasAddr = hasField('Business_Address__c');
        Boolean hasCover = hasField('Cover_Image_Url__c');

        String soql = 'SELECT Id, Name, Industry, Website, Description, BillingCity, Phone';
        if (hasType)  soql += ', Business_Type__c';
        if (hasAddr)  soql += ', Business_Address__c';
        if (hasCover) soql += ', Cover_Image_Url__c';
        soql += ' FROM Account WHERE RecordTypeId = :rtId';

        Boolean filter = String.isNotBlank(category) && category != 'All';
        if (filter && hasType) {
            soql += ' AND Business_Type__c = :category';
        }
        soql += ' ORDER BY CreatedDate DESC NULLS LAST LIMIT 500';

        List<Account> rows = Database.query(soql);
        List<BusinessItem> out = new List<BusinessItem>();
        Integer i = 0;
        for (Account a : rows) {
            String cat = hasType ? (String) a.get('Business_Type__c') : a.Industry;
            // When filtering by a category that lives only in Industry, apply it in-memory.
            if (filter && !hasType && a.Industry != category) continue;

            BusinessItem b = new BusinessItem();
            b.id = a.Id;
            b.name = a.Name;
            b.category = String.isNotBlank(cat) ? cat : a.Industry;
            b.city = hasAddr ? (String) a.get('Business_Address__c') : a.BillingCity;
            if (String.isBlank(b.city)) b.city = a.BillingCity;
            b.about = a.Description;
            b.tagline = String.isNotBlank(a.Description)
                ? (a.Description.length() > 120 ? a.Description.substring(0, 120) : a.Description)
                : '';
            b.contact = a.Phone;
            b.coverUrl = hasCover ? (String) a.get('Cover_Image_Url__c') : null;
            b.initial = String.isNotBlank(a.Name) ? a.Name.substring(0, 1).toUpperCase() : '?';
            b.col = PALETTE[Math.mod(i, PALETTE.size())];
            b.owner = '';
            b.discount = '';
            b.products = '';
            out.add(b);
            i++;
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static BusinessItem getBusiness(String id) {
        if (String.isBlank(id)) return null;
        for (BusinessItem b : getBusinesses('All')) {
            if (b.id == id) return b;
        }
        return null;
    }
}