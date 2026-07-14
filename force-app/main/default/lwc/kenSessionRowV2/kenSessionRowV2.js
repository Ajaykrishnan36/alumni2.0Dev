import { LightningElement, api } from 'lwc';

export default class KenSessionRowV2 extends LightningElement {
    @api session = {};

    get title() { return this.session && this.session.title; }
    get time() { return this.session && this.session.time; }
    get pillLabel() { return this.session && this.session.pillLabel; }
    get pillClass() { return this.session && this.session.pillClass; }

    handleClick() {
        this.dispatchEvent(new CustomEvent('click', { detail: { id: this.session && this.session.id } }));
    }
}