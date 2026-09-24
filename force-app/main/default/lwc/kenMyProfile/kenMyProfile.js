import { LightningElement, track } from "lwc";
import {
  htmlToPlainText,
  replaceElementHtml,
  serializeElementHtml
} from "c/kenHtmlSanitizer";
import { NavigationMixin } from "lightning/navigation";
import defaultProfileImage from "@salesforce/resourceUrl/AlumniAlt";

import getMyProfile from "@salesforce/apex/KenMyProfileController.getMyProfile";
import getProfileFor from "@salesforce/apex/KenMyProfileController.getProfileFor";
import getMyEngagement from "@salesforce/apex/KenMyProfileController.getMyEngagement";
import getEngagementFor from "@salesforce/apex/KenMyProfileController.getEngagementFor";
import getMySupport from "@salesforce/apex/KenMyProfileController.getMySupport";
import getSupportFor from "@salesforce/apex/KenMyProfileController.getSupportFor";
import getMyRecentActivity from "@salesforce/apex/KenMyProfileController.getMyRecentActivity";
import getRecentActivityFor from "@salesforce/apex/KenMyProfileController.getRecentActivityFor";
import getMyRecordHealth from "@salesforce/apex/KenMyProfileController.getMyRecordHealth";
import getRecordHealthFor from "@salesforce/apex/KenMyProfileController.getRecordHealthFor";
import getPersonalDetails from "@salesforce/apex/KenProfileSettingsController.getPersonalDetails";
import saveAboutText from "@salesforce/apex/KenMyProfileController.saveAbout";
import saveEducationRecord from "@salesforce/apex/KenMyProfileController.saveEducation";
import archiveEducationRecord from "@salesforce/apex/KenMyProfileController.archiveEducation";
import saveExperienceRecord from "@salesforce/apex/KenMyProfileController.saveExperience";
import archiveExperienceRecord from "@salesforce/apex/KenMyProfileController.archiveExperience";
import saveAchievementRecord from "@salesforce/apex/KenMyProfileController.saveAchievement";
import archiveAchievementRecord from "@salesforce/apex/KenMyProfileController.archiveAchievement";
import { localDateKey } from "c/kenDateTime";

const KEN_HEADER_CHAT_OPEN_KEY = "ken_header_open_chat";

const EMPTY_PROFILE = {
  name: "",
  title: "",
  company: "",
  location: "",
  profileImage: "",
  isOnline: false,
  batch: "",
  expertise: "",
  email: "",
  phone: "",
  linkedin: "",
  willingToHelp: true,
  about: "",
  registrationNumber: null,
  education: [],
  experience: [],
  achievements: []
};

const RECORD_HEALTH_ICON_OK = "utility:success";
const RECORD_HEALTH_ICON_WARN = "utility:warning";

export default class KenMyProfile extends NavigationMixin(LightningElement) {
  @track isLoading = true;
  @track isWorking = false;
  @track loadingText = "Loading profile...";
  @track showSuccessPopup = false;
  @track successMessage = "";

  @track showChatbox = false;
  @track isChatExpanded = false;
  @track messageInput = "";
  @track chatMessages = [
    {
      id: 1,
      type: "received",
      text: "Hope life is treating you well! We have got an exciting alumni networking event on the horizon.",
      time: "05:10 PM",
      date: "2026-02-19"
    },
    {
      id: 2,
      type: "sent",
      text: "Sounds awesome! Can't wait to catch up and network with fellow alumni.",
      time: "05:10 PM",
      date: "2026-02-19"
    }
  ];

  @track showAboutModal = false;
  @track showExperienceModal = false;
  @track showEducationModal = false;
  @track showAchievementModal = false;
  @track aboutEditText = "";
  @track isAboutBoldActive = false;
  @track isAboutItalicActive = false;
  @track isAboutUnorderedListActive = false;
  @track isAboutOrderedListActive = false;
  // Personal Details is the landing tab; About Me was folded into it and
  // no longer has its own tab (its edit code stays below, unused, in case
  // a future card wants the rich-text bio back).
  @track activeTab = "personalDetails";
  @track paymentSearchTerm = "";
  @track experienceModalCareerData = null;
  @track experienceModalTitle = "Add Experience";
  @track educationModalData = null;
  @track achievementModalData = null;
  @track profileData = { ...EMPTY_PROFILE };
  @track engagementData = {};
  @track supportData = {};
  @track recordHealth = [];
  @track recentActivity = [];

