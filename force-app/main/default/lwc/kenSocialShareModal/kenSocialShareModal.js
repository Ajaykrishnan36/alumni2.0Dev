import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getImageBytes from "@salesforce/apex/KenGroupFeedController.getImageBytes";

// Platforms with an official web intent that accepts prefilled text directly.
const TEXT_INTENT_BUILDERS = {
  whatsapp: (text) => `https://wa.me/?text=${encodeURIComponent(text)}`,
  x: (text) =>
    `https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}`,
  threads: (text) =>
    `https://www.threads.net/intent/post?text=${encodeURIComponent(text)}`
};

// Platforms with no text-prefill param at all — the caption is always copied to the
// clipboard for these, and this is the best-effort compose/home page opened afterward.
const COMPOSE_PAGE_URLS = {
  facebook:
    "https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fwww.facebook.com%2F",
  linkedin: "https://www.linkedin.com/feed/?shareActive=true",
  // The internal /create/select/ route was tried but triggers an account-picker
  // interstitial for accounts logged into more than one profile — not a clean landing.
  // Instagram publishes no official create-post URL at all, so this is just the plain
  // homepage; the user starts a new post themselves from there.
  instagram: "https://www.instagram.com/"
};

const DEFAULT_CAPTION = "Check out this post from our Alumni community!";

// WhatsApp and Instagram have no web mechanism at all for receiving an image
// (wa.me is text-only; Instagram has no web compose intent). On phones, the
// OS's own native "Share via" sheet is the only way to hand the image + caption
// to those apps together automatically — desktop has no equivalent, so it always
// falls through to the unified download-and-manually-attach flow below.
const NATIVE_SHARE_PLATFORMS = new Set(["whatsapp", "instagram"]);

export default class KenSocialShareModal extends LightningElement {
  @api caption = "";
  @api imageUrl;
  @api imageFileName;
  @api groupId;
  @api feedItemId;
  @api contentDocumentId;

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleBackdropClick() {
    this.handleClose();
  }

  stopPropagation(event) {
    event.stopPropagation();
  }

  async handlePlatformClick(event) {
    const platform = event.currentTarget.dataset.platform;
    // Only attempt the native OS share sheet on mobile-like devices — attempting it
    // on desktop (where it will just fail the canShare check anyway) wastes the click's
    // transient activation on a network fetch first, for no benefit.
    if (
      this.imageUrl &&
      NATIVE_SHARE_PLATFORMS.has(platform) &&
      this.isMobileLike()
    ) {
      const handledByOs = await this.tryNativeShare();
      if (handledByOs) return;
    }

    const captionText =
      this.caption && this.caption.trim()
        ? this.caption.trim()
        : DEFAULT_CAPTION;
    await this.share(platform, captionText);
  }

