import { LightningElement, track, wire, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSurveyForEdit from '@salesforce/apex/KenSurveyController.getSurveyForEdit';
import getMySurveys from '@salesforce/apex/KenSurveyController.getMySurveys';
import getSurveyResponsesForExport from '@salesforce/apex/KenSurveyController.getSurveyResponsesForExport';
import deleteSurvey from '@salesforce/apex/KenSurveyController.deleteSurvey';
import createNeedHelpCase from '@salesforce/apex/KenServiceSupportController.createNeedHelpCase';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

// NEW feature apex
import getSurveyResponseStats from '@salesforce/apex/KenSurveyController.getSurveyResponseStats';
import getShortAnswerQuestionCounts from '@salesforce/apex/KenSurveyController.getShortAnswerQuestionCounts';
import getShortAnswerResponsesForExport from '@salesforce/apex/KenSurveyController.getShortAnswerResponsesForExport';

const DRAFT_STORAGE_KEY = 'createSurveyDraft';

export default class KenSurveyDetails extends NavigationMixin(LightningElement) {
    @api surveyId;
    @track surveyData = {};
    @track statusInfo = null;
    @track isLoading = true;
    @track isGroup1Expanded = true;
    @track isDownloading = false;
    @track showDeleteConfirmation = false;
    @track isDeleting = false;
    @track showGetHelpDialog = false;
    @track issueDescription = '';
    @track selectedIssueType = '';
    @track issueSubject = '';
    @track isSubmittingHelp = false;
    @track showNeedHelpModal = false;
    @track isSuccessToastVisible = false;
    @track successTitle = 'Request submitted';
    @track successDescription = 'Your request has been submitted successfully.';
    _successTimer;

    @track shortAnswerCacheByQuestionId = {}; // { [questionId]: { total, rows } }

    get deleteButtonLabel() {
        return this.isDeleting ? 'Deleting...' : 'Request Deletion';
    }

    disconnectedCallback() {
        window.clearTimeout(this._successTimer);
    }

    connectedCallback() {
        if (this.surveyId) {
            this.loadSurveyDetails();
        }   
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
    showSuccessModalWithTimeout() {
        window.clearTimeout(this._successTimer);
        this.isSuccessToastVisible = true;
        this._successTimer = window.setTimeout(() => {
            this.isSuccessToastVisible = false;
        }, 1500);
    }



    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            const urlSurveyId = currentPageReference.state?.surveyId || currentPageReference.state?.c__surveyId;
            if (urlSurveyId && !this.surveyId) {
                this.surveyId = urlSurveyId;
            }
            if (this.surveyId) {
                this.loadSurveyDetails();
            }
        }
    }



    async loadSurveyDetails() {
        if (!this.surveyId) {
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        try {
            const value = localStorage.getItem('ConstituentRoleId');
            const [editResult, surveysResult] = await Promise.all([
                getSurveyForEdit({ surveyId: this.surveyId }),
                getMySurveys({ constituentRoleId: value })
            ]);

            let responseCount = 0;
            if (surveysResult && Array.isArray(surveysResult)) {
                const survey = surveysResult.find(s => s.id === this.surveyId);
                if (survey) {
                    const startDate = this.parseDate(survey.startDate);
                    const endDate = this.parseDate(survey.endDate);
                    this.statusInfo = this.getStatusInfo(survey.approvalStatus, startDate, endDate);
                    responseCount = survey.responsesCount != null ? survey.responsesCount : 0;
                }
            }

            if (editResult && editResult.data) {
                const dto = editResult.data;
                const audienceGroup = this.parseSegmentationDefinition(editResult.segmentationDefinitionJson);

                const questionsBuilt = (dto.questions || []).map((q, index) => {
                    const options = (q.options || []).map((opt, idx) => ({
                        id: `${Date.now()}-${index}-${idx}`,
                        text: opt.text,
                        letter: String.fromCharCode(97 + idx),
                        count: 0,
                        percent: 0
                    }));

                    return {
                        id: `${Date.now()}-${index}`, // UI only
                        sfId: q.id,                  // IMPORTANT: real Questionnaire_Parameter__c Id from Apex
                        number: index + 1,
                        text: q.text || '',
                        type: q.type || '',
                        required: q.required || false,
                        options,
                        scaleMin: q.scaleMin || 1,
                        scaleMax: q.scaleMax || 5,
                        scaleMinLabel: q.scaleMinLabel || '',
                        scaleMaxLabel: q.scaleMaxLabel || '',
                        showOptions: q.type === 'multiple' || q.type === 'checkbox',
                        showLinearScale: q.type === 'linear',
                        showShortAnswer: q.type === 'short',
                        hasLabels:
                            q.type === 'linear' &&
                            (((q.scaleMinLabel || '').trim()) || ((q.scaleMaxLabel || '').trim())),
                        totalResponses: 0,
                        scaleStats: [],

                        // NEW short answer UI fields
                        textResponseCount: 0,
                        shortAnswerDownloading: false,
                        shortAnswerDownloadLabel: 'Download'
                    };
                });

                this.surveyData = {
                    title: dto.title || '',
                    description: dto.description || '',
                    startDate: dto.startDate || '',
                    endDate: dto.endDate || '',
                    responseCount: responseCount,
                    targetAudience: dto.targetAudience || [],
                    questions: questionsBuilt,
                    audienceGroup
                };

                // Existing stats merge (MCQ/checkbox/linear) - keep your logic
                try {
                    const statsList = await getSurveyResponseStats({ surveyId: this.surveyId });

                    const statsByQuestionId = new Map();
                    (statsList || []).forEach(s => {
                        statsByQuestionId.set(s.questionId, {
                            total: s.total || 0,
                            stats: s.stats || []
                        });
                    });

                    const questions = (this.surveyData.questions || []).map((question, index) => {
                        const questionKey = question.sfId || question.id;
                        let qStats = statsByQuestionId.get(questionKey);

                        if (!qStats && Array.isArray(statsList) && statsList[index]) {
                            qStats = {
                                total: statsList[index].total || 0,
                                stats: statsList[index].stats || []
                            };
                        }

                        qStats = qStats || { total: 0, stats: [] };

                        const byValue = new Map();
                        (qStats.stats || []).forEach(st => {
                            const key = (st.responseValue || '').trim();
                            byValue.set(key, {
                                count: st.count || 0,
                                percent: st.percent || 0
                            });
                        });

                        const options = (question.options || []).map(opt => {
                            const key = (opt.text || '').trim();
                            const st = byValue.get(key) || { count: 0, percent: 0 };
                            return {
                                ...opt,
                                count: st.count,
                                percent: st.percent
                            };
                        });

                        let scaleStats = [];
                        if (question.type === 'linear') {
                            const min = question.scaleMin || 1;
                            const max = question.scaleMax || 5;
                            for (let v = min; v <= max; v++) {
                                const key = String(v);
                                const st = byValue.get(key) || { count: 0, percent: 0 };
                                scaleStats.push({
                                    value: v,
                                    count: st.count,
                                    percent: st.percent,
                                    isFirst: v === min,
                                    isLast: v === max
                                });
                            }
                        }

                        return {
                            ...question,
                            totalResponses: qStats.total,
                            options,
                            scaleStats
                        };
                    });

                    this.surveyData = { ...this.surveyData, questions };

                    // âœ… NEW: preload short answer counts (single controller call)
                    await this.preloadShortAnswerCounts();
                } catch (e) {
                    // eslint-disable-next-line no-console
                    console.error('Error loading survey response stats', e);
                }
            }
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading survey details:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // =========================
    // NEW FEATURE: Short Answer counts + CSV download
    // =========================
    async preloadShortAnswerCounts() {
        try {
            const questions = this.surveyData.questions || [];
            const shortQs = questions.filter(q => q.type === 'short' && q.sfId);
            if (!shortQs.length) return;

            // one call returns counts for ALL short answer questions
            const counts = await getShortAnswerQuestionCounts({ surveyId: this.surveyId });
            const mapByQid = new Map();
            (counts || []).forEach(c => mapByQid.set(c.questionId, c.total || 0));

            this.surveyData = {
                ...this.surveyData,
                questions: (this.surveyData.questions || []).map(q => {
                    if (q.type === 'short' && q.sfId) {
                        return { ...q, textResponseCount: mapByQid.get(q.sfId) || 0 };
                    }
                    return q;
                })
            };
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('preloadShortAnswerCounts error', e);
        }
    }

    async handleDownloadShortAnswer(event) {
        const questionId = event.currentTarget?.dataset?.questionid;
        if (!questionId) return;

        // set per-question loading (same feel as your download button)
        this.setShortAnswerButtonState(questionId, true);

        try {
            let exportData = this.shortAnswerCacheByQuestionId[questionId];

            if (!exportData) {
                exportData = await getShortAnswerResponsesForExport({
                    surveyId: this.surveyId,
                    questionId
                });

                this.shortAnswerCacheByQuestionId = {
                    ...this.shortAnswerCacheByQuestionId,
                    [questionId]: exportData
                };
            }

            const rows = exportData?.rows || [];

            const header = ['RespondentId', 'RespondentName', 'Response'];
            const csvLines = [header.join(',')];

            rows.forEach(r => {
                const line = [
                    this.csvEscape(r.respondentId),
                    this.csvEscape(r.respondentName),
                    this.csvEscape(r.responseText)
                ].join(',');
                csvLines.push(line);
            });

            const csv = csvLines.join('\n');
            const safeName = (this.surveyData.title || 'Survey').replace(/[\\/:*?"<>|]/g, '_');
            const fileName = `${safeName}_ShortAnswer_${questionId}_${this.buildTimestamp()}.csv`;

            this.downloadTextFile(csv, fileName, 'text/csv;charset=utf-8');

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Download ready',
                    message: 'Short answer responses downloaded.',
                    variant: 'success'
                })
            );
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('handleDownloadShortAnswer error', e);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to download',
                    message: this.normalizeError(e),
                    variant: 'error'
                })
            );
        } finally {
            this.setShortAnswerButtonState(questionId, false);
        }
    }

    setShortAnswerButtonState(questionId, isDownloading) {
        this.surveyData = {
            ...this.surveyData,
            questions: (this.surveyData.questions || []).map(q => {
                if (q.sfId === questionId) {
                    return {
                        ...q,
                        shortAnswerDownloading: isDownloading,
                        shortAnswerDownloadLabel: isDownloading ? 'Preparing...' : 'Download'
                    };
                }
                return q;
            })
        };
    }

    csvEscape(value) {
        if (value === null || value === undefined) return '""';
        const s = String(value).replace(/\r?\n/g, ' ');
        const escaped = s.replace(/"/g, '""');
        return `"${escaped}"`;
    }

    downloadTextFile(content, fileName, mimeType) {
        try {
            const blob = new Blob([content], { type: mimeType });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = fileName;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
        } catch (err) {
            const dataUrl = `data:${mimeType},${encodeURIComponent(content)}`;
            const link = document.createElement('a');
            link.href = dataUrl;
            link.download = fileName;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }
    }

    // =========================
    // Your existing methods below (unchanged)
    // =========================
    parseDate(value) {
        if (!value) return null;
        const d = value instanceof Date ? value : new Date(value);
        if (Number.isNaN(d.getTime())) return null;
        return d;
    }

    parseSegmentationDefinition(defJson) {
        if (!defJson) return null;
        try {
            const parsed = JSON.parse(defJson);
            // Apex sends '[obj1,obj2,...]' (array of segmentation objects)
            // or a single object for backward-compat
            const segList = Array.isArray(parsed) ? parsed : [parsed];
            const allItems = [];
            segList.forEach(payload => {
                const items = Array.isArray(payload?.items) ? payload.items : [];
                items.forEach(item => {
                    const criteria = (Array.isArray(item.criteria) ? item.criteria : []).map((c, index) => {
                        const values = Array.isArray(c?.values)
                            ? c.values.filter(v => v !== null && v !== undefined && String(v).trim())
                            : [];
                        return {
                            key: c?.key || c?.label || `criteria-${index}`,
                            label: c?.label || c?.key || 'Criteria',
                            values
                        };
                    }).filter(c => c.values.length);
                    allItems.push({
                        id: item.id || `item-${allItems.length}`,
                        title: item?.title || item?.roleLabel || 'Audience',
                        roleLabel: item?.roleLabel || item?.role || '',
                        membersLabel: item?.membersLabel || '',
                        criteria
                    });
                });
            });
            return allItems.length ? allItems : null;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Unable to parse segmentation definition', e);
            return null;
        }
    }

    getStatusInfo(approvalStatus, startDate, endDate) {
        const now = new Date();
        const normalized = (approvalStatus || '').toLowerCase();

        if (normalized === 'rejected') {
            return { label: 'Rejected', className: 'status-badge rejected', bucket: 'rejected' };
        }
        if (normalized === 'approved') {
            if (endDate && endDate < now) {
                return { label: 'Completed', className: 'status-badge completed', bucket: 'approved' };
            }
            if (startDate && startDate > now) {
                return { label: 'Upcoming', className: 'status-badge upcoming', bucket: 'approved' };
            }
            return { label: 'Ongoing', className: 'status-badge ongoing', bucket: 'approved' };
        }
        return { label: 'In Review', className: 'status-badge in-review', bucket: 'inReview' };
    }

    get hasSurveyTitle() { return this.surveyData.title && this.surveyData.title.trim(); }
    get hasSurveyDescription() { return this.surveyData.description && this.surveyData.description.trim(); }
    get hasStartDate() { return this.surveyData.startDate && this.surveyData.startDate.trim(); }
    get hasEndDate() { return this.surveyData.endDate && this.surveyData.endDate.trim(); }
    get formattedStartDate() { return this.surveyData.startDate ? new Date(this.surveyData.startDate).toLocaleDateString('en-GB') : '-'; }
    get formattedEndDate() { return this.surveyData.endDate ? new Date(this.surveyData.endDate).toLocaleDateString('en-GB') : '-'; }

    get hasTargetAudience() {
        const items = this.surveyData?.audienceGroup;
        return Array.isArray(items) && items.length > 0;
    }

    get audienceItems() {
        return this.surveyData?.audienceGroup || [];
    }

    get summaryQuestions() {
        return (this.surveyData.questions || []).filter(q => (q.text || '').trim() || q.type);
    }
    get hasQuestions() { return this.summaryQuestions && this.summaryQuestions.length > 0; }
    get totalQuestions() { return this.summaryQuestions ? this.summaryQuestions.length : 0; }

    get group1CaretClass() { return this.isGroup1Expanded ? 'group-caret group-caret-up' : 'group-caret group-caret-down'; }
    get showStatusIcon() { return this.statusInfo && this.statusInfo.label === 'Ongoing'; }
    get showDeleteButton() { return this.statusInfo && this.statusInfo.label === 'Upcoming'; }
    get showGetHelpButton() { return this.statusInfo && this.statusInfo.label === 'Ongoing'; }
    get showDownloadButton() { return this.statusInfo && (this.statusInfo.label === 'Ongoing' || this.statusInfo.label === 'Completed'); }
    get showEditButton() { return this.statusInfo && this.statusInfo.bucket === 'inReview'; }
    get showDeleteInReviewButton() { return this.statusInfo && this.statusInfo.bucket === 'inReview'; }
    get showEditResubmitButton() { return this.statusInfo && this.statusInfo.bucket === 'rejected'; }
    get isUpcoming() { return this.statusInfo && this.statusInfo.label === 'Upcoming'; }

    get downloadButtonText() { return this.isDownloading ? 'Preparing...' : 'Download Results'; }

    handleToggleGroup1() { this.isGroup1Expanded = !this.isGroup1Expanded; }
    handleDeleteClick() { this.showDeleteConfirmation = true; }
    handleGetHelpClick() { this.showGetHelpDialog = true; }
    handleCloseGetHelpDialog() { this.showGetHelpDialog = false; this.issueDescription = ''; this.selectedIssueType = ''; this.issueSubject = ''; }
    handleGetHelpDialogClick(event) { event.stopPropagation(); }
    handleAutoCreateForm() { /* eslint-disable-next-line no-console */ console.log('Auto-Create Form Now clicked'); }

    async handleSubmitHelp() {
        if (!this.selectedIssueType || !this.issueSubject) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Please fill in all required fields', variant: 'error' }));
            return;
        }
        this.isSubmittingHelp = true;
        try {
            await new Promise(resolve => setTimeout(resolve, 1000));
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Your help request has been submitted successfully', variant: 'success' }));
            this.handleCloseGetHelpDialog();
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error submitting help request:', error);
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Failed to submit help request. Please try again.', variant: 'error' }));
        } finally {
            this.isSubmittingHelp = false;
        }
    }

    get issueTypeOptions() {
        return [
            { label: 'Select', value: '' },
            { label: 'Difficulty Accessing Event Registration', value: 'access' },
            { label: 'Payment issue', value: 'payment' }
        ];
    }

    get submitHelpButtonLabel() { return this.isSubmittingHelp ? 'Submitting...' : 'Submit'; }
    handleDescriptionChange(event) { this.issueDescription = event.target.value; }
    handleIssueTypeChange(event) { this.selectedIssueType = event.target.value; }
    handleIssueSubjectChange(event) { this.issueSubject = event.target.value; }

    async handleDownloadResults() {
        this.isDownloading = true;
        try {
            const rawData = await getSurveyResponsesForExport({ surveyId: this.surveyId });
            const exportData = this.cloneData(rawData);
            if (!exportData) throw new Error('No export data returned.');
            const tableMarkup = this.buildExcelTable(exportData);
            const safeName = (this.surveyData.title || 'Survey').replace(/[\\/:*?"<>|]/g, '_');
            const fileName = `${safeName}_Responses_${this.buildTimestamp()}.xls`;
            this.triggerExcelDownload(tableMarkup, fileName);
            this.dispatchEvent(new ShowToastEvent({ title: 'Download ready', message: 'Responses file downloaded.', variant: 'success' }));
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('downloadSurveyResults error', error);
            this.dispatchEvent(new ShowToastEvent({ title: 'Unable to download', message: this.normalizeError(error), variant: 'error' }));
        } finally {
            this.isDownloading = false;
        }
    }

    handleEditClick() { this.prefillSurveyDraft(this.surveyId); }
    handleEditResubmitClick() { this.prefillSurveyDraft(this.surveyId); }
    handleCloseDeleteConfirmation() { this.showDeleteConfirmation = false; }
    handleDeleteDialogClick(event) { event.stopPropagation(); }

    async handleRequestDeletion() {
        if (!this.surveyId || this.isDeleting) return;
        this.isDeleting = true;
        try {
            await deleteSurvey({ surveyId: this.surveyId });
            this.showDeleteConfirmation = false;
            this.dispatchEvent(new ShowToastEvent({ title: 'Survey deleted', message: 'Survey and related records were deleted.', variant: 'success' }));
            this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'all_surveys__c' } });
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('delete survey error', error);
            this.dispatchEvent(new ShowToastEvent({ title: 'Delete failed', message: this.normalizeError(error), variant: 'error' }));
        } finally {
            this.isDeleting = false;
        }
    }

    async prefillSurveyDraft(surveyId) {
        try {
            const result = await getSurveyForEdit({ surveyId });
            if (!result || !result.data) return;
            const dto = result.data;
            const questions = (dto.questions || []).map((q, index) => {
                const options = (q.options || []).map((opt, idx) => ({
                    id: `${Date.now()}-${index}-${idx}`,
                    text: opt.text,
                    letter: String.fromCharCode(97 + idx)
                }));
                return {
                    id: `${Date.now()}-${index}`,
                    sfId: q.id,
                    number: index + 1,
                    text: q.text || '',
                    type: q.type || '',
                    required: q.required || false,
                    options,
                    scaleMin: q.scaleMin || 1,
                    scaleMax: q.scaleMax || 5,
                    scaleMinLabel: q.scaleMinLabel || '',
                    scaleMaxLabel: q.scaleMaxLabel || '',
                    showMultipleOptions: q.type === 'multiple' || q.type === 'checkbox',
                    isMultiple: q.type === 'multiple',
                    isCheckboxType: q.type === 'checkbox',
                    showLinearScale: q.type === 'linear',
                    showShortAnswer: q.type === 'short',
                    nextOptionNumber: options.length + 1
                };
            });

            const draft = {
                existingSurveyId: result.surveyId,
                surveyTitle: dto.title || '',
                surveyDescription: dto.description || '',
                targetAudience: dto.targetAudience || [],
                startDate: dto.startDate || '',
                endDate: dto.endDate || '',
                questions: questions.length ? questions : [
                    {
                        id: '1',
                        sfId: null,
                        number: 1,
                        text: '',
                        type: '',
                        required: false,
                        options: [],
                        scaleMin: 1,
                        scaleMax: 5,
                        scaleMinLabel: '',
                        scaleMaxLabel: '',
                        showMultipleOptions: false,
                        isMultiple: false,
                        isCheckboxType: false,
                        showLinearScale: false,
                        showShortAnswer: false,
                        nextOptionNumber: 1
                    }
                ]
            };
            window.sessionStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify(draft));
            this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'create_survey__c' } });
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unable to prefill survey draft', e);
        }
    }

    buildExcelTable(exportData) {
        const headers = ['AccountId', 'Username', 'SubmittedAt'];
        const questionColumns = [...(exportData.questions || [])]
            .sort((a, b) => (a.displayOrder || 0) - (b.displayOrder || 0))
            .map((q) => ({ id: q.id, label: q.label || 'Question', type: q.questionType }));
        questionColumns.forEach((q) => headers.push(q.label));

        const bodyRows = (exportData.rows || []).map((row) => {
            const answers = row.answersByQuestionId || {};
            const submitted = row.submittedAt ? new Date(row.submittedAt).toISOString() : '';
            const data = [row.accountId || '', row.respondentName || '', submitted];
            questionColumns.forEach((q) => {
                data.push(answers[q.id] || '');
            });
            return data;
        });

        const thead = `<thead><tr>${headers.map((h) => `<th>${this.escapeHtml(h)}</th>`).join('')}</tr></thead>`;
        const tbody = `<tbody>${bodyRows
            .map((row) => `<tr>${row.map((cell) => `<td>${this.escapeHtml(cell)}</td>`).join('')}</tr>`)
            .join('')}</tbody>`;
        return `<table>${thead}${tbody}</table>`;
    }

    triggerExcelDownload(tableMarkup, fileName) {
        const html = `<html><head><meta charset="UTF-8"></head><body>${tableMarkup}</body></html>`;
        const mime = 'application/vnd.ms-excel;charset=utf-8';
        try {
            const blob = new Blob([html], { type: mime });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = fileName;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
        } catch (err) {
            const dataUrl = `data:${mime},${encodeURIComponent(html)}`;
            const link = document.createElement('a');
            link.href = dataUrl;
            link.download = fileName;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }
    }

    buildTimestamp() {
        const now = new Date();
        const pad = (num) => String(num).padStart(2, '0');
        return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}`;
    }

    cloneData(value) {
        try { return value ? JSON.parse(JSON.stringify(value)) : value; }
        catch (e) { return value; }
    }

    escapeHtml(value) {
        if (value === null || value === undefined) return '';
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
        if (error?.body && typeof error.body === 'object') return error.body.message || JSON.stringify(error.body);
        return error?.message || 'Unexpected error occurred';
    }

    handleNeedHelpClick() {
        this.showNeedHelpModal = true;
    }

    handleCloseNeedHelpModal() {
        this.showNeedHelpModal = false;
    }

    
    async handleNeedHelpSubmit(event) {
        const { description, issueType, subject, file } = event.detail || {};

        try {
            let fileData;
            let fileName;

            if (file) {
                ({ fileData, fileName } = await this.readFileAsBase64(file));
            }

            await createNeedHelpCase({
                serviceOfferingId: issueType,
                subject,
                description,
                fileName,
                fileData
            });

            this.showNeedHelpModal = false;

            //  this is the success modal (not toast)
            this.successTitle = 'Request submitted';
            this.successDescription = 'Your request has been submitted successfully.';
            this.showSuccessModalWithTimeout();

        } catch (error) {
            // show the child error modal (your existing pattern)
            const modal = this.template.querySelector('c-need-help-modal');
            const message = error?.body?.message || error?.message || 'An unexpected error occurred.';
            if (modal) modal.showError('Submission failed', message);
        }
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                resolve({ fileData: base64, fileName: file.name });
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }




}