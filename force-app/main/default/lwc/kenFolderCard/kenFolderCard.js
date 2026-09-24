import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import defaultProfileImage from '@salesforce/resourceUrl/defaultProfileImage';
export default class KenFolderCard extends LightningElement {
    @api folder;

    get folderName() {
        return this.folder?.name || '';
    }

    get lastUpdatedDate() {
        return this.folder?.lastUpdatedDate || '';
    }

    get ownerName() {
        return this.folder?.ownerName || '';
    }

    get ownerProfileImageUrl() {
        return this.folder?.ownerProfileImageUrl || defaultProfileImage;
    }

    get collaboratorsCount() {
        return this.folder?.collaboratorsCount || 0;
    }

    get hasCollaborators() {
        return this.collaboratorsCount > 0;
    }

    handleCardClick(event) {
        this.dispatchEvent(
            new CustomEvent('folderclick', {
                detail: {
                    folderId: this.folder.id
                }
            })
        );
    }

    handleAvatarError(event) {
        event.target.src = defaultProfileImage;
    }

    renderedCallback() {
        const profileImages = this.template.querySelectorAll('[data-profile-image="true"]');
        profileImages.forEach(img => {
            if (!img.src || img.src === '' || img.src.includes('undefined')) {
                img.src = defaultProfileImage;
            }
            img.addEventListener('error', () => {
                img.src = defaultProfileImage;
            });
        });
    }
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
}