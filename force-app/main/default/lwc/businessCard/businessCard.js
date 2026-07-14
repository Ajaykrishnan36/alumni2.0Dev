import { LightningElement, api } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';
import defaultBusinessImage from '@salesforce/resourceUrl/AlumniAlt';

export default class BusinessCard extends LightningElement {
    @api business;

    get featuredImageUrl() {
        return this.business?.featuredImage || defaultBusinessImage;
    }

    get logoUrl() {
        return this.business?.logo || defaultBusinessImage;
    }

    handleImageError(event) {
        if (event && event.target) {
            event.target.src = defaultBusinessImage;
        }
    }

    handleLogoError(event) {
        if (event && event.target) {
            event.target.src = defaultBusinessImage;
        }
    }

    handleCardClick() {
        // Dispatch event to parent to show business details
        if (this.business && this.business.id) {
            this.dispatchEvent(new CustomEvent('businessclick', {
                detail: {
                    businessId: this.business.id,
                    business: this.business
                },
                bubbles: true,
                composed: true
            }));
        }
    }
}