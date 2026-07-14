import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenAlumniCard extends NavigationMixin(LightningElement) {
    @api recordId;
    @api name;
    @api title;
    @api company;
    @api expertise;
    @api education;
    @api graduationYear;
    @api location;
    @api batch;
    @api profileImage;
    @api willingToHelp = false;
    @api isMentor = false;
    // True only when this person is the viewer's accepted mentor — gates the "Mentor" badge.
    @api isMyMentor = false;
    @api badgeLabel = 'Willing to help';
    @api mentorBadgeLabel = 'Mentor';
    @api isOnline = false;
    @api presenceStatus;
    @api showBatch = false;
    @api compact = false;
    @api linkedin;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    normalizeText(value) {
        const v = (value ?? '').toString().trim();
        if (!v || v === '-') return null;
        return v;
    }

    get cardClass() {
        let cls = 'alumni-card';
        if (this.showBatch) cls += ' batch-view';
        if (this.compact) cls += ' compact';
        return cls;
    }

    get showMentorBadge() {
        // "Mentor" badge is only for the viewer's accepted mentor — NOT everyone
        // willing to help (those get the "Willing to help" badge below).
        return this.isMyMentor === true;
    }

    get showWillingBadge() {
        return this.willingToHelp === true && this.showMentorBadge !== true;
    }

    get resolvedProfileImage() {
        return this.profileImage ? this.profileImage : defaultProfileImage;
    }

    get resolvedTitle() {
        return this.normalizeText(this.title);
    }

    get resolvedCompany() {
        return this.normalizeText(this.company);
    }

    get resolvedLocation() {
        return this.normalizeText(this.location);
    }

    get displayTitle() {
        return this.resolvedTitle ?? '-';
    }

    get displayCompany() {
        return this.resolvedCompany ?? '-';
    }

    get displayLocation() {
        return this.resolvedLocation ?? '-';
    }

    get subtitleText() {
        return this.normalizeText(this.expertise) || this.normalizeText(this.title) || '';
    }

    get educationText() {
        return this.normalizeText(this.education) || this.normalizeText(this.batch) || '';
    }

    get hasLocation() {
        return !!this.resolvedLocation;
    }

    // Always-rendered display values: fall back to a dash when data is missing so every card
    // keeps the same field rows (and therefore the same size) instead of collapsing.
    get batchDisplay() {
        return this.normalizeText(this.batch) || '-';
    }

    get subtitleDisplay() {
        return this.subtitleText || '-';
    }

    get educationDisplay() {
        return this.educationText || '-';
    }

    get locationDisplay() {
        return this.displayLocationText || '-';
    }

    truncateText(value, maxChars) {
        const v = (value ?? '').toString();
        if (!maxChars || maxChars <= 0) return { text: v, title: v };
        if (v.length <= maxChars) return { text: v, title: v };
        const keep = Math.max(0, maxChars - 3);
        return { text: `${v.slice(0, keep)}...`, title: v };
    }

    getPrimaryLabel(value) {
        const v = (value ?? '').toString().trim();
        if (!v || v === '-') return '-';

        // Remove leading separators/spaces so values like ", Chennai" still show "Chennai"
        const cleaned = v.replace(/^[\s,.;:|/\\-]+/, '').trim();
        if (!cleaned) return '-';

        // Take the text before the first separator (comma/dot/etc.)
        const first = cleaned.split(/[,.;:|/\\-]+/)[0]?.trim();
        return first || '-';
    }

    get displayLocationText() {
        if (!this.resolvedLocation) return '';
        return this.truncateText(this.resolvedLocation, 40).text;
    }

    get displayLocationTooltip() {
        return this.resolvedLocation || '';
    }

    get normalizedPresenceStatus() {
        if (this.isOnline === true) {
            return 'online';
        }
        const value = (this.presenceStatus || '').toLowerCase();
        if (value === 'online' || value === 'offline') {
            return value;
        }
        return 'offline';
    }

    get showPresenceDot() {
        return this.normalizedPresenceStatus === 'online';
    }

    get presenceDotClass() {
        return `presence-indicator ${this.normalizedPresenceStatus}`;
    }

    get linkedinUrl() {
        if (!this.linkedin) return null;
        const val = this.linkedin.trim();
        if (val.startsWith('http://') || val.startsWith('https://')) return val;
        if (val.startsWith('in/') || val.startsWith('/in/')) return 'https://www.linkedin.com/' + val.replace(/^\//, '');
        return 'https://www.linkedin.com/in/' + val;
    }

    renderedCallback() {
        const img = this.template.querySelector('.profile-image');
        if (img) {
            img.addEventListener('error', () => {
                img.src = defaultProfileImage;
            });
        }
    }

    handleLinkedinClick(event) {
        event.stopPropagation();
    }

    handleCardClick() {
        const profileId = this.recordId;
        if (!profileId) return;

        // Use the same navigation shape as `kenNetworkPage` so `CurrentPageReference`
        // updates reliably and the profile view loads.
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'network__c' },
            state: { profileId }
        });
    }

    handleCardKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleCardClick();
        }
    }
}