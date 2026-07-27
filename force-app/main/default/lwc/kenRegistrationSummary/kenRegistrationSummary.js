import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import basePath from '@salesforce/community/basePath';
import getRegistrationSummary from '@salesforce/apex/KenPortalEventController.getRegistrationSummary';
import cancelRegistrations from '@salesforce/apex/KenPortalEventController.cancelRegistrations';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenRegistrationSummary extends NavigationMixin(LightningElement) {
    _recordId;
    @api get recordId() { return this._recordId; }
    set recordId(val) { this._recordId = val; }

    @track summary;
    wiredSummaryResult;

    @track showCancelConfirm = false;
    @track showCancelSelect = false;
    @track cancelAll = false;
    @track selectedCancelIds = new Set();
    @track _refreshTick = 0;

    @wire(CurrentPageReference)
    setPageRef(ref) {
        if (ref && ref.state && ref.state.recordId) {
            this._recordId = ref.state.recordId;
        }
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
        // Re-render when returning from the survey form so a just-submitted
        // participant's "Fill" flips to "Submitted".
        this._boundRefresh = () => { this._refreshTick++; };
        window.addEventListener('focus', this._boundRefresh);
        window.addEventListener('pageshow', this._boundRefresh);
    }

    disconnectedCallback() {
        if (this._boundRefresh) {
            window.removeEventListener('focus', this._boundRefresh);
            window.removeEventListener('pageshow', this._boundRefresh);
        }
    }

    _isSurveySubmitted(participantId) {
        try {
            const arr = JSON.parse(sessionStorage.getItem('kenFbSubmitted:' + this._recordId) || '[]');
            return arr.includes(participantId) || arr.includes('__self__');
        } catch (e) {
            return false;
        }
    }

    handleFillSurvey(event) {
        const participantId = event.currentTarget.dataset.id;
        // Open the survey form against the event; resolves the event's Survey__c.
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'survey_form__c' },
            state: { recId: this._recordId, participantId }
        });
    }

    @wire(getRegistrationSummary, { eventId: '$_recordId' })
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            this.summary = result.data;
        }
    }

    // ---- Header getters ----
    get eventName() { return this.summary?.eventName || ''; }
    get hasSummary() { return !!this.summary; }

    get dateRange() {
        if (!this.summary?.startDate) return '';
        return this._formatRange(this.summary.startDate, this.summary.endDate);
    }

    get locationType() { return this.summary?.location || ''; }

    get formattedLanguage() {
        const lang = this.summary?.language;
        if (!lang) return '';
        return lang.split(';').map(l => l.trim()).filter(Boolean).join(', ');
    }

    // ---- Participants ----
    get participants() {
        return (this.summary?.participants || []).map(p => ({
            ...p,
            typeClass: p.type === 'Myself' ? 'type-badge type-myself' : 'type-badge type-guest',
            dietaryLabel: p.dietaryPref || '-',
            contactLines: [p.email, p.phone].filter(Boolean),
            surveySubmitted: this._isSurveySubmitted(p.id)
        }));
    }
    get hasParticipants() { return (this.summary?.participants || []).length > 0; }
    get participantCount() { return (this.summary?.participants || []).length; }

    // ---- Sessions grouped by date ----
    get sessionsByDate() {
        const sessions = this.summary?.sessions || [];
        const map = new Map();
        sessions.forEach(s => {
            const key = s.sessionDate || 'Unknown';
            if (!map.has(key)) {
                map.set(key, { dateKey: key, displayDate: this._formatDate(s.sessionDate), sessions: [] });
            }
            map.get(key).sessions.push({
                id: s.id,
                name: s.name,
                timeLabel: `${this._msToTime(s.startTime)} - ${this._msToTime(s.endTime)}`,
                priceLabel: s.price ? `₹${Number(s.price).toLocaleString('en-IN')}` : 'Free'
            });
        });
        return [...map.values()];
    }
    get hasSessions() { return (this.summary?.sessions || []).length > 0; }

    // ---- Payment summary (data-driven) ----
    get sessionCount() { return (this.summary?.sessions || []).length; }
    get perSessionPrice() {
        const sessions = this.summary?.sessions || [];
        if (!sessions.length) return 0;
        const total = sessions.reduce((sum, s) => sum + (Number(s.price) || 0), 0);
        return Math.round(total / sessions.length);
    }
    get sessionSubtotal() {
        const sessions = this.summary?.sessions || [];
        return sessions.reduce((sum, s) => sum + (Number(s.price) || 0), 0);
    }
    get sessionSubtotalLabel() { return this.sessionSubtotal.toLocaleString('en-IN'); }
    get perSessionLabel() { return this.perSessionPrice.toLocaleString('en-IN'); }
    get totalPayable() { return this.sessionSubtotal * Math.max(1, this.participantCount); }
    get totalPayableLabel() { return this.totalPayable.toLocaleString('en-IN'); }

    // ---- Cancellation window (closes 72 hours before the event starts) ----
    static CANCEL_WINDOW_MS = 72 * 60 * 60 * 1000;

    // Event start in epoch ms = event start date + earliest session start time.
    get eventStartMs() {
        const base = this._toDate(this.summary?.startDate);
        if (!base) return null;
        let minStart = null;
        (this.summary?.sessions || []).forEach(s => {
            // startTime arrives as milliseconds-from-midnight
            if (s.startTime != null && (minStart == null || s.startTime < minStart)) {
                minStart = s.startTime;
            }
        });
        return base.getTime() + (minStart || 0);
    }

    get cancellationClosed() {
        const start = this.eventStartMs;
        if (start == null) return false;
        return (start - Date.now()) < KenRegistrationSummary.CANCEL_WINDOW_MS;
    }

    // Show the cancel button only when there is something to cancel and the window is still open.
    get showCancelButton() {
        return this.hasSessions && !this.cancellationClosed;
    }

    // ---- Cancel flow ----
    handleCancelRegistration() {
        if (this.cancellationClosed) return;
        this.showCancelConfirm = true;
    }
    handleConfirmNo() { this.showCancelConfirm = false; }
    handleConfirmYes() {
        this.showCancelConfirm = false;
        this.selectedCancelIds = new Set();
        this.cancelAll = false;
        this.showCancelSelect = true;
    }
    handleCloseCancelSelect() { this.showCancelSelect = false; }

    get cancelSessionGroups() {
        return this.sessionsByDate.map((dg, idx) => ({
            dateKey: dg.dateKey,
            dayLabel: `Day ${idx + 1} | ${dg.displayDate}`,
            sessions: dg.sessions.map(s => ({
                ...s,
                checked: this.cancelAll || this.selectedCancelIds.has(s.id)
            }))
        }));
    }

    handleToggleCancelAll(e) {
        this.cancelAll = e.target.checked;
        if (this.cancelAll) {
            const all = new Set();
            (this.summary?.sessions || []).forEach(s => all.add(s.id));
            this.selectedCancelIds = all;
        } else {
            this.selectedCancelIds = new Set();
        }
    }

    handleToggleCancelSession(e) {
        const id = e.target.dataset.id;
        const set = new Set(this.selectedCancelIds);
        if (e.target.checked) set.add(id); else { set.delete(id); this.cancelAll = false; }
        this.selectedCancelIds = set;
    }

    get canCancelNow() { return this.selectedCancelIds.size > 0; }

    handleCancelNow() {
        if (this.selectedCancelIds.size === 0) {
            this._toast('Info', 'Please select at least one session to cancel.', 'info');
            return;
        }
        cancelRegistrations({ sessionIds: [...this.selectedCancelIds] })
            .then(() => {
                this.showCancelSelect = false;
                this._toast('Success', 'Registration cancelled.', 'success');
                return refreshApex(this.wiredSummaryResult);
            })
            .catch(err => {
                this._toast('Error', err?.body?.message || 'Cancellation failed.', 'error');
            });
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'registered_events__c' }
        });
    }

    // ---- helpers ----
    _formatRange(start, end) {
        const s = this._toDate(start);
        const e = end ? this._toDate(end) : s;
        if (!s) return '';
        const sd = s.getDate();
        const ed = e.getDate();
        const month = e.toLocaleString('default', { month: 'short' });
        const year = e.getFullYear();
        if (s.getTime() === e.getTime()) return `${sd} ${month} ${year}`;
        if (s.getMonth() === e.getMonth() && s.getFullYear() === e.getFullYear()) {
            return `${sd}–${ed} ${month} ${year}`;
        }
        return `${sd} ${s.toLocaleString('default', { month: 'short' })} ${s.getFullYear()} - ${ed} ${month} ${year}`;
    }
    _formatDate(dateStr) {
        const d = this._toDate(dateStr);
        if (!d) return '';
        return `${d.getDate()} ${d.toLocaleString('default', { month: 'short' })} ${d.getFullYear()}`;
    }
    _toDate(val) {
        if (!val) return null;
        if (val instanceof Date) return val;
        const [y, m, d] = String(val).split('-');
        if (y && m && d) return new Date(Number(y), Number(m) - 1, Number(d));
        return new Date(val);
    }
    _msToTime(ms) {
        if (ms == null) return '';
        const totalMinutes = Math.floor(ms / 60000);
        let hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        const ampm = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12 || 12;
        return `${hours}:${minutes.toString().padStart(2, '0')} ${ampm}`;
    }
    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}