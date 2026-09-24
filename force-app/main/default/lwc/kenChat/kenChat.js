import { LightningElement, api, track } from "lwc";
import { getPortalConfigs as getPrimaryColor } from "c/kenThemeConfig";
import {
  LIST_POLL_MS,
  THREAD_POLL_MS,
  fetchPollConfig,
  fetchRooms,
  fetchMessages,
  postMessage,
  markThreadRead,
  decorateRooms,
  decorateMessages,
  decorateFiles,
  filterByName,
  readError,
  uploadFile,
  fetchRoomForAlumnus
} from "c/kenChatService";

/*
 * Desktop chat - list and thread side by side. The mobile variant is c/kenMobileChat; a parent
 * page picks between them on viewport. All the data logic is shared in c/kenChatService so the
 * two layouts cannot drift apart.
 *
 * Messages arrive by polling rather than streaming. A platform event broadcasts every payload to
 * every subscriber and filters client-side, and it goes dark for portal users without
 * "API Enabled" - neither is acceptable for an alumni portal.
 */
export default class KenChat extends LightningElement {
  /*
   * SINGLE-THREAD MODE. Set alumnusId and the component drops the conversation rail and shows
   * just that person's thread - which is what the Network profile's floating window needs.
   *
   * It is the same component on purpose. The profile page used to carry its own chat-shaped
   * markup with a hardcoded message array and a send handler that pushed into local state, so
   * nothing it sent ever left the browser. Reusing this one means the polling, read receipts,
   * unread state, uploads and previews are the ones that already work, and a fix lands in both
   * places at once.
   */
  @api alumnusId;
  /** The floating window draws its own title bar, so this suppresses the thread's own header. */
  @api hideHeader = false;

  @track activeTab = "individuals";
  @track searchTerm = "";
  @track selectedChat = null;
  @track newMessageText = "";
  // Files already uploaded and waiting for Send to attach them to a message.
  @track pendingFiles = [];
  @track isUploading = false;
  // The attachment being shown full-size, or null. Kept here rather than on the file so opening
  // one never mutates the message list the poll is replacing under it.
  @track previewFile = null;

  @track individualsList = [];
  @track groupsList = [];
  @track messagesByChat = {};

  errorMessage = "";
  _listPollMs = LIST_POLL_MS;
  _threadPollMs = THREAD_POLL_MS;
  _listTimer;
  _threadTimer;
  _onVisibility;
  /*
   * Scroll anchoring.
   *
   * _lastRenderKey identifies what is on screen (room + count + newest id). The latch
   * this replaces was set in renderedCallback, which fires BEFORE the messages arrive
   * from Apex - so it scrolled an empty list, latched, and never scrolled again. That is
   * why a thread opened mid-conversation and why an arriving message never pulled the
   * view down.
   *
   * _stickToBottom stops that becoming the opposite bug: someone reading history must
   * not be yanked to the newest message every ten seconds.
   */
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

    if (this.isSingleThread) {
      this.loadSingleRoom();
    } else {
      this.loadRooms();
    }
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

