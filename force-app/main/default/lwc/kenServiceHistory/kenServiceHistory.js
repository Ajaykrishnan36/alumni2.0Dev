import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getUserHistory from '@salesforce/apex/KenServiceSupportController.getUserHistory';
import submitCaseFeedback from '@salesforce/apex/KenServiceSupportController.submitCaseFeedback';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';

const TAB_SERVICE   = 'service';
const TAB_SUPPORT   = 'support';
const TAB_GATE_PASS = 'gatepass';

export default class KenServiceHistory extends NavigationMixin(LightningElement) {
    _serviceHistory  = [];
    _supportHistory  = [];
    _gatePassHistory = [];
    _selfFetch = true; // default: standalone fetch unless parent overrides
    constituentRoleId;

    @track processedServiceHistory  = [];
    @track processedSupportHistory  = [];
    @track processedGatePassHistory = [];
    @track showFeedbackModal = false;
    @track showSuccessDialog = false;
    @track currentFeedbackCaseId = null;
    @track currentFeedbackCaseNumber = null;
    @track currentFeedbackTitle = null;
    @track selectedRating = 0;
    @track feedbackText = '';
    @track submittedFeedbackCases = new Set();
    @track searchTerm = '';
    @track showRatingError = false;

    @api activeTab = TAB_SERVICE;
    @api recordLimit;
    @api showViewAllButton = false;
    @api
    get selfFetch() {
        return this._selfFetch;
    }
    set selfFetch(value) {
        // accept boolean/string values; default remains true
        this._selfFetch = value === false || value === 'false' ? false : true;
    }
    @api detailPageUrlBase = '/service-support/ticket-detail';

    connectedCallback() {
        this.constituentRoleId = localStorage.getItem('ConstituentRoleId');
        if (this.selfFetch === true) {
            console.debug('[serviceHistory] self-fetching history data');
            this.loadHistory();
        } else {
            console.debug('[serviceHistory] waiting for parent-provided history data');
        }
         console.log('constituentRoleId *****', this.constituentRoleId );
        getColors().then(colors => {
            if (colors?.primary) {
                document.documentElement.style.setProperty('--primary-color', colors.primary);
            }
            if (colors?.secondary) {
                document.documentElement.style.setProperty('--secondary-color', colors.secondary);
            }
        }).catch(() => {
            console.log('Error getting colors');
        });
    }

    loadHistory() {
        getUserHistory({constituentRoleId : this.constituentRoleId})
            .then(result => {
                this._serviceHistory  = result?.serviceHistory  || [];
                this._supportHistory  = result?.supportHistory  || [];
                this._gatePassHistory = result?.gatePassHistory || [];
                this.processHistoryData();
            })
            .catch(error => {
                console.error('History Error:', error);
                this._serviceHistory  = [];
                this._supportHistory  = [];
                this._gatePassHistory = [];
                this.processHistoryData();
            });
    }

    @api
    get serviceHistory() {
        return this._serviceHistory;
    }
    set serviceHistory(value) {
        this._serviceHistory = value || [];
        this.processHistoryData();
    }

    @api
    get supportHistory() {
        return this._supportHistory;
    }
    set supportHistory(value) {
        this._supportHistory = value || [];
        this.processHistoryData();
    }

    @api
    get gatePassHistory() {
        return this._gatePassHistory;
    }
    set gatePassHistory(value) {
        this._gatePassHistory = value || [];
        this.processHistoryData();
    }

    get serviceTabClass() {
        return `history-tab ${this.isServiceTabActive ? 'active' : ''}`;
    }
    
    get supportTabClass() {
        return `history-tab ${this.isSupportTabActive ? 'active' : ''}`;
    }

    get gatePassTabClass() {
        return `history-tab ${this.isGatePassTabActive ? 'active' : ''}`;
    }

    get numericLimit() {
        const n = Number(this.recordLimit);
        return Number.isFinite(n) && n > 0 ? n : null;
    }

    get historyContentClass() {
        return ['history-content', this.showViewAllButton ? null : 'no-view-all']
            .filter(Boolean)
            .join(' ');
    }

    get shouldShowBreadcrumb() {
        return this.selfFetch === true && !this.showViewAllButton;
    }

    get crumbs() {
        let lastLabel;
        if (this.activeTab === TAB_SERVICE)        lastLabel = 'Service Requests';
        else if (this.activeTab === TAB_GATE_PASS) lastLabel = 'Gate Pass Requests';
        else                                       lastLabel = 'Support Tickets';
        return [
            { label: 'Home', url: '' },
            { label: 'Service & Support', url: '/service-support' },
            { label: lastLabel }
        ];
    }

