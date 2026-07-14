import { LightningElement, api } from 'lwc';

export default class KenMentorProfilePageV2 extends LightningElement {
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
        // Apex sometimes returns null entries; filter & wrap with a stable id so for:each key stays unique.
        const list = (this.mentor && this.mentor.expertise) || [];
        return list.filter(Boolean).map((e, i) => ({ id: `${i}-${e}`, label: e }));
    }
    // Guard hero meta fields that are bound directly in the template.
    get mentorCity()       { return (this.mentor && this.mentor.city) || ''; }
    get mentorBatch()      { return (this.mentor && this.mentor.batch) || ''; }
    get mentorExperience() { return (this.mentor && this.mentor.experience) || ''; }
    get mentorLanguages()  { return (this.mentor && this.mentor.languages) || ''; }
    get mentorBio()        { return (this.mentor && this.mentor.bio) || 'This mentor hasn\'t added a bio yet.'; }
    get hasExpertise()     { return this.expertise.length > 0; }

    get reviews() {
        const list = (this.mentor && this.mentor.reviews) || [];
        return list.map(r => ({
            ...r,
            avStyle: `background:${r.color || '#67A1C8'};color:#fff;`
        }));
    }

    get hasReviews() { return this.reviewCount > 0; }

    get availability() {
        return (this.mentor && this.mentor.availability) || [];
    }

    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
    handleBook() {
        this.dispatchEvent(new CustomEvent('book', { detail: { id: this.mentor && this.mentor.id } }));
    }
    handleMessage() {
        this.dispatchEvent(new CustomEvent('message', { detail: { id: this.mentor && this.mentor.id } }));
    }
}