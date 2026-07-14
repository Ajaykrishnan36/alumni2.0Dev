import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CASE_OBJECT from '@salesforce/schema/Case';
import STATUS_FIELD from '@salesforce/schema/Case.Status';
import getKpis from '@salesforce/apex/KenServiceRequestCommandCenterController.getKpis';
import getQueue from '@salesforce/apex/KenServiceRequestCommandCenterController.getQueue';
import getCaseDetail from '@salesforce/apex/KenServiceRequestCommandCenterController.getCaseDetail';
import getAdminOverview from '@salesforce/apex/KenServiceRequestCommandCenterController.getAdminOverview';
import getCaseRecordTypes from '@salesforce/apex/KenServiceRequestCommandCenterController.getCaseRecordTypes';
import assignToMe from '@salesforce/apex/KenServiceRequestCommandCenterController.assignToMe';
import solveCase from '@salesforce/apex/KenServiceRequestCommandCenterController.solveCase';
import needInfo from '@salesforce/apex/KenServiceRequestCommandCenterController.needInfo';
import changeCaseStatus from '@salesforce/apex/KenServiceRequestCommandCenterController.changeCaseStatus';
import saveResolution from '@salesforce/apex/KenServiceRequestCommandCenterController.saveResolution';

export default class KenServiceRequestCommandCenter extends NavigationMixin(LightningElement) {
    @track kpis = { openRequests: 0, slaRisk: 0, highPriority: 0, solved: 0 };
    @track rows = [];
    @track selectedCaseId = null;
    @track detail = null;
    @track activeTab = 'queue';
    @track adminOverview = { queueWorkload: [], solveNext: [] };
    @track recordTypeOptions = [];
    @track showRecordTypePicker = false;

    // Statuses considered "solved" for the SOLVED KPI / visual styling.
    SOLVED_STATUSES = ['Closed', 'Fulfilled', 'Resolved'];

    // Display order for the status-step buttons. Any picklist value not in this
    // list appears AFTER the listed ones, in the order Salesforce returns it.
    STATUS_DISPLAY_ORDER = ['New', 'In Progress', 'Waiting for Student', 'Response Received', 'On Hold', 'Escalated', 'Merged', 'Closed'];

    // Status steps are loaded dynamically from the Case.Status picklist
    // (see @wire below). No hardcoded list — admins manage the steps by
    // editing the picklist + business process in Setup.
    @track picklistStatusValues = [];
    @track defaultCaseRecordTypeId = null;

    @track detailTab = 'details';   // details | activity | related
    @track resolutionNote = '';
    @track isDetailOpen = false;
    @track isLoading = false;

    statusFilter = 'All';
    priorityFilter = 'All';
    slaFilter = 'All';
    quickChip = '';
    searchKey = '';

    wiredKpisResult;
    wiredQueueResult;
    wiredOverviewResult;

    statusOptions = [
        { label: 'All Statuses', value: 'All' },
        { label: 'New', value: 'New' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'Pending', value: 'Pending' },
        { label: 'Closed', value: 'Closed' }
    ];

    priorityOptions = [
        { label: 'All Priorities', value: 'All' },
        { label: 'Critical', value: 'Critical' },
        { label: 'High', value: 'High' },
        { label: 'Medium', value: 'Medium' },
        { label: 'Low', value: 'Low' }
    ];

    slaOptions = [
        { label: 'All SLA', value: 'All' },
        { label: 'Healthy', value: 'Healthy' },
        { label: 'At Risk', value: 'At Risk' },
        { label: 'Breached', value: 'Breached' }
    ];

    // Fall-back record-type Id when no case is selected yet. Used to pre-load
    // the picklist before the user opens a case detail.
    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    wireObjectInfo({ data }) {
        if (data) {
            this.defaultCaseRecordTypeId = data.defaultRecordTypeId || '012000000000000AAA';
        }
    }

    // Use the selected case's actual RecordTypeId when available so the
    // status-step buttons match THAT case's business process. Fall back to
    // the default record type before any case is opened.
    get statusPicklistRecordTypeId() {
        if (this.detail && this.detail.recordTypeId) {
            return this.detail.recordTypeId;
        }
        return this.defaultCaseRecordTypeId;
    }

