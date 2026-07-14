import { LightningElement, track, api } from 'lwc';
import getPrimaryColor from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';

export default class KenPortalRegisterEvent extends LightningElement {
    @api eventId;
    @api eventTitle = 'Entrepreneurship Bootcamp';
    @api eventDates = '11-12 Mar 2025';
    @api eventLocation = 'Hybrid';
    @api eventLanguage = 'English';
    @api pricePerParticipant = '₹250';

    @track currentStep = 1;
    @track isStep1Completed = false;
    @track isStep2Completed = false;
    @track isStep3Completed = false;

    // Step 1: Participants
    @track registrationType = 'myself'; // 'myself' or 'bulk'
    @track participantGroups = [];
    @track participants = [];
    @track guestName = '';
    @track guestEmail = '';
    @track guestPhone = '';
    @track guestPhoneCountry = null;
    @track selectedCountryCode = '+91';
    @track searchTerm = '';
    @track currentPage = 1;
    @track itemsPerPage = 10;

    // Step 2: Sessions
    @track sessionDateGroups = [];
    @track selectedSessionIds = new Set();

    // Step 3: Summary
    @track mealsStatus = 'Yes (Included for all)';

    // Country codes
    countryCodeOptions = [
        { label: '+91', value: '+91' },
        { label: '+1', value: '+1' },
        { label: '+44', value: '+44' }
    ];

