import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getServiceOfferingDetail from '@salesforce/apex/KenServiceSupportController.getServiceOfferingDetail';
import saveQuestionnaireFromLwc from '@salesforce/apex/KenServiceSupportController.saveQuestionnaireFromLwc';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';
import {
    PORTAL_FILE_ACCEPT,
    PORTAL_FILE_TYPE_LABEL,
    validatePortalUploadFile
} from 'c/kenPortalFileValidation';

export default class KenRequestServiceDetailView extends NavigationMixin(LightningElement) {
    @track serviceItems = [];
    @track serviceDetails = [];
    @track selectedServiceId = '';
    @track selectedServiceTitle = '';
    @track serviceGroupTitle = '';
    @track questionList = [];
    @track isErrorToastVisible = false;
    @track errorTitle = 'Submission Failed';
    @track errorDescription = 'Something went wrong. Please try again.';
    @track isSubmitting = false;

    serviceId;
    errorTimer;
    fileAccept = PORTAL_FILE_ACCEPT;
    fileHint = `${PORTAL_FILE_TYPE_LABEL} (max 5 MB)`;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const urlServiceId = pageRef?.state?.serviceId;
        if (urlServiceId && urlServiceId !== this.serviceId) {
            this.serviceId = urlServiceId;
            this.loadServiceDetail();
        }
    }

    connectedCallback() {
        getColors().then(colors => {
            this.applyOrganizationTheme(colors);
        }).catch(() => {
            console.log('Error getting colors');
        });
        if (this.serviceId) this.loadServiceDetail();
    }

    disconnectedCallback() {
        window.clearTimeout(this.errorTimer);
    }

    get crumbs() {
        return [
            { label: 'Home', url: '' },
            { label: 'Service & Support', url: '/service-support' },
            { label: 'Request for a Service', pageName: 'request_service__c' },
            { label: this.selectedServiceTitle || 'Service Details' }
        ];
    }

    applyOrganizationTheme(colors) {
        if (!this.template?.host || !colors) return;
        const primary = colors.primary || colors.primaryColor;
        const secondary = colors.secondary || colors.secondaryColor;
        if (primary && typeof primary === 'string') {
            this.template.host.style.setProperty('--primary-color', primary);
        }
        if (secondary && typeof secondary === 'string') {
            this.template.host.style.setProperty('--secondary-color', secondary);
        }
    }

    loadServiceDetail() {
        if (!this.serviceId) return;
        getServiceOfferingDetail({ serviceId: this.serviceId })
            .then(result => {
                this.serviceDetails = result || [];
                if (this.serviceDetails.length === 0) {
                    this[NavigationMixin.Navigate]({
                        type: 'comm__namedPage',
                        attributes: { name: 'request_service__c' }
                    });
                    return;
                }
                this.serviceGroupTitle = this.serviceDetails[0]?.serviceName || '';
                this.initializeServiceItems();
            })
            .catch(error => {
                console.error('Service detail error', error);
                this.serviceDetails = [];
                this.serviceItems = [];
                this.selectedServiceId = '';
                this.selectedServiceTitle = '';
                this.serviceGroupTitle = '';
                this.questionList = [];
            });
    }

    initializeServiceItems() {
        const hasSelectedService = (this.serviceDetails || []).some(item => item.id === this.selectedServiceId);
        if (!hasSelectedService) {
            this.selectedServiceId = this.serviceDetails[0]?.id || '';
        }

        this.serviceItems = (this.serviceDetails || []).map(item => ({
            id: item.id,
            title: item.name,
            cssClass: item.id === this.selectedServiceId ? 'service-item-button active' : 'service-item-button'
        }));

        this.applySelection(this.selectedServiceId);
    }

    applySelection(itemId) {
        const selected = (this.serviceDetails || []).find(item => item.id === itemId) || this.serviceDetails[0];
        if (!selected) {
            this.selectedServiceId = '';
            this.selectedServiceTitle = '';
            this.questionList = [];
            return;
        }

        this.selectedServiceId = selected.id;
        this.selectedServiceTitle = selected.name;
        this.serviceGroupTitle = selected.serviceName || this.serviceGroupTitle;

        const questionnaire = (selected.questionnaire || []).filter(
            question => !this.shouldHideQuestion(selected, question)
        );
        this.questionList = questionnaire.map(q => this.buildQuestion(q));

        // Update active state
        this.serviceItems = this.serviceItems.map(item => ({
            ...item,
            cssClass: item.id === this.selectedServiceId ? 'service-item-button active' : 'service-item-button'
        }));
    }

    handleServiceItemClick(event) {
        const itemId = event.currentTarget.dataset.itemId;
        this.applySelection(itemId);
    }

    handleQuestionChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.target.value;
        this.updateQuestion(questionId, () => ({ value }));
    }

    handleFileUploadClick(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const fileInput = document.createElement('input');
        fileInput.type = 'file';
        fileInput.accept = PORTAL_FILE_ACCEPT;
        fileInput.style.display = 'none';

        fileInput.addEventListener('change', (e) => {
            const file = e.target.files?.[0];
            if (file) {
                const result = validatePortalUploadFile(file);
                if (!result.valid) {
                    this.updateQuestion(questionId, () => ({
                        value: null,
                        fileData: null,
                        fileName: null,
                        fileType: null,
                        fileSize: null,
                        fileError: result.error,
                        fileTouched: true
                    }));
                    document.body.removeChild(fileInput);
                    return;
                }

                const reader = new FileReader();
                reader.onload = () => {
                    const base64 = reader.result.split(',')[1];
                    this.updateQuestion(questionId, () => ({
                        value: file.name,
                        fileData: base64,
                        fileName: file.name,
                        fileType: (file.type || '').split('/')[1] || 'pdf',
                        fileSize: file.size,
                        fileError: '',
                        fileTouched: true
                    }));
                };
                reader.onerror = () => {
                    this.updateQuestion(questionId, () => ({
                        fileError: 'Unable to read the selected file. Please try again.',
                        fileTouched: true
                    }));
                };
                reader.readAsDataURL(file);
            } else {
                this.updateQuestion(questionId, () => ({
                    value: null,
                    fileData: null,
                    fileName: null,
                    fileType: null,
                    fileSize: null,
                    fileError: '',
                    fileTouched: true
                }));
            }
            document.body.removeChild(fileInput);
        });

        document.body.appendChild(fileInput);
        fileInput.click();
    }

    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'request_service__c'
            }
        });
    }

    handleSubmit() {
        if (!this.validateQuestionnaire()) {
            return;
        }

        // Prepare submission payload for simplified Apex endpoint
        const responses = this.questionList.map(q => ({
            questionId: q.id,
            value: q.showFileUpload ? null : q.value,
            fileData: q.showFileUpload ? q.fileData : null,
            fileName: q.fileName,
            fileType: q.fileType
        }));

        const caseRecord = {
            Subject: this.selectedServiceTitle || 'Service Request',
            Origin: 'Portal',
        };
        if (this.selectedServiceId) {
            caseRecord.Service_Offering__c = this.selectedServiceId;
        }

        // Always use the student's own constituentRoleId for case creation
        // (visitor contact is stored separately in localStorage as VisitorContactId)
        const constituentRoleId = localStorage.getItem('ConstituentRoleId');

        const submissionData = { caseRecord, responses, constituentRoleId };

        this.isSubmitting = true;
        saveQuestionnaireFromLwc({ requestPayloadJson: JSON.stringify(submissionData) })
            .then(() => {
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: { url: '/service-support?success=request' }
                });
            })
            .catch(err => {
                const message = err?.body?.message || err?.message || JSON.stringify(err);
                console.error('Questionnaire save error:', message);
                this.showToast(message, 'error');
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    buildQuestion(q) {
        const lowerType = (q.type || '').toLowerCase();
        const showFileUpload = lowerType === 'file upload';
        const isSubjectQuestion = (q.label || '').trim().toLowerCase() === 'subject';
        return {
            id: q.id,
            label: q.label,
            options: q.options,
            isRequired: q.isRequired,
            order: q.order,
            type: lowerType,
            optionList: this.parseOptions(q.options),
            value: lowerType === 'linear scale'
                ? '5'
                : (isSubjectQuestion ? this.selectedServiceTitle : null),
            fileData: null,
            fileName: null,
            fileType: null,
            fileSize: null,
            fileSize: null,
            fileError: '',
            fileTouched: false,
            requiredError: '',
            fileInputClass: 'file-input',
            showFileUpload,
            typeIsYesNo: ['yes/no', 'yes', 'no'].includes(lowerType),
            typeIsComment: lowerType === 'comment',
            typeIsShortAnswer: lowerType === 'short answer',
            typeIsMultipleChoice: lowerType === 'multiple choice',
            typeIsRating: lowerType === 'rating',
            typeIsDropdown: lowerType === 'dropdown',
            typeIsLinearScale: lowerType === 'linear scale',
            typeIsDate: lowerType === 'date',
            typeIsTime: lowerType === 'time',
            ratingOptions: lowerType === 'rating' ? ['1', '2', '3', '4', '5'] : []
        };
    }

    parseOptions(optionString) {
        if (!optionString) return [];
        return optionString.split(',').map(opt => opt.trim()).filter(opt => opt);
    }

    shouldHideQuestion(selectedService, question) {
        const serviceName = (selectedService?.serviceName || '').trim().toLowerCase();
        const questionLabel = (question?.label || '').trim().toLowerCase();

        return serviceName === 'it & digital services' && questionLabel === 'student id / username';
    }

    updateQuestion(questionId, updater) {
        this.questionList = this.questionList.map(q =>
            q.id === questionId ? { ...q, ...updater(q) } : q
        );
    }

    validateQuestionnaire() {
        let isValid = true;
        this.questionList = this.questionList.map((question) => {
            let fileError = question.fileError || '';
            let requiredError = '';

            if (question.showFileUpload) {
                if (question.isRequired && !question.fileData) {
                    requiredError = 'Please upload a document.';
                    isValid = false;
                } else if (question.fileData && question.fileName) {
                    const result = validatePortalUploadFile({
                        name: question.fileName,
                        type: '',
                        size: question.fileSize || this.estimateBase64FileSize(question.fileData)
                    });
                    if (!result.valid) {
                        fileError = result.error;
                        isValid = false;
                    }
                }
            } else if (question.isRequired && !question.value) {
                requiredError = 'This field is required.';
                isValid = false;
            }

            return {
                ...question,
                fileError,
                requiredError,
                fileInputClass: (fileError || requiredError) ? 'file-input form-input--invalid' : 'file-input',
                fileTouched: question.fileTouched || Boolean(fileError || requiredError)
            };
        });
        return isValid;
    }

    estimateBase64FileSize(base64Data) {
        if (!base64Data) {
            return 0;
        }
        const padding = base64Data.endsWith('==') ? 2 : (base64Data.endsWith('=') ? 1 : 0);
        return Math.floor((base64Data.length * 3) / 4) - padding;
    }

    showToast(message, variant) {
        if (variant === 'error') {
            this.errorDescription = message || this.errorDescription;
            this.isErrorToastVisible = true;
            window.clearTimeout(this.errorTimer);
            this.errorTimer = window.setTimeout(() => {
                this.isErrorToastVisible = false;
            }, 1500);
        }
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.isErrorToastVisible = false;
        }
    }
}