import { LightningElement, api } from 'lwc';

export default class KenEventSummaryStep extends LightningElement {
    @api data = {};

    get hasMealLines() {
        return this.data && Array.isArray(this.data.mealLines) && this.data.mealLines.length > 0;
    }

    get hasCustomSurvey() {
        return this.data && this.data.customSurveyCount > 0;
    }

    get showPreSurveyCard() {
        return this.hasMealLines || this.hasCustomSurvey;
    }

    // Fees / price / total columns are hidden when the org has fees disabled.
    get showFees() {
        return !(this.data && this.data.feeDisabled);
    }

    // When fees are hidden the session grid drops the Price column (3 cols -> 2 cols).
    get sessionHeaderClass() {
        return this.showFees ? 'session-cols-header' : 'session-cols-header no-fees';
    }

    get sessionRowClass() {
        return this.showFees ? 'session-row' : 'session-row no-fees';
    }

    handleEdit(event) {
        const step = parseInt(event.currentTarget.dataset.step, 10);
        this.dispatchEvent(new CustomEvent('editstep', {
            detail: { step },
            bubbles: true,
            composed: true
        }));
    }
}