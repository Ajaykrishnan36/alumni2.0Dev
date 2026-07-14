import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import defaultBusinessImage from '@salesforce/resourceUrl/AlumniAlt';

export default class SimilarBusinesses extends NavigationMixin(LightningElement) {
    @api businessId;
    @api category;

    similarBusinesses = [
        {
            id: '2',
            name: 'SpaceMan',
            category: 'Technology',
            location: 'Chennai, India',
            logo: defaultBusinessImage
        }
    ];

    handleImageError(event) {
        if (event && event.target) {
            event.target.src = defaultBusinessImage;
        }
    }

    handleBusinessClick(event) {
        const businessId = event.currentTarget.dataset.businessId;
        if (businessId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'business_detail__c'
                },
                state: {
                    businessId: businessId
                }
            });
        }
    }

    handleViewMore() {
        // Navigate to business directory with filters
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'business_directory__c'
            }
        });
    }
}