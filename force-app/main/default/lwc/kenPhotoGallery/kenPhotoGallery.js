import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAlbums from '@salesforce/apex/KenGalleryController.getAlbums';
import createAlbum from '@salesforce/apex/KenGalleryController.createAlbum';
import deleteAlbum from '@salesforce/apex/KenGalleryController.deleteAlbum';
import updateAlbumLink from '@salesforce/apex/KenGalleryController.updateAlbumLink';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenPhotoGallery extends NavigationMixin(LightningElement) {
    @track searchTerm = '';
    @track albumSortOption = 'a-z';
    @track canCreateAlbum = false;
    @track showCreateAlbumModal = false;
    @track showSortDropdown = false;
    @track showEditLinkModal = false;
    @track editLinkAlbum = null;

    wiredAlbumsResult;
    rawAlbums = [];

    constructor() {
        super();
        this.boundHandleClickOutside = this.handleClickOutside.bind(this);
    }

    connectedCallback() {
        document.addEventListener('click', this.boundHandleClickOutside);
        getPrimaryColor()
            .then((color) => {
                this.canCreateAlbum = color?.createAlbum !== false;
            })
            .catch(() => {});
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.boundHandleClickOutside);
    }

    @wire(getAlbums)
    wiredAlbums(result) {
        this.wiredAlbumsResult = result;
        this.rawAlbums = result?.data || [];
    }

    get filteredAlbums() {
        let albums = this.rawAlbums.map((a) => ({
            id: a.id,
            name: a.name,
            lastUpdatedDate: a.lastUpdatedDate,
            coverImageUrl: a.coverImageUrl || '',
            ownerName: a.ownerName,
            ownerProfileImageUrl: a.ownerImage,
            photoCount: a.photoCount,
            isOwner: a.isOwner,
            externalLink: a.externalLink
        }));

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            albums = albums.filter((album) => album.name.toLowerCase().includes(term));
        }

        const sorted = [...albums];
        switch (this.albumSortOption) {
            case 'a-z':
                sorted.sort((a, b) => a.name.localeCompare(b.name));
                break;
            case 'z-a':
                sorted.sort((a, b) => b.name.localeCompare(a.name));
                break;
            case 'recent':
                sorted.sort((a, b) => new Date(b.lastUpdatedDate) - new Date(a.lastUpdatedDate));
                break;
            default:
                break;
        }
        return sorted;
    }

    get hasNoAlbums() {
        return this.filteredAlbums.length === 0;
    }

    get sortOptions() {
        const options = [
            { label: 'A - Z', value: 'a-z' },
            { label: 'Z - A', value: 'z-a' },
            { label: 'Recently updated', value: 'recent' }
        ];
        return options.map((opt) => ({ ...opt, isSelected: opt.value === this.albumSortOption }));
    }

    get currentSortLabel() {
        const selected = this.sortOptions.find((opt) => opt.isSelected);
        return selected ? selected.label : 'Sort by';
    }

    handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
    }

    handleSortButtonClick(event) {
        event.stopPropagation();
        this.showSortDropdown = !this.showSortDropdown;
    }

    handleSortOptionClick(event) {
        this.albumSortOption = event.currentTarget.dataset.value;
        this.showSortDropdown = false;
    }

    handleClickOutside(event) {
        if (this.showSortDropdown && !this.template.contains(event.target)) {
            this.showSortDropdown = false;
        }
    }

    handleCreateAlbum() {
        this.showCreateAlbumModal = true;
    }

    handleCloseCreateAlbumModal() {
        this.showCreateAlbumModal = false;
    }

    handleAlbumCreate(event) {
        const albumData = event.detail;
        createAlbum({ req: { name: albumData.name, externalLink: albumData.externalLink } })
            .then(() => refreshApex(this.wiredAlbumsResult))
            .then(() => {
                this.showCreateAlbumModal = false;
            })
            .catch((error) => {
                const msg = error?.body?.message || 'Could not create album. Please try again.';
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            });
    }

    handleAlbumMenu(event) {
        const albumId = event.detail.albumId;
        const action = event.detail.action;

        if (action === 'delete') {
            deleteAlbum({ albumId })
                .then(() => refreshApex(this.wiredAlbumsResult))
                .catch((error) => {
                    const msg = error?.body?.message || 'Could not delete album. Please try again.';
                    this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
                });
        } else if (action === 'edit') {
            this.editLinkAlbum = this.filteredAlbums.find((album) => album.id === albumId) || null;
            this.showEditLinkModal = true;
        } else if (action === 'share') {
            console.log(`Share album ${albumId}`);
        }
    }

    handleCloseEditLinkModal() {
        this.showEditLinkModal = false;
        this.editLinkAlbum = null;
    }

    handleSaveAlbumLink(event) {
        const { albumId, externalLink, name } = event.detail;
        updateAlbumLink({ albumId, externalLink, name })
            .then(() => refreshApex(this.wiredAlbumsResult))
            .then(() => {
                this.showEditLinkModal = false;
                this.editLinkAlbum = null;
            })
            .catch((error) => {
                const msg = error?.body?.message || 'Could not update album link. Please try again.';
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            });
    }

    handleAlbumClick(event) {
        const albumId = event.detail.albumId;
        if (!albumId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'album_detail__c' },
            state: { recordId: albumId }
        });
    }
}