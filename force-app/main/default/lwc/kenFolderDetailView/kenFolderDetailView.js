import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenFolderDetailView extends LightningElement {
    @api folder;
    @track files = [];

    connectedCallback() {
        // Load files for this folder
        // For now, using empty array - will be populated from API
        this.files = [];
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    get folderName() {
        return this.folder?.name || 'Folder';
    }

    get isEmpty() {
        return !this.files || this.files.length === 0;
    }

    handleFileClick(event) {
        const fileId = event.detail.fileId;
        console.log('File clicked:', fileId);
    }
}