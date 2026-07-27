import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenResourceGallery extends LightningElement {
    @track currentTab = 'files';
    @track searchTerm = '';
    @track sortOption = 'recent';
    @track files = [
        {
            id: '1',
            title: 'Leadership Lessons Learned...',
            uploadedDate: '2025-05-20',
            fileType: 'PDF',
            uploaderName: 'Ranav J',
            uploaderImageUrl: '/assets/images/profile1.jpg'
        },
        {
            id: '2',
            title: 'Work-Life balance in the real world',
            uploadedDate: '2025-05-20',
            fileType: 'XLS',
            uploaderName: 'Akash Sharama',
            uploaderImageUrl: '/assets/images/profile2.jpg'
        },
        {
            id: '3',
            title: 'Lessons beyond the classroom',
            uploadedDate: '2025-05-30',
            fileType: 'DOC',
            uploaderName: 'Libresh A',
            uploaderImageUrl: '/assets/images/profile3.jpg'
        },
        {
            id: '4',
            title: 'Future-Proof Skills for the Moder...',
            uploadedDate: '2025-06-10',
            fileType: 'JPG',
            uploaderName: 'Sanjay Kumar',
            uploaderImageUrl: '/assets/images/profile4.jpg'
        },
        {
            id: '5',
            title: 'Stories of alumni journeys after gr...',
            uploadedDate: '2025-07-15',
            fileType: 'MP3',
            uploaderName: 'Praveen Kumar',
            uploaderImageUrl: '/assets/images/default-profile.png'
        },
        {
            id: '6',
            title: 'Alumni showcase their typical wo...',
            uploadedDate: '2025-08-10',
            fileType: 'MP4',
            uploaderName: 'Sam Mattew',
            uploaderImageUrl: '/assets/images/default-profile.png'
        }
    ];
    @track filteredFiles = [];
    @track folders = [
        {
            id: '1',
            name: 'Newsletters',
            lastUpdatedDate: '30 May, 2025',
            ownerName: 'Admin',
            ownerProfileImageUrl: '/assets/images/default-profile.png',
            collaboratorsCount: 0
        },
        {
            id: '2',
            name: 'Sustainability in Everyday Work Life',
            lastUpdatedDate: '20 May, 2025',
            ownerName: 'Ranav J',
            ownerProfileImageUrl: '/assets/images/profile1.jpg',
            collaboratorsCount: 3
        },
        {
            id: '3',
            name: 'Staying Relevant in a Changing Industry',
            lastUpdatedDate: '30 May, 2025',
            ownerName: 'Sanjay Kumar',
            ownerProfileImageUrl: '/assets/images/profile2.jpg',
            collaboratorsCount: 3
        },
        {
            id: '4',
            name: 'The power of UX testing',
            lastUpdatedDate: '30 May, 2025',
            ownerName: 'You',
            ownerProfileImageUrl: '/assets/images/default-profile.png',
            collaboratorsCount: 3
        }
    ];
    @track filteredFolders = [];
    @track folderSortOption = 'a-z';
    @track showSortDropdown = false;
    @track showFolderDetail = false;
    @track selectedFolder = null;
    @track showFiltersPopup = false;
    @track selectedFileFormat = '';
    @track selectedDate = '';
    @track postedBy = 'others';

    constructor() {
        super();
        this.boundHandleClickOutside = this.handleClickOutside.bind(this);
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    connectedCallback() {
        this.filteredFiles = [...this.files];
        this.filteredFolders = [...this.folders];
        document.addEventListener('click', this.boundHandleClickOutside);
        this.applyFilters();
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.boundHandleClickOutside);
    }

    get isFilesTab() {
        return this.currentTab === 'files';
    }

    get isFoldersTab() {
        return this.currentTab === 'folders';
    }

    get filesTabClass() {
        return this.isFilesTab ? 'active' : '';
    }

    get foldersTabClass() {
        return this.isFoldersTab ? 'active' : '';
    }

    get hasNoFiles() {
        return this.filteredFiles.length === 0;
    }

    get hasNoFolders() {
        return this.filteredFolders.length === 0;
    }

    get sortOptions() {
        if (this.isFilesTab) {
            return [
                { label: 'Recent', value: 'recent', isSelected: this.sortOption === 'recent' },
                { label: 'A - Z', value: 'a-z', isSelected: this.sortOption === 'a-z' },
                { label: 'Z - A', value: 'z-a', isSelected: this.sortOption === 'z-a' }
            ];
        } else {
            return [
                { label: 'A - Z', value: 'a-z', isSelected: this.folderSortOption === 'a-z' },
                { label: 'Z - A', value: 'z-a', isSelected: this.folderSortOption === 'z-a' },
                { label: 'Recently updated', value: 'recent', isSelected: this.folderSortOption === 'recent' }
            ];
        }
    }

    get currentSortLabel() {
        const option = this.sortOptions.find(opt => opt.isSelected);
        return option ? option.label : 'Recent';
    }

    get fileFormatOptions() {
        return [
            { label: 'File format', value: '' },
            { label: 'PDF', value: 'PDF' },
            { label: 'XLS', value: 'XLS' },
            { label: 'DOC', value: 'DOC' },
            { label: 'JPG', value: 'JPG' },
            { label: 'MP3', value: 'MP3' },
            { label: 'MP4', value: 'MP4' }
        ];
    }

    get isOthersSelected() {
        return this.postedBy === 'others';
    }

    get isMyselfSelected() {
        return this.postedBy === 'myself';
    }

    handleTabChange(event) {
        const tab = event.currentTarget.dataset.tab;
        this.currentTab = tab;
        this.showSortDropdown = false;
        if (tab === 'files') {
            this.filterFiles();
        } else {
            this.filterFolders();
        }
    }

    handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
        if (this.currentTab === 'files') {
            this.filterFiles();
        } else {
            this.filterFolders();
        }
    }

    filterFiles() {
        this.applyFilters();
    }

    filterFolders() {
        if (!this.searchTerm) {
            this.filteredFolders = [...this.folders];
        } else {
            this.filteredFolders = this.folders.filter(folder =>
                folder.name.toLowerCase().includes(this.searchTerm) ||
                folder.ownerName.toLowerCase().includes(this.searchTerm)
            );
        }
        this.sortFolders();
    }

    sortFiles() {
        const sorted = [...this.filteredFiles];
        switch (this.sortOption) {
            case 'a-z':
                sorted.sort((a, b) => a.title.localeCompare(b.title));
                break;
            case 'z-a':
                sorted.sort((a, b) => b.title.localeCompare(a.title));
                break;
            case 'recent':
                sorted.sort((a, b) => {
                    const dateA = new Date(a.uploadedDate);
                    const dateB = new Date(b.uploadedDate);
                    return dateB - dateA;
                });
                break;
            default:
                break;
        }
        this.filteredFiles = sorted;
    }

    sortFolders() {
        const sorted = [...this.filteredFolders];
        switch (this.folderSortOption) {
            case 'a-z':
                sorted.sort((a, b) => a.name.localeCompare(b.name));
                break;
            case 'z-a':
                sorted.sort((a, b) => b.name.localeCompare(a.name));
                break;
            case 'recent':
                sorted.sort((a, b) => {
                    const dateA = new Date(a.lastUpdatedDate);
                    const dateB = new Date(b.lastUpdatedDate);
                    return dateB - dateA;
                });
                break;
            default:
                break;
        }
        this.filteredFolders = sorted;
    }

    handleSortButtonClick(event) {
        event.stopPropagation();
        this.showSortDropdown = !this.showSortDropdown;
    }

    handleSortOptionClick(event) {
        const value = event.currentTarget.dataset.value;
        if (this.isFilesTab) {
            this.sortOption = value;
            this.sortFiles();
        } else {
            this.folderSortOption = value;
            this.sortFolders();
        }
        this.showSortDropdown = false;
    }

    handleClickOutside(event) {
        if (this.showSortDropdown && !this.template.contains(event.target)) {
            this.showSortDropdown = false;
        }
    }

    handleFileClick(event) {
        const fileId = event.detail.fileId;
        console.log('File clicked:', fileId);
    }

    handleFolderClick(event) {
        const folderId = event.detail.folderId;
        this.selectedFolder = this.folders.find(folder => folder.id === folderId);
        if (this.selectedFolder) {
            this.showFolderDetail = true;
        }
    }

    handleBackFromFolder() {
        this.showFolderDetail = false;
        this.selectedFolder = null;
    }

    handleFolderFilesAdded(event) {
        const folderId = event.detail.folderId;
        const filesCount = event.detail.filesCount;
        console.log('Files added to folder:', folderId, filesCount);
    }

    handleFolderFileDeleted(event) {
        const folderId = event.detail.folderId;
        const fileId = event.detail.fileId;
        console.log('File deleted from folder:', folderId, fileId);
    }

    handleFiltersClick() {
        this.showFiltersPopup = true;
    }

    handleFiltersOverlayClick(event) {
        if (event.target.classList.contains('filters-overlay')) {
            this.showFiltersPopup = false;
        }
    }

    handleFiltersPopupClick(event) {
        event.stopPropagation();
    }

    handleFileFormatChange(event) {
        this.selectedFileFormat = event.detail.value;
        this._applyFiltersLive();
    }

    handleDateChange(event) {
        this.selectedDate = event.target.value;
        this._applyFiltersLive();
    }

    handlePostedByChange(event) {
        this.postedBy = event.target.value;
        this._applyFiltersLive();
    }

    handleResetFilters() {
        this.selectedFileFormat = '';
        this.selectedDate = '';
        this.postedBy = 'others';
        this.applyFilters();
    }

    handleApplyFilters() {
        this.applyFilters();
        this.showFiltersPopup = false;
    }

    _applyFiltersLive() {
        this.applyFilters();
    }

    applyFilters() {
        let filtered = [...this.files];

        if (this.searchTerm) {
            filtered = filtered.filter(file =>
                file.title.toLowerCase().includes(this.searchTerm) ||
                file.uploaderName.toLowerCase().includes(this.searchTerm)
            );
        }

        // Filter by file format
        if (this.selectedFileFormat) {
            filtered = filtered.filter(file => file.fileType === this.selectedFileFormat);
        }

        // Filter by date
        if (this.selectedDate) {
            filtered = filtered.filter(file => {
                const fileDate = new Date(file.uploadedDate);
                const selectedDateObj = new Date(this.selectedDate);
                return fileDate.toDateString() === selectedDateObj.toDateString();
            });
        }

        // Filter by posted by
        if (this.postedBy === 'myself') {
            filtered = filtered.filter(file => file.uploaderName === 'You' || file.uploaderName === 'Current User');
        } else if (this.postedBy === 'others') {
            filtered = filtered.filter(file => file.uploaderName !== 'You' && file.uploaderName !== 'Current User');
        }

        this.filteredFiles = filtered;
        this.sortFiles();
    }
}