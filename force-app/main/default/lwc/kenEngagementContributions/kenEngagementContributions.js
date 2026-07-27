import { LightningElement, track, api, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import KEN_ALUMNI_CRM_OBJECT from '@salesforce/schema/Ken_Alumni_CRM__c';
import PREF_FIELD from '@salesforce/schema/Ken_Alumni_CRM__c.Preferences__c';
import donateImg from '@salesforce/resourceUrl/donateImg';
import eventTest1 from '@salesforce/resourceUrl/eventTest1';
import eventTest2 from '@salesforce/resourceUrl/eventTest2';
import PortalLoginImage from '@salesforce/resourceUrl/PortalLoginImage';
import requestServiceImg from '@salesforce/resourceUrl/requestServiceImg';
import suggestedGroupsbgimage from '@salesforce/resourceUrl/suggestedGroupsbgimage';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getEngagementOptions from '@salesforce/apex/KenEngagementPreferenceController.getOptions';

// Fallback images used when a Ken_Engagement_Preference__c record has no
// Image URL set, so a card always renders an image.
const DEFAULT_IMAGES = [donateImg, eventTest1, eventTest2, PortalLoginImage, requestServiceImg, suggestedGroupsbgimage];

// Rendered only if the object has no active records / can't be read, so the
// step is never blank.
const FALLBACK_OPTIONS = [
    { id: 'f1', name: 'Learn from fellow alumni', image: donateImg, checked: false },
    { id: 'f2', name: 'Reconnect with my friends', image: eventTest1, checked: false },
    { id: 'f3', name: 'Give back to the community', image: eventTest2, checked: false },
    { id: 'f4', name: 'Interested in hiring new talent', image: PortalLoginImage, checked: false },
    { id: 'f5', name: 'Looking to find a new job', image: requestServiceImg, checked: false },
    { id: 'f6', name: 'Grow my professional network', image: suggestedGroupsbgimage, checked: false }
];

export default class KenEngagementContributions extends LightningElement {
    @track joinNetwork = 'Yes';
    @track speakAtEvents = 'Yes';
    @track featuredInStories = 'Yes';
    @track researchPartner = 'Yes';
    @track selectedActivities = [];
    @track engagementActivities = [];
    baseActivities = [];

    // Loaded from Ken_Engagement_Preference__c (see loadEngagementOptions).
    @track engagementOptions = [];
    // Names selected via prefill, applied once options load.
    _selectedNames = new Set();
    _optionsLoaded = false;

    yesNoOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    @api
    set activityOptions(options) {
        this.baseActivities = Array.isArray(options) ? options : [];
        this.rebuildActivities();
    }

    get activityOptions() {
        return this.baseActivities;
    }

    @wire(getObjectInfo, { objectApiName: KEN_ALUMNI_CRM_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: PREF_FIELD
    })
    wiredPreferences({ data, error }) {
        if (data && data.values) {
            this.activityOptions = data.values.map(v => ({ label: v.label, value: v.value }));
        } else if (error) {
            console.error('Error loading engagement picklist', error);
        }
    }

    rebuildActivities() {
        const selected = new Set(this.selectedActivities);
        this.engagementActivities = this.baseActivities.map(activity => ({
            ...activity,
            checked: selected.has(activity.value)
        }));
    }

    handleRadioChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    // If a record's Image URL fails to load, fall back to a bundled image.
    handleImageError(event) {
        if (event?.target) {
            event.target.src = donateImg;
        }
    }

    handleCheckboxChange(event) {
        const value = event.target.dataset.value;
        if (event.target.checked) {
            this.selectedActivities = [...new Set([...this.selectedActivities, value])];
        } else {
            this.selectedActivities = this.selectedActivities.filter(v => v !== value);
        }
        this.rebuildActivities();
    }

    handleCardClick(event) {
        const card = event.currentTarget;
        const optionId = card.dataset.optionId;
        if (optionId) {
            this.toggleOption(optionId);
        }
    }

    handleCardKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            const card = event.currentTarget;
            const optionId = card.dataset.optionId;
            if (optionId) {
                this.toggleOption(optionId);
            }
        }
    }

    handleOptionChange(event) {
        event.stopPropagation();
        const optionId = event.target.dataset.optionId;
        if (optionId) {
            this.toggleOption(optionId);
        }
    }

    toggleOption(optionId) {
        this.engagementOptions = this.engagementOptions.map(option => {
            if (String(option.id) === String(optionId)) {
                const checked = !option.checked;
                if (checked) this._selectedNames.add(option.name);
                else this._selectedNames.delete(option.name);
                return { ...option, checked };
            }
            return option;
        });
    }

    loadEngagementOptions() {
        return getEngagementOptions()
            .then(records => {
                const list = Array.isArray(records) ? records : [];
                if (list.length) {
                    this.engagementOptions = list.map((r, i) => ({
                        id: r.id,
                        name: r.name,
                        image: r.imageUrl || DEFAULT_IMAGES[i % DEFAULT_IMAGES.length],
                        iconUrl: r.iconUrl,
                        email: r.email,
                        checked: this._selectedNames.has(r.name)
                    }));
                } else {
                    this.applyFallbackOptions();
                }
            })
            .catch(error => {
                console.error('Error loading engagement preference options', error);
                this.applyFallbackOptions();
            })
            .finally(() => {
                this._optionsLoaded = true;
            });
    }

    applyFallbackOptions() {
        this.engagementOptions = FALLBACK_OPTIONS.map(o => ({
            ...o,
            checked: this._selectedNames.has(o.name)
        }));
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous', { bubbles: true, composed: true }));
    }

    handleSaveAndNext() {
        // Get selected options from new design
        const selectedOptions = this.engagementOptions
            .filter(option => option.checked)
            .map(option => option.name);

        // Also include old form data if needed
        const selectedActivities = this.engagementActivities
            .filter(activity => activity.checked)
            .map(activity => activity.value);
        this.selectedActivities = selectedActivities;

        const selectedPreferences = [...selectedActivities, ...selectedOptions];
        const preferences = [...new Set(selectedPreferences)].join(';');
        const formData = { preferences };

        this.dispatchEvent(new CustomEvent('saveandnext', {
            detail: formData,
            bubbles: true,
            composed: true
        }));
    }

    @api
    setEngagementData(data) {
        if (!data) {
            return;
        }
        if (data.joinNetwork) this.joinNetwork = data.joinNetwork;
        if (data.speakAtEvents) this.speakAtEvents = data.speakAtEvents;
        if (data.featuredInStories) this.featuredInStories = data.featuredInStories;
        if (data.researchPartner) this.researchPartner = data.researchPartner;

        let activities = [];
        if (data.preferences) {
            activities = data.preferences.split(';').map(v => v.trim()).filter(v => v);
        } else if (data.engagementActivities && Array.isArray(data.engagementActivities)) {
            activities = data.engagementActivities;
        }
        if (activities.length) {
            this.selectedActivities = [...new Set(activities)];
            this._selectedNames = new Set(this.selectedActivities);
            // Mark matching cards checked. If options haven't loaded yet, the
            // selection is re-applied when loadEngagementOptions resolves.
            this.engagementOptions = this.engagementOptions.map(opt => ({
                ...opt,
                checked: this._selectedNames.has(opt.name)
            }));
            this.rebuildActivities();
        }
    }
    connectedCallback() {
        this.loadEngagementOptions();
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
}