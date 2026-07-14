import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import processVerifiedLead from '@salesforce/apex/KenAlumniOnboardingService.processVerifiedLead';
import resendMagicLink from '@salesforce/apex/KenAlumniOnboardingService.resendMagicLink';

export default class KenVerifyLink extends LightningElement {
    isLoading = true;
    error;
    resendMessage;
    token;
    resendRequested = false;

    @wire(CurrentPageReference)
    parseState(currentPageReference) {
        if (!currentPageReference || !currentPageReference.state) {
            return;
        }
        const urlToken = currentPageReference.state.token;
        const fallbackToken = this.getTokenFromUrl();
        const tokenToUse = urlToken || fallbackToken;
        if (tokenToUse && tokenToUse !== this.token) {
            this.token = tokenToUse;
            this.verify(tokenToUse);
        } else if (!tokenToUse) {
            this.error = 'Missing or invalid verification token. Please use the link from your email.';
            this.isLoading = false;
        }
    }

    connectedCallback() {
        if (!this.token) {
            const token = this.getTokenFromUrl();
            if (token) {
                this.token = token;
                this.verify(token);
            } else {
                this.error = 'Missing or invalid verification token. Please use the link from your email.';
                this.isLoading = false;
            }
        }
    }

    getTokenFromUrl() {
        try {
            const url = new URL(window.location.href);
            return url.searchParams.get('token');
        } catch (e) {
            return null;
        }
    }

    async verify(token) {
        this.error = null;
        this.resendMessage = null;
        this.isLoading = true;
        const resendParam = this.getResendFlagFromUrl();
        try {
            if (resendParam) {
                await resendMagicLink({ token });
                this.resendMessage = 'Verification email resent successfully.';
                this.isLoading = false;
                return;
            }

            const redirectUrl = await processVerifiedLead({ token });
            if (redirectUrl) {
                try {
                    const url = new URL(redirectUrl, window.location.origin);
                    const accountId = url.searchParams.get('accountId');
                    const roleId = url.searchParams.get('roleId');
                    const tokenParam = url.searchParams.get('token') || token;
                    if (accountId) {
                        window.localStorage.setItem('UserAccountId', accountId);
                    }
                    if (roleId) {
                        window.localStorage.setItem('ConstituentRoleId', roleId);
                    }
                    if (tokenParam) {
                        window.sessionStorage.setItem('onboardToken', tokenParam);
                    }
                } catch (e) {
                    // ignore storage failures
                }
                window.location.assign(redirectUrl);
            } else {
                this.error = 'Verification failed. Please try again.';
            }
        } catch (e) {
            const msg = e?.body?.message || 'Verification failed. Please try again or request a new link.';
            if (msg === 'EXPIRED') {
                this.error = 'Token is expired. Please click on the resend verification in the email.';
            } else if (msg === 'ALREADY_REGISTERED') {
                this.error = 'Already registered. Please login.';
            } else if (msg === 'INVALID_TOKEN' || msg === 'Missing or invalid verification token.') {
                this.error = 'Missing or invalid verification token. Please use the link from your email.';
            } else {
                this.error = msg;
            }
        } finally {
            this.isLoading = false;
        }
    }

    getResendFlagFromUrl() {
        try {
            const url = new URL(window.location.href);
            return url.searchParams.get('resend') === 'true';
        } catch (e) {
            return false;
        }
    }
}