/**
 * Shared chat logic for c/kenChat (desktop) and c/kenMobileChat.
 *
 * The two components differ only in layout - mobile swaps between a list view and a thread view
 * where desktop shows both at once. Everything else (which Apex to call, how a room or message is
 * decorated for the template, how a timestamp becomes a label) is identical, so it lives here
 * rather than being maintained twice.
 */
import getRooms from "@salesforce/apex/KenChatController.getRooms";
import getRoomForAlumnus from "@salesforce/apex/KenChatController.getRoomForAlumnus";
import getMessages from "@salesforce/apex/KenChatController.getMessages";
import sendMessage from "@salesforce/apex/KenChatController.sendMessage";
import markRead from "@salesforce/apex/KenChatController.markRead";
import editMessageApex from "@salesforce/apex/KenChatController.editMessage";
import deleteMessageApex from "@salesforce/apex/KenChatController.deleteMessage";
import getChatConfig from "@salesforce/apex/KenChatController.getChatConfig";
import uploadChatFile from "@salesforce/apex/KenChatController.uploadChatFile";

/*
 * Two intervals, because the two views tolerate very different lag: a thread you are looking at
 * should feel live, a list of chats does not. Both stop while the tab is hidden - people leave
 * portal tabs open all day, and polling for hours of nobody looking is pure waste.
 *
 * These are only the fallbacks used before the server answers, or if it cannot be reached. The
 * real values come from Ken_Alm_Org_Parameters__c so an admin can tune them without a deploy.
 */
export const LIST_POLL_MS = 30000;
export const THREAD_POLL_MS = 10000;

export async function fetchPollConfig() {
  try {
    const cfg = await getChatConfig();
    return {
      listPollMs: cfg?.listPollMs || LIST_POLL_MS,
      threadPollMs: cfg?.threadPollMs || THREAD_POLL_MS
    };
  } catch {
    // Chat must still work if the setting is unreadable; it just polls at the built-in rate.
    return { listPollMs: LIST_POLL_MS, threadPollMs: THREAD_POLL_MS };
  }
}

/** Apex returning null must not replace an array the getters map over. */
export async function fetchRooms(tab) {
  const apexTab = tab === "groups" ? "Groups" : "Individuals";
  return (await getRooms({ tab: apexTab, offset: 0 })) || [];
}

/**
 * The single room shared with one alumnus - what the Network profile opens as a P2P thread.
 * Returns null when there is no accepted connection, which the caller shows as a message rather
 * than an empty chat.
 */
export function fetchRoomForAlumnus(accountId) {
  return getRoomForAlumnus({ accountId });
}

/**
 * `markSeen` false leaves the room unread even though the messages are fetched. Used by the
 * background poll when the window is not focused, so a thread left open on another monitor does
 * not quietly swallow everything that arrives.
 */
export async function fetchMessages(roomId, markSeen = true) {
  return (await getMessages({ roomId, before: null, markSeen })) || [];
}

/**
 * Sends the composer's contents as messages.
 *
 * ONE FILE PER MESSAGE, deliberately. Folding several files into a single message produced one
 * bubble holding a stack of thumbnails and a document chip, stretched to the full width allowance
 * - unreadable, and impossible to act on a single file. A file per bubble means each one is sized
 * to itself, previews on its own, and reads as a distinct thing that was sent.
 *
 * Typed text goes first, as its own message, so it is not swallowed by whichever attachment
 * happens to be last. Sent in series rather than in parallel: the big object's index is
 * (room, sent-at DESC, uid), so two rows written in the same millisecond collide on the sort key
 * and the order they appear in is not the order they were sent.
 */
export async function postMessage(roomId, body, files) {
  const list = Array.isArray(files) ? files : [];
  const text = (body || "").trim();
  let last;

  if (text) {
    last = await sendMessage({ roomId, body: text, attachmentsJson: null });
  }
  for (const file of list) {
    // eslint-disable-next-line no-await-in-loop -- see the ordering note above
    last = await sendMessage({
      roomId,
      body: null,
      attachmentsJson: JSON.stringify([file])
    });
  }
  return last;
}

/**
 * Edits the sender's own message in place. `sentAt` must be the exact value the message
 * arrived with from getMessages/postMessage - it is one third of the big object's index
 * together with roomId and messageUid, so an altered value would edit a different row (or
 * none) instead of this one.
 */
export function editChatMessage(roomId, messageUid, sentAt, newBody) {
  return editMessageApex({ roomId, sentAt, messageUid, newBody: newBody.trim() });
}

/** Soft-deletes the sender's own message - see KenChatController.deleteMessage for why the
 *  original content still needs a non-blank sentinel rather than actually going blank. */
