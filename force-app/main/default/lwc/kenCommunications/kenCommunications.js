/**
 * kenCommunications
 *
 * Four-step wizard for bulk alumni email:
 *   1. Audience    — pick an existing Ken_Segmentation__c or launch the
 *                    embedded audience builder to create one.
 *   2. Compose     — name, subject, body (with {{FirstName}} tokens), from.
 *   3. Review/Send — show recipient count, send now or schedule.
 *   4. Analytics   — live deliverability stats + per-recipient breakdown.
 *
 * State machine is driven by `step`. The component also lists previously sent
 * campaigns so the user can drop into analytics without re-walking the wizard.
 */
import { LightningElement, track, wire } from 'lwc';
import getPortalConfigs from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';
import previewSegmentationCount from '@salesforce/apex/KenCommunicationController.previewSegmentationCount';
import saveDraftCampaign from '@salesforce/apex/KenCommunicationController.saveDraftCampaign';
import sendCampaign from '@salesforce/apex/KenCommunicationController.sendCampaign';
import getCampaign from '@salesforce/apex/KenCommunicationController.getCampaign';
import listCampaigns from '@salesforce/apex/KenCommunicationController.listCampaigns';
import listCampaignRecipients from '@salesforce/apex/KenCommunicationController.listCampaignRecipients';

const VIEW = { HOME: 'HOME', WIZARD: 'WIZARD', ANALYTICS: 'ANALYTICS' };
const STEP = { AUDIENCE: 1, COMPOSE: 2, REVIEW: 3, DONE: 4 };
const STATUS_FILTERS = [
    { value: '', label: 'All statuses' },
    { value: 'Sent', label: 'Sent' },
    { value: 'Opened', label: 'Opened' },
    { value: 'Bounced', label: 'Bounced' }
];

export default class KenCommunications extends LightningElement {
    view = VIEW.HOME;
    step = STEP.AUDIENCE;

    @track campaigns = [];
    campaignsLoading = false;

    selectedSegmentationId = null;
    selectedSegmentationName = '';
    recipientPreview = null;

    showAudienceBuilder = false;

    @track form = {
        campaignId: null,
        name: '',
        subject: '',
        body: '',
        fromName: '',
        fromAddress: '',
        scheduledFor: ''
    };

    saving = false;
    sending = false;

    activeCampaignId = null;
    @track activeCampaign = null;
    @track recipients = [];
    recipientsLoading = false;
    recipientStatusFilter = '';
    analyticsTimer = null;
    analyticsRefreshing = false;

    statusFilterOptions = STATUS_FILTERS;

    connectedCallback() {
        this.loadCampaigns();
    }

    @wire(getPortalConfigs)
    wiredTheme({ data }) {
        if (!data) return;
        const host = this.template.host;
        if (data.primaryColor) {
            host.style.setProperty('--brand-primary', data.primaryColor);
            host.style.setProperty('--brand-primary-soft', this.toSoft(data.primaryColor));
            // Map onto SLDS brand tokens so lightning-button variant="brand"
            // and lightning-input focus rings pick up the customer's colour.
            host.style.setProperty('--lwc-brandAccessible', data.primaryColor);
            host.style.setProperty('--lwc-brandAccessibleActive', data.primaryColor);
            host.style.setProperty('--lwc-colorTextLinkActive', data.primaryColor);
            host.style.setProperty('--slds-c-button-brand-color-background', data.primaryColor);
            host.style.setProperty('--slds-c-button-brand-color-border', data.primaryColor);
        }
        if (data.secondaryColor) host.style.setProperty('--brand-secondary', data.secondaryColor);
        if (data.tertiaryColor)  host.style.setProperty('--brand-tertiary', data.tertiaryColor);

        // The embedded kenSavedAudiencePicker / kenTargetAudienceSelection style
        // their buttons and pills with the global --primary-color / --secondary-color
        // / --tertiary-color vars. Those are set on document.documentElement by the
        // other modules, so set them here too — otherwise inside this wizard they
        // resolve to nothing and the picker renders without brand colour.
        const root = document.documentElement;
        if (data.primaryColor)   root.style.setProperty('--primary-color', data.primaryColor);
        if (data.secondaryColor) root.style.setProperty('--secondary-color', data.secondaryColor);
        if (data.tertiaryColor)  root.style.setProperty('--tertiary-color', data.tertiaryColor);
    }

