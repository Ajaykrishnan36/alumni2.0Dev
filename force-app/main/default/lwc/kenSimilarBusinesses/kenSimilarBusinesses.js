import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import defaultBusinessImage from '@salesforce/resourceUrl/AlumniAlt';
import getSimilarBusinesses from '@salesforce/apex/KenBusinessController.getSimilarBusinesses';

export default class KenSimilarBusinesses extends NavigationMixin(LightningElement) {
    @track similarBusinesses = [];
    _businessId;
    _category;

    @api
    get businessId() {
        return this._businessId;
    }
    set businessId(value) {
        this._businessId = value;
        this.loadSimilar();
    }

    @api
    get category() {
        return this._category;
    }
    set category(value) {
        this._category = value;
        this.loadSimilar();
    }

    loadSimilar() {
        if (!this._businessId || !this._category) {
            return;
        }
        getSimilarBusinesses({ businessId: this._businessId, category: this._category })
            .then((data) => {
                this.similarBusinesses = (data || []).map((b) => ({
                    ...b,
                    logo: b.logo || defaultBusinessImage
                }));
            })
            .catch(() => {
                this.similarBusinesses = [];
            });
    }

    get hasSimilar() {
        return this.similarBusinesses && this.similarBusinesses.length > 0;
    }

    handleImageError(event) {
        if (event && event.target) {
            event.target.src = defaultBusinessImage;
        }
    }

    handleBusinessClick(event) {
        const businessId = event.currentTarget.dataset.businessId;
        if (businessId) {
            this.dispatchEvent(
                new CustomEvent('similarselect', {
                    detail: { businessId },
                    bubbles: true,
                    composed: true
                })
            );
        }
    }

    handleViewMore() {
        // Bubble up so the directory closes the detail view and shows all businesses
        this.dispatchEvent(
            new CustomEvent('viewmore', {
                bubbles: true,
                composed: true
            })
        );
    }
}