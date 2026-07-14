import { LightningElement, api } from 'lwc';

const DOW = ['S','M','T','W','T','F','S'];
const CAL_DAYS = [null,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31];

export default class KenMentorshipCalendarV2 extends LightningElement {
    @api today = 12;
    @api eventsOn = [7,21,26,27];
    @api monthLabel = 'December 2025';

    get dayHeaders() {
        return DOW.map((d, i) => ({ key: `dow-${i}`, label: d }));
    }
    get calendarRows() {
        const set = this.eventsOn || [];
        return CAL_DAYS.map((d, i) => ({
            key: `cal-${i}`,
            label: d == null ? '' : String(d),
            cssClass: this._cls(d, set)
        }));
    }
    _cls(d, set) {
        if (d == null) return 'cal__d cal__d--empty';
        if (d === this.today) return 'cal__d cal__d--today';
        if (set.indexOf(d) >= 0) return 'cal__d cal__d--has';
        return 'cal__d';
    }
}