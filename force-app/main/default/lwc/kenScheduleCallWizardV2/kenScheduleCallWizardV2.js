// V2 wiring — calls OLD KenMentorshipController.getMentorAvailabilityDays imperatively.
// Mock days stay as fallback when mentor.id isn't a real Salesforce Id or the call errors.
import { LightningElement, api, track } from 'lwc';
import getMentorAvailabilityDays from '@salesforce/apex/KenMentorshipController.getMentorAvailabilityDays';
import getMentorshipDashboardData from '@salesforce/apex/KenMentorshipController.getMentorshipDashboardData';

const SF_ID_RE = /^[a-zA-Z0-9]{15,18}$/;

const STEPS = [
    { id: 1, label: 'Slot' },
    { id: 2, label: 'Topic' },
    { id: 3, label: 'Confirm' }
];

export default class KenScheduleCallWizardV2 extends LightningElement {
    @api mentor;

    @track availability = null; // populated from OLD method when mentor has a SF Id
    @track availabilityLoaded = false;
    @track hasAvailability = false;

    // ---- Mentor-picker (when the wizard is opened without a pre-selected mentor) ----
    @track pickerMode = false;
    @track pickerLoading = false;
    @track pickerError = '';
    @track availableMentors = [];
    @track pickedMentorId = null;

    connectedCallback() {
        const id = this.mentor && this.mentor.id;
        if (typeof id === 'string' && SF_ID_RE.test(id)) {
            this._loadAvailability(id);
        } else {
            // No real SF mentor id — open the picker first so the dispatched
            // 'confirm' event always carries a real mentorId (fixing the
            // generic "Schedule a Call" dead-end where Apex got mentorId=null).
            this.pickerMode = true;
            this._loadAvailableMentors();
        }
    }

    _loadAvailability(id) {
        getMentorAvailabilityDays({ mentorId: id })
            .then(res => {
                // Apex returns: { availabilityDays:'Monday;Wednesday;Friday',
                //   availabilityStartTime:'10:00', availabilityEndTime:'13:00' }
                this.availability = (res && typeof res === 'object') ? res : null;
                this._applyAvailabilityDefaults(this.availability);
                this.availabilityLoaded = true;
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.getMentorAvailabilityDays error', err);
                this.availabilityLoaded = true;
            });
    }

    _loadAvailableMentors() {
        this.pickerLoading = true;
        getMentorshipDashboardData()
            .then(res => {
                const conns = (res && res.connections) || [];
                // Counterparty must be a real Salesforce Id and a MENTOR to the running user
                // (i.e. the running user is NOT the mentor in that pairing).
                this.availableMentors = conns
                    .filter(c => c && c.id && SF_ID_RE.test(String(c.id)) && c.currentUserIsMentor !== true)
                    .map(c => ({
                        id: c.id,
                        name: c.name || 'Mentor',
                        roleLine: c.roleCompany || c.role || '',
                        color: c.color || '#4f46e5',
                        initial: ((c.name || '?').trim().charAt(0) || '?').toUpperCase()
                    }));
                this.pickerLoading = false;
            })
            .catch(err => {
                this.pickerLoading = false;
                this.pickerError = (err && err.body && err.body.message) || 'Could not load your mentors.';
            });
    }

    get hasPickerMentors() { return this.availableMentors && this.availableMentors.length > 0; }
    get pickerEmpty() { return !this.pickerLoading && !this.hasPickerMentors && !this.pickerError; }
    get pickContinueDisabled() { return !this.pickedMentorId; }
    get pickerRows() {
        return this.availableMentors.map(m => ({
            ...m,
            avStyle: 'background:' + m.color,
            rowCls: 'pick-row' + (m.id === this.pickedMentorId ? ' pick-row--on' : '')
        }));
    }

    handlePickMentor(event) {
        this.pickedMentorId = event.currentTarget.dataset.id;
    }
    handlePickContinue() {
        const m = this.availableMentors.find(x => x.id === this.pickedMentorId);
        if (!m) return;
        this.mentor = { id: m.id, name: m.name, role: m.roleLine, color: m.color };
        this.pickerMode = false;
        this._loadAvailability(m.id);
    }

    // Materialize the MentorAvailability response into an initial date + time slot.
    // Picks the next upcoming weekday that matches one of the mentor's availability days,
    // then picks an hourly slot inside the [start, end) window.
    _applyAvailabilityDefaults(data) {
        if (!data || !data.availabilityDays) { this.hasAvailability = false; return; }

        const dayTokens = String(data.availabilityDays)
            .split(';')
            .map(s => s.trim())
            .filter(Boolean);
        if (!dayTokens.length) { this.hasAvailability = false; return; }

        const WEEK = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const dayIndexes = new Set(
            dayTokens.map(d => WEEK.indexOf(d)).filter(i => i >= 0)
        );
        if (!dayIndexes.size) { this.hasAvailability = false; return; }

        // Look forward up to 14 days for the next matching weekday.
        const today = new Date();
        let chosen = null;
        for (let offset = 0; offset < 14; offset++) {
            const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset);
            if (dayIndexes.has(d.getDay())) { chosen = d; break; }
        }
        if (!chosen) { this.hasAvailability = false; return; }

