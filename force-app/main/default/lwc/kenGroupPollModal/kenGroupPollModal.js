import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createPollPost from '@salesforce/apex/KenGroupFeedController.createPollPost';

const MIN_OPTIONS = 2;
const MAX_OPTIONS = 10;
const DEFAULT_DURATION = 7;

export default class KenGroupPollModal extends LightningElement {
    @api groupId;

    @track question = '';
    @track options = [{ id: 1, value: '' }, { id: 2, value: '' }];
    @track durationDays = DEFAULT_DURATION;
    @track isSubmitting = false;
    @track errorMessage = '';

    nextId = 3;

    get durationOptions() {
        return [
            { label: '1 day',  value: 1  },
            { label: '3 days', value: 3  },
            { label: '7 days', value: 7  },
            { label: '14 days', value: 14 },
            { label: '30 days', value: 30 }
        ];
    }

    get canAddMore()  { return this.options.length < MAX_OPTIONS; }
    get canRemove()   { return this.options.length > MIN_OPTIONS; }

    get submitDisabled() {
        if (this.isSubmitting) return true;
        if (!this.question || !this.question.trim()) return true;
        const filled = this.options.filter(o => o.value && o.value.trim()).length;
        return filled < MIN_OPTIONS;
    }

    handleQuestionInput(event) {
        this.question = event.target.value || '';
    }

    handleOptionInput(event) {
        const id = parseInt(event.target.dataset.id, 10);
        const value = event.target.value || '';
        this.options = this.options.map(o => (o.id === id ? { ...o, value } : o));
    }

    handleAddOption() {
        if (!this.canAddMore) return;
        this.options = [...this.options, { id: this.nextId++, value: '' }];
    }

    handleRemoveOption(event) {
        if (!this.canRemove) return;
        const id = parseInt(event.currentTarget.dataset.id, 10);
        this.options = this.options.filter(o => o.id !== id);
    }

    handleDurationChange(event) {
        this.durationDays = parseInt(event.detail.value, 10) || DEFAULT_DURATION;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSubmit() {
        if (this.submitDisabled) return;
        const cleanOptions = this.options
            .map(o => (o.value || '').trim())
            .filter(v => v.length > 0);
        this.isSubmitting = true;
        this.errorMessage = '';
        createPollPost({
            groupId: this.groupId,
            question: this.question.trim(),
            options: cleanOptions,
            durationDays: this.durationDays
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Poll posted',
                    message: 'Your poll is now live in the group.',
                    variant: 'success'
                }));
                this.dispatchEvent(new CustomEvent('created'));
            })
            .catch(err => {
                this.errorMessage = this.extractError(err);
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }
}