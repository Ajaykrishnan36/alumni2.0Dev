import { LightningElement, track } from 'lwc';
import getAlbums from '@salesforce/apex/KenGalleryV2Controller.getAlbums';
import getAlbumPhotos from '@salesforce/apex/KenGalleryV2Controller.getAlbumPhotos';
import createAlbumApex from '@salesforce/apex/KenGalleryV2Controller.createAlbum';
import addPhotoApex from '@salesforce/apex/KenGalleryV2Controller.addPhoto';

const ALBUMS_INIT = [
    { id:1, name:'Batch 2018 Reunion',     count:148, cover:'#3061FF', year:'2024' },
    { id:2, name:'Annual Fundraiser Gala', count:96,  cover:'#19A974', year:'2024' },
    { id:3, name:'Sports Day',             count:124, cover:'#F59E0B', year:'2024' },
    { id:4, name:'Convocation 2018',       count:312, cover:'#B033C8', year:'2018' },
    { id:5, name:'Cultural Night',         count:88,  cover:'#E8B4D6', year:'2023' },
    { id:6, name:'Bangalore Meetup',       count:42,  cover:'#67A1C8', year:'2024' }
];

const PHOTOS_BY_ALBUM = {
    1: [
        { id:101, color:'#3061FF', caption:'Welcome desk',         uploader:'Sandra R' },
        { id:102, color:'#5179FF', caption:'Class photo',          uploader:'Rahul M'  },
        { id:103, color:'#7B96FF', caption:'Cake cutting',         uploader:'Anya K'   },
        { id:104, color:'#A8B9FF', caption:'Group selfie',         uploader:'Sandra R' },
        { id:105, color:'#3061FF', caption:'Dance floor',          uploader:'Liam T'   },
        { id:106, color:'#5179FF', caption:'Throwback corner',     uploader:'Karthik R'}
    ],
    2: [
        { id:201, color:'#19A974', caption:'Stage setup',          uploader:'Tanya J'  },
        { id:202, color:'#3FB58A', caption:'Award handout',        uploader:'Rahul M'  },
        { id:203, color:'#5DC09F', caption:'Donor wall',           uploader:'Anya K'   },
        { id:204, color:'#19A974', caption:'Closing speech',       uploader:'Sandra R' }
    ],
    3: [
        { id:301, color:'#F59E0B', caption:'100m sprint finals',   uploader:'Liam T'   },
        { id:302, color:'#F7AE32', caption:'Tug of war',           uploader:'Karthik R'},
        { id:303, color:'#F9C062', caption:'Football final',       uploader:'Rahul M'  }
    ],
    4: [
        { id:401, color:'#B033C8', caption:'Cap toss',             uploader:'Sandra R' },
        { id:402, color:'#BD55D2', caption:'Convocation hall',     uploader:'Anya K'   }
    ],
    5: [
        { id:501, color:'#E8B4D6', caption:'Band performance',     uploader:'Tanya J'  },
        { id:502, color:'#EFC4DF', caption:'Lights & stage',       uploader:'Liam T'   }
    ],
    6: [
        { id:601, color:'#67A1C8', caption:'Coffee mixer',         uploader:'Rahul M'  },
        { id:602, color:'#82B3D2', caption:'Networking corner',    uploader:'Anya K'   }
    ]
};

