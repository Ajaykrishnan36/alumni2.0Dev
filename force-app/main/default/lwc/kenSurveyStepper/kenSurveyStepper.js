import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenSurveyStepper extends LightningElement {
    @api currentStep = 1;
    @api isStep1Completed = false;
    @api isStep2Completed = false;
    @api isStep3Completed = false;
    @api isStep4Completed = false;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
    get stepperItems() {
        const steps = [
            { number: 1, label: 'About Survey', completed: this.isStep1Completed },
            { number: 2, label: 'Target Audience', completed: this.isStep2Completed },
            { number: 3, label: 'Setup Survey', completed: this.isStep3Completed },
            { number: 4, label: 'Summary', completed: this.isStep4Completed }
        ];

        const totalSteps = steps.length;

        return steps.map(step => {
            const isActive = this.currentStep === step.number;
            // A step is completed only if it was explicitly marked as completed AND it's not the current step
            const isCompleted = (step.completed || this.currentStep > step.number) && !isActive;
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
        return `Step ${this.currentStep} out of 4`;
    }

    get progressFillStyle() {
        const progress = Math.min(100, ((this.currentStep - 1) / 3) * 100);
        return `width:${progress}%`;
    }
}