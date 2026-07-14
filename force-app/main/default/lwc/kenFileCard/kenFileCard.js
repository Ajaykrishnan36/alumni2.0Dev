import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenFileCard extends LightningElement {
    @api file;

    get fileTitle() {
        return this.file?.title || '';
    }

    get uploadedDate() {
        if (!this.file?.uploadedDate) return '';
        const date = new Date(this.file.uploadedDate);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${date.getDate()} ${months[date.getMonth()]}, ${date.getFullYear()}`;
    }

    get fileType() {
        return this.file?.fileType || 'FILE';
    }

    get fileTypeClass() {
        const type = this.fileType.toLowerCase();
        const colorMap = {
            'pdf': 'file-icon pdf',
            'xls': 'file-icon xls',
            'doc': 'file-icon doc',
            'jpg': 'file-icon jpg',
            'jpeg': 'file-icon jpg',
            'png': 'file-icon jpg',
            'mp3': 'file-icon mp3',
            'mp4': 'file-icon mp4'
        };
        return colorMap[type] || 'file-icon default';
    }

    get uploaderName() {
        return this.file?.uploaderName || '';
    }

    get uploaderImageUrl() {
        return this.file?.uploaderImageUrl || '/assets/images/default-profile.png';
    }

    handleCardClick(event) {
        this.dispatchEvent(
            new CustomEvent('fileclick', {
                detail: {
                    fileId: this.file.id
                }
            })
        );
    }

    handleAvatarError(event) {
        event.target.src = '/assets/images/default-profile.png';
    }

    renderedCallback() {
        const profileImages = this.template.querySelectorAll('[data-profile-image="true"]');
        profileImages.forEach(img => {
            if (!img.src || img.src === '' || img.src.includes('undefined')) {
                img.src = '/assets/images/default-profile.png';
            }
            img.addEventListener('error', () => {
                img.src = '/assets/images/default-profile.png';
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