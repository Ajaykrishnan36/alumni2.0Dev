public without sharing class KenAlumniIdCardController {

    public String       alumniName         { get; private set; }
    public String       registrationNumber { get; private set; }
    public String       programLabel       { get; private set; }
    public String       graduationYear     { get; private set; }
    public String       photoUrl           { get; private set; }
    public Boolean      hasPhoto           { get; private set; }
    public String       roleId             { get; private set; }
    public String       qrBase64           { get; private set; }
    public Boolean      hasQrCode          { get; private set; }
    public List<String> yearChars          { get; private set; }

    public KenAlumniIdCardController() {
        hasPhoto  = false;
        hasQrCode = false;
        qrBase64  = '';
        yearChars = new List<String>();

        roleId = ApexPages.currentPage().getParameters().get('roleId');

        // QR image pre-fetched by the Queueable and passed as base64
        String qrData = ApexPages.currentPage().getParameters().get('qrData');
        if (String.isNotBlank(qrData)) {
            qrBase64  = qrData;
            hasQrCode = true;
        }
        if (String.isBlank(roleId)) return;

        List<ConstituentRole> roles = [
            SELECT Id, PersonId, Registration_Number__c,
                   Program_Name__c, Graduation_Year__c
            FROM   ConstituentRole
            WHERE  Id = :roleId
            LIMIT  1
        ];
        if (roles.isEmpty()) return;

        ConstituentRole role = roles[0];

        if (role.PersonId != null) {
            List<Account> accounts = [
                SELECT Name FROM Account WHERE Id = :role.PersonId LIMIT 1
            ];
            if (!accounts.isEmpty()) alumniName = accounts[0].Name;
        }

        registrationNumber = role.Registration_Number__c != null ? role.Registration_Number__c : '';
        programLabel       = role.Program_Name__c        != null ? role.Program_Name__c        : '';
        graduationYear     = role.Graduation_Year__c     != null ? String.valueOf(role.Graduation_Year__c) : '';

        for (Integer i = 0; i < graduationYear.length(); i++) {
            yearChars.add(graduationYear.substring(i, i + 1));
        }

        List<Ken_Alumni_CRM__c> crmList = [
            SELECT Profile_Photo_URL__c
            FROM   Ken_Alumni_CRM__c
            WHERE  ConstituentRole__c = :roleId
            LIMIT  1
        ];
        if (!crmList.isEmpty() && String.isNotBlank(crmList[0].Profile_Photo_URL__c)) {
            photoUrl = crmList[0].Profile_Photo_URL__c;
            hasPhoto = true;
        }
    }
}