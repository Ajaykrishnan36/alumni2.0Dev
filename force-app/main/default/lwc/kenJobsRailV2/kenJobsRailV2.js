import { LightningElement, api, track } from 'lwc';

export default class KenJobsRailV2 extends LightningElement {
    @api applications = [];
    @api savedJobs = [];
    @api postedJobs = [];
    @track activeTab = 'applied';

    get hasPosted()   { return (this.postedJobs || []).length > 0; }
    get postedItems() { return (this.postedJobs || []).slice(0, 5); }

    get showApplied() { return this.activeTab === 'applied'; }
    get showSaved()   { return this.activeTab === 'saved'; }
    get hasApplied()  { return (this.applications || []).length > 0; }
    get hasSaved()    { return (this.savedJobs || []).length > 0; }
    get noApplied()   { return !this.hasApplied; }
    get noSaved()     { return !this.hasSaved; }
    get appliedItems() { return (this.applications || []).slice(0, 3); }
    get savedItems()   { return (this.savedJobs || []).slice(0, 3); }

    handleTabChange(event) {
        this.activeTab = event.detail.id;
    }
    handleItem(event) {
        // IDs are Salesforce strings (e.g. 18-char Ids). Do NOT Number()-cast — that yields NaN.
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('jobclick', { detail: { id } }));
    }
    handlePostJob() {
        this.dispatchEvent(new CustomEvent('postjob'));
    }
}