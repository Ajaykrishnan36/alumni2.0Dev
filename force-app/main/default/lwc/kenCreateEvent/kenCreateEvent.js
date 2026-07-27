/* eslint-disable max-lines, max-statements, one-var, sort-vars  */

import { refreshApex } from '@salesforce/apex';
import getEvent from '@salesforce/apex/KenEventFormController.getEvent';
import getFileUploadSettings from '@salesforce/apex/KenEventFormController.getFileUploadSettings';
import getPicklistValuesByFields from '@salesforce/apex/KenEventFormController.getPicklistValues';
import updateEvent from '@salesforce/apex/KenEventFormController.saveEvent';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { api, LightningElement, track, wire } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
const BASE64_DATA_INDEX = 1,
  BYTES_IN_KB = 1024,
  BYTES_IN_MB = BYTES_IN_KB * BYTES_IN_KB,
  CHILD_INIT_DELAY_MS = 2000,
  MONTH_OFFSET = 1,
  TEXTAREA_MAX_CHARS = 1000,
  TEXTAREA_MIN_CHARS = 10,
  TWO_DIGITS = 2,
  ZERO = 0;

/* eslint-disable no-console */
// eslint-disable-next-line one-var
const logger = {
   error(...args) { 
     console.error('[CreateEvent]', ...args);
   },
   info(...args) {
     console.info('[CreateEvent]', ...args);
   },
   warn(...args) {
     console.warn('[CreateEvent]', ...args);
   }
 };
/* eslint-enable no-console */

