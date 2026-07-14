import { LightningElement, api, wire, track } from 'lwc';
import getCaseQuestionnaireResponses from '@salesforce/apex/KenServiceSupportController.getCaseQuestionnaireResponses';

export default class KenCaseQuestionnaireResponses extends LightningElement {
    @api recordId;
    @track _responses = [];
    @track isLoading = true;
    @track isCollapsed = false;

    @wire(getCaseQuestionnaireResponses, { caseId: '$recordId' })
    wiredResponses({ data, error }) {
        this.isLoading = false;
        if (data) {
            this._responses = data.map((r, idx) => {
                const isFile = r.questionType && r.questionType.toLowerCase() === 'file upload';
                const rawResponse = r.response && r.response.trim() ? r.response : null;
                const fileName = isFile && rawResponse
                    ? rawResponse.replace(/^Attachment uploaded:\s*/i, '')
                    : null;
                return {
                    ...r,
                    _key: (r.questionnaireName || '') + '_' + idx,
                    displayQuestion: r.question ? this._toTitleCase(r.question) : r.question,
                    isFileUpload: isFile,
                    hasFile: isFile && !!r.contentDocumentId,
                    fileUrl: r.contentDocumentId
                        ? '/lightning/r/ContentDocument/' + r.contentDocumentId + '/view'
                        : null,
                    displayResponse: isFile
                        ? (fileName || '—')
                        : (rawResponse || '—'),
                    responseClass: rawResponse ? 'qr-answer' : 'qr-answer empty'
                };
            });
        } else if (error) {
            console.error('getCaseQuestionnaireResponses error:', error);
        }
    }

    _toTitleCase(str) {
        return str.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
    }

    get groupedResponses() {
        const groups = [];
        const seen = {};
        for (const r of this._responses) {
            const key = r.questionnaireName || 'General';
            if (!seen[key]) {
                seen[key] = { questionnaireName: key, items: [] };
                groups.push(seen[key]);
            }
            seen[key].items.push(r);
        }
        return groups;
    }

    get hasResponses() {
        return this._responses && this._responses.length > 0;
    }

    get responseCount() {
        return this._responses ? this._responses.length : 0;
    }

    get isMultipleQuestionnaires() {
        return this.groupedResponses.length > 1;
    }

    get chevronClass() {
        return this.isCollapsed ? 'chevron rotated' : 'chevron';
    }

    get collapseLabel() {
        return this.isCollapsed ? 'Expand' : 'Collapse';
    }

    toggleCollapse() {
        this.isCollapsed = !this.isCollapsed;
    }
}