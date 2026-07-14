import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import syncAlumni from "@salesforce/apex/KenLinkedInController.syncAlumni";

/**
 * Headless record quick action ("Sync LinkedIn") for the Person Account page.
 * Kicks off the async LinkedIn enrichment for the current alumnus and toasts.
 */
export default class KenLinkedInSyncAction extends LightningElement {
  @api recordId;

  @api invoke() {
    syncAlumni({ accountId: this.recordId })
      .then(() => {
        this.toast(
          "LinkedIn sync started",
          "Fetching this alumnus's LinkedIn profile. Employment, education and certifications will update shortly.",
          "success",
        );
      })
      .catch((error) => {
        const message =
          (error && error.body && error.body.message) || "Unable to start LinkedIn sync.";
        this.toast("Sync failed", message, "error");
      });
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}