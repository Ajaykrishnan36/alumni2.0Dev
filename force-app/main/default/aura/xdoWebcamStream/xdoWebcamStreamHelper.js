({
    getVideoStream : function(component, event, helper) {
        // console.log('navigator', navigator);
        
        navigator.mediaDevices.getUserMedia({
            audio: false,
            video: {
              width: { ideal: 1280 },
              height: { ideal: 720 }
            }
        }).then((stream) => {
            // console.log('stream variable', typeof stream);
            // console.log(stream);
            // console.log('tracks');
            // console.log(stream.getTracks());

            window.stream = stream;
            component.find("videostream").getElement().srcObject = stream;
            component.set("v.streamObj", stream);

            if(component.get('v.showYouText')){
              component.set('v.youTextEnabled', true);
            }

            if(component.get('v.showMicLogo')){
              component.set('v.micLogoEnabled', true);
            }
        })
        .catch((error) => {
          console.log('error', error);
        });
    }
})