import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getAlbumForRecord from '@salesforce/apex/KenGalleryController.getAlbumForRecord';
import getAlbumPhotos from '@salesforce/apex/KenGalleryController.getAlbumPhotos';
import uploadPhotos from '@salesforce/apex/KenGalleryController.uploadPhotos';
import deletePhoto from '@salesforce/apex/KenGalleryController.deletePhoto';

export default class KenAlbumDetailView extends NavigationMixin(LightningElement) {
    @track album;
    @track showUploadPage = false;
    @track isSavingPhotos = false;
    @track showPhotoDetail = false;
    @track selectedPhoto = null;
    wiredPhotosResult;
    rawPhotos = [];
    pendingPhotoId = null;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });

        if (!this.album) {
            this.resolveAlbumFromUrl();
        }
    }

    resolveAlbumFromUrl() {
        const params = new URLSearchParams(window.location.search);
        const recordId = params.get('recordId');
        if (!recordId) {
            return;
        }
        getAlbumForRecord({ recordId })
            .then((result) => {
                this.pendingPhotoId = result?.photoId || null;
                this.album = result?.album || null;
            })
            .catch((error) => {
                const msg = error?.body?.message || 'Could not load this album.';
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            });
    }

    @wire(getAlbumPhotos, { albumId: '$album.id' })
    wiredPhotos(result) {
        this.wiredPhotosResult = result;
        this.rawPhotos = result?.data || [];
        this.openPendingPhoto();
    }

    openPendingPhoto() {
        if (!this.pendingPhotoId || this.rawPhotos.length === 0) {
            return;
        }
        const photo = this.albumPhotos.find((p) => p.id === this.pendingPhotoId) || null;
        this.pendingPhotoId = null;
        if (photo && photo.isImage) {
            this.selectedPhoto = photo;
            this.showPhotoDetail = true;
        }
    }

    get albumPhotos() {
        return this.rawPhotos.map((p) => ({
            id: p.id,
            imageUrl: p.imageUrl,
            profileImageUrl: p.uploaderImage,
            personName: p.uploaderName,
            isImage: p.isImage,
            fileName: p.fileName,
            isOwner: this.isOwner
        }));
    }

    get albumName() {
        return this.album?.name || '';
    }

    get isOwner() {
        return !!this.album?.isOwner;
    }

    get addFilesDisabled() {
        return !this.isOwner;
    }

    get addFilesDisabledTitle() {
        return this.isOwner
            ? ''
            : 'Only the folder owner has access to upload. You don’t have access.';
    }

    get isEmpty() {
        return this.albumPhotos.length === 0;
    }

    get photosCount() {
        return this.albumPhotos.length;
    }

    get photosLabel() {
        return this.albumPhotos.length === 1 ? 'file' : 'files';
    }

    get albumDetailContainerClass() {
        return this.showUploadPage 
            ? 'album-detail-container no-bg' 
            : 'album-detail-container with-bg';
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'gallery__c' }
        });
    }

    handleAddPhotos() {
        this.showUploadPage = true;
    }

    handleCloseUploadModal() {
        this.showUploadPage = false;
    }

    handleBackFromUploadPage() {
        this.showUploadPage = false;
    }

    handlePhotoPost(event) {
        const photoData = event.detail;
        if (!photoData.images || photoData.images.length === 0) {
            this.showUploadPage = false;
            return;
        }

        const photos = photoData.images.map((img) => ({
            title: img.name,
            base64: img.preview
        }));

        this.isSavingPhotos = true;
        uploadPhotos({ albumId: this.album.id, photos })
            .then(() => refreshApex(this.wiredPhotosResult))
            .then(() => {
                this.isSavingPhotos = false;
                this.showUploadPage = false;
            })
            .catch((error) => {
                this.isSavingPhotos = false;
                const msg = error?.body?.message || 'Could not upload photos. Please try again.';
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            });
    }

    handlePhotoClick(event) {
        const photoId = event.detail.photoId;
        const photo = this.albumPhotos.find((p) => p.id === photoId) || null;
        if (!photo) {
            return;
        }
        if (photo.isImage) {
            this.selectedPhoto = photo;
            this.showPhotoDetail = true;
        } else {
            window.open(photo.imageUrl, '_blank', 'noopener,noreferrer');
        }
    }

    handleClosePhotoDetail() {
        this.showPhotoDetail = false;
        this.selectedPhoto = null;
    }

    handlePhotoChange(event) {
        this.selectedPhoto = event.detail.photo;
    }

    handlePhotoMenu(event) {
        const photoId = event.detail.photoId;
        const action = event.detail.action;

        if (action === 'delete') {
            deletePhoto({ photoId })
                .then(() => refreshApex(this.wiredPhotosResult))
                .catch((error) => {
                    const msg = error?.body?.message || 'Could not delete photo. Please try again.';
                    this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
                });
        } else if (action === 'edit') {
            console.log(`Edit photo ${photoId}`);
        } else if (action === 'share') {
            console.log(`Share photo ${photoId}`);
        }
    }
}