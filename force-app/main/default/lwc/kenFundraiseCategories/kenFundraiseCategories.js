import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFundraiseCategories from '@salesforce/apex/KenFundraiseController.getFundraiseCategories';
import FallbackImage from '@salesforce/resourceUrl/AlumniCommunityCoverImg1';

export default class KenFundraiseCategories extends NavigationMixin(LightningElement) {
    categories = [];

    @wire(getFundraiseCategories)
    wiredCategories({ data }) {
        if (data) {
            this.categories = [...data]
                .sort((a, b) => new Date(b.createdDate) - new Date(a.createdDate))
                .map(c => ({
                    id: c.id,
                    title: c.name,
                    description: c.description,
                    image: c.imageUrl || FallbackImage
                }));
        }
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'all_campaigns__c' }
        });
    }

    handleCardClick(event) {
        const cat = this.categories.find(c => c.id === event.currentTarget.dataset.id);
        if (!cat) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'all_campaigns__c' },
            state: { category: cat.id }
        });
    }

    handleImgError(event) {
        event.target.style.display = 'none';
    }
}