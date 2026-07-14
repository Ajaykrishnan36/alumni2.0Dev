import { LightningElement, api, track } from 'lwc';
import getMyResumes from '@salesforce/apex/KenResumeController.getMyResumes';

/**
 * Apply wizard — Step 1 "Choose a resume".
 * Lists the alumnus's REAL uploaded resumes from the Resume Library
 * (KenResumeController.getMyResumes) so applications use a library resume.
 */
export default class KenJobApplyStepResumeV2 extends LightningElement {
    @api selectedResumeId = '';

    @track _resumes = [];
    @track loaded = false;

    connectedCallback() {
        getMyResumes()
            .then(rows => {
                this._resumes = (rows || []).map(r => ({
                    id: r.id,
                    name: r.name,
                    updated: r.lastModified ? ('Updated ' + r.lastModified) : 'Uploaded',
                    downloadUrl: r.downloadUrl,
                    contentVersionId: r.contentVersionId
                }));
                this.loaded = true;
                // Auto-select the first resume so the wizard always has a valid choice.
                if (!this.selectedResumeId && this._resumes.length) {
                    this._notify(this._resumes[0]);
                }
            })
            .catch(() => { this._resumes = []; this.loaded = true; });
    }

    get resumes() {
        return this._resumes.map(r => ({
            ...r,
            cls: r.id === this.selectedResumeId ? 'opt-row opt-row--active' : 'opt-row'
        }));
    }
    get hasResumes() { return this._resumes.length > 0; }
    get showEmpty() { return this.loaded && this._resumes.length === 0; }

    handleResumePick(event) {
        const id = event.currentTarget.dataset.id;
        const r = this._resumes.find(x => x.id === id);
        if (r) this._notify(r);
    }

    _notify(r) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'selectedResumeId', value: r.id } }));
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'selectedResumeName', value: r.name } }));
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'selectedResumeUrl', value: r.downloadUrl || '' } }));
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'selectedResumeContentVersionId', value: r.contentVersionId || '' } }));
    }
}