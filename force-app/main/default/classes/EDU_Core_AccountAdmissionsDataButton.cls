public class EDU_Core_AccountAdmissionsDataButton {

    public EDU_Core_AccountAdmissionsDataButton(ApexPages.StandardController controller) {

    }

    
    // Method to be called by the button
    public void handleButtonClick() {
        
        //Get the System Admin profile ID
        String sysAdProfileId = [SELECT Id, Name FROM Profile WHERE Name = 'System Administrator'].Id;
        
        // Check if the user is a system administrator
        if (UserInfo.getProfileId() == sysAdProfileId) {
            
            //Get the name of the current app
        	UserAppInfo userAppInfo         = [SELECT Id, AppDefinitionId FROM UserAppInfo WHERE UserId = :UserInfo.getUserId() LIMIT 1];
        	AppDefinition appDefinition     = [SELECT DurableId, Label FROM AppDefinition Where DurableId = :userAppInfo.AppDefinitionId LIMIT 1];
        	String appName                  = appDefinition.Label;
            
            // Get the Account record for the current page
            Account account                 = [SELECT Id, Name, RecordType.Name, (SELECT Id, Name, AccountId FROM Contacts) FROM Account WHERE Id = :ApexPages.currentPage().getParameters().get('id')];
            
            //Get the Record Type records for Person Accounts so we can assign them later based on the app
            List<RecordType> paRecordTypes  = [SELECT Id, Name, IsPersonType, SobjectType FROM RecordType WHERE IsPersonType = TRUE];
            
            //Get the Contact record for the current account
            Contact contact                 = [SELECT Id, Name, AccountId FROM Contact WHERE AccountId = :account.Id];
            
            // Get the Record Alerts, Cases, Service Appointments, and the Constituent Roles that we'll want to edit
            List<RecordAlert> alerts        = [SELECT Id, Name, ParentId, WhatId, RecordAlertCategory.DeveloperName, RecordType.Name FROM RecordAlert WHERE (ParentId = :account.Id OR WhatId = :account.Id) AND RecordType.Name != NULL AND RecordAlertCategory.DeveloperName != NULL];
            List<Case> cases                = [SELECT Id, Subject, AccountId, ContactId, RecordType.Name, Status, CaseNumber, Type FROM Case WHERE (AccountId = :account.Id OR ContactId = :contact.Id) AND CaseNumber != '00068729' AND Subject != 'Registration Problem'];
            List<ConstituentRole> crs       = [SELECT Id, PersonId, RoleType FROM ConstituentRole WHERE PersonId = :account.Id];
            List<ServiceAppointment> sas    = [SELECT Id, Subject FROM ServiceAppointment WHERE AccountId = :account.Id];
            
            //Create a map to use for the Flow parameters when we update Sofia's record type
            Map<String, Object> params = new Map<String, Object>();
            
            // Determine which app we're in and set visibility accordingly
             
            // If in 'Recruitment & Admissions'...
            if(appName.contains('Recruit') || appName.contains('Admission')){
                
                //Loop through Record Alerts and hide the student related ones
                for(RecordAlert ra : alerts){
                    if(ra.RecordType.Name == 'Student' || ra.RecordAlertCategory.DeveloperName.contains('Student')){
                        ra.IsActive = FALSE;
                    }else if(ra.RecordType.Name == 'Admissions' || ra.RecordAlertCategory.DeveloperName.contains('Admission')){
                        ra.IsActive = TRUE;
                    }else if(ra.RecordType.Name == 'Advancement' || ra.RecordAlertCategory.DeveloperName.contains('Advancement')){
                        ra.IsActive = FALSE;
                    }else{
                        ra.IsActive = TRUE;
                    }
                    update ra;
            	}
                
                //Loop through Constituent Roles and change 'Student' to 'Applicant'
                for(ConstituentRole cr : crs){
                    if(cr.RoleType == 'Student' || cr.RoleType == 'Alum'){
                        cr.RoleType = 'Applicant';
                    }
                    update cr;
                }
                
                //Loop through Cases, close any Student related cases and open any Admissions ones
                for(Case c : cases){
                    if(c.RecordType.Name == 'Admissions' || c.RecordType.Name == 'RFI'){
                        c.Status = 'New';
                    }else{
                        c.Status = 'Closed';
                    }
                    update c;
                }
                
                //Set RecordType
                for (RecordType part : paRecordTypes){
                    if(part.Name == 'Admissions - Higher Ed - Person Account'){
                        params.put('partId', part.Id);
                        params.put('sofiasId', account.Id);
                        Flow.Interview.Update_Sofia_s_Record_Type flowToRun = new Flow.Interview.Update_Sofia_s_Record_Type(params);
                        flowToRun.start();
                    }
                }
                
            //If in 'Student Success'...
            }else if(appName.contains('Student')){
                
                //Loop through Record Alerts and hide the admissions related ones
                for(RecordAlert ra : alerts){
                    if(ra.RecordType.Name == 'Student' || ra.RecordAlertCategory.DeveloperName.contains('Student_Experience_Higher_Ed')){
                        ra.IsActive = TRUE;
                    	
                    }else{
                        ra.IsActive = FALSE;
                    }
                    update ra;
            	}
                
                //Loop through Constituent Roles and change 'Applicant' to 'Student'
                for(ConstituentRole cr : crs){
                    if(cr.RoleType == 'Applicant' || cr.RoleType == 'Alum'){
                        cr.RoleType = 'Student';
                    }
                    update cr;
                }
                
                //Loop through Cases, close any Admissions related cases and open any Student ones
                for(Case c : cases){
                    if(c.RecordType.Name == 'Admissions' || c.RecordType.Name == 'RFI'){
                        c.Status = 'Closed';
                    }else{
                        c.Status = 'New';
                    }
                    update c;
                }
                
                //Set RecordType
                for (RecordType part : paRecordTypes){
                    if(part.Name == 'Student Success - Higher Ed - Student'){
                        params.put('partId', part.Id);
                        params.put('sofiasId', account.Id);
                        Flow.Interview.Update_Sofia_s_Record_Type flowToRun = new Flow.Interview.Update_Sofia_s_Record_Type(params);
                        flowToRun.start();
                    }
                }
                
            //If in 'Advancement' Or 'Alumni'...
            }else if(appName.contains('Advancement') || appName.contains('Alumni')){
                
                //Loop through Record Alerts and hide the admissions related ones
                for(RecordAlert ra : alerts){
                    if(ra.RecordType.Name == 'Advancement'){
                        ra.IsActive = TRUE;
                    	
                    }else{
                        ra.IsActive = FALSE;
                    }
                    update ra;
            	}
                
                //Loop through Constituent Roles and change 'Applicant' to 'Student'
                for(ConstituentRole cr : crs){
                    if(cr.RoleType == 'Applicant' || cr.RoleType == 'Student'){
                        cr.RoleType = 'Alum';
                    }
                    update cr;
                }
                
                //Loop through Cases, close any Admissions related cases and open any Student ones
                for(Case c : cases){
                    if(c.RecordType.Name == 'Advancement'){
                        c.Status = 'New';
                    }else{
                        c.Status = 'Closed';
                    }
                    update c;
                }
                
                //Set RecordType
                for (RecordType part : paRecordTypes){
                    if(part.Name == 'Advancement - Higher Ed - Alumni'){
                        params.put('partId', part.Id);
                        params.put('sofiasId', account.Id);
                        Flow.Interview.Update_Sofia_s_Record_Type flowToRun = new Flow.Interview.Update_Sofia_s_Record_Type(params);
                        flowToRun.start();
                    }
                }
            }else{
                for(RecordAlert ra : alerts){
               	 ra.isActive = TRUE;
                 update ra;
                }
            }
        }
    }
}