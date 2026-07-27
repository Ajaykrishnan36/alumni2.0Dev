import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenImageCropModal extends LightningElement {
    _imageUrl;
    // Resetting the geometry when the source changes covers both the initial
    // open and the "Choose a different image" swap.
    @api
    get imageUrl() {
        return this._imageUrl;
    }
    set imageUrl(value) {
        this._imageUrl = value;
        this.naturalWidth = 0;
        this.naturalHeight = 0;
        this.userScale = 1;
        this.offsetX = 0;
        this.offsetY = 0;
    }

    @track naturalWidth = 0;
    @track naturalHeight = 0;
    @track userScale = 1;
    @track offsetX = 0;
    @track offsetY = 0;

    isDragging = false;
    startX = 0;
    startY = 0;
    viewport = 400;
    outputSize = 400;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    // =========================================================
    // Geometry (all derived from the natural image + user gestures)
    // =========================================================
    get imageReady() {
        return this.naturalWidth > 0 && this.naturalHeight > 0;
    }

    // Scale at which the image just covers the circular viewport.
    get coverScale() {
        if (!this.imageReady) {
            return 1;
        }
        return Math.max(this.viewport / this.naturalWidth, this.viewport / this.naturalHeight);
    }

    get totalScale() {
        return this.coverScale * this.userScale;
    }

    // Inline style for the preview <img>: sized in real pixels and centered on
    // the viewport, then panned by the drag offset.
    get imageStyle() {
        if (!this.imageReady) {
            return 'opacity: 0;';
        }
        const w = this.naturalWidth * this.totalScale;
        const h = this.naturalHeight * this.totalScale;
        return `width:${w}px; height:${h}px; transform: translate(-50%, -50%) translate(${this.offsetX}px, ${this.offsetY}px);`;
    }

    handleImageOnLoad(event) {
        const img = event.target;
        const vp = this.template.querySelector('.crop-viewport');
        this.viewport = (vp && vp.getBoundingClientRect().width) || 400;
        this.naturalWidth = img.naturalWidth || 1;
        this.naturalHeight = img.naturalHeight || 1;
        this.userScale = 1;
        this.offsetX = 0;
        this.offsetY = 0;
    }

    handleImageError() {
        this.showToast('Error', 'Failed to load image. Please try again.', 'error');
    }

    // Keep the image covering the viewport (no empty edges inside the circle).
    constrainOffset() {
        const dispW = this.naturalWidth * this.totalScale;
        const dispH = this.naturalHeight * this.totalScale;
        const maxX = Math.max(0, (dispW - this.viewport) / 2);
        const maxY = Math.max(0, (dispH - this.viewport) / 2);
        this.offsetX = Math.min(maxX, Math.max(-maxX, this.offsetX));
        this.offsetY = Math.min(maxY, Math.max(-maxY, this.offsetY));
    }

    // =========================================================
    // Pointer / touch move + wheel zoom
    // =========================================================
    handleMouseDown(event) {
        if (!this.imageReady) {
            return;
        }
        event.preventDefault();
        this.isDragging = true;
        this.startX = event.clientX - this.offsetX;
        this.startY = event.clientY - this.offsetY;
    }

    handleMouseMove(event) {
        if (!this.isDragging) {
            return;
        }
        event.preventDefault();
        this.offsetX = event.clientX - this.startX;
        this.offsetY = event.clientY - this.startY;
        this.constrainOffset();
    }

    handleMouseUp() {
        this.isDragging = false;
    }

    handleTouchStart(event) {
        if (!this.imageReady || event.touches.length !== 1) {
            return;
        }
        this.isDragging = true;
        this.startX = event.touches[0].clientX - this.offsetX;
        this.startY = event.touches[0].clientY - this.offsetY;
    }

    handleTouchMove(event) {
        if (!this.isDragging || event.touches.length !== 1) {
            return;
        }
        this.offsetX = event.touches[0].clientX - this.startX;
        this.offsetY = event.touches[0].clientY - this.startY;
        this.constrainOffset();
    }

    handleTouchEnd() {
        this.isDragging = false;
    }

    handleWheel(event) {
        if (!this.imageReady) {
            return;
        }
        event.preventDefault();
        const delta = event.deltaY > 0 ? -0.1 : 0.1;
        this.userScale = Math.min(4, Math.max(1, this.userScale + delta));
        this.constrainOffset();
    }

    // =========================================================
    // Produce the cropped circular image from the natural pixels
    // =========================================================
    handleUpload() {
        const imgEl = this.template.querySelector('.crop-image');
        if (!imgEl || !this.imageReady) {
            return;
        }
        const total = this.totalScale;
        const sSize = this.viewport / total;
        const sx = this.naturalWidth / 2 - (this.offsetX + this.viewport / 2) / total;
        const sy = this.naturalHeight / 2 - (this.offsetY + this.viewport / 2) / total;

        const out = this.outputSize;
        const canvas = document.createElement('canvas');
        canvas.width = out;
        canvas.height = out;
        const ctx = canvas.getContext('2d');
        ctx.beginPath();
        ctx.arc(out / 2, out / 2, out / 2, 0, Math.PI * 2);
        ctx.closePath();
        ctx.clip();
        ctx.drawImage(imgEl, sx, sy, sSize, sSize, 0, 0, out, out);

        const dataUrl = canvas.toDataURL('image/png');
        this.dispatchEvent(new CustomEvent('upload', {
            detail: { imageUrl: dataUrl },
            bubbles: true,
            composed: true
        }));
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }

    handleChooseDifferent() {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = 'image/png,image/jpeg,image/jpg,image/svg+xml,.png,.jpg,.jpeg,.svg';
        input.onchange = (e) => {
            if (e.target.files && e.target.files[0]) {
                const file = e.target.files[0];

                // Check for HEIC format (not supported)
                const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
                const isHeicFormat = file.type === 'image/heic' || file.type === 'image/heif' || fileExtension === '.heic' || fileExtension === '.heif';

                if (isHeicFormat) {
                    this.showToast('Error', 'HEIC format is not supported. Please use PNG, JPG, JPEG, or SVG format.', 'error');
                    return;
                }

                // Validate file format
                const allowedFormats = ['image/png', 'image/jpeg', 'image/jpg', 'image/svg+xml'];
                const allowedExtensions = ['.png', '.jpg', '.jpeg', '.svg'];
                const isValidFormat = allowedFormats.includes(file.type) || allowedExtensions.includes(fileExtension);

                if (!isValidFormat) {
                    this.showToast('Error', 'Please select a valid image format (PNG, JPG, JPEG, or SVG)', 'error');
                    return;
                }

                // Validate file size (2MB = 2 * 1024 * 1024 bytes)
                const maxSize = 2 * 1024 * 1024;
                if (file.size > maxSize) {
                    this.showToast('Error', 'Image size must be under 2 MB. Please choose a smaller picture.', 'error');
                    return;
                }

                // Read file and dispatch event with data URL
                const reader = new FileReader();
                reader.onload = (event) => {
                    this.dispatchEvent(new CustomEvent('imagechanged', {
                        detail: { imageUrl: event.target.result },
                        bubbles: true,
                        composed: true
                    }));
                };
                reader.readAsDataURL(file);
            }
        };
        input.click();
    }
}