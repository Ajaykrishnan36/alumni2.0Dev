@IsTest
private class KenNamespaceUtilTest {

    @IsTest
    static void resolvesCustomObjectFromBareName() {
        Schema.SObjectType resolved = KenNamespaceUtil.resolveSObjectType('Ken_Event_Master__c');
        System.assertNotEquals(null, resolved, 'A bare custom object name should resolve with or without a namespace.');
        System.assertEquals(
            Ken_Event_Master__c.SObjectType,
            resolved,
            'The resolved type should be the packaged Ken_Event_Master__c.'
        );
    }

    @IsTest
    static void resolvesStandardObject() {
        System.assertEquals(
            Account.SObjectType,
            KenNamespaceUtil.resolveSObjectType('Account'),
            'Standard objects carry no namespace and must still resolve.'
        );
    }

    @IsTest
    static void resolvesNamespacedNameWhenSuppliedInFull() {
        String fullName = String.valueOf(Ken_Event_Master__c.SObjectType);
        System.assertEquals(
            Ken_Event_Master__c.SObjectType,
            KenNamespaceUtil.resolveSObjectType(fullName),
            'An already-qualified name should resolve on the first lookup.'
        );
    }

    @IsTest
    static void returnsNullForBlankAndUnknownNames() {
        System.assertEquals(null, KenNamespaceUtil.resolveSObjectType(null), 'Null should not resolve.');
        System.assertEquals(null, KenNamespaceUtil.resolveSObjectType(''), 'Blank should not resolve.');
        System.assertEquals(null, KenNamespaceUtil.resolveSObjectType('No_Such_Object__c'), 'Unknown names should not resolve.');
    }

    @IsTest
    static void resolvesFieldMap() {
        Map<String, Schema.SObjectField> fields = KenNamespaceUtil.resolveFieldMap('Ken_Event_Master__c');
        System.assertNotEquals(null, fields, 'A resolvable object should return a field map.');
        System.assert(fields.containsKey('name'), 'The field map should contain the Name field.');
        System.assertEquals(null, KenNamespaceUtil.resolveFieldMap('No_Such_Object__c'), 'Unknown objects return null.');
    }

    @IsTest
    static void resolvesApexTypeFromBareName() {
        System.assertNotEquals(
            null,
            KenNamespaceUtil.resolveType('KenNamespaceUtil'),
            'A bare class name should resolve with or without a namespace.'
        );
        System.assertEquals(null, KenNamespaceUtil.resolveType(null), 'Null should not resolve.');
        System.assertEquals(null, KenNamespaceUtil.resolveType('NoSuchClassAnywhere'), 'Unknown classes should not resolve.');
    }

    @IsTest
    static void namespacePrefixIsConsistentWithTheReferenceObject() {
        String prefix = KenNamespaceUtil.namespacePrefix();
        String fullName = String.valueOf(Ken_Event_Master__c.SObjectType);
        System.assertEquals(
            prefix + 'Ken_Event_Master__c',
            fullName,
            'The derived prefix plus the bare name must reconstruct the full API name.'
        );
    }
}