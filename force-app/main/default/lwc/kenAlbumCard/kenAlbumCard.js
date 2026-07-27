import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenAlbumCard extends LightningElement {
    @api album;
    @track showMenu = false;

    constructor() {
        super();
        this.boundHandleClickOutside = this.handleClickOutside.bind(this);
        this.boundHandleProfileImageError = this.handleProfileImageError.bind(this);
    }

    renderedCallback() {
        const profileImage = this.template.querySelector('[data-profile-image="true"]');
        if (profileImage && !profileImage.hasAttribute('data-error-handler-attached')) {
            profileImage.addEventListener('error', this.boundHandleProfileImageError);
            profileImage.setAttribute('data-error-handler-attached', 'true');
        }
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

    get coverImageUrl() {
        return this.album?.coverImageUrl || '';
    }

    get hasCoverImage() {
        return !!this.album?.coverImageUrl;
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
        return this.album?.ownerProfileImageUrl || '/assets/images/default-profile.png';
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
        event.target.src = '/assets/images/default-profile.png';
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
        event.target.src = '/assets/images/default-profile.png';
    }
}