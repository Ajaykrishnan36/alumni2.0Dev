import { LightningElement, track } from 'lwc';
import getCampaigns from '@salesforce/apex/KenGiftPortalController.getCampaigns';
import getCampaignDetail from '@salesforce/apex/KenGiftPortalController.getCampaignDetail';

export default class KenGiftPortalV2 extends LightningElement {
    @track view = 'list';
    @track campaigns = [];
    @track isLoading = true;
    @track detail = null;
    @track isLoadingDetail = false;
    @track showWizard = false;
    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer;

    connectedCallback() { this.loadCampaigns(); }
    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }

    loadCampaigns() {
        this.isLoading = true;
        getCampaigns()
            .then(rows => { this.campaigns = (rows || []).map(r => this.decorate(r)); this.isLoading = false; })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGiftPortalController.getCampaigns error', err);
                this.campaigns = []; this.isLoading = false;
            });
    }

    decorate(r) {
        const goal = Number(r.goal) || 0;
        const raised = Number(r.raised) || 0;
        const pct = Math.max(0, Math.min(100, Number(r.percent) || 0));
        return {
            ...r,
            goalDisplay: this.money(goal),
            raisedDisplay: this.money(raised),
            pct,
            barStyle: `width:${pct}%`,
            hasHero: !!r.heroImageUrl,
            heroStyle: r.heroImageUrl ? `background-image:url('${String(r.heroImageUrl).replace(/'/g, "\\'")}')` : '',
            donorLabel: `${Number(r.donorCount) || 0} donor${(Number(r.donorCount) || 0) === 1 ? '' : 's'}`
        };
    }

    money(n) {
        try {
            return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(Number(n) || 0);
        } catch (e) { return '₹' + (Number(n) || 0); }
    }

    get isList() { return this.view === 'list'; }
    get isDetail() { return this.view === 'detail'; }
    get hasCampaigns() { return this.campaigns.length > 0; }

    handleOpen(event) {
        const id = event.currentTarget.dataset.id;
        this.isLoadingDetail = true; this.view = 'detail'; this.detail = null;
        try { window.scrollTo({ top: 0, behavior: 'auto' }); } catch (e) { /* ignore */ }
        getCampaignDetail({ campaignId: id })
            .then(d => { this.detail = this.decorateDetail(d); this.isLoadingDetail = false; })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGiftPortalController.getCampaignDetail error', err);
                this._toast('Could not load this campaign.'); this.isLoadingDetail = false; this.view = 'list';
            });
    }

    decorateDetail(d) {
        if (!d) return null;
        return { ...d, campaign: this.decorate(d.campaign), tiers: d.tiers || [], funds: d.funds || [] };
    }

    handleLearnMore() {
        // Placeholder destination — never leave the user at a dead end. Swap for a real
        // mission/impact page when it exists.
        this._toast('Our impact story is coming soon — thank you for caring!');
    }

    handleBack() { this.view = 'list'; this.detail = null; }
    handleDonate() { this.showWizard = true; }
    handleWizardClose() { this.showWizard = false; }
    handleWizardSuccess() {
        this.showWizard = false;
        this._toast('Thank you for your generous gift!');
        this.loadCampaigns();
        if (this.detail) {
            const id = this.detail.campaign.id;
            getCampaignDetail({ campaignId: id })
                .then(d => { this.detail = this.decorateDetail(d); })
                .catch(() => { /* keep prior */ });
        }
    }

    get wizardTiers() { return this.detail ? this.detail.tiers : []; }
    get wizardFunds() { return this.detail ? this.detail.funds : []; }
    get wizardCampaignId() { return this.detail ? this.detail.campaign.id : null; }
    get wizardCampaignName() { return this.detail ? this.detail.campaign.name : ''; }

    _toast(msg) {
        this.toastMessage = msg; this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2600);
    }
}