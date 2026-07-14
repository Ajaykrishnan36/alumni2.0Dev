import { LightningElement, api } from 'lwc';

export default class KenConnectionRequestsSection extends LightningElement {
    @api requests = [];

    get requestsCount() {
        return this.requests.length;
    }

    get hasRequests() {
        return this.requests && this.requests.length > 0;
    }

    handleAccept(event) {
        this.dispatchEvent(new CustomEvent('acceptrequest', {
            detail: { id: event.detail.id }
        }));
    }

    handleDecline(event) {
        this.dispatchEvent(new CustomEvent('declinerequest', {
            detail: { id: event.detail.id }
        }));
    }
}