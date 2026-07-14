import { LightningElement, api } from 'lwc';

export default class KenGivingRecognitionV2 extends LightningElement {
    @api contributors = [];
    @api topBatches = [];
    @api corporateSupporters = [];
    @api anonymousCount = 0;

    get rankedBatches() {
        return (this.topBatches || []).map((b, i) => ({ ...b, rank: i + 1 }));
    }
    get anonText() {
        return `${this.anonymousCount} fully anonymous not shown`;
    }
}