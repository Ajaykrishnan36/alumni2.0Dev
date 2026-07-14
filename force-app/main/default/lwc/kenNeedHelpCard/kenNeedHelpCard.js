import { LightningElement } from 'lwc';

export default class KenNeedHelpCard extends LightningElement {
    handleCardClick() {
        this.dispatchEvent(new CustomEvent('needhelpclick'));
    }
}