import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getSurveys from '@salesforce/apex/KenSurveyController.getSurveys';
import getEventFeedbackAsSurvey from '@salesforce/apex/KenSurveyController.getEventFeedbackAsSurvey';
import submitSurveyResponses from '@salesforce/apex/KenSurveyController.submitSurveyResponses';
// Module-record feedback (e.g. a mentorship call) is taken through this same form,
// so there is one feedback surface and no separate fill component.
import getModuleFeedbackForm from '@salesforce/apex/KenModuleFeedbackController.getModuleFeedbackForm';
import submitModuleFeedback from '@salesforce/apex/KenModuleFeedbackController.submitModuleFeedback';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenSurveyForm extends NavigationMixin(LightningElement) {
    @track surveyId;
    @track sessionId;
    @track moduleRecordId;   // a module record (e.g. mentorship call) whose feedback form we render
    returnUrl;               // where to go back to after submit (replaces hardcoded page redirects)
    @track survey;
    @track surveyAnswers = {};
    @track showSubmitConfirmation = false;
    @track isSubmitting = false;
    @track submitError = '';
    @track isAnonymous = false;
    @track isSuccessToastVisible = false;
    @track isErrorToastVisible = false;
    @track successTitle = 'Survey Submitted Successfully';
    @track successDescription = '';
    @track errorTitle = '';
    @track errorDescription = '';

    successTimeout;
    errorTimeout;
    navigateTimeout;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) return;
        const sessionFromState = currentPageReference.state?.sessionId;
        const surveyFromState = currentPageReference.state?.surveyId;
        // Use a custom key (recId) for the module-record mode — `recordId` is a
        // reserved Experience Cloud navigation key and doesn't pass through cleanly.
        const recordFromState = currentPageReference.state?.recId || currentPageReference.state?.recordId;
        // Capture where to return to after submit. Decoded because callers pass an
        // encoded absolute URL (e.g. the registration or mentorship page).
        const ret = currentPageReference.state?.returnUrl;
        if (ret) {
            try { this.returnUrl = decodeURIComponent(ret); } catch (e) { this.returnUrl = ret; }
        }
        // Participant whose "Fill" launched this (event registration) — used to mark
        // that participant's survey as submitted on the page we return to.
        this.participantId = currentPageReference.state?.participantId || null;
        if (sessionFromState) {
            this.sessionId = sessionFromState;
            this.surveyId = null;
            this.moduleRecordId = null;
            this.loadEventFeedback();
        } else if (recordFromState) {
            this.moduleRecordId = recordFromState;
            this.sessionId = null;
            this.surveyId = null;
            this.loadModuleFeedback();
        } else if (surveyFromState) {
            this.surveyId = surveyFromState;
            this.sessionId = null;
            this.moduleRecordId = null;
            this.loadSurvey();
        }
    }

    _markFeedbackSubmitted(recordId, participantId) {
        try {
            const key = 'kenFbSubmitted:' + recordId;
            const arr = JSON.parse(sessionStorage.getItem(key) || '[]');
            const pid = participantId || '__self__';
            if (!arr.includes(pid)) {
                arr.push(pid);
            }
            sessionStorage.setItem(key, JSON.stringify(arr));
        } catch (e) {
            /* sessionStorage unavailable — ignore */
        }
    }

    async loadModuleFeedback() {
        try {
            const data = await getModuleFeedbackForm({ recordId: this.moduleRecordId });
            if (data) {
                this.surveyId = data.surveyId;
                this.survey = {
                    id: data.surveyId,
                    title: data.name || data.sectionName,
                    questions: (data.questions || []).map((q, i) => this.mapQuestion({
                        id: q.id,
                        displayOrder: i + 1,
                        questionLabel: q.label,
                        questionType: q.type,
                        mcqOptions: q.options,
                        minGrade: q.minGrade,
                        maxGrade: q.maxGrade,
                        minGradeLabel: q.minGradeLabel,
                        maxGradeLabel: q.maxGradeLabel,
                        required: q.required
                    }, i))
                };
            }
        } catch (error) {
            console.error('Error loading module feedback:', error);
            this.showErrorToast(
                'Unable to load feedback',
                error?.body?.message || error?.message || 'Please try again later.'
            );
        }
    }

    async loadSurvey() {
        try {
            const value = localStorage.getItem('ConstituentRoleId');
            const allSurveys = await getSurveys({ constituentRoleId: value });
            const surveyData = allSurveys.find(survey => survey.id === this.surveyId);
            if (surveyData) {
                this.survey = this.transformSurveyData(surveyData);
            }
        } catch (error) {
            console.error('Error loading survey:', error);
        }
    }

    async loadEventFeedback() {
        try {
            const data = await getEventFeedbackAsSurvey({ sessionId: this.sessionId });
            if (data) {
                this.survey = this.transformSurveyData(data);
            }
        } catch (error) {
            console.error('Error loading event feedback:', error);
            this.showErrorToast(
                'Unable to load feedback',
                error?.body?.message || error?.message || 'Please try again later.'
            );
        }
    }

    transformSurveyData(surveyData) {
        // Transform survey data similar to surveys.js
        return {
            id: surveyData.id,
            title: surveyData.name || surveyData.sectionName,
            questions: this.mapQuestionsFromSurvey(surveyData.questionnaire?.parameters)
        };
    }

    mapQuestionsFromSurvey(questionList) {
        if (!questionList || !questionList.length) {
            return [];
        }
        return questionList.map((question, index) => this.mapQuestion(question, index));
    }

    mapQuestion(question, index) {
        const displayOrder = question.displayOrder != null ? Number(question.displayOrder) : index + 1;
        const type = this.mapQuestionType(question.questionType);
        return {
            id: question.id,
            displayId: displayOrder,
            question: question.questionLabel || '',
            type: type,
            options: this.buildOptions(question.questionType, question.mcqOptions),
            scale: this.buildScale(question),
            isRequired: question.required === true,
            isRating: type === 'rating',
            isRadio: type === 'radio',
            isCheckbox: type === 'checkbox',
            isText: type === 'text'
        };
    }

    mapQuestionType(questionType) {
        switch (questionType) {
            case 'Multiple Choice': return 'checkbox';
            case 'Dropdown': return 'radio';
            case 'Yes/No': return 'radio';
            case 'Rating':
            case 'Linear Scale': return 'rating';
            case 'Short Answer':
            case 'Comment':
            default: return 'text';
        }
    }

    buildOptions(questionType, mcqOptions) {
        if (questionType === 'Yes/No') {
            return ['Yes', 'No'];
        }
        if (!mcqOptions) return [];
        return mcqOptions.split(/[\n;,]+/).map(option => option.trim()).filter(option => option);
    }

    buildScale(question) {
        if (question.questionType === 'Rating' || question.questionType === 'Linear Scale') {
            const min = question.minGrade || 1;
            const max = question.maxGrade || 5;
            const minLabel = question.minGradeLabel || '';
            const maxLabel = question.maxGradeLabel || '';
            
            const scale = [];
            for (let i = min; i <= max; i++) {
                scale.push({ 
                    value: i, 
                    label: i === min ? minLabel : i === max ? maxLabel : '' 
                });
            }
            return scale;
        }
        return null;
    }

    get completedQuestions() {
        if (!this.survey?.questions) return 0;
        return this.survey.questions.filter(q => this.hasAnswer(q)).length;
    }

    get totalQuestions() {
        return this.survey?.questions?.length || 0;
    }

    get progressText() {
        return `${this.completedQuestions} of ${this.totalQuestions} questions completed`;
    }

    get progressBarStyle() {
        const percentage = this.totalQuestions > 0 ? (this.completedQuestions / this.totalQuestions) * 100 : 0;
        return `width: ${percentage}%`;
    }

    handleAnonymousToggle(event) {
        this.isAnonymous = event.target.checked;
    }

    handleAnswerChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.target.value;
        const checked = event.target.checked;
        const type = event.target.type;

        if (type === 'checkbox') {
            const existing = Array.isArray(this.surveyAnswers[questionId]) ? this.surveyAnswers[questionId] : [];
            let updated = existing;
            if (checked) {
                updated = [...existing, value];
            } else {
                updated = existing.filter(item => item !== value);
            }
            this.surveyAnswers = { ...this.surveyAnswers, [questionId]: updated };
        } else {
            this.surveyAnswers = { ...this.surveyAnswers, [questionId]: value };
        }
        
        // Update UI styling
        this.updateOptionStyling();
    }

    updateOptionStyling() {
        // This will be handled by CSS, but we can add classes if needed
        setTimeout(() => {
            const radioInputs = this.template.querySelectorAll('input[type="radio"]');
            radioInputs.forEach(input => {
                const optionItem = input.closest('.option-item');
                if (input.checked && optionItem) {
                    optionItem.classList.add('selected');
                } else if (optionItem) {
                    optionItem.classList.remove('selected');
                }
            });
            
            const checkboxInputs = this.template.querySelectorAll('input[type="checkbox"]');
            checkboxInputs.forEach(input => {
                const optionItem = input.closest('.option-item');
                if (input.checked && optionItem) {
                    optionItem.classList.add('selected');
                } else if (optionItem) {
                    optionItem.classList.remove('selected');
                }
            });
        }, 0);
    }

    handleRatingClick(event) {
        const value = parseInt(event.currentTarget.dataset.ratingValue);
        const questionId = event.currentTarget.dataset.questionId;
        this.surveyAnswers = { ...this.surveyAnswers, [questionId]: value };
        
        // Update button states
        const ratingButtons = this.template.querySelectorAll(`[data-question-id="${questionId}"]`);
        ratingButtons.forEach(btn => {
            if (btn.dataset.ratingValue) {
                const btnValue = parseInt(btn.dataset.ratingValue);
                if (btnValue === value) {
                    btn.classList.add('selected');
                } else {
                    btn.classList.remove('selected');
                }
            }
        });
    }

    hasAnswer(question) {
        if (!question) return false;
        const answer = this.surveyAnswers[question.id];
        if (question.type === 'checkbox') {
            return Array.isArray(answer) && answer.length > 0;
        }
        return answer !== undefined && answer !== null && String(answer).trim() !== '';
    }

    handleCancel() {
        if (this.sessionId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'registered_events__c' },
                state: { selectedTab: 'Completed' }
            });
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'all_surveys__c' }
        });
    }

    handleSubmit() {
        // Validate required questions
        const unansweredRequired = this.survey.questions.filter(q => q.isRequired && !this.hasAnswer(q));
        if (unansweredRequired.length > 0) {
            this.submitError = 'Please answer all required questions.';
            return;
        }
        
        this.showSubmitConfirmation = true;
    }

    handleConfirmSubmit() {
        this.confirmSubmit();
    }

    handleReviewForm() {
        this.showSubmitConfirmation = false;
        this.submitError = '';
    }

    async confirmSubmit() {
        this.isSubmitting = true;
        this.showSubmitConfirmation = false;

        try {
            const responses = this.buildResponsePayload();
            if (this.moduleRecordId) {
                // Module-record feedback (e.g. mentorship call) → write against the
                // record's per-record survey instance.
                await submitModuleFeedback({
                    request: { recordId: this.moduleRecordId, surveyId: this.surveyId, responses }
                });
            } else {
                const request = {
                    responses,
                    isAnonymous: this.isAnonymous
                };
                if (this.sessionId) {
                    request.sessionId = this.sessionId;
                } else {
                    request.surveyId = this.surveyId;
                }
                await submitSurveyResponses({ request });
            }

            // Record submission so the page we return to (e.g. event registration)
            // can flip the participant's "Fill" to "Submitted".
            if (this.moduleRecordId) {
                this._markFeedbackSubmitted(this.moduleRecordId, this.participantId);
            }

            const isEventFeedback = !!this.sessionId || !!this.moduleRecordId;
            this.showSuccessToast(
                isEventFeedback ? 'Feedback submitted' : 'Survey Submitted Successfully',
                isEventFeedback
                    ? `Thank you for your feedback on "${this.survey?.title || 'this event'}".`
                    : `Your response for "${this.survey?.title || 'this survey'}" has been submitted.`
            );

            window.clearTimeout(this.navigateTimeout);
            this.navigateTimeout = window.setTimeout(() => {
                // Return to wherever the user came from. Prefer an explicit returnUrl,
                // otherwise just go back in browser history — that lands on the previous
                // page for every entry point (event registration, surveys list,
                // mentorship) and keeps the survey-form URL short. Falls back to a
                // named page only when there's no history to return to.
                if (this.returnUrl) {
                    window.location.assign(this.returnUrl);
                } else if (typeof window !== 'undefined' && window.history && window.history.length > 1) {
                    window.history.back();
                } else if (isEventFeedback) {
                    this[NavigationMixin.Navigate]({
                        type: 'comm__namedPage',
                        attributes: { name: 'registered_events__c' },
                        state: { selectedTab: 'Completed' }
                    });
                } else {
                    this[NavigationMixin.Navigate]({
                        type: 'comm__namedPage',
                        attributes: { name: 'survey__c' },
                        state: {
                            surveyId: this.surveyId,
                            surveyTitle: this.survey?.title
                        }
                    });
                }
            }, 1500);

        } catch (error) {
            console.error('Survey submission error:', error);

            const message =
                error?.body?.message ||
                error?.message ||
                'Unable to submit survey. Please try again.';

            // Show error modal (and keep user on same page)
            this.showErrorToast('Submission Failed', message);

            // Optional: keep old inline footer error if you still want it
            this.submitError = message;

        } finally {
            this.isSubmitting = false;
        }
    }


    buildResponsePayload() {
        const responses = [];
        this.survey.questions.forEach(question => {
            const answer = this.surveyAnswers[question.id];
            if (answer === undefined || answer === null || answer === '') return;
            
            const responseValue = Array.isArray(answer) ? answer.join('; ') : String(answer);
            responses.push({
                questionId: question.id,
                responseValue
            });
        });
        return responses;
    }

    handleDialogClick(event) {
        event.stopPropagation();
    }

    renderedCallback() {
        // Update option styling after render
        this.updateOptionStyling();
        
        // Update rating button states
        if (this.survey && this.survey.questions) {
            this.survey.questions.forEach(question => {
                if (question.isRating) {
                    const questionId = question.id;
                    const selectedValue = this.surveyAnswers[questionId];
                    if (selectedValue !== undefined) {
                        setTimeout(() => {
                            const ratingButtons = this.template.querySelectorAll(`[data-question-id="${questionId}"].rating-btn`);
                            ratingButtons.forEach(btn => {
                                const btnValue = parseInt(btn.dataset.ratingValue);
                                if (btnValue === selectedValue) {
                                    btn.classList.add('selected');
                                } else {
                                    btn.classList.remove('selected');
                                }
                            });
                        }, 0);
                    }
                }
            });
        }
    }

    showSuccessToast(title, description) {
        this.successTitle = title;
        this.successDescription = description;
        this.isSuccessToastVisible = true;
        this.isErrorToastVisible = false;

        window.clearTimeout(this.successTimeout);
        this.successTimeout = window.setTimeout(() => {
            this.isSuccessToastVisible = false;
        }, 1500);
    }

    showErrorToast(title, description) {
        this.errorTitle = title;
        this.errorDescription = description;
        this.isErrorToastVisible = true;
        this.isSuccessToastVisible = false;

        window.clearTimeout(this.errorTimeout);
        this.errorTimeout = window.setTimeout(() => {
            this.isErrorToastVisible = false;
        }, 1500);
    }

    disconnectedCallback() {
        window.clearTimeout(this.successTimeout);
        window.clearTimeout(this.errorTimeout);
        window.clearTimeout(this.navigateTimeout);
    }

}