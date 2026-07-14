({
    getFileId : function(component, event, helper) {
        var action = component.get("c.getContentDocumentId");
        action.setParams({
            "recordId": component.get("v.recordId")
        });
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                component.set("v.fileId", response.getReturnValue());
            }
        });
        $A.enqueueAction(action);
    }
})