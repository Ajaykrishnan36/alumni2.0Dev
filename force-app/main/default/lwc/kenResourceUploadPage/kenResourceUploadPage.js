import { LightningElement, track, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenResourceUploadPage extends LightningElement {
    @api source = 'files';
    @track uploadedFiles = [];
    @track fileTitle = '';
    @track category = '';
    @track description = '';

    categoryOptions = [
        { label: 'Select', value: '' },
        { label: 'Documents', value: 'documents' },
        { label: 'Images', value: 'images' },
        { label: 'Videos', value: 'videos' },
        { label: 'Audio', value: 'audio' },
        { label: 'Other', value: 'other' }
    ];

    get hasFiles() {
        return this.uploadedFiles.length > 0;
    }

    get hasNoFiles() {
        return !this.hasFiles;
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

    get fileType() {
        if (this.uploadedFiles.length > 0) {
            const fileName = this.uploadedFiles[0].name;
            const extension = fileName.split('.').pop().toUpperCase();
            return extension;
        }
        return 'FILE';
    }

    get fileTypeIconClass() {
        const type = this.fileType.toLowerCase();
        const colorMap = {
            'pdf': 'file-icon pdf',
            'xls': 'file-icon xls',
            'xlsx': 'file-icon xls',
            'doc': 'file-icon doc',
            'docx': 'file-icon doc',
            'jpg': 'file-icon jpg',
            'jpeg': 'file-icon jpg',
            'png': 'file-icon jpg',
            'mp3': 'file-icon mp3',
            'mp4': 'file-icon mp4'
        };
        return colorMap[type] || 'file-icon default';
    }

    get fileSize() {
        if (this.uploadedFiles.length > 0) {
            const size = this.uploadedFiles[0].size;
            if (size < 1024) {
                return size + ' B';
            } else if (size < 1024 * 1024) {
                return (size / 1024).toFixed(2) + ' KB';
            } else {
                return (size / (1024 * 1024)).toFixed(2) + ' MB';
            }
        }
        return '';
    }

    handleUploadClick(event) {
        const fileInput = this.template.querySelector('[data-file-input="true"]');
        if (fileInput && !event.target.closest('.delete-file-btn')) {
            fileInput.click();
        }
    }

    handleFileSelect(event) {
        const files = Array.from(event.target.files);
        const maxSize = 16 * 1024 * 1024; // 16 MB
        const allowedTypes = [
            'application/pdf',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/vnd.ms-excel',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'image/jpeg',
            'image/png',
            'image/jpg',
            'audio/mpeg',
            'video/mp4'
        ];

        files.forEach(file => {
            if (file.size > maxSize) {
                console.error(`File ${file.name} exceeds maximum size of 16 MB`);
                return;
            }

            if (!allowedTypes.includes(file.type)) {
                console.error(`File ${file.name} is not a supported format`);
                return;
            }

            const fileData = {
                id: Date.now().toString() + Math.random().toString(36).substr(2, 9),
                name: file.name,
                size: file.size,
                type: file.type,
                file: file
            };

            this.uploadedFiles = [...this.uploadedFiles, fileData];
        });

        // Reset file input
        event.target.value = '';
    }

    handleRemoveFile(event) {
        const fileId = event.currentTarget.dataset.fileId;
        this.uploadedFiles = this.uploadedFiles.filter(file => file.id !== fileId);
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        const uploadArea = this.template.querySelector('[data-upload-area="true"]');
        if (uploadArea) {
            uploadArea.classList.remove('drag-over');
        }

        const files = Array.from(event.dataTransfer.files);
        const fileInput = this.template.querySelector('[data-file-input="true"]');
        if (fileInput) {
            const dataTransfer = new DataTransfer();
            files.forEach(file => dataTransfer.items.add(file));
            fileInput.files = dataTransfer.files;
            this.handleFileSelect({ target: fileInput });
        }
    }

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        const uploadArea = this.template.querySelector('[data-upload-area="true"]');
        if (uploadArea) {
            uploadArea.classList.add('drag-over');
        }
    }

    handleDragLeave(event) {
        event.preventDefault();
        event.stopPropagation();
        const uploadArea = this.template.querySelector('[data-upload-area="true"]');
        if (uploadArea) {
            uploadArea.classList.remove('drag-over');
        }
    }

    handleTitleChange(event) {
        this.fileTitle = event.target.value;
    }

    handleCategoryChange(event) {
        this.category = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handlePost() {
        if (this.uploadedFiles.length === 0) {
            return;
        }

        const resourceData = {
            files: this.uploadedFiles,
            title: this.fileTitle,
            category: this.category,
            description: this.description,
            source: this.source
        };

        this.dispatchEvent(
            new CustomEvent('post', {
                detail: resourceData
            })
        );
    }
}