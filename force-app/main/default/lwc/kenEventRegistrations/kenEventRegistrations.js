import { LightningElement, api, wire, track } from 'lwc';
import getEventParticipants from '@salesforce/apex/KenPortalEventController.getEventParticipants';

const COLUMNS = [
    { label: 'Participant', fieldName: 'name', type: 'text', sortable: true, wrapText: true },
    { label: 'Type', fieldName: 'type', type: 'text', initialWidth: 90 },
    { label: 'Batch', fieldName: 'batch', type: 'text', initialWidth: 90 },
    { label: 'Email', fieldName: 'email', type: 'email' },
    { label: 'Phone', fieldName: 'phone', type: 'phone', initialWidth: 130 },
    { label: 'Sessions', fieldName: 'sessionsCount', type: 'number', initialWidth: 100,
        cellAttributes: { alignment: 'left' } },
    { label: 'Meals', fieldName: 'mealsLabel', type: 'text', initialWidth: 80 },
    { label: 'Dietary Pref.', fieldName: 'diet', type: 'text', initialWidth: 130 },
    { label: 'Form Filled', fieldName: 'formLabel', type: 'text', initialWidth: 110 },
    { label: 'Registered On', fieldName: 'registeredOn', type: 'date', initialWidth: 160,
        typeAttributes: { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' } }
];

/**
 * Internal-side view of an event's registrations. The portal host sees this on the
 * event detail page's Participants tab; there is no lookup from Ken_Event_Booking__c
 * to the event, so a related list cannot show it and this reads the same Apex the
 * portal does.
 */
export default class KenEventRegistrations extends LightningElement {
    @api recordId;
    @api title = 'Registrations';

    @track participants = [];
    @track error;
    isLoading = true;
    columns = COLUMNS;

    @wire(getEventParticipants, { eventId: '$recordId' })
    wiredParticipants({ data, error }) {
        if (data) {
            this.participants = data.map(p => ({
                ...p,
                mealsLabel: p.mealsIncluded ? 'Yes' : 'No',
                diet: p.diet || '—',
                batch: p.batch || '—',
                formLabel: p.customFormFilled ? 'Yes' : 'No'
            }));
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = error?.body?.message || error?.message || 'Unable to load registrations.';
            this.participants = [];
            this.isLoading = false;
        }
    }

    get hasParticipants() {
        return this.participants.length > 0;
    }

    get cardTitle() {
        return `${this.title} (${this.participants.length})`;
    }

    get totalSeats() {
        return this.participants.reduce((sum, p) => sum + (p.sessionsCount || 0), 0);
    }

    get mealsOptedCount() {
        return this.participants.filter(p => p.mealsIncluded).length;
    }

    get formFilledCount() {
        return this.participants.filter(p => p.customFormFilled).length;
    }

    handleDownloadCsv() {
        const header = ['Participant', 'Type', 'Batch', 'Email', 'Phone', 'Sessions',
            'Meals', 'Dietary Preference', 'Form Filled', 'Registered On'];
        const esc = v => {
            const s = v === null || v === undefined ? '' : String(v);
            return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
        };
        const rows = this.participants.map(p => [
            p.name, p.type, p.batch, p.email, p.phone, p.sessionsCount,
            p.mealsLabel, p.diet, p.formLabel, p.registeredOn
        ].map(esc).join(','));
        const csv = [header.join(','), ...rows].join('\n');
        const link = document.createElement('a');
        link.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        link.download = `event_registrations_${this.recordId}.csv`;
        link.click();
    }
}