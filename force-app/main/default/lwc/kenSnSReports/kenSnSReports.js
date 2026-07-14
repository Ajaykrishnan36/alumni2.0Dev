import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CHARTJS            from '@salesforce/resourceUrl/KenSnSChartJS';
import getReportData      from '@salesforce/apex/KenSnSReportsController.getReportData';
import getServiceOfferings from '@salesforce/apex/KenSnSReportsController.getServiceOfferings';

// ── Report definitions ────────────────────────────────────────────────────
const REPORTS = [
    { key: 'allCases',   label: 'All Cases',          reportLabel: 'All Cases Report',        icon: '≡', subtitle: 'All service and support cases'        },
    { key: 'category',   label: 'Service Offering',   reportLabel: 'Service Offering Report', icon: '⊞', subtitle: 'Cases grouped by service offering'   },
    { key: 'recordType', label: 'Record Type',         reportLabel: 'Record Type Report',      icon: '☰', subtitle: 'Cases grouped by record type'       },
    { key: 'status',     label: 'Status',              reportLabel: 'Status Report',           icon: '◑', subtitle: 'Cases grouped by status'            },
];

const DASHBOARD_KEYS = ['status', 'category', 'recordType'];
const REPORTS_KEYS   = ['allCases', 'category', 'recordType', 'status'];

const GROUP_BY_FIELD = {
    allCases:   null,
    category:   'serviceOffering',
    recordType: 'recordTypeName',
    status:     'status',
};

const BASE_COLS = [
    { label: 'Case Number',       fieldName: 'caseNumber',      type: 'text', initialWidth: 110, sortable: true },
    { label: 'Subject',      fieldName: 'subject',         type: 'text', initialWidth: 220, sortable: true },
    { label: 'Status',       fieldName: 'status',          type: 'text', initialWidth: 120, sortable: true },
    { label: 'Record Type',  fieldName: 'recordTypeName',  type: 'text', initialWidth: 150, sortable: true },
    { label: 'Service',      fieldName: 'serviceOffering', type: 'text', initialWidth: 200, sortable: true },
    { label: 'Priority',     fieldName: 'priority',        type: 'text', initialWidth: 90,  sortable: true },
    { label: 'Case Owner',        fieldName: 'ownerName',       type: 'text', initialWidth: 160, sortable: true },
    { label: 'Account',      fieldName: 'accountName',     type: 'text', initialWidth: 170, sortable: true },
    { label: 'Created',      fieldName: 'createdDate',     type: 'text', initialWidth: 120, sortable: true },
];

const KPI_ICON_MAP = {
    blue:   { iconName: 'utility:case',    iconBoxCss: 'hr-kpi-icon-box hr-icon-blue'   },
    green:  { iconName: 'utility:check',   iconBoxCss: 'hr-kpi-icon-box hr-icon-green'  },
    orange: { iconName: 'utility:clock',   iconBoxCss: 'hr-kpi-icon-box hr-icon-orange' },
    red:    { iconName: 'utility:warning', iconBoxCss: 'hr-kpi-icon-box hr-icon-red'    },
    purple: { iconName: 'utility:people',  iconBoxCss: 'hr-kpi-icon-box hr-icon-purple' },
};

export default class KenSnSReports extends LightningElement {

    // ── public API ────────────────────────────────────────────────────────
    @api reportGroup = 'all';   // 'dashboard' | 'reports' | 'all'
    @api reportView  = 'reports'; // 'dashboard' | 'reports'

    // ── state ─────────────────────────────────────────────────────────────
    @track activeReport  = 'status';
    @track isLoading     = true;
    @track isExporting   = false;
    @track errorMessage  = null;

    @track _allRows      = [];
    @track kpiItems      = [];
    @track currentPage   = 1;
    pageSize             = 15;
    @track tableSortField  = null;
    @track tableSortDir    = 'asc';

    @track searchKey      = '';
    @track activeFilters  = [];
    @track dashboardSections      = [];
    @track dashboardActiveSection = 'status';
    @track zoomCard        = null;

    @track dashboardRecordType  = '';
    @track dashboardStatus      = '';
    @track dashboardService     = '';
    @track dashboardDateRange   = 'all';
    @track serviceOfferingOptions = [{ label: 'All Services', value: '' }];

    @track isDrillDownOpen    = false;
    @track drillDownTitle     = '';
    @track _drillDownBaseRows = [];
    @track drillDownSearch    = '';
    @track drillDownPage      = 1;
    drillDownPageSize         = 15;

    _chartjsLoaded      = false;
    _chartjsReady       = false;
    _chartInstances     = [];
    _pendingChartRender = false;
    _filtersByReport    = {};

