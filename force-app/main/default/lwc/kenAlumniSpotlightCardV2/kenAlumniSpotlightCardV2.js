import { LightningElement, api } from 'lwc';

export default class KenAlumniSpotlightCardV2 extends LightningElement {
    @api spotlight = {
        title: 'Turning Ambition into Impact',
        description: 'From campus beginnings to real-world impact, this alumnus turned learning into leadership, built meaningful solutions, and continues to inspire the community through growth, resilience, and purpose.'
    };

    get title() { return (this.spotlight && this.spotlight.title) || 'Turning Ambition into Impact'; }
    get description() {
        return (this.spotlight && this.spotlight.description) ||
            'From campus beginnings to real-world impact, this alumnus turned learning into leadership, built meaningful solutions, and continues to inspire the community through growth, resilience, and purpose.';
    }

    handleClick() { this.dispatchEvent(new CustomEvent('click')); }
}