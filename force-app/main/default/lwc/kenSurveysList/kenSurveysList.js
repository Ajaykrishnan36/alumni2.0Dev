import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getMySurveys from '@salesforce/apex/KenSurveyController.getMySurveys';
import getSurveyForEdit from '@salesforce/apex/KenSurveyController.getSurveyForEdit';
import getSurveyResponsesForExport from '@salesforce/apex/KenSurveyController.getSurveyResponsesForExport';
import deleteSurvey from '@salesforce/apex/KenSurveyController.deleteSurvey';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import SurveyEmptyImage from '@salesforce/resourceUrl/SurveyEmptyImage'; 
const DRAFT_STORAGE_KEY = 'createSurveyDraft';

export default class KenSurveysList extends NavigationMixin(LightningElement) {
    @track activeTab = 'approved';
    @track searchTerm = '';
    @track showFiltersPopup = false;
    @track selectedStatus = '';
    @track popupTop = 0;
    @track popupRight = 0;
    @track showDetailsModal = false;
    @track selectedSurvey = {};
    @track showDeleteConfirmation = false;
    @track isDownloading = false;
    @track sortDirection = 'asc';
    @track isDeleting = false;
    SurveyEmptyImageUrl = SurveyEmptyImage;

    get computedPopupStyle() {
        return `top: ${this.popupTop}px; right: ${this.popupRight}px;`;
    }

    get isEmptySurveys() {
        return !this.filteredSurveys || this.filteredSurveys.length === 0;
    }

    get emptyStateMessage() {
        if (this.activeTab === 'approved') {
            return 'You have no approved surveys yet.';
        } else if (this.activeTab === 'inReview') {
            return 'You have no surveys in review.';
        } else if (this.activeTab === 'rejected') {
            return 'You have no rejected surveys.';
        }
        return 'No surveys found.';
    }
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    @track allSurveys = {
        approved: [],
        inReview: [],
        rejected: []
    };

    get filteredSurveys() {
        let surveys = this.allSurveys[this.activeTab] || [];
        
        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            surveys = surveys.filter((survey) => (survey.title || '').toLowerCase().includes(term));
        }
        // eslint-disable-next-line no-console
        console.log('surveysList filteredSurveys', this.activeTab, surveys);