  currentEditExperienceId = null;
  currentEditEducationId = null;
  currentEditAchievementId = null;
  successPopupTimeout = null;
  aboutRichTextEditor = null;
  aboutLastValidHtml = "";
  // Set from ?accountId= when a caller (e.g. an admin link) points this
  // component at someone else's record. Empty/absent means "my own
  // profile", which is how this component is used everywhere today.
  targetAccountId = null;

  connectedCallback() {
    this.targetAccountId = this.getTargetAccountIdFromUrl();
    this.loadAll({ showLoader: true, loadingText: "Loading profile..." });

    try {
      if (sessionStorage.getItem(KEN_HEADER_CHAT_OPEN_KEY)) {
        sessionStorage.removeItem(KEN_HEADER_CHAT_OPEN_KEY);
        this.showChatbox = true;
      }
    } catch {
      // ignore
    }
  }

  disconnectedCallback() {
    if (this.successPopupTimeout) {
      window.clearTimeout(this.successPopupTimeout);
      this.successPopupTimeout = null;
    }
  }

  renderedCallback() {
    if (!this.showAboutModal) {
      this.aboutRichTextEditor = null;
      return;
    }

    const editor = this.template.querySelector(".about-rich-text-area");
    if (!editor) {
      return;
    }

    if (editor !== this.aboutRichTextEditor) {
      this.aboutRichTextEditor = editor;
      replaceElementHtml(editor, this.aboutEditText || "");
      this.aboutLastValidHtml = serializeElementHtml(editor);
      this.ensureAboutListFormatting();
      this.updateAboutToolbarStates();
    } else if (serializeElementHtml(editor) !== (this.aboutEditText || "")) {
      replaceElementHtml(editor, this.aboutEditText || "");
      this.ensureAboutListFormatting();
    }
  }

  get showLoader() {
    return this.isLoading || this.isWorking;
  }

  get isMyProfile() {
    return !this.targetAccountId;
  }

  getTargetAccountIdFromUrl() {
    try {
      const url = new URL(window.location.href);
      const id = url.searchParams.get("accountId");
      return id || null;
    } catch {
      return null;
    }
  }

