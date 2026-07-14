import { LightningElement } from 'lwc';
import needHelpImg from '@salesforce/resourceUrl/needHelp';
export default class NeedHelpCard extends LightningElement {
    needHelpImgUrl = needHelpImg;
    handleCardClick() {
        const needHelpEvent = new CustomEvent('needhelpclick');
        this.dispatchEvent(needHelpEvent);
    }
}