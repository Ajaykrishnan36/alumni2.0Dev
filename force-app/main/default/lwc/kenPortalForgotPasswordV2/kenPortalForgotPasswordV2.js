import { LightningElement, api, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import requestPasswordOtp from '@salesforce/apex/KenCommunityLoginV2Controller.requestPasswordOtp';
import resetPasswordWithOtp from '@salesforce/apex/KenCommunityLoginV2Controller.resetPasswordWithOtp';

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const RESEND_COOLDOWN_SECS = 30;

export default class KenPortalForgotPasswordV2 extends LightningElement {
    @api institutionName = 'Name of the Institute';
    @api institutionLogoUrl = '';

    // Stage: 'email' → enter email; 'reset' → OTP + new password; 'done' → success.
    @track stage = 'email';
    @track email = '';
    @track otp = '';
    @track newPassword = '';
    @track confirmPassword = '';
    @track error = '';
    @track isLoading = false;
    @track resendCooldown = 0;
    @track resending = false;
    _timer = null;

    get isEmailStage() { return this.stage === 'email'; }
    get isResetStage() { return this.stage === 'reset'; }
    get isDoneStage() { return this.stage === 'done'; }

    get maskedEmail() {
        const e = this.email || '';
        const at = e.indexOf('@');
        if (at < 2) return e;
        const n = e.substring(0, at);
        return (n.length <= 2 ? n : n.substring(0, 2)) + '***' + e.substring(at);
    }
    get resendDisabled() { return this.resendCooldown > 0 || this.resending; }
    get resendLabel() {
        if (this.resending) return 'Sending…';
        if (this.resendCooldown > 0) return `Resend in ${this.resendCooldown}s`;
        return 'Resend code';
    }
    get resetDisabled() {
        return this.isLoading
            || !/^[0-9]{6}$/.test((this.otp || '').trim())
            || (this.newPassword || '').length < 8
            || this.newPassword !== this.confirmPassword;
    }

    handleEmailInput(event) { this.email = event.target.value; if (this.error) this.error = ''; }
    handleOtpInput(event) { this.otp = (event.target.value || '').replace(/[^0-9]/g, '').slice(0, 6); if (this.error) this.error = ''; }
    handleNewPassword(event) { this.newPassword = event.target.value; if (this.error) this.error = ''; }
    handleConfirmPassword(event) { this.confirmPassword = event.target.value; if (this.error) this.error = ''; }

    handleRequest(event) {
        if (event) event.preventDefault();
        const v = (this.email || '').trim();
        if (!v || !EMAIL_RE.test(v)) { this.error = 'Please enter a valid email address.'; return; }
        this.isLoading = true;
        this.error = '';
        requestPasswordOtp({ email: v })
            .then(() => {
                this.stage = 'reset';
                this.otp = ''; this.newPassword = ''; this.confirmPassword = '';
                this._startCooldown();
            })
            .catch(err => { this.error = (err && err.body && err.body.message) || 'Something went wrong. Please try again.'; })
            .finally(() => { this.isLoading = false; });
    }

    handleReset(event) {
        if (event) event.preventDefault();
        if (this.resetDisabled) return;
        this.isLoading = true;
        this.error = '';
        resetPasswordWithOtp({
            email: (this.email || '').trim(),
            otp: (this.otp || '').trim(),
            newPassword: this.newPassword,
            confirmPassword: this.confirmPassword
        })
            .then(() => { this._clearTimer(); this.stage = 'done'; })
            .catch(err => { this.error = (err && err.body && err.body.message) || 'Could not reset your password. Please try again.'; })
            .finally(() => { this.isLoading = false; });
    }

    handleResend(event) {
        if (event) event.preventDefault();
        if (this.resendDisabled) return;
        this.resending = true;
        this.error = '';
        requestPasswordOtp({ email: (this.email || '').trim() })
            .then(() => { this.otp = ''; this._startCooldown(); })
            .catch(err => { this.error = (err && err.body && err.body.message) || 'Could not resend the code.'; })
            .finally(() => { this.resending = false; });
    }

    handleEditEmail(event) { if (event) event.preventDefault(); this._clearTimer(); this.stage = 'email'; this.error = ''; }

    handleBackToLogin(event) {
        if (event) event.preventDefault();
        try { window.location.assign(basePath + '/login'); }
        catch (e) { window.location.href = basePath + '/login'; }
    }

    _startCooldown() {
        this._clearTimer();
        this.resendCooldown = RESEND_COOLDOWN_SECS;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setInterval(() => {
            this.resendCooldown -= 1;
            if (this.resendCooldown <= 0) this._clearTimer();
        }, 1000);
    }
    _clearTimer() { if (this._timer) { clearInterval(this._timer); this._timer = null; } this.resendCooldown = 0; }
    disconnectedCallback() { this._clearTimer(); }
}