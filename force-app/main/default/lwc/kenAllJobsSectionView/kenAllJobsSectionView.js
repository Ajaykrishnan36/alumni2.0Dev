import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const APPROVED_ROWS = [
    { id: 'app-1', jobId: '#HF384E2389DUE', designation: 'UX/UI intern', applicants: 120, status: 'Ongoing', statusType: 'ongoing', openDate: '23-03-2024', closeDate: '30-03-2024' },
    { id: 'app-2', jobId: '#HF384E2389FE3', designation: 'UX/UI intern', applicants: 38, status: 'Upcoming', statusType: 'upcoming', openDate: '24-03-2024', closeDate: '01-04-2024' },
    { id: 'app-3', jobId: '#HF384E2389HWO', designation: 'Visual designer', applicants: 58, status: 'Upcoming', statusType: 'upcoming', openDate: '25-03-2024', closeDate: '02-04-2024' },
    { id: 'app-4', jobId: '#HF384E2389DH7', designation: 'UI designer', applicants: 27, status: 'Upcoming', statusType: 'upcoming', openDate: '26-03-2024', closeDate: '03-04-2024' },
    { id: 'app-5', jobId: '#HF384E2389BE7', designation: 'UX/UI designer', applicants: 93, status: 'Upcoming', statusType: 'upcoming', openDate: '27-03-2024', closeDate: '04-04-2024' }
];

const IN_REVIEW_ROWS = [
    { id: 'rev-1', jobId: '#HF384E2389DUE', designation: 'UX/UI intern', openDate: '23-03-2024', closeDate: '30-03-2024' },
    { id: 'rev-2', jobId: '#HF384E2389FE3', designation: 'UX/UI intern', openDate: '24-03-2024', closeDate: '01-04-2024' },
    { id: 'rev-3', jobId: '#HF384E2389HWO', designation: 'Visual designer', openDate: '25-03-2024', closeDate: '02-04-2024' },
    { id: 'rev-4', jobId: '#HF384E2389DH7', designation: 'UI designer', openDate: '26-03-2024', closeDate: '03-04-2024' },
    { id: 'rev-5', jobId: '#HF384E2389BE7', designation: 'UX/UI designer', openDate: '27-03-2024', closeDate: '04-04-2024' }
];

const ARCHIVE_ROWS = [
    { id: 'arc-1', jobId: '#HF384E2389DUE', designation: 'UX/UI intern', applicants: 120, status: 'Completed', statusType: 'completed', openDate: '23-03-2024', closeDate: '30-03-2024' },
    { id: 'arc-2', jobId: '#HF384E2389FE3', designation: 'UX/UI intern', applicants: 38, status: 'Inactive', statusType: 'inactive', openDate: '24-03-2024', closeDate: '01-04-2024' },
    { id: 'arc-3', jobId: '#HF384E2389HWO', designation: 'Visual designer', applicants: 58, status: 'Rejected', statusType: 'rejected', openDate: '25-03-2024', closeDate: '02-04-2024' },
    { id: 'arc-4', jobId: '#HF384E2389DH7', designation: 'UI designer', applicants: 27, status: 'Completed', statusType: 'completed', openDate: '26-03-2024', closeDate: '03-04-2024' },
    { id: 'arc-5', jobId: '#HF384E2389BE7', designation: 'UX/UI designer', applicants: 93, status: 'Completed', statusType: 'completed', openDate: '27-03-2024', closeDate: '04-04-2024' }
];

export default class KenAllJobsSectionView extends NavigationMixin(LightningElement) {
    @api manualJobFlowPageApiName;
    @api jobDetailPageApiName = 'job_detail__c';

    activeTab = 'approved';
    searchText = '';
    isPostJobModalOpen = false;

    archiveRows = ARCHIVE_ROWS.map((row) => ({ ...row, selected: false }));

    get approvedTabClass() {
        return `tab-btn${this.activeTab === 'approved' ? ' active' : ''}`;
    }

    get inReviewTabClass() {
        return `tab-btn${this.activeTab === 'inreview' ? ' active' : ''}`;
    }

    get archiveTabClass() {
        return `tab-btn${this.activeTab === 'archive' ? ' active' : ''}`;
    }

    get isApprovedTab() {
        return this.activeTab === 'approved';
    }

    get isInReviewTab() {
        return this.activeTab === 'inreview';
    }

    get isArchiveTab() {
        return this.activeTab === 'archive';
    }

    get filteredApprovedRows() {
        return this.decorateStatusRows(this.applySearch(APPROVED_ROWS));
    }

    get filteredInReviewRows() {
        return this.applySearch(IN_REVIEW_ROWS);
    }

    get filteredArchiveRows() {
        return this.decorateStatusRows(this.applySearch(this.archiveRows));
    }

    get allArchiveSelected() {
        const rows = this.filteredArchiveRows;
        return rows.length > 0 && rows.every((row) => row.selected);
    }

    handleTabChange(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab && tab !== this.activeTab) {
            this.activeTab = tab;
        }
    }

    handleSearch(event) {
        this.searchText = event.target.value || '';
    }

    handleArchiveSelectAll(event) {
        const checked = event.target.checked;
        const visibleIds = new Set(this.filteredArchiveRows.map((row) => row.id));

        this.archiveRows = this.archiveRows.map((row) =>
            visibleIds.has(row.id) ? { ...row, selected: checked } : row
        );
    }

    handleArchiveSelect(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.archiveRows = this.archiveRows.map((row) =>
            row.id === id ? { ...row, selected: checked } : row
        );
    }

    handlePostJob() {
        this.isPostJobModalOpen = true;
    }

    closePostJobModal() {
        this.isPostJobModalOpen = false;
    }

    handleCreateManually() {
        this.isPostJobModalOpen = false;
        const target = (this.manualJobFlowPageApiName || '').trim();
        if (!target) {
            return;
        }

        const isRoutePath = target.startsWith('/') || target.includes('-');
        if (isRoutePath) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: target.startsWith('/') ? target : `/${target}`
                }
            });
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: target }
        });
    }

    handleUploadJobDescription() {
        this.isPostJobModalOpen = false;
    }

    handleViewDetails(event) {
        const jobId = event.currentTarget.dataset.jobId;
        const pageName = (this.jobDetailPageApiName || '').trim();
        if (!pageName) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: pageName },
            state: { jobId }
        });
    }

    applySearch(rows) {
        const query = this.searchText.trim().toLowerCase();
        if (!query) {
            return rows;
        }

        return rows.filter((row) =>
            (row.jobId || '').toLowerCase().includes(query) ||
            (row.designation || '').toLowerCase().includes(query)
        );
    }

    decorateStatusRows(rows) {
        return rows.map((row) => ({
            ...row,
            statusClass: `status-pill ${row.statusType || ''}`
        }));
    }
}