import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import defaultAvatar from '@salesforce/resourceUrl/AlumniAlt';
import donateImg from '@salesforce/resourceUrl/donateImg';
import eventTest1 from '@salesforce/resourceUrl/eventTest1';
import eventTest2 from '@salesforce/resourceUrl/eventTest2';
import PortalLoginImage from '@salesforce/resourceUrl/PortalLoginImage';
import requestServiceImg from '@salesforce/resourceUrl/requestServiceImg';
import suggestedGroupsbgimage from '@salesforce/resourceUrl/suggestedGroupsbgimage';
import getPersonalDetails from '@salesforce/apex/KenProfileSettingsController.getPersonalDetails';
import savePersonalDetails from '@salesforce/apex/KenProfileSettingsController.savePersonalDetails';
import saveEngagementPreferences from '@salesforce/apex/KenProfileSettingsController.saveEngagementPreferences';
import saveProfilePhoto from '@salesforce/apex/KenProfileSettingsController.saveProfilePhoto';
import createNeedHelpCase from '@salesforce/apex/KenServiceSupportController.createNeedHelpCase';
import getVerificationStatus from '@salesforce/apex/KenCommunityOtpLoginController.getVerificationStatus';
import saveMobileNumber from '@salesforce/apex/KenCommunityOtpLoginController.saveMobileNumber';
import startVerification from '@salesforce/apex/KenCommunityOtpLoginController.startVerification';
import confirmVerificationCode from '@salesforce/apex/KenCommunityOtpLoginController.confirmVerificationCode';

const INTEREST_OPTIONS = [
    { id: 1, label: 'Learn from fellow alumni', name: 'Learn from fellow alumni', img: donateImg },
    { id: 2, label: 'Reconnect with my friends', name: 'Reconnect with my friends', img: eventTest1 },
    { id: 3, label: 'Give back to the community', name: 'Give back to the community', img: eventTest2 },
    { id: 4, label: 'Interested in hiring new talent', name: 'Interested in hiring new talent', img: PortalLoginImage },
    { id: 5, label: 'Looking to find a new job', name: 'Looking to find a new job', img: requestServiceImg },
    { id: 6, label: 'Grow my professional network', name: 'Grow my professional network', img: suggestedGroupsbgimage }
];

export default class KenSettingPersonalDetails extends NavigationMixin(LightningElement) {
    profilePic = defaultAvatar;

    @track isLoading = true;
    @track isSaving = false;
    @track showSuccessPopup = false;
    @track successPopupMessage = 'Personal details saved successfully';
    @track error = null;

    @track firstName = '';
    @track lastName = '';
    @track maskedEmail = '';
    @track maskedPhone = '';
    @track email = '';
    @track phone = '';
    @track emailVerified = false;
    @track phoneVerified = false;
    @track verifyingChannel = '';
    @track otpCode = '';
    @track isVerifyBusy = false;
    @track verifyMessage = '';
    @track verifyMessageIsError = false;
    @track phoneDraft = '';
    lastVerifiedChannel = '';
    @track city = '';
    @track country = '';
    @track linkedin = '';
    @track twitter = '';
    @track interests = [];

    @track showNeedHelpModal = false;
    @track needHelpRequestType = '';

