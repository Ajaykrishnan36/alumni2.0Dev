import { LightningElement, api, track } from 'lwc';
import getResponsesForRecord from '@salesforce/apex/KenModuleFeedbackController.getResponsesForRecord';
import getResponsesForTemplate from '@salesforce/apex/KenModuleFeedbackController.getResponsesForTemplate';

/**
 * kenFeedbackResponses — the single, view-only feedback viewer.
 *
 * Individual mode: place on any record page (recordId is auto-supplied). Shows
 * the responses for THAT record's per-record survey instance — so a mentorship
 * call shows only its mentor+mentee, while an event shows every attendee.
 *
 * Bulk mode: pass `template-id` to aggregate every response across all instances
 * of a template (e.g. all mentorship-call feedback).
 *
 * Fully generic — no module object is referenced anywhere.
 */
export default class KenFeedbackResponses extends LightningElement {
    @api title = 'Feedback Responses';
    @track respondents = [];
    @track total = 0;
    error;
    isLoading = false;
    _recordId;
    _templateId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.load();
    }

    @api
    get templateId() {
        return this._templateId;
    }
    set templateId(value) {
        this._templateId = value;
        this.load();
    }

    connectedCallback() {
        this.load();
    }

    load() {
        const useTemplate = !!this._templateId;
        const useRecord = !useTemplate && !!this._recordId;
        if (!useTemplate && !useRecord) {
            return;
        }
        this.isLoading = true;
        const promise = useTemplate
            ? getResponsesForTemplate({ templateId: this._templateId })
            : getResponsesForRecord({ recordId: this._recordId });
        promise
            .then((data) => {
                this.total = (data && data.total) || 0;
                this.respondents = ((data && data.respondents) || []).map((r, i) => ({
                    ...r,
                    key: r.respondentId || `anon-${i}`,
                    answers: (r.answers || []).map((a, ai) => ({ ...a, key: `${i}-${ai}` }))
                }));
                this.error = undefined;
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Unable to load feedback.';
                this.respondents = [];
                this.total = 0;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get hasResponses() {
        return this.total > 0;
    }

    // ---- CSV export (long format: one row per answer) ----
    handleDownloadCsv() {
        if (!this.hasResponses) {
            return;
        }
        const header = ['Respondent', 'Submitted', 'Question', 'Answer'];
        const rows = [header];
        this.respondents.forEach((r) => {
            const submitted = r.submittedDate
                ? new Date(r.submittedDate).toISOString().slice(0, 10)
                : '';
            (r.answers || []).forEach((a) => {
                rows.push([r.respondentName || 'Anonymous', submitted, a.question || '', a.answer || '']);
            });
        });
        const csv = rows.map((row) => row.map((c) => this.csvCell(c)).join(',')).join('\r\n');
        // Prepend BOM so Excel renders UTF-8 correctly.
        const dataUri = 'data:text/csv;charset=utf-8,%EF%BB%BF' + encodeURIComponent(csv);
        const a = document.createElement('a');
        a.href = dataUri;
        a.download = `${(this.title || 'feedback-responses').replace(/\s+/g, '_')}_${new Date()
            .toISOString()
            .slice(0, 10)}.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    csvCell(value) {
        const s = value == null ? '' : String(value);
        return '"' + s.replace(/"/g, '""') + '"';
    }
}