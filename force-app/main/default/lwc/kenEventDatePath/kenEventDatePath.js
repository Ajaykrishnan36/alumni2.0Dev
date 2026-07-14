/* eslint-disable no-magic-numbers */
import { LightningElement, api, track } from 'lwc';

const HOURS_PER_DAY = 24,
 MINUTES_PER_HOUR = 60,
 MS_PER_SECOND = 1000,
 SECONDS_PER_MINUTE = 60;

export default class KenEventDatePath extends LightningElement {
    @api startDate;
    @api endDate;
    @track datePath = [];

    selectedDate = '';

    static DAY_MS =
        HOURS_PER_DAY * MINUTES_PER_HOUR * SECONDS_PER_MINUTE * MS_PER_SECOND;

    connectedCallback() {
        if (this.startDate && this.endDate) {
            this.generateDatePath(new Date(this.startDate), new Date(this.endDate));
        } else if (this.startDate) {
            const dateStr = EventDatePath.toISODate(new Date(this.startDate));
            this.datePath = [{ className: '', date: dateStr }];
        }
    }

    static toISODate(date) {
        const [ymd] = date.toISOString().split('T');
        return ymd;
    }

    generateDatePath(start, end) {
        const endTs = new Date(end).getTime(),
        startTs = new Date(start).getTime();

        this.datePath = [];
        for (let ts = startTs; ts <= endTs; ts += EventDatePath.DAY_MS) {
            const currentDate = new Date(ts),
                dateStr = EventDatePath.toISODate(currentDate);

            let className = '';
            if (dateStr === this.selectedDate) {
                className = 'active';
            }

            this.datePath.push({
                className,
                date: dateStr
            });
        }
    }

    handleDateClick(event) {
        const clickedDate = event.target.dataset.date;
        this.selectedDate = clickedDate;

        this.datePath = this.datePath.map((item) => {
            let className = '';
            if (item.date === this.selectedDate) {
                className = 'active';
            }
            return { className, date: item.date };
        });
    }
}