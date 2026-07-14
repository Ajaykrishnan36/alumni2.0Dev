import { LightningElement, api } from 'lwc';

export default class KenSettingsSidebarV2 extends LightningElement {
    static renderMode = 'light';
    @api sections = [];

    handleSection(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('sectionchange', {
            detail: { id },
            bubbles: true,
            composed: true
        }));
    }
}