import { LightningElement, api } from 'lwc';
import SUGGESTED_BG from '@salesforce/resourceUrl/suggestedGroupsbgimage';

export default class GroupsDiscover extends LightningElement {
    @api suggestedGroups = [];

    get backgroundStyle() {
        return `background-image: url(${SUGGESTED_BG}); background-size: cover; background-position: center;`;
    }

    handlePrev() {
        // Implement scrolling or carousel logic if needed
        const container = this.template.querySelector('.cards-scroll-container');
        if (container) {
            container.scrollBy({ left: -300, behavior: 'smooth' });
        }
    }

    handleNext() {
        const container = this.template.querySelector('.cards-scroll-container');
        if (container) {
            container.scrollBy({ left: 300, behavior: 'smooth' });
        }
    }
}