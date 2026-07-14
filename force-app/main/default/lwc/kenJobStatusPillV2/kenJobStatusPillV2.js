import { LightningElement, api } from 'lwc';

const STATUS_MAP = {
    submitted: { label: 'Submitted',    cls: 'pill pill--info'    },
    review:    { label: 'Under Review', cls: 'pill pill--warn'    },
    interview: { label: 'Interview',    cls: 'pill pill--accent'  },
    offer:     { label: 'Offer',        cls: 'pill pill--success' },
    rejected:  { label: 'Rejected',     cls: 'pill pill--danger'  }
};

export default class KenJobStatusPillV2 extends LightningElement {
    @api status = '';

    get hasStatus() {
        return !!STATUS_MAP[this.status];
    }
    get pillClass() {
        const s = STATUS_MAP[this.status];
        return s ? s.cls : 'pill';
    }
    get pillLabel() {
        const s = STATUS_MAP[this.status];
        return s ? s.label : '';
    }
}