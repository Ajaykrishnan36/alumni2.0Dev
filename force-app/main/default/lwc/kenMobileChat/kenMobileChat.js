import { LightningElement, track } from "lwc";
import { getPortalConfigs as getPrimaryColor } from "c/kenThemeConfig";
import {
  LIST_POLL_MS,
  THREAD_POLL_MS,
  fetchRooms,
  fetchMessages,
  postMessage,
  markThreadRead,
  decorateRooms,
  decorateMessages,
  decorateFiles,
  filterByName,
  readError,
  uploadFile
} from "c/kenChatService";

/*
 * Mobile chat (viewport <= 768px). Wrapper: render <c-ken-mobile-chat> when isMobile,
 * <c-ken-chat> when isDesktop.
 *
 * Identical to the desktop component except that it shows one pane at a time - viewMode swaps
 * between the conversation list and an open thread, with a back button. All data logic lives in
 * c/kenChatService, so the two layouts cannot drift apart.
 */
export default class KenMobileChat extends LightningElement {
  @track activeTab = "individuals";
  @track searchTerm = "";
  @track selectedChat = null;
  @track newMessageText = "";
  @track pendingFiles = [];
  @track isUploading = false;
  // The attachment being shown full-size, or null. Kept here rather than on the file so opening
  // one never mutates the message list the poll is replacing under it.
  @track previewFile = null;
  @track viewMode = "list";

  @track individualsList = [];
  @track groupsList = [];
  @track messagesByChat = {};

