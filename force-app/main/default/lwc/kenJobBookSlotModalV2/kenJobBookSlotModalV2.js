import { LightningElement, api, track } from 'lwc';

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const TIME_SLOTS = [
    { id: 't1', period: 'Morning',   label: '09:00 AM IST' },
    { id: 't2', period: 'Morning',   label: '10:30 AM IST' },
    { id: 't3', period: 'Afternoon', label: '02:30 PM IST' },
    { id: 't4', period: 'Afternoon', label: '03:30 PM IST' }
];

export default class KenJobBookSlotModalV2 extends LightningElement {
    @api job = {};

    @track selectedDayKey = '';
    @track selectedSlotId = '';

    connectedCallback() {
        const days = this.buildDays();
        if (days.length && !this.selectedDayKey) {
            this.selectedDayKey = days[0].key;
        }
        if (!this.selectedSlotId) {
            this.selectedSlotId = TIME_SLOTS[0].id;
        }
    }

    buildDays() {
        const now = new Date();
        const out = [];
        for (let i = 0; i < 5; i++) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
            const key = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
            out.push({
                key,
                dayName: DAY_NAMES[d.getDay()],
                dayNum: d.getDate(),
                monthName: MONTH_NAMES[d.getMonth()]
            });
        }
        return out;
    }

    get days() {
        const sel = this.selectedDayKey;
        return this.buildDays().map(d => ({
            ...d,
            cssClass: d.key === sel ? 'day day--selected' : 'day'
        }));
    }

    get morningSlots() {
        return TIME_SLOTS.filter(s => s.period === 'Morning').map(s => ({
            ...s,
            cssClass: s.id === this.selectedSlotId ? 'slot slot--selected' : 'slot'
        }));
    }
    get afternoonSlots() {
        return TIME_SLOTS.filter(s => s.period === 'Afternoon').map(s => ({
            ...s,
            cssClass: s.id === this.selectedSlotId ? 'slot slot--selected' : 'slot'
        }));
    }

    get jobTitle()   { return (this.job && this.job.title)   ? this.job.title   : 'Interview'; }
    get jobCompany() { return (this.job && this.job.company) ? this.job.company : ''; }

    handleDayClick(event) {
        this.selectedDayKey = event.currentTarget.dataset.key;
    }
    handleSlotClick(event) {
        this.selectedSlotId = event.currentTarget.dataset.id;
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
    stopBubble(e) { e.stopPropagation(); }
    handleBook() {
        const day  = this.days.find(d => d.key === this.selectedDayKey);
        const slot = TIME_SLOTS.find(s => s.id === this.selectedSlotId);
        const label = (day ? `${day.dayName} ${day.dayNum} ${day.monthName}` : '') +
                      (slot ? `, ${slot.label}` : '');
        this.dispatchEvent(new CustomEvent('book', {
            detail: {
                day: this.selectedDayKey,
                slotId: this.selectedSlotId,
                slot: label.trim()
            }
        }));
    }
}