  showSuccess(message) {
    this.successMessage = message || "Saved successfully";
    this.showSuccessPopup = true;
    if (this.successPopupTimeout) {
      window.clearTimeout(this.successPopupTimeout);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.successPopupTimeout = window.setTimeout(() => {
      this.showSuccessPopup = false;
      this.successPopupTimeout = null;
    }, 2000);
  }

  async runWithLoader(loadingText, operation) {
    this.isWorking = true;
    this.loadingText = loadingText || "Processing...";
    try {
      return await operation();
    } finally {
      this.isWorking = false;
    }
  }

  async loadAll(options = {}) {
    const { showLoader = false, loadingText = "Loading profile..." } = options;
    if (showLoader) {
      this.isLoading = true;
      this.loadingText = loadingText;
    }
    try {
      await Promise.all([
        this.loadProfile(),
        this.loadEngagement(),
        this.loadSupport(),
        this.loadRecentActivity(),
        this.loadRecordHealth()
      ]);
    } finally {
      if (showLoader) {
        this.isLoading = false;
      }
    }
  }

  async loadProfile() {
    try {
      const [data, settings] = await Promise.all([
        this.isMyProfile
          ? getMyProfile()
          : getProfileFor({ targetAccountId: this.targetAccountId }),
        this.isMyProfile ? getPersonalDetails() : Promise.resolve(null)
      ]);
      this.profileData = {
        ...EMPTY_PROFILE,
        ...(data || {}),
        profileImage:
          settings?.profileImageUrl ||
          data?.profileImage ||
          defaultProfileImage,
        education: data?.education || [],
        experience: data?.experience || [],
        achievements: data?.achievements || []
      };
    } catch (e) {
      // Keep existing data on error
      console.error("Failed to load profile", e);
    }
  }

  async loadEngagement() {
    try {
      this.engagementData =
        (await (this.isMyProfile
          ? getMyEngagement()
          : getEngagementFor({ targetAccountId: this.targetAccountId }))) || {};
    } catch (e) {
      console.error("Failed to load engagement data", e);
      this.engagementData = {};
    }
  }

  async loadSupport() {
    try {
      this.supportData =
        (await (this.isMyProfile
          ? getMySupport()
          : getSupportFor({ targetAccountId: this.targetAccountId }))) || {};
    } catch (e) {
      console.error("Failed to load support data", e);
      this.supportData = {};
    }
  }

  async loadRecentActivity() {
    try {
      this.recentActivity =
        (await (this.isMyProfile
          ? getMyRecentActivity()
          : getRecentActivityFor({ targetAccountId: this.targetAccountId }))) ||
        [];
    } catch (e) {
      console.error("Failed to load recent activity", e);
      this.recentActivity = [];
    }
  }

  async loadRecordHealth() {
    try {
      this.recordHealth =
        (await (this.isMyProfile
          ? getMyRecordHealth()
          : getRecordHealthFor({ targetAccountId: this.targetAccountId }))) ||
        [];
    } catch (e) {
      console.error("Failed to load record health", e);
      this.recordHealth = [];
    }
  }

  // ── Tabs ─────────────────────────────────────────────────────────────
  get personalDetailsTabClass() {
    return this.activeTab === "personalDetails" ? "ken-tab active" : "ken-tab";
  }
  get educationCareerTabClass() {
    return this.activeTab === "educationCareer" ? "ken-tab active" : "ken-tab";
  }
  get achievementsTabClass() {
    return this.activeTab === "achievements" ? "ken-tab active" : "ken-tab";
  }
  get engagementTabClass() {
    return this.activeTab === "engagement" ? "ken-tab active" : "ken-tab";
  }
  get supportTabClass() {
    return this.activeTab === "support" ? "ken-tab active" : "ken-tab";
  }
  get paymentsTabClass() {
    return this.activeTab === "payments" ? "ken-tab active" : "ken-tab";
  }

  get isPersonalDetails() {
    return this.activeTab === "personalDetails";
  }
  get isEducationCareer() {
    return this.activeTab === "educationCareer";
  }
  get isAchievements() {
    return this.activeTab === "achievements";
  }
  get isEngagement() {
    return this.activeTab === "engagement";
  }
  get isSupport() {
    return this.activeTab === "support";
  }
  get isPayments() {
    return this.activeTab === "payments";
  }

  selectPersonalDetails() {
    this.activeTab = "personalDetails";
  }
  selectEducationCareer() {
    this.activeTab = "educationCareer";
  }
  selectAchievements() {
    this.activeTab = "achievements";
  }
  selectEngagement() {
    this.activeTab = "engagement";
  }
  selectSupport() {
    this.activeTab = "support";
  }
  selectPayments() {
    this.activeTab = "payments";
  }

  get payments() {
    return [
      {
        id: "1",
        particulars: "Event Payment",
        transactionId: "alfly000002EVirAAG",
        paymentMode: "Online",
        currency: "Rupee",
        paidAmount: "Rs 50,000",
        transactionDate: "17 Aug 2026"
      },
      {
        id: "2",
        particulars: "Event Payment",
        transactionId: "alfly000002EVirAAG",
        paymentMode: "Online",
        currency: "Rupee",
        paidAmount: "Rs 50,000",
        transactionDate: "17 Aug 2026"
      },
      {
        id: "3",
        particulars: "Event Payment",
        transactionId: "alfly000002EVirAAG",
        paymentMode: "Online",
        currency: "Rupee",
        paidAmount: "Rs 50,000",
        transactionDate: "17 Aug 2026"
      }
    ];
  }

  get filteredPayments() {
    const term = (this.paymentSearchTerm || "").toLowerCase().trim();
    const list = this.payments || [];
    if (!term) return list;
    return list.filter((p) => {
      const particulars = (p.particulars || "").toLowerCase();
      const transactionId = (p.transactionId || "").toLowerCase();
      const paymentMode = (p.paymentMode || "").toLowerCase();
      const currency = (p.currency || "").toLowerCase();
      return (
        particulars.includes(term) ||
        transactionId.includes(term) ||
        paymentMode.includes(term) ||
        currency.includes(term)
      );
    });
  }

  get chatContainerClass() {
    return this.isChatExpanded
      ? "chatbox-container expanded"
      : "chatbox-container";
  }

  get chatExpandIcon() {
    return this.isChatExpanded ? "utility:contract_alt" : "utility:expand_alt";
  }

  get displayMessages() {
    const items = [];
    let lastDateString = null;

    const getRelativeDateLabel = (dateString) => {
      if (!dateString) return "";
      const msgDate = new Date(dateString);
      const today = new Date();
      const yesterday = new Date(today);
      yesterday.setDate(yesterday.getDate() - 1);
      if (msgDate.toDateString() === today.toDateString()) return "Today";
      if (msgDate.toDateString() === yesterday.toDateString())
        return "Yesterday";
      return msgDate.toLocaleDateString([], {
        month: "short",
        day: "numeric",
        year: "numeric"
      });
    };

    this.chatMessages.forEach((msg, index) => {
      const currentDateString = msg.date || localDateKey();
      const dateLabel = getRelativeDateLabel(currentDateString);
      if (dateLabel !== lastDateString) {
        items.push({ id: "date-" + index, isDateSeparator: true, dateLabel });
        lastDateString = dateLabel;
      }
      items.push({
        ...msg,
        isSent: msg.type === "sent",
        isReceived: msg.type === "received"
      });
    });
    return items;
  }

  get educationLine() {
    const list = this.profileData?.education;
    if (!list || !list.length) return this.profileData?.batch || "";
    const parts = list.slice(0, 2).map((e) => {
      const degree = (e.degree || "").trim();
      const year = (e.endYear || "").trim();
      return year ? `${degree} ${year}` : degree;
    });
    return parts.filter(Boolean).join(" | ") || this.profileData?.batch || "";
  }

  get hasEducationRecords() {
    return (
      Array.isArray(this.profileData?.education) &&
      this.profileData.education.length > 0
    );
  }

  get hasExperienceRecords() {
    return (
      Array.isArray(this.profileData?.experience) &&
      this.profileData.experience.length > 0
    );
  }

  get hasAchievementRecords() {
    return (
      Array.isArray(this.profileData?.achievements) &&
      this.profileData.achievements.length > 0
    );
  }

  // ── Personal Details tab: Alumna Snapshot / Personal Details / Contact ──
  _buildInfoGroup(g) {
    return {
      key: g.key,
      title: g.title,
      note: g.note,
      groupLocked: g.groupLocked,
      showEditButton: g.canEdit && this.isMyProfile,
      fields: g.defs.map(([key, label, value]) => {
        const filled =
          value !== null && value !== undefined && String(value).trim() !== "";
        return {
          key,
          label,
          value: filled ? value : "Not provided",
          valueClass: filled
            ? "personal-info-value"
            : "personal-info-value personal-info-value--empty"
        };
      })
    };
  }

  get personalInfoGroups() {
    const p = this.profileData || {};
    return [
      {
        key: "academic",
        title: "Alumna Snapshot",
        note: null,
        groupLocked: true,
        canEdit: false,
        defs: [
          ["registrationNumber", "Registration Number", p.registrationNumber],
          ["yearOfEnrollment", "Year of Enrollment", p.yearOfEnrollment],
          ["classOf", "Class of", p.classOf],
          ["program", "Program", p.program],
          ["yearsPostGrad", "Years Post-Graduation", p.yearsPostGrad],
          ["alumniStatus", "Alumni Status", p.alumniStatus]
        ]
      },
      {
        key: "personalDetails",
        title: "Personal Details",
        note: null,
        groupLocked: false,
        canEdit: true,
        defs: [
          ["dob", "Date of Birth", p.dob],
          ["gender", "Gender", p.gender],
          ["bloodGroup", "Blood Group", p.bloodGroup],
          ["nationality", "Nationality", p.nationality],
          ["languagesKnown", "Languages Known", p.languagesKnown],
          ["mailingCity", "City", p.mailingCity],
          ["mailingState", "State", p.mailingState],
          ["mailingCountry", "Country", p.mailingCountry]
        ]
      },
      {
        key: "contact",
        title: "Contact Details",
        note: null,
        groupLocked: false,
        canEdit: true,
        defs: [
          ["email", "Email", p.email],
          ["phone", "Phone", p.phone],
          ["linkedin", "LinkedIn", p.linkedin],
          ["twitter", "Twitter", p.twitter]
        ]
      }
    ].map((g) => this._buildInfoGroup(g));
  }

  // Broken out so the template can interleave each card with its paired
  // right-column card in one grid (Alumna Snapshot/Record Health,
  // Personal Details/Recent Activity, Contact/LinkedIn Sync) - CSS grid's
  // default row-stretch then makes each pair match height automatically.
  get alumnaSnapshotGroup() {
    return this.personalInfoGroups[0];
  }

  get personalDetailsGroup() {
    return this.personalInfoGroups[1];
  }

  get contactDetailsGroup() {
    return this.personalInfoGroups[2];
  }

  get hasRecordHealth() {
    return Array.isArray(this.recordHealth) && this.recordHealth.length > 0;
  }

  get recordHealthDisplay() {
    return (this.recordHealth || []).map((h, i) => ({
      key: h.label || `health-${i}`,
      label: h.label,
      ok: h.ok === true,
      missingNote: h.missingNote,
      iconName: h.ok === true ? RECORD_HEALTH_ICON_OK : RECORD_HEALTH_ICON_WARN
    }));
  }

  get hasRecentActivity() {
    return Array.isArray(this.recentActivity) && this.recentActivity.length > 0;
  }

  get recentActivityDisplay() {
    return (this.recentActivity || []).map((a, i) => ({
      key: `${a.title || "activity"}-${i}`,
      title: a.title,
      when_x: a.when_x,
      iconName: a.iconKey || "utility:info"
    }));
  }

  navigateToSettings(event) {
    // LinkedIn lives in the Settings page's Social Media card, well below
    // the fold - callers that care (Contact Details' edit icon, the
    // LinkedIn Sync card's setup icon) mark data-focus="linkedin" so
    // Settings can scroll straight to it instead of landing at the top.
    const focus = event?.currentTarget?.dataset?.focus;
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: "settings__c" },
      state: focus ? { focus } : undefined
    });
  }

  handleLinkedInSyncComplete() {
    // Re-run the wires that could have changed: new experience/education
    // rows from the sync, the LinkedIn-linked Record Health check, and
    // the profile photo if LinkedIn supplied one.
    this.loadProfile();
    this.loadRecordHealth();
  }

  // ── Engagement tab ───────────────────────────────────────────────────
  get hasEventsAttended() {
    return (
      Array.isArray(this.engagementData?.eventsAttended) &&
      this.engagementData.eventsAttended.length > 0
    );
  }

  get hasMentorship() {
    return (
      Array.isArray(this.engagementData?.mentorship) &&
      this.engagementData.mentorship.length > 0
    );
  }

  get mentorshipRows() {
    return (this.engagementData?.mentorship || []).map((m) => ({
      ...m,
      initials: this.initialsFor(m.name),
      statusTone:
        m.status === "Active"
          ? "status-pill status-pill--active"
          : "status-pill"
    }));
  }

  initialsFor(name) {
    if (!name) return "";
    return name
      .split(" ")
      .filter(Boolean)
      .slice(0, 2)
      .map((n) => n[0].toUpperCase())
      .join("");
  }

  // ── Support tab ──────────────────────────────────────────────────────
  get hasSupportTickets() {
    return (
      Array.isArray(this.supportData?.tickets) &&
      this.supportData.tickets.length > 0
    );
  }

  get supportTicketRows() {
    return (this.supportData?.tickets || []).map((t) => ({
      ...t,
      priorityTone:
        t.priority === "High"
          ? "ticket-priority ticket-priority--high"
          : t.priority === "Medium"
            ? "ticket-priority ticket-priority--medium"
            : "ticket-priority"
    }));
  }

  get avgFirstResponseDisplay() {
    const v = this.supportData?.avgFirstResponse;
    return v === null || v === undefined || String(v).trim() === "" ? "—" : v;
  }

  handleMessage() {
    this.showChatbox = true;
  }

  handleToggleExpand() {
    this.isChatExpanded = !this.isChatExpanded;
  }

  handleCloseChat() {
    this.showChatbox = false;
    this.isChatExpanded = false;
  }

  handleImageError(event) {
    if (event && event.target) event.target.src = defaultProfileImage;
  }

  handleInputChange(event) {
    this.messageInput = event.target.value;
  }

  handleInputKeyup(event) {
    if (event.key === "Enter") this.handleSendMessage();
  }

  handleSendMessage() {
    if (!this.messageInput || !this.messageInput.trim()) return;
    const now = new Date();
    const timeString = now.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit"
    });
    const newMessage = {
      id: this.chatMessages.length + 1,
      type: "sent",
      text: this.messageInput,
      time: timeString,
      date: localDateKey(now)
    };
    this.chatMessages = [...this.chatMessages, newMessage];
    this.messageInput = "";
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      const chatBody = this.template.querySelector(".chatbox-body");
      if (chatBody) chatBody.scrollTop = chatBody.scrollHeight;
    }, 0);
  }

  openAboutEdit() {
    this.aboutEditText = this.profileData.about || "";
    this.aboutLastValidHtml = this.aboutEditText || "";
    this.showAboutModal = true;
  }

  closeAboutModal() {
    this.showAboutModal = false;
  }

  handleAboutDiscard() {
    this.closeAboutModal();
  }

  handleAboutChange(event) {
    this.aboutEditText = event.detail.value || "";
  }

  async handleAboutSave() {
    await this.runWithLoader("Saving about...", async () => {
      try {
        await saveAboutText({ aboutText: this.aboutEditText || "" });
        this.profileData = {
          ...this.profileData,
          about: this.aboutEditText || ""
        };
        this.closeAboutModal();
        this.showSuccess("About updated successfully");
      } catch (e) {
        console.error("Failed to save about", e);
      }
    });
  }

  handleAboutEditInput(event) {
    this.aboutEditText = event.target.value;
  }

  get aboutEditLength() {
    return this.getPlainTextLength(this.aboutEditText);
  }

  get aboutBoldButtonClass() {
    return `toolbar-button ${this.isAboutBoldActive ? "active" : ""}`;
  }

  get aboutItalicButtonClass() {
    return `toolbar-button ${this.isAboutItalicActive ? "active" : ""}`;
  }

  get aboutUnorderedListButtonClass() {
    return `toolbar-button ${this.isAboutUnorderedListActive ? "active" : ""}`;
  }

  get aboutOrderedListButtonClass() {
    return `toolbar-button ${this.isAboutOrderedListActive ? "active" : ""}`;
  }

  getPlainTextLength(htmlValue) {
    return htmlToPlainText(htmlValue).length;
  }

  handleAboutRichTextInput(event) {
    const html = serializeElementHtml(event.target) || "";
    if (this.getPlainTextLength(html) <= 1200) {
      this.aboutEditText = html;
      this.aboutLastValidHtml = html;
    } else {
      replaceElementHtml(event.target, this.aboutLastValidHtml || "");
      this.placeCaretAtEnd(event.target);
    }
    this.ensureAboutListFormatting();
    this.updateAboutToolbarStates();
  }

  handleAboutRichTextFocus() {
    this.updateAboutToolbarStates();
  }

  handleAboutRichTextSelection() {
    this.updateAboutToolbarStates();
  }

  handleAboutRichTextBlur() {
    if (!this.aboutRichTextEditor) return;
    this.aboutEditText = serializeElementHtml(this.aboutRichTextEditor) || "";
    this.aboutLastValidHtml = this.aboutEditText;
    this.updateAboutToolbarStates();
  }

  executeAboutCommand(command) {
    if (!this.aboutRichTextEditor) return;
    this.aboutRichTextEditor.focus();

    if (command === "insertUnorderedList" || command === "insertOrderedList") {
      const selection = window.getSelection();
      if (selection && (selection.rangeCount === 0 || selection.isCollapsed)) {
        const range = document.createRange();
        const textNode =
          this.aboutRichTextEditor.childNodes[0] || this.aboutRichTextEditor;
        range.setStart(textNode, 0);
        range.setEnd(
          textNode,
          textNode.textContent ? textNode.textContent.length : 0
        );
        selection.removeAllRanges();
        selection.addRange(range);
      }
    }

    document.execCommand(command, false, null);
    this.aboutEditText = serializeElementHtml(this.aboutRichTextEditor) || "";
    this.aboutLastValidHtml = this.aboutEditText;
    this.ensureAboutListFormatting();
    this.updateAboutToolbarStates();
  }

  handleAboutBold(event) {
    event.preventDefault();
    this.executeAboutCommand("bold");
  }

  handleAboutItalic(event) {
    event.preventDefault();
    this.executeAboutCommand("italic");
  }

  handleAboutUnorderedList(event) {
    event.preventDefault();
    this.executeAboutCommand("insertUnorderedList");
  }

  handleAboutOrderedList(event) {
    event.preventDefault();
    this.executeAboutCommand("insertOrderedList");
  }

  updateAboutToolbarStates() {
    try {
      this.isAboutBoldActive = document.queryCommandState("bold");
      this.isAboutItalicActive = document.queryCommandState("italic");

      let isInUnorderedList = false;
      let isInOrderedList = false;
      const selection = window.getSelection();
      if (selection && selection.rangeCount > 0) {
        const range = selection.getRangeAt(0);
        let container = range.commonAncestorContainer;
        while (container && container !== this.aboutRichTextEditor) {
          if (container.nodeType === 1) {
            const tagName = container.tagName.toUpperCase();
            if (tagName === "UL") {
              isInUnorderedList = true;
              break;
            }
            if (tagName === "OL") {
              isInOrderedList = true;
              break;
            }
            if (tagName === "LI") {
              const parent = container.parentElement;
              if (parent) {
                const parentTag = parent.tagName.toUpperCase();
                if (parentTag === "UL") isInUnorderedList = true;
                if (parentTag === "OL") isInOrderedList = true;
              }
              break;
            }
          }
          container = container.parentElement || container.parentNode;
        }
      }
      this.isAboutUnorderedListActive = isInUnorderedList;
      this.isAboutOrderedListActive = isInOrderedList;
    } catch {
      // ignore
    }
  }

  ensureAboutListFormatting() {
    if (!this.aboutRichTextEditor) return;
    const lists = this.aboutRichTextEditor.querySelectorAll("ul, ol");
    lists.forEach((list) => {
      if (!list.style.marginLeft) {
        list.style.marginLeft = "1.5rem";
        list.style.marginTop = "0.5rem";
        list.style.marginBottom = "0.5rem";
      }
    });
    const listItems = this.aboutRichTextEditor.querySelectorAll("li");
    listItems.forEach((li) => {
      if (!li.style.marginBottom) {
        li.style.marginBottom = "0.25rem";
      }
    });
  }

  placeCaretAtEnd(element) {
    if (!element) return;
    const range = document.createRange();
    range.selectNodeContents(element);
    range.collapse(false);
    const selection = window.getSelection();
    if (!selection) return;
    selection.removeAllRanges();
    selection.addRange(range);
  }

  handlePaymentSearchInput(event) {
    this.paymentSearchTerm = event.target.value;
  }

  openAddExperience() {
    this.currentEditExperienceId = null;
    this.experienceModalCareerData = null;
    this.experienceModalTitle = "Add Experience";
    this.showExperienceModal = true;
  }

  handleEditExperience(event) {
    const id = event.detail.id;
    const exp = (this.profileData.experience || []).find((e) => e.id === id);
    if (!exp) return;

    const startDate =
      exp.startYear && exp.startMonth
        ? `${exp.startYear}-${exp.startMonth}-01`
        : null;
    const endDate =
      exp.endYear && exp.endMonth ? `${exp.endYear}-${exp.endMonth}-01` : null;

    this.currentEditExperienceId = id;
    this.experienceModalCareerData = {
      id,
      jobTitle: exp.position || "",
      organization: exp.company || "",
      employmentType: exp.employmentType || "",
      location: exp.location || "",
      roleDescription: exp.description || "",
      isCurrentJob: exp.isCurrentJob || false,
      startDate,
      endDate,
      jobRole: exp.jobRole || ""
    };
    this.experienceModalTitle = "Edit Experience";
    this.showExperienceModal = true;
  }

  async handleDeleteExperience(event) {
    const id = event.detail.id;
    await this.runWithLoader("Deleting experience...", async () => {
      try {
        await archiveExperienceRecord({ recordId: id });
        await this.loadProfile();
        this.showSuccess("Experience deleted successfully");
      } catch (e) {
        console.error("Failed to archive experience", e);
      }
    });
  }

  handleCloseExperienceModal() {
    this.showExperienceModal = false;
    this.currentEditExperienceId = null;
  }

  async handleSaveExperience(event) {
    const d = event.detail || {};
    const start = this.extractMonthYear(d.startDate);
    const end = this.extractMonthYear(d.endDate);

    await this.runWithLoader("Saving experience...", async () => {
      try {
        await saveExperienceRecord({
          input: {
            id: this.currentEditExperienceId || null,
            jobTitle: d.jobTitle || "",
            organization: d.organization || "",
            employmentType: d.employmentType || "",
            location: d.location || "",
            startMonth: d.startMonth || start.month,
            startYear: d.startYear || start.year,
            endMonth: d.endMonth || end.month,
            endYear: d.endYear || end.year,
            isCurrentJob: d.isCurrentJob || false,
            roleDescription: d.roleDescription || "",
            workType: "Onsite",
            jobRole: d.jobRole || d.employmentStatus || ""
          }
        });
        this.showExperienceModal = false;
        this.currentEditExperienceId = null;
        await this.loadProfile();
        await this.loadRecordHealth();
        this.showSuccess("Experience saved successfully");
      } catch (e) {
        console.error("Failed to save experience", e);
      }
    });
  }
  get educationModalTitle() {
    return this.currentEditEducationId ? "Edit Education" : "Add Education";
  }

  openAddEducation() {
    this.currentEditEducationId = null;
    this.educationModalData = null;
    this.showEducationModal = true;
  }

  handleEditEducation(event) {
    const id = event.detail.id;
    const edu = (this.profileData.education || []).find((e) => e.id === id);
    if (!edu) return;

    this.currentEditEducationId = id;
    this.educationModalData = {
      id,
      degree: edu.degree || "",
      institution: edu.institution || "",
      institutionType: edu.institutionType || "",
      programPlan: edu.programPlan || "",
      registrationNumber: edu.registrationNumber || "",
      startMonth: edu.startMonth || "",
      startYear: edu.startYear || "",
      endMonth: edu.endMonth || "",
      endYear: edu.endYear || "",
      gradingFormat: edu.gradingFormat || "CGPA",
      cgpa: edu.cgpa || (edu.score || "").replace("%", "")
    };
    this.showEducationModal = true;
  }

  async handleDeleteEducation(event) {
    const id = event.detail.id;
    await this.runWithLoader("Deleting education...", async () => {
      try {
        await archiveEducationRecord({ recordId: id });
        await this.loadProfile();
        this.showSuccess("Education deleted successfully");
      } catch (e) {
        console.error("Failed to archive education", e);
      }
    });
  }

  handleCloseEducationModal() {
    this.showEducationModal = false;
    this.currentEditEducationId = null;
    this.educationModalData = null;
  }

  async handleSaveEducation(event) {
    const d = event.detail || {};

    await this.runWithLoader("Saving education...", async () => {
      try {
        await saveEducationRecord({
          input: {
            id: this.currentEditEducationId || null,
            degree: d.degree || "",
            institution: d.institution || "",
            institutionType: d.institutionType || "institute",
            programPlan: d.programPlan || null,
            registrationNumber: d.registrationNumber || null,
            startMonth: d.startMonth || null,
            startYear: d.startYear || null,
            endMonth: d.endMonth || null,
            endYear: d.endYear || null,
            gradingFormat: d.gradingFormat || "CGPA",
            cgpa: d.cgpa || ""
          }
        });
        this.handleCloseEducationModal();
        await this.loadProfile();
        this.showSuccess("Education saved successfully");
      } catch (e) {
        console.error("Failed to save education", e);
      }
    });
  }

  get achievementModalTitle() {
    return this.currentEditAchievementId
      ? "Edit Achievement"
      : "Add Achievement";
  }

  openAddAchievement() {
    this.currentEditAchievementId = null;
    this.achievementModalData = null;
    this.showAchievementModal = true;
  }

  handleEditAchievement(event) {
    const id = event.detail.id;
    const ach = (this.profileData.achievements || []).find((a) => a.id === id);
    if (!ach) return;

    this.currentEditAchievementId = id;
    this.achievementModalData = {
      id,
      type: ach.type || "Honors & Awards",
      title: ach.title || "",
      organization: ach.organization || "",
      dateMonth: ach.dateMonth || "",
      dateYear: ach.dateYear || "",
      description: ach.description || "",
      patentNumber: ach.patentNumber || "",
      status: ach.status || "",
      role: ach.role || "",
      referenceUrl: ach.referenceUrl || "",
      paperType: ach.paperType || ""
    };
    this.showAchievementModal = true;
  }

  async handleDeleteAchievement(event) {
    const id = event.detail.id;
    await this.runWithLoader("Deleting achievement...", async () => {
      try {
        await archiveAchievementRecord({ recordId: id });
        await this.loadProfile();
        this.showSuccess("Achievement deleted successfully");
      } catch (e) {
        console.error("Failed to archive achievement", e);
      }
    });
  }

  handleCloseAchievementModal() {
    this.showAchievementModal = false;
    this.currentEditAchievementId = null;
    this.achievementModalData = null;
  }

  async handleSaveAchievement(event) {
    const d = event.detail || {};

    await this.runWithLoader("Saving achievement...", async () => {
      try {
        await saveAchievementRecord({
          input: {
            id: this.currentEditAchievementId || null,
            type: d.type || "Honors & Awards",
            title: d.title || "",
            organization: d.organization || "",
            dateMonth: d.dateMonth || null,
            dateYear: d.dateYear || null,
            description: d.description || "",
            patentNumber: d.patentNumber || "",
            status: d.status || null,
            role: d.role || null,
            referenceUrl: d.referenceUrl || "",
            paperType: d.paperType || null
          }
        });
        this.handleCloseAchievementModal();
        await this.loadProfile();
        this.showSuccess("Achievement saved successfully");
      } catch (e) {
        console.error("Failed to save achievement", e);
      }
    });
  }

  extractMonthYear(dateString) {
    if (!dateString) return { month: null, year: null };
    const parts = String(dateString).split("-");
    if (parts.length < 2) return { month: null, year: null };
    return { year: parts[0], month: parts[1] };
  }
}