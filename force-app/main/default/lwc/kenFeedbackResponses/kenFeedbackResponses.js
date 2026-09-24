import { LightningElement, api, track } from 'lwc';
import getResponsesForRecord from '@salesforce/apex/KenModuleFeedbackController.getResponsesForRecord';
import getResponsesForTemplate from '@salesforce/apex/KenModuleFeedbackController.getResponsesForTemplate';
import getSurveyRecordView from '@salesforce/apex/KenSurveyController.getSurveyRecordView';
import getSurveyResponsesForExport from '@salesforce/apex/KenSurveyController.getSurveyResponsesForExport';
import getSubmissionsPage from '@salesforce/apex/KenSurveyController.getSubmissionsPage';
import exportNeedsBatch from '@salesforce/apex/KenSurveyController.exportNeedsBatch';
import requestFullExport from '@salesforce/apex/KenSurveyController.requestFullExport';
import { localDateKey } from 'c/kenDateTime';

const SURVEY_OBJECT = 'Ken_Survey__c';
const CHOICE_TYPES = ['Dropdown', 'Multiple Choice', 'Yes/No'];
const SCALE_TYPES = ['Linear Scale', 'Rating'];

/**
 * kenFeedbackResponses — the single feedback and survey viewer.
 *
 * Survey mode: on a Ken_Survey__c record page it shows the whole survey — status, counts,
 * every question with its choices or scale points, and the responses received.
 *
 * Individual mode: on any other record page it shows the responses for that record's own
 * survey instance, so a mentorship call shows only its mentor and mentee while an event
 * shows every attendee.
 *
 * Bulk mode: pass `template-id` to aggregate responses across every instance of a template.
 *
 * Outside survey mode no module object is referenced anywhere.
 */
export default class KenFeedbackResponses extends LightningElement {
    @api title = 'Feedback Responses';

    @track respondents = [];
    @track total = 0;
    error;
    isLoading = false;
    downloading = false;
    activeTab = 'questions';
    surveyView;
    loadedSubmissions = [];
    cursorDate = null;
    cursorId = null;
    hasMore = false;
    loadingMore = false;
    exportQueued = false;