    get limitedServiceHistory() {
        if (this.numericLimit) {
            return this.processedServiceHistory.slice(0, this.numericLimit);
        }
        return this.processedServiceHistory;
    }

    get limitedSupportHistory() {
        if (this.numericLimit) {
            return this.processedSupportHistory.slice(0, this.numericLimit);
        }
        return this.processedSupportHistory;
    }

    get limitedGatePassHistory() {
        if (this.numericLimit) {
            return this.processedGatePassHistory.slice(0, this.numericLimit);
        }
        return this.processedGatePassHistory;
    }

    get filteredServiceHistory() {
        return this.filterBySearchTerm(this.limitedServiceHistory);
    }

    get filteredSupportHistory() {
        return this.filterBySearchTerm(this.limitedSupportHistory);
    }

    get filteredGatePassHistory() {
        return this.filterBySearchTerm(this.limitedGatePassHistory);
    }

    filterBySearchTerm(historyList) {
        if (!this.searchTerm || this.searchTerm.trim() === '') {
            return historyList;
        }

        const searchLower = this.searchTerm.toLowerCase().trim();
        return historyList.filter(item => {
            const id = (item.id || '').toLowerCase();
            const title = (item.title || '').toLowerCase();
            const description = (item.description || '').toLowerCase();
            const status = (item.status || '').toLowerCase();
            
            return id.includes(searchLower) || 
                   title.includes(searchLower) || 
                   description.includes(searchLower) || 
                   status.includes(searchLower);
        });
    }

    get shouldShowSearchBar() {
        // Show search bar when:
        // 1. There's no record limit (meaning we're showing all records)
        // 2. AND there are 3 or more items in the current tab
        if (this.numericLimit) {
            return false; // Don't show search bar when we're limiting results
        }
        let totalItems;
        if (this.activeTab === TAB_SERVICE)        totalItems = this.processedServiceHistory.length;
        else if (this.activeTab === TAB_GATE_PASS) totalItems = this.processedGatePassHistory.length;
        else                                       totalItems = this.processedSupportHistory.length;
        return totalItems >= 3;
    }

    get shouldShowViewAll() {
        // Only show when allowed and we actually have more than the limit
        if (!this.showViewAllButton) {
            return false;
        }
        if (this.numericLimit) {
            const hasMoreService  = this.processedServiceHistory.length  > this.numericLimit;
            const hasMoreSupport  = this.processedSupportHistory.length  > this.numericLimit;
            const hasMoreGatePass = this.processedGatePassHistory.length > this.numericLimit;
            return hasMoreService || hasMoreSupport || hasMoreGatePass;
        }
        return false; // Hide View All button when there's no limit (we're already viewing all)
    }

    processHistoryData() {
        if (this._serviceHistory && this._serviceHistory.length > 0) {
            this.processedServiceHistory = this._serviceHistory.map(item => {
                const statusClass = this.computeStatusClass(item.status);
                const isClosed = this.isStatusClosed(item.status);
                return {
                    ...item,
                    description: this.normalizeHistoryDescription(item.description),
                    statusClass: statusClass,
                    attachmentName: this.normalizeAttachmentName(item.attachmentName, item.attachment),
                    isClosed: isClosed || statusClass === 'status-closed',
                    hasFeedbackSubmitted: item.hasFeedbackSubmitted || this.submittedFeedbackCases.has(item.caseId),
                    ...this.getStatusDisplay(item.status, item.closedDate, item.rejectedDate, item.canceledDate)
                };
            });
        } else {
            this.processedServiceHistory = [];
        }

        if (this._supportHistory && this._supportHistory.length > 0) {
            this.processedSupportHistory = this._supportHistory.map(item => {
                const statusClass = this.computeStatusClass(item.status);
                const isClosed = this.isStatusClosed(item.status);
                return {
                    ...item,
                    statusClass: statusClass,
                    title: item.serviceOfferingName || item.title,
                    description: item.subject || item.title,
                    attachmentName: this.normalizeAttachmentName(item.attachmentName, item.attachment),
                    isClosed: isClosed || statusClass === 'status-closed',
                   hasFeedbackSubmitted: !!(item.hasFeedbackSubmitted || this.submittedFeedbackCases.has(item.caseId)),
                    ...this.getStatusDisplay(item.status, item.closedDate, item.rejectedDate, item.canceledDate)
                };
            });
        } else {
            this.processedSupportHistory = [];
        }

        if (this._gatePassHistory && this._gatePassHistory.length > 0) {
            this.processedGatePassHistory = this._gatePassHistory.map(item => {
                const statusClass = this.computeStatusClass(item.status);
                const isClosed = this.isStatusClosed(item.status);
                return {
                    ...item,
                    statusClass,
                    title: item.subject || item.title,
                    description: item.subject || item.title,
                    attachmentName: this.normalizeAttachmentName(item.attachmentName, item.attachment),
                    isClosed: isClosed || statusClass === 'status-closed',
                    hasFeedbackSubmitted: !!(item.hasFeedbackSubmitted || this.submittedFeedbackCases.has(item.caseId)),
                    ...this.getStatusDisplay(item.status, item.closedDate, item.rejectedDate, item.canceledDate)
                };
            });
        } else {
            this.processedGatePassHistory = [];
        }
    }