    @track isSidebarCollapsed = false;

    // ── lifecycle ─────────────────────────────────────────────────────────
    connectedCallback() {
        const list = this._activeReportsList;
        if (list.length > 0 && !list.find(r => r.key === this.activeReport)) {
            this.activeReport = list[0].key;
        }
        getServiceOfferings()
            .then(opts => {
                this.serviceOfferingOptions = (opts || []).map(o => ({ label: o.label, value: o.value }));
            })
            .catch(() => {});
        this._loadReport();
    }

    renderedCallback() {
        if (!this._chartjsLoaded) {
            this._chartjsLoaded = true;
            loadScript(this, CHARTJS)
                .then(() => {
                    this._chartjsReady = true;
                    // Chart.js just became ready — if data already loaded, render now
                    if (this._pendingChartRender && this.kpiItems && this.kpiItems.length > 0) {
                        this._pendingChartRender = false;
                        this._renderCharts(this.kpiItems);
                    }
                })
                .catch(() => {});
        }
        // Don't trigger chart render from renderedCallback when chartjs is already loaded.
        // Data-load callbacks handle it directly (see _triggerChartRender).
    }

    _triggerChartRender(kpis) {
        if (this._chartjsReady) {
            // Chart.js already loaded — defer 100ms so LWC has flushed DOM updates
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this._renderCharts(kpis), 100);
        } else {
            // Chart.js not yet loaded — mark pending; renderedCallback will pick it up
            this._pendingChartRender = true;
        }
    }

    // ── computed ──────────────────────────────────────────────────────────

    get _activeReportsList() {
        if (this.reportGroup === 'dashboard') return REPORTS.filter(r => DASHBOARD_KEYS.includes(r.key));
        if (this.reportGroup === 'reports')   return REPORTS.filter(r => REPORTS_KEYS.includes(r.key));
        return REPORTS;
    }

    get isDashboardView() { return this.reportView === 'dashboard'; }

    get sidebarClass() {
        return 'hr-sidebar' + (this.isSidebarCollapsed ? ' hr-sidebar-collapsed' : '');
    }

    get isZoomOpen()         { return this.zoomCard !== null; }
    get hasPrevPage()        { return this.currentPage > 1; }
    get hasNextPage()        { return this.currentPage < this.totalPages; }
    get prevPageDisabled()   { return this.currentPage <= 1; }
    get nextPageDisabled()   { return this.currentPage >= this.totalPages; }

    get totalPages() {
        return Math.max(1, Math.ceil(this._filteredRows.length / this.pageSize));
    }

    get recordTypeOptions() {
        return [
            { label: 'All Record Types', value: '' },
            { label: 'Service',          value: 'Service' },
            { label: 'Support',          value: 'Support' },
        ];
    }

    get statusOptions() {
        return [
            { label: 'All Status',   value: '' },
            { label: 'New',          value: 'New' },
            { label: 'In Progress',  value: 'In Progress' },
            { label: 'Resolved',     value: 'Resolved' },
            { label: 'Closed',       value: 'Closed' },
            { label: 'Canceled',     value: 'Canceled' },
            { label: 'Rejected',     value: 'Rejected' },
            { label: 'On Hold',      value: 'On Hold' },
        ];
    }

    get dateRangeOptions() {
        return [
            { label: 'All Time',    value: 'all' },
            { label: 'Last 30 Days',value: 'last30' },
            { label: 'Last 90 Days',value: 'last90' },
            { label: 'This Month',  value: 'thisMonth' },
            { label: 'Last Month',  value: 'lastMonth' },
            { label: 'This Year',   value: 'thisYear' },
        ];
    }

    get reportMenuItems() {
        return this._activeReportsList.map(r => ({
            key:      r.key,
            label:    this.isDashboardView ? r.label : (r.reportLabel || r.label),
            icon:     r.icon,
            cssClass: 'hr-nav-item' + (r.key === this.activeReport ? ' hr-nav-active' : ''),
        }));
    }

    get activeReportLabel() {
        const r = this._activeReportsList.find(x => x.key === this.activeReport);
        return r ? (this.isDashboardView ? r.label : (r.reportLabel || r.label)) : '';
    }

    get activeReportSubtitle() {
        const r = this._activeReportsList.find(x => x.key === this.activeReport);
        return r ? r.subtitle : '';
    }

    get tableColumns() {
        const groupField = GROUP_BY_FIELD[this.activeReport];
        let cols = [...BASE_COLS];
        if (groupField) {
            const idx = cols.findIndex(c => c.fieldName === groupField);
            if (idx > 0) cols = [cols[idx], ...cols.filter((_, i) => i !== idx)];
        }
        const sf = this.tableSortField;
        const sd = this.tableSortDir;
        return cols.map(col => ({
            ...col,
            isSortable:    col.sortable === true,
            thClass:       col.sortable ? 'hr-th hr-th-sortable' : 'hr-th',
            sortIcon:      sf === col.fieldName ? (sd === 'desc' ? '↓' : '↑') : '',
            sortIconClass: sf === col.fieldName ? 'hr-sort-icon hr-sort-icon-active' : 'hr-sort-icon',
        }));
    }

    get drillDownColumns() {
        return [
            { label: 'Case Number',      fieldName: 'caseNumber',  type: 'text', initialWidth: 110 },
            { label: 'Subject',     fieldName: 'subject',     type: 'text', initialWidth: 220 },
            { label: 'Status',      fieldName: 'status',      type: 'text', initialWidth: 120 },
            { label: 'Service',     fieldName: 'serviceOffering', type: 'text', initialWidth: 180 },
            { label: 'Case Owner',       fieldName: 'ownerName',   type: 'text', initialWidth: 160 },
            { label: 'Created',     fieldName: 'createdDate', type: 'text', initialWidth: 120 },
        ];
    }

    get _filteredRows() {
        const key = this.searchKey ? this.searchKey.trim().toLowerCase() : '';
        let rows = this._allRows;
        if (key) {
            rows = rows.filter(r =>
                (r.caseNumber     || '').toLowerCase().includes(key) ||
                (r.subject        || '').toLowerCase().includes(key) ||
                (r.ownerName      || '').toLowerCase().includes(key) ||
                (r.accountName    || '').toLowerCase().includes(key) ||
                (r.status         || '').toLowerCase().includes(key)
            );
        }
        this.activeFilters.forEach(f => {
            if (!f.applied || !f.field || !f.values.length) return;
            const vals = f.values.map(v => v.toLowerCase());
            rows = rows.filter(row => {
                const rv = String(row[f.field] == null ? '' : row[f.field]).toLowerCase();
                switch (f.operator) {
                    case 'equals':     return vals.some(v => rv === v);
                    case 'contains':   return vals.some(v => rv.includes(v));
                    case 'startsWith': return vals.some(v => rv.startsWith(v));
                    case 'notEquals':  return vals.every(v => rv !== v);
                    default:           return true;
                }
            });
        });
        return rows;
    }

    get tableRows() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this._filteredRows.slice(start, start + this.pageSize);
    }

    get hasRows() {
        return this._filteredRows && this._filteredRows.length > 0;
    }

    get pageInfo() {
        if (this.isLoading) return 'Loading…';
        const rows = this._filteredRows;
        if (!rows.length) return 'No records found';
        const groupField = GROUP_BY_FIELD[this.activeReport];
        if (!groupField) return rows.length + ' record' + (rows.length !== 1 ? 's' : '');
        const groups = new Set(rows.map(r => r[groupField])).size;
        return rows.length + ' record' + (rows.length !== 1 ? 's' : '') +
               ' in ' + groups + ' group' + (groups !== 1 ? 's' : '');
    }

    get flatGroupedRows() {
        const groupField = GROUP_BY_FIELD[this.activeReport];
        const cols = this.tableColumns;
        const rows = this._filteredRows;
        const sf   = this.tableSortField;
        const dir  = this.tableSortDir === 'asc' ? 1 : -1;
        if (!rows.length) return [];

        let sortedRows = [...rows];
        if (sf) {
            sortedRows.sort((a, b) => {
                const va = String(a[sf] == null ? '' : a[sf]).toLowerCase();
                const vb = String(b[sf] == null ? '' : b[sf]).toLowerCase();
                return va < vb ? -dir : va > vb ? dir : 0;
            });
        }

        // No grouping — flat rows for All Cases
        if (!groupField) {
            return sortedRows.map((row, ri) => ({
                id:       (row.id || ri) + '-flat',
                rowClass: 'hr-data-row',
                cells:    cols.map((col, ci) => ({
                    id:        ri + '-' + ci,
                    value:     String(row[col.fieldName] == null ? '' : row[col.fieldName]),
                    cellClass: 'hr-td',
                })),
            }));
        }

        // Grouped rows
        const groups = new Map();
        sortedRows.forEach(row => {
            const key = row[groupField] || '—';
            if (!groups.has(key)) groups.set(key, []);
            groups.get(key).push(row);
        });

        const groupDir = groupField === sf ? dir : 1;
        const groupKeys = [...groups.keys()].sort((a, b) => a.localeCompare(b) * groupDir);

        const result = [];
        groupKeys.forEach(key => {
            const gRows = groups.get(key);
            gRows.forEach((row, ri) => {
                const isFirst = ri === 0;
                result.push({
                    id:       (row.id || key) + '-' + ri,
                    rowClass: isFirst ? 'hr-data-row hr-group-first-row' : 'hr-data-row',
                    cells:    cols.map((col, ci) => {
                        let value;
                        let cellClass = 'hr-td';
                        if (col.fieldName === groupField) {
                            if (isFirst) {
                                value     = (row[col.fieldName] || '—') + ' (' + gRows.length + ')';
                                cellClass = 'hr-group-cell-first';
                            } else {
                                value     = '';
                                cellClass = 'hr-group-cell-rest';
                            }
                        } else {
                            value = String(row[col.fieldName] == null ? '' : row[col.fieldName]);
                        }
                        return { id: key + '-' + ri + '-' + ci, value, cellClass };
                    }),
                });
            });
        });

        return result;
    }

    get pageNumberItems() {
        const total = this.totalPages;
        const cur   = this.currentPage;
        const items = [];
        const addPage = (n) => items.push({ id: 'p'+n, num: n, label: String(n), css: 'hr-page-btn'+(n===cur?' hr-page-btn-active':''), isEllipsis: false, disabled: false });
        const addEll  = (u) => items.push({ id: 'e'+u, num: 0, label: '…', css: 'hr-page-btn hr-page-ellipsis', isEllipsis: true, disabled: true });
        if (total <= 7) {
            for (let i = 1; i <= total; i++) addPage(i);
        } else {
            addPage(1);
            if (cur > 4) addEll(1);
            const start = Math.max(2, cur - 1);
            const end   = Math.min(total - 1, cur + 1);
            for (let i = start; i <= end; i++) addPage(i);
            if (cur < total - 3) addEll(2);
            addPage(total);
        }
        return items;
    }

    get filterFieldOptions() {
        const seen = new Set();
        const opts = [{ label: '-- Select Field --', value: '' }];
        this.tableColumns.forEach(col => {
            if (!seen.has(col.fieldName)) {
                seen.add(col.fieldName);
                opts.push({ label: col.label, value: col.fieldName });
            }
        });
        return opts;
    }

    get operatorOptions() {
        return [
            { label: 'equals',      value: 'equals'     },
            { label: 'contains',    value: 'contains'   },
            { label: 'starts with', value: 'startsWith' },
            { label: 'not equals',  value: 'notEquals'  },
        ];
    }

    get activeFiltersView() {
        return this.activeFilters.map(f => ({
            ...f,
            valuesView:   f.values.map((v, i) => ({ val: v, idx: i, key: f.id + '-v-' + i })),
            applyVariant: f.applied ? 'success' : 'brand',
        }));
    }

    get hasActiveFilters()   { return this.activeFilters.length > 0; }

    get _drillDownFilteredRows() {
        if (!this.drillDownSearch) return this._drillDownBaseRows;
        const key = this.drillDownSearch.toLowerCase();
        return this._drillDownBaseRows.filter(r =>
            (r.caseNumber  || '').toLowerCase().includes(key) ||
            (r.subject     || '').toLowerCase().includes(key) ||
            (r.ownerName   || '').toLowerCase().includes(key)
        );
    }

    get drillDownPageRows()      { const s = (this.drillDownPage - 1) * this.drillDownPageSize; return this._drillDownFilteredRows.slice(s, s + this.drillDownPageSize); }
    get drillDownTotalCount()    { return this._drillDownFilteredRows.length; }
    get drillDownTotalPages()    { return Math.max(1, Math.ceil(this._drillDownFilteredRows.length / this.drillDownPageSize)); }
    get hasDrillDownRows()       { return this.drillDownPageRows.length > 0; }
    get drillDownPrevDisabled()  { return this.drillDownPage <= 1; }
    get drillDownNextDisabled()  { return this.drillDownPage >= this.drillDownTotalPages; }
    get drillDownPageInfo() {
        const rows = this._drillDownFilteredRows;
        if (!rows.length) return 'No records found';
        const s = (this.drillDownPage - 1) * this.drillDownPageSize + 1;
        const e = Math.min(this.drillDownPage * this.drillDownPageSize, rows.length);
        return 'Showing ' + s + ' – ' + e + ' of ' + rows.length + ' records';
    }

    // ── handlers ──────────────────────────────────────────────────────────

    handleReportSwitch(event) {
        const key = event.currentTarget.dataset.key;
        if (!key || key === this.activeReport) return;
        this._filtersByReport[this.activeReport] = this.activeFilters;
        this.activeReport   = key;
        this.tableSortField = null;
        this.tableSortDir   = 'asc';
        this.activeFilters  = this._filtersByReport[key] ? [...this._filtersByReport[key]] : [];
        this.searchKey      = '';
        this._loadReport();
    }

    handleColumnSort(event) {
        const f = event.currentTarget.dataset.field;
        if (!f) return;
        if (this.tableSortField === f) {
            this.tableSortDir = this.tableSortDir === 'asc' ? 'desc' : 'asc';
        } else {
            this.tableSortField = f;
            this.tableSortDir   = 'asc';
        }
    }

    handleSearchChange(event)  { this.searchKey = event.target.value; }
    handleSidebarToggle()      { this.isSidebarCollapsed = !this.isSidebarCollapsed; }
    handleRefresh()            { this._loadReport(); }
    handleDismissError()       { this.errorMessage = null; }
    handlePrevPage()           { if (this.hasPrevPage) this.currentPage--; }
    handleNextPage()           { if (this.hasNextPage) this.currentPage++; }
    stopProp(event)            { event.stopPropagation(); }

    handlePageClick(event) {
        const num = parseInt(event.currentTarget.dataset.page, 10);
        if (!num || num < 1 || num > this.totalPages || num === this.currentPage) return;
        this.currentPage = num;
    }

    handleDashboardFilterChange(event) {
        const field = event.currentTarget.dataset.field;
        if (field === 'recordType')  this.dashboardRecordType = event.detail.value || '';
        if (field === 'status')      this.dashboardStatus     = event.detail.value || '';
        if (field === 'service')     this.dashboardService    = event.detail.value || '';
        if (field === 'dateRange')   this.dashboardDateRange  = event.detail.value || 'all';
        this._loadReport();
    }

    handleDashboardFilterKeydown(event) {
        if (event.key === 'Enter') this.handleDashboardFilterChange(event);
    }

    handleClearDashboardFilters() {
        this.dashboardRecordType = '';
        this.dashboardStatus     = '';
        this.dashboardService    = '';
        this.dashboardDateRange  = 'all';
        this._loadReport();
    }

    handleDashboardSectionRefresh(event) {
        event.preventDefault();
        event.stopPropagation();
        const key = event.currentTarget.dataset.key;
        this._loadDashboardSection(key);
    }

    handleDashboardChartExpand(event) {
        event.preventDefault();
        event.stopPropagation();
        const reportKey = event.currentTarget.dataset.reportKey;
        const chartKey  = event.currentTarget.dataset.chartKey;
        const section   = this.dashboardSections.find(s => s.key === reportKey);
        const kpi       = section && section.kpiItems ? section.kpiItems.find(k => k.chartKey === chartKey) : null;
        if (!kpi) return;
        this.zoomCard = { ...kpi, sectionLabel: section.label };
        this._triggerChartRender([this.zoomCard]);
    }

    handleZoomClose(event) {
        if (event) { event.preventDefault(); event.stopPropagation(); }
        this.zoomCard = null;
        this._triggerChartRender(this.kpiItems);
    }

    handleAddFilter() {
        this.activeFilters = [...this.activeFilters, {
            id: 'f-' + (this.activeFilters.length + 1) + '-' + Math.floor(Math.random() * 9999),
            field: '', operator: 'equals', values: [], applied: false,
        }];
    }

    handleRemoveFilter(event) {
        const id = event.currentTarget.dataset.id;
        this.activeFilters = this.activeFilters.filter(f => f.id !== id);
    }

    handleFilterFieldChange(event) {
        const id = event.currentTarget.dataset.id;
        this.activeFilters = this.activeFilters.map(f =>
            f.id === id ? { ...f, field: event.detail.value, values: [], applied: false } : f
        );
    }

    handleFilterOperatorChange(event) {
        const id = event.currentTarget.dataset.id;
        this.activeFilters = this.activeFilters.map(f =>
            f.id === id ? { ...f, operator: event.detail.value, applied: false } : f
        );
    }

    handleTagKeydown(event) {
        if (event.key !== 'Enter' && event.key !== ',') return;
        event.preventDefault();
        const fid  = event.currentTarget.dataset.fid;
        const text = event.currentTarget.value.replace(/,\s*$/, '').trim();
        if (!text) return;
        this.activeFilters = this.activeFilters.map(f => {
            if (f.id !== fid) return f;
            if (f.values.includes(text)) return f;
            return { ...f, values: [...f.values, text], applied: false };
        });
        event.currentTarget.value = '';
    }

    handleRemoveTag(event) {
        const fid = event.currentTarget.dataset.fid;
        const vi  = parseInt(event.currentTarget.dataset.vidx, 10);
        this.activeFilters = this.activeFilters.map(f => {
            if (f.id !== fid) return f;
            const vals = [...f.values];
            vals.splice(vi, 1);
            return { ...f, values: vals, applied: false };
        });
    }

    handleApplyFilter(event) {
        const id = event.currentTarget.dataset.id;
        const inputEl = this.template.querySelector('.hr-tag-text[data-fid="' + id + '"]');
        if (inputEl && inputEl.value.trim()) {
            const tags = inputEl.value.split(',').map(t => t.trim()).filter(Boolean);
            this.activeFilters = this.activeFilters.map(f => {
                if (f.id !== id) return f;
                const merged = [...f.values, ...tags.filter(t => !f.values.includes(t))];
                return { ...f, values: merged };
            });
            inputEl.value = '';
        }
        this.activeFilters = this.activeFilters.map(f =>
            f.id === id ? { ...f, applied: true } : f
        );
        this.dispatchEvent(new ShowToastEvent({ title: 'Filter Applied', variant: 'success', mode: 'dismissable' }));
    }

    handleClearFilters() {
        this.activeFilters = [];
    }

    handleExport() {
        const exportRows = this._filteredRows;
        if (!exportRows.length) { this.errorMessage = 'No data to export.'; return; }
        this.isExporting = true;
        try {
            const cols = this.tableColumns;
            const esc  = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
            let xml = '<?xml version="1.0" encoding="UTF-8"?><?mso-application progid="Excel.Sheet"?>'
                + '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
                + '<Styles><Style ss:ID="h"><Font ss:Bold="1" ss:Color="#FFFFFF"/><Interior ss:Color="#2563EB" ss:Pattern="Solid"/></Style></Styles>'
                + '<Worksheet ss:Name="' + esc(this.activeReportLabel) + '"><Table>';
            xml += '<Row>' + cols.map(c => '<Cell ss:StyleID="h"><Data ss:Type="String">' + esc(c.label) + '</Data></Cell>').join('') + '</Row>';
            exportRows.forEach(row => {
                xml += '<Row>' + cols.map(c => '<Cell><Data ss:Type="String">' + esc(row[c.fieldName]) + '</Data></Cell>').join('') + '</Row>';
            });
            xml += '</Table></Worksheet></Workbook>';
            const blob = new Blob([xml], { type: 'text/plain' });
            const url  = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href     = url;
            link.download = 'sns-report-' + this.activeReport + '.xls';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
        } catch (e) {
            this.errorMessage = 'Export failed: ' + e.message;
        } finally {
            this.isExporting = false;
        }
    }

    handleDrillDownClose()             { this.isDrillDownOpen = false; }
    handleDrillDownSearchChange(event) { this.drillDownSearch = event.target.value; this.drillDownPage = 1; }
    handleDrillDownPrev()              { if (this.drillDownPage > 1) this.drillDownPage--; }
    handleDrillDownNext()              { if (this.drillDownPage < this.drillDownTotalPages) this.drillDownPage++; }

    handleDrillDownExport() {
        if (!this._drillDownFilteredRows.length) return;
        const cols = this.drillDownColumns;
        const esc  = s => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
        let xml = '<?xml version="1.0" encoding="UTF-8"?><?mso-application progid="Excel.Sheet"?>'
            + '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
            + '<Styles><Style ss:ID="h"><Font ss:Bold="1" ss:Color="#FFFFFF"/><Interior ss:Color="#2563EB" ss:Pattern="Solid"/></Style></Styles>'
            + '<Worksheet ss:Name="Export"><Table>';
        xml += '<Row>' + cols.map(c => '<Cell ss:StyleID="h"><Data ss:Type="String">' + esc(c.label) + '</Data></Cell>').join('') + '</Row>';
        this._drillDownFilteredRows.forEach(row => {
            xml += '<Row>' + cols.map(c => '<Cell><Data ss:Type="String">' + esc(row[c.fieldName]) + '</Data></Cell>').join('') + '</Row>';
        });
        xml += '</Table></Worksheet></Workbook>';
        const blob = new Blob([xml], { type: 'text/plain' });
        const url  = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url; link.download = 'sns-drilldown.xls';
        document.body.appendChild(link); link.click(); document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }

    // ── Chart click → drill-down ──────────────────────────────────────────

    _handleChartClick(kpi, segmentLabel) {
        if (!segmentLabel || segmentLabel === 'No Data') return;
        const groupField = GROUP_BY_FIELD[this.activeReport];
        const rows = groupField
            ? this._allRows.filter(r => String(r[groupField] || '').toLowerCase() === segmentLabel.toLowerCase())
            : this._allRows;
        this.drillDownTitle     = (kpi.label || this.activeReportLabel) + ' — ' + segmentLabel;
        this._drillDownBaseRows = rows;
        this.drillDownSearch    = '';
        this.drillDownPage      = 1;
        this.isDrillDownOpen    = true;
    }

    // ── private: data load ────────────────────────────────────────────────

    _loadReport() {
        if (this.isDashboardView) { this._loadDashboardSections(); return; }

        this.isLoading    = true;
        this.errorMessage = null;
        this.currentPage  = 1;
        this._destroyCharts();

        getReportData({
            reportType:       this.activeReport,
            statusFilter:     null,
            recordTypeFilter: null,
            dateRange:        'all',
            searchKey:        null,
            limitSize:        50000,
        })
        .then(res => {
            this._allRows = res.rows || [];
            this.kpiItems = this._decorateKpis(res.kpis || [], this.activeReport);
            this.isLoading = false;
            this._triggerChartRender(this.kpiItems);
        })
        .catch(err => {
            this.errorMessage = err.body ? err.body.message : (err.message || 'Unknown error');
            this.isLoading = false;
        });
    }

    _loadDashboardSections() {
        this.isLoading         = true;
        this.errorMessage      = null;
        this.dashboardSections = [];
        this._destroyCharts();

        const reports = DASHBOARD_KEYS.map(k => REPORTS.find(r => r.key === k)).filter(Boolean);

        Promise.all(reports.map(report =>
            getReportData({
                reportType:       report.key,
                statusFilter:     this.dashboardStatus     || null,
                recordTypeFilter: this.dashboardRecordType || null,
                dateRange:        this.dashboardDateRange  || 'all',
                searchKey:        this.dashboardService    || null,
                limitSize:        50000,
            }).then(res => ({ report, res }))
        ))
        .then(results => {
            const sections = [];
            const flatKpis = [];
            const allRows  = [];
            results.forEach(({ report, res }) => {
                const kpis = this._decorateKpis(res.kpis || [], report.key);
                flatKpis.push(...kpis);
                allRows.push(...(res.rows || []));
                sections.push({
                    key:              report.key,
                    label:            report.label,
                    subtitle:         report.subtitle,
                    kpiItems:         kpis,
                    isSectionLoading: false,
                    sectionClass:     'hr-dashboard-section hr-dashboard-section-' + report.key,
                    rowCount:         (res.rows || []).length,
                });
            });
            this.dashboardSections = sections;
            this.kpiItems          = flatKpis;
            this._allRows          = allRows; // enable drill-down click-through
            this.isLoading         = false;
            this._triggerChartRender(flatKpis);
        })
        .catch(err => {
            this.errorMessage = err.body ? err.body.message : (err.message || 'Unknown error');
            this.isLoading = false;
        });
    }

    _loadDashboardSection(key) {
        const report = REPORTS.find(r => r.key === key);
        if (!report) return;

        this.dashboardSections = this.dashboardSections.map(s =>
            s.key === key ? { ...s, isSectionLoading: true } : s
        );

        getReportData({
            reportType:       key,
            statusFilter:     this.dashboardStatus     || null,
            recordTypeFilter: this.dashboardRecordType || null,
            dateRange:        this.dashboardDateRange  || 'all',
            searchKey:        this.dashboardService    || null,
            limitSize:        50000,
        })
        .then(res => {
            const kpis = this._decorateKpis(res.kpis || [], key);
            this.dashboardSections = this.dashboardSections.map(s =>
                s.key === key ? { ...s, kpiItems: kpis, isSectionLoading: false, rowCount: (res.rows || []).length } : s
            );
            this.kpiItems = this.dashboardSections.reduce((all, s) => all.concat(s.kpiItems || []), []);
            this._triggerChartRender(this.kpiItems);
        })
        .catch(err => {
            this.dashboardSections = this.dashboardSections.map(s =>
                s.key === key ? { ...s, isSectionLoading: false } : s
            );
            this.errorMessage = err.body ? err.body.message : (err.message || 'Unknown error');
        });
    }

    // ── private: KPI decoration ───────────────────────────────────────────

    _decorateKpis(kpis, reportKey) {
        return (kpis || []).map((k, index) => {
            const im      = KPI_ICON_MAP[k.color || 'blue'] || KPI_ICON_MAP.blue;
            const isDonut = k.chartType === 'donut';
            const isBar   = k.chartType === 'bar' || k.chartType === 'hbar';
            const isHbar  = k.chartType === 'hbar';
            const total   = isDonut ? (k.chartValues || []).reduce((a, v) => a + Number(v), 0) : 0;
            const barLegend = (isBar && (!isHbar || (k.chartLabels || []).length <= 10))
                ? (k.chartLabels || []).map((lbl, i) => ({
                    color:    (k.chartColors || [])[i] || k.dotColor || '#1B5FFF',
                    label:    lbl || '',
                    value:    String((k.chartValues || [])[i] != null ? (k.chartValues || [])[i] : ''),
                    dotStyle: 'background:' + ((k.chartColors || [])[i] || k.dotColor || '#1B5FFF'),
                })) : [];
            return {
                ...k,
                reportKey,
                chartKey:    reportKey + '-' + index,
                cardCss:     'hr-kpi-card',
                iconBoxCss:  im.iconBoxCss,
                iconName:    im.iconName,
                dotStyle:    'background:' + (k.dotColor || '#1B5FFF'),
                isDonut,
                hasLegend:    k.legend && k.legend.length > 0,
                hasBarLegend: isBar && barLegend.length > 0,
                barLegend,
                legend: (k.legend || []).map((lg, lgIdx) => ({
                    ...lg,
                    dotStyle: 'background:' + lg.color,
                    pct: (isDonut && total > 0)
                        ? ((Number((k.chartValues || [])[lgIdx] || 0) / total) * 100).toFixed(1) + '%'
                        : '',
                })),
            };
        });
    }

    // ── private: charts ───────────────────────────────────────────────────

    _destroyCharts() {
        this._chartInstances.forEach(c => { if (c) { try { c.destroy(); } catch (e) {} } });
        this._chartInstances = [];
    }

    _renderCharts(kpis) {
        if (typeof window.Chart === 'undefined') return;
        this._destroyCharts();
        // Build a map of chartKey → kpi for fast lookup
        const kpiMap = {};
        (kpis || []).forEach(k => { kpiMap[k.chartKey] = k; });
        // Query all canvases at once — more reliable than individual queries in LWC
        const canvases = this.template.querySelectorAll('.hr-chart-canvas');
        if (!canvases || canvases.length === 0) return;
        canvases.forEach(canvas => {
            const chartKey = canvas.dataset.chartKey;
            const kpi = kpiMap[chartKey];
            if (!kpi) return;
            const labels = kpi.chartLabels || [];
            const values = (kpi.chartValues || []).map(v => Number(v) || 0);
            const colors = kpi.chartColors || ['#2563EB'];
            if (!labels.length || values.every(v => v === 0)) {
                this._renderEmptyChart(canvas);
                return;
            }
            const isHbar  = kpi.chartType === 'hbar';
            const isDonut = kpi.chartType === 'donut';
            const type    = isDonut ? 'doughnut' : (isHbar ? 'bar' : 'bar');
            try {
                const chart = new window.Chart(canvas, {
                    type,
                    data: {
                        labels,
                        datasets: [{
                            data:                  values,
                            backgroundColor:       colors,
                            borderColor:           isDonut ? '#fff' : colors,
                            borderWidth:           isDonut ? 2 : 0,
                            borderRadius:          isDonut ? 0 : 4,
                            hoverBorderWidth:      isDonut ? 3 : 0,
                        }],
                    },
                    options: {
                        indexAxis:   isHbar ? 'y' : 'x',
                        responsive:  true,
                        maintainAspectRatio: false,
                        cutout:      isDonut ? '65%' : undefined,
                        onClick:     (_, elements) => {
                            if (elements && elements.length > 0) {
                                const idx = elements[0].index;
                                this._handleChartClick(kpi, labels[idx]);
                            }
                        },
                        plugins: {
                            legend: { display: false },
                            tooltip: {
                                callbacks: {
                                    label: ctx => ' ' + ctx.label + ': ' + (ctx.parsed != null && ctx.parsed.y != null ? ctx.parsed.y : (ctx.parsed || '')),
                                },
                            },
                        },
                        scales: isDonut ? {} : {
                            x: { grid: { display: isHbar }, ticks: { font: { size: 11 } } },
                            y: { grid: { display: !isHbar }, ticks: { font: { size: 11 } } },
                        },
                    },
                });
                this._chartInstances.push(chart);
            } catch (e) {}
        });
    }

    _renderEmptyChart(canvas) {
        try {
            const chart = new window.Chart(canvas, {
                type: 'doughnut',
                data: { labels: ['No Data'], datasets: [{ data: [1], backgroundColor: ['#E5E7EB'], borderWidth: 0 }] },
                options: {
                    responsive: true, maintainAspectRatio: false, cutout: '65%',
                    plugins: { legend: { display: false }, tooltip: { enabled: false } },
                },
            });
            this._chartInstances.push(chart);
        } catch (e) {}
    }
}