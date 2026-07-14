import { LightningElement, api, track } from 'lwc';
import getApplicationSteps from '@salesforce/apex/KenJobTrackerController.getApplicationSteps';

const WINDOW_BEFORE_MS = 15 * 60 * 1000; // join opens 15 min before start

export default class KenJobApplicationTrackerV2 extends LightningElement {
    @api applicationId;

    @track steps = [];
    @track errorMsg = '';
    loading = true;

    skewMs = 0;             // serverNowEpoch - browserNow captured at load
    nowEpoch = Date.now();  // server-aligned "now", ticked every second
    _timer;

    connectedCallback() {
        if (this.applicationId) {
            this.load();
        } else {
            this.loading = false;
            this.errorMsg = 'No application specified.';
        }
    }
    disconnectedCallback() { this._clearTimer(); }

    load() {
        getApplicationSteps({ applicationId: this.applicationId })
            .then(res => {
                // Neutralise browser clock skew: align to the server epoch immediately.
                this.skewMs = Number(res.serverNowEpoch) - Date.now();
                this.steps = res.steps || [];
                this.loading = false;
                this._tick();
                this._startTimer();
            })
            .catch(e => {
                this.loading = false;
                this.errorMsg = (e && e.body && e.body.message) || 'Could not load the tracker.';
            });
    }

    _startTimer() {
        this._clearTimer();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setInterval(() => this._tick(), 1000);
    }
    _clearTimer() { if (this._timer) { clearInterval(this._timer); this._timer = undefined; } }
    _tick() { this.nowEpoch = Date.now() + this.skewMs; }

    get hasSteps() { return this.steps && this.steps.length > 0; }

    get displaySteps() {
        return this.steps.map((s, i) => ({
            ...s,
            num: i + 1,
            cssClass: 'stp stp--' + (s.state || 'upcoming'),
            connClass: 'conn conn--' + (s.state || 'upcoming')
        }));
    }

    get activeStep() {
        return this.steps.find(s => s.state === 'active') || null;
    }
    get hasActive() { return !!this.activeStep; }
    get activeLabel() { return this.activeStep ? this.activeStep.label : ''; }

    get isOnlineMeeting() {
        const a = this.activeStep;
        return !!(a && a.locationMode === 'Online' && a.meetingLink);
    }
    get meetingLink() { return this.activeStep ? this.activeStep.meetingLink : ''; }

    get joinOpensEpoch() {
        const a = this.activeStep;
        return a && a.scheduledStartEpoch ? Number(a.scheduledStartEpoch) - WINDOW_BEFORE_MS : null;
    }
    get joinClosesEpoch() {
        const a = this.activeStep;
        return a && a.scheduledEndEpoch ? Number(a.scheduledEndEpoch) : null;
    }

    get joinDisabled() {
        if (!this.isOnlineMeeting) return true;
        const open = this.joinOpensEpoch;
        const close = this.joinClosesEpoch;
        if (open === null) return true;
        if (this.nowEpoch < open) return true;       // too early
        if (close !== null && this.nowEpoch > close) return true; // ended
        return false;
    }

    get windowLabel() {
        if (!this.isOnlineMeeting) return '';
        const open = this.joinOpensEpoch;
        const close = this.joinClosesEpoch;
        if (open !== null && this.nowEpoch < open) {
            return 'Opens in ' + this._fmt(open - this.nowEpoch);
        }
        if (close !== null && this.nowEpoch > close) return 'Meeting ended';
        return 'You can join now';
    }

    _fmt(ms) {
        const total = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        const pad = n => (n < 10 ? '0' + n : '' + n);
        return (h > 0 ? h + ':' : '') + pad(m) + ':' + pad(s);
    }

    handleJoin() {
        if (this.joinDisabled) return;
        window.open(this.meetingLink, '_blank');
    }
}