import { LightningElement, api } from 'lwc';

export default class KenSuccessPageV2 extends LightningElement {
    @api title = 'Thank you for registering!';
    @api message = "Your application is under review. You'll receive a confirmation email within 3 working days once it's approved.";
    @api ctaLabel = 'Got it!';

    handleCta() {
        this.dispatchEvent(new CustomEvent('confirm'));
    }
}