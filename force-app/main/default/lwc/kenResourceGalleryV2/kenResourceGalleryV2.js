import { LightningElement, track } from 'lwc';
import getCategories from '@salesforce/apex/KenResourceV2Controller.getCategories';
import getResources from '@salesforce/apex/KenResourceV2Controller.getResources';
import createFolderApex from '@salesforce/apex/KenResourceV2Controller.createFolder';
import createResourceApex from '@salesforce/apex/KenResourceV2Controller.createResource';

const FOLDERS_INIT = [
    { id:1, name:'Newsletters',       owner:'Comms Team',      updated:'01 Oct 2025', count:24, color:'#3061FF', icon:'📰' },
    { id:2, name:'Research Journals', owner:'Academics',       updated:'14 Sep 2025', count:18, color:'#19A974', icon:'📚' },
    { id:3, name:'Brochures',         owner:'Admissions',      updated:'01 Aug 2025', count:9,  color:'#B033C8', icon:'📄' },
    { id:4, name:'Recordings',        owner:'Events Team',     updated:'21 Sep 2025', count:12, color:'#F59E0B', icon:'🎬' },
    { id:5, name:'Career Toolkits',   owner:'Placement Cell',  updated:'01 Jul 2025', count:32, color:'#67A1C8', icon:'🧰' },
    { id:6, name:'Founder Playbooks', owner:'Entrepreneurship',updated:'15 Aug 2025', count:7,  color:'#E8B4D6', icon:'🚀' },
    { id:7, name:'Templates',         owner:'Comms Team',      updated:'04 Oct 2025', count:15, color:'#DC5959', icon:'📝' },
    { id:8, name:'Policies',          owner:'Admin Office',    updated:'18 Aug 2025', count:6,  color:'#1A1A1A', icon:'📋' }
];

const FILES_BY_FOLDER = {
    1: [
        { id:101, name:'October 2025 Newsletter.pdf', size:'2.4 MB', date:'01 Oct 2025', ext:'PDF' },
        { id:102, name:'September 2025 Newsletter.pdf', size:'2.1 MB', date:'01 Sep 2025', ext:'PDF' },
        { id:103, name:'August 2025 Newsletter.pdf', size:'2.6 MB', date:'01 Aug 2025', ext:'PDF' }
    ],
    2: [
        { id:201, name:'Research Journal Vol 12.pdf', size:'8.1 MB', date:'14 Sep 2025', ext:'PDF' },
        { id:202, name:'Research Journal Vol 11.pdf', size:'7.4 MB', date:'14 Mar 2025', ext:'PDF' }
    ],
    3: [
        { id:301, name:'Placement Brochure 2024-25.pdf', size:'5.7 MB', date:'01 Aug 2025', ext:'PDF' }
    ],
    4: [
        { id:401, name:'Bangalore Meet — Recap.mp4', size:'124 MB', date:'21 Sep 2025', ext:'MP4' },
        { id:402, name:'Founders Panel.mp4',         size:'212 MB', date:'15 Jul 2025', ext:'MP4' }
    ],
    5: [
        { id:501, name:'Interview Prep Guide.pdf', size:'1.2 MB', date:'01 Jul 2025', ext:'PDF' },
        { id:502, name:'Resume Templates.zip',     size:'4.6 MB', date:'12 Jul 2025', ext:'ZIP' }
    ],
    6: [
        { id:601, name:'First-Timer Playbook.pdf', size:'3.4 MB', date:'15 Aug 2025', ext:'PDF' }
    ],
    7: [
        { id:701, name:'Event Poster Template.pptx', size:'2.1 MB', date:'04 Oct 2025', ext:'PPTX' }
    ],
    8: [
        { id:801, name:'Code of Conduct.pdf', size:'820 KB', date:'18 Aug 2025', ext:'PDF' }
    ]
};