    toSoft(hex) {
        if (!hex || typeof hex !== 'string') return 'rgba(30,58,138,0.10)';
        const v = hex.replace('#', '');
        if (v.length !== 3 && v.length !== 6) return 'rgba(30,58,138,0.10)';
        const expand = v.length === 3 ? v.split('').map(c => c + c).join('') : v;
        const r = parseInt(expand.substring(0, 2), 16);
        const g = parseInt(expand.substring(2, 4), 16);
        const b = parseInt(expand.substring(4, 6), 16);
        return `rgba(${r},${g},${b},0.10)`;
    }

    disconnectedCallback() {
        this.clearAnalyticsTimer();
    }

    // ----- View helpers --------------------------------------------------
    get isHome() { return this.view === VIEW.HOME; }
    get isWizard() { return this.view === VIEW.WIZARD; }
    get isAnalytics() { return this.view === VIEW.ANALYTICS; }

    get isAudienceStep() { return this.step === STEP.AUDIENCE; }
    get isComposeStep() { return this.step === STEP.COMPOSE; }
    get isReviewStep() { return this.step === STEP.REVIEW; }
    get isDoneStep() { return this.step === STEP.DONE; }

    // Stepper model — mirrors the shared kenCampaignStepper look: numbered
    // circles joined by connector lines, a green progress bar, and a
    // "Step X out of N" pill.
    get stepperItems() {
        const steps = [
            { number: 1, label: 'Audience' },
            { number: 2, label: 'Compose' },
            { number: 3, label: 'Review & Send' },
            { number: 4, label: 'Track' }
        ];
        const total = steps.length;
        return steps.map((s) => {
            const isActive = this.step === s.number;
            const isCompleted = this.step > s.number;
            return {
                ...s,
                isCompleted,
                isLast: s.number === total,
                statusClass: `step ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''}`.trim(),
                lineClass: isCompleted ? 'step-line completed' : 'step-line'
            };
        });
    }

    get stepIndicatorLabel() { return `Step ${this.step} out of 4`; }
    get progressFillStyle() { return `width:${Math.min(100, (this.step / 4) * 100)}%`; }

    get reviewDisabled() { return !this.selectedSegmentationId || !this.form.subject || !this.form.body; }
    get composeDisabled() { return !this.selectedSegmentationId; }
    get sendDisabled() { return this.reviewDisabled || this.sending; }
    get recipientCountLabel() {
        if (this.recipientPreview === null) return 'Calculating…';
        return `${this.recipientPreview} alumni`;
    }

    // Literal `{{...}}` in the template is parsed as an LWC expression, so
    // expose token-bearing strings through getters.
    get subjectPlaceholder() { return 'Dear {{FirstName}}, …'; }
    get bodyLabel() { return 'Body (HTML supported · tokens: {{FirstName}}, {{LastName}}, {{Email}})'; }

    renderedCallback() {
        const ta = this.refs && this.refs.bodyArea;
        if (ta && ta.dataset.synced !== '1') {
            ta.value = this.form.body || '';
            ta.dataset.synced = '1';
        }
        const pb = this.refs && this.refs.previewBody;
        if (pb) {
            const html = this.sanitizePreview(this.form.body || '');
            if (pb.dataset.html !== html) {
                pb.innerHTML = html;
                pb.dataset.html = html;
            }
        }
    }

    sanitizePreview(html) {
        if (!html) return '';
        // strip <script> blocks; admin authors content but defensive cleanup.
        return String(html).replace(/<script[\s\S]*?<\/script>/gi, '');
    }

    // ----- Home: campaign list -------------------------------------------
    async loadCampaigns() {
        this.campaignsLoading = true;
        try {
            const rows = await listCampaigns({ status: null, limitSize: 50 });
            this.campaigns = (rows || []).map((c) => ({
                ...c,
                statusPillClass: this.statusPillClass(c.status),
                createdLabel: this.formatDate(c.createdDate),
                sentLabel: c.sentDateTime ? this.formatDate(c.sentDateTime) : '—',
                deliveryLabel: c.totalRecipients ? `${c.deliveryRate}%` : '—'
            }));
        } catch (e) {
            this.toast('Failed to load campaigns', 'error');
        } finally {
            this.campaignsLoading = false;
        }
    }

    handleNewCampaign() {
        this.resetForm();
        this.view = VIEW.WIZARD;
        this.step = STEP.AUDIENCE;
    }

    handleOpenCampaign(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this.openAnalytics(id);
    }

