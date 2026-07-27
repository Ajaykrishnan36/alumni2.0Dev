import { LightningElement, api } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

export default class KenOnlineUserItem extends LightningElement {
    @api name;
    @api batch;
    @api profession;
    @api profileImage;
    @api willingToHelp = false;

    get displayImage() {
        return this.profileImage || defaultProfileImage;
    }

    handleAvatarError(event) {
        if (event && event.target) {
            event.target.src = defaultProfileImage;
        }
    }
}