    // Live-load the Case.Status picklist values for the selected case's
    // record type. The status-step buttons render from this list.
    @wire(getPicklistValues, {
        recordTypeId: '$statusPicklistRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wireStatusPicklist({ data }) {
        if (data && data.values) {
            this.picklistStatusValues = data.values.map((v) => v.value);
        }
    }

    @wire(getKpis)
    wireKpis(result) {
        this.wiredKpisResult = result;
        if (result.data) this.kpis = result.data;
    }

    @wire(getQueue, {
        statusFilter: '$statusFilter',
        priorityFilter: '$priorityFilter',
        slaFilter: '$slaFilter',
        quickChip: '$quickChip',
        searchKey: '$searchKey'
    })
    wireQueue(result) {
        this.wiredQueueResult = result;
        if (result.data) {
            this.rows = result.data.map((r) => {
                const isSolved = this.SOLVED_STATUSES.includes(r.status);
                return {
                    ...r,
                    statusClass: this._statusClass(r.status),
                    priorityClass: this._priorityClass(r.priority),
                    slaClass: this._slaClass(r.slaStatus),
                    isSolved
                };
            });
        }
    }

    @wire(getCaseRecordTypes)
    wireRecordTypes({ data }) {
        if (data) this.recordTypeOptions = data;
    }

    @wire(getAdminOverview)
    wireAdminOverview(result) {
        this.wiredOverviewResult = result;
        if (result.data) {
            const queueWorkload = (result.data.queueWorkload || []).map((w) => ({
                ...w,
                showSlaRisk: (w.slaRiskCount || 0) > 0
            }));
            const solveNext = (result.data.solveNext || []).map((t) => ({
                ...t,
                priorityClass: this._priorityClass(t.priority),
                slaClass: this._slaClass(t.slaStatus)
            }));
            this.adminOverview = { queueWorkload, solveNext };
        }
    }

    get totalRows() {
        return this.rows.length;
    }

    get isEmpty() {
        return this.rows.length === 0;
    }

    get queueIsActive() {
        return this.activeTab === 'queue';
    }

    get overviewIsActive() {
        return this.activeTab === 'overview';
    }

    get hasSolveNext() {
        return (this.adminOverview.solveNext || []).length > 0;
    }

    get hasQueueWorkload() {
        return (this.adminOverview.queueWorkload || []).length > 0;
    }

    get statusSteps() {
        const currentStatus = this.detail ? this.detail.status : null;
        const order = this.STATUS_DISPLAY_ORDER;
        const sorted = [...(this.picklistStatusValues || [])].sort((a, b) => {
            const ai = order.indexOf(a);
            const bi = order.indexOf(b);
            // values not in the explicit order go at the end, in their existing relative order
            const aRank = ai === -1 ? order.length : ai;
            const bRank = bi === -1 ? order.length : bi;
            return aRank - bRank;
        });
        return sorted.map((s) => ({
            value: s,
            label: s,
            cssClass: s === currentStatus ? 'status-step status-step-active' : 'status-step'
        }));
    }

    get queueTabClass() {
        return this.activeTab === 'queue' ? 'tab tab-active' : 'tab';
    }

    get overviewTabClass() {
        return this.activeTab === 'overview' ? 'tab tab-active' : 'tab';
    }

    get chipNewOnlyClass() { return this._chipClass('newOnly'); }
    get chipBreachedClass() { return this._chipClass('breachedSla'); }
    get chipCriticalClass() { return this._chipClass('critical'); }

    _chipClass(name) {
        return this.quickChip === name ? 'chip chip-active' : 'chip';
    }

    _statusClass(status) {
        const map = {
            'New': 'badge badge-new',
            'In Progress': 'badge badge-progress',
            'Waiting for Student': 'badge badge-pending',
            'Response Received': 'badge badge-pending',
            'On Hold': 'badge badge-pending',
            'Escalated': 'badge badge-pending',
            'Closed': 'badge badge-closed',
            'Merged': 'badge badge-closed',
            'Fulfilled': 'badge badge-fulfilled',
            'Resolved': 'badge badge-fulfilled'
        };
        return map[status] || 'badge';
    }

    _priorityClass(priority) {
        const map = {
            'Critical': 'badge badge-critical',
            'High': 'badge badge-high',
            'Medium': 'badge badge-medium',
            'Low': 'badge badge-low'
        };
        return map[priority] || 'badge';
    }

    _slaClass(sla) {
        const map = {
            'Healthy': 'sla sla-healthy',
            'At Risk': 'sla sla-risk',
            'Breached': 'sla sla-breached'
        };
        return map[sla] || 'sla';
    }

    handleStatusChange(e) { this.statusFilter = e.detail.value; }
    handlePriorityChange(e) { this.priorityFilter = e.detail.value; }
    handleSlaChange(e) { this.slaFilter = e.detail.value; }
    handleSearchChange(e) { this.searchKey = e.target.value; }

    handleChipNewOnly() { this.quickChip = this.quickChip === 'newOnly' ? '' : 'newOnly'; }
    handleChipBreached() { this.quickChip = this.quickChip === 'breachedSla' ? '' : 'breachedSla'; }
    handleChipCritical() { this.quickChip = this.quickChip === 'critical' ? '' : 'critical'; }
    handleChipReset() {
        this.statusFilter = 'All';
        this.priorityFilter = 'All';
        this.slaFilter = 'All';
        this.quickChip = '';
        this.searchKey = '';
    }

    handleTabClick(e) {
        this.activeTab = e.currentTarget.dataset.tab;
    }

    async handleRowClick(e) {
        const caseId = e.currentTarget.dataset.id;
        this.selectedCaseId = caseId;
        this.isDetailOpen = true;
        this.detailTab = 'details';
        try {
            this.detail = await getCaseDetail({ caseId });
            this.resolutionNote = (this.detail && this.detail.resolutionNote) || '';
        } catch (err) {
            this._toast('Error', 'Could not load case detail.', 'error');
        }
    }

    handleCloseDetail() {
        this.isDetailOpen = false;
        this.selectedCaseId = null;
        this.detail = null;
    }

    handleResolutionInput(e) {
        this.resolutionNote = e.target.value;
    }

    async handleSolve(e) {
        e.stopPropagation();
        const caseId = e.currentTarget.dataset.id || this.selectedCaseId;
        if (!caseId) return;
        this.isLoading = true;
        try {
            await solveCase({ caseId, resolutionNote: this.resolutionNote });
            this._toast('Solved', 'Case marked as Closed.', 'success');
            await this._refreshAll();
            this.handleCloseDetail();
        } catch (err) {
            this._toast('Error', this._errMsg(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Opens the Case record page in the current org. Triggered by the "View"
    // button in each row's Action cell.
    handleView(e) {
        e.stopPropagation();
        const caseId = e.currentTarget.dataset.id;
        if (!caseId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: caseId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    async handleAssignToMe() {
        if (!this.selectedCaseId) return;
        this.isLoading = true;
        try {
            await assignToMe({ caseId: this.selectedCaseId });
            this._toast('Assigned', 'Case assigned to you.', 'success');
            await this._refreshAll();
            this.detail = await getCaseDetail({ caseId: this.selectedCaseId });
        } catch (err) {
            this._toast('Error', this._errMsg(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleNeedInfo() {
        if (!this.selectedCaseId) return;
        this.isLoading = true;
        try {
            await needInfo({ caseId: this.selectedCaseId, note: this.resolutionNote });
            this._toast('Status updated', 'Case set to Waiting for Student.', 'success');
            await this._refreshAll();
            this.detail = await getCaseDetail({ caseId: this.selectedCaseId });
        } catch (err) {
            this._toast('Error', this._errMsg(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleNewRequest() {
        // Show our own record-type picker so the user always sees the choice,
        // regardless of profile "Skip Record Type Selection" settings.
        if (!this.recordTypeOptions || this.recordTypeOptions.length === 0) {
            // No record types loaded yet (or user only has Master) — fall back to native nav.
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Case', actionName: 'new' }
            });
            return;
        }
        if (this.recordTypeOptions.length === 1) {
            this._navigateNewCase(this.recordTypeOptions[0].recordTypeId);
            return;
        }
        this.showRecordTypePicker = true;
    }

    handlePickRecordType(e) {
        const rtId = e.currentTarget.dataset.id;
        this.showRecordTypePicker = false;
        this._navigateNewCase(rtId);
    }

    handleClosePicker() {
        this.showRecordTypePicker = false;
    }

    _navigateNewCase(recordTypeId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Case', actionName: 'new' },
            state: { recordTypeId, nooverride: '1' }
        });
    }

    async handleSaveResolution() {
        if (!this.selectedCaseId) return;
        this.isLoading = true;
        try {
            await saveResolution({ caseId: this.selectedCaseId, resolutionNote: this.resolutionNote });
            this._toast('Saved', 'Resolution note saved.', 'success');
            this.detail = await getCaseDetail({ caseId: this.selectedCaseId });
        } catch (err) {
            this._toast('Error', this._errMsg(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleEditCase() {
        if (!this.selectedCaseId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedCaseId,
                objectApiName: 'Case',
                actionName: 'edit'
            }
        });
    }

    handleDetailTabClick(e) {
        this.detailTab = e.currentTarget.dataset.tab;
    }

    get isDetailsTab() { return this.detailTab === 'details'; }
    get isActivityTab() { return this.detailTab === 'activity'; }
    get isRelatedTab() { return this.detailTab === 'related'; }

    get detailsTabClass() { return this.detailTab === 'details' ? 'detail-tab detail-tab-active' : 'detail-tab'; }
    get activityTabClass() { return this.detailTab === 'activity' ? 'detail-tab detail-tab-active' : 'detail-tab'; }
    get relatedTabClass() { return this.detailTab === 'related' ? 'detail-tab detail-tab-active' : 'detail-tab'; }

    get hasResponses() {
        return this.detail && (this.detail.responses || []).length > 0;
    }

    async handleStatusStepClick(e) {
        e.stopPropagation();
        const newStatus = e.currentTarget.dataset.status;
        if (!this.selectedCaseId || !newStatus) return;
        if (this.detail && this.detail.status === newStatus) return; // no-op
        this.isLoading = true;
        try {
            await changeCaseStatus({ caseId: this.selectedCaseId, status: newStatus });
            this._toast('Status updated', `Case is now ${newStatus}.`, 'success');
            await this._refreshAll();
            this.detail = await getCaseDetail({ caseId: this.selectedCaseId });
        } catch (err) {
            this._toast('Error', this._errMsg(err), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async _refreshAll() {
        if (this.wiredKpisResult) await refreshApex(this.wiredKpisResult);
        if (this.wiredQueueResult) await refreshApex(this.wiredQueueResult);
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _errMsg(err) {
        return err && err.body && err.body.message ? err.body.message : 'Operation failed.';
    }

    _stop(e) {
        e.stopPropagation();
    }
}