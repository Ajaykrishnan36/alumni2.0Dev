import { LightningElement, api } from 'lwc';

export default class ExperienceCard extends LightningElement {
    @api position;
    @api company;
    @api employmentType;
    @api location;
    @api workType;
    @api duration;
    @api companyLogo;

    get displayLogo() {
        return this.companyLogo || '/assets/images/default-company-logo.png';
    }

    handleLogoError(event) {
        if (event && event.target) {
            event.target.style.display = 'none';
        }
    }
}