  errorMessage = "";
  _listTimer;
  _threadTimer;
  _onVisibility;
  /* Same anchoring as kenChat - see the note there for why the old latch mis-fired. */
  _lastRenderKey = "";
  _stickToBottom = true;

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
        // Theme is cosmetic; chat still works on the default palette.
      });

    this.loadRooms();
    this._onVisibility = () => {
      if (document.visibilityState === "hidden") {
        this.stopPolling();
      } else {
        this.startPolling();
        this.loadRooms(true);
        if (this.selectedChatId) this.loadMessages(this.selectedChatId, true);
      }
    };
    document.addEventListener("visibilitychange", this._onVisibility);

    // Escape closes the preview. Registered on the document because the overlay is not
    // focusable and a viewer reaching for Escape has not necessarily clicked it first.
    this._onKeydown = (e) => {
      if (e.key === "Escape" && this.previewFile) this.previewFile = null;
    };
    document.addEventListener("keydown", this._onKeydown);
    this.startPolling();
  }

  disconnectedCallback() {
    this.stopPolling();
    if (this._onVisibility) {
      document.removeEventListener("visibilitychange", this._onVisibility);
    }
    if (this._onKeydown) {
      document.removeEventListener("keydown", this._onKeydown);
    }
  }

  startPolling() {
    this.stopPolling();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._listTimer = setInterval(() => this.loadRooms(true), LIST_POLL_MS);
    // On mobile only one pane is on screen, so the thread poll is pointless in list view.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._threadTimer = setInterval(() => {
      if (this.viewMode === "thread" && this.selectedChatId) {
        this.loadMessages(this.selectedChatId, true);
      }
    }, THREAD_POLL_MS);
  }

  stopPolling() {
    if (this._listTimer) {
      clearInterval(this._listTimer);
      this._listTimer = null;
    }
    if (this._threadTimer) {
      clearInterval(this._threadTimer);
      this._threadTimer = null;
    }
  }

  async loadRooms(silent = false) {
    try {
      const rooms = await fetchRooms(this.activeTab);
      if (this.activeTab === "groups") {
        this.groupsList = rooms;
      } else {
        this.individualsList = rooms;
      }
      this.errorMessage = "";
    } catch (e) {
      if (!silent) this.errorMessage = readError(e);
    }
  }

  async loadMessages(roomId, silent = false) {
    try {
      const rows = await fetchMessages(roomId);
      this.messagesByChat = { ...this.messagesByChat, [roomId]: rows };
      const marked = await markThreadRead(this.findRoom(roomId));
      if (marked > 0) this.loadRooms(true);
    } catch (e) {
      if (!silent) this.errorMessage = readError(e);
    }
  }

  findRoom(id) {
    const all = [...(this.individualsList || []), ...(this.groupsList || [])];
    return all.find((r) => r.id === id) || null;
  }

  // ---- getters -------------------------------------------------------------------------

  get isIndividuals() {
    return this.activeTab === "individuals";
  }
  get isGroups() {
    return this.activeTab === "groups";
  }
  get isListView() {
    return this.viewMode === "list";
  }
  get isThreadView() {
    return this.viewMode === "thread";
  }
  get hasSelectedChat() {
    return !!this.selectedChat;
  }
  get isGroupSelected() {
    return this.selectedChat && this.selectedChat.type === "group";
  }
  get hasError() {
    return !!this.errorMessage;
  }
  get selectedChatId() {
    return this.selectedChat ? this.selectedChat.id : null;
  }

  get currentList() {
    const list =
      this.activeTab === "individuals" ? this.individualsList : this.groupsList;
    return Array.isArray(list) ? list : [];
  }

  get filteredList() {
    return decorateRooms(
      filterByName(this.currentList, this.searchTerm),
      this.selectedChatId,
      "chat-card mobile-chat-card"
    );
  }

  get currentMessages() {
    if (!this.selectedChat) return [];
    return decorateMessages(
      this.messagesByChat[this.selectedChat.id],
      this.selectedChat
    );
  }

  get chatHeaderSubline() {
    if (!this.selectedChat) return "";
    if (this.selectedChat.type === "group") {
      return `${this.selectedChat.membersCount || 0} members`;
    }
    return this.selectedChat.online ? "Online" : "Offline";
  }

  /* Presence belongs to a 1:1 only - a group is many people and has no single online state. */
  get showHeaderPresenceDot() {
    return !!(
      this.selectedChat &&
      this.selectedChat.type === "individual" &&
      this.selectedChat.online
    );
  }

  // ---- handlers ------------------------------------------------------------------------

  handleTabChange(event) {
    const tab = event.currentTarget.dataset.tab;
    if (!tab || tab === this.activeTab) return;
    this.activeTab = tab;
    this.selectedChat = null;
    this.loadRooms();
  }

  handleSearchInput(event) {
    this.searchTerm = event.target.value;
  }

  handleChatSelect(event) {
    const id = event.currentTarget.dataset.id;
    this.selectedChat = this.currentList.find((c) => c.id === id) || null;
    if (!this.selectedChat) return;
    this.viewMode = "thread";
    this._stickToBottom = true;
    this.loadMessages(id);
    this._scrollMessagesToBottomAfterRender();
  }

  handleBack() {
    this.viewMode = "list";
    this.selectedChat = null;
    // A file attached in one thread must not follow the viewer into the next one.
    this._clearComposer();
    // Coming back from a thread the unread state has just changed, so refresh the list.
    this.loadRooms(true);
  }

  /* Same upload contract as the desktop layout - see the notes in kenChat.js. */
  get decoratedPendingFiles() {
    return decorateFiles(this.pendingFiles);
  }
  get hasPendingFiles() {
    return this.pendingFiles.length > 0;
  }
  get canSend() {
    return (
      !this.isUploading &&
      (!!(this.newMessageText || "").trim() || this.pendingFiles.length > 0)
    );
  }
  get sendDisabled() {
    return !this.canSend;
  }

  get hasFilePreview() {
    return !!this.previewFile;
  }

  /*
   * Opens an image full size in place. Only images come through here: a document's URL is served
   * Content-Disposition: attachment, so it cannot be displayed at all - its chip is a plain link
   * that saves the file, which is the intended behaviour.
   */
  handleOpenPreview(event) {
    const el = event.currentTarget;
    this.previewFile = { src: el.dataset.src, name: el.dataset.name };
  }

  handleClosePreview() {
    this.previewFile = null;
  }

  /*
   * Focus moves to the message box, because the paperclip keeps it otherwise: the next Enter
   * activates the still-focused BUTTON and the file dialog opens again instead of the message
   * being sent.
   */
  handleAttachClick() {
    const input = this.template.querySelector(".chat-file-input");
    if (input) input.click();
    this._focusComposer();
  }

  _focusComposer() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      const box = this.template.querySelector(".chat-composer-input");
      if (box) box.focus();
    }, 0);
  }

  async handleFilesSelected(event) {
    const files = Array.from(event.target.files || []);
    event.target.value = "";
    if (!files.length || !this.selectedChat) return;

    const roomId = this.selectedChat.id;
    this.isUploading = true;
    this.errorMessage = "";
    for (const file of files) {
      try {
        // eslint-disable-next-line no-await-in-loop -- one Apex call per file on purpose
        const uploaded = await uploadFile(roomId, file);
        this.pendingFiles = [...this.pendingFiles, uploaded];
      } catch (e) {
        this.errorMessage = readError(e);
      }
    }
    this.isUploading = false;
    // Enter should send what was just attached, not re-open the picker.
    this._focusComposer();
  }

  handleRemovePending(event) {
    const key = event.currentTarget.dataset.key;
    this.pendingFiles = this.pendingFiles.filter(
      (f) => (f.contentDocumentId || f.id) !== key
    );
  }

  _clearComposer() {
    this.newMessageText = "";
    this.pendingFiles = [];
    this.isUploading = false;
    this.previewFile = null;
  }

  async handleSend() {
    const text = (this.newMessageText || "").trim();
    if (!this.selectedChat || !this.canSend) return;
    const roomId = this.selectedChat.id;
    const files = this.pendingFiles;
    this.newMessageText = "";
    this.pendingFiles = [];
    try {
      await postMessage(roomId, text, files);
      await this.loadMessages(roomId);
      this.loadRooms(true);
      this._scrollMessagesToBottomAfterRender();
    } catch (e) {
      this.errorMessage = readError(e);
      this.newMessageText = text;
      this.pendingFiles = files;
    }
  }

  handleComposerInput(event) {
    this.newMessageText = event.target.value;
  }

  handleComposerKeyDown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      this.handleSend();
    }
  }

  handleMessagesScroll(event) {
    const el = event.target;
    this._stickToBottom =
      el.scrollHeight - el.scrollTop - el.clientHeight <= 40;
  }

  renderedCallback() {
    if (!this.isThreadView || !this.hasSelectedChat) return;

    const msgs = this.currentMessages;
    const newest = msgs.length ? msgs[msgs.length - 1].key : "";
    const key = `${this.selectedChatId}|${msgs.length}|${newest}`;
    if (key === this._lastRenderKey) return;

    const isNewRoom = !this._lastRenderKey.startsWith(
      `${this.selectedChatId}|`
    );
    this._lastRenderKey = key;

    if (isNewRoom || this._stickToBottom) {
      this._stickToBottom = true;
      this._scrollMessagesToBottomAfterRender();
    }
  }

  scrollMessagesToBottom() {
    const el = this.template.querySelector(".chat-messages");
    if (el) el.scrollTop = el.scrollHeight;
  }

  _scrollMessagesToBottomAfterRender() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => this.scrollMessagesToBottom(), 0);
  }
}