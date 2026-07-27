import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import AlumniAlt from '@salesforce/resourceUrl/AlumniAlt';
import MENTORSHIP_EMPTY_STATE from '@salesforce/resourceUrl/MentorshipEmptyState';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getNetworkData from '@salesforce/apex/KenNetworkController.getNetworkData';
import getAllAlumniForFilterOptions from '@salesforce/apex/KenNetworkController.getAllAlumniForFilterOptions';
import respondToConnectionRequests from '@salesforce/apex/KenNetworkController.respondToConnectionRequests';
import getReferralLink from '@salesforce/apex/KenReferralService.getReferralLink';

const FILTER_FIELDS = [
    'company',
    'industry',
    'jobFunction',
    'employmentType',
    'gender',
    'programLastAttended',
    'graduationYear',
    'currentCity',
    'institute',
    'program',
    'intake',
    'country'
];
const ONLINE_WINDOW_MS = 5 * 60 * 1000;

export default class KenNetworkPage extends NavigationMixin(LightningElement) {
    @track activeTab = 'all';
    @track searchTerm = '';
    @track allAlumni = [];
    @track connectedAlumni = [];
    // Every eligible alumnus in the org (unscoped by tab or by the current
    // viewer's own connections/self-exclusion) — used only to build filter
    // dropdown options, never rendered as cards.
    @track allAlumniForFilterOptions = [];
    @track filteredAlumni = [];
    @track onlineUsers = [];
    @track connectionRequests = [];
    @track showFiltersPopup = false;
    @track showMapModal = false;
    mapModalHeight = 560;
    @track showMentorsNearMe = false;
    @track currentUserCity = '';
    @track currentUserState = '';
    @track showProfilePage = false;
    @track selectedAlumniId = null;
    @track showUserNotFoundModal = false;
    @track selectedUser = null;
    @track isMobile = false;
    @track showMobileListFullView = false;
    @track sortBy = 'a-z';
    @track isSortOpen = false;
    @track portalUrl = '';
    @track inviteUrl = '';
    @track copySuccess = false;
    @track selectedFilters = {
        company: '',
        industry: '',
        jobFunction: '',
        employmentType: '',
        gender: '',
        programLastAttended: '',
        graduationYear: '',
        currentCity: '',
        institute: '',
        program: '',
        intake: '',
        country: '',
        // Checkbox multi-select — array-valued, unlike every field above, so
        // it's kept out of FILTER_FIELDS and handled by its own methods.
        language: []
    };
    @track filterOptions = {
        company: [],
        industry: [],
        jobFunction: [],
        employmentType: [],
        gender: [],
        programLastAttended: [],
        graduationYear: [],
        currentCity: [],
        institute: [],
        program: [],
        intake: [],
        country: [],
        language: []
    };

