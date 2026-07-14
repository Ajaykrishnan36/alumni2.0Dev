import { LightningElement, track } from 'lwc';

export default class MyProfilePersonalDetails extends LightningElement {
    // Component refresh
    @track firstName = 'Joshua';
    @track lastName = 'B';
    @track email = 'ganeshkumar@gmail.com';
    @track phoneNumber = '63794 16588';
    @track countryCode = '+91';
    @track city = 'Chennai';
    @track aboutMe = 'A product enthusiast based out of Chennai. I\'ve worked in a number of startups and helped them achieve crazy numbers.';
    @track linkedinLink = 'www.linkedin.com/in/';
    @track twitterLink = 'x.com/';

    // Placeholder flag URL (India)
    flagUrl = 'https://flagcdn.com/w20/in.png';

    // Modal State
    @track showPhotoModal = false;
    @track showEmailModal = false;
    @track showPhoneModal = false;
    @track showInterestsModal = false;
    @track showAboutMeModal = false;
    @track showSocialMediaModal = false;

    // Temp State for Editing
    @track tempEmail = '';
    @track tempPhone = '';
    @track tempCountryCode = '';
    @track tempAboutMe = '';
    @track tempLinkedin = '';
    @track tempTwitter = '';
    @track tempInterests = [];

    // Data Lists
    @track interests = [
        { id: 1, label: 'Learn from fellow alumni.', iconUrl: 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?q=80&w=100&auto=format&fit=crop', selected: true },
        { id: 2, label: 'Reconnect with my friends.', iconUrl: 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?q=80&w=100&auto=format&fit=crop', selected: true },
        { id: 3, label: 'Grow my professional network', iconUrl: 'https://images.unsplash.com/photo-1515169067750-d51a73e5bf0d?q=80&w=100&auto=format&fit=crop', selected: true }
    ];

    @track allInterests = [
        { id: 1, label: 'Learn from fellow alumni.', iconUrl: 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?q=80&w=100&auto=format&fit=crop', selected: true },
        { id: 2, label: 'Reconnect with my friends.', iconUrl: 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?q=80&w=100&auto=format&fit=crop', selected: true },
        { id: 4, label: 'Give back to the community.', iconUrl: 'https://images.unsplash.com/photo-1469571486292-0ba58a3f068b?q=80&w=100&auto=format&fit=crop', selected: false },
        { id: 5, label: 'Interested in hiring new talent.', iconUrl: 'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?q=80&w=100&auto=format&fit=crop', selected: false },
        { id: 6, label: 'Looking to find a new job.', iconUrl: 'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?q=80&w=100&auto=format&fit=crop', selected: false },
        { id: 3, label: 'Grow my professional network', iconUrl: 'https://images.unsplash.com/photo-1515169067750-d51a73e5bf0d?q=80&w=100&auto=format&fit=crop', selected: true }
    ];

    handleFirstNameChange(event) {
        this.firstName = event.target.value;
    }

    handleLastNameChange(event) {
        this.lastName = event.target.value;
    }

    handleCityChange(event) {
        this.city = event.target.value;
    }

    // Photo Modal
    handleEditPhoto() {
        this.showPhotoModal = true;
    }
    closePhotoModal() {
        this.showPhotoModal = false;
    }
    savePhoto() {
        // Mock save
        this.closePhotoModal();
    }

    // Email Modal
    handleEditEmail() {
        this.tempEmail = this.email;
        this.showEmailModal = true;
    }
    closeEmailModal() {
        this.showEmailModal = false;
    }
    handleEmailChange(event) {
        this.tempEmail = event.target.value;
    }
    saveEmail() {
        this.email = this.tempEmail;
        this.closeEmailModal();
    }

    // Phone Modal
    handleEditPhone() {
        this.tempPhone = this.phoneNumber;
        this.tempCountryCode = this.countryCode;
        this.showPhoneModal = true;
    }
    closePhoneModal() {
        this.showPhoneModal = false;
    }
    handlePhoneChange(event) {
        this.tempPhone = event.target.value;
    }
    savePhone() {
        this.phoneNumber = this.tempPhone;
        this.countryCode = this.tempCountryCode;
        this.closePhoneModal();
    }

    // Interests Modal
    handleEditInterests() {
        // Deep copy and add UI properties
        this.tempInterests = JSON.parse(JSON.stringify(this.allInterests)).map(item => ({
            ...item,
            checkboxClass: item.selected ? 'checkbox-custom checked' : 'checkbox-custom'
        }));
        this.showInterestsModal = true;
    }
    closeInterestsModal() {
        this.showInterestsModal = false;
    }
    toggleInterest(event) {
        const id = event.currentTarget.dataset.id;
        const index = this.tempInterests.findIndex(item => item.id == id);
        if (index !== -1) {
            this.tempInterests[index].selected = !this.tempInterests[index].selected;
            this.tempInterests[index].checkboxClass = this.tempInterests[index].selected ? 'checkbox-custom checked' : 'checkbox-custom';
        }
    }
    saveInterests() {
        // Save back to main state (strip UI props if needed, or keep them)
        this.allInterests = this.tempInterests.map(item => ({
            id: item.id,
            label: item.label,
            iconUrl: item.iconUrl,
            selected: item.selected
        }));
        this.interests = this.allInterests.filter(item => item.selected);
        this.closeInterestsModal();
    }

    // About Me Modal
    handleEditAboutMe() {
        this.tempAboutMe = this.aboutMe;
        this.showAboutMeModal = true;
    }
    closeAboutMeModal() {
        this.showAboutMeModal = false;
    }
    handleAboutMeChange(event) {
        this.tempAboutMe = event.target.value;
    }
    saveAboutMe() {
        this.aboutMe = this.tempAboutMe;
        this.closeAboutMeModal();
    }

    // Social Media Modal (Optional if needed based on design flow)
    handleEditSocialMedia() {
        this.tempLinkedin = this.linkedinLink;
        this.tempTwitter = this.twitterLink;
        this.showSocialMediaModal = true;
    }
    closeSocialMediaModal() {
        this.showSocialMediaModal = false;
    }
    handleLinkedinChange(event) {
        this.tempLinkedin = event.target.value;
    }
    handleTwitterChange(event) {
        this.tempTwitter = event.target.value;
    }
    saveSocialMedia() {
        this.linkedinLink = this.tempLinkedin;
        this.twitterLink = this.tempTwitter;
        this.closeSocialMediaModal();
    }
}