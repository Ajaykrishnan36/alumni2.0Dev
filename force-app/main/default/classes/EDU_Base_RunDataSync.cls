public class EDU_Base_RunDataSync {
    
    public static void getConnector() {
        String connectorId;
        String baseURL = System.URL.getSalesforceBaseUrl().toExternalForm();
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();
        
        req.setEndpoint(baseURL+'/services/data/v57.0/wave/dataConnectors');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        
        try {
            res = http.send(req);
            System.debug(res.getBody());
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            connectorId = (String) ((Map<String, Object>) ((List<Object>) jsonMap.get('dataConnectors')).get(0)).get('id');
            
        } catch (System.CalloutException e) {
            System.debug('Callout error: ' + e);
        }
        System.debug('Id is = ' + connectorId);
        runDataSync(connectorId,baseURL);
    }
    
    
    public static void runDataSync(String conID, String baseURL){
        Http h = new Http();    
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseURL+'/services/data/v57.0/wave/dataConnectors/'+conId+'/ingest');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setBody('{}');
        
        // Send the request, and return a response
        HttpResponse res = h.send(req);
        System.debug(res);
    }
}