import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
// JSON Data for Log History
// 18 entries: 5 with 09-12-2025, 10 with 10-12-2025, 3 with 11-12-2025
const LOG_HISTORY_JSON = [
    // 5 entries for 09-12-2025
    {
        id: '1',
        timestamp: '2025-12-09T09:12:00',
        userType: 'Student',
        name: 'Ramesh K',
        studentId: '21939',
        passType: '-',
        method: 'Biometric',
        activity: 'Check-out',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    {
        id: '2',
        timestamp: '2025-12-09T10:12:00',
        userType: 'Student',
        name: 'Ramesh K',
        studentId: '21939',
        passType: '-',
        method: 'Biometric',
        activity: 'Check-in',
        status: 'Out campus',
        actionTaken: 'Logged'
    },
    {
        id: '3',
        timestamp: '2025-12-09T11:15:00',
        userType: 'Student',
        name: 'Arjun Verma',
        studentId: '22001',
        passType: 'Night Out Request',
        method: 'QR Scan',
        activity: 'Check-out',
        status: 'In campus (late)',
        actionTaken: 'Escalated to Warden'
    },
    {
        id: '4',
        timestamp: '2025-12-09T14:30:00',
        userType: 'Student',
        name: 'Kiran Kumar',
        studentId: '22002',
        passType: 'Night Out Request',
        method: 'QR Scan',
        activity: 'Check-out',
        status: 'Out campus',
        actionTaken: 'Logged'
    },
    {
        id: '5',
        timestamp: '2025-12-09T16:45:00',
        userType: 'Student',
        name: 'Sneha Patel',
        studentId: '22003',
        passType: 'Night Out Request',
        method: 'QR Scan',
        activity: 'Check-in',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    // 10 entries for 10-12-2025
    {
        id: '6',
        timestamp: '2025-12-10T08:00:00',
        userType: 'Student',
        name: 'Amit Sharma',
        studentId: '22004',
        passType: '-',
        method: 'Biometric',
        activity: 'Check-in',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    {
        id: '7',
        timestamp: '2025-12-10T09:15:00',
        userType: 'Student',
        name: 'Priya Reddy',
        studentId: '22005',
        passType: '-',
        method: 'Biometric',
        activity: 'Check-in',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    {
        id: '8',
        timestamp: '2025-12-10T10:30:00',
        userType: 'Student',
        name: 'Rahul Mehta',
        studentId: '22006',
        passType: 'Night Out Request',
        method: 'QR Scan',
        activity: 'Check-out',
        status: 'Out campus',
        actionTaken: 'Logged'
    },
    {
        id: '9',
        timestamp: '2025-12-10T11:45:00',
        userType: 'Student',
        name: 'Anjali Desai',
        studentId: '22007',
        passType: 'Night Out Request',
        method: 'QR Scan',
        activity: 'Check-out',
        status: 'In campus (late)',
        actionTaken: 'Escalated to Warden'
    },
    {
        id: '10',
        timestamp: '2025-12-10T13:00:00',
        userType: 'Visitor',
        name: 'Vikram Singh',
        aadharId: '8293-9012-9901',
        passType: 'Visitor Request',
        method: 'QR Scan',
        activity: 'Check-in',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    {
        id: '11',
        timestamp: '2025-12-10T14:15:00',
        userType: 'Visitor',
        name: 'Priya Sharma',
        aadharId: '8293-9012-9902',
        passType: 'Visitor Request',
        method: 'QR Scan',
        activity: 'Check-in',
        status: 'In campus (late)',
        actionTaken: 'Escalated to Admin'
    },
    {
        id: '12',
        timestamp: '2025-12-10T15:30:00',
        userType: 'Student',
        name: 'Suresh Kumar',
        studentId: '22008',
        passType: '-',
        method: 'Biometric',
        activity: 'Check-out',
        status: 'Out campus',
        actionTaken: 'Logged'
    },
    {
        id: '13',
        timestamp: '2025-12-10T16:45:00',
        userType: 'Student',
        name: 'Meera Nair',
        studentId: '22009',
        passType: 'Night Out Request',
        method: 'QR Scan',
        activity: 'Check-out',
        status: 'Out campus',
        actionTaken: 'Logged'
    },
    {
        id: '14',
        timestamp: '2025-12-10T17:00:00',
        userType: 'Student',
        name: 'Rajesh Patel',
        studentId: '22010',
        passType: '-',
        method: 'Biometric',
        activity: 'Check-in',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    {
        id: '15',
        timestamp: '2025-12-10T18:15:00',
        userType: 'Visitor',
        name: 'Deepak Joshi',
        aadharId: '8293-9012-9903',
        passType: 'Visitor Request',
        method: 'QR Scan',
        activity: 'Check-out',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    // 3 entries for 11-12-2025
    {
        id: '16',
        timestamp: '2025-12-11T09:00:00',
        userType: 'Student',
        name: 'Neha Gupta',
        studentId: '22011',
        passType: '-',
        method: 'Biometric',
        activity: 'Check-in',
        status: 'In campus',
        actionTaken: 'Logged'
    },
    {
        id: '17',
        timestamp: '2025-12-11T12:30:00',
        userType: 'Student',
        name: 'Vikash Yadav',
        studentId: '22012',
        passType: 'Night Out Request',
        method: 'QR Scan',
        activity: 'Check-out',
        status: 'Out campus',
        actionTaken: 'Logged'
    },
    {
        id: '18',
        timestamp: '2025-12-11T15:45:00',
        userType: 'Visitor',
        name: 'Sunita Devi',
        aadharId: '8293-9012-9904',
        passType: 'Visitor Request',
        method: 'QR Scan',
        activity: 'Check-in',
        status: 'In campus (late)',
        actionTaken: 'Escalated to Admin'
    }
];


export default class KenTableview extends LightningElement {
    @track selectedTab = 'all';
    @track searchQuery = '';
    @track selectedTimeFilter = '30days';
    @track selectedDate = '';
    @track currentPage = 1;
    @track sortColumn = 'timestamp';
    @track sortDirection = 'desc';
    @track logs = [];
    itemsPerPage = 10;

    monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    connectedCallback() {
        // Don't set default date - let user select if needed
        // Only set selectedDate when user explicitly picks a date
        this.selectedDate = '';
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        // Load logs
        this.loadLogs();
    }

    renderedCallback() {
        // Hide format text from lightning-input date picker
        const dateInput = this.template.querySelector('.date-picker-input');
        if (dateInput) {
            // Hide help text/format text
            const helpText = dateInput.shadowRoot?.querySelector('.slds-form-element__help');
            if (helpText) {
                helpText.style.display = 'none';
            }
            
            // Also check for any span or div with format text
            const allElements = dateInput.shadowRoot?.querySelectorAll('*');
            if (allElements) {
                allElements.forEach(el => {
                    if (el.textContent && el.textContent.includes('Format:')) {
                        el.style.display = 'none';
                        el.style.visibility = 'hidden';
                        el.style.height = '0';
                        el.style.margin = '0';
                        el.style.padding = '0';
                    }
                });
            }
        }
    }

    loadLogs() {
        // Transform JSON data to match table structure
        this.logs = LOG_HISTORY_JSON.map(log => {
            const date = new Date(log.timestamp);
            let statusClass = 'status-badge';
            if (log.status === 'In campus') {
                statusClass += ' status-in-campus';
            } else if (log.status === 'Out campus') {
                statusClass += ' status-out-campus';
            } else if (log.status === 'In campus (late)') {
                statusClass += ' status-late';
            }
            
            // Format ID with type (Student ID or Aadhar ID)
            let formattedId = '';
            if (log.studentId) {
                formattedId = `${log.studentId} Student ID`;
            } else if (log.aadharId) {
                formattedId = `${log.aadharId} Aadhar ID`;
            }
            
            // Add bullet point to status
            const statusWithBullet = `• ${log.status}`;
            
            return {
                ...log,
                id: log.studentId || log.aadharId,
                formattedId: formattedId,
                formattedTimestamp: this.formatTimestamp(date),
                passType: log.passType || '-',
                statusClass: statusClass.trim(),
                statusWithBullet: statusWithBullet
            };
        });
    }

    formatDateString(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatTimestamp(date) {
        const day = date.getDate();
        const month = this.monthNames[date.getMonth()];
        const year = date.getFullYear();
        const hours = date.getHours();
        const minutes = date.getMinutes();
        const period = hours >= 12 ? 'PM' : 'AM';
        const displayHours = hours % 12 || 12;
        const displayMinutes = String(minutes).padStart(2, '0');
        
        return `${day} ${month} ${year}, ${displayHours}:${displayMinutes} ${period}`;
    }

    get formattedSelectedDate() {
        if (!this.selectedDate) {
            // Show today's date as default display
            const today = new Date();
            const day = today.getDate();
            const month = this.monthNames[today.getMonth()];
            const year = today.getFullYear();
            return `${day} ${month} ${year}`;
        }
        const date = new Date(this.selectedDate + 'T00:00:00');
        const day = date.getDate();
        const month = this.monthNames[date.getMonth()];
        const year = date.getFullYear();
        return `${day} ${month} ${year}`;
    }

    get tabButtonClassAll() {
        return `tab-button ${this.selectedTab === 'all' ? 'active' : ''}`.trim();
    }

    get tabButtonClassStudents() {
        return `tab-button ${this.selectedTab === 'students' ? 'active' : ''}`.trim();
    }

    get tabButtonClassVisitors() {
        return `tab-button ${this.selectedTab === 'visitors' ? 'active' : ''}`.trim();
    }

    get timeFilterClass30Days() {
        return `time-filter-button ${this.selectedTimeFilter === '30days' ? 'active' : ''}`.trim();
    }

    get timeFilterClass7Days() {
        return `time-filter-button ${this.selectedTimeFilter === '7days' ? 'active' : ''}`.trim();
    }

    get timeFilterClass24Hours() {
        return `time-filter-button ${this.selectedTimeFilter === '24hours' ? 'active' : ''}`.trim();
    }

    get filteredLogs() {
        let filtered = [...this.logs];

        // Filter by tab (User Type)
        if (this.selectedTab === 'students') {
            filtered = filtered.filter(log => log.userType === 'Student');
        } else if (this.selectedTab === 'visitors') {
            filtered = filtered.filter(log => log.userType === 'Visitor');
        }

        // Filter by search query
        if (this.searchQuery) {
            const query = this.searchQuery.toLowerCase();
            filtered = filtered.filter(log => 
                log.name.toLowerCase().includes(query) ||
                (log.studentId && log.studentId.includes(query)) ||
                (log.aadharId && log.aadharId.includes(query))
            );
        }

        // Filter by time range (only if not filtering by specific date)
        if (!this.selectedDate) {
            const now = new Date();
            const filterDate = new Date(now);
            
            if (this.selectedTimeFilter === '24hours') {
                filterDate.setHours(filterDate.getHours() - 24);
                filtered = filtered.filter(log => {
                    const logDate = new Date(log.timestamp);
                    return logDate >= filterDate;
                });
            } else if (this.selectedTimeFilter === '7days') {
                filterDate.setDate(filterDate.getDate() - 7);
                filtered = filtered.filter(log => {
                    const logDate = new Date(log.timestamp);
                    return logDate >= filterDate;
                });
            } else if (this.selectedTimeFilter === '30days') {
                filterDate.setDate(filterDate.getDate() - 30);
                filtered = filtered.filter(log => {
                    const logDate = new Date(log.timestamp);
                    return logDate >= filterDate;
                });
            }
            // If no time filter or 'all', show all data
        }

        // Filter by selected date if explicitly provided
        if (this.selectedDate) {
            const selected = new Date(this.selectedDate + 'T00:00:00');
            filtered = filtered.filter(log => {
                const logDate = new Date(log.timestamp);
                return logDate.toDateString() === selected.toDateString();
            });
        }

        // Sort
        filtered.sort((a, b) => {
            const aVal = new Date(a.timestamp).getTime();
            const bVal = new Date(b.timestamp).getTime();
            return this.sortDirection === 'asc' ? aVal - bVal : bVal - aVal;
        });

        // Pagination
        const startIndex = (this.currentPage - 1) * this.itemsPerPage;
        const endIndex = startIndex + this.itemsPerPage;
        return filtered.slice(startIndex, endIndex);
    }

    get totalPages() {
        let filtered = [...this.logs];

        if (this.selectedTab === 'students') {
            filtered = filtered.filter(log => log.userType === 'Student');
        } else if (this.selectedTab === 'visitors') {
            filtered = filtered.filter(log => log.userType === 'Visitor');
        }

        if (this.searchQuery) {
            const query = this.searchQuery.toLowerCase();
            filtered = filtered.filter(log => 
                log.name.toLowerCase().includes(query) ||
                (log.studentId && log.studentId.includes(query)) ||
                (log.aadharId && log.aadharId.includes(query))
            );
        }

        return Math.ceil(filtered.length / this.itemsPerPage);
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    handleTabChange(event) {
        this.selectedTab = event.currentTarget.dataset.tab;
        this.currentPage = 1;
    }

    handleSearch(event) {
        this.searchQuery = event.target.value;
        this.currentPage = 1;
    }

    handleTimeFilterChange(event) {
        this.selectedTimeFilter = event.currentTarget.dataset.filter;
        this.currentPage = 1;
    }

    handleDateChange(event) {
        this.selectedDate = event.target.value;
        this.currentPage = 1;
    }

    handleDatePickerClick(event) {
        // The lightning-input overlay will handle the click
        // This method is kept for potential future use
    }

    handleDatePickerKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            const dateInput = this.template.querySelector('.date-picker-input');
            if (dateInput) {
                dateInput.focus();
            }
        }
    }

    handleSort(event) {
        const column = event.currentTarget.dataset.column;
        if (this.sortColumn === column) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortColumn = column;
            this.sortDirection = 'desc';
        }
    }

    handleSortKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSort(event);
        }
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

    handleExport() {
        // Export functionality
    }

    handleViewAll() {
        // View all functionality
    }
}