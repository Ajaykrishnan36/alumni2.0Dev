window._snapinsSnippetSettingsFile = (function () {

    var meta = JSON.parse(sessionStorage.getItem('LSSIndex:SESSION{"namespace":"c"}'));
    //var contactFirstName = sessionStorage.getItem(meta.contactFirstName);
    //var contactLastName = sessionStorage.getItem(meta.contactLastName);
    //var contactEmail = sessionStorage.getItem(meta.contactEmail);

    var contactFirstName = "Sofia";
    var contactLastName = "Sanders";
    var contactEmail = "sofia.sanders@email.com";


    embedded_svc.menu.snippetSettingsFile = {
        Chat: {
            settings: {
                prepopulatedPrechatFields: {
                    "Email": contactEmail,
                    "FirstName": contactFirstName,
                    "LastName": contactLastName
                }
            }
        }
    };

})();