        // Store ISO yyyy-MM-dd so the native date picker + Apex parseDateValue agree.
        const mmDate = String(chosen.getMonth() + 1).padStart(2, '0');
        const ddDate = String(chosen.getDate()).padStart(2, '0');
        this.selectedDate = `${chosen.getFullYear()}-${mmDate}-${ddDate}`;

        // Pick first hourly slot inside the [start, end) window.
        this.selectedSlot = this._firstSlotInWindow(data.availabilityStartTime, data.availabilityEndTime);
        this.hasAvailability = !!(this.selectedDate || this.selectedSlot);
    }

    // Return a "hh:mm AM/PM" label for the first hour at or after startHHmm and strictly before endHHmm.
    _firstSlotInWindow(startHHmm, endHHmm) {
        const parse = (t) => {
            if (!t || typeof t !== 'string') return null;
            const m = t.match(/^(\d{1,2}):(\d{2})/);
            if (!m) return null;
            return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
        };
        const startMin = parse(startHHmm);
        const endMin = parse(endHHmm);
        if (startMin == null || endMin == null || endMin <= startMin) return '';

        // Round up to the next half hour to keep within hardcoded slot grid.
        let mins = startMin;
        if (mins % 30 !== 0) mins = mins + (30 - (mins % 30));
        if (mins >= endMin) return '';

        const h24 = Math.floor(mins / 60);
        const mm = mins % 60;
        const ampm = h24 >= 12 ? 'PM' : 'AM';
        const h12 = h24 === 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
        const hh = String(h12).padStart(2, '0');
        const mmStr = String(mm).padStart(2, '0');
        return `${hh}:${mmStr} ${ampm}`;
    }

    get showNoAvailability() {
        return this.availabilityLoaded && !this.hasAvailability && !this.selectedDate && !this.selectedSlot;
    }

    @track currentStep = 1;
    @track selectedSlot = '';
    @track selectedDuration = '30 min';
    @track selectedDate = '';
    @track topic = '';
    @track agenda = "I'd love to get your feedback on my portfolio and discuss the transition from individual contributor to design manager.";

    get steps() { return STEPS; }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get backDisabled() { return this.pickerMode || this.currentStep === 1; }
    get nextDisabled() { return this.pickerMode && this.pickContinueDisabled; }
    get nextLabel() {
        if (this.pickerMode) return 'Continue';
        if (this.currentStep === 3) return 'Send Request';
        return 'Continue';
    }

    get mentorName() { return (this.mentor && this.mentor.name) || 'Mentor'; }
    get mentorInitial() {
        const n = (this.mentor && this.mentor.name) || '';
        return n ? n.charAt(0).toUpperCase() : '?';
    }
    get mentorAvStyle() {
        // Deterministic color from name; falls back to neutral grey
        const c = (this.mentor && this.mentor.color) || '#94A3B8';
        return `background:${c}`;
    }
    get mentorRoleLine() {
        if (!this.mentor) return '';
        const r = this.mentor.role || this.mentor.title || '';
        const c = this.mentor.company || '';
        if (r && c) return `${r} · ${c}`;
        return r || c || '';
    }

    handleValueChange(event) {
        const { field, value } = event.detail || {};
        if (!field) return;
        this[field] = value;
    }

    handleBack() {
        if (this.pickerMode) return;
        if (this.currentStep > 1) this.currentStep -= 1;
    }
    handleNext() {
        // In picker mode, Continue confirms the mentor pick and unlocks the rest of the wizard.
        if (this.pickerMode) { this.handlePickContinue(); return; }
        if (this.currentStep < 3) {
            this.currentStep += 1;
        } else {
            this.handleConfirm();
        }
    }

    // Convert a display slot ("10:00 AM") to 24h "HH:mm" that Apex parseTimeValue accepts.
    _slotTo24h(slot) {
        if (!slot) return '';
        const m = String(slot).trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i);
        if (!m) return '';
        let h = parseInt(m[1], 10);
        const min = m[2];
        const ap = (m[3] || '').toUpperCase();
        if (ap === 'PM' && h < 12) h += 12;
        if (ap === 'AM' && h === 12) h = 0;
        return `${String(h).padStart(2, '0')}:${min}`;
    }
    _addMinutes(hhmm, mins) {
        const m = /^(\d{2}):(\d{2})$/.exec(hhmm);
        if (!m) return '';
        let total = parseInt(m[1], 10) * 60 + parseInt(m[2], 10) + (mins || 0);
        total = ((total % 1440) + 1440) % 1440;
        const h = Math.floor(total / 60);
        const mm = total % 60;
        return `${String(h).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    }

    handleConfirm() {
        const start24 = this._slotTo24h(this.selectedSlot);
        const durMins = parseInt(this.selectedDuration, 10) || 30;
        const end24 = start24 ? this._addMinutes(start24, durMins) : '';
        this.dispatchEvent(new CustomEvent('confirm', {
            detail: {
                mentorId: (this.mentor && this.mentor.id) || null,
                slot: this.selectedSlot,
                duration: this.selectedDuration,
                date: this.selectedDate,
                // Machine-readable fields the dashboard forwards straight to Apex.
                meetingDate: this.selectedDate,
                startTime: start24,
                endTime: end24,
                topic: this.topic,
                agenda: this.agenda
            }
        }));
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('overlay')) {
            this.handleClose();
        }
    }
    handleStop(event) { event.stopPropagation(); }
}