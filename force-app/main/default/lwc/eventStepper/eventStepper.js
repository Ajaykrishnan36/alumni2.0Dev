import { LightningElement, api } from 'lwc';

export default class EventStepper extends LightningElement {
    @api currentStep = 1;
    @api isStep1Completed = false;
    @api isStep2Completed = false;
    @api isStep3Completed = false;
    @api isStep4Completed = false;
    @api isStep5Completed = false;
    @api isStep6Completed = false;
    @api isStep7Completed = false;

    get stepperItems() {
        const steps = [
            { number: 1, label: 'Event Setup', completed: this.isStep1Completed },
            { number: 2, label: 'Target Audience', completed: this.isStep2Completed },
            { number: 3, label: 'Schedule Setup', completed: this.isStep3Completed },
            { number: 4, label: 'Pre-Event Surveys', completed: this.isStep4Completed },
            { number: 5, label: 'Fee Setup', completed: this.isStep5Completed },
            { number: 6, label: 'Feedback Form', completed: this.isStep6Completed },
            { number: 7, label: 'Summary', completed: this.isStep7Completed }
        ];

        const totalSteps = steps.length;

        return steps.map(step => {
            const isActive = this.currentStep === step.number;
            const isCompleted = step.completed || this.currentStep > step.number;
            return {
                ...step,
                isActive,
                isCompleted,
                isLast: step.number === totalSteps,
                statusClass: `step ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''}`.trim(),
                lineClass: isActive || isCompleted ? 'step-line active' : 'step-line'
            };
        });
    }

    get stepIndicatorLabel() {
        return `Step ${this.currentStep} out of 7`;
    }

    get progressFillStyle() {
        const progress = Math.min(100, ((this.currentStep - 1) / 6) * 100);
        return `width:${progress}%`;
    }
}