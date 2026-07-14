import { LightningElement, api } from 'lwc';

export default class KenEventsRailV2 extends LightningElement {
    @api registeredEvents = [];
    @api hostedEvents = [];

    get decoratedRegistered() {
        return (this.registeredEvents || []).map(r => ({
            ...r,
            imgStyle: `background:${r.grad || r.imgGrad || 'linear-gradient(135deg,#3061FF,#86E1FF)'}`
        }));
    }

    get hasHosted() {
        return (this.hostedEvents || []).length > 0;
    }

    // Hosted events come from real data (mapEventList): {id, title, date, time,
    // eventStatus}. Decorate for the rail: clamp the list to 5, build a date·time
    // line, and derive a status pill so the row reads as a manageable event.
    get decoratedHosted() {
        return (this.hostedEvents || []).slice(0, 5).map(h => {
            const date = h.date || '';
            const time = h.time || '';
            const dateTime = time ? `${date} · ${time}` : date;
            const raw = (h.eventStatus || '').toString();
            const key = raw.toLowerCase();
            let label = raw || 'Draft';
            let cls = 'he-status he-status--draft';
            if (key.includes('publish') || key.includes('approved') || key.includes('live')) { label = 'Published'; cls = 'he-status he-status--published'; }
            else if (key.includes('review') || key.includes('pending')) { label = 'In Review'; cls = 'he-status he-status--review'; }
            else if (key.includes('reject') || key.includes('cancel')) { label = raw; cls = 'he-status he-status--rejected'; }
            else if (key.includes('complete') || key.includes('closed')) { label = 'Completed'; cls = 'he-status he-status--done'; }
            else if (!raw) { label = 'Draft'; }
            return { id: h.id, title: h.title || 'Untitled event', dateTime, statusLabel: label, statusClass: cls };
        });
    }

    handleHostEvent() {
        this.dispatchEvent(new CustomEvent('hostevent'));
    }

    handleViewAllRegistered() {
        this.dispatchEvent(new CustomEvent('viewallregistered'));
    }

    handleViewAllHosted() {
        this.dispatchEvent(new CustomEvent('viewallhosted'));
    }

    handleHostedClick(event) {
        const id = event.currentTarget.dataset.id;
        if (id) this.dispatchEvent(new CustomEvent('hostedclick', { detail: { id } }));
    }
    handleHostedKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleHostedClick(event);
        }
    }
}