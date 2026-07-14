({
    setUserEmail : function(component) {
        var action = component.get("c.getEmail");
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                // Alert the user with the value returned 
                // from the server
                /*(function (i, s, o, g, r, a, m) {
                    i["GoogleAnalyticsObject"] = r;
                    (i[r] =
                     i[r] ||
                     function () {
                         (i[r].q = i[r].q || []).push(arguments);
                     }),
                        (i[r].l = 1 * new Date());
                    (a = s.createElement(o)), (m = s.getElementsByTagName(o)[0]);
                    a.async = 1;
                    a.src = g;
                    m.parentNode.insertBefore(a, m);
                })(window, document, "script", "/resource/SDO_Tool_DemoAppTrackGA", "ga");*/
                
                let org = component.get("v.page");
                let ga = window.ga;
                
                let dimensionValue = response.getReturnValue();
                
                if(org == ''){
                    org = 'SDO';
                }
                let page = component.get("v.org")+' '+org;
                
                ga("create", "UA-183945453-1", "auto");
                ga('set', 'dimension1', dimensionValue);
                ga("send", {
                    hitType: "event",
                    eventCategory: "pageview",
                    eventAction: "view",
                    eventLabel: page,
                    hitCallback: function() {
                        console.log('App Tracker Event Sent');
                    },
                    hitCallbackFail : function () {
                        console.log("App Tracker Failed");
                    }
                });
            }
            else {
                console.log('insight helper failed');
            }
        })
        
        $A.enqueueAction(action);
    }
})