    // ----- Step 1: Audience ----------------------------------------------
    // Selection list, search and review modal are delegated to the shared
    // c-ken-saved-audience-picker. We only react to its two events:
    //   audienceadded → user picked a saved segmentation
    //   addnew        → user wants to build a brand new one
    async handleAudiencePicked(event) {
        const id = event.detail && event.detail.audienceId;
        if (!id) return;
        this.selectedSegmentationId = id;
        this.selectedSegmentationName = (event.detail && event.detail.name) || '';
        this.recipientPreview = null;
        try {
            this.recipientPreview = await previewSegmentationCount({ segmentationId: id });
        } catch (e) {
            this.recipientPreview = 0;
        }
        this.toast(`Segmentation "${this.selectedSegmentationName || 'Untitled'}" selected.`, 'success');
    }

    handleCreateSegmentation() {
        this.showAudienceBuilder = true;
    }

    async handleCloseAudienceBuilder() {
        // Pull the segmentation the user just built from the embedded audience
        // selector and auto-select it. The audience builder persists the
        // Ken_Segmentation__c record internally; we just adopt its Id here.
        let newSeg = null;
        try {
            const builder = this.refs && this.refs.audienceBuilder;
            if (builder && typeof builder.getCurrentSegmentation === 'function') {
                newSeg = builder.getCurrentSegmentation();
            }
        } catch (e) {
            newSeg = null;
        }

        this.showAudienceBuilder = false;

        // Refresh the shared picker so the new segmentation shows in its list.
        const picker = this.refs && this.refs.savedPicker;
        if (picker && typeof picker.refresh === 'function') picker.refresh();

        if (newSeg && newSeg.id) {
            this.selectedSegmentationId = newSeg.id;
            this.selectedSegmentationName = newSeg.name || '';
            this.recipientPreview = null;
            try {
                this.recipientPreview = await previewSegmentationCount({ segmentationId: newSeg.id });
            } catch (e) {
                this.recipientPreview = 0;
            }
            this.toast(`Segmentation "${newSeg.name || 'Untitled'}" added.`, 'success');
        }
    }

    handleNextFromAudience() {
        if (!this.selectedSegmentationId) {
            this.toast('Pick a segmentation to continue.', 'info');
            return;
        }
        if (!this.form.name) {
            this.form.name = `${this.selectedSegmentationName} · ${new Date().toLocaleDateString()}`;
        }
        this.step = STEP.COMPOSE;
    }

