import { LightningElement, track } from 'lwc';
import getJobPreferences from '@salesforce/apex/KenProfileSettingsController.getJobPreferences';
import saveJobPreferences from '@salesforce/apex/KenProfileSettingsController.saveJobPreferences';

const ALL_JOB_TITLES  = ['Software Engineer', 'Senior consultant', 'UX designer', 'Product Designer'];
const ALL_SKILLS      = ['C', 'C++', 'JAVA'];
const ALL_LOCATIONS   = ['Hyderabad', 'Bangalore', 'Chennai', 'Coimbatore'];
const LOCATION_TYPES  = ['Onsite', 'Hybrid', 'Remote'];
const EMPLOYMENT_TYPES = ['Full-time', 'Part-time', 'Contract', 'Internship', 'Temporary'];

export default class KenSettingJobs extends LightningElement {
    @track isLoading = true;
    @track isSaving  = false;
    @track showSuccessPopup = false;
    @track error = null;

    @track openToWork         = false;
    @track selectedJobTitles  = [];
    @track selectedSkills     = [];
    @track selectedLocations  = [];
    @track locationTypes      = [];
    @track employmentTypes    = [];

    @track showJobsDropdown      = false;
    @track showSkillsDropdown    = false;
    @track showLocationsDropdown = false;

    connectedCallback() {
        this.loadData();
        this._outsideClick = (e) => {
            if (this.template && !this.template.contains(e.target)) {
                this.showJobsDropdown = false;
                this.showSkillsDropdown = false;
                this.showLocationsDropdown = false;
            }
        };
        document.addEventListener('click', this._outsideClick);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._outsideClick);
    }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        try {
            const data = await getJobPreferences();
            this.openToWork        = data?.openToWork || false;
            this.selectedJobTitles = this._splitField(data?.preferredJobTitles);
            this.selectedSkills    = this._splitField(data?.skillSet);
            this.selectedLocations = this._splitField(data?.locationOnSite);
            this.locationTypes     = this._buildCheckboxList(LOCATION_TYPES,   data?.preferredLocationTypes);
            this.employmentTypes   = this._buildCheckboxList(EMPLOYMENT_TYPES, data?.employmentTypes);
        } catch (e) {
            this.error = e?.body?.message || 'Failed to load job preferences.';
        } finally {
            this.isLoading = false;
        }
    }

    _splitField(val) { return val ? val.split(';').map(v => v.trim()).filter(Boolean) : []; }

    _buildCheckboxList(options, savedValue) {
        const selected = new Set(savedValue ? savedValue.split(';').map(v => v.trim()) : []);
        return options.map(o => ({ label: o, value: o, checked: selected.has(o) }));
    }

    // ── Computed lists for dropdowns ──────────────────────────────────────────
    get availableJobTitles()  { return ALL_JOB_TITLES.filter(v => !this.selectedJobTitles.includes(v)); }
    get availableSkills()     { return ALL_SKILLS.filter(v => !this.selectedSkills.includes(v)); }
    get availableLocations()  { return ALL_LOCATIONS.filter(v => !this.selectedLocations.includes(v)); }

    get isJobTitlesEmpty()    { return this.selectedJobTitles.length === 0; }
    get isSkillsEmpty()       { return this.selectedSkills.length === 0; }
    get isLocationsEmpty()    { return this.selectedLocations.length === 0; }

    // ── Toggles ───────────────────────────────────────────────────────────────
    handleOpenToWorkChange(event) { this.openToWork = event.target.checked; }

    toggleJobsDropdown(event)      { event.stopPropagation(); this.showJobsDropdown = !this.showJobsDropdown; this.showSkillsDropdown = false; this.showLocationsDropdown = false; }
    toggleSkillsDropdown(event)    { event.stopPropagation(); this.showSkillsDropdown = !this.showSkillsDropdown; this.showJobsDropdown = false; this.showLocationsDropdown = false; }
    toggleLocationsDropdown(event) { event.stopPropagation(); this.showLocationsDropdown = !this.showLocationsDropdown; this.showJobsDropdown = false; this.showSkillsDropdown = false; }

    // ── Add / Remove ──────────────────────────────────────────────────────────
    addJobTitle(event)    { event.stopPropagation(); this.selectedJobTitles  = [...this.selectedJobTitles,  event.currentTarget.dataset.value]; this.showJobsDropdown = false; }
    addSkill(event)       { event.stopPropagation(); this.selectedSkills     = [...this.selectedSkills,     event.currentTarget.dataset.value]; this.showSkillsDropdown = false; }
    addLocation(event)    { event.stopPropagation(); this.selectedLocations  = [...this.selectedLocations,  event.currentTarget.dataset.value]; this.showLocationsDropdown = false; }

    handleRemoveJobTitle(event) { event.stopPropagation(); this.selectedJobTitles  = this.selectedJobTitles.filter(v => v !== event.currentTarget.dataset.title); }
    handleRemoveSkill(event)    { event.stopPropagation(); this.selectedSkills     = this.selectedSkills.filter(v => v !== event.currentTarget.dataset.skill); }
    handleRemoveLocation(event) { event.stopPropagation(); this.selectedLocations  = this.selectedLocations.filter(v => v !== event.currentTarget.dataset.location); }

    handleLocationTypeChange(event) {
        const val = event.target.dataset.value;
        this.locationTypes = this.locationTypes.map(o => o.value === val ? { ...o, checked: event.target.checked } : o);
    }

    handleEmploymentTypeChange(event) {
        const val = event.target.dataset.value;
        this.employmentTypes = this.employmentTypes.map(o => o.value === val ? { ...o, checked: event.target.checked } : o);
    }

    handleDiscard() { this.loadData(); }

    async handleSave() {
        this.isSaving = true;
        this.error = null;
        try {
            await saveJobPreferences({
                requestJson: JSON.stringify({
                    openToWork:             this.openToWork,
                    preferredJobTitles:     this.selectedJobTitles.join(';'),
                    skillSet:               this.selectedSkills.join(';'),
                    preferredLocationTypes: this.locationTypes.filter(o => o.checked).map(o => o.value).join(';'),
                    locationOnSite:         this.selectedLocations.join(';'),
                    employmentTypes:        this.employmentTypes.filter(o => o.checked).map(o => o.value).join(';')
                })
            });
            this.showSuccessPopup = true;
            setTimeout(() => { this.showSuccessPopup = false; }, 3000);
        } catch (e) {
            this.error = e?.body?.message || 'Failed to save.';
        } finally {
            this.isSaving = false;
        }
    }
}