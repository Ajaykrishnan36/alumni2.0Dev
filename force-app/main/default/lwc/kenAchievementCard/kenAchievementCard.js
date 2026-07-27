import { LightningElement, api } from 'lwc';

export default class KenAchievementCard extends LightningElement {
    @api recordId;
    @api type; // e.g. "Honour / Award"
    @api title; // e.g. "Best Student Award"
    @api meta; // e.g. "Department of CSE | 2022"
    @api description; // long text
    @api isMyProfile = false;
    showDeleteConfirm = false;

    handleEdit() {
        this.dispatchEvent(new CustomEvent('edit', { detail: { id: this.recordId }, bubbles: true, composed: true }));
    }

    handleDelete() {
        this.showDeleteConfirm = true;
    }

    handleConfirmDelete() {
        this.showDeleteConfirm = false;
        this.dispatchEvent(new CustomEvent('delete', { detail: { id: this.recordId }, bubbles: true, composed: true }));
    }

    handleCancelDelete() {
        this.showDeleteConfirm = false;
    }
}