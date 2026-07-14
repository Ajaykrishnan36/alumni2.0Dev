import { LightningElement, api } from 'lwc';
import SLDSICONSSR from '@salesforce/resourceUrl/xdoIcons';

export default class XdoIcon extends LightningElement {
    @api iconType = 'standard';
    @api iconName = 'account';
    @api iconClass = 'slds-icon';
    @api assistiveText = 'Description of icon when needed';

    iconPath;

    connectedCallback(){
        this.iconPath = SLDSICONSSR + '/' + this.iconType + '-sprite/svg/symbols.svg#' + this.iconName;
    }
}