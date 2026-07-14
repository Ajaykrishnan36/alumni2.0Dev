import { LightningElement, api } from 'lwc';

export default class KenEventStepperV2 extends LightningElement {
    @api steps = [];
    @api currentIndex = 1;
    @api hideProgressBar = false;
    @api hideCounter = false;

    get stepperItems() {
        const total = (this.steps || []).length;
        const cur = Number(this.currentIndex) || 1;
        return (this.steps || []).map((s, i) => {
            const n = i + 1;
            const isActive = cur === n;
            const isCompleted = cur > n;
            let cls = 'hstep';
            if (isActive) cls += ' hstep--active';
            if (isCompleted) cls += ' hstep--done';
            return {
                id: s.id || n,
                label: s.label || `Step ${n}`,
                num: isCompleted ? '✓' : String(n),
                cls,
                isLast: n === total,
                lineCls: isActive || isCompleted ? 'hstep__line hstep__line--on' : 'hstep__line'
            };
        });
    }

    get totalSteps() {
        return (this.steps || []).length;
    }

    get progressStyle() {
        const total = this.totalSteps || 1;
        const cur = Number(this.currentIndex) || 1;
        const pct = Math.min(100, (cur / total) * 100);
        return `width:${pct}%`;
    }

    get counterLabel() {
        return `Step ${this.currentIndex} out of ${this.totalSteps}`;
    }

    get showProgressBar() {
        return !this.hideProgressBar;
    }

    get showCounter() {
        return !this.hideCounter;
    }
}