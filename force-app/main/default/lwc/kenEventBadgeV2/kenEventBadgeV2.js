import { LightningElement, api } from 'lwc';

const TONES = ['emerald', 'violet', 'sky', 'amber', 'rose'];

export default class KenEventBadgeV2 extends LightningElement {
    @api label = '';
    @api tone = 'sky';

    get badgeClass() {
        const t = TONES.indexOf(this.tone) > -1 ? this.tone : 'sky';
        return `evb evb--${t}`;
    }
}