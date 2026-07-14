// V2 — full OTP reset flow:
//   Step 1: sendResetOtp(email) — email pulled fresh from KenMyProfileController.getMyProfile()
//   Step 2: verifyResetOtp(email, otp)
//   Step 3: resetPassword(email, newPassword)
import { LightningElement, api, track } from 'lwc';
import getMyProfile from '@salesforce/apex/KenMyProfileController.getMyProfile';
import sendResetOtp from '@salesforce/apex/KenCommunityLoginController.sendResetOtp';
import verifyResetOtp from '@salesforce/apex/KenCommunityLoginController.verifyResetOtp';
import resetPassword from '@salesforce/apex/KenCommunityLoginController.resetPassword';

export default class KenSettingsPasswordModalV2 extends LightningElement {
    static renderMode = 'light';
    @api passForm = {}; // legacy prop kept for backwards compatibility

    @track step = 1;
    @track email = '';
    @track otp = '';
    @track nextPwd = '';
    @track confirmPwd = '';
    @track busy = false;
    @track errorMessage = '';

    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get emailDisplay() { return this.email || 'your registered email'; }

    connectedCallback() {
        // Fetch un-masked email fresh (getPersonalDetails returns masked email).
        getMyProfile()
            .then(p => { if (p && p.email) this.email = p.email; })
            .catch(() => { /* non-fatal — user will see error if Send code fails */ });
    }

    handleField(event) {
        const f = event.target.dataset.field;
        if (!f) return;
        if (f === 'otp')     this.otp = event.target.value;
        if (f === 'next')    this.nextPwd = event.target.value;
        if (f === 'confirm') this.confirmPwd = event.target.value;
    }

    handleSendOtp() {
        this.errorMessage = '';
        if (!this.email) { this.errorMessage = 'Could not resolve your registered email.'; return; }
        this.busy = true;
        sendResetOtp({ email: this.email })
            .then(() => { this.step = 2; })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('sendResetOtp error', err);
                this.errorMessage = (err && err.body && err.body.message) || 'Could not send code. Please try again.';
            })
            .finally(() => { this.busy = false; });
    }

    handleVerifyOtp() {
        this.errorMessage = '';
        if (!(this.otp || '').trim()) { this.errorMessage = 'Please enter the 6-digit code.'; return; }
        this.busy = true;
        verifyResetOtp({ email: this.email, otpEntered: this.otp.trim() })
            .then(() => { this.step = 3; })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('verifyResetOtp error', err);
                this.errorMessage = (err && err.body && err.body.message) || 'Invalid code. Please try again.';
            })
            .finally(() => { this.busy = false; });
    }

    handleSubmitReset() {
        this.errorMessage = '';
        if (!this.nextPwd || this.nextPwd !== this.confirmPwd) {
            this.errorMessage = 'Passwords do not match.';
            return;
        }
        this.busy = true;
        resetPassword({ email: this.email, newPassword: this.nextPwd })
            .then(() => {
                this.dispatchEvent(new CustomEvent('resetdone', { bubbles: true, composed: true }));
                this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('resetPassword error', err);
                this.errorMessage = (err && err.body && err.body.message) || 'Could not update password.';
            })
            .finally(() => { this.busy = false; });
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
        }
    }
    handleStop(event) { event.stopPropagation(); }
}