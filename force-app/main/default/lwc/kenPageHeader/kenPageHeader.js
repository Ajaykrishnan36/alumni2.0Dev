import { LightningElement, api, track, wire } from "lwc";
import getChatUnreadCount from "@salesforce/apex/KenChatController.getUnreadCount";
import getChatConfig from "@salesforce/apex/KenChatController.getChatConfig";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import siteBasePath from "@salesforce/community/basePath";
import { MessageContext } from "lightning/messageService";
import KenLogo from "@salesforce/resourceUrl/LoginKen";
import getNavigationMenuItems from "@salesforce/apex/KenNavBarController.getNavigationMenuItems";
import { getPortalConfigs as getPrimaryColor } from "c/kenThemeConfig";
import getUserContactDetails from "@salesforce/apex/KenNavBarController.getUserContactDetails";
import getNewsletterBanner from "@salesforce/apex/KenGalleryController.getNewsletterBanner";
import loginBg from "@salesforce/resourceUrl/AlumniAlt";

const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December"
];

export default class KenHeader extends NavigationMixin(LightningElement) {
  @wire(MessageContext)
  messageContext;

  kenLogo = KenLogo;
  profilePhotoUrl;
  studentName;
  graduationYear;
  @api headerLabel;
  @api linkSetMasterLabel = "Default Navigation";
  @api parentPageName = "Home";
  @api parentPageUrl;
  @api childPageName;
  @api childPageUrl;
  @api settingsPageApiName = "settings__c";
  @api calendarPageApiName = "Calendar__c";
  @api chatPageApiName = "";
  @api parentPageApiName = "";

  @track chatUnread = 0;
  _chatTimer;
  /* Built-in fallback, replaced by the org's configured interval once it arrives. */
  _chatPollMs = 60000;
  _onChatVisibility;

  @track dynamicHeaderLabel = "";
  @track menuItems = [];
  @track breadcrumbLabel = "";
  @track breadcrumbs = [];
  @track hasBreadcrumbVisible = false;
  @track newsletterBanner = null;
  @track currentPageApiName = "";
  publishStatus;

  @wire(CurrentPageReference)
  setCurrentPageReference(ref) {
    const app = ref?.state?.app;
    this.publishStatus = app === "commeditor" ? "Draft" : "Live";
    this.currentPageApiName = ref?.attributes?.name || "";
    this.updateHeaderLabel();
  }

  @wire(getNavigationMenuItems, {
    navigationLinkSetMasterLabel: "$linkSetMasterLabel",
    publishStatus: "$publishStatus",
    addHomeMenuItem: false,
    includeImageUrl: false
  })
  wiredMenuItems({ error, data }) {
    if (data) {
      const base = this.getCommunityBasePath();
      this.menuItems = data.map((item) => {
        const normalizedTarget = this.normalizePath(
          item.actionValue || (item.label === "Home" ? base : ""),
          base
        );
        return {
          label: item.label,
          normalizedTarget
        };
      });
      this.updateHeaderLabel();
    } else if (error) {
      console.error("Header navigation load error:", error);
    }
  }

  @wire(getUserContactDetails)
  wiredUserDetails({ error, data }) {
    if (data) {
      this.profilePhotoUrl = data.profilePhotoUrl || loginBg;
      this.studentName = data.studentName || "Student Name";
      this.graduationYear = data.graduationYear;
    } else if (error) {
      console.error("Header: Error fetching user details:", error);
      this.profilePhotoUrl = loginBg;
      this.studentName = "Student Name";
      this.graduationYear = undefined;
    }
  }

  connectedCallback() {
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
      .catch(() => {
        console.log("Error getting primary color");
      });
    this.loadNewsletterBanner();

    this.refreshChatUnread();
    this._onChatVisibility = () => {
      if (document.visibilityState === "hidden") {
        this.stopChatPolling();
      } else {
        this.startChatPolling();
        this.refreshChatUnread();
      }
    };
    document.addEventListener("visibilitychange", this._onChatVisibility);

    // Start on the built-in rate, then restart on the org's once it arrives, so a slow config
    // call never delays the first badge refresh. Same pattern as c/kenChat.
    this.startChatPolling();
    getChatConfig()
      .then((cfg) => {
        if (cfg && cfg.listPollMs) {
          this._chatPollMs = cfg.listPollMs;
          this.startChatPolling();
        }
      })
      .catch(() => {
        // Cadence is a preference, not a requirement; the built-in rate stands.
      });
  }

  async loadNewsletterBanner() {
    try {
      this.newsletterBanner = await getNewsletterBanner();
    } catch {
      this.newsletterBanner = null;
    }
  }

  get computedHeaderLabel() {
    return this.headerLabel || this.dynamicHeaderLabel || "";
  }

  get showNewsletterBanner() {
    return this.currentPageApiName === "Home" && !!this.newsletterBanner;
  }

  get newsletterTitle() {
    const dateValue = this.newsletterBanner?.photoDate;
    if (dateValue) {
      const parsed = new Date(dateValue);
      if (!isNaN(parsed.getTime())) {
        return `Alumni Newsletter | ${MONTH_NAMES[parsed.getMonth()]} ${parsed.getFullYear()}`;
      }
    }
    return this.newsletterBanner?.fileName || "Alumni Newsletter";
  }

