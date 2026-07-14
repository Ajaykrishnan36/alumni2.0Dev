({
    launchFlow: function(component, update) {
        var flowUrl = '/flow/EDU_RandA_Update_Document_Checklist_from_File?recordId=' + component.get('v.recordId') + '&update=' + update + '&retURL=apex/EDU_Base_CloseWindow';
        window.open(flowUrl);
        
    }
})