    _pendingPhotoBase64 = null;

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        try {
            const data = await getPersonalDetails();
            if (data) {
                this.firstName = data.firstName || '';
                this.lastName = data.lastName || '';
                this.maskedEmail = data.maskedEmail || '';
                this.maskedPhone = data.maskedPhone || '';
                this.city = data.city || '';
                this.country = data.country || '';
                this.linkedin = data.linkedinUrl || '';
                this.twitter = data.twitterUrl || '';
                if (data.profileImageUrl) {
                    this.profilePic = data.profileImageUrl;
                }
                this._buildInterests(data.engagementPreferences);
            }
            await this.loadVerificationStatus();
        } catch (e) {
            this.error = e?.body?.message || 'Failed to load profile.';
        } finally {
            this.isLoading = false;
        }
    }

    _buildInterests(preferences) {
        const selected = new Set(
            preferences ? preferences.split(';').map(v => v.trim()).filter(Boolean) : []
        );
        this.interests = INTEREST_OPTIONS.map(opt => ({
            ...opt,
            selected: selected.has(opt.name),
            checkboxClass: selected.has(opt.name) ? 'custom-checkbox checked' : 'custom-checkbox'
        }));
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this[field] = event.target.value;
    }

    toggleInterest(event) {
        const id = parseInt(event.currentTarget.dataset.id, 10);
        this.interests = this.interests.map(item => {
            if (item.id === id) {
                const selected = !item.selected;
                return { ...item, selected, checkboxClass: selected ? 'custom-checkbox checked' : 'custom-checkbox' };
            }
            return item;
        });
    }

    handleRequestEmailChange() {
        this.needHelpRequestType = 'email';
        this.showNeedHelpModal = true;
    }

    handleRequestPhoneChange() {
        this.needHelpRequestType = 'phone';
        this.showNeedHelpModal = true;
    }

    async loadVerificationStatus() {
        try {
            const status = await getVerificationStatus();
            this.email = status?.email || '';
            this.phone = status?.mobilePhone || '';
            this.emailVerified = status?.emailVerified === true;
            this.phoneVerified = status?.phoneVerified === true;
        } catch (e) {
            this.email = '';
            this.phone = '';
        }
    }

    get isVerifyingEmail() {
        return this.verifyingChannel === 'Email';
    }

    get isVerifyingPhone() {
        return this.verifyingChannel === 'SMS';
    }

    get isPhoneEditable() {
        return !this.phone;
    }

    get isSavePhoneDisabled() {
        return this.isVerifyBusy || (this.phoneDraft || '').replace(/[^0-9]/g, '').length < 10;
    }

    handlePhoneDraftInput(event) {
        this.phoneDraft = event.target.value;
    }

    handlePhoneDraftKeyDown(event) {
        if (event.key === 'Enter' && !this.isSavePhoneDisabled) {
            this.handleSaveAndVerifyPhone();
        }
    }

    async handleSaveAndVerifyPhone() {
        this.isVerifyBusy = true;
        this.lastVerifiedChannel = 'SMS';
        try {
            const saved = await saveMobileNumber({ phone: this.phoneDraft });
            if (!saved?.success) {
                this.setVerifyMessage(saved?.message || 'Please try again.', true);
                return;
            }
            await this.loadVerificationStatus();
            this.phoneDraft = '';
        } catch (error) {
            this.setVerifyMessage(error?.body?.message || 'Please try again.', true);
            return;
        } finally {
            this.isVerifyBusy = false;
        }
        await this.beginVerification('SMS');
    }

    get isConfirmDisabled() {
        return this.isVerifyBusy || (this.otpCode || '').length < 6;
    }

    get emailFieldLabel() {
        return this.isVerifyingEmail ? `Enter the code sent to ${this.email}` : 'Email';
    }

    get phoneFieldLabel() {
        return this.isVerifyingPhone ? `Enter the code sent to ${this.phone}` : 'Phone Number';
    }

    get emailVerifyMessage() {
        return this.verifyingChannel === 'Email' || this.lastVerifiedChannel === 'Email'
            ? this.verifyMessage
            : '';
    }

    get phoneVerifyMessage() {
        return this.verifyingChannel === 'SMS' || this.lastVerifiedChannel === 'SMS'
            ? this.verifyMessage
            : '';
    }

    get emailVerifyMessageClass() {
        return this.verifyMessageIsError ? 'field-note field-note_error' : 'field-note';
    }

    get phoneVerifyMessageClass() {
        return this.emailVerifyMessageClass;
    }

    handleVerifyEmail() {
        this.beginVerification('Email');
    }

    handleVerifyPhone() {
        this.beginVerification('SMS');
    }

    async beginVerification(channel) {
        this.isVerifyBusy = true;
        this.otpCode = '';
        this.verifyMessage = '';
        this.lastVerifiedChannel = channel;
        try {
            const result = await startVerification({ channel });
            if (result?.debugMessage) {
                console.warn('Verification diagnostics:', result.debugMessage);
            }
            if (!result?.success) {
                this.setVerifyMessage(result?.message || 'Please try again.', true);
                return;
            }
            this.verifyingChannel = channel;
        } catch (error) {
            this.setVerifyMessage(error?.body?.message || 'Please try again.', true);
        } finally {
            this.isVerifyBusy = false;
        }
    }

    handleOtpInput(event) {
        this.otpCode = (event.target.value || '').replace(/[^0-9]/g, '');
        event.target.value = this.otpCode;
    }

    handleOtpKeyDown(event) {
        if (event.key === 'Enter' && !this.isConfirmDisabled) {
            this.handleConfirmOtp();
        }
        if (event.key === 'Escape') {
            this.handleCancelVerify();
        }
    }

    handleCancelVerify() {
        this.verifyingChannel = '';
        this.otpCode = '';
        this.verifyMessage = '';
    }

    async handleConfirmOtp() {
        const channel = this.verifyingChannel;
        this.isVerifyBusy = true;
        try {
            const result = await confirmVerificationCode({ channel, code: this.otpCode });
            if (result?.debugMessage) {
                console.warn('Verification diagnostics:', result.debugMessage);
            }
            if (!result?.success) {
                this.setVerifyMessage(result?.message || 'Please try again.', true);
                return;
            }
            this.verifyingChannel = '';
            this.otpCode = '';
            if (channel === 'SMS') {
                this.phoneVerified = true;
            } else {
                this.emailVerified = true;
            }
            this.setVerifyMessage('Verified. You can now sign in with a one-time password.', false);
        } catch (error) {
            this.setVerifyMessage(error?.body?.message || 'Please try again.', true);
        } finally {
            this.isVerifyBusy = false;
        }
    }

    setVerifyMessage(message, isError) {
        this.verifyMessage = message;
        this.verifyMessageIsError = isError;
        setTimeout(() => {
            this.verifyMessage = '';
        }, 6000);
    }

    handleNeedHelpClose() {
        this.showNeedHelpModal = false;
        this.needHelpRequestType = '';
    }

    async handleNeedHelpSubmit(event) {
        const { description, issueType, subject, file } = event.detail || {};
        const requestType = this.needHelpRequestType;
        this.showNeedHelpModal = false;
        this.needHelpRequestType = '';
        this.isSaving = true;
        try {
            let fileData;
            let fileName;
            if (file) {
                ({ fileData, fileName } = await this.readFileAsBase64(file));
            }
            const constituentRoleId = localStorage.getItem('ConstituentRoleId');
            await createNeedHelpCase({
                serviceOfferingId: issueType,
                subject,
                description,
                fileName,
                fileData,
                constituentRoleId
            });
            this.successPopupMessage = 'Request submitted successfully';
            this.showSuccessPopup = true;
            setTimeout(() => {
                this.showSuccessPopup = false;
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: { name: 'service_support__c' }
                });
            }, 600);
        } catch (error) {
            this.needHelpRequestType = requestType;
            this.showNeedHelpModal = true;
            const message = error?.body?.message || error?.message || 'An unexpected error occurred.';
            // Defer until the modal re-renders so we can call its @api method
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const modal = this.template.querySelector('c-ken-need-help-modal');
                if (modal) {
                    modal.showError('Submission failed', message);
                }
            }, 0);
        } finally {
            this.isSaving = false;
        }
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                resolve({ fileData: base64, fileName: file.name });
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    handleEditPicture() {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = 'image/png,image/jpeg,image/jpg';
        input.onchange = (e) => {
            const file = e.target.files && e.target.files[0];
            if (!file) return;
            if (file.size > 5 * 1024 * 1024) {
                this.error = 'Image size must be less than 5MB';
                return;
            }
            const reader = new FileReader();
            reader.onload = (evt) => {
                this._pendingPhotoBase64 = evt.target.result;
                this.profilePic = evt.target.result;
            };
            reader.readAsDataURL(file);
        };
        input.click();
    }

    handleDiscard() {
        this._pendingPhotoBase64 = null;
        this.loadData();
    }

    async handleSave() {
        this.isSaving = true;
        this.error = null;
        try {
            if (this._pendingPhotoBase64) {
                const url = await saveProfilePhoto({ base64Image: this._pendingPhotoBase64 });
                this.profilePic = url;
                this._pendingPhotoBase64 = null;
            }

            await savePersonalDetails({
                requestJson: JSON.stringify({
                    firstName: this.firstName,
                    lastName: this.lastName,
                    city: this.city,
                    country: this.country,
                    linkedinUrl: this.linkedin,
                    twitterUrl: this.twitter
                })
            });

            const preferences = this.interests
                .filter(i => i.selected)
                .map(i => i.name)
                .join(';');
            await saveEngagementPreferences({ preferences });

            this.successPopupMessage = 'Personal details saved successfully';
            this.showSuccessPopup = true;
            setTimeout(() => { this.showSuccessPopup = false; }, 3000);
        } catch (e) {
            this.error = e?.body?.message || 'Failed to save changes.';
        } finally {
            this.isSaving = false;
        }
    }
}