    // Dietary options
    dietaryOptions = [
        { label: 'Select', value: '' },
        { label: 'Vegetarian', value: 'vegetarian' },
        { label: 'Vegan', value: 'vegan' },
        { label: 'Gluten-Free', value: 'gluten-free' },
        { label: 'No Preference', value: 'none' }
    ];

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });

        // Initialize with sample data
        this.initializeSampleData();
    }

    initializeSampleData() {
        // Sample participant groups
        this.participantGroups = [
            { id: '1', name: 'Batch 2018', memberCount: '1.2k members', selected: false },
            { id: '2', name: '5K Runners Group', memberCount: '1.2k members', selected: false },
            { id: '3', name: 'Class of 2018 Network', memberCount: '1.2k members', selected: false },
            { id: '4', name: 'Film Buff Collective', memberCount: '1.2k members', selected: false }
        ];

        // Sample participants
        this.participants = [
            {
                id: '1',
                name: 'John Doe',
                email: 'john.doe@company.com',
                phone: '+91 98765 43210',
                type: 'myself',
                selected: false,
                mealsEnabled: false,
                dietaryPreference: ''
            },
            {
                id: '2',
                name: 'Alice Smith',
                email: 'alice.smith@company.com',
                phone: '+91 98765 43210',
                type: 'guest',
                selected: false,
                mealsEnabled: false,
                dietaryPreference: ''
            },
            {
                id: '3',
                name: 'Bob Johnson',
                email: 'bob.johnson@company.com',
                phone: '+91 98765 43211',
                type: 'group',
                selected: false,
                mealsEnabled: false,
                dietaryPreference: ''
            }
        ];

        // Sample session date groups
        this.sessionDateGroups = [
            {
                dateKey: '2025-03-11',
                displayDate: '11 Mar, 2025',
                allSelected: false,
                allSessionsPrice: '₹750',
                sessions: [
                    {
                        id: 's1',
                        name: 'Blockchain and Cryptocurrency Demystified',
                        timeRange: '01:00 PM - 02:00 PM',
                        price: '₹250',
                        selected: true
                    },
                    {
                        id: 's2',
                        name: 'Digital Banking Innovations',
                        timeRange: '01:00 PM - 02:00 PM',
                        price: '₹250',
                        selected: true
                    },
                    {
                        id: 's3',
                        name: 'Revolutionizing Finance: The Future of Digital Banking',
                        timeRange: '01:00 PM - 02:00 PM',
                        price: '₹250',
                        selected: false
                    }
                ]
            },
            {
                dateKey: '2025-03-12',
                displayDate: '12 Mar, 2025',
                allSelected: false,
                allSessionsPrice: '₹500',
                sessions: [
                    {
                        id: 's4',
                        name: 'Understanding Blockchain: A Guide to Cryptocurrency and Its Impact',
                        timeRange: '01:00 PM - 02:00 PM',
                        price: '₹250',
                        selected: true
                    }
                ]
            }
        ];

        // Initialize selected sessions
        this.sessionDateGroups.forEach(group => {
            group.sessions.forEach(session => {
                if (session.selected) {
                    this.selectedSessionIds.add(session.id);
                }
            });
        });
    }

    // Step navigation
    get isStep1Active() {
        return this.currentStep === 1;
    }

    get isStep2Active() {
        return this.currentStep === 2;
    }

    get isStep3Active() {
        return this.currentStep === 3;
    }

    // Step 1: Registration Type Toggle
    get myselfButtonClass() {
        return this.registrationType === 'myself' 
            ? 'toggle-btn toggle-btn-active' 
            : 'toggle-btn';
    }

    get bulkButtonClass() {
        return this.registrationType === 'bulk' 
            ? 'toggle-btn toggle-btn-active' 
            : 'toggle-btn';
    }

    get isBulkRegistration() {
        return this.registrationType === 'bulk';
    }

    get isMyselfRegistration() {
        return this.registrationType === 'myself';
    }

    handleMyselfClick() {
        this.registrationType = 'myself';
    }

    handleBulkClick() {
        this.registrationType = 'bulk';
    }

    // Step 1: Participant Groups
    get hasParticipantGroups() {
        return this.participantGroups && this.participantGroups.length > 0;
    }

    handleGroupToggle(event) {
        const groupId = event.target.dataset.groupId;
        this.participantGroups = this.participantGroups.map(group => {
            if (group.id === groupId) {
                return { ...group, selected: event.target.checked };
            }
            return group;
        });
    }

    // Step 1: Add Guest Form
    handleGuestNameChange(event) {
        this.guestName = event.target.value;
    }

    handleGuestEmailChange(event) {
        this.guestEmail = event.target.value;
    }

    handlePhoneInputChange(event) {
        const detail = event.detail;
        this.guestPhone = detail.phoneNumber || '';
        this.guestPhoneCountry = detail.country || null;
        if (detail.country) {
            this.selectedCountryCode = detail.country.dialCode;
        }
    }

    get isAddGuestDisabled() {
        return !this.guestName || !this.guestEmail || !this.guestPhone || this.participants.length >= 5;
    }

    handleAddGuest() {
        if (this.isAddGuestDisabled) return;

        // Format phone number with country code
        const phoneNumber = this.guestPhoneCountry 
            ? `${this.guestPhoneCountry.dialCode} ${this.guestPhone}` 
            : `${this.selectedCountryCode} ${this.guestPhone}`;

        const newGuest = {
            id: Date.now().toString(),
            name: this.guestName,
            email: this.guestEmail,
            phone: phoneNumber,
            type: 'guest',
            selected: false,
            mealsEnabled: false,
            dietaryPreference: ''
        };

        this.participants = [...this.participants, newGuest];
        
        // Reset form
        this.guestName = '';
        this.guestEmail = '';
        this.guestPhone = '';
        this.guestPhoneCountry = null;
    }

    // Step 1: Participants Table
    get participantsCount() {
        return this.participants.length;
    }

    get displayedParticipants() {
        const filtered = this.searchTerm
            ? this.participants.filter(p => 
                p.name.toLowerCase().includes(this.searchTerm.toLowerCase()) ||
                p.email.toLowerCase().includes(this.searchTerm.toLowerCase())
            )
            : this.participants;

        const start = (this.currentPage - 1) * this.itemsPerPage;
        const end = start + this.itemsPerPage;
        return filtered.slice(start, end).map(p => ({
            ...p,
            typeClass: `type-pill type-pill-${p.type}`,
            typeLabel: p.type === 'myself' ? 'Myself' : p.type === 'guest' ? 'Guest' : 'Group'
        }));
    }

    get allSelected() {
        return this.displayedParticipants.length > 0 && 
               this.displayedParticipants.every(p => p.selected);
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        this.currentPage = 1; // Reset to first page on search
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        const displayedIds = this.displayedParticipants.map(p => p.id);
        this.participants = this.participants.map(p => {
            if (displayedIds.includes(p.id)) {
                return { ...p, selected: checked };
            }
            return p;
        });
    }

    handleParticipantToggle(event) {
        const participantId = event.target.dataset.participantId;
        this.participants = this.participants.map(p => {
            if (p.id === participantId) {
                return { ...p, selected: event.target.checked };
            }
            return p;
        });
    }

    handleMealsToggle(event) {
        const participantId = event.target.dataset.participantId;
        this.participants = this.participants.map(p => {
            if (p.id === participantId) {
                return { ...p, mealsEnabled: event.target.checked };
            }
            return p;
        });
    }

    handleDietaryChange(event) {
        const participantId = event.target.dataset.participantId;
        this.participants = this.participants.map(p => {
            if (p.id === participantId) {
                return { ...p, dietaryPreference: event.target.value };
            }
            return p;
        });
    }

    handleFillSurvey(event) {
        const participantId = event.currentTarget.dataset.participantId;
        // TODO: Implement survey fill functionality
        console.log('Fill survey for participant:', participantId);
    }

    handleShareSurvey(event) {
        const participantId = event.currentTarget.dataset.participantId;
        // TODO: Implement share survey functionality
        console.log('Share survey for participant:', participantId);
    }

    handleDeleteParticipant(event) {
        const participantId = event.currentTarget.dataset.participantId;
        this.participants = this.participants.filter(p => p.id !== participantId);
    }

    // Pagination
    get totalPages() {
        const filtered = this.searchTerm
            ? this.participants.filter(p => 
                p.name.toLowerCase().includes(this.searchTerm.toLowerCase()) ||
                p.email.toLowerCase().includes(this.searchTerm.toLowerCase())
            )
            : this.participants;
        return Math.ceil(filtered.length / this.itemsPerPage);
    }

    get pageNumbers() {
        const total = this.totalPages;
        const pages = [];
        
        if (total <= 7) {
            for (let i = 1; i <= total; i++) {
                pages.push({
                    value: i,
                    label: i.toString(),
                    isActive: i === this.currentPage,
                    isEllipsis: false,
                    pageButtonClass: i === this.currentPage ? 'page-btn active' : 'page-btn'
                });
            }
        } else {
            pages.push({
                value: 1,
                label: '1',
                isActive: 1 === this.currentPage,
                isEllipsis: false,
                pageButtonClass: 1 === this.currentPage ? 'page-btn active' : 'page-btn'
            });
            if (this.currentPage > 3) {
                pages.push({
                    value: null,
                    label: '...',
                    isActive: false,
                    isEllipsis: true,
                    pageButtonClass: ''
                });
            }
            for (let i = Math.max(2, this.currentPage - 1); i <= Math.min(total - 1, this.currentPage + 1); i++) {
                pages.push({
                    value: i,
                    label: i.toString(),
                    isActive: i === this.currentPage,
                    isEllipsis: false,
                    pageButtonClass: i === this.currentPage ? 'page-btn active' : 'page-btn'
                });
            }
            if (this.currentPage < total - 2) {
                pages.push({
                    value: null,
                    label: '...',
                    isActive: false,
                    isEllipsis: true,
                    pageButtonClass: ''
                });
            }
            pages.push({
                value: total,
                label: total.toString(),
                isActive: total === this.currentPage,
                isEllipsis: false,
                pageButtonClass: total === this.currentPage ? 'page-btn active' : 'page-btn'
            });
        }
        
        return pages;
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    handlePageClick(event) {
        const page = parseInt(event.currentTarget.dataset.page);
        if (!isNaN(page)) {
            this.currentPage = page;
        }
    }

    // Step 2: Sessions
    handleAllSessionsToggle(event) {
        const dateKey = event.target.dataset.dateKey;
        const checked = event.target.checked;
        
        this.sessionDateGroups = this.sessionDateGroups.map(group => {
            if (group.dateKey === dateKey) {
                const updatedSessions = group.sessions.map(session => ({
                    ...session,
                    selected: checked
                }));
                
                if (checked) {
                    updatedSessions.forEach(s => this.selectedSessionIds.add(s.id));
                } else {
                    updatedSessions.forEach(s => this.selectedSessionIds.delete(s.id));
                }
                
                return {
                    ...group,
                    allSelected: checked,
                    sessions: updatedSessions
                };
            }
            return group;
        });
    }

    handleSessionToggle(event) {
        const sessionId = event.target.dataset.sessionId;
        const dateKey = event.target.dataset.dateKey;
        const checked = event.target.checked;
        
        if (checked) {
            this.selectedSessionIds.add(sessionId);
        } else {
            this.selectedSessionIds.delete(sessionId);
        }
        
        this.sessionDateGroups = this.sessionDateGroups.map(group => {
            if (group.dateKey === dateKey) {
                const updatedSessions = group.sessions.map(session => {
                    if (session.id === sessionId) {
                        return { ...session, selected: checked };
                    }
                    return session;
                });
                
                const allSelected = updatedSessions.every(s => s.selected);
                
                return {
                    ...group,
                    allSelected,
                    sessions: updatedSessions
                };
            }
            return group;
        });
    }

    // Step 3: Summary
    get selectedSessionsByDate() {
        return this.sessionDateGroups
            .map(group => ({
                ...group,
                sessions: group.sessions.filter(s => s.selected)
            }))
            .filter(group => group.sessions.length > 0);
    }

    get selectedSessionsCount() {
        return this.selectedSessionIds.size;
    }

    get sessionFeePerSession() {
        return '₹250';
    }

    get totalSessionFee() {
        return `₹${this.selectedSessionsCount * 250}`;
    }

    get totalPayable() {
        return `₹${this.selectedSessionsCount * 250 * this.participantsCount}`;
    }

    // Navigation
    handleNextStep() {
        if (this.currentStep === 1) {
            if (this.participants.length === 0) {
                // Show error - at least one participant required
                return;
            }
            this.isStep1Completed = true;
        } else if (this.currentStep === 2) {
            if (this.selectedSessionIds.size === 0) {
                // Show error - at least one session required
                return;
            }
            this.isStep2Completed = true;
        }

        if (this.currentStep < 3) {
            this.currentStep++;
        }
    }

    handlePreviousStep() {
        if (this.currentStep > 1) {
            this.currentStep--;
        }
    }

    handleCancel() {
        // TODO: Handle cancel - navigate back or close modal
        console.log('Cancel registration');
    }

    handleProceedToPayment() {
        // TODO: Navigate to payment page
        console.log('Proceed to payment');
    }
}