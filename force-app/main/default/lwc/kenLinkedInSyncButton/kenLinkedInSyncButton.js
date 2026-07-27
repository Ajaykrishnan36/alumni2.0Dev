import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue, getRecordNotifyChange } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import syncAlumniSync from "@salesforce/apex/KenLinkedInController.syncAlumniSync";
import LAST_SYNC from "@salesforce/schema/Account.Last_LinkedIn_Sync__c";
import LINKEDIN_URL from "@salesforce/schema/Account.Linkedin_Profile_URL__c";

/**
 * Record-page button for the Person Account page: triggers the async LinkedIn
 * enrichment for this alumnus and shows the last sync time.
 */
export default class KenLinkedInSyncButton extends LightningElement {
  @api recordId;
  isSyncing = false;

  @wire(getRecord, { recordId: "$recordId", fields: [LAST_SYNC, LINKEDIN_URL] })
  account;

  get lastSyncLabel() {
    const value = getFieldValue(this.account.data, LAST_SYNC);
    return value ? new Date(value).toLocaleString() : "Never synced";
  }

  get hasLinkedIn() {
    return !!getFieldValue(this.account.data, LINKEDIN_URL);
  }

  get syncDisabled() {
    return this.isSyncing || !this.hasLinkedIn;
  }

  handleSync() {
    this.isSyncing = true;
    // Synchronous sync: a 401 / missing key / empty response surfaces as a
    // real error toast (the @future path swallowed those).
    syncAlumniSync({ accountId: this.recordId })
      .then(() => {
        this.toast(
          "LinkedIn sync complete",
          "Updated employment, education and certifications from LinkedIn.",
          "success",
        );
        // Re-fetch the record + related lists so the new rows appear on a
        // standard record page that hosts this card.
        getRecordNotifyChange([{ recordId: this.recordId }]);
        // Tell the parent (e.g. Alumni 360) so it can rerun its Apex wires
        // in place — no full page reload.
        this.dispatchEvent(new CustomEvent("synccomplete", { detail: { accountId: this.recordId } }));
      })
      .catch((error) => {
        const message =
          (error && error.body && error.body.message) || "Unable to sync from LinkedIn.";
        this.toast("Sync failed", message, "error");
      })
      .finally(() => {
        this.isSyncing = false;
      });
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}