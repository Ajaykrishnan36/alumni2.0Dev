import { LightningElement, api, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";

export default class KenCreateEventSetup extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isEventSetup = true;
    @track isFeeSetup = true;
    @track isEventWise;
    @track isSessionWise;
    @track eventNoFee = false; // Add this property
    @track selectedEventDates = [];
    @track storedSelectedDates = [];
    @track state = {
        currentState: "eventSetup",
        eventRecordId: ""
    };
    @track barValue;

    get steps() {
        const baseSteps = [
            { label: "Event setup", value: "eventSetup" },
            { label: "Date selection", value: "dateSelection" },
            { label: "Schedule setup", value: "scheduleSetup" }
        ];

        // Only add fee setup if it's not a no-fee event
        if (!this.eventNoFee) {
            baseSteps.push({ label: "Fee setup", value: "feeSetup" });
        }

        baseSteps.push({ label: "Summary", value: "summary" });

        return baseSteps;
    }

    get currentStep() {
        return this.state.currentState;
    }

    // Remove the isEventSetup getter - use the tracked property instead

    get progressBarValue() {
        const totalSteps = this.steps.length;
        const currentIndex = this.steps.findIndex(step => step.value === this.currentStep);
        if (totalSteps === 0) {
            return 0;
        }
        return ((currentIndex) / totalSteps) * 100;
    }

    get currentStepLabel() {
        const stepIndex = this.steps.findIndex(step => step.value === this.currentStep);
        return `Step ${stepIndex + 1} out of ${this.steps.length}`;
    }

    get eventRecordId() {
        console.log('this.recordId====' + this.recordId);
        this.state.eventRecordId = this.recordId
            ? this.recordId
            : this.state.eventRecordId;
        return this.state.eventRecordId;
    }

    get showEvent() {
        return this.state.currentState === "eventSetup";
    }

    get showDateSelection() {
        return this.state.currentState === "dateSelection";
    }

    get showEventSchedule() {
        console.log('Inside showEventSchedule--' + this.state.currentState);
        return this.state.currentState === "scheduleSetup";
    }

    get showFeeSetup() {
        console.log('isEventWise--' + this.isEventWise);
        console.log('sessionwise--' + this.isSessionWise);
        return this.state.currentState === "feeSetup";
    }

    get showSummary() {
        return this.state.currentState === "summary";
    }

    handleEvent(event) {
        const eventData = event.detail;
        this.recordId = eventData.eventId;
        this.eventNoFee = eventData.noFee;

        this.state.currentState = "dateSelection";
    }

    handleDateSelection({ detail }) {
        this.recordId = detail.eventId;
        this.selectedEventDates = detail.selectedDates;
        this.storedSelectedDates = [...detail.selectedDates];
        this.state.currentState = "scheduleSetup";
    }

    handlePrevious({ detail }) {
        this.state.currentState = detail;

        if (detail === 'dateSelection') {
            this.isEventWise = false;
            this.isSessionWise = false;
        } else if (detail === 'eventSetup') {
            this.storedSelectedDates = [];
        }
    }

    handleEventSchedule({ detail }) {
        console.log('Handling event schedule, eventId:', detail.eventId);
        this.recordId = detail.eventId;

        // Check the type of event schedule completion
        if (detail.type === 'NoFee' || this.eventNoFee) {
            console.log('Skipping fee setup - No Fee event');
            this.state.currentState = "summary";
        } else {
            this.state.currentState = "feeSetup";
            if (detail.type == 'Event') {
                this.isEventWise = detail.value;
            } else if (detail.type == 'Session') {
                this.isSessionWise = detail.value;
            }
        }
        console.log('Current State:', this.state.currentState);
        console.log('value: ' + detail.value + ',type:' + detail.type);

        /*this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: this.eventRecordId,
            actionName: "view"
          }
        });*/
    }
    get feeSetup() {
        return this.isFeeSetup;
    }

    handleFeeSetup({ detail }) {
        console.log('handleFeeSetupParent:', detail.eventId);
        this.recordId = detail.eventId;
        this.state.currentState = "summary";
        console.log('Current State:', this.state.currentState);
    }
    handleSummary() {
        /*this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: this.eventRecordId,
            actionName: "view"
          }
        });*/
    }
}