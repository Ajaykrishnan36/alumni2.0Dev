import { LightningElement, api } from 'lwc';

export default class KenGroupUpdateRowV2 extends LightningElement {
    @api update;

    get initial() { return this.update ? this.update.author.charAt(0) : ''; }
    get tagItems() {
        if (!this.update || !this.update.tags) return [];
        return this.update.tags.map((t, i) => ({ id: i, label: t }));
    }
    get commentsLabel() { return this.update ? `${this.update.comments} comments` : ''; }
    get hasImage() { return !!(this.update && this.update.hasImage); }

    handleClick() {
        if (!this.update) return;
        this.dispatchEvent(new CustomEvent('groupclick', { detail: { id: this.update.groupId } }));
    }
}