    get isServiceTabActive() {
        return this.activeTab === TAB_SERVICE;
    }

    get isSupportTabActive() {
        return this.activeTab === TAB_SUPPORT;
    }

    get isGatePassTabActive() {
        return this.activeTab === TAB_GATE_PASS;
    }

    get currentHistoryData() {
        if (this.activeTab === TAB_SERVICE)        return this.filteredServiceHistory;
        if (this.activeTab === TAB_GATE_PASS)      return this.filteredGatePassHistory;
        return this.filteredSupportHistory;
    }

    handleTabClick(event) {
        const selectedTab = event.currentTarget.dataset.tab;
        if (selectedTab !== this.activeTab) {
            console.debug('[serviceHistory] tab change', selectedTab);
            if (this.selfFetch) {
                // In standalone mode, switch locally
                this.activeTab = selectedTab;
            } else {
                const tabChangeEvent = new CustomEvent('tabchange', {
                    detail: selectedTab,
                    bubbles: true,
                    composed: true
                });
                this.dispatchEvent(tabChangeEvent);
            }
        }
    }

    handleViewAllClick() {
        console.debug('[serviceHistory] View All clicked');
        this.dispatchEvent(new CustomEvent('viewall', { bubbles: true, composed: true }));
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
    }

    computeStatusClass(status) {
        if (!status) {
            return 'status-default';
        }
        const statusLower = status.toLowerCase();
        if (statusLower.includes('cancel')) {
            return 'status-canceled';
        }
        if (statusLower.includes('closed')) {
            return 'status-closed';
        }
        if (statusLower.includes('review') || statusLower.includes('pending')) {
            return 'status-review';
        }
        if (statusLower.includes('rejected')) {
            return 'status-rejected';
        }
        if (statusLower.includes('resolved')) {
            return 'status-resolved';
        }
        return 'status-default';
    }

    handleAttachmentClick(event) {
        event.stopPropagation();
        const fileUrl = event.currentTarget.dataset.url || event.currentTarget.dataset.filename;
        const fileName = event.currentTarget.dataset.name || event.currentTarget.dataset.filename;
        if (!fileUrl) {
            return;
        }

        if (this.selfFetch) {
            window.open(fileUrl, '_blank');
        } else {
            const fileEvent = new CustomEvent('filedownload', {
                detail: { fileUrl, fileName },
                bubbles: true,
                composed: true
            });
            this.dispatchEvent(fileEvent);
        }
    }

    normalizeAttachmentName(name, url) {
        if (name) {
            return name;
        }
        if (!url) {
            return '';
        }
        try {
            const parts = url.split('/');
            return parts[parts.length - 1];
        } catch (e) {
            return '';
        }
    }

    normalizeHistoryDescription(description) {
        const normalizedDescription = (description || '').trim();
        if (normalizedDescription.toLowerCase() === 'submitted from portal service request detail view') {
            return null;
        }
        return normalizedDescription || null;
    }

    getStatusDisplay(status, closedDate, rejectedDate, canceledDate) {
        const statusLower = (status || '').toLowerCase();
        if (statusLower.includes('rejected') && rejectedDate) {
            return {
                statusLabel: 'Rejected on',
                statusDate: this.formatDate(rejectedDate)
            };
        }
        if (statusLower.includes('closed') && closedDate) {
            return {
                statusLabel: 'Closed on',
                statusDate: this.formatDate(closedDate)
            };
        }
        if (statusLower.includes('cancel') && canceledDate) {
            return {
                statusLabel: 'Canceled on',
                statusDate: this.formatDate(canceledDate)
            };
        }
        return {
            statusLabel: null,
            statusDate: null
        };
    }

