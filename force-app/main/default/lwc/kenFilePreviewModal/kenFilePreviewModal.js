import { LightningElement, api } from 'lwc';

const IMAGE_TYPES = new Set(['JPG', 'JPEG', 'PNG', 'GIF', 'WEBP', 'BMP', 'SVG']);
const PDF_TYPES = new Set(['PDF']);

export default class KenFilePreviewModal extends LightningElement {
    @api show = false;
    @api fileUrl;
    @api fileTitle;
    @api fileType;

    get normalizedFileType() {
        return (this.fileType || '').toUpperCase();
    }

    get isImage() {
        return IMAGE_TYPES.has(this.normalizedFileType);
    }

    get isPdf() {
        return PDF_TYPES.has(this.normalizedFileType);
    }

    get isOther() {
        return !!this.fileUrl && !this.isImage && !this.isPdf;
    }

    get modalTitle() {
        return this.fileTitle || 'Preview';
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleContentClick(event) {
        event.stopPropagation();
    }
}