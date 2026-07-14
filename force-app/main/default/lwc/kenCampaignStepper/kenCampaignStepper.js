import { LightningElement, api } from 'lwc';
import { getPortalConfigs } from 'c/kenThemeConfig';

export default class KenCampaignStepper extends LightningElement {
    @api currentStep = 1;
    @api isStep1Completed = false;
    @api isStep2Completed = false;
    @api isStep3Completed = false;

    connectedCallback() {
        getPortalConfigs().then(configs => {
            if (configs) {
                document.documentElement.style.setProperty('--primary-color', configs.primaryColor || '#1E40AF');
                document.documentElement.style.setProperty('--secondary-color', configs.secondaryColor || '#60A563');
            }
        }).catch(error => {
            console.error('Error fetching portal configs:', error);
        });
    }

    get stepperItems() {
        const steps = [
            { number: 1, label: 'Setup Campaign', completed: this.isStep1Completed },
            { number: 2, label: 'Target Audience', completed: this.isStep2Completed },
            { number: 3, label: 'Summary', completed: this.isStep3Completed }
        ];

        const totalSteps = steps.length;

        return steps.map(step => {
            const isActive = this.currentStep === step.number;
            const isCompleted = (step.completed || this.currentStep > step.number) && !isActive;

            return {
                ...step,
                isActive,
                isCompleted,
                isLast: step.number === totalSteps,
                statusClass: `step ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''}`.trim(),
                lineClass: isCompleted ? 'step-line completed' : 'step-line'
            };
        });
    }

    get stepIndicatorLabel() {
        return `Step ${this.currentStep} out of 3`;
    }

    get progressFillStyle() {
        // Step 1: 33%, Step 2: 66%, Step 3: 100%
        const progress = Math.min(100, (this.currentStep / 3) * 100);
        return `width:${progress}%`;
    }
}