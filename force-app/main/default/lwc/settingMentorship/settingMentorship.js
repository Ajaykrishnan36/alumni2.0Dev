import { LightningElement, track } from 'lwc';

export default class SettingMentorship extends LightningElement {
    @track isMentor = false;
    @track selectedExpertise1 = '';
    @track selectedExpertise2 = '';
    @track maxMentees = 0;
    @track isUnlimited = true;
    @track showEmail = false;
    @track showContactNumber = false;

    @track communicationMethods = [
        { label: 'Email', value: 'email', checked: false },
        { label: 'SMS', value: 'sms', checked: false },
        { label: 'Whatsapp', value: 'whatsapp', checked: false },
        { label: 'In-Person Meeting', value: 'inperson', checked: false }
    ];

    expertiseOptions = [
        { label: 'Select expertise', value: '' },
        { label: 'Technology', value: 'technology' },
        { label: 'Business', value: 'business' },
        { label: 'Marketing', value: 'marketing' },
        { label: 'Finance', value: 'finance' },
        { label: 'Healthcare', value: 'healthcare' },
        { label: 'Education', value: 'education' },
        { label: 'Engineering', value: 'engineering' },
        { label: 'Design', value: 'design' }
    ];

    handleMentorToggle(event) {
        this.isMentor = event.target.checked;
    }

    get isDisabled() {
        return !this.isMentor;
    }

    handleExpertise1Change(event) {
        this.selectedExpertise1 = event.detail.value;
    }

    handleExpertise2Change(event) {
        this.selectedExpertise2 = event.detail.value;
    }

    handleCommunicationChange(event) {
        const value = event.target.dataset.value;
        this.communicationMethods = this.communicationMethods.map(method => {
            if (method.value === value) {
                return { ...method, checked: event.target.checked };
            }
            return method;
        });
    }

    incrementCount() {
        if (!this.isUnlimited) {
            this.maxMentees = (this.maxMentees || 0) + 1;
        }
    }

    decrementCount() {
        if (!this.isUnlimited && this.maxMentees > 0) {
            this.maxMentees = this.maxMentees - 1;
        }
    }

    handleMaxMenteesChange(event) {
        this.maxMentees = parseInt(event.target.value) || 0;
    }

    handleUnlimitedChange(event) {
        this.isUnlimited = event.target.checked;
        if (this.isUnlimited) {
            this.maxMentees = 0;
        }
    }

    handleShowEmailChange(event) {
        this.showEmail = event.target.checked;
    }

    handleShowContactNumberChange(event) {
        this.showContactNumber = event.target.checked;
    }
}