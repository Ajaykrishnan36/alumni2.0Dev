import { LightningElement, api } from 'lwc';

export default class KenAlumniInviteCardV2 extends LightningElement {
    @api inviteUrl = 'https://alumni.portal.edu/...';

    handleCopy() {
        this.dispatchEvent(new CustomEvent('copy', { detail: { url: this.inviteUrl } }));
    }
}