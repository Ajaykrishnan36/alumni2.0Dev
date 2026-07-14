({
    getContentDocumentId : function(component) {
        var action = component.get("c.getContentDocumentLink");
        action.setParams({
            "recordId": component.get("v.recordId")
        });
        return action;
    }
})