export default class KenPhotoGalleryV2 extends LightningElement {
    @track activeYear = 'All';
    @track activeView = 'albums'; // albums | photos
    @track selectedAlbumId = 0;
    @track selectedPhotoId = 0;
    @track albumsState = ALBUMS_INIT.map(a => ({ ...a }));
    @track photosState = [];
    @track isLoading = false;
    _photosByAlbum = { ...PHOTOS_BY_ALBUM };
    _usingMock = true;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const view = params.get('view');
            const id = params.get('id');
            const VALID_VIEWS = ['albums', 'photos'];
            if (view && VALID_VIEWS.indexOf(view) > -1) this.activeView = view;
            if (id) this.selectedAlbumId = /^\d+$/.test(id) ? Number(id) : id;
        } catch (e) { /* ignore */ }
        this.loadAlbums();
        if (this.activeView === 'photos' && this.selectedAlbumId) {
            this.loadPhotos(this.selectedAlbumId);
        }
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeView && this.activeView !== 'albums') params.set('view', this.activeView); else params.delete('view');
            if (this.selectedAlbumId) params.set('id', String(this.selectedAlbumId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadAlbums() {
        this.isLoading = true;
        getAlbums()
            .then(rows => {
                if (Array.isArray(rows) && rows.length) {
                    this.albumsState = rows.map(r => ({
                        id: r.id,
                        name: r.name || '',
                        count: r.count || 0,
                        cover: r.cover || '#3061FF',
                        year: r.year || ''
                    }));
                    this._usingMock = false;
                }
                this.isLoading = false;
            })
            .catch(err => {
                this.isLoading = false;
                this._usingMock = true;
                // eslint-disable-next-line no-console
                console.error('KenGalleryV2Controller.getAlbums error, using mock fallback', err);
            });
    }

    loadPhotos(albumId) {
        if (this._usingMock) {
            this.photosState = this._photosByAlbum[albumId] || [];
            return;
        }
        this.isLoading = true;
        getAlbumPhotos({ albumId })
            .then(rows => {
                this.photosState = (rows || []).map(p => ({
                    id: p.id,
                    color: p.color || '#3061FF',
                    caption: p.caption || '',
                    uploader: p.uploader || ''
                }));
                this.isLoading = false;
            })
            .catch(err => {
                this.isLoading = false;
                this.photosState = this._photosByAlbum[albumId] || [];
                // eslint-disable-next-line no-console
                console.error('KenGalleryV2Controller.getAlbumPhotos error, using mock fallback', err);
            });
    }

    @track showCreate = false;
    @track showUpload = false;
    @track showLightbox = false;

    @track createForm = { name:'', cover:'#3061FF', privacy:'Public' };
    @track uploadForm = { caption:'' };

    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;

    get isAlbums() { return this.activeView === 'albums'; }
    get isPhotos() { return this.activeView === 'photos'; }

    get years() { return ['All','2024','2023','2022','2021','2020','2019','2018']; }
    get yearChips() {
        return this.years.map(y => ({ id:y, label:y, chipClass: y === this.activeYear ? 'chip chip--active' : 'chip' }));
    }

    get albums() {
        const list = this.activeYear === 'All' ? this.albumsState : this.albumsState.filter(a => a.year === this.activeYear);
        return list.map(a => ({ ...a, coverStyle: `background:linear-gradient(135deg, ${a.cover}, ${a.cover}AA);` }));
    }
    get hasAlbums() { return this.albums.length > 0; }
    get hasPhotos() { return (this.photosState || []).length > 0; }

    get selectedAlbum() {
        return this.albumsState.find(a => String(a.id) === String(this.selectedAlbumId)) || { name:'', count:0 };
    }
    get selectedAlbumName() { return this.selectedAlbum.name; }
    get selectedAlbumMeta() { return `${this.selectedAlbum.count} photos · ${this.selectedAlbum.year || ''}`; }

    get photos() {
        const list = this.photosState || [];
        return list.map(p => ({ ...p, photoStyle: `background:linear-gradient(135deg, ${p.color}, ${p.color}99);` }));
    }

    get selectedPhoto() {
        const list = this.photosState || [];
        return list.find(p => String(p.id) === String(this.selectedPhotoId)) || { caption:'', uploader:'', color:'#3061FF' };
    }
    get selectedPhotoStyle() { return `background:linear-gradient(135deg, ${this.selectedPhoto.color}, ${this.selectedPhoto.color}99);`; }
    get selectedPhotoCaption() { return this.selectedPhoto.caption; }
    get selectedPhotoUploader() { return `Uploaded by ${this.selectedPhoto.uploader}`; }

    /* Filtering */
    handleYear(event) { this.activeYear = event.currentTarget.dataset.id; }

    /* Album navigation */
    handleAlbumOpen(event) {
        const raw = event.currentTarget.dataset.id;
        this.selectedAlbumId = this._usingMock ? Number(raw) : raw;
        this.activeView = 'photos';
        this.syncUrl();
        this.loadPhotos(this.selectedAlbumId);
    }
    handleBackToAlbums() {
        this.activeView = 'albums';
        this.selectedAlbumId = 0;
        this.photosState = [];
        this.syncUrl();
    }

    /* Lightbox */
    handlePhotoOpen(event) {
        const raw = event.currentTarget.dataset.id;
        this.selectedPhotoId = this._usingMock ? Number(raw) : raw;
        this.showLightbox = true;
    }
    handleCloseLightbox() { this.showLightbox = false; }

    /* Create album modal */
    handleOpenCreate() {
        this.createForm = { name:'', cover:'#3061FF', privacy:'Public' };
        this.showCreate = true;
    }
    handleCloseCreate() { this.showCreate = false; }
    handleCreateField(event) {
        const f = event.target.dataset.field;
        if (f) this.createForm = { ...this.createForm, [f]: event.target.value };
    }
    handleCreateSubmit() {
        const name = (this.createForm.name || '').trim();
        if (!name) { this._showToast('Please enter an album name'); return; }
        if (this._usingMock) {
            const next = {
                id: Date.now(),
                name,
                count: 0,
                cover: this.createForm.cover,
                year: String(new Date().getFullYear())
            };
            this.albumsState = [next, ...this.albumsState];
            this.showCreate = false;
            this._showToast('Album created');
            return;
        }
        const payload = {
            name,
            year: String(new Date().getFullYear()),
            cover: this.createForm.cover,
            privacy: this.createForm.privacy || 'Public'
        };
        createAlbumApex({ payload })
            .then(() => {
                this.showCreate = false;
                this._showToast('Album created');
                this.loadAlbums();
            })
            .catch(err => {
                this.showCreate = false;
                this._showToast('Create failed');
                // eslint-disable-next-line no-console
                console.error('createAlbum error', err);
            });
    }

    /* Upload photos modal */
    handleOpenUpload() {
        this.uploadForm = { caption:'' };
        this.showUpload = true;
    }
    handleCloseUpload() { this.showUpload = false; }
    handleUploadField(event) {
        const f = event.target.dataset.field;
        if (f) this.uploadForm = { ...this.uploadForm, [f]: event.target.value };
    }
    handleUploadSubmit() {
        if (this._usingMock || !this.selectedAlbumId) {
            this.showUpload = false;
            this._showToast('Photos uploaded');
            return;
        }
        const payload = {
            albumId: this.selectedAlbumId,
            name: this.uploadForm.caption || 'Photo',
            caption: this.uploadForm.caption || '',
            color: '#3061FF'
        };
        addPhotoApex({ payload })
            .then(() => {
                this.showUpload = false;
                this._showToast('Photos uploaded');
                this.loadPhotos(this.selectedAlbumId);
            })
            .catch(err => {
                this.showUpload = false;
                this._showToast('Upload failed');
                // eslint-disable-next-line no-console
                console.error('addPhoto error', err);
            });
    }

    handleBackdropClick(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.showCreate = false;
            this.showUpload = false;
            this.showLightbox = false;
        }
    }
    handleStopProp(event) { event.stopPropagation(); }

    _showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }

    disconnectedCallback() {
        if (this._toastTimer) clearTimeout(this._toastTimer);
    }
}