  get myFeedCardClass() {
    let cls = this.hasBreadcrumbVisible
      ? "my-feed-card has-breadcrumb"
      : "my-feed-card";
    if (this.showNewsletterBanner) {
      cls += " newsletter-mode";
    }
    return cls;
  }

  // "View More" goes to the whole gallery - every folder, not just this one.
  handleNewsletterViewMore() {
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: "gallery__c" }
    });
  }

  // "Read Now" goes straight into the Newsletter folder. Falls back to the
  // folder list rather than dead-ending if the album could not be resolved.
  handleNewsletterReadNow() {
    const albumId = this.newsletterBanner?.albumId;
    if (!albumId) {
      this.handleNewsletterViewMore();
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: "album_detail__c" },
      state: { recordId: albumId }
    });
  }

  handleCalendarClick() {
    this.goToSitePage("calendar");
  }

  handleSettingsClick() {
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: this.settingsPageApiName || "settings__c" }
    });
  }

  // ---- chat unread badge ---------------------------------------------------------------
  /*
   * The header sits on every page, so this rides the same 60s cadence as notifications rather
   * than adding a fourth poll. It stops entirely while the tab is hidden - people leave portal
   * tabs open all day.
   */
  disconnectedCallback() {
    this.stopChatPolling();
    if (this._onChatVisibility) {
      document.removeEventListener("visibilitychange", this._onChatVisibility);
    }
  }

  /*
   * The badge polls on the portal's ambient cadence, the same one the notification bell uses,
   * rather than the 60s that was hardcoded here. Two badges in the same row asking "anything
   * new?" on two different clocks was a setting nobody could tune.
   */
  startChatPolling() {
    this.stopChatPolling();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._chatTimer = setInterval(
      () => this.refreshChatUnread(),
      this._chatPollMs
    );
  }

  stopChatPolling() {
    if (this._chatTimer) {
      clearInterval(this._chatTimer);
      this._chatTimer = null;
    }
  }

  async refreshChatUnread() {
    try {
      this.chatUnread = (await getChatUnreadCount()) || 0;
    } catch {
      // A badge is not worth breaking the header over; leave the last known value.
    }
  }

  get hasChatUnread() {
    return this.chatUnread > 0;
  }

  /** Apex caps the count at 9, so anything at the cap is shown as "9+" - two characters at
   *  most, which keeps the pill the same size as the notification bell's. */
  get chatUnreadLabel() {
    return this.chatUnread >= 9 ? "9+" : String(this.chatUnread);
  }

  get chatAriaLabel() {
    return this.chatUnread > 0
      ? `Chat, ${this.chatUnreadLabel} unread`
      : "Chat";
  }

  /*
   * Always navigates within the CURRENT site, derived from window.location.
   *
   * This deliberately does not use comm__namedPage: the org runs two Experience sites whose
   * chat pages share an API name, and the named-page reference resolved to the other one -
   * sending /alumni users to /alumninewvforcesite/blank/chat, which 404s. A path built from the
   * URL the user is already on cannot cross sites.
   */
  handleChatClick() {
    this.goToSitePage("chat");
  }

  /** Absolute URL for a page on the site the user is currently browsing. */
  buildSiteUrl(pageName) {
    const path = `${this.getCommunityBasePath()}/${pageName}`.replace(
      /\/+/g,
      "/"
    );
    return `${window.location?.origin || ""}${path}`;
  }

  /** Full-page navigation to a page on the current site. */
  goToSitePage(pageName) {
    window.location.href = this.buildSiteUrl(pageName);
  }

  handleNotificationClick() {
    // Handle notification click
    this.dispatchEvent(
      new CustomEvent("notificationclick", {
        bubbles: true
      })
    );
  }

  @track isMobileMenuOpen = false;

  handleMenuClick() {
    console.log("KenHeader: Menu clicked (Local toggle)");
    this.isMobileMenuOpen = true;
  }

  handleCloseMenu() {
    this.isMobileMenuOpen = false;
  }

  handleMobileProfileKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.navigateToMyProfile(event);
    }
  }

  navigateToMyProfile(event) {
    if (event) {
      event.stopPropagation();
    }
    this.handleCloseMenu();
    const pageRef = {
      type: "comm__namedPage",
      attributes: { name: "my_profile__c" }
    };
    const basePath = this.getCommunityBasePath();
    const fallbackUrl = `${basePath}/my-profile`.replace(/\/+/g, "/");

    this[NavigationMixin.GenerateUrl](pageRef)
      .then(() => {
        this[NavigationMixin.Navigate](pageRef);
      })
      .catch(() => {
        window.location.assign(fallbackUrl);
      });
  }

  handleMobileSettingsClick() {
    this.handleCloseMenu();
    const apiName = this.settingsPageApiName || "settings__c";
    const pageRef = { type: "comm__namedPage", attributes: { name: apiName } };
    const basePath = this.getCommunityBasePath();
    const fallbackUrl = `${basePath}/settings`.replace(/\/+/g, "/");

    this[NavigationMixin.GenerateUrl](pageRef)
      .then(() => {
        this[NavigationMixin.Navigate](pageRef);
      })
      .catch(() => {
        window.location.assign(fallbackUrl);
      });
  }

  handleMobileCalendarClick() {
    this.handleCloseMenu();
    this.goToSitePage("calendar");
  }

  handleMobileChatClick() {
    this.handleCloseMenu();
    this.goToSitePage("chat");
  }

  handleBreadcrumbVisibilityChange(event) {
    this.hasBreadcrumbVisible = event.detail.isVisible;
  }

  updateHeaderLabel() {
    const base = this.getCommunityBasePath();
    const currentPath = this.normalizePath(
      window.location?.pathname || "/",
      base
    );

    this.updateBreadcrumbLabel(currentPath, base);

    if (!this.menuItems?.length) {
      return;
    }

    let bestMatch = { label: "", score: -1 };

    this.menuItems.forEach((item) => {
      const target = item.normalizedTarget;
      if (!target) return;

      if (target === currentPath) {
        const score = target.length + 1000;
        if (score > bestMatch.score) bestMatch = { label: item.label, score };
      } else if (currentPath.startsWith(target + "/")) {
        const score = target.length;
        if (score > bestMatch.score) bestMatch = { label: item.label, score };
      }
    });

    this.dynamicHeaderLabel = bestMatch.label || "";
  }

  updateBreadcrumbLabel(currentPath, communityBasePath) {
    if (!currentPath) {
      this.breadcrumbLabel = "";
      this.breadcrumbs = [];
      return;
    }

    let pathAfterBase = currentPath;
    if (communityBasePath && currentPath.startsWith(communityBasePath)) {
      pathAfterBase = currentPath.slice(communityBasePath.length);
    }

    const segments = pathAfterBase.split("/").filter(Boolean);
    const basePath = communityBasePath || "/";

    const crumbs = [
      {
        label: "Home",
        url: basePath,
        clickable: segments.length > 0,
        isLast: segments.length === 0
      }
    ];

    if (segments.length) {
      let cumulativePath = basePath;
      segments.forEach((seg, index) => {
        const decoded = decodeURIComponent(seg);
        const label = this.formatBreadcrumbLabel(decoded);
        cumulativePath = this.normalizePath(
          `${cumulativePath}/${decoded}`,
          basePath
        );

        crumbs.push({
          label,
          url: cumulativePath,
          clickable: index < segments.length - 1,
          isLast: index === segments.length - 1
        });
      });
    }

    this.breadcrumbs = crumbs.map((crumb, index) => ({
      ...crumb,
      hasNext: index < crumbs.length - 1
    }));
    this.breadcrumbLabel = crumbs.length ? crumbs[crumbs.length - 1].label : "";
    this.breadcrumbs = crumbs.map((crumb, index) => ({
      ...crumb,
      hasNext: index < crumbs.length - 1,
      cssClass: crumb.isLast ? "breadcrumb-leaf" : "breadcrumb-link"
    }));
  }

  formatBreadcrumbLabel(segment) {
    return segment
      .replace(/[-_]/g, " ")
      .replace(/\s+/g, " ")
      .trim()
      .replace(/\b\w/g, (char) => char.toUpperCase());
  }

  get hasBreadcrumbs() {
    return (
      (this.breadcrumbs?.length || 0) > 1 ||
      this.breadcrumbs?.[0]?.label === "Home"
    );
  }

  getCommunityBasePath() {
    const scoped = (siteBasePath || "").replace(/\/+$/, "");
    if (scoped) return scoped;

    const pathname = window?.location?.pathname || "/";
    const parts = pathname.split("/").filter(Boolean);
    if (!parts.length) return "/";

    const sIndex = parts.indexOf("s");
    if (sIndex > 0) {
      // Handles typical Experience Cloud paths like /alumni/s/*
      return `/${parts.slice(0, sIndex + 1).join("/")}`;
    }

    return `/${parts[0]}`;
  }

  normalizePath(path, communityBasePath = "/") {
    if (!path) return "";

    if (/^https?:\/\//i.test(path)) {
      return "";
    }

    let normalized = path.trim();
    if (!normalized.startsWith("/")) {
      normalized = "/" + normalized;
    }

    normalized = normalized.replace(/\/+$/, "");
    if (normalized === "") normalized = "/";

    if (
      communityBasePath !== "/" &&
      normalized !== communityBasePath &&
      !normalized.startsWith(communityBasePath + "/")
    ) {
      const baseParts = communityBasePath.split("/").filter(Boolean);
      const communityRoot = baseParts.length > 0 ? `/${baseParts[0]}` : "/";

      if (
        normalized === communityRoot ||
        normalized.startsWith(communityRoot + "/")
      ) {
        normalized = normalized.replace(communityRoot, communityBasePath);
      } else {
        normalized = `${communityBasePath}${normalized}`;
      }
    }

    normalized = normalized.replace(/\/+$/, "");
    if (normalized === "")
      normalized = communityBasePath !== "/" ? communityBasePath : "/";

    return normalized;
  }
}