public class EDU_SSH_ResetCarePlans {
    
    public Id accId {get; set;}
    
   public EDU_SSH_ResetCarePlans(ApexPages.StandardController controller) {
        // We assign the ID of the record from the standard controller to accId
        this.accId = controller.getId();
    }
    
    public void resetCarePlans() {
        //Identify the Care Plan Template that should NEVER be deleted
        CarePlanTemplate cpt = [SELECT Id FROM CarePlanTemplate WHERE Name = 'Payment Plan' LIMIT 1];
        List<Task> actDelete = new List<Task>();
        List<BenefitAssignment> baDelete = new List<BenefitAssignment>();
        List<GoalAssignment> gDelete = new List<GoalAssignment>();
        List<ActionPlan> apDelete = new List<ActionPlan>();
        
        //Identify all existing Care Plans that are NOT tied to the persistent template
        List<CarePlan> plans = [SELECT Id FROM CarePlan WHERE CarePlanTemplateId !=: cpt.Id AND ParticipantId =: accId AND (NOT Name LIKE: '%First Year Student Success Plan')];
        System.debug(plans);

		        
        //Loop through Care Plans to delete all child records
        for (CarePlan cp : plans) {
            List<ActionPlan> apCP = [SELECT Id FROM ActionPlan WHERE TargetId =: cp.Id];
            apDelete.addAll(apCP);
            
            List<Task> cpAct = [SELECT Id FROM Task WHERE WhatId =: cp.Id];
            actDelete.addAll(cpAct);
            
            List<GoalAssignment> ga = [SELECT Id FROM GoalAssignment WHERE GoalAssigneeId =: accId AND ParentRecordId =: cp.Id];
            gDelete.addAll(ga);
            for (GoalAssignment g : ga) {
                List<Task> actGa = [SELECT Id FROM Task WHERE WhatId =: g.Id];
                actDelete.addAll(actGa);
                List<ActionPlan> apGA = [SELECT Id FROM ActionPlan WHERE TargetId =: g.Id];
            	apDelete.addAll(apGA);
                List<BenefitAssignment> baGA = [SELECT Id FROM BenefitAssignment WHERE EnrolleeId =: accId AND ParentRecordId =: g.Id];
                baDelete.addAll(baGA);
            }

            List<BenefitAssignment> ba = [SELECT Id FROM BenefitAssignment WHERE EnrolleeId =: accId AND ParentRecordId =: cp.Id];
            baDelete.addAll(ba);
               for (BenefitAssignment b : ba) {
                List<Task> actBa = [SELECT Id FROM Task WHERE WhatId =: b.Id];
                actDelete.addAll(actBa);
                List<ActionPlan> apBA = [SELECT Id FROM ActionPlan WHERE TargetId =: b.Id];
           	    apDelete.addAll(apBA);
            
               }
                       
        }
        
		delete apDelete;
        delete actDelete;
        delete baDelete;
        delete gDelete;
        delete plans;
        

    } 

}