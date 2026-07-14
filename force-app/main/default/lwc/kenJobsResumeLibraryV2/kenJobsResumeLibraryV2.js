import { LightningElement, api, track } from "lwc";
import getMyResumes from "@salesforce/apex/KenResumeController.getMyResumes";
import deleteResume from "@salesforce/apex/KenResumeController.deleteResume";
import uploadResume from "@salesforce/apex/KenResumeController.uploadResume";

const MAX_RESUME_BYTES = 4 * 1024 * 1024; // 4 MB

/**
 * Resume Library — UPLOAD ONLY.
 * The resume *generator/builder* feature has been removed: alumni upload an
 * existing PDF and it appears in their library to download or delete.
 */
export default class KenJobsResumeLibraryV2 extends LightningElement {
    // When embedded inside another shell-wrapped page (e.g. kenJobsV2), skip our
    // own shell wrapper so the sidebar isn't rendered twice.
    @api embedded = false;

    @track resumes = [];
    @track isLoading = true;
    @track searchTerm = "";

    // Upload modal state
    @track showUpload = false;
    @track uploading = false;
    @track pendingName = "";
    _pendingBase64 = "";

    @track toast = "";
    @track toastVisible = false;
    _t;

    connectedCallback() { this.load(); }
    disconnectedCallback() { if (this._t) clearTimeout(this._t); }

    load() {
        this.isLoading = true;
        getMyResumes()
            .then(rows => {
                this.resumes = (rows || []).map(r => ({
                    ...r,
                    canDownload: r.hasPdf && !!r.downloadUrl
                }));
                this.isLoading = false;
            })
            .catch(err => { console.error("getMyResumes", err); this.resumes = []; this.isLoading = false; });
    }

    get _term() { return (this.searchTerm || "").trim().toLowerCase(); }
    get filteredResumes() {
        const t = this._term;
        if (!t) return this.resumes;
        return this.resumes.filter(r => String(r.name || "").toLowerCase().includes(t));
    }
    get hasResumes() { return this.filteredResumes.length > 0; }

    handleSearch(event) { this.searchTerm = (event.target && event.target.value) || ""; }

    handleDelete(e) {
        const id = e.currentTarget.dataset.id;
        deleteResume({ resumeId: id })
            .then(() => { this._toast("Resume deleted"); this.load(); })
            .catch(err => { this._toast((err && err.body && err.body.message) || "Could not delete."); });
    }

    // ---- Upload modal ----
    handleOpenUpload() {
        this.pendingName = "";
        this._pendingBase64 = "";
        this.showUpload = true;
    }
    handleCloseUpload() {
        if (this.uploading) return;
        this.showUpload = false;
        this.pendingName = "";
        this._pendingBase64 = "";
    }

    // Read the picked PDF into base64 but don't upload until Submit.
    handleFilePick(event) {
        const file = event && event.target && event.target.files && event.target.files[0];
        if (!file) return;
        if (file.type !== "application/pdf" && !/\.pdf$/i.test(file.name)) {
            this._toast("Please choose a PDF file.");
            event.target.value = "";
            return;
        }
        if (file.size > MAX_RESUME_BYTES) {
            this._toast("File too large (max 4 MB). Please choose a smaller file.");
            event.target.value = "";
            return;
        }
        const reader = new FileReader();
        reader.onload = () => {
            const result = String(reader.result || "");
            const idx = result.indexOf("base64,");
            this._pendingBase64 = idx > -1 ? result.substring(idx + 7) : "";
            this.pendingName = file.name;
            if (!this._pendingBase64) this._toast("Could not read the file.");
        };
        reader.onerror = () => { this._toast("Could not read the file."); };
        reader.readAsDataURL(file);
        event.target.value = "";
    }

    get submitDisabled() { return this.uploading || !this._pendingBase64; }

    handleSubmitUpload() {
        if (this.submitDisabled) {
            if (!this._pendingBase64) this._toast("Please choose a PDF to upload.");
            return;
        }
        this.uploading = true;
        uploadResume({ fileName: this.pendingName, base64Data: this._pendingBase64 })
            .then(() => {
                this.uploading = false;
                this.showUpload = false;
                this.pendingName = "";
                this._pendingBase64 = "";
                this._toast("Resume uploaded");
                this.load();
            })
            .catch(err => {
                this.uploading = false;
                this._toast((err && err.body && err.body.message) || "Upload failed. Please try again.");
            });
    }

    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains("rl-modal-backdrop")) this.handleCloseUpload();
    }
    stop(event) { event.stopPropagation(); }

    _toast(m) { this.toast = m; this.toastVisible = true; if (this._t) clearTimeout(this._t); /* eslint-disable-next-line @lwc/lwc/no-async-operation */ this._t = setTimeout(() => { this.toastVisible = false; }, 2400); }
}