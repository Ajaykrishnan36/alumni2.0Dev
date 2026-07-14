import { LightningElement, api } from 'lwc';

export default class KenEventStepSummaryV2 extends LightningElement {
    // Full wizard formData snapshot from the parent (kenEventHostWizardV2).
    @api formData = {};

    // Jump back to a section to edit it (handled by the wizard parent).
    handleEdit(event) {
        const step = Number(event.currentTarget.dataset.step);
        if (step >= 1) this.dispatchEvent(new CustomEvent('gotostep', { detail: { step } }));
    }

    _v(key, fallback) {
        const v = this.formData ? this.formData[key] : undefined;
        return (v === undefined || v === null || v === '') ? (fallback || '—') : v;
    }

    // ----- Event Setup -----
    get eventTitle() { return this._v('eventTitle'); }
    get category()   { return this._v('category'); }
    get eventType()  { return this._v('eventType'); }
    get language()   { return this._v('language'); }
    get hostType()   { return this._v('hostType'); }
    get venueLabel() { return (this.formData && this.formData.hostType === 'Online') ? 'Meeting Link' : 'Location'; }
    get venueOrLink() {
        const f = this.formData || {};
        if ((f.hostType || '') === 'Online') return f.meetingLink || '—';
        return f.location || '—';
    }

    // ----- Schedule -----
    get scheduleText() {
        const f = this.formData || {};
        if (!f.startDate && !f.endDate) return 'Not scheduled';
        const range = (f.startDate === f.endDate || !f.endDate) ? f.startDate : `${f.startDate} – ${f.endDate}`;
        const time = (f.startTime || f.endTime) ? ` · ${f.startTime || ''}${f.endTime ? ' – ' + f.endTime : ''}` : '';
        return `${range}${time}`;
    }
    get multiDayText() { return (this.formData && this.formData.multiDay) ? 'Yes' : 'No'; }

    // Per-day speakers (multi-day events only).
    get hasDaySchedules() {
        const ds = (this.formData && this.formData.daySchedules) || [];
        return this.formData && this.formData.multiDay &&
               ds.some(d => Array.isArray(d.speakers) && d.speakers.length);
    }
    get daySchedulesView() {
        const ds = (this.formData && this.formData.daySchedules) || [];
        return ds
            .filter(d => Array.isArray(d.speakers) && d.speakers.length)
            .map((d, i) => ({
                key: d.date || `day-${i}`,
                label: `Day ${i + 1} · ${d.date}`,
                speakers: (d.speakers || []).join(', ')
            }));
    }

    // ----- Pre-Event Surveys -----
    get surveyText() {
        const f = this.formData || {};
        const parts = [];
        if (f.surveyMeals) parts.push('Meal preferences');
        if (f.surveyCustom) parts.push('Custom questions');
        return parts.length ? parts.join(', ') : 'None configured';
    }

    // ----- Fee -----
    get feeText() {
        const f = this.formData || {};
        if ((f.feeType || 'Free') === 'Free') return 'Free';
        const amt = f.baseFee ? `${f.currency || ''} ${f.baseFee}` : (f.feeType || 'Paid');
        return amt.trim();
    }

    // ----- Feedback Form -----
    get feedbackText() {
        const fb = (this.formData && this.formData.feedbackForm) || null;
        if (!fb || fb.enabled === false) return 'Disabled';
        const count = Array.isArray(fb.questions) ? fb.questions.length : 0;
        return `Enabled · ${count} question${count === 1 ? '' : 's'}`;
    }

    // ----- Target Audience -----
    get audienceText() {
        const a = (this.formData && this.formData.audienceDetail) || null;
        if (!a) return 'All alumni';
        const bits = [];
        if (Array.isArray(a.roles) && a.roles.length) bits.push(`${a.roles.length} role(s)`);
        if (Array.isArray(a.groupIds) && a.groupIds.length) bits.push(`${a.groupIds.length} group(s)`);
        if (Array.isArray(a.individualIds) && a.individualIds.length) bits.push(`${a.individualIds.length} individual(s)`);
        if (Array.isArray(a.csvEmails) && a.csvEmails.length) bits.push(`${a.csvEmails.length} CSV recipient(s)`);
        return bits.length ? bits.join(', ') : 'All alumni';
    }
}