    _recordId;
    _templateId;
    _objectApiName;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.load();
    }

    // The framework can set this after recordId, so it reloads rather than leaving the
    // component stuck in whichever mode it guessed first.
    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
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

    get isSurveyMode() {
        return this._objectApiName === SURVEY_OBJECT && !!this._recordId && !this._templateId;
    }

    load() {
        if (this.isSurveyMode) {
            this.loadSurvey();
            return;
        }
        this.loadResponses();
    }

    loadSurvey() {
        this.isLoading = true;
        this.loadedSubmissions = [];
        this.cursorDate = null;
        this.cursorId = null;
        this.hasMore = false;
        getSurveyRecordView({ recordId: this._recordId })
            .then((data) => {
                this.surveyView = data;
                this.loadedSubmissions = data?.submissions || [];
                const last = this.loadedSubmissions[this.loadedSubmissions.length - 1];
                this.cursorDate = last ? last.cursorDate : null;
                this.cursorId = last ? last.id : null;
                this.hasMore = (data?.totalSubmissions || 0) > this.loadedSubmissions.length;
                this.error = undefined;
            })
            .catch((e) => {
                this.error = e?.body?.message || 'Unable to load this survey.';
                this.surveyView = undefined;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    loadResponses() {
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

    // ---- survey mode ----

    get hasQuestions() {
        return (this.surveyView?.questions?.length || 0) > 0;
    }

    get hasSubmissions() {
        return (this.loadedSubmissions?.length || 0) > 0;
    }

    get loadMoreLabel() {
        const total = this.surveyView?.totalSubmissions || 0;
        return this.loadingMore
            ? 'Loading…'
            : `Load more (${this.loadedSubmissions.length} of ${total})`;
    }

    /** Pulls the next page using the cursor from the last row already on screen. */
    handleLoadMore() {
        if (this.loadingMore || !this.hasMore) {
            return;
        }
        this.loadingMore = true;
        getSubmissionsPage({
            surveyId: this._recordId,
            cursorDate: this.cursorDate,
            cursorId: this.cursorId
        })
            .then((page) => {
                const incoming = page?.submissions || [];
                this.loadedSubmissions = this.loadedSubmissions.concat(incoming);
                this.cursorDate = page?.nextCursorDate || this.cursorDate;
                this.cursorId = page?.nextCursorId || this.cursorId;
                const total = this.surveyView?.totalSubmissions || 0;
                this.hasMore = page?.hasMore && this.loadedSubmissions.length < total;
            })
            .catch((e) => {
                this.error = e?.body?.message || 'Could not load more responses.';
            })
            .finally(() => {
                this.loadingMore = false;
            });
    }

    get statusClass() {
        const status = this.surveyView?.approvalStatus;
        if (status === 'Approved') {
            return 'ken-pill ken-pill_success';
        }
        if (status === 'Rejected') {
            return 'ken-pill ken-pill_error';
        }
        return 'ken-pill ken-pill_pending';
    }

    get activeClass() {
        return this.surveyView?.isActive ? 'ken-pill ken-pill_success' : 'ken-pill ken-pill_muted';
    }

    get activeLabel() {
        return this.surveyView?.isActive ? 'Active' : 'Inactive';
    }

    get windowLabel() {
        const start = this.formatDate(this.surveyView?.startDate);
        const end = this.formatDate(this.surveyView?.endDate);
        if (!start && !end) {
            return 'Not scheduled';
        }
        return `${start || '—'} → ${end || '—'}`;
    }

    get audienceList() {
        const raw = this.surveyView?.targetAudience;
        return raw ? raw.split(';').filter(Boolean) : [];
    }

    get hasAudience() {
        return this.audienceList.length > 0;
    }

    get requiredCount() {
        return (this.surveyView?.questions || []).filter((q) => q.required).length;
    }

    get questionsView() {
        return (this.surveyView?.questions || []).map((q, index) => {
            const choices = q.options || [];
            const isScale = SCALE_TYPES.includes(q.questionType);
            const isChoice = CHOICE_TYPES.includes(q.questionType);
            return {
                key: q.id,
                number: index + 1,
                label: q.questionLabel,
                type: q.questionType || 'Short Answer',
                required: q.required,
                isScale,
                isChoice,
                isFreeText: !isScale && !isChoice,
                choices: choices.map((c) => ({
                    key: `${q.id}-${c.value}`,
                    value: c.value,
                    label: c.text && c.text !== c.value ? c.text : '',
                    hasLabel: !!(c.text && c.text !== c.value)
                }))
            };
        });
    }

    get submissionsView() {
        return (this.loadedSubmissions || []).map((s) => ({
            key: s.id,
            respondentName: s.respondentName,
            initials: this.initialsFor(s.respondentName),
            submittedDate: this.formatDate(s.submittedDate),
            answers: (s.answers || []).map((a, idx) => ({
                key: `${s.id}-${idx}`,
                question: a.question,
                answer: a.answer || '—'
            }))
        }));
    }

    get questionsTabClass() {
        return this.activeTab === 'questions' ? 'ken-tab ken-tab_active' : 'ken-tab';
    }

    get responsesTabClass() {
        return this.activeTab === 'responses' ? 'ken-tab ken-tab_active' : 'ken-tab';
    }

    get showQuestions() {
        return this.activeTab === 'questions';
    }

    get showResponses() {
        return this.activeTab === 'responses';
    }

    get downloadDisabled() {
        return this.downloading || !this.hasSubmissions;
    }

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    /**
     * Survey mode exports one row per submission with a column per question, which is the
     * shape people pivot in a spreadsheet. Responses mode keeps its one-row-per-answer export.
     */
    async handleDownloadSurveyCsv() {
        this.downloading = true;
        this.error = undefined;
        this.exportQueued = false;
        try {
            // Past the row ceiling the browser export cannot be complete, so the file is built
            // in the background and attached to the record instead of silently truncating.
            const needsBatch = await exportNeedsBatch({ surveyId: this._recordId });
            if (needsBatch) {
                await requestFullExport({ surveyId: this._recordId });
                this.exportQueued = true;
                return;
            }

            const result = await getSurveyResponsesForExport({ surveyId: this._recordId });
            // Responses can still arrive between the check above and this read. The server
            // flags a capped read, and a capped file must never be handed over as complete.
            if (result?.truncated) {
                await requestFullExport({ surveyId: this._recordId });
                this.exportQueued = true;
                return;
            }
            const questions = result?.questions || [];
            const rows = result?.rows || [];
            if (!rows.length) {
                this.error = 'No answers have been submitted yet, so there is nothing to export.';
                return;
            }
            const header = ['Respondent', 'Submitted'].concat(questions.map((q) => q.label || 'Question'));
            const lines = [header.map((c) => this.csvCell(c)).join(',')];
            rows.forEach((row) => {
                const answers = row.answersByQuestionId || {};
                const line = [row.respondentName || 'Anonymous', this.formatDate(row.submittedAt)]
                    .concat(questions.map((q) => answers[q.id] || ''));
                lines.push(line.map((c) => this.csvCell(c)).join(','));
            });
            this.downloadCsv(lines.join('\r\n'), `${this.safeFileName(result.surveyName)}-responses.csv`);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('survey CSV export failed', e);
            const detail = this.exportErrorDetail(e);
            this.error = detail
                ? 'Could not build the CSV: ' + detail
                : 'Could not build the CSV.';
        } finally {
            this.downloading = false;
        }
    }

    handleDownloadCsv() {
        if (!this.hasResponses) {
            return;
        }
        const header = ['Respondent', 'Submitted', 'Question', 'Answer'];
        const rows = [header];
        this.respondents.forEach((r) => {
            const submitted = r.submittedDate ? localDateKey(new Date(r.submittedDate)) : '';
            (r.answers || []).forEach((a) => {
                rows.push([r.respondentName || 'Anonymous', submitted, a.question || '', a.answer || '']);
            });
        });
        const csv = rows.map((row) => row.map((c) => this.csvCell(c)).join(',')).join('\r\n');
        this.downloadCsv(
            csv,
            `${(this.title || 'feedback-responses').replace(/\s+/g, '_')}_${new Date().toISOString().slice(0, 10)}.csv`
        );
    }

    /**
     * Lightning Web Security only lets URL.createObjectURL accept a restricted set of MIME
     * types and rejects text/csv outright, so the permitted types are tried in turn and a
     * data URI is the last resort. The .csv extension on the download attribute is what makes
     * Excel open it, not the MIME type; the leading byte order mark is what makes Excel read
     * it as UTF-8. encodeURIComponent throws URIError on a lone surrogate -- which a free-text
     * answer can carry -- so the data URI must never be the only path.
     */
    downloadCsv(csv, fileName) {
        const text = '\uFEFF' + csv;
        const types = ['text/plain;charset=utf-8', 'application/octet-stream', 'text/csv;charset=utf-8'];
        const refused = [];
        for (const type of types) {
            try {
                const url = URL.createObjectURL(new Blob([text], { type }));
                this.clickDownload(url, fileName);
                window.setTimeout(() => URL.revokeObjectURL(url), 30000);
                return;
            } catch (e) {
                refused.push(type + ' (' + this.describeError(e) + ')');
            }
        }
        try {
            this.clickDownload('data:text/csv;charset=utf-8,' + encodeURIComponent(text), fileName);
        } catch (e) {
            refused.push('data URI (' + this.describeError(e) + ')');
            throw new Error('the browser refused every download route: ' + refused.join('; '));
        }
    }

    /**
     * The anchor is declared in the template instead of being appended to document.body.
     * Under Lightning Web Security an element appended to the sandboxed document never
     * reaches the real DOM, so that click did nothing and raised nothing -- the file simply
     * never arrived. An anchor inside this component's shadow root is a real, live element.
     */
    clickDownload(url, fileName) {
        const sink = this.template.querySelector('a[data-id="download"]');
        if (!sink) {
            throw new Error('the download link is not rendered');
        }
        sink.href = url;
        sink.download = fileName;
        sink.click();
    }

    describeError(e) {
        if (!e) {
            return 'no detail';
        }
        if (e.name) {
            return e.message ? e.name + ': ' + e.message : e.name;
        }
        return e.message || String(e);
    }

    /**
     * LWC hands a failure back in several shapes: an Apex exception as body.message, a record
     * error as an array of bodies or as pageErrors, and a browser failure with only message.
     * Reading body.message alone turned every non-Apex failure into a blank message.
     */
    exportErrorDetail(e) {
        const body = e && e.body;
        if (Array.isArray(body)) {
            const joined = body.map((b) => b && b.message).filter(Boolean).join(', ');
            if (joined) {
                return joined;
            }
        }
        if (body && body.message) {
            return body.message;
        }
        if (body && body.pageErrors && body.pageErrors.length) {
            return body.pageErrors.map((p) => p.message).join(', ');
        }
        if (body && body.output && body.output.errors && body.output.errors.length) {
            return body.output.errors.map((x) => x.message).join(', ');
        }
        if (e && e.message) {
            return e.message;
        }
        return typeof e === 'string' ? e : this.describeError(e);
    }

    csvCell(value) {
        const s = value == null ? '' : String(value);
        return '"' + s.replace(/"/g, '""') + '"';
    }

    safeFileName(name) {
        return String(name || 'survey')
            .replace(/[^a-z0-9]+/gi, '-')
            .replace(/^-+|-+$/g, '')
            .toLowerCase();
    }

    initialsFor(name) {
        if (!name) {
            return '?';
        }
        return name
            .split(/\s+/)
            .filter(Boolean)
            .slice(0, 2)
            .map((part) => part[0].toUpperCase())
            .join('');
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        return new Date(value).toLocaleDateString(undefined, {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    }
}