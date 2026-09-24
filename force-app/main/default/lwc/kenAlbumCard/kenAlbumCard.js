import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import AlbumCoverPlaceholder from '@salesforce/resourceUrl/AlbumCoverPlaceholder';
import FilePreviewPlaceholder from '@salesforce/resourceUrl/FilePreviewPlaceholder';
import ExternalFolderPlaceholder from '@salesforce/resourceUrl/ExternalFolderPlaceholder';
import defaultProfileImage from '@salesforce/resourceUrl/defaultProfileImage';
export default class KenAlbumCard extends LightningElement {
    @api album;
    @track showMenu = false;

    constructor() {
        super();
        this.boundHandleClickOutside = this.handleClickOutside.bind(this);
        this.boundHandleProfileImageError = this.handleProfileImageError.bind(this);
        this.boundHandleCoverImageError = this.handleCoverImageError.bind(this);
    }

    renderedCallback() {
        const profileImage = this.template.querySelector('[data-profile-image="true"]');
        if (profileImage && !profileImage.hasAttribute('data-error-handler-attached')) {
            profileImage.addEventListener('error', this.boundHandleProfileImageError);
            profileImage.setAttribute('data-error-handler-attached', 'true');
        }
        const coverImage = this.template.querySelector('[data-cover-image="true"]');
        if (coverImage && !coverImage.hasAttribute('data-error-handler-attached')) {
            coverImage.addEventListener('error', this.boundHandleCoverImageError);
            coverImage.setAttribute('data-error-handler-attached', 'true');
        }
    }

    // The album's most recent upload is its cover, except for a drive-linked
    // album: its real contents live in the external folder, so any file that
    // happens to be attached in Salesforce would misrepresent what the card
    // opens. Those always get the external-folder art.
    //
    // Otherwise three states, and the distinction matters: an album holding a
    // PDF is NOT empty, so it must not get the "No files yet" art - it gets the
    // same document art the file cards inside the album use.
    get coverImageUrl() {
        if (this.isLinked) {
            return ExternalFolderPlaceholder;
        }
        if (this.album?.coverIsImage && this.album?.coverImageUrl) {
            return this.album.coverImageUrl;
        }
        return this.hasPhotos ? FilePreviewPlaceholder : AlbumCoverPlaceholder;
    }

    // Name the file the cover stands in for, so a document cover says what it is
    // rather than showing anonymous art.
    get coverFileName() {
        return this.album?.coverFileName || '';
    }

    get showCoverFileName() {
        return (
            !this.isLinked &&
            this.hasPhotos &&
            !this.album?.coverIsImage &&
            !!this.coverFileName
        );
    }

    handleCoverImageError(event) {
        if (this.isLinked) {
            event.target.src = ExternalFolderPlaceholder;
            return;
        }
        event.target.src = this.hasPhotos
            ? FilePreviewPlaceholder
            : AlbumCoverPlaceholder;
    }

    connectedCallback() {
        document.addEventListener('click', this.boundHandleClickOutside);
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.boundHandleClickOutside);
        const profileImage = this.template.querySelector('[data-profile-image="true"]');
        if (profileImage) {
            profileImage.removeEventListener('error', this.boundHandleProfileImageError);
        }
    }

    handleClickOutside(event) {
        if (this.showMenu && !this.template.contains(event.target)) {
            this.showMenu = false;
        }
    }

    get albumName() {
        return this.album?.name || '';
    }

    get isOwner() {
        return !!this.album?.isOwner;
    }

    get lastUpdatedDate() {
        const raw = this.album?.lastUpdatedDate;
        if (!raw) {
            return '';
        }
        const date = new Date(raw);
        if (Number.isNaN(date.getTime())) {
            return '';
        }
        return date.toLocaleDateString('en-US', {
            day: 'numeric',
            month: 'short',
            year: 'numeric'
        });
    }

    get ownerName() {
        return this.album?.ownerName || '';
    }

    get ownerProfileImageUrl() {
        return this.album?.ownerProfileImageUrl || defaultProfileImage;
    }

    get photoCount() {
        return this.album?.photoCount || 0;
    }

    get hasPhotos() {
        return this.photoCount > 0;
    }

    get photoCountLabel() {
        return this.photoCount === 1 ? '1 file' : `${this.photoCount} files`;
    }

    get externalLink() {
        return this.album?.externalLink || '';
    }

    get isLinked() {
        return !!this.externalLink;
    }

    handleAvatarError(event) {
        event.target.src = defaultProfileImage;
    }

    handleMenuClick(event) {
        event.stopPropagation();
        this.showMenu = !this.showMenu;
    }

    handleMenuAction(event) {
        const action = event.currentTarget.dataset.action;
        this.showMenu = false;
        this.dispatchEvent(
            new CustomEvent('menuselect', {
                detail: {
                    albumId: this.album.id,
                    action: action
                }
            })
        );
    }

    handleAlbumClick() {
        if (this.isLinked) {
            window.open(this.externalLink, '_blank', 'noopener,noreferrer');
            return;
        }
        this.dispatchEvent(
            new CustomEvent('albumclick', {
                detail: {
                    albumId: this.album.id
                }
            })
        );
    }

    handleProfileImageError(event) {
        event.target.src = defaultProfileImage;
    }
}