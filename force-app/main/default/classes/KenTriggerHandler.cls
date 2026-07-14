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
    
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void processBeforeInsert() {
  }
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void processAfterInsert() {
  }
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void processBeforeUpdate() {
  }
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void processAfterUpdate() {
  }
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void processAfterDelete() {
  }
  @SuppressWarnings('PMD.EmptyStatementBlock')
  protected virtual void processAfterUndelete() {
  }
}