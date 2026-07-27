import { LightningElement, api, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { CurrentPageReference } from "lightning/navigation";
import { wire } from "lwc";
import defaultBusinessImage from "@salesforce/resourceUrl/AlumniAlt";
import defaultProfileImage from "@salesforce/resourceUrl/AlumniAlt";
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getBusinessById from "@salesforce/apex/KenBusinessController.getBusinessById";
import updateBusiness from "@salesforce/apex/KenBusinessController.updateBusiness";
import createBusiness from "@salesforce/apex/KenBusinessController.createBusiness";
import expressInterest from "@salesforce/apex/KenBusinessController.expressInterest";
import requestFeature from "@salesforce/apex/KenBusinessController.requestFeature";
import setBusinessActive from "@salesforce/apex/KenBusinessController.setBusinessActive";
import deleteBusiness from "@salesforce/apex/KenBusinessController.deleteBusiness";
import approveBusinessDeletion from "@salesforce/apex/KenBusinessController.approveBusinessDeletion";
import dismissBusinessDeletion from "@salesforce/apex/KenBusinessController.dismissBusinessDeletion";
import removeFeature from "@salesforce/apex/KenBusinessController.removeFeature";
import linkSegmentationToParent from "@salesforce/apex/KenAudienceJunctionController.linkSegmentationToParent";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
export default class KenBusinessDetailView extends NavigationMixin(
  LightningElement
) {
  @api business;
  _isStandaloneMode = false;

  // Only apply the full-viewport height/scroll treatment when this component
  // is standalone on its own page (business_detail__c) — nothing else there
  // provides a bounded height. When embedded inside kenBusinessDirectory,
  // that parent already provides its own full-height container, so adding
  // a second one here would stack and break the internal scroll areas.
  get pageContainerClass() {
    return this._isStandaloneMode
      ? "business-detail-page standalone-page"
      : "business-detail-page";
  }
  // isMyBusiness can be passed as a prop hint (e.g. from My Businesses panel),
  // but the authoritative value is always businessData.isOwner from the server.
  @api isMyBusiness = false;
  @track businessData = {};
  @track showExpressInterestModal = false;
  @track showDeactivateModal = false;
  @track showDeleteModal = false;
  @track showBusinessListingForm = false;
  @track isEditMode = false;
  @track subject = "";
  @track message = "";
  // Feature request (Subject + Message, no dates)
  @track showFeatureModal = false;
  @track showRequestSent = false;
  @track isSubmittingFeature = false;
  @track featureSubject = "";
  @track featureMessage = "";
  @track featureDateFrom = "";
  @track featureDateTo = "";
  @track institutionName = "";
  @track interestDone = false;
  @track showReactivateModal = false;
  @track showRemoveFeatureModal = false;
  // Tracks the last `business` prop id we applied, so internal navigation
  // (clicking a similar business) isn't reverted by renderedCallback.
  _appliedBusinessPropId;

  // Only prefill the form when editing the current business.
  // "List Your Business" must open blank (treated as a new business).
  get listingFormBusiness() {
    return this.isEditMode ? this.businessData : undefined;
  }

  get editBusinessId() {
    return this.isEditMode ? this.businessData?.id : null;
  }

  @wire(CurrentPageReference)
  getStateParameters(currentPageReference) {
    if (currentPageReference && currentPageReference.state) {
      const businessId =
        currentPageReference.state.recordId ||
        currentPageReference.state.c__businessId ||
        currentPageReference.state.businessId;
      if (businessId && !this.businessData.id) {
        this.loadBusinessData(businessId);
      }
    }
  }

  connectedCallback() {
    this.updateBusinessData();
    getPrimaryColor()
      .then((color) => {
        this.institutionName = color?.institutionName || "";
        document.documentElement.style.setProperty(
          "--primary-color",
          color?.primaryColor
        );
        document.documentElement.style.setProperty(
          "--secondary-color",
          color?.secondaryColor
        );
        document.documentElement.style.setProperty(
          "--tertiary-color",
          color?.tertiaryColor
        );
      })
      .catch(() => {
        console.log("Error getting primary color");
      });
  }

  renderedCallback() {
    // Only react to an ACTUAL change of the incoming `business` prop.
    // Do NOT revert businessData when we navigate internally (e.g. clicking a
    // similar business updates businessData while the prop stays unchanged).
    if (
      this.business &&
      this.business.id &&
      this.business.id !== this._appliedBusinessPropId
    ) {
      this.updateBusinessData();
    }
  }

  updateBusinessData() {
    // If business is passed as prop, use it
    if (this.business && this.business.id) {
      this._appliedBusinessPropId = this.business.id;
      this.businessData = { ...this.business };
    } else if (!this.businessData || !this.businessData.id) {
      // Otherwise load from state or use default
      this.loadDefaultBusinessData();
    }
  }

  loadBusinessData(businessId) {
    // Only reached when no `business` prop was passed in (i.e. this component
    // is placed standalone on business_detail__c, not embedded inside
    // kenBusinessDirectory) — used by handleBack() to decide how to navigate.
    this._isStandaloneMode = true;
    getBusinessById({ businessId })
      .then((data) => {
        if (data) this.businessData = { ...data };
        else this.loadDefaultBusinessData();
      })
      .catch(() => this.loadDefaultBusinessData());
  }

  loadDefaultBusinessData() {
    this.businessData =
      this.businessData && this.businessData.id ? this.businessData : {};
  }

  get bannerImageUrl() {
    return this.businessData?.featuredImage || defaultBusinessImage;
  }

  get logoUrl() {
    return this.businessData?.logo || defaultBusinessImage;
  }

  get ownerImageUrl() {
    return this.businessData?.ownerImage || defaultProfileImage;
  }

  get aboutParagraph1() {
    return this.businessData?.description || "";
  }

  get hasBusinessData() {
    return this.businessData && this.businessData.id;
  }

  // Authoritative owner check: use server-returned isOwner if available,
  // fall back to the isMyBusiness prop (e.g. before first server load).
  get isOwner() {
    const d = this.businessData || {};
    return d.isOwner === true || this.isMyBusiness === true;
  }

  // Feature status badge — shown only to the owner of the business.
  get canSeeFeatureBadge() {
    return this.isOwner;
  }

  get featureBadge() {
    const d = this.businessData || {};
    const s = d.featureStatus;
    // A featured (approved) business shows a green "Featured" badge to EVERYONE.
    if (s === "Approved" && d.isCurrentlyFeatured) {
      return { show: true, text: "★ Featured", cls: "feature-badge fb-live" };
    }
    // Other states (under approval / rejected) are owner-only.
    if (!this.canSeeFeatureBadge) {
      return { show: false };
    }
    if (s === "Pending Approval") {
      return { show: true, text: "★ Feature: Under approval", cls: "feature-badge fb-pending" };
    }
    if (s === "Rejected") {
      return { show: true, text: "★ Feature request rejected", cls: "feature-badge fb-rejected" };
    }
    return { show: false };
  }

  get featureRejectionComment() {
    const d = this.businessData || {};
    return this.canSeeFeatureBadge &&
      d.featureStatus === "Rejected" &&
      d.featureRejectionReason
      ? d.featureRejectionReason
      : "";
  }

  // Business-approval rejection reason (shown in the pink box on the detail page).
  get businessRejectionReason() {
    const d = this.businessData || {};
    return this.canSeeFeatureBadge &&
      d.status === "Rejected" &&
      d.rejectionReason
      ? d.rejectionReason
      : "";
  }

  // "Request Feature in {Institute}" link: only the owner of an approved business
  // that isn't already pending/featured can request.
  get canRequestFeature() {
    const d = this.businessData || {};
    return (
      this.isOwner &&
      d.status === "Active" &&
      d.featureStatus !== "Pending Approval" &&
      !d.isCurrentlyFeatured
    );
  }

  get isBusinessActive() {
    return this.businessData?.status === "Active";
  }

  // Record is locked (either approval queue is open) — no write actions allowed.
  get isLocked() {
    const d = this.businessData || {};
    return d.status === "In review" || d.featureStatus === "Pending Approval";
  }

  // Tooltip text when a lock prevents an action.
  get lockTooltip() {
    const d = this.businessData || {};
    if (d.status === "In review") return "Business is under review — wait for admin decision";
    if (d.featureStatus === "Pending Approval") return "Feature approval is pending — wait for admin decision";
    return "";
  }

  get isDeletionRequested() {
    return (this.businessData?.status || '').toLowerCase() === 'deletion under review';
  }

  get isDeleted() {
    return (this.businessData?.status || '').toLowerCase() === 'deleted';
  }

  // Delete — disabled while locked (In Review, Feature Pending, Deletion Requested, or Deleted).
  get isDeleteDisabled() { return this.isLocked || this.isDeletionRequested || this.isDeleted; }
  get deleteTooltip() {
    if (this.isDeleted) return 'This business has been deleted';
    if (this.isDeletionRequested) return 'Deletion is under review — pending admin decision';
    return this.isLocked ? this.lockTooltip : 'Delete this listing';
  }

  // Single De-Activate / Re-Activate toggle button.
  get toggleActivateLabel() {
    const s = (this.businessData?.status || "").toLowerCase();
    return s === "de-activated" || s === "deactivated" ? "Re-Activate" : "De-Activate";
  }
  get toggleActivateClass() {
    const s = (this.businessData?.status || "").toLowerCase();
    return s === "de-activated" || s === "deactivated" ? "reactivate-btn" : "deactivate-btn";
  }
  get isToggleActivateDisabled() {
    const s = (this.businessData?.status || "").toLowerCase();
    if (s === "de-activated" || s === "deactivated") return this.isLocked;
    return this.isLocked || !this.isBusinessActive;
  }
  get toggleActivateTooltip() {
    if (this.isLocked) return this.lockTooltip;
    const s = (this.businessData?.status || "").toLowerCase();
    if (!this.isBusinessActive && s !== "de-activated" && s !== "deactivated")
      return "Only available for active businesses";
    return "";
  }

  // Edit enabled only when business is Active/In Review AND no feature pending.
  // If feature is under approval, edit is locked — submit/reject the feature first.
  get isEditDisabled() {
    const d = this.businessData || {};
    const s = (d.status || "").toLowerCase();
    if (d.featureStatus === "Pending Approval") return true;
    return s !== "active" && s !== "in review";
  }
  get editTooltip() {
    const d = this.businessData || {};
    const s = (d.status || "").toLowerCase();
    if (d.featureStatus === "Pending Approval")
      return "Feature approval is pending — wait for admin decision";
    if (s !== "active" && s !== "in review") return "Only available for active businesses";
    return "";
  }

  // Remove Featured — shown when featured or feature pending; disabled when pending.
  get showRemoveFeatureBtn() {
    const d = this.businessData || {};
    return this.isOwner && (d.isCurrentlyFeatured === true || d.featureStatus === "Pending Approval");
  }
  get isRemoveFeatureDisabled() {
    return (this.businessData?.featureStatus || "") === "Pending Approval";
  }
  get removeFeatureTooltip() {
    return this.isRemoveFeatureDisabled ? this.lockTooltip : "";
  }

  // ── Feature toggle (top-right of header, owner + active business only) ──────
  get featureToggleOn() {
    const d = this.businessData || {};
    return d.isCurrentlyFeatured === true || d.featureStatus === "Pending Approval";
  }

  get featureToggleClass() {
    const d = this.businessData || {};
    if (d.isCurrentlyFeatured) return "feature-toggle-btn toggle-on";
    if (d.featureStatus === "Pending Approval") return "feature-toggle-btn toggle-pending";
    return "feature-toggle-btn toggle-off";
  }

  get featureToggleDisabled() {
    return (this.businessData?.featureStatus || "") === "Pending Approval" || this.isLocked;
  }

  get featureToggleTooltip() {
    const d = this.businessData || {};
    if (d.featureStatus === "Pending Approval") return "Feature request is pending admin approval";
    if (this.isLocked) return this.lockTooltip;
    if (d.isCurrentlyFeatured) return "Toggle off to remove from featured";
    return "Toggle on to request featuring";
  }

  handleFeatureToggle() {
    const d = this.businessData || {};
    if (d.isCurrentlyFeatured) {
      this.showRemoveFeatureModal = true;
    } else {
      this.openFeatureModal();
    }
  }

  get submitFeatureBtnLabel() {
    return this.isSubmittingFeature ? "Sending…" : "Send for approval";
  }

  get isFeatureRequestValid() {
    return !!(this.featureSubject && this.featureMessage);
  }

  // Owner first name for "Chat with {name}".
  get ownerFirstName() {
    const n = (this.businessData && this.businessData.ownerName) || "";
    return n.split(" ")[0] || n;
  }

  // Express Interest -> "Interest Expressed" once done (server flag or this session).
  get alreadyExpressed() {
    return !!(this.businessData && this.businessData.interestExpressed) || this.interestDone;
  }

  // Status pill shown at the bottom-right for the owner.
  get statusLabel() {
    return this.businessData?.status || "";
  }

  get statusBadgeClass() {
    const s = (this.businessData?.status || "").toLowerCase();
    let mod = "st-review";
    if (s === "active") mod = "st-active";
    else if (s === "rejected") mod = "st-rejected";
    else if (s === "de-activated" || s === "deactivated") mod = "st-deactivated";
    else if (s === "deletion under review") mod = "st-deletion";
    else if (s === "deleted") mod = "st-deleted";
    return "status-badge-pill " + mod;
  }

  get showAdminDeletionActions() {
    return this.businessData?.isAdmin && this.isDeletionRequested;
  }

  handleBannerError(event) {
    if (event && event.target) {
      event.target.src = defaultBusinessImage;
    }
  }

  handleLogoError(event) {
    if (event && event.target) {
      event.target.src = defaultBusinessImage;
    }
  }

  handleOwnerImageError(event) {
    if (event && event.target) {
      event.target.src = defaultProfileImage;
    }
  }

  handleGetDirections() {
    // Open maps with business location
    const location = encodeURIComponent(this.businessData.location || "");
    window.open(
      `https://www.google.com/maps/search/?api=1&query=${location}`,
      "_blank"
    );
  }

  handleExpressInterest() {
    this.showExpressInterestModal = true;
  }

  handleCancel() {
    this.showExpressInterestModal = false;
    this.subject = "";
    this.message = "";
  }

  handleSubmit() {
    // Validate required fields
    if (!this.subject || !this.message) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Required",
          message: "Please fill in both subject and message.",
          variant: "error"
        })
      );
      return;
    }

    expressInterest({
      businessId: this.businessData.id,
      subject: this.subject,
      message: this.message
    })
      .then(() => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Interest sent",
            message: "Your interest has been shared with " + this.businessData.name + ".",
            variant: "success"
          })
        );
        this.showExpressInterestModal = false;
        this.subject = "";
        this.message = "";
        this.interestDone = true;
      })
      .catch((error) => {
        const msg =
          error && error.body && error.body.message
            ? error.body.message
            : "Could not submit your interest. Please try again.";
        this.dispatchEvent(
          new ShowToastEvent({ title: "Error", message: msg, variant: "error" })
        );
      });
  }

  handleSubjectChange(event) {
    this.subject = event.target.value;
  }

  handleMessageChange(event) {
    this.message = event.target.value;
  }

  handleModalOverlayClick(event) {
    // Close modal when clicking on overlay
    if (event.target.classList.contains("modal-overlay")) {
      this.handleCancel();
    }
  }

  handleModalContainerClick(event) {
    // Prevent closing when clicking inside modal
    event.stopPropagation();
  }

  handleDeactivateModalOverlayClick(event) {
    // Close modal when clicking on overlay
    if (event.target.classList.contains("modal-overlay")) {
      this.handleCancelDeactivate();
    }
  }

  handleDeleteModalOverlayClick(event) {
    // Close modal when clicking on overlay
    if (event.target.classList.contains("modal-overlay")) {
      this.handleCloseDeleteModal();
    }
  }

  handleChat() {
    // Handle chat functionality
    console.log("Chat clicked for:", this.businessData.name);
    // You can add chat modal or navigation logic here
  }

  handleDelete() {
    // Show delete confirmation modal
    this.showDeleteModal = true;
  }

  handleCloseDeleteModal() {
    // Close delete modal
    this.showDeleteModal = false;
  }

  handleDeactivateFromDelete() {
    // Close delete modal and open deactivate modal
    this.showDeleteModal = false;
    this.showDeactivateModal = true;
  }

  handleConfirmDelete() {
    const name = this.businessData.name;
    deleteBusiness({ businessId: this.businessData.id })
      .then(() => {
        this.showDeleteModal = false;
        this.businessData = { ...this.businessData, status: 'Deletion Requested' };
        this.dispatchEvent(
          new ShowToastEvent({ title: "Request Sent", message: "Deletion request for " + name + " has been submitted for admin review.", variant: "success" })
        );
      })
      .catch((error) => {
        const msg = error?.body?.message || "Could not delete. Please try again.";
        this.dispatchEvent(new ShowToastEvent({ title: "Error", message: msg, variant: "error" }));
        this.showDeleteModal = false;
      });
  }

  handleAdminApproveDeletion() {
    approveBusinessDeletion({ businessId: this.businessData.id })
      .then(() => {
        this.businessData = { ...this.businessData, status: 'Deleted' };
        this.dispatchEvent(
          new ShowToastEvent({ title: "Deletion Approved", message: this.businessData.name + " has been marked as Deleted.", variant: "success" })
        );
      })
      .catch((error) => {
        const msg = error?.body?.message || "Could not approve deletion. Please try again.";
        this.dispatchEvent(new ShowToastEvent({ title: "Error", message: msg, variant: "error" }));
      });
  }

  handleAdminDismissDeletion() {
    dismissBusinessDeletion({ businessId: this.businessData.id })
      .then(() => {
        this.businessData = { ...this.businessData, status: 'Active' };
        this.dispatchEvent(
          new ShowToastEvent({ title: "Dismissed", message: "Deletion request has been dismissed.", variant: "success" })
        );
      })
      .catch((error) => {
        const msg = error?.body?.message || "Could not dismiss. Please try again.";
        this.dispatchEvent(new ShowToastEvent({ title: "Error", message: msg, variant: "error" }));
      });
  }

  handleToggleActivate() {
    const s = (this.businessData?.status || "").toLowerCase();
    if (s === "de-activated" || s === "deactivated") {
      this.showReactivateModal = true;
    } else {
      this.showDeactivateModal = true;
    }
  }

  handleDeactivate() {
    this.showDeactivateModal = true;
  }

  handleCancelDeactivate() {
    // Close deactivate modal
    this.showDeactivateModal = false;
  }

  handleConfirmDeactivate() {
    setBusinessActive({ businessId: this.businessData.id, isActive: false })
      .then(() => getBusinessById({ businessId: this.businessData.id }))
      .then((data) => {
        if (data) this.businessData = { ...data };
        this.showDeactivateModal = false;
        this.dispatchEvent(
          new ShowToastEvent({ title: "Deactivated", message: "Your listing is now hidden from the directory.", variant: "success" })
        );
      })
      .catch((error) => {
        const msg = error?.body?.message || "Could not deactivate. Please try again.";
        this.dispatchEvent(new ShowToastEvent({ title: "Error", message: msg, variant: "error" }));
        this.showDeactivateModal = false;
      });
  }

  handleReactivate() {
    this.showReactivateModal = true;
  }

  handleCancelReactivate() {
    this.showReactivateModal = false;
  }

  handleReactivateModalOverlayClick(event) {
    if (event.target.classList.contains("modal-overlay")) {
      this.handleCancelReactivate();
    }
  }

  handleConfirmReactivate() {
    setBusinessActive({ businessId: this.businessData.id, isActive: true })
      .then(() => getBusinessById({ businessId: this.businessData.id }))
      .then((data) => {
        if (data) this.businessData = { ...data };
        this.showReactivateModal = false;
        this.dispatchEvent(
          new ShowToastEvent({ title: "Re-activated", message: "Your listing is now visible in the directory.", variant: "success" })
        );
      })
      .catch((error) => {
        const msg = error?.body?.message || "Could not re-activate. Please try again.";
        this.dispatchEvent(new ShowToastEvent({ title: "Error", message: msg, variant: "error" }));
        this.showReactivateModal = false;
      });
  }

  handleRemoveFeature() {
    this.showRemoveFeatureModal = true;
  }

  handleCancelRemoveFeature() {
    this.showRemoveFeatureModal = false;
  }

  handleRemoveFeatureModalOverlayClick(event) {
    if (event.target.classList.contains("modal-overlay")) {
      this.handleCancelRemoveFeature();
    }
  }

  handleConfirmRemoveFeature() {
    removeFeature({ businessId: this.businessData.id })
      .then(() => getBusinessById({ businessId: this.businessData.id }))
      .then((data) => {
        if (data) this.businessData = { ...data };
        this.showRemoveFeatureModal = false;
        this.dispatchEvent(
          new ShowToastEvent({ title: "Featured removed", message: "Your business has been removed from the featured list.", variant: "success" })
        );
      })
      .catch((error) => {
        const msg = error?.body?.message || "Could not remove feature. Please try again.";
        this.dispatchEvent(new ShowToastEvent({ title: "Error", message: msg, variant: "error" }));
        this.showRemoveFeatureModal = false;
      });
  }

  handleEditBusiness() {
    this.isEditMode = true;
    this.showBusinessListingForm = true;
  }

  handleSimilarSelect(event) {
    event.stopPropagation();
    const businessId = event.detail && event.detail.businessId;
    if (!businessId) {
      return;
    }
    getBusinessById({ businessId })
      .then((data) => {
        if (data) {
          this.businessData = { ...data };
          this.showExpressInterestModal = false;
          this.subject = "";
          this.message = "";
          try {
            window.scrollTo({ top: 0, behavior: "smooth" });
          } catch (e) {
            // ignore
          }
        }
      })
      .catch(() => {});
  }

  handleSimilarViewMore(event) {
    // "View More" -> go back to the all-businesses page
    event.stopPropagation();
    this.handleBack();
  }

  // ── Feature request (Subject + Message, no dates) ──────────────────────────
  openFeatureModal() {
    if (this.businessData?.status !== "Active") {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Not yet eligible",
          message:
            "Your business needs to be approved before you can request featuring.",
          variant: "info"
        })
      );
      return;
    }
    this.featureSubject = "";
    this.featureMessage = "";
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const twoWeeks = new Date();
    twoWeeks.setDate(twoWeeks.getDate() + 15);
    this.featureDateFrom = tomorrow.toISOString().slice(0, 10);
    this.featureDateTo = twoWeeks.toISOString().slice(0, 10);
    this.showFeatureModal = true;
  }

  closeFeatureModal() {
    this.showFeatureModal = false;
  }

  handleFeatureSubjectChange(event) {
    this.featureSubject = event.target.value;
  }

  handleFeatureMessageChange(event) {
    this.featureMessage = event.target.value;
  }

  handleFeatureDateFromChange(event) {
    this.featureDateFrom = event.target.value;
  }

  handleFeatureDateToChange(event) {
    this.featureDateTo = event.target.value;
  }

  get featureTodayStr() {
    return new Date().toISOString().slice(0, 10);
  }

  submitFeatureRequest() {
    if (!this.featureSubject || !this.featureMessage) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Required",
          message: "Please fill in both subject and message.",
          variant: "error"
        })
      );
      return;
    }
    if (!this.featureDateFrom || !this.featureDateTo) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Required",
          message: "Please select a feature date range.",
          variant: "error"
        })
      );
      return;
    }
    if (this.featureDateTo < this.featureDateFrom) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Invalid dates",
          message: "End date must be on or after the start date.",
          variant: "error"
        })
      );
      return;
    }
    this.isSubmittingFeature = true;
    requestFeature({
      businessId: this.businessData.id,
      subject: this.featureSubject,
      message: this.featureMessage,
      featuredFrom: this.featureDateFrom,
      featuredTo: this.featureDateTo
    })
      .then(() => getBusinessById({ businessId: this.businessData.id }))
      .then((data) => {
        if (data) this.businessData = { ...data };
        this.showFeatureModal = false;
        this.showRequestSent = true;
        setTimeout(() => { this.showRequestSent = false; }, 4000);
      })
      .catch((error) => {
        const msg =
          error && error.body && error.body.message
            ? error.body.message
            : "Could not submit your feature request. Please try again.";
        this.dispatchEvent(
          new ShowToastEvent({ title: "Error", message: msg, variant: "error" })
        );
      })
      .finally(() => {
        this.isSubmittingFeature = false;
      });
  }

  closeRequestSent() {
    this.showRequestSent = false;
  }

  handleBack() {
    // When embedded inside kenBusinessDirectory, let the parent handle "back"
    // exactly as it always has (unchanged embedded behavior). When placed
    // standalone on business_detail__c, there's no parent listening, so
    // navigate to the directory hub directly instead of a silent no-op.
    if (this._isStandaloneMode) {
      this[NavigationMixin.Navigate]({
        type: "comm__namedPage",
        attributes: { name: "business__c" }
      });
      return;
    }
    this.dispatchEvent(
      new CustomEvent("back", {
        bubbles: true,
        composed: true
      })
    );
  }

  handleListBusiness() {
    this.isEditMode = false;
    this.showBusinessListingForm = true;
  }

  handleCancelListingForm() {
    this.showBusinessListingForm = false;
  }

  handleSubmitListingForm(event) {
    const payload = event.detail || {};

    const req = {
      businessName: payload.businessName,
      businessType: payload.businessType,
      phone: payload.phone,
      hidePhone: payload.hidePhone,
      email: payload.email,
      hideEmail: payload.hideEmail,
      website: payload.website,
      address: payload.address,
      mapUrl: payload.mapUrl,
      description: payload.description,
      coverPictureName: payload.coverPictureName,
      coverPictureBase64: payload.coverPictureBase64,
      logoName: payload.logoName,
      logoBase64: payload.logoBase64
    };

    const form = this.template.querySelector("c-ken-business-listing-form");

    if (this.isEditMode) {
      // Edit existing business -> upsert with its id, then reload it
      req.id = this.businessData?.id;
      // Optional "feature this business" request (separate approval flow)
      req.requestFeature = payload.requestFeature === true;
      req.featuredFrom = payload.featuredFrom;
      req.featuredTo = payload.featuredTo;
      updateBusiness({ req })
        .then(() => getBusinessById({ businessId: this.businessData?.id }))
        .then((data) => {
          if (data) this.businessData = { ...data };
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Business updated",
              message: "Your changes have been saved and sent for re-approval.",
              variant: "success"
            })
          );
          if (form) {
            form.confirmSaved();
          } else {
            this.showBusinessListingForm = false;
          }
        })
        .catch(() => {
          if (form) form.resetSave();
        });
    } else {
      // List Your Business -> create a brand new business (no id)
      const segmentationId = payload.audienceSegmentationId || null;
      createBusiness({ req })
        .then((newBusinessId) => {
          if (segmentationId && newBusinessId) {
            return linkSegmentationToParent({
              parentObjectType: 'Business',
              parentId: newBusinessId,
              segmentationId
            }).catch(() => {});
          }
        })
        .then(() => {
          if (form) {
            form.confirmSaved();
          } else {
            this.showBusinessListingForm = false;
          }
        })
        .catch(() => {
          if (form) form.resetSave();
        });
    }
  }

  handleListingClose() {
    this.showBusinessListingForm = false;
    this.isEditMode = false;
  }
}