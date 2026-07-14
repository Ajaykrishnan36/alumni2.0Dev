import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenMyBusinessCard extends LightningElement {
    @api business;

    get statusClass() {
        if (!this.business?.status) return 'status-badge';
        
        const status = this.business.status.toLowerCase();
        let statusClass = '';
        if (status === 'active') statusClass = 'active';
        else if (status === 'in review' || status === 'inreview') statusClass = 'in-review';
        else if (status === 'rejected') statusClass = 'rejected';
        else if (status === 'de-activated' || status === 'deactivated') statusClass = 'deactivated';
        
        return `status-badge ${statusClass}`;
    }

    get isRejected() {
        return this.business?.status?.toLowerCase() === 'rejected' && this.business?.rejectionReason;
    }

    get hasFeatureLabel() {
        return this.featureLabel !== '';
    }

    get featureLabel() {
        const s = this.business?.featureStatus;
        if (s === 'Pending Approval') return '★ Feature: under approval';
        if (s === 'Approved' && this.business?.isCurrentlyFeatured) return '★ Featured';
        if (s === 'Approved') return '★ Feature approved';
        if (s === 'Rejected') return '★ Feature rejected';
        return '';
    }

    get featureRejectionReason() {
        return this.business?.featureStatus === 'Rejected'
            ? (this.business?.rejectionReason || '')
            : '';
    }

    get featureLabelClass() {
        const s = this.business?.featureStatus;
        let mod = '';
        if (s === 'Pending Approval') mod = 'fb-pending';
        else if (s === 'Approved' && this.business?.isCurrentlyFeatured) mod = 'fb-live';
        else if (s === 'Approved') mod = 'fb-approved';
        else if (s === 'Rejected') mod = 'fb-rejected';
        return `feature-chip ${mod}`;
    }

    handleCardClick() {
        // Dispatch event to parent to show business details
        if (this.business && this.business.id) {
            this.dispatchEvent(new CustomEvent('mybusinessclick', {
                detail: {
                    businessId: this.business.id,
                    business: this.business
                },
                bubbles: true,
                composed: true
            }));
        }
    }
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
}