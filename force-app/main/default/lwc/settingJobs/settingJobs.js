import { LightningElement, track } from 'lwc';

export default class SettingJobs extends LightningElement {
    @track openToWork = false;
    @track selectedJobTitles = [];
    @track inputJobTitles = [];
    @track jobTitleInput = '';
    @track showSuggestions = false;
    @track selectedSkills = [];
    @track skillInput = '';
    @track selectedLocations = [];
    @track locationSearch = '';

    @track locationTypes = [
        { label: 'On-site', value: 'onsite', checked: false },
        { label: 'Hybrid', value: 'hybrid', checked: false },
        { label: 'Remote', value: 'remote', checked: false }
    ];

    @track employmentTypes = [
        { label: 'Full-time', value: 'fulltime', checked: false },
        { label: 'Part-time', value: 'parttime', checked: false },
        { label: 'Contract', value: 'contract', checked: false },
        { label: 'Internship', value: 'internship', checked: false },
        { label: 'Temporary', value: 'temporary', checked: false }
    ];

    suggestedJobTitles = [
        'UX designer',
        'Product designer',
        'Experience designer',
        'UI developer',
        'UI Designers',
        'Java specialist',
        'Product manager',
        'HR Professional',
        'Photographer',
        'Senior graphic designer'
    ];

    locationOptions = [
        { label: 'Search', value: '' },
        { label: 'Chennai', value: 'chennai' },
        { label: 'Bangalore', value: 'bangalore' },
        { label: 'Mumbai', value: 'mumbai' },
        { label: 'Delhi', value: 'delhi' },
        { label: 'Hyderabad', value: 'hyderabad' },
        { label: 'Pune', value: 'pune' },
        { label: 'Kolkata', value: 'kolkata' }
    ];

    handleOpenToWorkChange(event) {
        this.openToWork = event.target.checked;
    }

    handleJobTitleInput(event) {
        this.jobTitleInput = event.target.value;
        this.showSuggestions = this.jobTitleInput.length > 0;
    }

    handleInputFocus() {
        if (this.jobTitleInput.length > 0) {
            this.showSuggestions = true;
        }
    }

    handleInputBlur() {
        // Delay to allow click on suggestions
        setTimeout(() => {
            this.showSuggestions = false;
        }, 200);
    }

    handleClearInput() {
        this.jobTitleInput = '';
        this.showSuggestions = false;
    }

    handleJobTitleKeyDown(event) {
        if (event.key === 'Enter' && this.jobTitleInput.trim()) {
            event.preventDefault();
            this.addJobTitle(this.jobTitleInput.trim());
            this.jobTitleInput = '';
            this.showSuggestions = false;
        } else if (event.key === 'Backspace' && !this.jobTitleInput && this.inputJobTitles.length > 0) {
            this.inputJobTitles = this.inputJobTitles.slice(0, -1);
        }
    }

    handleAddSuggestion(event) {
        const title = event.currentTarget.dataset.title;
        this.addJobTitle(title);
        this.jobTitleInput = '';
        this.showSuggestions = false;
    }

    addJobTitle(title) {
        if (!this.selectedJobTitles.includes(title) && !this.inputJobTitles.includes(title)) {
            this.inputJobTitles = [...this.inputJobTitles, title];
        }
    }

    handleRemoveJobTitle(event) {
        const title = event.currentTarget.dataset.title;
        this.selectedJobTitles = this.selectedJobTitles.filter(t => t !== title);
    }

    handleRemoveInputTitle(event) {
        const title = event.currentTarget.dataset.title;
        this.inputJobTitles = this.inputJobTitles.filter(t => t !== title);
    }

    handleSkillInput(event) {
        this.skillInput = event.target.value;
    }

    handleSkillKeyDown(event) {
        if (event.key === 'Enter' && this.skillInput.trim()) {
            event.preventDefault();
            const skill = this.skillInput.trim();
            if (!this.selectedSkills.includes(skill)) {
                this.selectedSkills = [...this.selectedSkills, skill];
            }
            this.skillInput = '';
        } else if (event.key === 'Backspace' && !this.skillInput && this.selectedSkills.length > 0) {
            this.selectedSkills = this.selectedSkills.slice(0, -1);
        }
    }

    handleRemoveSkill(event) {
        const skill = event.currentTarget.dataset.skill;
        this.selectedSkills = this.selectedSkills.filter(s => s !== skill);
    }

    handleLocationTypeChange(event) {
        const value = event.target.dataset.value;
        this.locationTypes = this.locationTypes.map(type => {
            if (type.value === value) {
                return { ...type, checked: event.target.checked };
            }
            return type;
        });
    }

    handleLocationSearchChange(event) {
        const location = event.detail.value;
        if (location && !this.selectedLocations.includes(location)) {
            this.selectedLocations = [...this.selectedLocations, location];
            this.locationSearch = '';
        }
    }

    handleRemoveLocation(event) {
        const location = event.currentTarget.dataset.location;
        this.selectedLocations = this.selectedLocations.filter(l => l !== location);
    }

    handleEmploymentTypeChange(event) {
        const value = event.target.dataset.value;
        this.employmentTypes = this.employmentTypes.map(type => {
            if (type.value === value) {
                return { ...type, checked: event.target.checked };
            }
            return type;
        });
    }

    handleSave() {
        // Move input titles to selected
        this.selectedJobTitles = [...this.selectedJobTitles, ...this.inputJobTitles];
        this.inputJobTitles = [];
        // Save logic here
    }

    handleDiscard() {
        // Reset logic here
        this.inputJobTitles = [];
        this.jobTitleInput = '';
    }
}