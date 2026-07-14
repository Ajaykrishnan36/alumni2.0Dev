import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import listYourBusinessImage from '@salesforce/resourceUrl/Listyourbusiness';
import SurveyEmptyImage from '@salesforce/resourceUrl/SurveyEmptyImage';
import getSurveys from '@salesforce/apex/KenSurveyController.getSurveys';
import getMySurveys from '@salesforce/apex/KenSurveyController.getMySurveys';
import submitSurveyResponses from '@salesforce/apex/KenSurveyController.submitSurveyResponses';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenSurveys extends NavigationMixin(LightningElement) {
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
    listYourBusinessImageUrl = listYourBusinessImage;
    SurveyEmptyImageUrl = SurveyEmptyImage;
    @track searchTerm = '';
    @track showFiltersPopup = false;
    @track selectedStatus = '';
    @track selectedDateRange = '';
    @track selectedDate = '';
    @track selectedSurveyFeedback = '';
    @track appliedStatus = '';
    @track appliedDateRange = '';
    @track appliedDate = '';
    @track appliedSurveyFeedback = '';
    @track popupTop = 0;
    @track popupRight = 0;

    get computedPopupStyle() {
        return `top: ${this.popupTop}px; right: ${this.popupRight}px;`;
    }

    @track allSurveys = [];
    rawSurveys = [];
    sortDirection = 'asc';
    sortField = 'name';

    @track yourSurveys = [];
    @track showBeginSurveyDialog = false;
    @track selectedSurveyId = null;

    get hasYourSurveys() {
        return this.yourSurveys && this.yourSurveys.length > 0;
    }

    get isEmptyYourSurveys() {
        return !this.hasYourSurveys;
    }

    get hasAllSurveys() {
        return this.allSurveys && this.allSurveys.length > 0;
    }

    get isEmptyAllSurveys() {
        return !this.hasAllSurveys;
    }

    get activeFilterCount() {
        let count = 0;
        if (this.appliedStatus && this.appliedStatus !== 'all') {
            count++;
        }
        if (this.appliedDateRange && this.appliedDateRange !== 'all') {
            count++;
        }
        if (this.appliedDate) {
            count++;
        }
        if (this.appliedSurveyFeedback && this.appliedSurveyFeedback !== 'all') {
            count++;
        }
        return count;
    }

    get hasActiveFilters() {
        return this.activeFilterCount > 0;
    }

    get filtersBtnClass() {
        return this.hasActiveFilters ? 'filters-btn filters-btn-active' : 'filters-btn';
    }

    connectedCallback() {
        this.loadSurveys();
    }

    async loadSurveys() {
        try {
            const value = localStorage.getItem('ConstituentRoleId');
            const [allSurveys, mySurveys] = await Promise.all([
                getSurveys({ constituentRoleId: value }),
                getMySurveys({ constituentRoleId: value })
            ]);
            this.rawSurveys = (allSurveys || []).map((survey) => this.transformSurvey(survey));
            this.applyFiltersAndSort();
            this.yourSurveys = (mySurveys || []).map((survey) => {
                const transformed = this.transformSurvey(survey);
                const statusInfo = this.getStatusInfo(
                    transformed.approvalStatus,
                    transformed.isCompleted,
                    transformed.startDate,
                    transformed.endDate
                );
                const label = statusInfo.label;
                return {
                    id: transformed.id,
                    title: transformed.title,
                    fromDate: transformed.startDate,
                    toDate: transformed.endDate,
                    status: label,
                    statusClass: statusInfo.className,
                    showStatusIcon: statusInfo.showIcon,
                    submittedDate:
                        label === 'In Review' && transformed.submittedDate
                            ? this.formatDate(transformed.submittedDate)
                            : '',
                    surveyPeriod:
                        label === 'Upcoming' || label === 'Ongoing'
                            ? this.formatPeriod(transformed.fromDate, transformed.toDate)
                            : '',
                    rejectedDate:
                        label === 'Rejected' && transformed.rejectedDate
                            ? this.formatDate(transformed.rejectedDate)
                            : null,
                    rejectionReason:
                        label === 'Rejected' ? transformed.rejectionComments || transformed.rejectionReason || null : null,
                    isCompleted: transformed.isCompleted,
                    responses: label === 'Ongoing' || label === 'Completed' ? transformed.responses || '0' : '0',
                    showResponses: label === 'Ongoing' || label === 'Completed'
                };
            });
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading surveys', error);
            this.rawSurveys = [];
            this.allSurveys = [];
            this.yourSurveys = [];
        }
    }

    transformSurvey(survey) {
        const endDate = survey.endDate ? new Date(survey.endDate) : null;
        const startDate = survey.startDate ? new Date(survey.startDate) : null;
        const submittedDate = survey.submittedDate ? new Date(survey.submittedDate) : null;
        const rejectedDate = survey.rejectedDate ? new Date(survey.rejectedDate) : null;
        const questions = this.mapQuestionsFromSurvey(survey.questionnaire?.parameters);
        const title = survey.name || survey.sectionName || '';
        const isFeedback = title.toLowerCase().includes('feedback');
        return {
            id: survey.id,
            title: title,
            lastDate: this.formatDate(endDate || startDate),
            endDate,
            startDate,
            fromDate: survey.fromDate ? new Date(survey.fromDate) : startDate,
            toDate: survey.toDate ? new Date(survey.toDate) : endDate,
            approvalStatus: survey.approvalStatus,
            isActive: survey.isActive,
            submittedDate,
            createdById: survey.createdById,
            createdByAccountId: survey.createdByAccountId,
            rejectedDate,
            rejectionReason: survey.rejectionReason,
            rejectionComments: survey.rejectionComments,
            questionnaireId: survey.questionnaireId,
            responses: survey.responsesCount != null ? String(survey.responsesCount) : '0',
            isCompleted: survey.hasResponses,
            questions: questions,
            type: isFeedback ? 'Feedback' : 'Survey',
            totalQuestions: questions ? questions.length : 0
        };
    }

    mapQuestionsFromSurvey(questionList) {
        if (!questionList || !questionList.length) {
            return [];
        }
        return questionList.map((question, index) => this.mapQuestion(question, index));
    }

    mapQuestion(question, index) {
        const type = this.mapQuestionType(question.questionType);
        const options = this.buildOptions(question.questionType, question.mcqOptions);
        const scale = this.buildScale(question);
        const displayOrder = question.displayOrder != null ? Number(question.displayOrder) : index + 1;

        return {
            id: question.id,
            displayId: displayOrder,
            order: displayOrder,
            type,
            question: question.questionLabel || '',
            options,
            placeholder: 'Enter',
            scale,
            showConditionalField: false,
            followUpQuestionId: `${question.id}-followup`,
            isRequired: question.required === true
        };
    }

    mapQuestionType(questionType) {
        switch (questionType) {
            case 'Multiple Choice':
                return 'checkbox';
            case 'Dropdown':
                return 'radio';
            case 'Yes/No':
                return 'radio';
            case 'Rating':
            case 'Linear Scale':
                return 'rating';
            case 'Short Answer':
            case 'Comment':
            default:
                return 'text';
        }
    }

    buildOptions(questionType, mcqOptions) {
        if (questionType === 'Yes/No') {
            return ['Yes', 'No'];
        }

        if (!mcqOptions) {
            return [];
        }

        return mcqOptions
            .split(/[\n;,]+/)
            .map((option) => option.trim())
            .filter((option) => option);
    }

    buildScale(question) {
        if (question.questionType === 'Rating' || question.questionType === 'Linear Scale') {
            const min = question.minGrade || 1;
            const max = question.maxGrade || 5;
            const minLabel = question.minGradeLabel || '';
            const maxLabel = question.maxGradeLabel || '';

            const scale = [];
            for (let i = min; i <= max; i++) {
                scale.push({ value: i, label: i === min ? minLabel : i === max ? maxLabel : '' });
            }
            return scale;
        }
        return null;
    }

    formatDate(dateValue) {
        if (!dateValue) {
            return '';
        }
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(dateValue);
    }

    applyFiltersAndSort() {
        const filtered = this.filterSurveys(this.rawSurveys);
        this.allSurveys = this.sortSurveys(filtered);
    }

    filterSurveys(source) {
        let filtered = [...source];

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            filtered = filtered.filter(
                (survey) =>
                    (survey.title && survey.title.toLowerCase().includes(term)) ||
                    (survey.approvalStatus && survey.approvalStatus.toLowerCase().includes(term))
            );
        }

        if (this.appliedStatus && this.appliedStatus !== 'all') {
            if (this.appliedStatus === 'completed') {
                filtered = filtered.filter((survey) => survey.isCompleted);
            } else {
                const statusMap = {
                    'in-review': 'Pending Approval',
                    ongoing: 'Approved',
                    rejected: 'Rejected'
                };
                const targetStatus = statusMap[this.appliedStatus] || this.appliedStatus;
                filtered = filtered.filter(
                    (survey) => (survey.approvalStatus || '').toLowerCase() === targetStatus.toLowerCase()
                );
            }
        }

        if (this.appliedDateRange && this.appliedDateRange !== 'all') {
            const now = new Date();
            let cutoff = new Date(now);
            switch (this.appliedDateRange) {
                case '7days':
                    cutoff.setDate(now.getDate() - 7);
                    break;
                case '30days':
                    cutoff.setDate(now.getDate() - 30);
                    break;
                case '3months':
                    cutoff.setMonth(now.getMonth() - 3);
                    break;
                case '6months':
                    cutoff.setMonth(now.getMonth() - 6);
                    break;
                default:
                    cutoff = null;
            }

            if (cutoff) {
                filtered = filtered.filter((survey) => !survey.endDate || survey.endDate >= cutoff);
            }
        }

        if (this.appliedDate) {
            const selectedDateObj = new Date(this.appliedDate);
            selectedDateObj.setHours(0, 0, 0, 0);
            filtered = filtered.filter((survey) => {
                if (!survey.endDate) return false;
                const surveyEndDate = new Date(survey.endDate);
                surveyEndDate.setHours(0, 0, 0, 0);
                return surveyEndDate.getTime() === selectedDateObj.getTime();
            });
        }

        if (this.appliedSurveyFeedback && this.appliedSurveyFeedback !== 'all') {
            filtered = filtered.filter((survey) => {
                const surveyType = (survey.type || '').toLowerCase();
                return surveyType === this.appliedSurveyFeedback.toLowerCase();
            });
        }

        return filtered;
    }

    sortSurveys(list) {
        const sorted = [...list];
        sorted.sort((a, b) => {
            if (this.sortField === 'endDate') {
                const aTime = a.endDate ? a.endDate.getTime() : 0;
                const bTime = b.endDate ? b.endDate.getTime() : 0;
                return aTime - bTime;
            }
            return (a.title || '').localeCompare(b.title || '');
        });

        if (this.sortDirection === 'desc') {
            sorted.reverse();
        }

        return sorted;
    }

    getStatusInfo(approvalStatus, isCompleted, startDate, endDate) {
        const now = new Date();
        if (isCompleted) {
            return { label: 'Completed', className: 'status-badge completed', showIcon: false };
        }
        const normalized = (approvalStatus || '').toLowerCase();
        if (normalized === 'rejected') {
            return { label: 'Rejected', className: 'status-badge rejected', showIcon: false };
        }
        if (normalized === 'approved') {
            if (startDate && startDate > now) {
                return { label: 'Upcoming', className: 'status-badge upcoming', showIcon: false };
            }
            if (endDate && endDate < now) {
                return { label: 'Completed', className: 'status-badge completed', showIcon: false };
            }
            return { label: 'Ongoing', className: 'status-badge ongoing', showIcon: true };
        }
        return { label: 'In Review', className: 'status-badge in-review', showIcon: false };
    }

    formatPeriod(fromDate, toDate) {
        if (!fromDate && !toDate) {
            return '';
        }
        const format = (dateValue) =>
            new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric' }).format(dateValue);
        const from = fromDate ? format(fromDate) : '';
        const to = toDate ? format(toDate) : '';
        if (from && to) {
            return `${from} - ${to}`;
        }
        return from || to;
    }

    setSurveyCompletionFlag(surveyId, isCompleted) {
        this.rawSurveys = this.rawSurveys.map((survey) => {
            if (survey.id !== surveyId) {
                return survey;
            }
            const updated = { ...survey };
            if (isCompleted) {
                updated.isCompleted = true;
            } else {
                delete updated.isCompleted;
            }
            return updated;
        });
        this.applyFiltersAndSort();
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value || '';
        this.applyFiltersAndSort();
    }

    get sortIconClass() {
        return this.sortDirection === 'desc' ? 'sort-arrow sort-arrow-desc' : 'sort-arrow';
    }

    handleSortClick() {
        this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        this.applyFiltersAndSort();
    }

    handleFiltersClick(event) {
        this.showFiltersPopup = !this.showFiltersPopup;
    }

    positionPopup() {
        const filterBtn = this.template.querySelector('[data-filter-btn="true"]');
        const popup = this.template.querySelector('.filters-popup');
        
        if (filterBtn && popup) {
            const rect = filterBtn.getBoundingClientRect();
            const popupWidth = 400;
            const viewportWidth = window.innerWidth;
            const viewportHeight = window.innerHeight;
            
            // Calculate position - align to bottom-right of button
            let top = rect.bottom + 8;
            let right = viewportWidth - rect.right;
            
            // Adjust if popup would go off screen
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

    // Mirrors the staged/draft (selected*) filter values onto the applied*
    // values that filterSurveys() actually reads, then re-runs the
    // synchronous in-memory filter/sort. Called from every field handler so
    // filters apply live, and from the Apply button handler.
    _applyDraftLive() {
        this.appliedStatus = this.selectedStatus;
        this.appliedDateRange = this.selectedDateRange;
        this.appliedDate = this.selectedDate;
        this.appliedSurveyFeedback = this.selectedSurveyFeedback;
        this.applyFiltersAndSort();
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this._applyDraftLive();
    }

    handleDateRangeChange(event) {
        this.selectedDateRange = event.detail.value;
        this._applyDraftLive();
    }

    handleDateChange(event) {
        this.selectedDate = event.detail.value;
        this._applyDraftLive();
    }

    handleSurveyFeedbackChange(event) {
        this.selectedSurveyFeedback = event.detail.value;
        this._applyDraftLive();
    }

    handleResetFilters() {
        this.selectedStatus = '';
        this.selectedDateRange = '';
        this.selectedDate = '';
        this.selectedSurveyFeedback = '';
        this.appliedStatus = '';
        this.appliedDateRange = '';
        this.appliedDate = '';
        this.appliedSurveyFeedback = '';
        this.applyFiltersAndSort();
    }

    handleApplyFilters() {
        // Filtering is already live from the field handlers; Apply just
        // syncs once more (in case of any drift) and closes the popup.
        this._applyDraftLive();
        this.showFiltersPopup = false;
    }

    handleBeginSurvey(event) {
        const surveyId = event.currentTarget.getAttribute('data-survey-id');
        // Show the beginning dialog first
        this.selectedSurveyId = surveyId;
        this.showBeginSurveyDialog = true;
    }

    handleGoBackFromDialog() {
        this.showBeginSurveyDialog = false;
        this.selectedSurveyId = null;
    }

    handleBeginSurveyFromDialog() {
        this.showBeginSurveyDialog = false;
        // Navigate to survey form page
        if (this.selectedSurveyId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'survey_form__c'
                },
                state: {
                    surveyId: this.selectedSurveyId
                }
            });
        }
        this.selectedSurveyId = null;
    }

    get selectedSurvey() {
        return this.rawSurveys.find((survey) => survey.id === this.selectedSurveyId);
    }

    get selectedSurveyTitle() {
        return (this.selectedSurvey && this.selectedSurvey.title) || 'Survey';
    }

    get surveyQuestions() {
        const selectedSurvey = this.selectedSurvey;
        const questions =
            selectedSurvey && selectedSurvey.questions && selectedSurvey.questions.length
                ? selectedSurvey.questions
                : [];
        return [...questions].sort((a, b) => (a.order || a.displayId || 0) - (b.order || b.displayId || 0));
    }

    get currentQuestion() {
        return this.surveyQuestions[this.currentQuestionIndex];
    }

    get isLastQuestion() {
        return this.surveyQuestions.length > 0 && this.currentQuestionIndex === this.surveyQuestions.length - 1;
    }

    get isFirstQuestion() {
        return this.currentQuestionIndex === 0;
    }

    get isCheckboxQuestion() {
        return this.currentQuestion && this.currentQuestion.type === 'checkbox';
    }

    get isTextQuestion() {
        return this.currentQuestion && this.currentQuestion.type === 'text';
    }

    get isRatingQuestion() {
        return this.currentQuestion && this.currentQuestion.type === 'rating';
    }

    get isRadioQuestion() {
        return this.currentQuestion && this.currentQuestion.type === 'radio';
    }

    get showConditionalField() {
        return (
            this.currentQuestion &&
            this.currentQuestion.showConditionalField &&
            this.surveyAnswers[this.currentQuestion.id] === 'Yes'
        );
    }

    handleCheckboxChange(event) {
        const value = event.target.value;
        const checked = event.target.checked;
        const questionId = event.target.getAttribute('data-question-id');
        const existing = Array.isArray(this.surveyAnswers[questionId]) ? this.surveyAnswers[questionId] : [];

        let updated = existing;
        if (checked) {
            updated = [...existing, value];
        } else {
            updated = existing.filter((item) => item !== value);
        }

        this.surveyAnswers = { ...this.surveyAnswers, [questionId]: updated };
    }

    renderedCallback() {
        if (this.showFiltersPopup) {
            setTimeout(() => {
                this.positionPopup();
            }, 0);
        }
        
        // Update checkbox and radio states after render
        if (this.showSurveyForm && this.currentQuestion) {
            setTimeout(() => {
                this.updateInputStates();
            }, 0);
        }
    }

    updateInputStates() {
        if (!this.currentQuestion) return;
        
        const questionId = this.currentQuestion.id;
        const answer = this.surveyAnswers[questionId];

        if (this.isCheckboxQuestion) {
            const checkboxes = this.template.querySelectorAll(`input[type="checkbox"][data-question-id="${questionId}"]`);
            if (checkboxes) {
                checkboxes.forEach((checkbox) => {
                    checkbox.checked = Array.isArray(answer) && answer.includes(checkbox.value);
                });
            }
        }

        if (this.isRadioQuestion) {
            const radios = this.template.querySelectorAll(`input[type="radio"][data-question-id="${questionId}"]`);
            if (radios) {
                radios.forEach((radio) => {
                    radio.checked = answer === radio.value;
                });
            }
        }

        if (this.isTextQuestion) {
            const input = this.template.querySelector(`input[data-question-id="${questionId}"]`);
            if (input) {
                input.value = answer || '';
            }
        }

        if (this.currentQuestion && this.currentQuestion.showConditionalField) {
            const followUpId = this.currentQuestion.followUpQuestionId || `${questionId}-followup`;
            const input = this.template.querySelector(`input[data-question-id="${followUpId}"]`);
            if (input) {
                input.value = this.surveyAnswers[followUpId] || '';
            }
        }

        if (this.isRatingQuestion) {
            this.updateRatingButtons(questionId);
        }
    }

    updateRatingButtons(questionId) {
        setTimeout(() => {
            const ratingButtons = this.template.querySelectorAll(`.rating-btn[data-question-id="${questionId}"]`);
            const selectedValue = this.surveyAnswers[questionId];
            if (ratingButtons && ratingButtons.length > 0) {
                ratingButtons.forEach((btn) => {
                    const btnValue = parseInt(btn.getAttribute('data-rating-value'), 10);
                    if (btnValue === selectedValue) {
                        btn.classList.add('selected');
                    } else {
                        btn.classList.remove('selected');
                    }
                });
            }
        }, 0);
    }

    handleTextChange(event) {
        const value = event.target.value;
        const questionId = event.target.getAttribute('data-question-id');
        this.surveyAnswers = { ...this.surveyAnswers, [questionId]: value };
    }

    handleRatingClick(event) {
        const value = parseInt(event.currentTarget.getAttribute('data-rating-value'));
        const questionId =
            event.currentTarget.getAttribute('data-question-id') || (this.currentQuestion ? this.currentQuestion.id : null);
        if (!questionId) {
            return;
        }
        this.surveyAnswers = { ...this.surveyAnswers, [questionId]: value };
        this.updateRatingButtons(questionId);
    }


    handleRadioChange(event) {
        const value = event.target.value;
        const questionId = event.target.getAttribute('data-question-id');
        this.surveyAnswers = { ...this.surveyAnswers, [questionId]: value };
    }

    handleNext() {
        this.questionError = '';
        if (!this.surveyQuestions.length) {
            this.submitError = 'No questions available for this survey.';
            return;
        }
        if (this.currentQuestion.isRequired && !this.hasAnswer(this.currentQuestion)) {
            this.questionError = 'This question is required.';
            return;
        }
        if (this.isLastQuestion) {
            this.showSurveyForm = false;
            this.showSubmitConfirmation = true;
        } else {
            this.currentQuestionIndex++;
        }
    }

    handleBack() {
        if (this.isFirstQuestion) {
            this.showSurveyForm = false;
            this.showBeginSurveyDialog = true;
        } else {
            this.currentQuestionIndex--;
        }
    }

    handleReviewForm() {
        this.showSubmitConfirmation = false;
        this.showSurveyForm = true;
        this.submitError = '';
    }

    async handleConfirmSubmit() {
        this.showSubmitConfirmation = false;
        this.showSurveyForm = false;
        this.submitError = '';
        this.isSubmitting = true;

        try {
            // Validate all questions answered
            const unanswered = (this.surveyQuestions || []).filter(q => q.isRequired && !this.hasAnswer(q));
            if (unanswered.length) {
                throw new Error('Please answer all questions before submitting.');
            }
            const responses = this.buildResponsePayload();
            await submitSurveyResponses({
                request: {
                    surveyId: this.selectedSurveyId,
                    responses
                }
            });
            this.setSurveyCompletionFlag(this.selectedSurveyId, true);
            this.showBeginSurveyDialog = false;
            this.currentQuestionIndex = 0;
            this.surveyAnswers = {};
            this.showSuccessDialog = true;
            window.clearTimeout(this.successDialogTimeout);
            this.successDialogTimeout = window.setTimeout(() => {
                this.showSuccessDialog = false;
                this.showFeedbackDialog = true;
            }, 1200);
            await this.loadSurveys();
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Survey submission error', error);
            this.submitError = error?.body?.message || error?.message || 'Unable to submit survey.';
            this.showSurveyForm = true;
            this.showSubmitConfirmation = false;
        } finally {
            this.isSubmitting = false;
        }
    }

    buildResponsePayload() {
        const responses = [];
        const questions = this.surveyQuestions || [];
        questions.forEach((question) => {
            const answer = this.surveyAnswers[question.id];
            if (answer === undefined || answer === null || answer === '') {
                return;
            }
            const responseValue = Array.isArray(answer) ? answer.join('; ') : String(answer);
            responses.push({
                questionId: question.id,
                responseValue
            });
        });
        return responses;
    }

    handleCloseSuccessDialog() {
        this.showSuccessDialog = false;
        window.clearTimeout(this.successDialogTimeout);
        this.showFeedbackDialog = true;
    }

    handleCloseFeedbackDialog() {
        this.showFeedbackDialog = false;
        this.selectedSurveyId = null;
        this.currentQuestionIndex = 0;
        this.surveyAnswers = {};
    }

    handleRetakeSurveyFromFeedback() {
        this.showFeedbackDialog = false;
        this.currentQuestionIndex = 0;
        this.surveyAnswers = {};
        this.showBeginSurveyDialog = true;
    }

    handleExploreMoreSurveys() {
        this.showFeedbackDialog = false;
        this.selectedSurveyId = null;
        this.currentQuestionIndex = 0;
        this.surveyAnswers = {};
    }

    hasAnswer(question) {
        if (!question) {
            return false;
        }
        const answer = this.surveyAnswers[question.id];
        if (question.type === 'checkbox') {
            return Array.isArray(answer) && answer.length > 0;
        }
        return answer !== undefined && answer !== null && String(answer).trim() !== '';
    }

    handleDialogClick(event) {
        event.stopPropagation();
    }

    handleViewAll() {
        // Navigate to surveys list page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'all_surveys__c'
            }
        });
    }

    handleViewSurveyDetails(event) {
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

    handleCreateSurvey() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'create_survey__c'
            }
        });
    }

    handleRetakeSurvey(event) {
        const surveyId = event.currentTarget.getAttribute('data-survey-id');
        this.selectedSurveyId = surveyId;
        this.currentQuestionIndex = 0;
        this.surveyAnswers = {};
        this.showBeginSurveyDialog = true;
    }

    get statusOptions() {
        return [
            { label: 'All', value: 'all' },
            { label: 'Ongoing', value: 'ongoing' },
            { label: 'Completed', value: 'completed' }
        ];
    }

    get dateRangeOptions() {
        return [
            { label: 'All Time', value: 'all' },
            { label: 'Last 7 days', value: '7days' },
            { label: 'Last 30 days', value: '30days' },
            { label: 'Last 3 months', value: '3months' },
            { label: 'Last 6 months', value: '6months' }
        ];
    }

    get surveyFeedbackOptions() {
        return [
            { label: 'All', value: 'all' },
            { label: 'Survey', value: 'survey' },
            { label: 'Feedback', value: 'feedback' }
        ];
    }

    handleImageError(event) {
        // Fallback if image fails to load
        console.error('Failed to load Create New Survey image');
    }
}