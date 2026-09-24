/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 12-09-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public virtual class KenTriggerHandler {
  public static Boolean skipTrigger = false;
  public static Integer runCount = 0;

  public void process() {
    if (skipTrigger)
    {
      return;
    }

    runCount++;
      
      if (!Trigger.isExecuting) {
      return;
    }

    if (Trigger.isInsert) {
      if (Trigger.isBefore) {
        processBeforeInsert();
      }

      if (Trigger.isAfter) {
        processAfterInsert();
      }
    }

    if (Trigger.isUpdate) {
      if (Trigger.isBefore) {
        processBeforeUpdate();
      }
      if (Trigger.isAfter) {
        processAfterUpdate();
      }
    }

    if (Trigger.isDelete) {
      if (Trigger.isAfter) {
        processAfterDelete();
      }
    }

    if (Trigger.isUndelete) {
      if (Trigger.isAfter) {
        processAfterUndelete();
      }
    }
  }
    
  protected virtual void processBeforeInsert() {
  }
  protected virtual void processAfterInsert() {
  }
  protected virtual void processBeforeUpdate() {
  }
  protected virtual void processAfterUpdate() {
  }
  protected virtual void processAfterDelete() {
  }
  protected virtual void processAfterUndelete() {
  }
}