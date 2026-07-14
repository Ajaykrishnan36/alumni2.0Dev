import { LightningElement, api, track, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { loadScript, loadStyle } from "lightning/platformResourceLoader";
import intlTelInputResource from "@salesforce/resourceUrl/intlTelInput";
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import createBusiness from "@salesforce/apex/KenBusinessController.createBusiness";

// Complete country list in JSON-style objects with ISO code and dial code
const COUNTRY_JSON = [
  { label: "Afghanistan", dialCode: "+93", code: "AF" },
  { label: "Albania", dialCode: "+355", code: "AL" },
  { label: "Algeria", dialCode: "+213", code: "DZ" },
  { label: "Andorra", dialCode: "+376", code: "AD" },
  { label: "Angola", dialCode: "+244", code: "AO" },
  { label: "Antigua and Barbuda", dialCode: "+1-268", code: "AG" },
  { label: "Argentina", dialCode: "+54", code: "AR" },
  { label: "Armenia", dialCode: "+374", code: "AM" },
  { label: "Australia", dialCode: "+61", code: "AU" },
  { label: "Austria", dialCode: "+43", code: "AT" },
  { label: "Azerbaijan", dialCode: "+994", code: "AZ" },
  { label: "Bahamas", dialCode: "+1-242", code: "BS" },
  { label: "Bahrain", dialCode: "+973", code: "BH" },
  { label: "Bangladesh", dialCode: "+880", code: "BD" },
  { label: "Barbados", dialCode: "+1-246", code: "BB" },
  { label: "Belarus", dialCode: "+375", code: "BY" },
  { label: "Belgium", dialCode: "+32", code: "BE" },
  { label: "Belize", dialCode: "+501", code: "BZ" },
  { label: "Benin", dialCode: "+229", code: "BJ" },
  { label: "Bhutan", dialCode: "+975", code: "BT" },
  { label: "Bolivia", dialCode: "+591", code: "BO" },
  { label: "Bosnia and Herzegovina", dialCode: "+387", code: "BA" },
  { label: "Botswana", dialCode: "+267", code: "BW" },
  { label: "Brazil", dialCode: "+55", code: "BR" },
  { label: "Brunei", dialCode: "+673", code: "BN" },
  { label: "Bulgaria", dialCode: "+359", code: "BG" },
  { label: "Burkina Faso", dialCode: "+226", code: "BF" },
  { label: "Burundi", dialCode: "+257", code: "BI" },
  { label: "Cambodia", dialCode: "+855", code: "KH" },
  { label: "Cameroon", dialCode: "+237", code: "CM" },
  { label: "Canada", dialCode: "+1", code: "CA" },
  { label: "Cape Verde", dialCode: "+238", code: "CV" },
  { label: "Central African Republic", dialCode: "+236", code: "CF" },
  { label: "Chad", dialCode: "+235", code: "TD" },
  { label: "Chile", dialCode: "+56", code: "CL" },
  { label: "China", dialCode: "+86", code: "CN" },
  { label: "Colombia", dialCode: "+57", code: "CO" },
  { label: "Comoros", dialCode: "+269", code: "KM" },
  { label: "Costa Rica", dialCode: "+506", code: "CR" },
  { label: "Croatia", dialCode: "+385", code: "HR" },
  { label: "Cuba", dialCode: "+53", code: "CU" },
  { label: "Cyprus", dialCode: "+357", code: "CY" },
  { label: "Czech Republic", dialCode: "+420", code: "CZ" },
  { label: "Denmark", dialCode: "+45", code: "DK" },
  { label: "Djibouti", dialCode: "+253", code: "DJ" },
  { label: "Dominica", dialCode: "+1-767", code: "DM" },
  { label: "Dominican Republic", dialCode: "+1-809", code: "DO" },
  { label: "Ecuador", dialCode: "+593", code: "EC" },
  { label: "Egypt", dialCode: "+20", code: "EG" },
  { label: "El Salvador", dialCode: "+503", code: "SV" },
  { label: "Equatorial Guinea", dialCode: "+240", code: "GQ" },
  { label: "Eritrea", dialCode: "+291", code: "ER" },
  { label: "Estonia", dialCode: "+372", code: "EE" },
  { label: "Eswatini", dialCode: "+268", code: "SZ" },
  { label: "Ethiopia", dialCode: "+251", code: "ET" },
  { label: "Fiji", dialCode: "+679", code: "FJ" },
  { label: "Finland", dialCode: "+358", code: "FI" },
  { label: "France", dialCode: "+33", code: "FR" },
  { label: "Gabon", dialCode: "+241", code: "GA" },
  { label: "Gambia", dialCode: "+220", code: "GM" },
  { label: "Georgia", dialCode: "+995", code: "GE" },
  { label: "Germany", dialCode: "+49", code: "DE" },
  { label: "Ghana", dialCode: "+233", code: "GH" },
  { label: "Greece", dialCode: "+30", code: "GR" },
  { label: "Grenada", dialCode: "+1-473", code: "GD" },
  { label: "Guatemala", dialCode: "+502", code: "GT" },
  { label: "Guinea", dialCode: "+224", code: "GN" },
  { label: "Guinea-Bissau", dialCode: "+245", code: "GW" },
  { label: "Guyana", dialCode: "+592", code: "GY" },
  { label: "Haiti", dialCode: "+509", code: "HT" },
  { label: "Honduras", dialCode: "+504", code: "HN" },
  { label: "Hong Kong", dialCode: "+852", code: "HK" },
  { label: "Hungary", dialCode: "+36", code: "HU" },
  { label: "Iceland", dialCode: "+354", code: "IS" },
  { label: "India", dialCode: "+91", code: "IN" },
  { label: "Indonesia", dialCode: "+62", code: "ID" },
  { label: "Iran", dialCode: "+98", code: "IR" },
  { label: "Iraq", dialCode: "+964", code: "IQ" },
  { label: "Ireland", dialCode: "+353", code: "IE" },
  { label: "Israel", dialCode: "+972", code: "IL" },
  { label: "Italy", dialCode: "+39", code: "IT" },
  { label: "Jamaica", dialCode: "+1-876", code: "JM" },
  { label: "Japan", dialCode: "+81", code: "JP" },
  { label: "Jordan", dialCode: "+962", code: "JO" },
  { label: "Kazakhstan", dialCode: "+7", code: "KZ" },
  { label: "Kenya", dialCode: "+254", code: "KE" },
  { label: "Kiribati", dialCode: "+686", code: "KI" },
  { label: "Kuwait", dialCode: "+965", code: "KW" },
  { label: "Kyrgyzstan", dialCode: "+996", code: "KG" },
  { label: "Laos", dialCode: "+856", code: "LA" },
  { label: "Latvia", dialCode: "+371", code: "LV" },
  { label: "Lebanon", dialCode: "+961", code: "LB" },
  { label: "Lesotho", dialCode: "+266", code: "LS" },
  { label: "Liberia", dialCode: "+231", code: "LR" },
  { label: "Libya", dialCode: "+218", code: "LY" },
  { label: "Liechtenstein", dialCode: "+423", code: "LI" },
  { label: "Lithuania", dialCode: "+370", code: "LT" },
  { label: "Luxembourg", dialCode: "+352", code: "LU" },
  { label: "Macau", dialCode: "+853", code: "MO" },
  { label: "Madagascar", dialCode: "+261", code: "MG" },
  { label: "Malawi", dialCode: "+265", code: "MW" },
  { label: "Malaysia", dialCode: "+60", code: "MY" },
  { label: "Maldives", dialCode: "+960", code: "MV" },
  { label: "Mali", dialCode: "+223", code: "ML" },
  { label: "Malta", dialCode: "+356", code: "MT" },
  { label: "Marshall Islands", dialCode: "+692", code: "MH" },
  { label: "Mauritania", dialCode: "+222", code: "MR" },
  { label: "Mauritius", dialCode: "+230", code: "MU" },
  { label: "Mexico", dialCode: "+52", code: "MX" },
  { label: "Micronesia", dialCode: "+691", code: "FM" },
  { label: "Moldova", dialCode: "+373", code: "MD" },
  { label: "Monaco", dialCode: "+377", code: "MC" },
  { label: "Mongolia", dialCode: "+976", code: "MN" },
  { label: "Montenegro", dialCode: "+382", code: "ME" },
  { label: "Morocco", dialCode: "+212", code: "MA" },
  { label: "Mozambique", dialCode: "+258", code: "MZ" },
  { label: "Myanmar", dialCode: "+95", code: "MM" },
  { label: "Namibia", dialCode: "+264", code: "NA" },
  { label: "Nauru", dialCode: "+674", code: "NR" },
  { label: "Nepal", dialCode: "+977", code: "NP" },
  { label: "Netherlands", dialCode: "+31", code: "NL" },
  { label: "New Zealand", dialCode: "+64", code: "NZ" },
  { label: "Nicaragua", dialCode: "+505", code: "NI" },
  { label: "Niger", dialCode: "+227", code: "NE" },
  { label: "Nigeria", dialCode: "+234", code: "NG" },
  { label: "North Macedonia", dialCode: "+389", code: "MK" },
  { label: "Norway", dialCode: "+47", code: "NO" },
  { label: "Oman", dialCode: "+968", code: "OM" },
  { label: "Pakistan", dialCode: "+92", code: "PK" },
  { label: "Palau", dialCode: "+680", code: "PW" },
  { label: "Panama", dialCode: "+507", code: "PA" },
  { label: "Papua New Guinea", dialCode: "+675", code: "PG" },
  { label: "Paraguay", dialCode: "+595", code: "PY" },
  { label: "Peru", dialCode: "+51", code: "PE" },
  { label: "Philippines", dialCode: "+63", code: "PH" },
  { label: "Poland", dialCode: "+48", code: "PL" },
  { label: "Portugal", dialCode: "+351", code: "PT" },
  { label: "Qatar", dialCode: "+974", code: "QA" },
  { label: "Romania", dialCode: "+40", code: "RO" },
  { label: "Russia", dialCode: "+7", code: "RU" },
  { label: "Rwanda", dialCode: "+250", code: "RW" },
  { label: "Saint Kitts and Nevis", dialCode: "+1-869", code: "KN" },
  { label: "Saint Lucia", dialCode: "+1-758", code: "LC" },
  { label: "Saint Vincent and the Grenadines", dialCode: "+1-784", code: "VC" },
  { label: "Samoa", dialCode: "+685", code: "WS" },
  { label: "San Marino", dialCode: "+378", code: "SM" },
  { label: "São Tomé and Príncipe", dialCode: "+239", code: "ST" },
  { label: "Saudi Arabia", dialCode: "+966", code: "SA" },
  { label: "Senegal", dialCode: "+221", code: "SN" },
  { label: "Serbia", dialCode: "+381", code: "RS" },
  { label: "Seychelles", dialCode: "+248", code: "SC" },
  { label: "Sierra Leone", dialCode: "+232", code: "SL" },
  { label: "Singapore", dialCode: "+65", code: "SG" },
  { label: "Slovakia", dialCode: "+421", code: "SK" },
  { label: "Slovenia", dialCode: "+386", code: "SI" },
  { label: "Solomon Islands", dialCode: "+677", code: "SB" },
  { label: "Somalia", dialCode: "+252", code: "SO" },
  { label: "South Africa", dialCode: "+27", code: "ZA" },
  { label: "South Korea", dialCode: "+82", code: "KR" },
  { label: "South Sudan", dialCode: "+211", code: "SS" },
  { label: "Spain", dialCode: "+34", code: "ES" },
  { label: "Sri Lanka", dialCode: "+94", code: "LK" },
  { label: "Sudan", dialCode: "+249", code: "SD" },
  { label: "Suriname", dialCode: "+597", code: "SR" },
  { label: "Sweden", dialCode: "+46", code: "SE" },
  { label: "Switzerland", dialCode: "+41", code: "CH" },
  { label: "Syria", dialCode: "+963", code: "SY" },
  { label: "Taiwan", dialCode: "+886", code: "TW" },
  { label: "Tajikistan", dialCode: "+992", code: "TJ" },
  { label: "Tanzania", dialCode: "+255", code: "TZ" },
  { label: "Thailand", dialCode: "+66", code: "TH" },
  { label: "Togo", dialCode: "+228", code: "TG" },
  { label: "Tonga", dialCode: "+676", code: "TO" },
  { label: "Trinidad and Tobago", dialCode: "+1-868", code: "TT" },
  { label: "Tunisia", dialCode: "+216", code: "TN" },
  { label: "Turkey", dialCode: "+90", code: "TR" },
  { label: "Turkmenistan", dialCode: "+993", code: "TM" },
  { label: "Tuvalu", dialCode: "+688", code: "TV" },
  { label: "Uganda", dialCode: "+256", code: "UG" },
  { label: "Ukraine", dialCode: "+380", code: "UA" },
  { label: "United Arab Emirates", dialCode: "+971", code: "AE" },
  { label: "United Kingdom", dialCode: "+44", code: "GB" },
  { label: "United States", dialCode: "+1", code: "US" },
  { label: "Uruguay", dialCode: "+598", code: "UY" },
  { label: "Uzbekistan", dialCode: "+998", code: "UZ" },
  { label: "Vanuatu", dialCode: "+678", code: "VU" },
  { label: "Vatican City", dialCode: "+379", code: "VA" },
  { label: "Venezuela", dialCode: "+58", code: "VE" },
  { label: "Vietnam", dialCode: "+84", code: "VN" },
  { label: "Yemen", dialCode: "+967", code: "YE" },
  { label: "Zambia", dialCode: "+260", code: "ZM" },
  { label: "Zimbabwe", dialCode: "+263", code: "ZW" }
];

export default class KenBusinessListingForm extends NavigationMixin(LightningElement) {
    _roleId = localStorage.getItem('ConstituentRoleId');
  @api business; // when provided, form works in edit mode
  // When true, this component is placed standalone on create_business__c
  // (no kenBusinessDirectory parent listening for submit/cancel/closeform),
  // so it must call Apex and navigate itself instead of just dispatching
  // events for a parent to handle.
  @api standalone = false;

  // The Builder-configured `standalone` attribute above depends on that page
  // property having been published — if it's ever stale/unset, dispatching
  // "submit" here would silently go nowhere (no parent is listening on
  // create_business__c), leaving the Save button stuck forever with no
  // error. Self-detecting the route as a fallback, the same way
  // kenBusinessDetailView detects its own standalone mode, makes this
  // resilient to that page-config drifting out of sync.
  @wire(CurrentPageReference) currentPageReference;

  get isStandaloneContext() {
    return (
      this.standalone ||
      this.currentPageReference?.attributes?.name === "create_business__c"
    );
  }

  @track formData = {
    coverPicture: null,
    logo: null,
    businessName: "",
    businessType: "",
    countryCode: "+91",
    phone: "",
    hidePhone: true,
    email: "",
    hideEmail: true,
    website: "",
    address: "",
    mapUrl: "",
    description: "",
    requestFeature: false,
    featuredFrom: "",
    featuredTo: ""
  };

  @track showCountryCodeDropdown = false;
  @track showFeatureModal = false;
  @track saveStatus = "idle"; // idle | saving | saved
  @track isToastVisible = false;
  @track toastTitle = "";
  @track toastMessage = "";
  @track toastVariant = "error";
  @track phoneError = "";
  @track nameError = "";
  @track typeError = "";
  @track emailError = "";
  @track websiteError = "";
  @track mapUrlError = "";
  @track coverPreviewUrl = null;
  @track countrySearchTerm = "";
  intlTelInputInstance = null;
  intlTelInputLoaded = false;

  _hasInitializedFromBusiness = false;

  get countryCodeOptions() {
    let options = COUNTRY_JSON.map((option) => ({
      ...option,
      flag: this.getFlagEmoji(option.code),
      selectedClass:
        option.dialCode === this.formData.countryCode
          ? "country-code-option selected"
          : "country-code-option"
    }));

    // Filter by search term if exists
    if (this.countrySearchTerm) {
      const search = this.countrySearchTerm.toLowerCase();
      options = options.filter(
        (option) =>
          option.label.toLowerCase().includes(search) ||
          option.dialCode.includes(search) ||
          option.code.toLowerCase().includes(search)
      );
    }

    return options;
  }

  get selectedCountryCode() {
    const selected = this.countryCodeOptions.find(
      (opt) => opt.dialCode === this.formData.countryCode
    );
    return selected || this.countryCodeOptions[0];
  }

  getFlagEmoji(countryCode) {
    if (!countryCode) return "";
    return countryCode
      .toUpperCase()
      .split("")
      .map((char) => String.fromCodePoint(127397 + char.charCodeAt()))
      .join("");
  }

  get indianFlagIcon() {
    return "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMTUiIHZpZXdCb3g9IjAgMCAyMCAxNSIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHJlY3Qgd2lkdGg9IjIwIiBoZWlnaHQ9IjUiIGZpbGw9IiNGRkZGRkYiLz4KPHJlY3QgeT0iNSIgd2lkdGg9IjIwIiBoZWlnaHQ9IjUiIGZpbGw9IiNGRkY1MDAiLz4KPHJlY3QgeT0iMTAiIHdpZHRoPSIyMCIgaGVpZ2h0PSI1IiBmaWxsPSIjMDA5OTAwIi8+CjxjaXJjbGUgY3g9IjEwIiBjeT0iNy41IiByPSIyLjUiIGZpbGw9IiMwMDAwODAiLz4KPC9zdmc+";
  }

  get saveButtonLabel() {
    if (this.saveStatus === "saving") return "Saving…";
    if (this.saveStatus === "saved") return this.isEditing ? "Updated ✓" : "Requested ✓";
    return this.isEditing ? "Update Business" : "Request Listing";
  }

  get saveButtonClass() {
    return this.saveStatus === "saved" ? "submit-btn is-saved" : "submit-btn";
  }

  get isSaveDisabled() {
    return this.saveStatus !== "idle";
  }

  get getPhonePlaceholder() {
    if (this.formData.countryCode === "+91") {
      return "0000 0000 00";
    } else if (this.formData.countryCode === "+1") {
      return "(000) 000-0000";
    }
    return "0000 0000 0000";
  }

  get phoneValidationRules() {
    return {
      "+91": { digits: 10, label: "India (+91)" },
      "+1": { digits: 10, label: "USA (+1)" },
      "+44": { min: 10, max: 11, label: "UK (+44)" },
      "+61": { min: 9, max: 10, label: "Australia (+61)" },
      "+65": { digits: 8, label: "Singapore (+65)" },
      "+971": { digits: 9, label: "UAE (+971)" }
    };
  }

  handleCoverPictureUpload() {
    const fileInput = this.template.querySelector(
      '[data-field="coverPicture"]'
    );
    if (fileInput) {
      fileInput.click();
    }
  }

  handleCoverPictureChange(event) {
    const file = event.target.files[0];
    if (file) {
      if (file.size > 5 * 1024 * 1024) {
        return;
      }
      this.formData.coverPicture = file;
      const reader = new FileReader();
      reader.onload = (e) => {
        this.coverPreviewUrl = e.target.result;
      };
      reader.readAsDataURL(file);
    }
  }

  handleRemoveCoverPicture(event) {
    event.stopPropagation();
    this.formData.coverPicture = null;
    this.coverPreviewUrl = null;
    const fileInput = this.template.querySelector('[data-field="coverPicture"]');
    if (fileInput) fileInput.value = "";
  }

  handleLogoChange(event) {
    const file = event.target.files[0];
    if (file) {
      // Validate file size (1 MB)
      if (file.size > 1 * 1024 * 1024) {
        console.warn("Logo too large (max 1 MB).");
        return;
      }
      this.formData.logo = file;
      const fileInputDisplay = event.target
        .closest(".file-input-wrapper")
        .querySelector(".file-placeholder");
      if (fileInputDisplay) {
        fileInputDisplay.textContent = file.name;
      }
      console.log("Logo selected:", file.name);
    }
  }

  handleBusinessNameChange(event) {
    this.formData.businessName = event.target.value;
    if (this.formData.businessName) this.nameError = "";
  }

  handleBusinessTypeChange(event) {
    this.formData.businessType = event.target.value;
    if (this.formData.businessType) this.typeError = "";
  }

  // Phone change is now handled by intl-tel-input event listeners

  formatPhoneNumber(digits, countryCode) {
    if (!digits) return "";

    switch (countryCode) {
      case "+91": // India
        if (digits.length > 10) digits = digits.substring(0, 10);
        if (digits.length <= 4) return digits;
        if (digits.length <= 8)
          return `${digits.substring(0, 4)} ${digits.substring(4)}`;
        return `${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8)}`;

      case "+1": // US/Canada
        if (digits.length > 10) digits = digits.substring(0, 10);
        if (digits.length <= 3) return digits;
        if (digits.length <= 6)
          return `(${digits.substring(0, 3)}) ${digits.substring(3)}`;
        return `(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}`;

      case "+44": // UK
        if (digits.length > 11) digits = digits.substring(0, 11);
        if (digits.length <= 4) return digits;
        if (digits.length <= 7)
          return `${digits.substring(0, 4)} ${digits.substring(4)}`;
        return `${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}`;

      case "+61": // Australia
        if (digits.length > 9) digits = digits.substring(0, 9);
        if (digits.length <= 4) return digits;
        return `${digits.substring(0, 4)} ${digits.substring(4)}`;

      case "+65": // Singapore
        if (digits.length > 8) digits = digits.substring(0, 8);
        if (digits.length <= 4) return digits;
        return `${digits.substring(0, 4)} ${digits.substring(4)}`;

      case "+971": // UAE
        if (digits.length > 9) digits = digits.substring(0, 9);
        if (digits.length <= 3) return digits;
        return `${digits.substring(0, 3)} ${digits.substring(3)}`;

      default:
        // Default formatting: group by 3-4 digits
        if (digits.length > 15) digits = digits.substring(0, 15);
        if (digits.length <= 4) return digits;
        if (digits.length <= 7)
          return `${digits.substring(0, 4)} ${digits.substring(4)}`;
        return `${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}`;
    }
  }

  handleCountryCodeClick(event) {
    event.stopPropagation();
    this.showCountryCodeDropdown = !this.showCountryCodeDropdown;
  }

  handleCountryCodeSelect(event) {
    event.stopPropagation();
    const selectedCode =
      event.currentTarget.dataset.code ||
      event.target.closest("[data-code]")?.dataset.code;
    if (selectedCode) {
      this.formData.countryCode = selectedCode;
      this.showCountryCodeDropdown = false;

      // Reformat existing phone number if it exists
      if (this.formData.phone) {
        const digitsOnly = this.formData.phone.replace(/\D/g, "");
        this.formData.phone = this.formatPhoneNumber(digitsOnly, selectedCode);
      }

      this.phoneError = "";
      this.validatePhone();
    }
  }

  handleDropdownClick(event) {
    event.stopPropagation();
  }

  handleClickOutside(event) {
    const countrySelector = this.template.querySelector(
      ".country-code-selector-wrapper"
    );
    if (countrySelector && !countrySelector.contains(event.target)) {
      this.showCountryCodeDropdown = false;
    }
  }

  async connectedCallback() {
    getPrimaryColor()
      .then((color) => {
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
      .catch(() => {});

    document.addEventListener("click", this._handleClickOutside);
    this.initializeFromBusiness();
    await this.loadIntlTelInput();
  }

  async loadIntlTelInput() {
    try {
      console.log("=== Loading intl-tel-input Library ===");

      // Load CSS first
      await loadStyle(this, intlTelInputResource + "/css/intlTelInput.css");
      console.log("✓ CSS loaded successfully");

      // Load main script
      await loadScript(this, intlTelInputResource + "/js/intlTelInput.min.js");
      console.log("✓ Main script loaded successfully");

      // Load utils script
      await loadScript(this, intlTelInputResource + "/js/utils.js");
      console.log("✓ Utils script loaded successfully");

      // Verify library is available
      if (typeof window.intlTelInput === "function") {
        console.log("✓ intlTelInput is available");
        this.intlTelInputLoaded = true;

        // Initialize after render
        this.defer(() => this.initializeIntlTelInput());
      } else {
        console.error("intlTelInput is not available after loading");
      }
    } catch (error) {
      console.error("=== ERROR loading intl-tel-input ===");
      console.error("Error:", error?.message || error);
      console.error("Stack:", error?.stack);
    }
  }

  initializeIntlTelInput() {
    const phoneInput = this.template.querySelector('[data-id="phone-input"]');

    console.log("Initializing intl-tel-input:", {
      phoneInputFound: !!phoneInput,
      intlTelInputAvailable: typeof window.intlTelInput,
      alreadyInitialized: !!this.intlTelInputInstance
    });

    if (!phoneInput) {
      console.log("Phone input not found, retrying...");
      this.defer(() => this.initializeIntlTelInput());
      return;
    }

    if (!window.intlTelInput) {
      console.log("intlTelInput not available yet, retrying...");
      this.defer(() => this.initializeIntlTelInput());
      return;
    }

    if (this.intlTelInputInstance) {
      console.log("Already initialized");
      return;
    }

    try {
      const utilsPath = intlTelInputResource + "/js/utils.js";
      console.log("Initializing with utils path:", utilsPath);

      // Clear any existing placeholder to prevent conflicts
      phoneInput.placeholder = "";

      this.intlTelInputInstance = window.intlTelInput(phoneInput, {
        initialCountry: "in",
        preferredCountries: ["in", "us", "gb", "ca", "au"],
        separateDialCode: false,
        utilsScript: utilsPath,
        formatOnDisplay: true,
        nationalMode: true,
        autoHideDialCode: false,
        showSelectedDialCode: true,
        allowDropdown: true,
        onlyCountries: [],
        excludeCountries: [],
        customPlaceholder: function () {
          return "0000 0000 00";
        }
      });

      console.log(
        "intl-tel-input initialized, instance:",
        !!this.intlTelInputInstance
      );

      // Force flag visibility after render
      this.defer(() => {
        const wrapper = phoneInput.closest(".phone-input-wrapper");
        if (wrapper) {
          const flagElement = wrapper.querySelector(".iti__flag");
          const flagBox = wrapper.querySelector(".iti__flag-box");
          const flagContainer = wrapper.querySelector(".iti__flag-container");

          if (flagElement) {
            flagElement.style.display = "inline-block";
            flagElement.style.visibility = "visible";
            flagElement.style.opacity = "1";
          }
          if (flagBox) {
            flagBox.style.display = "inline-block";
            flagBox.style.visibility = "visible";
          }
          if (flagContainer) {
            flagContainer.style.display = "flex";
          }

          console.log("Flag visibility forced:", {
            flagElement: !!flagElement,
            flagBox: !!flagBox,
            flagContainer: !!flagContainer
          });
        }
      });

      console.log("intl-tel-input initialized successfully");

      // Update formData when country changes
      phoneInput.addEventListener("countrychange", () => {
        const countryData = this.intlTelInputInstance.getSelectedCountryData();
        this.formData.countryCode = "+" + countryData.dialCode;
        this.phoneError = "";
        console.log(
          "Country changed to:",
          countryData.name,
          countryData.dialCode
        );
      });

      // Update formData when phone number changes
      phoneInput.addEventListener("input", () => {
        this.formData.phone = phoneInput.value;
        this.validatePhone();
      });

      // Validate on blur
      phoneInput.addEventListener("blur", () => {
        this.validatePhone();
      });

      // Set initial value if exists
      if (this.formData.phone) {
        this.intlTelInputInstance.setNumber(this.formData.phone);
      }
    } catch (initError) {
      console.error("Error initializing intl-tel-input:", initError);
      console.error("Init error details:", initError.message, initError.stack);
      // Retry initialization
      this.defer(() => this.initializeIntlTelInput());
    }
  }

  renderedCallback() {
    if (this.intlTelInputLoaded && !this.intlTelInputInstance) {
      this.initializeIntlTelInput();
    }
    // Reflect the pre-populated business type onto the native <select> (edit mode).
    const typeSelect = this.template.querySelector("select.form-select");
    if (
      typeSelect &&
      this.formData.businessType &&
      typeSelect.value !== this.formData.businessType
    ) {
      typeSelect.value = this.formData.businessType;
    }
  }

  disconnectedCallback() {
    document.removeEventListener("click", this._handleClickOutside);
    if (this.intlTelInputInstance) {
      this.intlTelInputInstance.destroy();
      this.intlTelInputInstance = null;
    }
  }

  handleCountrySearch(event) {
    this.countrySearchTerm = event.target.value;
  }

  handleCountrySearchClick(event) {
    event.stopPropagation();
  }

  validatePhone() {
    this.phoneError = "";

    // Use intl-tel-input validation if available
    if (this.intlTelInputInstance) {
      const phoneInput = this.template.querySelector(".phone-input");
      if (!phoneInput || !phoneInput.value.trim()) {
        return true; // Allow empty, required validation happens elsewhere
      }

      if (this.intlTelInputInstance.isValidNumber()) {
        this.formData.phone = phoneInput.value;
        this.formData.countryCode =
          "+" + this.intlTelInputInstance.getSelectedCountryData().dialCode;
        return true;
      }

      const countryData = this.intlTelInputInstance.getSelectedCountryData();
      const errorCode = this.intlTelInputInstance.getValidationError();

      switch (errorCode) {
        case 1: // TOO_SHORT
          this.phoneError = `Phone number is too short for ${countryData.name}.`;
          break;
        case 2: // TOO_LONG
          this.phoneError = `Phone number is too long for ${countryData.name}.`;
          break;
        case 3: // INVALID_COUNTRY_CODE
          this.phoneError = "Invalid country code.";
          break;
        default:
          this.phoneError = `Please enter a valid phone number for ${countryData.name}.`;
      }
      return false;
    }

    // Fallback validation if intl-tel-input not loaded
    const digits = this.formData.phone.replace(/\D/g, "");
    const rules = this.phoneValidationRules[this.formData.countryCode];
    if (rules) {
      if (rules.digits && digits.length !== rules.digits) {
        this.phoneError = `Enter a ${rules.digits}-digit phone number for ${rules.label}.`;
      } else {
        const min = rules.min || rules.digits || 0;
        const max = rules.max || rules.digits || 15;
        if (digits.length < min || digits.length > max) {
          this.phoneError = `Enter a valid phone number for ${rules.label}.`;
        }
      }
    } else {
      // Default validation
      if (digits.length < 7 || digits.length > 15) {
        this.phoneError = "Enter a valid phone number.";
      }
    }
    return !this.phoneError;
  }

  validateForm() {
    this.nameError = this.formData.businessName ? "" : "Business name is required.";
    this.typeError = this.formData.businessType ? "" : "Business type is required.";
    if (!this.validatePhone()) {
      // phoneError already set by validatePhone()
    }
    this.emailError = this.validateEmail(this.formData.email);
    this.websiteError = this.validateUrl(this.formData.website);
    this.mapUrlError = this.validateUrl(this.formData.mapUrl);
    return [
      this.nameError,
      this.typeError,
      this.phoneError,
      this.emailError,
      this.websiteError,
      this.mapUrlError
    ].filter(Boolean);
  }

  showToast(title, message, variant) {
    this.toastTitle = title;
    this.toastMessage = message;
    this.toastVariant = variant;
    this.isToastVisible = true;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.isToastVisible = false;
    }, 4000);
  }

  async handleSubmit() {
    const errors = this.validateForm();
    if (errors.length) {
      return;
    }

    this.saveStatus = "saving";

    try {
      const coverPictureBase64 = this.formData.coverPicture
        ? await this.readFileAsBase64(this.formData.coverPicture)
        : null;
      const logoBase64 = this.formData.logo
        ? await this.readFileAsBase64(this.formData.logo)
        : null;

      const submissionData = {
        id: this.business?.id || null,
        ...this.formData,
        coverPictureName: this.formData.coverPicture
          ? this.formData.coverPicture.name
          : null,
        coverPictureBase64,
        logoName: this.formData.logo ? this.formData.logo.name : null,
        logoBase64
      };

      if (this.isStandaloneContext) {
        // Same request shape kenBusinessDirectory.handleSubmitListingForm builds
        // from the identical event payload — Apex call/logic is unchanged,
        // only *where* it's invoked from differs for the standalone page.
        const req = {
          businessName: submissionData.businessName,
          businessType: submissionData.businessType,
          phone: submissionData.phone,
          hidePhone: submissionData.hidePhone,
          email: submissionData.email,
          hideEmail: submissionData.hideEmail,
          website: submissionData.website,
          address: submissionData.address,
          mapUrl: submissionData.mapUrl,
          description: submissionData.description,
          coverPictureName: submissionData.coverPictureName,
          coverPictureBase64: submissionData.coverPictureBase64,
          logoName: submissionData.logoName,
          logoBase64: submissionData.logoBase64
        };
        await createBusiness({ req, constituentRoleId: this._roleId });
        this.confirmSaved();
        return;
      }

      this.dispatchEvent(
        new CustomEvent("submit", {
          detail: submissionData,
          bubbles: true,
          composed: true
        })
      );
    } catch (error) {
      const message =
        error?.body?.message ||
        error?.message ||
        "Something went wrong while saving your business. Please try again.";
      this.showToast("Save failed", message, "error");
      this.resetSave();
    }
  }

  // Called by the parent after a successful save (or by this component itself
  // in standalone mode): show the green "Saved" state, then close.
  @api
  confirmSaved() {
    this.saveStatus = "saved";
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      this.saveStatus = "idle";
      if (this.isStandaloneContext) {
        this[NavigationMixin.Navigate]({
          type: "comm__namedPage",
          attributes: { name: "business__c" }
        });
        return;
      }
      this.dispatchEvent(
        new CustomEvent("closeform", { bubbles: true, composed: true })
      );
    }, 2000);
  }

  // Called by the parent on save failure: revert the button to its normal state.
  @api
  resetSave() {
    this.saveStatus = "idle";
  }

  // ── Featured business ─────────────────────────────────────────────────────

  // Featuring is only offered when editing an existing, already-approved business.
  get isEditing() {
    return !!(this.business && this.business.id);
  }

  get canRequestFeature() {
    return this.isEditing && this.business.status === "Active";
  }

  get showFeatureDates() {
    return (
      this.formData.requestFeature &&
      this.formData.featuredFrom &&
      this.formData.featuredTo
    );
  }

  get todayStr() {
    return new Date().toISOString().slice(0, 10);
  }

  get defaultFeatureFrom() {
    const d = new Date();
    d.setDate(d.getDate() + 1); // tomorrow
    return d.toISOString().slice(0, 10);
  }

  get defaultFeatureTo() {
    const d = new Date();
    d.setDate(d.getDate() + 15); // tomorrow + 14 days
    return d.toISOString().slice(0, 10);
  }

  get featureDatesSummary() {
    return `${this.formData.featuredFrom} → ${this.formData.featuredTo}`;
  }

  // Shows the current feature state (e.g. while a request is under approval).
  get featureStatusLabel() {
    if (!this.isEditing) return "";
    const s = this.business.featureStatus;
    const from = this.business.featuredFrom;
    const to = this.business.featuredTo;
    if (s === "Pending Approval") {
      return `Feature request under approval (${from} – ${to}).`;
    }
    if (s === "Approved" && this.business.isCurrentlyFeatured) {
      return `Currently featured until ${to}.`;
    }
    if (s === "Approved") {
      return `Feature approved (${from} – ${to}).`;
    }
    if (s === "Rejected") {
      return "Previous feature request was rejected.";
    }
    return "";
  }

  get hasFeatureStatus() {
    return this.featureStatusLabel !== "";
  }

  handleRequestFeatureChange(event) {
    const checked = event.target.checked;
    this.formData = { ...this.formData, requestFeature: checked };
    if (checked) {
      // Pre-fill sensible defaults and open the date picker modal.
      this.formData = {
        ...this.formData,
        featuredFrom: this.formData.featuredFrom || this.defaultFeatureFrom,
        featuredTo: this.formData.featuredTo || this.defaultFeatureTo
      };
      this.showFeatureModal = true;
    } else {
      this.formData = { ...this.formData, featuredFrom: "", featuredTo: "" };
    }
  }

  handleEditFeatureDates() {
    this.showFeatureModal = true;
  }

  handleFeatureModalProceed() {
    // Light client-side guard; the server re-validates against config bounds.
    if (!this.formData.featuredFrom || !this.formData.featuredTo) {
      return;
    }
    if (this.formData.featuredTo < this.formData.featuredFrom) {
      return;
    }
    this.showFeatureModal = false;
  }

  handleFeatureModalCancel() {
    this.formData = {
      ...this.formData,
      requestFeature: false,
      featuredFrom: "",
      featuredTo: ""
    };
    this.showFeatureModal = false;
  }

  stopModalClick(event) {
    event.stopPropagation();
  }

  handleFeaturedFromChange(event) {
    this.formData = { ...this.formData, featuredFrom: event.target.value };
  }

  handleFeaturedToChange(event) {
    this.formData = { ...this.formData, featuredTo: event.target.value };
  }

  handleHidePhoneChange(event) {
    this.formData.hidePhone = event.target.checked;
  }

  handlePhoneInput(event) {
    // This will be handled by intl-tel-input event listeners
    // Just ensure formData is updated
    this.formData.phone = event.target.value;
  }

  handleEmailChange(event) {
    this.formData.email = event.target.value;
    this.emailError = this.validateEmail(this.formData.email);
  }

  handleHideEmailChange(event) {
    this.formData.hideEmail = event.target.checked;
  }

  handleWebsiteChange(event) {
    this.formData.website = event.target.value;
    this.websiteError = this.validateUrl(this.formData.website);
  }

  handleAddressChange(event) {
    this.formData.address = event.target.value;
  }

  handleMapUrlChange(event) {
    this.formData.mapUrl = event.target.value;
    this.mapUrlError = this.validateUrl(this.formData.mapUrl);
  }

  // Returns an error message, or "" when valid/blank (both fields are optional).
  validateEmail(value) {
    if (!value) return "";
    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailPattern.test(value) ? "" : "Enter a valid email address.";
  }

  validateUrl(value) {
    if (!value) return "";
    try {
      const url = new URL(value);
      if (url.protocol !== "http:" && url.protocol !== "https:") {
        return "URL must start with http:// or https://.";
      }
      return "";
    } catch {
      return "Enter a valid URL starting with http:// or https://.";
    }
  }

  handleDescriptionChange(event) {
    this.formData.description = event.detail.value || '';
  }

  handleCancel() {
    if (this.isStandaloneContext) {
      this[NavigationMixin.Navigate]({
        type: "comm__namedPage",
        attributes: { name: "business__c" }
      });
      return;
    }
    // Dispatch event to go back
    this.dispatchEvent(
      new CustomEvent("cancel", {
        bubbles: true,
        composed: true
      })
    );
  }

  initializeFromBusiness() {
    if (this._hasInitializedFromBusiness) return;
    if (!this.business || !this.business.id) return;

    this._hasInitializedFromBusiness = true;

    const clean = (v) => {
      if (!v) return "";
      const t = v.trim();
      return /^[-–—]+$/.test(t) ? "" : t;
    };

    const phone = clean(this.business.phone);
    const email = clean(this.business.email);

    if (this.business.featuredImage) {
      this.coverPreviewUrl = this.business.featuredImage;
    }

    this.formData = {
      ...this.formData,
      businessName: this.business.name || "",
      businessType: this.business.category || "",
      phone,
      hidePhone: !phone,
      email,
      hideEmail: !email,
      website: clean(this.business.website),
      address: clean(this.business.address) || clean(this.business.location),
      mapUrl: clean(this.business.mapUrl),
      description: this.business.description || ""
    };
  }

  _handleClickOutside = (event) => this.handleClickOutside(event);

  readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
      try {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(file);
      } catch (e) {
        reject(e);
      }
    });
  }

  defer(fn) {
    Promise.resolve().then(() => {
      try {
        fn();
      } catch (e) {
        console.error(e);
      }
    });
  }
}