export default class KenResourceGalleryV2 extends LightningElement {
    @track activeView = 'folders'; // folders | inside-folder
    @track selectedFolderId = 0;
    @track foldersState = FOLDERS_INIT.map(f => ({ ...f }));
    @track filesState = []; // resources for current folder (from Apex)
    @track isLoading = false;
    _filesByFolder = { ...FILES_BY_FOLDER };
    _usingMock = true;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const view = params.get('view');
            const id = params.get('id');
            const VALID_VIEWS = ['folders', 'inside-folder'];
            if (view && VALID_VIEWS.indexOf(view) > -1) this.activeView = view;
            if (id) this.selectedFolderId = /^\d+$/.test(id) ? Number(id) : id;
        } catch (e) { /* ignore */ }
        this.loadFolders();
        if (this.activeView === 'inside-folder' && this.selectedFolderId) {
            this.loadResources(this.selectedFolderId);
        }
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeView && this.activeView !== 'folders') params.set('view', this.activeView); else params.delete('view');
            if (this.selectedFolderId) params.set('id', String(this.selectedFolderId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadFolders() {
        this.isLoading = true;
        getCategories()
            .then(rows => {
                if (Array.isArray(rows) && rows.length) {
                    this.foldersState = rows.map(r => ({
                        id: r.id,
                        name: r.name || '',
                        owner: r.owner || '',
                        updated: r.updated || '',
                        count: r.count || 0,
                        color: r.color || '#3061FF',
                        icon: r.icon || ''
                    }));
                    this._usingMock = false;
                }
                this.isLoading = false;
            })
            .catch(err => {
                this.isLoading = false;
                this._usingMock = true;
                // eslint-disable-next-line no-console
                console.error('KenResourceV2Controller.getCategories error, using mock fallback', err);
            });
    }

    loadResources(folderId) {
        if (this._usingMock) {
            this.filesState = this._filesByFolder[folderId] || [];
            return;
        }
        this.isLoading = true;
        getResources({ folderId })
            .then(rows => {
                this.filesState = (rows || []).map(r => ({
                    id: r.id,
                    name: r.name || '',
                    size: r.size || '',
                    date: r.fileDate || '',
                    ext: r.ext || ''
                }));
                this.isLoading = false;
            })
            .catch(err => {
                this.isLoading = false;
                this.filesState = this._filesByFolder[folderId] || [];
                // eslint-disable-next-line no-console
                console.error('KenResourceV2Controller.getResources error, using mock fallback', err);
            });
    }

    @track showUpload = false;
    @track showNewFolder = false;

    @track uploadForm = { name:'', folder:'', notes:'' };
    @track folderForm = { name:'', owner:'', color:'#3061FF', icon:'📁' };

    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;

    get isFolders() { return this.activeView === 'folders'; }
    get isInsideFolder() { return this.activeView === 'inside-folder'; }

    get folders() {
        return this.foldersState.map(f => ({
            ...f,
            iconStyle: `background:${f.color}1A;color:${f.color};`,
            meta: `${f.count} files · Updated ${f.updated}`
        }));
    }

    get selectedFolder() {
        return this.foldersState.find(f => String(f.id) === String(this.selectedFolderId)) || { name:'', owner:'', count:0 };
    }
    get selectedFolderName() { return this.selectedFolder.name; }
    get selectedFolderMeta() { return `${this.selectedFolder.count} files · Owned by ${this.selectedFolder.owner}`; }

    get files() {
        return this.filesState || [];
    }
    get hasFolders() { return (this.foldersState || []).length > 0; }
    get hasFiles() { return this.files.length > 0; }

    get folderOptions() {
        return this.foldersState.map(f => ({ id:f.id, label:f.name }));
    }

    /* Folder nav */
    handleFolderOpen(event) {
        const raw = event.currentTarget.dataset.id;
        // Salesforce Ids are strings; mock ids are numeric — keep both working.
        this.selectedFolderId = this._usingMock ? Number(raw) : raw;
        this.activeView = 'inside-folder';
        this.syncUrl();
        this.loadResources(this.selectedFolderId);
    }
    handleBackToFolders() {
        this.activeView = 'folders';
        this.selectedFolderId = 0;
        this.filesState = [];
        this.syncUrl();
    }

    /* File actions */
    handleDownload(event) {
        const raw = event.currentTarget.dataset.id;
        const id = this._usingMock ? Number(raw) : raw;
        const file = (this.filesState || []).find(f => String(f.id) === String(id));
        this._showToast(`Downloading ${file ? file.name : 'file'}...`);
    }

    /* Upload */
    handleOpenUpload() {
        this.uploadForm = { name:'', folder: String(this.selectedFolderId || (this.foldersState[0] && this.foldersState[0].id) || ''), notes:'' };
        this.showUpload = true;
    }
    handleCloseUpload() { this.showUpload = false; }
    handleUploadField(event) {
        const f = event.target.dataset.field;
        if (f) this.uploadForm = { ...this.uploadForm, [f]: event.target.value };
    }
    handleUploadSubmit() {
        const name = (this.uploadForm.name || '').trim();
        const folderId = this.uploadForm.folder;
        if (!name) { this._showToast('Please enter a display name'); return; }
        if (this._usingMock || !folderId) {
            this.showUpload = false;
            this._showToast('Resource uploaded');
            return;
        }
        const payload = {
            name,
            folderId,
            notes: this.uploadForm.notes || '',
            ext: (name.split('.').pop() || 'PDF').toUpperCase()
        };
        createResourceApex({ payload })
            .then(() => {
                this.showUpload = false;
                this._showToast('Resource uploaded');
                this.loadResources(this.selectedFolderId);
            })
            .catch(err => {
                this.showUpload = false;
                this._showToast('Upload failed');
                // eslint-disable-next-line no-console
                console.error('createResource error', err);
            });
    }

    /* New folder */
    handleOpenNewFolder() {
        this.folderForm = { name:'', owner:'', color:'#3061FF', icon:'📁' };
        this.showNewFolder = true;
    }
    handleCloseNewFolder() { this.showNewFolder = false; }
    handleFolderField(event) {
        const f = event.target.dataset.field;
        if (f) this.folderForm = { ...this.folderForm, [f]: event.target.value };
    }
    handleFolderSubmit() {
        const name = (this.folderForm.name || '').trim();
        if (!name) { this._showToast('Please enter a folder name'); return; }
        if (this._usingMock) {
            const next = {
                id: Date.now(),
                name,
                owner: this.folderForm.owner || 'You',
                updated: 'Just now',
                count: 0,
                color: this.folderForm.color,
                icon: this.folderForm.icon || '📁'
            };
            this.foldersState = [next, ...this.foldersState];
            this.showNewFolder = false;
            this._showToast('Folder created');
            return;
        }
        const payload = {
            name,
            owner: this.folderForm.owner || 'You',
            color: this.folderForm.color,
            icon: this.folderForm.icon || '📁',
            updated: 'Just now',
            privacy: 'Public'
        };
        createFolderApex({ payload })
            .then(() => {
                this.showNewFolder = false;
                this._showToast('Folder created');
                this.loadFolders();
            })
            .catch(err => {
                this.showNewFolder = false;
                this._showToast('Create failed');
                // eslint-disable-next-line no-console
                console.error('createFolder error', err);
            });
    }

    handleBackdropClick(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.showUpload = false;
            this.showNewFolder = false;
        }
    }
    handleStopProp(event) { event.stopPropagation(); }

    _showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }
}