/* eslint-disable new-cap */ 
export default class KenCreateEvent extends NavigationMixin(LightningElement) 
/* eslint-enable new-cap */
{
  @api eventRecordId;
  @api isEventSetup;
  @track wiredProgram;
  @track suitableForOptions = [];
  @track isEventGroup = false;
  @track selectedCategories = [];
  @track selectedLanguages = [];
  @track eventDetails;
  @track imageUrl;
  @track imageFile;
  @track isFileInputVisible = true;
  @track existingEventType;
  @track eventfields = {
    agenda: '',
    contentDocumentId: null,
    description: '',
    enddate: null,
    eventExpectations: '',
    eventGroupId: null,
    eventGroupTitle: '',
    eventLanguages: '',
    eventTitle: '',
    eventTypes: '',
    id: '',
    image: null,
    imageFileName: '',
    isPortal: false,
    isEventGroup: false,
    maximumNumberOfParticipants: null,
    startdate: null
  };
  showSpinner = true;
  suitableFor;
  acceptedBannerFormats = [];
  maxBannerSize;
  @track eventCategories = [];
  @track eventLanguages = [];
  hasRendered = false;
  wiredEventResult;
  eventRecordTypeId;

  connectedCallback() {
    getPrimaryColor().then(color => {
      document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
      document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
      document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
    }).catch(() => {
      
    });
  }

  @wire(getEvent, { recordId: '$eventRecordId' })
  wiredEvent(result) {
    this.wiredEventResult = result;
    const { data, error } = result;
    if (data) {
      try {
        this.eventDetails = data;
 this.assignFields(data);

 if (data.eventTypes === null || typeof data.eventTypes === 'undefined') {
   this.selectedCategories = [];
 } else {
   this.selectedCategories = data.eventTypes;
 }

 if (data.eventLanguages === null || typeof data.eventLanguages === 'undefined') {
   this.selectedLanguages = [];
 } else {
   this.selectedLanguages = data.eventLanguages;
 }
        this.imageUrl = data.image;
        if (this.imageUrl === null || typeof this.imageUrl === 'undefined') {
         this.isFileInputVisible = true;
        } else {
        this.isFileInputVisible = false;
       }
        this.getPicklistOptions();
      } catch {
        this.showToast('Error', 'Failed to load Event Data, Please try again.', 'error');
      }
    } else if (error) {
      this.showToast('Error', 'Failed to load Event Data, Please try again.', 'error');
    }
    this.showSpinner = false;
  }

  @wire(getFileUploadSettings, { allowedFileTypes: 'Event_Banner_File_Types__c', maxFileSize: 'Event_Banner_File_Size_MB__c' })
  fileUploadSettings({ error, data }) {
    if (data) {
      this.acceptedBannerFormats = data?.allowedFileTypes?.toLowerCase().split(',');
      this.maxBannerSize = parseInt(data?.maxFileSize, 10) * BYTES_IN_MB;
    } else if (error) {
      this.showToast('Error', 'Error fetching file upload settings', 'error');
    }
  }

  renderedCallback() {
    if (this.hasRendered) {
      return;
    }
    this.hasRendered = true;
    this.initializeChildComponents('eventTypeSelect');
    this.initializeChildComponents('languageSelect');
  }


  handleInputChange(event) {
    const { dataset, value } = event.target,
   { id: field } = dataset;
    this.eventfields[field] = value;
    this.validateField(field, event.target);

    if (field === 'startdate' || field === 'enddate') {
      this.validateDateRange();
    }
  }

  handleCategorySelection(event) {
    this.selectedCategories = event.detail;
    this.eventfields.eventTypes = this.selectedCategories;
    const eventTypesSelected = this.template.querySelector('[data-id="eventTypeSelect"]');
    if (eventTypesSelected)
    {
      eventTypesSelected.validate();
    }
  }

  handleLanguageSelection(event) {
    this.selectedLanguages = event.detail;
    this.eventfields.eventLanguages = this.selectedLanguages;
    const languagesSelected = this.template.querySelector('[data-id="languageSelect"]');
    if (languagesSelected)
    {
      languagesSelected.validate();
    }
  }

  handleCheckboxChange(event) {
    this.isEventGroup = event.target.checked;
  }

  handleFileChange(event) {
    /* eslint-disable sort-vars */
    const { files } = event.target,
  [file] = files,
  parts = file.name.split('.'),
  fileExtension = parts.pop();

if (!file) {
  return;
}
    if (
      this.acceptedBannerFormats &&
      !this.acceptedBannerFormats.includes(fileExtension.toLowerCase())
    ) {
      const maxMB = this.maxBannerSize / BYTES_IN_MB;
      this.showToast(
        'Error',
        `File size exceeds the maximum limit. Please upload a file with size less than ${maxMB}MB.`,
        'error'
      );
      event.target.value = '';
      return;
    }


    if (this.maxBannerSize && file.size > this.maxBannerSize) {
      const maxMB = this.maxBannerSize / BYTES_IN_MB;
      this.showToast(
        'Error',
        `File size exceeds the maximum limit. Please upload a file with size less than ${maxMB}MB.`,
        'error'
      );
      event.target.value = '';
      return;
    }

    this.createImagePreview(file);
    this.imageFile = file;
    this.convertToBase64(file)
      .then(base64Image => {
        this.eventfields.image = base64Image; 
        this.eventfields.imageFileName = file.name;
      })
      .catch(error => {
        logger.warn('Error converting image to Base64', error);
      });
    this.isFileInputVisible = false; 
  }

  async handleSaveAsDraft() {

    if (!this.validateEventFields() || !this.validateDateRange()) {
      this.showToast(
        'Error',
        'Please fix all the errors in the form before saving.',
        'error'
      );
      return;
    }

    this.showSpinner = true;
    try {
      // backend flow: keep portal flag false
      this.eventfields.isPortal = false;
      await updateEvent({ eventData: JSON.stringify(this.eventfields) })

      this[NavigationMixin.Navigate]({
        attributes: {
        actionName: 'view',
        objectApiName: 'Ken_Event_Master__c',
        recordId: this.eventRecordId
       },
      type: 'standard__recordPage'
      });
    } catch {
      this.showToast('Error', 'Error saving record', 'error');
    } finally {
      this.showSpinner = false;
    }
  }

  async handleSave() {
    if (!this.validateEventFields() || !this.validateDateRange()) {
      this.showToast(
        'Error',
        'Please fix all the errors in the form before saving.',
        'error'
      );
      return;
    }

    this.showSpinner = true;

    try {
      // backend flow: keep portal flag false
      this.eventfields.isPortal = false;
      await updateEvent({ eventData: JSON.stringify(this.eventfields) })

      this.showToast('Success', 'Event Data saved successfully', 'success');

      await refreshApex(this.wiredEventResult);

      this.dispatchEvent(
        new CustomEvent("event", {
          detail: { eventId: this.eventRecordId }
        })
      );
    } catch  {
      this.showToast('Error', 'Error saving record', 'error');
    } finally {
      this.showSpinner = false;
    }
  }

  handleCancel() {
    if (this.eventRecordId) {
      this[NavigationMixin.Navigate]({
      attributes: {
      actionName: 'view',
      recordId: this.eventRecordId
    },
     type: 'standard__recordPage'
    });
    } else {
      this[NavigationMixin.Navigate]({
        attributes: {
        actionName: 'list',
        objectApiName: 'Ken_Event_Master__c'
       },
        state: {
          filterName: "Recent"
        },
        type: 'standard__objectPage'
      });
    }
  }

  handlePrevious() {
    this.dispatchEvent(new CustomEvent("previous", { detail: "eventSetup" }));
  }

  async getPicklistOptions() {
    const picklistData = await getPicklistValuesByFields({ fieldNames: ['Event_Type__c', 'Language__c'], objectName: 'Ken_Event_Master__c' });
    if (!picklistData) {
      this.showToast('Error', 'Error fetching picklist values', 'error');
      return;
    }

    this.eventLanguages = this.formatPicklistValues(picklistData.Language__c, this.selectedLanguages);
    this.eventCategories = this.formatPicklistValues(picklistData.Event_Type__c, this.selectedCategories);
  }

  /* eslint-disable class-methods-use-this */
  formatPicklistValues(picklistOptions, selectedValues) {
    if (!Array.isArray(picklistOptions)) {
      return [];
    }
    return picklistOptions?.map(option => (
      { checked: selectedValues.includes(option.value), label: option.label, show: true, value: option.value }));
  }

  initializeChildComponents(dataid) {
    setTimeout(() => {
      const childComponent = this.template.querySelector(`[data-id="${dataid}"]`);
      if (childComponent) {
        childComponent.postSelect();
      } else {
        logger.warn('Child component not found');
      }
    }, CHILD_INIT_DELAY_MS);
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
    this.eventfields.image = null;
    this.isFileInputVisible = true; 
  }

  /* eslint-disable class-methods-use-this */
  convertToBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => {
      const dataUrl = reader.result || '',
       parts = String(dataUrl).split(',');
      resolve(parts[BASE64_DATA_INDEX] || '');
     };
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }
  /* eslint-disable class-methods-use-this */

  assignFields(data) {
  this.eventfields = {
    ...this.eventfields,
    agenda: data.agenda,
    description: data.description,
    enddate: data.enddate,
    eventExpectations: data.eventExpectations,
    eventLanguages: data.eventLanguages,
    eventTitle: data.eventTitle,
    eventTypes: data.eventTypes,
    id: data.id,
    maximumNumberOfParticipants: data.maximumNumberOfParticipants,
    startdate: data.startdate
  };
}

  validateField(field, inputElement) {
    /* eslint-disable sort-vars */
    const value = this.eventfields[field],
    isEmpty = value === '' || value === null || typeof value === 'undefined';

    if (isEmpty) {
      this.setCustomValidity(inputElement, false, 'This field is required.');
      return false;
    }

    if (field === 'maximumNumberOfParticipants' && Number(value) <= ZERO) {
      this.setCustomValidity(inputElement, false, 'Must be greater than 0.');
      return false;
    }

    if ((field === 'description' || field === 'agenda') &&
        (value.length < TEXTAREA_MIN_CHARS || value.length > TEXTAREA_MAX_CHARS)) {
          /* eslint-disable no-magic-numbers */
      this.setCustomValidity(inputElement, false, `${field.charAt(0).toUpperCase() + field.slice(1)} must be between 10 and 1000 characters.`);
      /* eslint-enable no-magic-numbers */
      return false;
    }

    this.setCustomValidity(inputElement, true, '');
    return true;
  }

  /* eslint-disable sort-vars */
  validateEventFields() {
    const fieldsToValidate = [
      'eventTitle',
      'maximumNumberOfParticipants',
      'description',
      'enddate',
      'startdate',
      'agenda',
      'eventExpectations'
    ];

    let isValid = true;

    fieldsToValidate.forEach(field => {
      const inputField = this.template.querySelector(`[data-id="${field}"]`);
      if (!this.validateField(field, inputField)) {
        isValid = false;
      }
    });

    const eventTypes = this.template.querySelector('[data-id="eventTypeSelect"]'),
  languages = this.template.querySelector('[data-id="languageSelect"]');

if (eventTypes && !eventTypes.validate()) {
  isValid = false;
}

if (languages && !languages.validate()) {
  isValid = false;
}

    return isValid;
  }
  /* eslint-enable sort-vars */

  validateDateRange() {
    const end = this.eventfields.enddate,
      endInput = this.template.querySelector('[data-id="enddate"]'),
      start = this.eventfields.startdate,
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

  /* eslint-disable class-methods-use-this */
  get todayDate() {
    const [dd, mm, yyyy] = (() => {
      const today = new Date();
      return [
        String(today.getDate()).padStart(TWO_DIGITS, 'ZERO'),
        String(today.getMonth() + MONTH_OFFSET).padStart(TWO_DIGITS, 'ZERO'),
        today.getFullYear()
      ];
    })();

    return `${yyyy}-${mm}-${dd}`;
  }
  /* eslint-disable class-methods-use-this */


  /* eslint-disable class-methods-use-this */
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
  /* eslint-disable class-methods-use-this */

  showToast(title, successMessage, variant) {
    const toastEvent = new ShowToastEvent({
    message: successMessage,
    title,
    variant
    });
    this.dispatchEvent(toastEvent);
  }
}