import { LightningElement, api } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

export default class KenMenteeHeader extends LightningElement {
    @api name;
    @api title;
    @api company;
    @api location;
    @api profileImage;
    @api isOnline = false;
    @api batch;
    @api expertise;
    @api email;
    @api phone;
    @api linkedin;
    @api willingToHelp = false;

    get displayImage() {
        return this.profileImage || defaultProfileImage;
    }

    get companyLogo() {
        // Return company logo based on company name
        if (this.company === 'Turbostart') {
            return '/assets/images/turbostart-logo.png';
        }
        return '/assets/images/default-company-logo.png';
    }

    handleImageError(event) {
        if (event && event.target) {
            event.target.src = defaultProfileImage;
        }
    }

    handleCompanyLogoError(event) {
        if (event && event.target) {
            event.target.style.display = 'none';
        }
    }
}