    // Start on the built-in rate, then restart on the admin-configured one once it arrives,
    // so a slow config call never delays the first refresh.
    this.startPolling();
    fetchPollConfig().then((cfg) => {
      this._listPollMs = cfg.listPollMs;
      this._threadPollMs = cfg.threadPollMs;
      this.startPolling();
    });
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
    this._listTimer = setInterval(() => this.loadRooms(true), this._listPollMs);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._threadTimer = setInterval(() => {
      // hasFocus() distinguishes "watching it" from "tab is merely visible". A visible but
      // unfocused window keeps showing new messages without marking them read.
      if (this.selectedChatId) {
        this.loadMessages(this.selectedChatId, true, document.hasFocus());
      }
    }, this._threadPollMs);
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
    // No rail in single-thread mode, so a list poll would fetch every room for nothing.
    if (this.isSingleThread) return;
    try {
      const rooms = await fetchRooms(this.activeTab);
      if (this.activeTab === "groups") {
        this.groupsList = rooms;
      } else {
        this.individualsList = rooms;
      }
      this.errorMessage = "";
    } catch (e) {
      // A failed background poll must not replace a working screen with an error.
      if (!silent) this.errorMessage = readError(e);
    }
  }

  async loadSingleRoom() {
    try {
      const room = await fetchRoomForAlumnus(this.alumnusId);
      if (!room) {
        this.errorMessage =
          "You can message someone once your connection is accepted.";
        return;
      }
      this.individualsList = [room];
      this.selectedChat = room;
      this._stickToBottom = true;
      await this.loadMessages(room.id);
      this._scrollMessagesToBottomAfterRender();
    } catch (e) {
      this.errorMessage = readError(e);
    }
  }

  async loadMessages(roomId, silent = false, markSeen = true) {
    try {
      const room = this.findRoom(roomId);
      const wasUnread = !!(room && room.unread);

      const rows = await fetchMessages(roomId, markSeen);
      this.messagesByChat = { ...this.messagesByChat, [roomId]: rows };

      // Only 1:1 rooms carry per-message read state; this is a no-op for groups. Skipped
      // entirely when we are not treating this fetch as the viewer having looked.
      const marked = markSeen ? await markThreadRead(room) : 0;

      /*
       * Refresh the list whenever the row could have stopped being bold - not just when
       * messages were marked. A group never marks anything, so keying off `marked` left
       * group rows bold until the next 30s list poll even though opening them had already
       * stamped last-seen server-side.
       */
      if (marked > 0 || wasUnread) {
        this.loadRooms(true);
      }
    } catch (e) {
      if (!silent) this.errorMessage = readError(e);
    }
  }

  findRoom(id) {
    const all = [...(this.individualsList || []), ...(this.groupsList || [])];
    return all.find((r) => r.id === id) || null;
  }

  // ---- getters -------------------------------------------------------------------------

  get isSingleThread() {
    return !!this.alumnusId;
  }
  get showRail() {
    return !this.isSingleThread;
  }
  get showThreadHeader() {
    return this.hasSelectedChat && !this.hideHeader;
  }
  get rootClass() {
    return this.isSingleThread ? "ken-chat ken-chat-single" : "ken-chat";
  }

  get isIndividuals() {
    return this.activeTab === "individuals";
  }
  get isGroups() {
    return this.activeTab === "groups";
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
      this.selectedChatId
    );
  }

  get currentMessages() {
    if (!this.selectedChat) return [];
    return decorateMessages(
      this.messagesByChat[this.selectedChat.id],
      this.selectedChat
    );
  }

  get decoratedPendingFiles() {
    return decorateFiles(this.pendingFiles);
  }
  get hasPendingFiles() {
    return this.pendingFiles.length > 0;
  }

  /* Empty text is a valid message when files are attached - Apex allows exactly that. */
  get canSend() {
    return (
      !this.isUploading &&
      (!!(this.newMessageText || "").trim() || this.pendingFiles.length > 0)
    );
  }

  /* Templates cannot negate, so the disabled state is its own getter. */
  get sendDisabled() {
    return !this.canSend;
  }

  get chatHeaderSubline() {
    if (!this.selectedChat) return "";
    if (this.selectedChat.type === "group") {
      return `${this.selectedChat.membersCount || 0} members`;
    }
    return this.selectedChat.online ? "Online" : "Offline";
  }

  /*
   * The dot is presence, so it only belongs on a 1:1 - a group is many people and has no single
   * online state. It used to render a second "N members" line on the right of the header, which
   * printed the same fact twice.
   */
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
    this._clearComposer();
    this.loadRooms();
  }

  handleSearchInput(event) {
    this.searchTerm = event.target.value;
  }

  handleChatSelect(event) {
    const id = event.currentTarget.dataset.id;
    if (id !== this.selectedChatId) this._clearComposer();
    this.selectedChat = this.currentList.find((c) => c.id === id) || null;
    this._stickToBottom = true;
    if (this.selectedChat) this.loadMessages(id);
    this._scrollMessagesToBottomAfterRender();
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

  /*
   * Uploaded one at a time rather than in parallel: each upload is an Apex call that inserts a
   * ContentVersion, and firing five at once is how a portal user meets a governor limit while
   * holding a spinner.
   */
  async handleFilesSelected(event) {
    const files = Array.from(event.target.files || []);
    event.target.value = ""; // so re-picking the same file still fires change
    if (!files.length || !this.selectedChat) return;

    const roomId = this.selectedChat.id;
    this.isUploading = true;
    this.errorMessage = "";
    for (const file of files) {
      try {
        // eslint-disable-next-line no-await-in-loop -- sequential on purpose, see above
        const uploaded = await uploadFile(roomId, file);
        this.pendingFiles = [...this.pendingFiles, uploaded];
      } catch (e) {
        // Report and keep going: one oversized file should not discard the others.
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
      // Hand both back rather than losing them.
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

  /* A chat resets its draft per conversation; a file uploaded into one room must not follow
       the viewer into another. */
  _clearComposer() {
    this.newMessageText = "";
    this.pendingFiles = [];
    this.isUploading = false;
    this.previewFile = null;
  }

  /* 40px of slack: "at the bottom" must survive a stray pixel and a thumbnail settling. */
  handleMessagesScroll(event) {
    const el = event.target;
    this._stickToBottom =
      el.scrollHeight - el.scrollTop - el.clientHeight <= 40;
  }

  renderedCallback() {
    if (!this.hasSelectedChat) return;

    const msgs = this.currentMessages;
    const newest = msgs.length ? msgs[msgs.length - 1].key : "";
    const key = `${this.selectedChatId}|${msgs.length}|${newest}`;
    if (key === this._lastRenderKey) return;

    const isNewRoom = !this._lastRenderKey.startsWith(
      `${this.selectedChatId}|`
    );
    this._lastRenderKey = key;

    // Opening a thread always lands on the newest message. After that, only follow
    // along if the viewer is already parked at the bottom.
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