export function deleteChatMessage(roomId, messageUid, sentAt) {
  return deleteMessageApex({ roomId, sentAt, messageUid });
}

/*
 * ---- files -------------------------------------------------------------------------------
 *
 * Upload happens BEFORE the message is sent: each file is stored and linked to the room, and the
 * FileItem that comes back is held on the client until Send folds it into Attachments__c. So a
 * file whose message is never sent is still in the room's files - which is the same trade every
 * chat makes, and the reason getRoomFiles reads from the link rather than from the messages.
 */
export const MAX_FILE_BYTES = 5 * 1024 * 1024;

const IMAGE_TYPES = new Set([
  "PNG",
  "JPG",
  "JPEG",
  "GIF",
  "WEBP",
  "BMP",
  "SVG"
]);

/** Reads a File into the bare base64 Apex expects - no data: prefix. */
export function readAsBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result || "";
      const comma = result.indexOf(",");
      resolve(comma === -1 ? result : result.substring(comma + 1));
    };
    reader.onerror = () => reject(new Error("That file could not be read."));
    reader.readAsDataURL(file);
  });
}

export async function uploadFile(roomId, file) {
  // Checked here as well as in Apex, so the user is told before spending the upload rather
  // than after it.
  if (file.size > MAX_FILE_BYTES) {
    throw new Error(`${file.name} is larger than 5 MB.`);
  }
  const base64Data = await readAsBase64(file);
  return uploadChatFile({ roomId, fileName: file.name, base64Data });
}

/**
 * The URL a chat attachment is viewed through - a ContentDistribution link minted by Apex at
 * upload.
 *
 * The sharing-enforced servlets (`/sfc/servlet.shepherd/...`, rendition or download) did not
 * resolve for portal users in this org: the thread rendered broken images. This is the same
 * mechanism the alumni avatars and the gallery already use, and it is what an <img> in a portal
 * page can render. It is public and permanent - see the note in KenChatController.uploadChatFile.
 */
export function previewSrc(file) {
  return (file && file.url) || "";
}

export function isImageFile(file) {
  if (!file) return false;
  const type = (file.fileType || "").toUpperCase();
  if (type) return IMAGE_TYPES.has(type);
  const name = (file.name || "").toLowerCase();
  return /\.(png|jpe?g|gif|webp|bmp|svg)$/.test(name);
}

/** PDF, DOCX, XLSX... - short, upper-case, and never longer than the chip can hold. */
export function fileExtLabel(file) {
  const type = (file && file.fileType) || "";
  if (type) return type.toUpperCase().substring(0, 4);
  const name = (file && file.name) || "";
  const dot = name.lastIndexOf(".");
  return dot === -1
    ? "FILE"
    : name
        .substring(dot + 1)
        .toUpperCase()
        .substring(0, 4);
}

