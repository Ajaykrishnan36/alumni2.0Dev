import { LightningElement, track } from 'lwc';

export default class KenOnboarding extends LightningElement {
    @track headerFirstName = '';
    @track headerLastName = '';
    @track headerProfileImageUrl = '';

    handleProfileChange(event) {
        const detail = event.detail || {};
        this.headerFirstName = detail.firstName || '';
        this.headerLastName = detail.lastName || '';
        this.headerProfileImageUrl = detail.profileImageUrl || '';
    }

    handleLogout() {
        // Logout is handled by the registration-header component
        // This method can be used for additional logout logic if needed
    }

    handleComplete() {
        // Handle completion of onboarding
        // The registration-stepper handles completion internally via opt-in modal
    }
}