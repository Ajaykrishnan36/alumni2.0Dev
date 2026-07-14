import { LightningElement, api } from 'lwc';

export default class KenAlumniBusinessesCardV2 extends LightningElement {
    @api businesses = [];

    get hasBusinesses() { return (this.businesses || []).length > 0; }
}