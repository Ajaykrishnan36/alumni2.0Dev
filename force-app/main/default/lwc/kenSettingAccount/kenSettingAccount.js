import { LightningElement, track } from 'lwc';
import celebrateResource from '@salesforce/resourceUrl/celebrate';

export default class KenSettingAccount extends LightningElement {
    @track isDeleteModalOpen = false;
    @track isFeedbackModalOpen = false;
    @track deleteReason = '';
    @track otpInput = '';
    @track feedbackText = '';

    celebrateGifUrl = celebrateResource;

    handleTermsClick() {
        // Navigate to terms of Service
    }

    handlePrivacyClick() {
        // Navigate to Privacy Policy
    }

    handleDeleteAccountClick() {
        this.isDeleteModalOpen = true;
    }

    closeDeleteModal() {
        this.isDeleteModalOpen = false;
        this.deleteReason = '';
        this.otpInput = '';
    }

    openFeedbackModal() {
        this.isDeleteModalOpen = false;
        this.isFeedbackModalOpen = true;
    }

    closeFeedbackModal() {
        this.isFeedbackModalOpen = false;
        this.feedbackText = '';
    }

    handleReasonChange(event) {
        this.deleteReason = event.target.value;
    }

    handleOtpChange(event) {
        this.otpInput = event.target.value;
    }

    handleFeedbackChange(event) {
        this.feedbackText = event.target.value;
    }

    confirmDeleteAccount() {
        // Handle confirm deletion
        this.closeDeleteModal();
    }

    submitFeedback() {
        // Handle feedback submission
        this.closeFeedbackModal();
    }
}