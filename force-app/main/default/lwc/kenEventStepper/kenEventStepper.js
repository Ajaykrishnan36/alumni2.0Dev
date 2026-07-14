import { LightningElement, api } from 'lwc';

export default class KenEventStepper extends LightningElement {
    @api currentStep = 1;
    // When true, the org has fees disabled — the Fee Setup step is removed
    // from the stepper and the remaining steps are renumbered for display.
    @api feeDisabled = false;
    @api isStep1Completed = false;
    @api isStep2Completed = false;
    @api isStep3Completed = false;
    @api isStep4Completed = false;
    @api isStep5Completed = false;
    @api isStep6Completed = false;
    @api isStep7Completed = false;

    get stepperItems() {
        let steps = [
            { number: 1, label: 'Event Setup', completed: this.isStep1Completed },
            { number: 2, label: 'Target Audience', completed: this.isStep2Completed },
            { number: 3, label: 'Schedule Setup', completed: this.isStep3Completed },
            { number: 4, label: 'Pre Event Surveys', completed: this.isStep4Completed },
            { number: 5, label: 'Fee Setup', completed: this.isStep5Completed },
            { number: 6, label: 'Feedback Form', completed: this.isStep6Completed },
            { number: 7, label: 'Summary', completed: this.isStep7Completed }
        ];

        if (this.feeDisabled) {
            steps = steps.filter(step => step.number !== 5);
        }

        const totalSteps = steps.length;

        return steps.map((step, index) => {
            const isActive = this.currentStep === step.number;
            const isCompleted = step.completed || this.currentStep > step.number;
            // displayNumber is the sequential position shown in the circle so
            // there is no visible gap when the Fee Setup step is hidden.
            const displayNumber = index + 1;
            return {
                ...step,
                displayNumber,
                isActive,
                isCompleted,
                isLast: index === totalSteps - 1,
                statusClass: `step ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''}`.trim(),
                lineClass: isActive || isCompleted ? 'step-line active' : 'step-line'
            };
        });
    }

    get totalSteps() {
        return this.feeDisabled ? 6 : 7;
    }

    // Position of the current step among the visible steps (handles the hidden Fee step).
    get displayCurrentStep() {
        if (this.feeDisabled && this.currentStep > 5) {
            return this.currentStep - 1;
        }
        return this.currentStep;
    }

    get stepIndicatorLabel() {
        return `Step ${this.displayCurrentStep} out of ${this.totalSteps}`;
    }

    get progressFillStyle() {
        const progress = Math.min(100, ((this.displayCurrentStep - 1) / (this.totalSteps - 1)) * 100);
        return `width:${progress}%`;
    }
}