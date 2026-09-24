import { LightningElement, track, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import defaultAvatar from "@salesforce/resourceUrl/AlumniAlt";
import donateImg from "@salesforce/resourceUrl/donateImg";
import eventTest1 from "@salesforce/resourceUrl/eventTest1";
import eventTest2 from "@salesforce/resourceUrl/eventTest2";
import PortalLoginImage from "@salesforce/resourceUrl/PortalLoginImage";
import requestServiceImg from "@salesforce/resourceUrl/requestServiceImg";
import suggestedGroupsbgimage from "@salesforce/resourceUrl/suggestedGroupsbgimage";
import getPersonalDetails from "@salesforce/apex/KenProfileSettingsController.getPersonalDetails";
import savePersonalDetails from "@salesforce/apex/KenProfileSettingsController.savePersonalDetails";
import saveEngagementPreferences from "@salesforce/apex/KenProfileSettingsController.saveEngagementPreferences";
import saveProfilePhoto from "@salesforce/apex/KenProfileSettingsController.saveProfilePhoto";
import getVerificationStatus from "@salesforce/apex/KenCommunityOtpLoginController.getVerificationStatus";
import saveMobileNumber from "@salesforce/apex/KenCommunityOtpLoginController.saveMobileNumber";
import startVerification from "@salesforce/apex/KenCommunityOtpLoginController.startVerification";
import confirmVerificationCode from "@salesforce/apex/KenCommunityOtpLoginController.confirmVerificationCode";

const INTEREST_OPTIONS = [
  {
    id: 1,
    label: "Learn from fellow alumni",
    name: "Learn from fellow alumni",
    img: donateImg
  },
  {
    id: 2,
    label: "Reconnect with my friends",
    name: "Reconnect with my friends",
    img: eventTest1
  },
  {
    id: 3,
    label: "Give back to the community",
    name: "Give back to the community",
    img: eventTest2
  },
  {
    id: 4,
    label: "Interested in hiring new talent",
    name: "Interested in hiring new talent",
    img: PortalLoginImage
  },
  {
    id: 5,
    label: "Looking to find a new job",
    name: "Looking to find a new job",
    img: requestServiceImg
  },
  {
    id: 6,
    label: "Grow my professional network",
    name: "Grow my professional network",
    img: suggestedGroupsbgimage
  }
];

export default class KenSettingPersonalDetails extends NavigationMixin(
  LightningElement
) {
  profilePic = defaultAvatar;

  @track isLoading = true;
  @track isSaving = false;
  @track showSuccessPopup = false;
  @track successPopupMessage = "Personal details saved successfully";
  @track error = null;

  @track firstName = "";
  @track lastName = "";
  @track maskedEmail = "";
  @track maskedPhone = "";
  @track email = "";
  @track phone = "";
  @track emailVerified = false;
  @track phoneVerified = false;
  @track verifyingChannel = "";
  @track otpCode = "";
  @track isVerifyBusy = false;
  @track verifyMessage = "";
  @track verifyMessageIsError = false;
  @track phoneDraft = "";
  @track phoneDraftValid = false;
  lastVerifiedChannel = "";
  @track city = "";
  @track country = "";
  @track state = "";
  @track linkedin = "";
  @track twitter = "";
  @track interests = [];

  // Personal Details card fields - self-editable, unlike the Alumna
  // Snapshot's institute-of-record fields (Registration Number, Program,
  // Class of, etc.), which stay read-only on the profile page.
  @track dob = "";
  @track gender = "";
  @track bloodGroup = "";
  @track nationality = "";
  @track languagesKnown = "";
  @track genderOptions = [];
  @track bloodGroupOptions = [];
  @track nationalityOptions = [];

  _pendingPhotoBase64 = null;
  _focusHandled = false;
  _accountId = null;

  @wire(CurrentPageReference) pageRef;

  connectedCallback() {
    this.loadData();
  }

  // Deep-link support: the profile page's Contact Details edit icon and the
  // LinkedIn Sync card's setup icon navigate here with state.focus set, so
  // the alumnus lands on the field instead of scrolling past Basic Details
  // and the interests grid to find the Social Media card themselves.
  renderedCallback() {
    if (this._focusHandled || this.isLoading) {
      return;
    }
    const focus = this.pageRef?.state?.focus;
    if (!focus) {
      return;
    }
    const anchor = this.template.querySelector(
      `[data-focus-anchor="${focus}"]`
    );
    if (!anchor) {
      return;
    }
    this._focusHandled = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      anchor.scrollIntoView({ behavior: "smooth", block: "center" });
      const input = anchor.querySelector("input, textarea, select");
      if (input) {
        input.focus();
      }
    }, 0);
  }

  async loadData() {
    this.isLoading = true;
    this.error = null;
    try {
      const data = await getPersonalDetails();
      if (data) {
        this._accountId = data.accountId || null;
        this.firstName = data.firstName || "";
        this.lastName = data.lastName || "";
        this.maskedEmail = data.maskedEmail || "";
        this.maskedPhone = data.maskedPhone || "";
        this.city = data.city || "";
        this.country = data.country || "";
        this.state = data.state || "";
        this.linkedin = data.linkedinUrl || "";
        this.twitter = data.twitterUrl || "";
        this.dob = data.dob || "";
        this.gender = data.gender || "";
        this.bloodGroup = data.bloodGroup || "";
        this.nationality = data.nationality || "";
        this.languagesKnown = data.languagesKnown || "";
        this.genderOptions = data.genderOptions || [];
        this.bloodGroupOptions = data.bloodGroupOptions || [];
        this.nationalityOptions = data.nationalityOptions || [];
        if (data.profileImageUrl) {
          this.profilePic = data.profileImageUrl;
        }
        this._buildInterests(data.engagementPreferences);
      }
      await this.loadVerificationStatus();
    } catch (e) {
      this.error = e?.body?.message || "Failed to load profile.";
    } finally {
      this.isLoading = false;
    }
  }

  _buildInterests(preferences) {
    const selected = new Set(
      preferences
        ? preferences
            .split(";")
            .map((v) => v.trim())
            .filter(Boolean)
        : []
    );
    this.interests = INTEREST_OPTIONS.map((opt) => ({
      ...opt,
      selected: selected.has(opt.name),
      checkboxClass: selected.has(opt.name)
        ? "custom-checkbox checked"
        : "custom-checkbox"
    }));
  }

  // Native <select> can't bind `value` directly in LWC (LWC1057), so each
  // option's `selected` is computed here instead - keeps these three in the
  // same .text-input styling as every other field instead of the darker,
  // non-overridable border that lightning-combobox's shadow DOM draws.
  get genderOptionsForSelect() {
    return (this.genderOptions || []).map((opt) => ({
      ...opt,
      selected: opt.value === this.gender
    }));
  }

  get bloodGroupOptionsForSelect() {
    return (this.bloodGroupOptions || []).map((opt) => ({
      ...opt,
      selected: opt.value === this.bloodGroup
    }));
  }

  get nationalityOptionsForSelect() {
    return (this.nationalityOptions || []).map((opt) => ({
      ...opt,
      selected: opt.value === this.nationality
    }));
  }

  handleFieldChange(event) {
    const field = event.currentTarget.dataset.field;
    // event.target.value covers native <input> and <select>; event.detail
    // is kept as a fallback for any lightning-* base component still in use.
    const value =
      event.detail && event.detail.value !== undefined
        ? event.detail.value
        : event.target.value;
    this[field] = value;
  }

  toggleInterest(event) {
    const id = parseInt(event.currentTarget.dataset.id, 10);
    this.interests = this.interests.map((item) => {
      if (item.id === id) {
        const selected = !item.selected;
        return {
          ...item,
          selected,
          checkboxClass: selected
            ? "custom-checkbox checked"
            : "custom-checkbox"
        };
      }
      return item;
    });
  }

  handleRequestEmailChange() {
    this.navigateToServiceSupport();
  }

  handleRequestPhoneChange() {
    this.navigateToServiceSupport();
  }

  navigateToServiceSupport() {
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: "service_support__c" }
    });
  }

  async loadVerificationStatus() {
    try {
      const status = await getVerificationStatus();
      this.email = status?.email || "";
      this.phone = status?.mobilePhone || "";
      this.emailVerified = status?.emailVerified === true;
      this.phoneVerified = status?.phoneVerified === true;
    } catch {
      this.email = "";
      this.phone = "";
    }
  }

  get isVerifyingEmail() {
    return this.verifyingChannel === "Email";
  }

  get isVerifyingPhone() {
    return this.verifyingChannel === "SMS";
  }

  get isPhoneEditable() {
    return !this.phone;
  }

  // The plain input this replaced hardcoded India's ten digits, so a nine-digit
  // UAE number could never be saved here and a fifteen-digit one sailed through.
  // The phone component reports validity against whichever country the user
  // picked, using the same rules as onboarding and registration.
  get isSavePhoneDisabled() {
    return this.isVerifyBusy || !this.phoneDraftValid;
  }

  handlePhoneDraftChange(event) {
    const { e164, isValid } = event.detail || {};
    this.phoneDraft = e164 || "";
    this.phoneDraftValid = isValid === true;
  }

  async handleSaveAndVerifyPhone() {
    this.isVerifyBusy = true;
    this.lastVerifiedChannel = "SMS";
    try {
      const saved = await saveMobileNumber({ phone: this.phoneDraft });
      if (!saved?.success) {
        this.setVerifyMessage(saved?.message || "Please try again.", true);
        return;
      }
      await this.loadVerificationStatus();
      this.phoneDraft = "";
    } catch (error) {
      this.setVerifyMessage(error?.body?.message || "Please try again.", true);
      return;
    } finally {
      this.isVerifyBusy = false;
    }
    await this.beginVerification("SMS");
  }

  get isConfirmDisabled() {
    return this.isVerifyBusy || (this.otpCode || "").length < 6;
  }

  get emailFieldLabel() {
    return this.isVerifyingEmail
      ? `Enter the code sent to ${this.email}`
      : "Email";
  }

  get phoneFieldLabel() {
    return this.isVerifyingPhone
      ? `Enter the code sent to ${this.phone}`
      : "Phone Number";
  }

  get emailVerifyMessage() {
    return this.verifyingChannel === "Email" ||
      this.lastVerifiedChannel === "Email"
      ? this.verifyMessage
      : "";
  }

  get phoneVerifyMessage() {
    return this.verifyingChannel === "SMS" || this.lastVerifiedChannel === "SMS"
      ? this.verifyMessage
      : "";
  }

  get emailVerifyMessageClass() {
    return this.verifyMessageIsError
      ? "field-note field-note_error"
      : "field-note";
  }

  get phoneVerifyMessageClass() {
    return this.emailVerifyMessageClass;
  }

  handleVerifyEmail() {
    this.beginVerification("Email");
  }

  handleVerifyPhone() {
    this.beginVerification("SMS");
  }

  async beginVerification(channel) {
    this.isVerifyBusy = true;
    this.otpCode = "";
    this.verifyMessage = "";
    this.lastVerifiedChannel = channel;
    try {
      const result = await startVerification({ channel });
      if (result?.debugMessage) {
        console.warn("Verification diagnostics:", result.debugMessage);
      }
      if (!result?.success) {
        this.setVerifyMessage(result?.message || "Please try again.", true);
        return;
      }
      this.verifyingChannel = channel;
    } catch (error) {
      this.setVerifyMessage(error?.body?.message || "Please try again.", true);
    } finally {
      this.isVerifyBusy = false;
    }
  }

  handleOtpInput(event) {
    this.otpCode = (event.target.value || "").replace(/[^0-9]/g, "");
    event.target.value = this.otpCode;
  }

  handleOtpKeyDown(event) {
    if (event.key === "Enter" && !this.isConfirmDisabled) {
      this.handleConfirmOtp();
    }
    if (event.key === "Escape") {
      this.handleCancelVerify();
    }
  }

  handleCancelVerify() {
    this.verifyingChannel = "";
    this.otpCode = "";
    this.verifyMessage = "";
  }

  async handleConfirmOtp() {
    const channel = this.verifyingChannel;
    this.isVerifyBusy = true;
    try {
      const result = await confirmVerificationCode({
        channel,
        code: this.otpCode
      });
      if (result?.debugMessage) {
        console.warn("Verification diagnostics:", result.debugMessage);
      }
      if (!result?.success) {
        this.setVerifyMessage(result?.message || "Please try again.", true);
        return;
      }
      this.verifyingChannel = "";
      this.otpCode = "";
      if (channel === "SMS") {
        this.phoneVerified = true;
      } else {
        this.emailVerified = true;
      }
      this.setVerifyMessage(
        "Verified. You can now sign in with a one-time password.",
        false
      );
    } catch (error) {
      this.setVerifyMessage(error?.body?.message || "Please try again.", true);
    } finally {
      this.isVerifyBusy = false;
    }
  }

  setVerifyMessage(message, isError) {
    this.verifyMessage = message;
    this.verifyMessageIsError = isError;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.verifyMessage = "";
    }, 6000);
  }

  readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const base64 = reader.result.split(",")[1];
        resolve({ fileData: base64, fileName: file.name });
      };
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  handleEditPicture() {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "image/png,image/jpeg,image/jpg";
    input.onchange = (e) => {
      const file = e.target.files && e.target.files[0];
      if (!file) return;
      if (file.size > 5 * 1024 * 1024) {
        this.error = "Image size must be less than 5MB";
        return;
      }
      const reader = new FileReader();
      reader.onload = (evt) => {
        this._pendingPhotoBase64 = evt.target.result;
        this.profilePic = evt.target.result;
      };
      reader.readAsDataURL(file);
    };
    input.click();
  }

  handleDiscard() {
    this._pendingPhotoBase64 = null;
    this.loadData();
  }

  async handleSave() {
    this.isSaving = true;
    this.error = null;
    try {
      if (this._pendingPhotoBase64) {
        const url = await saveProfilePhoto({
          base64Image: this._pendingPhotoBase64
        });
        this.profilePic = url;
        this._pendingPhotoBase64 = null;
      }

      await savePersonalDetails({
        requestJson: JSON.stringify({
          firstName: this.firstName,
          lastName: this.lastName,
          city: this.city,
          country: this.country,
          state: this.state,
          linkedinUrl: this.linkedin,
          twitterUrl: this.twitter,
          dob: this.dob,
          gender: this.gender,
          bloodGroup: this.bloodGroup,
          nationality: this.nationality,
          languagesKnown: this.languagesKnown
        })
      });

      const preferences = this.interests
        .filter((i) => i.selected)
        .map((i) => i.name)
        .join(";");
      await saveEngagementPreferences({ preferences });

      // This save is a plain Apex DML, not Lightning Data Service, so
      // other components with an LDS wire on this same Account (e.g.
      // the LinkedIn Sync card's getRecord wire) would otherwise keep
      // serving a stale cached copy - Sync from LinkedIn would look
      // permanently disabled even right after saving a LinkedIn URL.
      if (this._accountId) {
        getRecordNotifyChange([{ recordId: this._accountId }]);
      }

      this.successPopupMessage = "Personal details saved successfully";
      this.showSuccessPopup = true;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => {
        this.showSuccessPopup = false;
      }, 3000);
    } catch (e) {
      this.error = e?.body?.message || "Failed to save changes.";
    } finally {
      this.isSaving = false;
    }
  }
}