  isMobileLike() {
    return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent || "");
  }

  async tryNativeShare() {
    if (!navigator.share || !navigator.canShare) return false;
    const captionText =
      this.caption && this.caption.trim()
        ? this.caption.trim()
        : DEFAULT_CAPTION;
    try {
      const { blob, fileName } = await this.fetchImageBlob();
      const file = new File([blob], fileName, {
        type: blob.type || "image/jpeg"
      });
      if (!navigator.canShare({ files: [file] })) return false;
      await navigator.share({ text: captionText, files: [file] });
      return true;
    } catch (err) {
      // AbortError = the user backed out of the OS sheet on purpose — treat as handled
      // so we don't also fall back to opening a web link behind their back.
      return !!(err && err.name === "AbortError");
    }
  }

  // Gets the image as an actual local Blob instead of a URL. A plain fetch(this.imageUrl)
  // is silently blocked by CORS whenever that file's Salesforce domain differs from this
  // page's own domain — which it often does — even though the exact same image renders
  // fine in an <img> tag. Routing the bytes through Apex (the same authenticated channel
  // every other call on this page already uses) sidesteps that entirely, since it's never
  // a cross-origin browser fetch in the first place.
  async fetchImageBlob() {
    if (this.groupId && this.feedItemId && this.contentDocumentId) {
      const result = await getImageBytes({
        groupId: this.groupId,
        feedItemId: this.feedItemId,
        contentDocumentId: this.contentDocumentId
      });
      const byteChars = atob(result.base64Data);
      const byteNumbers = new Array(byteChars.length);
      for (let i = 0; i < byteChars.length; i++)
        byteNumbers[i] = byteChars.charCodeAt(i);
      const blob = new Blob([new Uint8Array(byteNumbers)], {
        type: result.contentType || "image/jpeg"
      });
      return {
        blob,
        fileName: result.fileName || this.imageFileName || "shared-image.jpg"
      };
    }
    // No ids to route through Apex with — last-resort direct fetch, which only
    // succeeds when the image happens to already share this page's origin.
    const response = await fetch(this.imageUrl);
    const blob = await response.blob();
    return { blob, fileName: this.imageFileName || "shared-image.jpg" };
  }

  // Text: WhatsApp/X/Threads always get real URL-embedded prefill — image or no image,
  // since those three genuinely support it. Facebook/LinkedIn/Instagram never support
  // prefill at all (image or no image), so the caption always goes to the clipboard there.
  // Image (any platform): always downloaded automatically; attaching it is always a
  // manual step, since no platform accepts an uploaded image through a plain share link.
  async share(platform, captionText) {
    const textIntentUrl = TEXT_INTENT_BUILDERS[platform]
      ? TEXT_INTENT_BUILDERS[platform](captionText)
      : null;
    const targetUrl = textIntentUrl || COMPOSE_PAGE_URLS[platform] || null;

    if (!textIntentUrl) {
      this.copyCaptionToClipboard(captionText);
    }

    // Open right away, synchronously within the click — targetUrl never depends on the
    // (separately awaited, below) image download, so there's nothing to wait for first
    // and no risk of this being blocked as a popup.
    if (targetUrl) {
      window.open(targetUrl, "_blank", "noopener,noreferrer");
    }

    if (this.imageUrl) {
      const downloaded = await this.downloadImage();
      if (textIntentUrl) {
        // Text is already prefilled in the page that just opened — only the image needs a mention.
        this.toast(
          downloaded ? "success" : "warning",
          downloaded ? "Image downloaded" : "Image opened in a new tab",
          downloaded
            ? "Text is already in the post — upload the image from your device to post."
            : "Right-click it there to save it, then upload it alongside the prefilled text."
        );
      } else {
        this.toast(
          downloaded ? "success" : "warning",
          downloaded
            ? "Caption copied, image downloaded"
            : "Caption copied, image opened in a new tab",
          downloaded
            ? "Please paste the caption and upload the image from your device to post."
            : "Right-click the image there to save it, then paste the caption and upload it to post."
        );
      }
    } else if (!textIntentUrl) {
      this.toast(
        "success",
        "Caption copied",
        "Paste it (Ctrl+V / Cmd+V) into your post."
      );
    }
  }

  copyCaptionToClipboard(captionText) {
    if (!captionText || !navigator.clipboard) return;
    navigator.clipboard.writeText(captionText).catch(() => {
      // Silently ignore — the compose page still opens regardless.
    });
  }

  // Returns true on a real automatic download, false when it had to fall back to opening
  // the image in a new tab for the user to save manually.
  async downloadImage() {
    try {
      const { blob, fileName } = await this.fetchImageBlob();
      // This objectUrl is always same-origin (the browser mints it locally for a Blob
      // we already hold in memory), so the download attribute is honored unconditionally —
      // unlike pointing the link straight at the original cross-origin Salesforce URL.
      const objectUrl = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = objectUrl;
      link.download = fileName;
      document.body.appendChild(link);
      link.click();
      link.remove();
      return true;
    } catch {
      // Last-resort fallback (e.g. the Apex call itself failed) — open the image directly
      // so the user can still save it manually (right-click → Save Image As).
      window.open(this.imageUrl, "_blank", "noopener,noreferrer");
      return false;
    }
  }

  toast(variant, title, message) {
    this.dispatchEvent(new ShowToastEvent({ variant, title, message }));
  }
}