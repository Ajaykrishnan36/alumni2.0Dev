({
    toggleWebcam : function(component, event, helper) {
        if(event.getParam("enableWebcam")){
            helper.getVideoStream(component, event, helper);
        } else{
            component.get("v.streamObj").getTracks()[0].stop();
            window.stream.getTracks()[0].stop();
        }
    },

    startVideoStream : function(component, event, helper) {
        helper.getVideoStream(component, event, helper);
    },

    stopVideoStream : function(component, event, helper) {
        component.get("v.streamObj").getTracks()[0].stop();
    }
})