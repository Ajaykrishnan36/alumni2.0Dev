import { LightningElement, api, track } from 'lwc';
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import basePath from '@salesforce/community/basePath';

export default class RegistrationHeader extends LightningElement {
    kenLogo = KenLogo;
    @api firstName = '';
    @api lastName = '';
    @api profileImageUrl = '';
    @track imageLoadFailed = false;

    get displayName() {
        const first = (this.firstName || '').trim();
        const last = (this.lastName || '').trim();
        return `${first} ${last}`.trim() || 'User';
    }

    get initials() {
        const first = (this.firstName || '').trim();
        const last = (this.lastName || '').trim();
        const firstInitial = first ? first.charAt(0) : '';
        const lastInitial = last ? last.charAt(0) : '';
        const initials = `${firstInitial}${lastInitial}`.trim();
        return initials || 'U';
    }

    get showAvatarImage() {
        return !!this.profileImageUrl && !this.imageLoadFailed;
    }

    handleImageError() {
        this.imageLoadFailed = true;
    }

    handleLogout() {
        window.location.href = `${basePath}/secur/logout.jsp?retUrl/login`;
        this.dispatchEvent(new CustomEvent('logout', { bubbles: true, composed: true }));
    }
}