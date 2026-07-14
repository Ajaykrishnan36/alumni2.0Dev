({
    handleWaive: function(component, event, helper) {
        helper.launchFlow(component, 'Waive');
    },
    handleApprove: function(component, event, helper) {
        helper.launchFlow(component, 'Approve');
    },
    handleReject: function(component, event, helper) {
        helper.launchFlow(component, 'Reject');
    }
})