    _mobileQuery = null;
    _boundUpdateMobile;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        const profileId = pageRef?.state?.profileId || null;
        this.selectedAlumniId = profileId;
        this.showProfilePage = !!profileId;
    }

    get connectionRequestsCount() {
        return this.connectionRequests.length;
    }

    get emptyStateImageUrl() {
        return MENTORSHIP_EMPTY_STATE;
    }

    get hasAnyFiltersOrSearch() {
        const hasSearch = (this.searchTerm || '').trim().length > 0;
        const hasFilters = FILTER_FIELDS.some((field) => {
            const v = (this.selectedFilters?.[field] || '').trim();
            return !!v;
        });
        const hasLanguageFilter = (this.selectedFilters?.language || []).length > 0;
        return hasSearch || hasFilters || hasLanguageFilter || this.showMentorsNearMe === true;
    }

    get isNoResults() {
        // "No results" means the UI is showing the grid/list but nothing matches
        // (either because API has no data or filters removed everything).
        return (this.filteredAlumni?.length || 0) === 0;
    }

    get emptyStateTitle() {
        return this.hasAnyFiltersOrSearch ? 'No results found' : 'No alumni found';
    }

    get emptyStateDescription() {
        if (this.hasAnyFiltersOrSearch) {
            return 'Try clearing filters or changing your search to see more alumni.';
        }
        return 'There are no alumni to display right now.';
    }

    get alumniSource() {
        return this.activeTab === 'missing' ? this.connectedAlumni : this.allAlumni;
    }

    // Every eligible alumnus in the org — used to build filter dropdown
    // options so a value (e.g. a rare Skill) is always choosable even if the
    // only person who has it happens to be excluded from the current viewer's
    // visible lists (self-exclusion, or already an accepted connection on
    // "All Alumni"). The actual filtered results still stay scoped to
    // alumniSource.
    get allKnownAlumni() {
        return this.allAlumniForFilterOptions || [];
    }

    get companyOptions() {
        return this.filterOptions.company || [];
    }

    get industryOptions() {
        return this.filterOptions.industry || [];
    }

    get jobFunctionOptions() {
        return this.filterOptions.jobFunction || [];
    }

    get employmentTypeOptions() {
        return this.filterOptions.employmentType || [];
    }

    get genderOptions() {
        return this.filterOptions.gender || [];
    }

    get languageOptions() {
        return this.filterOptions.language || [];
    }

    get selectedLanguages() {
        return this.selectedFilters.language || [];
    }

    get programLastAttendedOptions() {
        return this.filterOptions.programLastAttended || [];
    }

    get graduationYearOptions() {
        return this.filterOptions.graduationYear || [];
    }

    get currentCityOptions() {
        return this.filterOptions.currentCity || [];
    }

    get instituteOptions() {
        return this.filterOptions.institute || [];
    }

    get programOptions() {
        return this.filterOptions.program || [];
    }

    get intakeOptions() {
        return this.filterOptions.intake || [];
    }

    get countryOptions() {
        return this.filterOptions.country || [];
    }

    connectedCallback() {
        this.initializeFallbackData();
        this.loadNetworkData();
        this.loadFilterOptionsData();
        this._updateMobile();
        this._mobileQuery = window.matchMedia('(max-width: 767px)');
        this._boundUpdateMobile = this._updateMobile.bind(this);
        this._mobileQuery.addEventListener('change', this._boundUpdateMobile);

        getPrimaryColor()
            .then((color) => {
                document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
                document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
                document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
                this.portalUrl = color?.portalUrl || '';
            })
            .catch(() => {
                // keep existing styles if config fetch fails
            });

        getReferralLink()
            .then((link) => { this.inviteUrl = link || ''; })
            .catch(() => { /* non-fatal — invite widget stays empty */ });
    }

    disconnectedCallback() {
        if (this._mobileQuery && this._boundUpdateMobile) {
            this._mobileQuery.removeEventListener('change', this._boundUpdateMobile);
        }
    }

    _updateMobile() {
        const nowMobile = window.matchMedia('(max-width: 767px)').matches;
        if (!nowMobile && this.showMobileListFullView) {
            this.showMobileListFullView = false;
        }
        this.isMobile = nowMobile;
    }

    initializeFallbackData() {
        this.allAlumni = [];
        this.connectedAlumni = [];
        this.onlineUsers = [];
        this.connectionRequests = [];
        this.filterAlumni();
    }

    loadFilterOptionsData() {
        getAllAlumniForFilterOptions()
            .then((result) => {
                const rows = Array.isArray(result) ? result : [];
                this.allAlumniForFilterOptions = rows.map((row) => this.normalizeAlumniRow(row));
                this.rebuildFilterOptions(true);
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('KenNetworkPage.loadFilterOptionsData failed', error);
                this.allAlumniForFilterOptions = [];
            });
    }

    loadNetworkData() {
        getNetworkData()
            .then((result) => {
                const allRows = Array.isArray(result?.allAlumni) ? result.allAlumni : [];
                const connectionRows = Array.isArray(result?.yourConnections) ? result.yourConnections : [];
                const requestRows = Array.isArray(result?.connectionRequests) ? result.connectionRequests : [];

                this.allAlumni = allRows.map((row) => this.normalizeAlumniRow(row));
                this.connectedAlumni = connectionRows.map((row) => this.normalizeAlumniRow(row));
                this.connectionRequests = requestRows.map((row) => this.normalizeConnectionRequestRow(row));
                this.currentUserCity  = (result?.currentUserCity  || '').trim().toLowerCase();
                this.currentUserState = (result?.currentUserState || '').trim().toLowerCase();
                this.onlineUsers = [];
                this.rebuildFilterOptions(true);
                this.filterAlumni();
            })
            .catch((error) => {
                // Keep fallback behavior but log server errors for faster debugging.
                // eslint-disable-next-line no-console
                console.error('KenNetworkPage.loadNetworkData failed', error);
                this.allAlumni = [];
                this.connectedAlumni = [];
                this.connectionRequests = [];
                this.onlineUsers = [];
                this.filteredAlumni = [];
            });
    }

    normalizeAlumniRow(row) {
        const location = this.toFilterValue(row?.location);
        const lastActive = row?.lastActive || null;
        const calculatedPresenceStatus = this.getPresenceStatus(lastActive);
        const presenceStatus = row?.isOnline === true ? 'online' : calculatedPresenceStatus;
        const programLastAttended = this.toFilterValue(row?.programLastAttended);
        const graduationYear = this.toFilterValue(row?.graduationYear);
        return {
            id: row?.id || '',
            name: row?.name || '',
            title: row?.title || '',
            company: this.toFilterValue(row?.company),
            industry: this.toFilterValue(row?.industry),
            jobFunction: this.toFilterValue(row?.jobFunction || row?.title),
            programLastAttended,
            specialisation: this.toFilterValue(row?.specialisation),
            currentCity: this.toFilterValue(row?.currentCity || this.extractCity(location)),
            location,
            // Card 3rd line: mirror the detail view's educationLine
            // (program | year, else program, else batch) instead of the blanks
            // that used to leave every card's education row empty.
            batch: this.toFilterValue(row?.batch),
            graduationYear,
            institute: this.toFilterValue(row?.institute),
            program: this.toFilterValue(row?.program),
            intake: this.toFilterValue(row?.intake),
            employmentType: this.toFilterValue(row?.employmentType),
            gender: this.toFilterValue(row?.gender),
            languages: this.toLanguageList(row?.language),
            country: this.toFilterValue(row?.country),
            education: this.buildEducationLine(programLastAttended, graduationYear),
            profileImage: row?.profileImage || AlumniAlt,
            lastActive,
            presenceStatus,
            willingToHelp: row?.willingToHelp === true,
            isMentor: row?.isMentor === true,
            isMyMentor: row?.isMyMentor === true,
            isOnline: presenceStatus === 'online'
        };
    }

    normalizeConnectionRequestRow(row) {
        return {
            id: row?.id || '',
            personAccountId: row?.personAccountId || '',
            name: row?.name || '',
            dateTime: row?.requestDateTime || row?.dateTime || '',
            profileImage: row?.profileImage || AlumniAlt,
            isOnline: row?.isOnline === true
        };
    }

    handleTabChange(event) {
        this.activeTab = event.detail.tab;
        this.showMobileListFullView = false;
        this.filterAlumni();
    }

    get isMissingTab() {
        return this.activeTab === 'missing';
    }

    get mobileVisibleAlumni() {
        if (!this.isMobile) return this.filteredAlumni || [];
        const list = this.filteredAlumni || [];
        return list.slice(0, 4);
    }

    get showViewMoreButton() {
        return this.isMobile && !this.showMobileListFullView && (this.filteredAlumni || []).length > 4;
    }

    get activeTabLabel() {
        return this.activeTab === 'all' ? 'All Alumni' : 'Your Connections';
    }

    get networkContainerClass() {
        return this.showMobileListFullView ? 'network-container mobile-full-view-active' : 'network-container';
    }

    handleViewMore() {
        this.showMobileListFullView = true;
    }

    handleMobileListBack() {
        this.showMobileListFullView = false;
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value;
        this.filterAlumni();
    }

    get activeFilterCount() {
        const scalarCount = FILTER_FIELDS.filter((f) => this.toFilterValue(this.selectedFilters[f])).length;
        const languageCount = (this.selectedFilters.language || []).length > 0 ? 1 : 0;
        return scalarCount + languageCount;
    }

    filterAlumni() {
        let filtered = [...this.alumniSource];

        if (this.searchTerm) {
            const searchLower = this.searchTerm.toLowerCase();
            filtered = filtered.filter((alumni) =>
                (alumni.name || '').toLowerCase().includes(searchLower) ||
                (alumni.title || '').toLowerCase().includes(searchLower) ||
                (alumni.location || '').toLowerCase().includes(searchLower) ||
                (alumni.company || '').toLowerCase().includes(searchLower) ||
                (alumni.industry || '').toLowerCase().includes(searchLower) ||
                (alumni.programLastAttended || '').toLowerCase().includes(searchLower) ||
                (alumni.specialisation || '').toLowerCase().includes(searchLower) ||
                (alumni.graduationYear || '').toLowerCase().includes(searchLower) ||
                (alumni.currentCity || '').toLowerCase().includes(searchLower) ||
                (alumni.batch || '').toLowerCase().includes(searchLower)
            );
        }

        filtered = this.applySelectedFilters(filtered);

        if (this.showMentorsNearMe) {
            const city = this.currentUserCity;
            const state = this.currentUserState;
            filtered = filtered
                .map((a) => {
                    const aCity = (a.currentCity || '').trim().toLowerCase();
                    const aState = this._extractStateFromLocation(a.location);
                    let rank;
                    if (city && aCity && aCity === city) {
                        rank = 0;
                    } else if (state && aState && aState === state) {
                        rank = 1;
                    } else {
                        rank = 2;
                    }
                    return { ...a, _nearbyRank: rank };
                })
                .filter((a) => a._nearbyRank < 2)
                .sort((a, b) => a._nearbyRank - b._nearbyRank);
        } else if (this.sortBy === 'a-z') {
            filtered.sort((a, b) => (a.name || '').localeCompare(b.name || '', undefined, { sensitivity: 'base' }));
        } else if (this.sortBy === 'z-a') {
            filtered.sort((a, b) => (b.name || '').localeCompare(a.name || '', undefined, { sensitivity: 'base' }));
        }

        this.filteredAlumni = filtered;
    }

    get showNearbyEmpty() {
        return this.showMentorsNearMe && this.filteredAlumni.length === 0;
    }

    applySelectedFilters(rows) {
        const activeFields = FILTER_FIELDS.filter((field) => this.toFilterValue(this.selectedFilters[field]));
        let filtered = rows;
        if (activeFields.length) {
            filtered = filtered.filter((alumni) =>
                activeFields.every((field) =>
                    this.toFilterValue(alumni[field]).toLowerCase() === this.toFilterValue(this.selectedFilters[field]).toLowerCase()
                )
            );
        }

        // Language is multi-select (OR within the selection — knowing ANY of
        // the picked languages counts), unlike every field above which is an
        // exact single-value match ANDed together.
        const selectedLanguages = (this.selectedFilters.language || []).map((v) => v.toLowerCase());
        if (selectedLanguages.length) {
            filtered = filtered.filter((alumni) => {
                const alumniLanguages = (alumni.languages || []).map((v) => v.toLowerCase());
                return selectedLanguages.some((lang) => alumniLanguages.includes(lang));
            });
        }

        return filtered;
    }

    rebuildFilterOptions(pruneInvalid = true) {
        const buckets = {};
        FILTER_FIELDS.forEach((field) => {
            buckets[field] = new Set();
        });
        const languageBucket = new Set();

        this.allKnownAlumni.forEach((alumni) => {
            FILTER_FIELDS.forEach((field) => {
                const value = this.toFilterValue(alumni[field]);
                if (value) {
                    buckets[field].add(value);
                }
            });
            (alumni.languages || []).forEach((lang) => languageBucket.add(lang));
        });

        const nextOptions = {};
        FILTER_FIELDS.forEach((field) => {
            nextOptions[field] = Array.from(buckets[field])
                .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }))
                .map((value) => ({ label: value, value }));
        });
        nextOptions.language = Array.from(languageBucket)
            .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }))
            .map((value) => ({ label: value, value }));

        this.filterOptions = nextOptions;
        if (pruneInvalid) {
            this.pruneInvalidSelectedFilters(nextOptions);
        }
    }

    pruneInvalidSelectedFilters(optionsByField) {
        let hasChanges = false;
        const nextSelected = { ...this.selectedFilters };

        FILTER_FIELDS.forEach((field) => {
            const selectedValue = this.toFilterValue(nextSelected[field]);
            if (!selectedValue) {
                return;
            }

            const exists = (optionsByField[field] || []).some((opt) => opt.value === selectedValue);
            if (!exists) {
                nextSelected[field] = '';
                hasChanges = true;
            }
        });

        const validLanguages = new Set((optionsByField.language || []).map((opt) => opt.value));
        const prunedLanguages = (nextSelected.language || []).filter((v) => validLanguages.has(v));
        if (prunedLanguages.length !== (nextSelected.language || []).length) {
            nextSelected.language = prunedLanguages;
            hasChanges = true;
        }

        if (hasChanges) {
            this.selectedFilters = nextSelected;
        }
    }

    handleFilterValueChange(event) {
        const field = event.currentTarget.dataset.field;
        if (!FILTER_FIELDS.includes(field)) {
            return;
        }
        this.selectedFilters = {
            ...this.selectedFilters,
            [field]: event.detail.value || ''
        };
        this.filterAlumni();
    }

    get sortIconClass() {
        return this.sortBy === 'z-a' ? 'sort-arrow sort-arrow-desc' : 'sort-arrow';
    }

    handleSortClick(event) {
        event.stopPropagation();
        this.sortBy = this.sortBy === 'a-z' ? 'z-a' : 'a-z';
        this.filterAlumni();
    }

    handleSortChange(event) {
        this.sortBy = event.detail || '';
        this.filterAlumni();
    }

    handleFiltersClick() {
        this.showFiltersPopup = !this.showFiltersPopup;
        if (this.showFiltersPopup) {
            this.rebuildFilterOptions(false);
        }
    }

    renderedCallback() {
        if (this.showFiltersPopup) {
            this.positionPopup();
        }
    }

    positionPopup() {
        if (this.isMobile) {
            const popup = this.template.querySelector('.filters-popup');
            if (popup) {
                popup.style.top = '';
                popup.style.right = '';
                popup.style.left = '';
            }
            return;
        }
        const filterBtn = this.template.querySelector('[data-filter-btn="true"]');
        const popup = this.template.querySelector('.filters-popup');
        if (filterBtn && popup) {
            const rect = filterBtn.getBoundingClientRect();
            const popupWidth = 400;
            const viewportWidth = window.innerWidth;
            const viewportHeight = window.innerHeight;
            let top = rect.bottom + 8;
            let right = viewportWidth - rect.right;
            if (top + 500 > viewportHeight) {
                top = rect.top - 500 - 8;
                if (top < 0) top = 8;
            }
            if (right + popupWidth > viewportWidth) right = 24;
            popup.style.top = `${top}px`;
            popup.style.right = `${right}px`;
            popup.style.left = 'auto';
        }
    }

    handleFiltersOverlayClick(event) {
        if (event.target.classList.contains('filters-overlay')) {
            this.showFiltersPopup = false;
        }
    }

    handleFiltersPopupClick(event) {
        event.stopPropagation();
    }

    handleMapViewOpen() {
        // Full-page modal now — only the map's own header (~80px) eats into
        // the viewport, not the card margins the old capped 720px assumed.
        this.mapModalHeight = Math.max(420, window.innerHeight - 90);
        this.showMapModal = true;
    }

    handleMapModalClose() {
        this.showMapModal = false;
    }

    handleMapModalClick(event) {
        event.stopPropagation();
    }

    handleMapProfileSelect(event) {
        const personId = event.detail && event.detail.personId;
        if (!personId) {
            return;
        }
        this.handleMapModalClose();
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'network__c' },
            state: { profileId: personId }
        });
    }

    handleToggleClick(event) {
        event.preventDefault();
        this.showMentorsNearMe = !this.showMentorsNearMe;
        this.filterAlumni();
    }

    handleResetFilters() {
        this.showMentorsNearMe = false;
        this.selectedFilters = {
            company: '',
            industry: '',
            jobFunction: '',
            employmentType: '',
            gender: '',
            programLastAttended: '',
            graduationYear: '',
            currentCity: '',
            institute: '',
            program: '',
            intake: '',
            country: '',
            language: []
        };
        this.filterAlumni();
    }

    // Separate from handleFilterValueChange since kenMultiSelectPicklist
    // dispatches detail.value as an array, not the single string every other
    // filter's handler assumes.
    handleLanguageFilterChange(event) {
        const value = (event.detail && event.detail.value) || [];
        this.selectedFilters = { ...this.selectedFilters, language: value };
        this.filterAlumni();
    }

    handleApplyFilters() {
        this.showFiltersPopup = false;
        this.filterAlumni();
    }

    handleAcceptRequest(event) {
        const requestId = event.detail.id;
        this.updateConnectionRequest(requestId, 'accept');
    }

    handleDeclineRequest(event) {
        const requestId = event.detail.id;
        this.updateConnectionRequest(requestId, 'reject');
    }

    updateConnectionRequest(requestId, action) {
        if (!requestId) {
            return;
        }
        respondToConnectionRequests({ requestIds: [requestId], action })
            .then((processedIds) => {
                const handledIds = new Set((processedIds || []).map((id) => String(id)));
                if (!handledIds.has(String(requestId))) {
                    return;
                }
                this.connectionRequests = this.connectionRequests.filter((req) => !handledIds.has(String(req.id)));
                this.loadNetworkData();
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('KenNetworkPage.updateConnectionRequest failed', error);
                // keep existing list and retry on next refresh
            });
    }

    get selectedUserName() {
        return this.selectedUser ? this.selectedUser.name : '';
    }

    get selectedUserBatch() {
        return this.selectedUser ? this.selectedUser.batch : '';
    }

    get selectedUserProfileImage() {
        return this.selectedUser ? this.selectedUser.profileImage : '';
    }

    handleProfileClick(event) {
        const alumniId = event.detail.id;
        const clickedAlumni = this.alumniSource.find((alumni) => String(alumni.id) === String(alumniId))
            || this.allAlumni.find((alumni) => String(alumni.id) === String(alumniId));

        this.selectedUser = clickedAlumni || null;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'network__c' },
            state: { profileId: alumniId }
        });
    }

    handleBackFromProfile() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'network__c' },
            state: {}
        });
    }

    handleCloseUserNotFoundModal() {
        this.showUserNotFoundModal = false;
        this.selectedUser = null;
    }

    handleCopyLink() {
        const url = this.inviteUrl || this.portalUrl;
        if (!url) return;
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(url).then(() => {
                this.copySuccess = true;
                setTimeout(() => { this.copySuccess = false; }, 2000);
            }).catch(() => {
                this._fallbackCopy(url);
            });
        } else {
            this._fallbackCopy(url);
        }
    }

    _fallbackCopy(text) {
        const input = this.template.querySelector('.invite-input');
        if (input) {
            input.select();
            try {
                document.execCommand('copy');
                this.copySuccess = true;
                setTimeout(() => { this.copySuccess = false; }, 2000);
            } catch (e) { /* silent */ }
        }
    }

    toFilterValue(value) {
        if (value === null || value === undefined) {
            return '';
        }
        return String(value).trim();
    }

    // Languages_Known__c is free text ("English, Hindi, Tamil"), not a
    // picklist, so a person can have several — this splits + normalizes each
    // one (title case, so "tamil"/"Tamil"/"TAMIL" all match) instead of the
    // single-scalar toFilterValue() every other field uses. Same casing
    // convention as KenAdminAlumniController.normalizeLanguageLabel(), for a
    // consistent list between the admin and portal filters.
    toLanguageList(value) {
        if (!value) {
            return [];
        }
        const seen = new Set();
        const out = [];
        String(value)
            .split(',')
            .map((part) => part.trim())
            .filter((part) => part.length > 0)
            .forEach((part) => {
                const normalized = part
                    .toLowerCase()
                    .split(/\s+/)
                    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
                    .join(' ');
                if (!seen.has(normalized)) {
                    seen.add(normalized);
                    out.push(normalized);
                }
            });
        return out;
    }

    // Same shape as kenAlumniDetailView.educationLine so list cards read like
    // the profile header: "B.Tech CS | 2021", else the program, else blank.
    buildEducationLine(program, year) {
        const p = (program || '').trim();
        const y = (year || '').trim();
        if (p && y) return `${p} | ${y}`;
        return p;
    }

    getPresenceStatus(lastActive) {
        if (!lastActive) {
            return 'offline';
        }
        const lastActiveMs = Date.parse(lastActive);
        if (Number.isNaN(lastActiveMs)) {
            return 'offline';
        }

        const elapsedMs = Date.now() - lastActiveMs;
        if (elapsedMs <= ONLINE_WINDOW_MS) {
            return 'online';
        }
        return 'offline';
    }

    extractCity(location) {
        const value = this.toFilterValue(location);
        if (!value) {
            return '';
        }
        return value.split(',')[0].trim();
    }

    _extractStateFromLocation(location) {
        const value = this.toFilterValue(location);
        if (!value) {
            return '';
        }
        const parts = value.split(',');
        return parts.length >= 2 ? parts[1].trim().toLowerCase() : '';
    }
}