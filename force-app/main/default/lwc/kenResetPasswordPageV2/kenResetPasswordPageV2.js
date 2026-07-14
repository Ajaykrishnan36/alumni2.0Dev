import { LightningElement, api, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import changePassword from '@salesforce/apex/KenCommunityLoginV2Controller.changePassword';

const MIN_LEN = 8;

export default class KenResetPasswordPageV2 extends LightningElement {
    @api institutionName = 'Name of the Institute';
    @api institutionLogoUrl = '';
    @api title = 'Reset your password';
    @api subtitle = 'Create a new password for your alumni account. Make it at least 8 characters.';

    @track form = { newPassword: '', confirmPassword: '' };
    @track errorMessage = '';
    @track isLoading = false;
    @track submitted = false;

    showNew = false;
    showConfirm = false;

    get newType() { return this.showNew ? 'text' : 'password'; }
    get confirmType() { return this.showConfirm ? 'text' : 'password'; }

    handleInput(event) {
        const field = event.target.dataset.field;
        if (field) {
            this.form = { ...this.form, [field]: event.target.value };
            if (this.errorMessage) this.errorMessage = '';
        }
    }
    toggleNew() { this.showNew = !this.showNew; }
    toggleConfirm() { this.showConfirm = !this.showConfirm; }

    handleSubmit(event) {
        if (event) event.preventDefault();
        const { newPassword, confirmPassword } = this.form;
        if (!newPassword || !confirmPassword) {
            this.errorMessage = 'Please fill in both fields.';
            return;
        }
        if (newPassword.length < MIN_LEN) {
            this.errorMessage = `Password must be at least ${MIN_LEN} characters.`;
            return;
        }
        if (newPassword !== confirmPassword) {
            this.errorMessage = 'Passwords do not match.';
            return;
        }
        this.isLoading = true;
        changePassword({ newPassword, verifyNewPassword: confirmPassword })
            .then(url => {
                this.submitted = true;
                // Land the user wherever Salesforce points after a successful reset
                // (their start page), falling back to login.
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    const target = url || (basePath + '/login');
                    try { window.location.assign(target); } catch (e) { window.location.href = target; }
                }, 1400);
            })
            .catch(err => {
                this.errorMessage = (err && err.body && err.body.message) || 'Could not update your password. Please try again.';
            })
            .finally(() => { this.isLoading = false; });
    }

    handleBackToLogin(event) {
        if (event) event.preventDefault();
        try { window.location.assign(basePath + '/login'); }
        catch (e) { window.location.href = basePath + '/login'; }
    }
}