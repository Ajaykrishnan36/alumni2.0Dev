import { LightningElement, api } from 'lwc';

export default class KenAlumniBadgeV2 extends LightningElement {
    @api label = 'Willing to help';
    @api tone = 'help'; // help | online | neutral

    get cssClass() {
        const map = {
            help: 'badge badge--help',
            online: 'badge badge--online',
            neutral: 'badge'
        };
        return map[this.tone] || 'badge';
    }
}