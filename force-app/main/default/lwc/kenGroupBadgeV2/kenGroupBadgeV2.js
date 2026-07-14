import { LightningElement, api } from 'lwc';

export default class KenGroupBadgeV2 extends LightningElement {
    @api label = '';
    @api tone = 'neutral'; // neutral | public | private | category

    get cssClass() {
        const map = {
            public: 'badge badge--public',
            private: 'badge badge--private',
            category: 'badge badge--category',
            neutral: 'badge'
        };
        return map[this.tone] || 'badge';
    }
}