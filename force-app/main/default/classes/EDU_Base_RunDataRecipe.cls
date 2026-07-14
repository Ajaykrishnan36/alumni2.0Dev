public class EDU_Base_RunDataRecipe {
    
    public static void getRecipeId() {
        String connectorId;
        String dataflowId;
        
        String baseURL = System.URL.getSalesforceBaseUrl().toExternalForm();
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();
        
        req.setEndpoint(baseURL+'/services/data/v57.0/wave/recipes');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        
        try {
            res = http.send(req);
            System.debug(res.getBody());
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> recipes = (List<Object>) jsonMap.get('recipes');
            
            String recipeId = null;
            String recipeURL = null;
            
            for (Object recipe : recipes) {
                Map<String, Object> recipeMap = (Map<String, Object>) recipe;
                String label = (String) recipeMap.get('label');
                if (label.equals('Education_Analytics Education Analytics')) {
                    recipeId = (String) recipeMap.get('id');
                    dataflowId = (String) recipeMap.get('targetDataflowId');
                    System.debug(recipeId);
                    System.debug('DF is '+dataflowId);
                    //  recipeURL = baseURL+'/wave/recipes/'+recipeMap.get('id')+'?format=R3';
                    runDataRecipe(dataflowId, baseURL);
                    break;
                } 
            
            
        }

            }
        
                catch (System.CalloutException e) {
            System.debug('Callout error: ' + e);
        }
    }
    
            
               
        
        public static void runDataRecipe(String targetDataFlowId, String baseURL){
            Http h = new Http();    
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseURL+'/services/data/v57.0/wave/dataflowjobs');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
           
            //req.setBody('{"dataflowId": "'+targetDataFlowId +'","command": "start"}');
           req.setBody('{"dataflowId": "'+targetDataFlowId+'","command": "start"}'); 
            System.debug('req = '+req);
            
            // Send the request, and return a response
            HttpResponse res = h.send(req);
            System.debug(res);
        
        
    }
}