import { LightningElement, track, api } from 'lwc';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';
import getIssueTypes from '@salesforce/apex/KenServiceSupportController.getIssueTypes';
import {
    PORTAL_FILE_ACCEPT,
    PORTAL_FILE_TYPE_LABEL,
    validatePortalUploadFile
} from 'c/kenPortalFileValidation';

const DEFAULT_ISSUE_TYPE_OPTION = { label: 'Select', value: '' };
const OTHER_ISSUE_TYPE_OPTION = { label: 'Others', value: 'other' };

export default class KenNeedHelpModal extends LightningElement {
    @track issueTypeOptions = [DEFAULT_ISSUE_TYPE_OPTION, OTHER_ISSUE_TYPE_OPTION];
    // Selected Service Offering Id (the dropdown value) used to auto-route the Case owner.
    selectedServiceOfferingId = null;
    // Map of dropdown value (offering Id) -> display label, so the offering name is saved as text.
    issueTypeLabelByValue = { '': DEFAULT_ISSUE_TYPE_OPTION.label, other: OTHER_ISSUE_TYPE_OPTION.label };
    @track issueDescription = '';
    @track issueType = '';
    @track issueSubject = '';
    @track uploadedFile = null;
    @track uploadedFileName = '';
    @track isErrorToastVisible = false;
    @track errorTitle = 'Submission Failed';
    @track errorDescription = 'Something went wrong. Please try again.';
    errorTimer;
    fileAccept = PORTAL_FILE_ACCEPT;
    fileHint = `${PORTAL_FILE_TYPE_LABEL} (max 5 MB)`;
    @track validationErrors = {
        description: '',
        issueType: '',
        issueSubject: '',
        file: ''
    };

    connectedCallback() {
        this.loadIssueTypes();
        getColors().then(colors => {
            this.applyOrganizationTheme(colors);
        }).catch(() => {
            console.log('Error getting colors');
        });
    }

    loadIssueTypes() {
        const baseLabels = { '': DEFAULT_ISSUE_TYPE_OPTION.label, other: OTHER_ISSUE_TYPE_OPTION.label };
        getIssueTypes()
            .then(issueTypes => {
                const options = [DEFAULT_ISSUE_TYPE_OPTION];
                const labelByValue = { ...baseLabels };
                // Each option is a Service Offering: value = offering Id (drives owner
                // routing), label = offering name (shown + saved as text in description).
                (issueTypes || []).forEach(item => {
                    if (!item.serviceOfferingId) return;
                    options.push({ label: item.label, value: item.serviceOfferingId });
                    labelByValue[item.serviceOfferingId] = item.label;
                });
                options.push(OTHER_ISSUE_TYPE_OPTION);
                this.issueTypeOptions = options;
                this.issueTypeLabelByValue = labelByValue;
            })
            .catch(() => {
                this.issueTypeOptions = [DEFAULT_ISSUE_TYPE_OPTION, OTHER_ISSUE_TYPE_OPTION];
                this.issueTypeLabelByValue = { ...baseLabels };
            });
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

    handleDescriptionChange(event) {
        this.issueDescription = event.target.value;
        this.validateField('description', this.issueDescription);
    }

    handleIssueTypeChange(event) {
        this.issueType = event.target.value;
        // A real offering Id was chosen (not 'Select' or 'Others') -> use it for owner routing.
        this.selectedServiceOfferingId =
            this.issueType && this.issueType !== 'other' ? this.issueType : null;
        this.validateField('issueType', this.issueType);
    }

    handleIssueSubjectChange(event) {
        this.issueSubject = event.target.value;
        this.validateField('issueSubject', this.issueSubject);
    }

    handleFileUpload(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }

        const result = validatePortalUploadFile(file);
        if (!result.valid) {
            this.validationErrors.file = result.error;
            this.uploadedFile = null;
            this.uploadedFileName = '';
            event.target.value = '';
            return;
        }

        this.uploadedFile = file;
        this.uploadedFileName = file.name;
        this.validationErrors.file = '';
    }

    handleRemoveFile() {
        this.uploadedFile = null;
        this.uploadedFileName = '';
        this.validationErrors.file = '';
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) {
            fileInput.value = '';
        }
    }

    handleAutoCreateForm() {
        // Auto-fill form based on description using AI/ML
        // This would trigger an Apex method or external service
        // to auto-populate form fields based on description
        if (this.issueDescription && this.issueDescription.trim() !== '') {
            // Auto-populate logic would go here
            // For now, we can set a default issue type based on keywords
            const description = this.issueDescription.toLowerCase();
            if (description.includes('payment') || description.includes('pay')) {
                this.issueType = 'payment';
            } else if (description.includes('event') || description.includes('registration')) {
                this.issueType = 'event_registration';
            } else if (description.includes('account') || description.includes('login')) {
                this.issueType = 'account';
            } else if (description.includes('technical') || description.includes('system')) {
                this.issueType = 'technical';
            }
        }
    }

    handleCancel() {
        this.closeModal();
    }

    handleSubmit() {
        if (this.validateForm()) {
            // The dropdown value is an offering Id; resolve back to its name for the text.
            const issueTypeLabel = this.issueTypeLabelByValue[this.issueType] || this.issueType;
            const submitEvent = new CustomEvent('submit', {
                detail: {
                    description: this.issueDescription,
                    issueType: issueTypeLabel,
                    subject: this.issueSubject,
                    file: this.uploadedFile,
                    serviceOfferingId: this.selectedServiceOfferingId
                }
            });
            this.dispatchEvent(submitEvent);
        }
    }

    validateField(fieldName, value) {
        switch (fieldName) {
            case 'description':
                this.validationErrors.description = value && value.trim() ? '' : 'Description is required';
                break;
            case 'issueType':
                this.validationErrors.issueType = value ? '' : 'Please select an issue type';
                break;
            case 'issueSubject':
                this.validationErrors.issueSubject = value && value.trim() ? '' : 'Issue subject is required';
                break;
            default:
                break;
        }
    }

    validateForm() {
        this.validateField('description', this.issueDescription);
        this.validateField('issueType', this.issueType);
        this.validateField('issueSubject', this.issueSubject);
        this.validateUploadedFile();

        return !this.validationErrors.description &&
               !this.validationErrors.issueType &&
               !this.validationErrors.issueSubject &&
               !this.validationErrors.file;
    }

    validateUploadedFile() {
        if (!this.uploadedFile) {
            this.validationErrors.file = '';
            return;
        }
        const result = validatePortalUploadFile(this.uploadedFile);
        this.validationErrors.file = result.valid ? '' : result.error;
    }

    closeModal() {
        this.isErrorToastVisible = false;
        const closeEvent = new CustomEvent('close');
        this.dispatchEvent(closeEvent);
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.closeModal();
        }
    }

    @api
    showError(title, description) {
        this.errorTitle = title || this.errorTitle;
        this.errorDescription = description || this.errorDescription;
        this.isErrorToastVisible = true;
        window.clearTimeout(this.errorTimer);
        this.errorTimer = window.setTimeout(() => {
            this.isErrorToastVisible = false;
        }, 1500);
    }
}