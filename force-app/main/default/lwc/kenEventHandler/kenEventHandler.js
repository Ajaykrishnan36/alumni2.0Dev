/* eslint-disable max-lines */
/* eslint-disable class-methods-use-this */

import getOptions from '@salesforce/apex/KenEventFormController.getPicklistValues';
import saveData from '@salesforce/apex/KenEventFormController.saveData';
import { NavigationMixin as navigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { LightningElement, track, wire } from 'lwc';

const MAX_TEXT_LENGTH = 1000,
    MIN_TEXT_LENGTH = 10,
    ONE = 1,
    TWO = 2,
    ZERO = 0;


export default class KenEventHandler extends navigationMixin(LightningElement) {
    @track isEventGroup = false;
    @track isLoading = false;
    @track selectedValues = [];
    @track eventGroupId;
    @track imageUrl;
    @track imageFile;
    @track isFileInputVisible = true;
    @track fields = {
    agenda: '',
    contentDocumentId: '',
    description: '',
    enddate: '',
    eventGroupId: '',
    eventGroupTitle: '',
    eventTitle: '',
    eventTypes: '',
    id: '',
    image: '',
    imageFileName: '',
    isEventGroup: false,
    maximumNumberOfParticipants: null,
    startdate: ''
};

    @track parentOptions = [];
    @track apiname = 'Ken_Event_Master__c';
    @track objecticonname = 'standard:event';
    @track recordtype = 'Event_Group';

    @wire(getOptions, { fieldNames: ['Event_Type__c'], objectName: 'Ken_Event_Master__c' })
    wiredOptions({ error, data }) {
        if (data) {
            this.parentOptions = data?.Event_Type__c?.map(option => ({
         checked: false,
         label: option.label,
         show: true,
         value: option.label
        }));
        } else if (error) {
            this.showToast('Error', 'Failed to load picklist values.', 'error');
        }
    }

    handleCheckboxChange(event) {
        this.isLoading = true;
        this.isEventGroup = event.target.checked;
        this.fields.isEventGroup = this.isEventGroup;
        this.isLoading = false;
    }

    handleLookupUpdate(event) {
    const { selectedRecord } = event.detail || {};
    if (selectedRecord && selectedRecord.Id) {
        this.selectedRecordId = selectedRecord.Id;
        this.eventGroupId = selectedRecord.Id;
        this.fields.eventGroupId = this.eventGroupId;
    }
}

    handleSelection(event) {
        this.selectedValues = event.detail;
        this.fields.eventTypes = this.selectedValues;
    }

    handleInputChange(event) {
        const { dataset: { id: field }, value } = event.target;
        this.fields[field] = value;

        this.validateField(field, event.target);

        if (field === 'startdate' || field === 'enddate') {
            this.validateDateRange();
        }
    }

    // eslint-disable-next-line max-statements
    validateDateRange() {
        const end = this.fields.enddate,
            endInput = this.template.querySelector('[data-id="enddate"]'),
            start = this.fields.startdate,
           startInput = this.template.querySelector('[data-id="startdate"]'),
            today = new Date();

        today.setHours(ZERO, ZERO, ZERO, ZERO);

        let isValid = true;

        if (start) {
            const startDate = new Date(start);
            if (startDate < today) {
                this.setCustomValidity(startInput, false, 'Start Date cannot be in the past.');
                isValid = false;
            } else {
                this.setCustomValidity(startInput, true, '');
            }
        }

        if (end) {
            const endDate = new Date(end);
            if (endDate < today) {
                this.setCustomValidity(endInput, false, 'End Date cannot be in the past.');
                isValid = false;
            } else {
                this.setCustomValidity(endInput, true, '');
            }
        }

        if (start && end && new Date(start) > new Date(end)) {
            this.setCustomValidity(startInput, false, 'Start Date must be earlier than End Date.');
            this.setCustomValidity(endInput, false, 'End Date must be later than Start Date.');
            isValid = false;
        }

        return isValid;
    }

    handleCancel() {
        const evt = new ShowToastEvent({
           message: 'Canceled creating Event',
           title: 'Canceled',
           variant: 'error'
         });
        this.dispatchEvent(evt);
        history.back();
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSaveAndProceed() {
        if (this.imageFile) {
            this.fields.image = await this.convertToBase64(this.imageFile);
        }
        if (!this.validateEventFields() || !this.validateDateRange()) {
            this.showToast(
                'Error',
                'Please fix all the errors in the form before saving.',
                'error'
            );
            return;
        }

        saveData({ eventData: JSON.stringify(this.fields) })
            .then(result => {
                if(this.isEventGroup) {
                    this.showToast(
                        'Success',
                        'Event group created successfully',
                        'success'
                    );
                } else {
                    this.showToast(
                        'Success',
                        'Event created successfully',
                        'success'
                    );
                }
                this.fields.id = result;
                this.navigateToRecord(result);
            })
            .catch(() => {
                this.showToast('Error', 'Error saving data.', 'error');
            });
    }

    async handleSaveAsDraft() {
        if (this.imageFile) {
            this.fields.image = await this.convertToBase64(this.imageFile);
        }

        if (!this.validateEventFields() || !this.validateDateRange()) {
            this.showToast(
                'Error',
                'Please fix all the errors in the form before saving.',
                'error'
            );
            return;
        }

        saveData({ eventData: JSON.stringify(this.fields) })
            .then(result => {
                this.showToast(
                    'Success',
                    'Event saved as draft',
                    'success'
                );
                this.fields.id = result;
                this[navigationMixin.Navigate]({
            attributes: {
            actionName: 'view',
            objectApiName: 'Ken_Event_Master__c',
            recordId: result
            },
            type: 'standard__recordPage'
            });
            })
            .catch(() => {
                this.showToast('Error', 'Error saving data.', 'error');
            });
    }

    navigateToRecord(recordId) {
        if (this.isEventGroup) {
            this[navigationMixin.Navigate]({
               attributes: {
                  actionName: 'view',
                  objectApiName: 'Ken_Event_Master__c',
                  recordId
               },
              type: 'standard__recordPage'
            });
        } else {
            this[navigationMixin.Navigate]({
             attributes: {
              actionName: 'edit',
              objectApiName: 'Ken_Event_Master__c',
              recordId
              },
              type: 'standard__recordPage'
           });
        }

    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
         this.fields.contentDocumentId = uploadedFiles[ZERO].documentId;
    }

    handleFileChange(event) {
        const [file] = event.target.files;
        if (file) {
            this.createImagePreview(file);
            this.imageFile = file;
            this.fields.imageFileName = file.name;
            this.isFileInputVisible = false; 
        }
    }

    openFileDialog() {
        this.template.querySelector('input[type="file"]').click();
    }

    createImagePreview(file) {
        const reader = new FileReader();
        reader.onloadend = () => {
            this.imageUrl = reader.result;
        };
        reader.readAsDataURL(file);
    }

    removeImage() {
        this.imageUrl = null;
        this.imageFile = null;
        this.isFileInputVisible = true; 
    }

    convertToBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onloadend = () => resolve(reader.result.split(',')[ONE]);
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    validateEventFields() {
         const fieldsToValidate = [
            'description',
            'agenda',
            'enddate',
            'startdate',
            'maximumNumberOfParticipants'
        ];

        if (this.isEventGroup) {
        fieldsToValidate.push('eventGroupTitle');
        } else {
        fieldsToValidate.push('eventTitle');
        }

        let isValid = true;

        fieldsToValidate.forEach(field => {
            const inputField = this.template.querySelector(`[data-id="${field}"]`);
            if (!this.validateField(field, inputField)) {
                isValid = false;
            }
        });

        return isValid;
    }

    // eslint-disable-next-line max-statements
    validateField(field, inputElement) {
        const value = this.fields[field];

        if (!this.isValidInput(value)) {
            this.setCustomValidity(inputElement, false, 'This field is required.');
            return false;
        }

        if (
         (field === 'description' || field === 'agenda') &&
         (value.length < MIN_TEXT_LENGTH || value.length > MAX_TEXT_LENGTH)
         ) {
            this.setCustomValidity(inputElement, false, `${field} should be between ${MIN_TEXT_LENGTH} and ${MAX_TEXT_LENGTH} characters.`);
            return false;
        }

        if (field === 'maximumNumberOfParticipants' && Number(value) < ZERO) {
            this.setCustomValidity(inputElement, false, 'Maximum Number of Participants should be greater than 0.');
            return false;
        }

        this.setCustomValidity(inputElement, true, '');
        return true;
    }


    isValidInput(value) {
        return !(value === '' || value === null);
    }

    get todayDate() {
        // eslint-disable-next-line sort-vars
        const today = new Date(),
           dd = String(today.getDate()).padStart(TWO, '0'),
            mm = String(today.getMonth() + ONE).padStart(TWO, '0'),
            yyyy = today.getFullYear();
        return `${yyyy}-${mm}-${dd}`;
    }

    setCustomValidity(inputField, isValid, message) {
        if (inputField) {
            if (isValid) {
                inputField.setCustomValidity('');
            } else {
                inputField.setCustomValidity(message);
            }
            inputField.reportValidity();
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ message, title, variant }));
    }
}