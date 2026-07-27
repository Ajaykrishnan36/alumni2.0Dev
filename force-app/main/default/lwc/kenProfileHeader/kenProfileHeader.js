import { LightningElement, api, track } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

// connectionStatus: null | 'Requested' | 'Accepted' | 'Rejected' | 'Cancelled'
// mentorshipStatus: null | 'Requested' | 'Accepted' | 'Cancelled'
export default class KenProfileHeader extends LightningElement {
    @api name;
    @api title;
    @api company;
    @api location;
    @api profileImage;
    @api isOnline = false;
    @api batch;
    @api expertise;
    @api email;
    @api phone;
    @api linkedin;
    @api willingToHelp = false;
    @api isMentor = false;
    // True only when this person is already the viewer's accepted mentor.
    @api isMyMentor = false;
    @api education;
    @api isMyProfile = false;
    @api connectionStatus;
    @api mentorshipStatus;
    @api isConnectLoading = false;
    @api isMentorshipLoading = false;

    @track isMenuOpen = false;

    get displayImage() {
        return this.profileImage || defaultProfileImage;
    }

    get linkedinUrl() {
        if (!this.linkedin) return null;
        const val = this.linkedin.trim();
        if (val.startsWith('http://') || val.startsWith('https://')) return val;
        // bare username or path like "in/john-doe"
        if (val.startsWith('in/') || val.startsWith('/in/')) {
            return 'https://www.linkedin.com/' + val.replace(/^\//, '');
        }
        // just a username
        return 'https://www.linkedin.com/in/' + val;
    }

    get subtitleText() {
        return this.expertise || this.title || '';
    }

    get educationText() {
        return this.education || this.batch || '';
    }

    handleImageError(event) {
        if (event && event.target) {
            event.target.src = defaultProfileImage;
        }
    }

    // ─── Connection ───────────────────────────────────────────────────────────

    get isConnected() {
        return this.connectionStatus === 'Accepted';
    }

    get showConnectButton() {
        return this.connectionStatus !== 'Accepted';
    }

    get connectButtonLabel() {
        if (this.isConnectLoading) return 'Connecting...';
        if (this.connectionStatus === 'Requested') return 'Connection Requested ✓';
        return 'Connect +';
    }

    get connectButtonDisabled() {
        return this.isConnectLoading || this.connectionStatus === 'Requested';
    }

    get connectButtonClass() {
        if (this.isConnectLoading) return 'btn-connect btn-connect--loading';
        if (this.connectionStatus === 'Requested') return 'btn-connect btn-connect--requested';
        return 'btn-connect';
    }

    // ─── Mentorship ───────────────────────────────────────────────────────────

    get hasMentorship() {
        return this.mentorshipStatus === 'Requested' || this.mentorshipStatus === 'Accepted';
    }

    get showMentorshipButton() {
        // Show for a willing mentor who isn't already MY mentor (isMentor is now
        // the badge flag, so gate on isMyMentor to preserve the old behaviour).
        return this.willingToHelp === true && !this.isMyMentor && this.mentorshipStatus !== 'Accepted';
    }

    get mentorshipButtonLabel() {
        if (this.isMentorshipLoading) return 'Requesting...';
        if (this.mentorshipStatus === 'Requested') return 'Mentorship Requested';
        if (this.mentorshipStatus === 'Accepted') return 'Mentorship Active';
        return 'Request Mentorship';
    }

    get mentorshipButtonDisabled() {
        return this.isMentorshipLoading || this.hasMentorship;
    }

    get mentorshipButtonClass() {
        if (this.isMentorshipLoading) return 'btn-request-mentorship btn-request-mentorship--loading';
        if (this.hasMentorship) return 'btn-request-mentorship btn-request-mentorship--requested';
        return 'btn-request-mentorship';
    }

    // ─── Three-dot menu ───────────────────────────────────────────────────────

    get menuClass() {
        return this.isMenuOpen ? 'menu-dropdown menu-dropdown--open' : 'menu-dropdown';
    }

    /** Show Remove Mentorship only when mentorship is fully accepted/active */
    get showRemoveMentorship() {
        return this.mentorshipStatus === 'Accepted';
    }

    /** Show Remove Connection when connected AND mentorship is not yet accepted */
    get showRemoveConnection() {
        return this.connectionStatus === 'Accepted' && this.mentorshipStatus !== 'Accepted';
    }

    /** Only render the 3-dot menu when it has at least one actionable item.
     *  (Report User was removed, so it's driven purely by the remove options.) */
    get showMenu() {
        return this.showRemoveConnection || this.showRemoveMentorship;
    }

    handleMenuClick() {
        this.isMenuOpen = !this.isMenuOpen;
    }

    handleMenuBackdropClick() {
        this.isMenuOpen = false;
    }

    handleRemoveConnection() {
        this.isMenuOpen = false;
        this.dispatchEvent(new CustomEvent('removeconnection', { bubbles: true, composed: true }));
    }

    handleRemoveMentorship() {
        this.isMenuOpen = false;
        this.dispatchEvent(new CustomEvent('removementorship', { bubbles: true, composed: true }));
    }

    handleReportUser() {
        this.isMenuOpen = false;
        this.dispatchEvent(new CustomEvent('reportuser', { bubbles: true, composed: true }));
    }

    // ─── Other ────────────────────────────────────────────────────────────────

    handleRequestConnection() {
        if (this.connectButtonDisabled) return;
        this.dispatchEvent(new CustomEvent('requestconnection', { bubbles: true, composed: true }));
    }

    handleRequestMentorship() {
        if (this.mentorshipButtonDisabled) return;
        this.dispatchEvent(new CustomEvent('requestmentorship', { bubbles: true, composed: true }));
    }

    handleMessage() {
        this.dispatchEvent(new CustomEvent('openchat', { bubbles: true, composed: true }));
    }

    handleEditProfile() {
        this.dispatchEvent(new CustomEvent('editprofile', { bubbles: true, composed: true }));
    }
}