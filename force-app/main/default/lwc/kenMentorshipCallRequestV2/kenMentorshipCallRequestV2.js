import { LightningElement, api, track } from 'lwc';
import respondToCallRequest from '@salesforce/apex/KenMentorshipController.respondToCallRequest';
import proposeReschedule from '@salesforce/apex/KenMentorshipController.proposeReschedule';
import acceptReschedule from '@salesforce/apex/KenMentorshipController.acceptReschedule';

export default class KenMentorshipCallRequestV2 extends LightningElement {
    @api mentorshipId;
    @api requesterName = 'Alumni';
    @api meetingTitle = 'Mentorship call';
    @api currentSlot = '';          // human-readable current slot, optional
    @api isProposed = false;        // true when the OTHER party already proposed a slot to review

    @track mode = 'detail';         // 'detail' | 'reschedule'
    @track busy = false;
    @track errorMsg = '';
    @track statusMsg = '';

    // reschedule form
    @track rDate = '';
    @track rStart = '';
    @track rEnd = '';
    @track rMode = 'Online';
    @track rLink = '';
    @track rLocation = '';

    get isDetail() { return this.mode === 'detail'; }
    get isReschedule() { return this.mode === 'reschedule'; }
    get isOnline() { return this.rMode === 'Online'; }
    get modeOptions() {
        return [{ label: 'Online (Google Meet)', value: 'Online' },
                { label: 'In-person', value: 'In-person' }];
    }
    get rescheduleInvalid() {
        if (this.busy || !this.rDate || !this.rStart || !this.rEnd) return true;
        if (this.rStart >= this.rEnd) return true;
        if (this.isOnline && !this.rLink) return true;
        if (!this.isOnline && !this.rLocation) return true;
        return false;
    }

    handleMode(e) { this.rMode = e.detail.value; }
    handleDate(e) { this.rDate = e.target.value; }
    handleStart(e) { this.rStart = e.target.value; }
    handleEnd(e) { this.rEnd = e.target.value; }
    handleLink(e) { this.rLink = e.target.value; }
    handleLocation(e) { this.rLocation = e.target.value; }

    showReschedule() { this.errorMsg = ''; this.mode = 'reschedule'; }
    backToDetail() { this.mode = 'detail'; }

    handleAccept() { this._respond('Accept', 'Request accepted.'); }
    handleDecline() { this._respond('Reject', 'Request declined.'); }

    _respond(action, okMsg) {
        this.busy = true; this.errorMsg = ''; this.statusMsg = '';
        respondToCallRequest({ callRequestId: this.mentorshipId, action })
            .then(() => {
                this.busy = false; this.statusMsg = okMsg;
                this.dispatchEvent(new CustomEvent('updated', { detail: { action } }));
            })
            .catch(e => { this.busy = false; this.errorMsg = this._msg(e); });
    }

    handleAcceptProposed() {
        this.busy = true; this.errorMsg = '';
        acceptReschedule({ mentorshipId: this.mentorshipId })
            .then(() => {
                this.busy = false; this.statusMsg = 'New slot confirmed and scheduled.';
                this.dispatchEvent(new CustomEvent('updated', { detail: { action: 'Rescheduled' } }));
            })
            .catch(e => { this.busy = false; this.errorMsg = this._msg(e); });
    }

    submitReschedule() {
        if (this.rescheduleInvalid) return;
        this.busy = true; this.errorMsg = '';
        proposeReschedule({
            mentorshipId: this.mentorshipId,
            meetDate: this.rDate,
            startTime: this.rStart,
            endTime: this.rEnd,
            mode: this.rMode,
            link: this.isOnline ? this.rLink : null,
            location: this.isOnline ? null : this.rLocation
        })
            .then(() => {
                this.busy = false; this.statusMsg = 'New slot suggested. Waiting for confirmation.';
                this.dispatchEvent(new CustomEvent('updated', { detail: { action: 'Reschedule Proposed' } }));
            })
            .catch(e => { this.busy = false; this.errorMsg = this._msg(e); });
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    stopBubble(e) { e.stopPropagation(); }
    _msg(e) { return (e && e.body && e.body.message) || 'Something went wrong. Please try again.'; }
}