        return this.getSortedSurveys(surveys);
    }

    get statusOptions() {
        return [
            { label: 'All', value: 'all' },
            { label: 'Upcoming', value: 'upcoming' },
            { label: 'Ongoing', value: 'ongoing' },
            { label: 'Completed', value: 'completed' },
            { label: 'In Review', value: 'inReview' },
            { label: 'Rejected', value: 'rejected' }
        ];
    }

    get approvedTabClass() {
        return `tab-btn ${this.activeTab === 'approved' ? 'active' : ''}`;
    }

    get inReviewTabClass() {
        return `tab-btn ${this.activeTab === 'inReview' ? 'active' : ''}`;
    }

    get rejectedTabClass() {
        return `tab-btn ${this.activeTab === 'rejected' ? 'active' : ''}`;
    }

    get sortIconClass() {
        return this.sortDirection === 'desc' ? 'sort-arrow sort-arrow-desc' : 'sort-arrow';
    }

    get surveyCardClass() {
        if (this.activeTab === 'inReview' || this.activeTab === 'rejected') {
            return 'survey-list-card clickable-card';
        }
        return 'survey-list-card';
    }

    get isInReviewTab() {
        return this.activeTab === 'inReview';
    }

    get isRejectedTab() {
        return this.activeTab === 'rejected';
    }

    handleTabChange(event) {
        const tab = event.currentTarget.getAttribute('data-tab');
        this.activeTab = tab;
    }

    connectedCallback() {
        // eslint-disable-next-line no-console
        console.log('surveysList connectedCallback');
        this.loadSurveys();
    }

    async loadSurveys() {
        try {
            const result = await getMySurveys();
            // eslint-disable-next-line no-console
            console.log('surveysList loadSurveys raw result', JSON.parse(JSON.stringify(result)));
            const mapped = (result || []).map((survey) => this.mapSurveyToCard(survey));
            // eslint-disable-next-line no-console
            console.log('surveysList mapped cards', mapped);
            const approved = [];
            const inReview = [];
            const rejected = [];
            mapped.forEach((item) => {
                if (item.bucket === 'rejected') {
                    rejected.push(item);
                } else if (item.bucket === 'inReview') {
                    inReview.push(item);
                } else {
                    approved.push(item);
                }
            });
            this.allSurveys = { approved, inReview, rejected };
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading surveys', error);
            this.allSurveys = { approved: [], inReview: [], rejected: [] };
        }
    }

    mapSurveyToCard(survey) {
        const startDate = this.parseDate(survey.startDate);
        const endDate = this.parseDate(survey.endDate);
        const statusInfo = this.getStatusInfo(survey.approvalStatus, startDate, endDate);
        const totalQuestions =
            survey.questionnaire && Array.isArray(survey.questionnaire.parameters)
                ? survey.questionnaire.parameters.length
                : null;
        const submittedDateValue = survey.submittedDate ? this.parseDate(survey.submittedDate) : null;

        // eslint-disable-next-line no-console
        console.log('surveysList mapSurveyToCard input', survey, 'statusInfo', statusInfo);

        return {
            bucket: statusInfo.bucket,
            id: survey.id,
            title: survey.name || survey.sectionName || '',
            segmentationName: survey.segmentationName || '-',
            surveyPeriod: this.formatPeriod(startDate, endDate),
            submittedDate: survey.submittedDate ? this.formatDate(survey.submittedDate) : '',
            totalQuestions: totalQuestions != null ? String(totalQuestions) : '',
            status: statusInfo.label,
            statusClass: statusInfo.className,
            showPeriod: true,
            startDateValue: startDate,
            endDateValue: endDate,
            submittedDateValue,
            showResponses: statusInfo.bucket === 'approved',
            responses: survey.responsesCount != null ? String(survey.responsesCount) : '0',
            showViewDetails: statusInfo.bucket === 'approved' || statusInfo.bucket === 'inReview',
            showStatusIcon: statusInfo.label === 'Ongoing',
            showSubmitted: statusInfo.bucket === 'inReview' || statusInfo.bucket === 'rejected',
            showSubmittedInTitleRow: statusInfo.bucket === 'inReview',
            showRejected: statusInfo.bucket === 'rejected',
            showReason: statusInfo.bucket === 'rejected',
            showEditResubmit: statusInfo.bucket === 'rejected',
            rejectedDate: survey.rejectedDate ? this.formatDate(survey.rejectedDate) : null,
            rejectionReason: survey.rejectionReason || survey.rejectionComments || null
        };
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

        return { label: 'Pending', className: 'status-badge in-review', bucket: 'inReview' };
    }

    formatPeriod(fromDate, toDate) {
        if (!fromDate && !toDate) {
            return '';
        }
        const from = fromDate ? this.formatDate(fromDate) : '';
        const to = toDate ? this.formatDate(toDate) : '';
        if (from && to) {
            return `${from} - ${to}`;
        }
        return from || to;
    }

    formatDate(dateValue) {
        const parsed = this.parseDate(dateValue);
        if (!parsed) {
            return '';
        }
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(parsed);
    }

    parseDate(value) {
        if (!value) {
            return null;
        }
        const d = value instanceof Date ? value : new Date(value);
        if (Number.isNaN(d.getTime())) {
            // eslint-disable-next-line no-console
            console.error('surveysList invalid date', value);
            return null;
        }
        return d;
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value || '';
    }

    handleSortClick() {
        this.sortDirection = this.sortDirection === 'desc' ? 'asc' : 'desc';
    }

    handleFiltersClick(event) {
        this.showFiltersPopup = !this.showFiltersPopup;
    }

    renderedCallback() {
        if (this.showFiltersPopup) {
            setTimeout(() => {
                this.positionPopup();
            }, 0);
        }
    }

    positionPopup() {
        const filterBtn = this.template.querySelector('[data-filter-btn="true"]');
        const popup = this.template.querySelector('.filters-popup');
        
        if (filterBtn && popup) {
            const rect = filterBtn.getBoundingClientRect();
            const popupWidth = 400;
            const viewportWidth = window.innerWidth;
            const viewportHeight = window.innerHeight;
            
            let top = rect.bottom + 8;
            let right = viewportWidth - rect.right;
            
            if (top + 500 > viewportHeight) {
                top = rect.top - 500 - 8;
                if (top < 0) {
                    top = 8;
                }
            }
            
            if (right + popupWidth > viewportWidth) {
                right = 24;
            }
            
            this.popupTop = top;
            this.popupRight = right;
        }
    }

    handleFiltersOverlayClick(event) {
        this.showFiltersPopup = false;
    }

    handleFiltersPopupClick(event) {
        event.stopPropagation();
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }

    handleResetFilters() {
        this.selectedStatus = '';
    }

    handleApplyFilters() {
        // Apply filter logic here
        this.showFiltersPopup = false;
    }

    handleViewDetails(event) {
        event.stopPropagation();
        const surveyId = event.currentTarget.getAttribute('data-survey-id');
        if (surveyId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'survey_detail__c'
                },
                state: {
                    surveyId: surveyId
                }
            });
        }
    }

    handleCloseModal() {
        this.showDetailsModal = false;
        this.selectedSurvey = {};
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleDownloadResults() {
        this.downloadSurveyResults();
    }

    get showDeleteEditButtons() {
        return this.selectedSurvey.status === 'Upcoming' && this.activeTab === 'approved';
    }

    get showDownloadButton() {
        return this.selectedSurvey.status === 'Completed' || this.selectedSurvey.status === 'Ongoing';
    }

    get showEditResubmitButton() {
        return this.selectedSurvey.showEditResubmit && this.activeTab === 'rejected';
    }

    get deleteButtonLabel() {
        return this.isDeleting ? 'Deleting...' : 'Delete';
    }

    handleCardClick(event) {
        const card = event.currentTarget;
        const status = card.getAttribute('data-survey-status');
        const surveyId = card.getAttribute('data-survey-id');
        
        // Prevent event from bubbling to buttons
        if (event.target.closest('.view-details-btn') || event.target.closest('.edit-resubmit-btn')) {
            return;
        }
        
        // Navigate to details page for all card clicks
        if (surveyId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'survey_detail__c'
                },
                state: {
                    surveyId: surveyId
                }
            });
        }
    }

    handleDeleteClick(event) {
        event.stopPropagation();
        this.showDetailsModal = false;
        this.showDeleteConfirmation = true;
    }

    handleEditClick(event) {
        event.stopPropagation();
        if (this.selectedSurvey?.id) {
            this.prefillSurveyDraft(this.selectedSurvey.id);
        }
    }

    handleCloseDeleteConfirmation() {
        this.showDeleteConfirmation = false;
    }

    handleDeleteDialogClick(event) {
        event.stopPropagation();
    }

    handleRequestDeletion(event) {
        event.stopPropagation();
        if (!this.selectedSurvey?.id || this.isDeleting) {
            return;
        }
        this.isDeleting = true;
        deleteSurvey({ surveyId: this.selectedSurvey.id })
            .then(() => {
                this.removeSurveyFromState(this.selectedSurvey.id);
                this.selectedSurvey = {};
                this.showDeleteConfirmation = false;
                this.showDetailsModal = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Survey deleted',
                        message: 'Survey and related records were deleted.',
                        variant: 'success'
                    })
                );
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('delete survey error', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Delete failed',
                        message: this.normalizeError(error),
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isDeleting = false;
            });
    }

    handleEditResubmit(event) {
        const surveyId = event.currentTarget.getAttribute('data-survey-id');
        this.prefillSurveyDraft(surveyId);
    }

    handleCreateSurvey() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'create_survey__c'
            }
        });
    }

    async prefillSurveyDraft(surveyId) {
        try {
            const result = await getSurveyForEdit({ surveyId });
            if (!result || !result.data) {
                return;
            }
            const dto = result.data;
            const questions = (dto.questions || []).map((q, index) => {
                const options = (q.options || []).map((opt, idx) => ({
                    id: `${Date.now()}-${index}-${idx}`,
                    text: opt.text,
                    letter: String.fromCharCode(97 + idx)
                }));
                return {
                    id: `${Date.now()}-${index}`,
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
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'create_survey__c'
                }
            });
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unable to prefill survey draft', e);
        }
    }

    get downloadButtonText() {
        return this.isDownloading ? 'Preparing...' : 'Download Results';
    }

    async downloadSurveyResults() {
        this.isDownloading = true;
        if (!this.selectedSurvey || !this.selectedSurvey.id) {
            this.isDownloading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No survey selected',
                    message: 'Open a survey and try again.',
                    variant: 'warning'
                })
            );
            return;
        }
        try {
            const rawData = await getSurveyResponsesForExport({ surveyId: this.selectedSurvey.id });
            const exportData = this.cloneData(rawData);
            if (!exportData) {
                throw new Error('No export data returned.');
            }
            const tableMarkup = this.buildExcelTable(exportData);
            const safeName = (exportData.surveyName || 'Survey').replace(/[\\/:*?"<>|]/g, '_');
            const fileName = `${safeName}_Responses_${this.buildTimestamp()}.xls`;
            this.triggerExcelDownload(tableMarkup, fileName);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Download ready',
                    message: 'Responses file downloaded.',
                    variant: 'success'
                })
            );
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('downloadSurveyResults error', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to download',
                    message: this.normalizeError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isDownloading = false;
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

        const thead = `<thead><tr>${headers
            .map((h) => `<th>${this.escapeHtml(h)}</th>`)
            .join('')}</tr></thead>`;
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
            // Fallback to data URL if Blob/ObjectURL is blocked
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
        return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(
            now.getHours()
        )}${pad(now.getMinutes())}`;
    }

    getSortedSurveys(surveys) {
        const dir = this.sortDirection === 'asc' ? 1 : -1;
        return [...surveys].sort((a, b) => {
            const aName = (a?.title || '').toLowerCase();
            const bName = (b?.title || '').toLowerCase();
            return dir * aName.localeCompare(bName);
        });
    }

    removeSurveyFromState(surveyId) {
        const filterOut = (list) => list.filter((s) => s.id !== surveyId);
        this.allSurveys = {
            approved: filterOut(this.allSurveys.approved),
            inReview: filterOut(this.allSurveys.inReview),
            rejected: filterOut(this.allSurveys.rejected)
        };
    }

    cloneData(value) {
        try {
            return value ? JSON.parse(JSON.stringify(value)) : value;
        } catch (e) {
            return value;
        }
    }

    escapeHtml(value) {
        if (value === null || value === undefined) {
            return '';
        }
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error?.body && typeof error.body === 'object') {
            return error.body.message || JSON.stringify(error.body);
        }
        return error?.message || 'Unexpected error occurred';
    }
}