    // ----- Step 2: Compose ------------------------------------------------
    handleFormChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        if (!field) return;
        this.form = { ...this.form, [field]: value };
    }

    async handleSaveDraft() {
        if (!this.selectedSegmentationId) return;
        this.saving = true;
        try {
            const id = await saveDraftCampaign({
                campaignId: this.form.campaignId,
                name: this.form.name,
                subject: this.form.subject,
                body: this.form.body,
                segmentationId: this.selectedSegmentationId,
                fromName: this.form.fromName,
                fromAddress: this.form.fromAddress
            });
            this.form = { ...this.form, campaignId: id };
            this.toast('Draft saved', 'success');
        } catch (e) {
            this.toast(this.reduceError(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    handleNextFromCompose() {
        if (!this.form.subject || !this.form.body) {
            this.toast('Subject and body are required.', 'info');
            return;
        }
        this.handleSaveDraft();
        this.step = STEP.REVIEW;
    }

    handleBackToAudience() { this.step = STEP.AUDIENCE; }
    handleBackToCompose()  { this.step = STEP.COMPOSE; }

    // ----- Step 3: Review & Send -----------------------------------------
    async handleSendNow() {
        await this.dispatchSend(null);
    }

    async handleSchedule() {
        if (!this.form.scheduledFor) {
            this.toast('Pick a date/time to schedule.', 'info');
            return;
        }
        await this.dispatchSend(this.form.scheduledFor);
    }

    async dispatchSend(scheduledFor) {
        if (!this.form.campaignId) {
            await this.handleSaveDraft();
        }
        if (!this.form.campaignId) return;
        this.sending = true;
        try {
            await sendCampaign({
                campaignId: this.form.campaignId,
                scheduledFor: scheduledFor || null
            });
            this.toast(scheduledFor ? 'Campaign scheduled' : 'Campaign queued — sending in batches.', 'success');
            this.activeCampaignId = this.form.campaignId;
            this.step = STEP.DONE;
            this.openAnalytics(this.form.campaignId);
        } catch (e) {
            this.toast(this.reduceError(e), 'error');
        } finally {
            this.sending = false;
        }
    }

    // ----- Step 4 / Analytics --------------------------------------------
    openAnalytics(campaignId) {
        this.activeCampaignId = campaignId;
        this.view = VIEW.ANALYTICS;
        this.refreshAnalytics();
        this.clearAnalyticsTimer();
        this.analyticsTimer = setInterval(() => this.refreshAnalytics(), 5000);
    }

    handleRefresh() {
        this.analyticsRefreshing = true;
        this.refreshAnalytics().finally(() => { this.analyticsRefreshing = false; });
    }

    async refreshAnalytics() {
        if (!this.activeCampaignId) return;
        try {
            const [camp, rcpts] = await Promise.all([
                getCampaign({ campaignId: this.activeCampaignId }),
                listCampaignRecipients({
                    campaignId: this.activeCampaignId,
                    statusFilter: this.recipientStatusFilter || null,
                    limitSize: 500
                })
            ]);
            if (camp) {
                this.activeCampaign = {
                    ...camp,
                    statusPillClass: this.statusPillClass(camp.status),
                    sentLabel: camp.sentDateTime ? this.formatDate(camp.sentDateTime) : '—',
                    deliveryLabel: `${camp.deliveryRate || 0}%`,
                    openLabel: `${camp.openRate || 0}%`,
                    bounceLabel: `${camp.bounceRate || 0}%`
                };
            }
            // Keep polling while the analytics view is open: opens and bounces
            // arrive AFTER the campaign reaches a terminal send status, so we must
            // not stop refreshing when it flips to Sent. The timer is cleared on
            // leaving the view / disconnect.
            this.recipients = (rcpts || []).map((r) => ({
                ...r,
                statusPillClass: this.statusPillClass(r.status),
                sentLabel: r.sentDateTime ? this.formatDate(r.sentDateTime) : '—',
                openedLabel: r.openedDateTime ? this.formatDate(r.openedDateTime) : '—'
            }));
        } catch (e) {
            // soft-fail; next tick retries
        }
    }

    handleStatusFilterChange(event) {
        this.recipientStatusFilter = event.detail.value;
        this.refreshAnalytics();
    }

    handleBackHome() {
        this.clearAnalyticsTimer();
        this.view = VIEW.HOME;
        this.activeCampaign = null;
        this.activeCampaignId = null;
        this.recipients = [];
        this.loadCampaigns();
    }

    clearAnalyticsTimer() {
        if (this.analyticsTimer) {
            clearInterval(this.analyticsTimer);
            this.analyticsTimer = null;
        }
    }

    // ----- Utilities ------------------------------------------------------
    resetForm() {
        this.form = {
            campaignId: null,
            name: '',
            subject: '',
            body: '',
            fromName: '',
            fromAddress: '',
            scheduledFor: ''
        };
        this.selectedSegmentationId = null;
        this.selectedSegmentationName = '';
        this.recipientPreview = null;
    }

    statusPillClass(status) {
        const base = 'pill ';
        switch (status) {
            case 'Sent':           return base + 'pillGreen';
            case 'Opened':         return base + 'pillBlue';
            case 'Delivered':      return base + 'pillGreen';
            case 'Sending':        return base + 'pillAmber';
            case 'Scheduled':      return base + 'pillAmber';
            case 'Queued':         return base + 'pillGrey';
            case 'Bounced':        return base + 'pillRed';
            case 'Failed':         return base + 'pillRed';
            case 'Partially Sent': return base + 'pillAmber';
            case 'Draft':          return base + 'pillGrey';
            default:               return base + 'pillGrey';
        }
    }

    formatDate(value) {
        if (!value) return '';
        try {
            const d = typeof value === 'string' ? new Date(value) : value;
            return d.toLocaleString();
        } catch (e) {
            return String(value);
        }
    }

    reduceError(err) {
        if (Array.isArray(err?.body)) return err.body.map((e) => e.message).join(', ');
        return err?.body?.message || err?.message || 'Unknown error';
    }

    toast(message, variant) {
        this.dispatchEvent(new CustomEvent('ken_toast', { bubbles: true, composed: true, detail: { message, variant } }));
        // also alert via simple console for now
        // eslint-disable-next-line no-console
        console.log(`[${variant || 'info'}] ${message}`);
    }
}