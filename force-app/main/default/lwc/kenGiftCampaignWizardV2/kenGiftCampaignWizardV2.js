import { LightningElement, track } from 'lwc';
import submitCampaignRequest from '@salesforce/apex/KenGiftCampaignController.submitCampaignRequest';

const CATEGORIES = ['Scholarship', 'Infrastructure', 'Emergency', 'Research', 'Athletics', 'General'];

export default class KenGiftCampaignWizardV2 extends LightningElement {
    @track step = 1;
    @track title = '';
    @track category = 'General';
    @track goalAmount = '';
    @track description = '';
    @track story = '';
    @track heroImageUrl = '';
    @track errorMsg = '';
    @track submitting = false;
    @track done = false;

    get isStep1() { return this.step === 1 && !this.done; }
    get isStep2() { return this.step === 2 && !this.done; }
    get isStep3() { return this.step === 3 && !this.done; }
    get isStep1Cls() { return this.step === 1 ? 'on' : ''; }
    get isStep2Cls() { return this.step === 2 ? 'on' : ''; }
    get isStep3Cls() { return this.step === 3 ? 'on' : ''; }
    get categoryOptions() {
        return CATEGORIES.map(v => ({ value: v, selected: v === this.category }));
    }
    get goalDisplay() {
        const n = Number(this.goalAmount);
        if (!isFinite(n) || n <= 0) return '—';
        try { return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(n); }
        catch (e) { return '₹' + n; }
    }

    handleField(e) { this[e.target.dataset.field] = e.target.value; }

    handleNext() {
        this.errorMsg = '';
        if (this.step === 1) {
            if (!this.title.trim()) { this.errorMsg = 'Please enter a campaign title.'; return; }
            const g = Number(this.goalAmount);
            if (!isFinite(g) || g <= 0) { this.errorMsg = 'Please enter a fundraising goal greater than zero.'; return; }
        }
        if (this.step < 3) this.step += 1;
    }
    handleBack() { this.errorMsg = ''; if (this.step > 1) this.step -= 1; }

    _requestId() {
        try { if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID(); } catch (e) { /* ignore */ }
        return 'camp-' + Date.now() + '-' + Math.floor(Math.random() * 1e6);
    }

    handleSubmit() {
        this.errorMsg = '';
        this.submitting = true;
        const input = {
            title: this.title,
            description: this.description,
            story: this.story,
            goalAmount: Number(this.goalAmount),
            category: this.category,
            heroImageUrl: this.heroImageUrl,
            requestId: this._requestId()
        };
        submitCampaignRequest({ req: input })
            .then(() => { this.submitting = false; this.done = true; })
            .catch(err => {
                this.submitting = false;
                // eslint-disable-next-line no-console
                console.error('submitCampaignRequest error', err);
                this.errorMsg = (err && err.body && err.body.message) || 'Could not submit your campaign. Please try again.';
            });
    }

    handleStartAnother() {
        this.step = 1; this.title = ''; this.category = 'General'; this.goalAmount = '';
        this.description = ''; this.story = ''; this.heroImageUrl = ''; this.done = false; this.errorMsg = '';
    }
}