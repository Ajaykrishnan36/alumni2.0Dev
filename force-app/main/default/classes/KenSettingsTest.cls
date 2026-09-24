/**
 * Covers the settings accessor, and in particular the hierarchy behaviour that the
 * mixed getInstance/getOrgDefaults usage used to get wrong.
 *
 * Fields are assigned through the compiler rather than through put() with a name
 * string, so these tests keep working once the package carries a namespace.
 */
@isTest
private class KenSettingsTest {

    private static Ken_Alm_Org_Parameters__c orgDefault() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        KenSettings.cachedParameters = null;
        return params;
    }

    private static void save(Ken_Alm_Org_Parameters__c params) {
        upsert params;
        KenSettings.cachedParameters = null;
    }

    @isTest
    static void readsTheOrgDefaultWhenNoOverrideExists() {
        Ken_Alm_Org_Parameters__c params = orgDefault();
        params.Institution_Name__c = 'Kenverse University';
        save(params);

        Assert.areEqual('Kenverse University', KenSettings.institutionName('fallback'),
            'With no user or profile override the org default is what applies');
    }

    @isTest
    static void aUserLevelOverrideWins() {
        Ken_Alm_Org_Parameters__c params = orgDefault();
        params.Institution_Name__c = 'Org Level';
        save(params);

        insert new Ken_Alm_Org_Parameters__c(
            SetupOwnerId = UserInfo.getUserId(),
            Institution_Name__c = 'User Level'
        );
        KenSettings.cachedParameters = null;

        Assert.areEqual('User Level', KenSettings.institutionName('fallback'),
            'getInstance resolves the hierarchy - this is the value getOrgDefaults would have missed');
    }

    @isTest
    static void theAliasIsPreferredThenTheNameThenTheFallback() {
        Ken_Alm_Org_Parameters__c params = orgDefault();
        params.Institution_Alias__c = 'Kenverse';
        params.Institution_Name__c = 'Kenverse University';
        save(params);
        Assert.areEqual('Kenverse', KenSettings.institutionAlias('x'), 'The short alias wins when set');

        params.Institution_Alias__c = null;
        save(params);
        Assert.areEqual('Kenverse University', KenSettings.institutionAlias('x'),
            'A blank alias falls through to the full name rather than to the fallback');

        params.Institution_Name__c = null;
        save(params);
        Assert.areEqual('x', KenSettings.institutionAlias('x'), 'With neither set the caller decides');
    }

    @isTest
    static void neverReturnsNullForTheRecordItself() {
        Assert.isNotNull(KenSettings.orgParameters(),
            'Callers dereference this directly, so an org with no settings row must not NPE them');
    }

    @isTest
    static void portalUrlLosesATrailingSlash() {
        Ken_Alm_Org_Parameters__c params = orgDefault();
        params.Portal_URL__c = 'https://example.my.site.com/alumni/';
        save(params);

        Assert.areEqual('https://example.my.site.com/alumni', KenSettings.portalUrl(''),
            'Callers append a path, so a trailing slash would produce a double slash');
    }

    @isTest
    static void guardsHandleTheBlankAndUnsetCases() {
        Assert.areEqual('fallback', KenSettings.textOr('   ', 'fallback'), 'Whitespace is blank');
        Assert.areEqual('kept', KenSettings.textOr('  kept  ', 'fallback'), 'A real value is trimmed, not replaced');

        Assert.isFalse(KenSettings.isOn(null), 'An unset checkbox is off, never null');
        Assert.isFalse(KenSettings.isOn(false), 'An unticked checkbox is off');
        Assert.isTrue(KenSettings.isOn(true), 'Only an explicitly ticked box is on');

        Assert.areEqual(10, KenSettings.countOr(null, 10), 'An unset number uses the caller default');
        Assert.areEqual(10, KenSettings.countOr(0, 10), 'Zero is not a usable count');
        Assert.areEqual(3, KenSettings.countOr(3, 10), 'A real number is honoured');
    }

    @isTest
    static void theRecordIsReadOnlyOncePerTransaction() {
        Ken_Alm_Org_Parameters__c params = orgDefault();
        params.Institution_Name__c = 'First';
        save(params);

        Ken_Alm_Org_Parameters__c first = KenSettings.orgParameters();
        Ken_Alm_Org_Parameters__c second = KenSettings.orgParameters();

        Assert.isTrue(first === second, 'The second call must come from the cache, not a fresh read');
    }
}