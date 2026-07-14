public class KenAlumniIdCardQueueable implements Queueable, Database.AllowsCallouts {

    private Set<Id> roleIds;

    public KenAlumniIdCardQueueable(Set<Id> roleIds) {
        this.roleIds = roleIds;
    }

    public void execute(QueueableContext ctx) {
        if (roleIds == null || roleIds.isEmpty()) return;

        Id roleId = roleIds.iterator().next();
        roleIds.remove(roleId);

        try {
            generateAndSaveIdCard(roleId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenAlumniIdCardQueueable failed for roleId=' + roleId + ': ' + e.getMessage());
        }

        if (!roleIds.isEmpty()) {
            System.enqueueJob(new KenAlumniIdCardQueueable(roleIds));
        }
    }

    private void generateAndSaveIdCard(Id roleId) {
        List<Ken_Alumni_CRM__c> crmList = [
            SELECT Id FROM Ken_Alumni_CRM__c
            WHERE  ConstituentRole__c = :roleId
            LIMIT  1
        ];
        if (crmList.isEmpty()) {
            System.debug('No Ken_Alumni_CRM__c found for ConstituentRole: ' + roleId);
            return;
        }
        Ken_Alumni_CRM__c crm = crmList[0];

        // ── CALLOUT 1: Pre-fetch QR PNG from api.qrserver.com ─────────────────
        // Flying Saucer (PDF renderer) cannot load external URLs — so we fetch the
        // QR image here and pass it to the VF page as a base64 data URI.
        // QR content = ConstituentRole ID (stable, known before card URL exists)
        String qrBase64 = '';
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(
                'https://api.qrserver.com/v1/create-qr-code/?size=120x120&ecc=L&data='
                + EncodingUtil.urlEncode(String.valueOf(roleId), 'UTF-8')
            );
            req.setMethod('GET');
            req.setTimeout(10000);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                qrBase64 = EncodingUtil.base64Encode(res.getBodyAsBlob());
            }
        } catch (Exception e) {
            System.debug('QR API callout failed: ' + e.getMessage());
        }

        // ── CALLOUT 2: Render VF page as PDF ──────────────────────────────────
        // Pass QR base64 as a URL param so the page can embed it as a data URI.
        // NO DML before this point — both callouts happen first.
        PageReference pageRef = new PageReference('/apex/KenAlumniIdCard');
        pageRef.getParameters().put('roleId', String.valueOf(roleId));
        if (String.isNotBlank(qrBase64)) {
            pageRef.getParameters().put('qrData', qrBase64);
        }

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('TEST_PDF_CONTENT')
            : pageRef.getContent();

        // ── DML: all database writes after callouts ────────────────────────────
        ContentVersion cv = new ContentVersion(
            Title                  = 'Alumni_ID_Card',
            PathOnClient           = 'Alumni_ID_Card.pdf',
            VersionData            = pdfBlob,
            IsMajorVersion         = true,
            FirstPublishLocationId = crm.Id
        );
        insert cv;

        // Build the download URL directly from the ContentVersion Id.
        // No ContentDistribution needed.
        String orgUrl = URL.getOrgDomainUrl().toExternalForm();
        crm.ID_Card_URL__c = orgUrl + '/sfc/servlet.shepherd/version/download/' + cv.Id;
        update crm;

        System.debug('ID card saved for ConstituentRole ' + roleId + ' → ' + crm.ID_Card_URL__c);
    }
}