export function fileSizeLabel(bytes) {
  const n = Number(bytes);
  if (!n || n < 0) return "";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

export function decorateFiles(files) {
  return (Array.isArray(files) ? files : []).map((f, i) => {
    const isImage = isImageFile(f);
    const src = previewSrc(f);
    return {
      ...f,
      key: f.contentDocumentId || f.id || `file-${i}`,
      isImage,
      // Only an image that has a URL behind it can show itself inline.
      hasThumb: isImage && !!src,
      previewSrc: src,
      /*
       * The same URL does both jobs: an <img> renders it, and a click saves it, because it
       * is served Content-Disposition: attachment. So an image previews in place and a
       * document downloads - which is the behaviour asked for.
       */
      href: src,
      canPreview: !!src,
      cannotPreview: !src,
      extLabel: fileExtLabel(f),
      sizeLabel: fileSizeLabel(f.size)
    };
  });
}

/**
 * Marking read is what turns the OTHER person's tick, so it runs on every fetch rather than only
 * on open - a message that arrives while the thread is on screen has been seen. Groups carry no
 * read state at all, so they are skipped entirely.
 */
export async function markThreadRead(room) {
  if (!room || room.type !== "individual") return 0;
  return (await markRead({ roomId: room.id })) || 0;
}

// ---- decoration ---------------------------------------------------------------------------

/**
 * `baseClass` is supplied by the caller because the two layouts style their cards differently -
 * mobile's stylesheet hangs off .mobile-chat-card. Hard-coding 'chat-card' here silently strips
 * that and the mobile list loses its styling.
 */
export function decorateRooms(list, selectedId, baseClass = "chat-card") {
  return (Array.isArray(list) ? list : []).map((item) => {
    // chat-card-pill is what lets a badged row move its timestamp clear of the corner
    // badge; CSS cannot ask "does this card have a pill" on its own.
    const classes = [baseClass];
    if (item.unread) classes.push("chat-card-unread");
    if (item.pillTag) classes.push("chat-card-pill");

    return {
      ...item,
      key: item.id,
      isSelected: item.id === selectedId,
      // A blank preview is not an empty state to hide - it is a real chat nobody has used yet.
      lastMessage: item.lastMessage || "Start Conversation",
      lastTime: relativeLabel(item.lastMessageAt),
      cardClass: classes.join(" ")
    };
  });
}

export function decorateMessages(rows, room) {
  if (!Array.isArray(rows)) return [];
  const isOneToOne = room && room.type === "individual";
  const isGroup = !!(room && room.type === "group");
  let lastDay = null;
  let lastRun = null;

  return rows.map((m, i) => {
    const day = dayLabel(m.sentAt);
    const showDay = day !== lastDay;
    lastDay = day;

    /*
     * A "run" is consecutive messages from one person on one day. Only the first of a run
     * carries an avatar and a name; the rest tuck in underneath. Without this, three quick
     * messages become three avatars and three name lines, which is what pushed the thread
     * into the widely-spaced list it is today.
     */
    const runId = `${day}|${m.isOutgoing ? "out" : `in:${m.senderName || ""}`}`;
    const startsRun = showDay || runId !== lastRun;
    lastRun = runId;

    // Only a 1:1 can borrow the room's picture for the other side - a group's avatarUrl is
    // its banner, and using it here would label every member with the group's image.
    const fallbackAvatar = !m.isOutgoing && isOneToOne ? room.avatarUrl : null;
    const avatarUrl = m.avatarUrl || fallbackAvatar || null;

    const isDeleted = m.status === "Deleted";
    const isEdited = m.status === "Edited";

    return {
      ...m,
      key: m.id || `msg-${i}`,
      dateLabel: showDay ? day : null,
      time: timeLabel(m.sentAt),
      // A deleted message's text/files are already stripped server-side (KenChatController
      // clears them once Status__c is 'Deleted'), so this is just the placeholder label -
      // there is nothing left to accidentally show even if that check ever changed.
      isDeleted,
      isEdited,
      displayText: isDeleted ? "This message was deleted" : m.text,
      textClass: isDeleted ? "chat-msg-text chat-msg-text-deleted" : "chat-msg-text",
      hasFiles: !isDeleted && !!(m.files && m.files.length),
      files: isDeleted ? [] : decorateFiles(m.files),
      showAvatar: startsRun,
      avatarUrl,
      avatarInitial: initialOf(m.senderName),
      // Both participants in a 1:1 are already named at the top of the thread, so a name
      // over every bubble is noise. A group has to say who is talking.
      showSenderName: isGroup && !m.isOutgoing && startsRun,
      rowClass: startsRun ? "chat-msg-row" : "chat-msg-row chat-msg-row-cont",
      // A tick only means something on your own bubble, and only in a 1:1 - a group
      // records no read state, so a tick there would be a lie.
      showTick: m.isOutgoing && isOneToOne && !isDeleted,
      tickClass: m.isRead ? "chat-msg-tick chat-msg-tick-read" : "chat-msg-tick",
      // Only the sender may act on their own message, and a deleted one has nothing left
      // to edit or delete again.
      canManage: m.isOutgoing && !isDeleted
    };
  });
}

/** Stands in for a missing photo, so an absent avatar is a monogram and not a broken image. */
function initialOf(name) {
  const n = (name || "").trim();
  return n ? n.charAt(0).toUpperCase() : "";
}

export function filterByName(list, term) {
  const t = (term || "").toLowerCase().trim();
  if (!t) return list;
  return list.filter((i) => (i.name || "").toLowerCase().includes(t));
}

export function readError(e) {
  return e?.body?.message || e?.message || "Something went wrong.";
}

// ---- time labels --------------------------------------------------------------------------
// Computed at render, never stored. A stored label freezes: a row written as "Just now" still
// reads "Just now" a week later, which is what Chat V2's Last_Message_Time_Label__c does today.

export function relativeLabel(iso) {
  if (!iso) return "";
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "Just now";
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  const days = Math.floor(hrs / 24);
  if (days === 1) return "1 day ago";
  if (days < 7) return `${days} days ago`;
  const weeks = Math.floor(days / 7);
  return weeks === 1 ? "1 week ago" : `${weeks} weeks ago`;
}

export function timeLabel(iso) {
  if (!iso) return "";
  return new Date(iso)
    .toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true
    })
    .toLowerCase();
}

export function dayLabel(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const today = new Date();
  const yest = new Date();
  yest.setDate(today.getDate() - 1);
  if (d.toDateString() === today.toDateString()) return "Today";
  if (d.toDateString() === yest.toDateString()) return "Yesterday";
  return d.toLocaleDateString("en-US", {
    day: "numeric",
    month: "short",
    year: "numeric"
  });
}