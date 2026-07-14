import { LightningElement, api } from 'lwc';

export default class KenAlumniCardV2 extends LightningElement {
    @api recordId;
    @api name;
    @api title;
    @api company;
    @api expertise;
    @api education;
    @api graduationYear;
    @api location;
    @api batch;
    @api profileImage;
    @api willingToHelp = false;
    @api isMentor = false;
    @api isOnline = false;
    @api linkedin;
    @api avatarColor;
    @api initial;
    @api connected = false;

    get avatarStyle() {
        const col = this.avatarColor || '#EAEFFF';
        return `background:${col};color:#1F2937;`;
    }
    get statusClass() {
        // Defensive boolean — booleans crossing Apex→LWC sometimes arrive as the string 'true'.
        const online = this.isOnline === true || this.isOnline === 'true';
        return online ? 'alum__status alum__status--online' : 'alum__status alum__status--offline';
    }
    get showWilling() { return this.willingToHelp === true || this.willingToHelp === 'true'; }
    get displayInitial() {
        if (this.initial) return this.initial;
        const n = (this.name || '').trim();
        return n ? n.charAt(0).toUpperCase() : '';
    }
    get cityLine() { return this.location ? `📍 ${this.location}` : ''; }

    handleView() {
        this.dispatchEvent(new CustomEvent('alumniclick', { detail: { id: this.recordId } }));
    }
}