    formatDate(dateValue) {
        if (!dateValue) {
            return null;
        }
        try {
            const dateObj = new Date(dateValue);
            const day = String(dateObj.getUTCDate()).padStart(2, '0');
            const month = String(dateObj.getUTCMonth() + 1).padStart(2, '0');
            const year = String(dateObj.getUTCFullYear()).slice(-2);
            return `${day}-${month}-${year}`;
        } catch (e) {
            return null;
        }
    }

    isStatusClosed(status) {
        if (!status) {
            return false;
        }
        const s = status.toLowerCase();
        return s.includes('closed') || s.includes('resolved');
    }

    handleItemClick(event) {
        const detail = {
            caseId: event.currentTarget.dataset.caseId
        };

        if (!detail.caseId) {
            return;
        }

        if (this.selfFetch) {
            console.debug('[serviceHistory] navigate to detail', detail.caseId);
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: `${this.detailPageUrlBase}?caseId=${detail.caseId}`
                }
            });
        } else {
            console.debug('[serviceHistory] dispatch ticketselect', detail.caseId);
            const selectEvent = new CustomEvent('ticketselect', {
                detail,
                bubbles: true,
                composed: true
            });
            this.dispatchEvent(selectEvent);
        }
    }

    handleLeaveFeedback(event) {
        event.stopPropagation();
        const caseId = event.currentTarget.dataset.caseId;
        const caseNumber = event.currentTarget.dataset.caseNumber;
        const title = event.currentTarget.dataset.title;
        
        if (!caseId) {
            return;
        }

        // Show feedback modal instead of navigating
        this.currentFeedbackCaseId = caseId;
        this.currentFeedbackCaseNumber = caseNumber;
        this.currentFeedbackTitle = title;
        this.selectedRating = 0;
        this.feedbackText = '';
        this.showFeedbackModal = true;
    }

    handleStarClick(event) {
        const rating = parseInt(event.currentTarget.dataset.rating, 10);
        this.selectedRating = rating;
        this.showRatingError = false;
    }

    handleFeedbackTextChange(event) {
        this.feedbackText = event.target.value;
    }

    handleCancelFeedback() {
        this.showFeedbackModal = false;
        this.currentFeedbackCaseId = null;
        this.currentFeedbackCaseNumber = null;
        this.currentFeedbackTitle = null;
        this.selectedRating = 0;
        this.feedbackText = '';
        this.showRatingError = false;
    }

    handleSubmitFeedback() {
        if (!this.currentFeedbackCaseId) {
            return;
        }
        if (!this.selectedRating || this.selectedRating < 1) {
            this.showRatingError = true;
            return;
        }
        this.showRatingError = false;

        const caseId = this.currentFeedbackCaseId;
        const rating = String(this.selectedRating); // picklist expects string value
        const feedback = this.feedbackText || '';

        submitCaseFeedback({ caseId, rating, feedback })
            .then(() => {
                this.submittedFeedbackCases = new Set([...this.submittedFeedbackCases, caseId]);

                this.processHistoryData();

                this.showFeedbackModal = false;
                this.currentFeedbackCaseId = null;
                this.currentFeedbackCaseNumber = null;
                this.currentFeedbackTitle = null;
                this.selectedRating = 0;
                this.feedbackText = '';

                // success dialog
                this.showSuccessDialog = true;
                setTimeout(() => {
                    this.showSuccessDialog = false;
                }, 3000);

                this.loadHistory();
            })
            .catch(error => {
                console.error('Feedback submit error:', error);
            });
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCancelFeedback();
        }
    }

    handleModalContainerClick(event) {
        event.stopPropagation();
    }

    closeSuccessDialog() {
        this.showSuccessDialog = false;
    }

    get starRatings() {
        return [1, 2, 3, 4, 5].map(rating => ({
            value: rating,
            isFilled: rating <= this.selectedRating
        }));
    }

    get ratingBadge() {
        if (this.selectedRating === 0) {
            return null;
        }
        const badges = {
            1: { text: 'Poor', class: 'rating-badge-poor' },
            2: { text: 'Fair', class: 'rating-badge-fair' },
            3: { text: 'Good', class: 'rating-badge-good' },
            4: { text: 'Very Good', class: 'rating-badge-very-good' },
            5: { text: 'Excellent', class: 'rating-badge-excellent' }
        };
        return badges[this.selectedRating] || null;
    }
}