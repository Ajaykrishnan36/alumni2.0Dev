import { LightningElement, api } from 'lwc';
import SurveyEmptyImage from '@salesforce/resourceUrl/SurveyEmptyImage';

export default class KenGroupsJoined extends LightningElement {

    @api groups = [];

    SurveyEmptyImageUrl = SurveyEmptyImage;

    get hasGroups() {
        return this.groups && this.groups.length > 0;
    }

    handleDiscover() {
        this.dispatchEvent(new CustomEvent('discover'));
    }

    handleViewAll() {
        this.dispatchEvent(new CustomEvent('viewalljoined'));
    }

    handleGroupClick(event) {
        const groupId = event.currentTarget.dataset.groupId;
        this.dispatchEvent(new CustomEvent('groupclick', {
            detail: { groupId },
            bubbles: true,
            composed: true
        }));
    }

    // Bubble up a leave request to the parent kenGroups component
    handleLeave(event) {
        const groupId        = event.currentTarget.dataset.groupId;
        const memberRecordId = event.currentTarget.dataset.memberRecordId;
        this.dispatchEvent(
            new CustomEvent('leavegroup', {
                detail: { groupId, memberRecordId },
                bubbles: true,
                composed: true
            })
        );
    }
}