import { LightningElement, api, wire } from 'lwc';
import getAudienceForRecord from '@salesforce/apex/KenAudienceJunctionController.getAudienceForRecord';

/**
 * kenAudienceSummary — read-only "who will receive this" panel.
 *
 * Drop it on any module record page that can carry an audience (event, survey, group,
 * campaign). It resolves the saved audience from that record itself, so the same component
 * works everywhere with no per-page configuration.
 */
export default class KenAudienceSummary extends LightningElement {
    @api recordId;
    @api title = 'Target Audience';

    audience;
    error;

    @wire(getAudienceForRecord, { recordId: '$recordId' })
    wiredAudience({ data, error }) {
        if (data) {
            this.audience = data;
            this.error = undefined;
        } else if (error) {
            this.error = error?.body?.message || 'Unable to load the audience.';
            this.audience = undefined;
        }
    }

    get isLoading() {
        return !this.audience && !this.error;
    }

    // The template renders before the wire resolves, so every field is read through a getter
    // rather than reaching into `audience` directly.
    get reachLabel() {
        return this.audience?.reachLabel;
    }

    get segmentationName() {
        return this.audience?.segmentationName;
    }

    get matchLabel() {
        return this.audience?.matchLabel;
    }

    get simpleAudienceList() {
        return this.audience?.simpleAudience || [];
    }

    get hasAudience() {
        return this.audience?.hasAudience === true;
    }

    get hasBlocks() {
        return (this.audience?.blocks?.length || 0) > 0;
    }

    get hasSimpleAudience() {
        return (this.audience?.simpleAudience?.length || 0) > 0;
    }

    get showMatchLabel() {
        return !!this.audience?.matchLabel;
    }

    get blocks() {
        return (this.audience?.blocks || []).map((b, index) => ({
            key: `${b.title}-${index}`,
            title: b.title,
            roleLabel: b.roleLabel,
            typeLabel: b.typeLabel,
            memberLabel: this.memberLabel(b.memberCount),
            hasCriteria: (b.criteria?.length || 0) > 0,
            criteria: (b.criteria || []).map((c, ci) => ({ key: `${index}-${ci}`, text: c }))
        }));
    }

    memberLabel(count) {
        if (count === null || count === undefined) {
            return '';
        }
        return count === 1 ? '1 member' : `${count} members`;
    }
}