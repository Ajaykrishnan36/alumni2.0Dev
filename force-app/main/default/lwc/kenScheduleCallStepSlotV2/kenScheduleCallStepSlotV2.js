import { LightningElement, api } from 'lwc';

const SLOTS = [
    { value: '09:00 AM', state: 'on' },
    { value: '09:30 AM', state: 'off' },
    { value: '10:00 AM', state: 'on' },
    { value: '10:30 AM', state: 'on' },
    { value: '11:00 AM', state: 'on' },
    { value: '11:30 AM', state: 'off' },
    { value: '02:00 PM', state: 'on' },
    { value: '02:30 PM', state: 'on' },
    { value: '03:00 PM', state: 'on' }
];
const DURATIONS = ['15 min', '30 min', '45 min', '60 min'];

export default class KenScheduleCallStepSlotV2 extends LightningElement {
    @api selectedSlot = '';
    @api selectedDuration = '30 min';
    @api selectedDate = '';

    get slotOptions() {
        return SLOTS.map(s => {
            let cls = 'slot';
            if (s.value === this.selectedSlot) cls = 'slot slot--on';
            else if (s.state === 'off') cls = 'slot slot--off';
            return { value: s.value, cssClass: cls };
        });
    }
    get minDate() {
        const d = new Date();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${d.getFullYear()}-${mm}-${dd}`;
    }
    get durationOptions() {
        return DURATIONS.map(d => ({
            value: d,
            cssClass: d === this.selectedDuration ? 'slot slot--on' : 'slot'
        }));
    }

    handleSlot(event) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'selectedSlot', value: event.currentTarget.dataset.value } }));
    }
    handleDuration(event) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'selectedDuration', value: event.currentTarget.dataset.value } }));
    }
    handleDate(event) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'selectedDate', value: event.target.value } }));
    }
}