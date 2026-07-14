import { LightningElement, track } from 'lwc';

export default class KenNewInitiativeModalV2 extends LightningElement {
    @track initTitle = '';
    @track initCategory = 'Batch Fund';
    @track initTarget = '';
    @track initDescription = '';
    @track initWhy = '';
    @track initBeneficiary = '';
    @track initBatch = '';
    @track initLinkedReunion = false;
    @track initListAsInitiator = false;
    @track initInvite = false;

    handleField(event) {
        const f = event.currentTarget.dataset.field;
        if (f === 'linkedReunion') this.initLinkedReunion = event.target.checked;
        else if (f === 'listAsInitiator') this.initListAsInitiator = event.target.checked;
        else if (f === 'invite') this.initInvite = event.target.checked;
        else this[f] = event.target.value;
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submit', { detail: {
            title: this.initTitle,
            category: this.initCategory,
            target: this.initTarget,
            description: this.initDescription,
            why: this.initWhy,
            beneficiary: this.initBeneficiary,
            batch: this.initBatch
        } }));
    }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
}