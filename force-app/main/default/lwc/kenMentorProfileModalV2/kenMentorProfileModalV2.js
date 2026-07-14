import { LightningElement, api } from 'lwc';

export default class KenMentorProfileModalV2 extends LightningElement {
    @api mentor;

    get hasMentor() { return !!this.mentor; }

    get avatarStyle() {
        const c = (this.mentor && this.mentor.color) ? this.mentor.color : '#EAEFFF';
        return `background:linear-gradient(135deg, ${c}, #B033C8);color:#fff;`;
    }

    get roleLine() {
        if (!this.mentor) return '';
        const r = this.mentor.role || '';
        const c = this.mentor.company || '';
        return c ? `${r} · ${c}` : r;
    }

    get ratingDisplay() {
        return (this.mentor && this.mentor.rating) ? this.mentor.rating : '—';
    }

    get reviewCount() {
        return (this.mentor && this.mentor.reviews) ? this.mentor.reviews.length : 0;
    }

    get reviewsHeading() {
        return `Reviews · ${this.reviewCount}`;
    }

    get expertise() {
        return (this.mentor && this.mentor.expertise) || [];
    }

    get reviews() {
        const list = (this.mentor && this.mentor.reviews) || [];
        return list.map(r => ({
            ...r,
            avStyle: `background:${r.color || '#67A1C8'};color:#fff;`
        }));
    }

    get hasReviews() {
        return this.reviewCount > 0;
    }

    get availability() {
        return (this.mentor && this.mentor.availability) || [];
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
    handleBook() {
        this.dispatchEvent(new CustomEvent('book', { detail: { id: this.mentor && this.mentor.id } }));
    }
    handleMessage() {
        this.dispatchEvent(new CustomEvent('message', { detail: { id: this.mentor && this.mentor.id } }));
    }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
    handleStop(event) { event.stopPropagation(); }
}