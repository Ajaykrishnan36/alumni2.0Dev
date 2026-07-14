import { LightningElement, track } from 'lwc';

const TABS = [
    'Overview',
    'Admissions',
    'Academics',
    'Attendance',
    'Examinations',
    'Fees',
    'Campus Life',
    'Placements',
    'Documents',
    'Communications',
    'Support',
    'Graduation'
];

const SUMMARY_CARDS = [
    {
        id: 'academic',
        title: 'Academic Standing',
        value: '7.8',
        subtitle: 'CGPA',
        accentClass: 'summary-card summary-card--blue',
        iconName: 'utility:knowledge_base',
        iconWrapClass: 'summary-card__icon summary-card__icon--blue',
        metrics: [
            { label: 'Semester', value: '4', valueClass: 'summary-card__metric-value' },
            { label: 'Credits', value: '62 / 160', valueClass: 'summary-card__metric-value' },
            { label: 'Backlogs', value: '1', valueClass: 'summary-card__metric-value summary-card__metric-value--warn' }
        ]
    },
    {
        id: 'attendance',
        title: 'Attendance',
        value: '72%',
        subtitle: 'Overall attendance',
        accentClass: 'summary-card summary-card--amber',
        iconName: 'utility:event',
        iconWrapClass: 'summary-card__icon summary-card__icon--amber',
        metrics: [
            { label: 'Below 75%', value: '2 courses', valueClass: 'summary-card__metric-value summary-card__metric-value--warn' },
            { label: 'Classes today', value: '4 of 5', valueClass: 'summary-card__metric-value' },
            { label: 'Last updated', value: 'Today', valueClass: 'summary-card__metric-value' }
        ]
    },
    {
        id: 'fees',
        title: 'Fees Status',
        value: 'Clear',
        subtitle: 'Current status',
        accentClass: 'summary-card summary-card--green',
        iconName: 'utility:moneybag',
        iconWrapClass: 'summary-card__icon summary-card__icon--green',
        metrics: [
            { label: 'Next due', value: '15 Aug 2026', valueClass: 'summary-card__metric-value' },
            { label: 'Last paid', value: '₹ 1,42,500', valueClass: 'summary-card__metric-value' },
            { label: 'Scholarship', value: 'Merit · 15%', valueClass: 'summary-card__metric-value summary-card__metric-value--good' }
        ]
    },
    {
        id: 'risk',
        title: 'At-Risk Status',
        value: 'Moderate',
        subtitle: 'Risk level',
        accentClass: 'summary-card summary-card--amber',
        iconName: 'utility:warning',
        iconWrapClass: 'summary-card__icon summary-card__icon--amber',
        metrics: [
            { label: 'Reason', value: 'Attendance shortfall', valueClass: 'summary-card__metric-value summary-card__metric-value--warn' },
            { label: 'Advisor', value: 'Prof. Meera Nair', valueClass: 'summary-card__metric-value' },
            { label: 'Intervention', value: '3 days ago', valueClass: 'summary-card__metric-value' }
        ]
    },
    {
        id: 'campus',
        title: 'Campus Status',
        value: 'Block B · 304',
        subtitle: 'Hostel',
        accentClass: 'summary-card summary-card--purple',
        iconName: 'utility:home',
        iconWrapClass: 'summary-card__icon summary-card__icon--purple',
        metrics: [
            { label: 'Mess plan', value: 'Standard veg', valueClass: 'summary-card__metric-value' },
            { label: 'Gate pass', value: 'Active', valueClass: 'summary-card__metric-value summary-card__metric-value--good' },
            { label: 'Open requests', value: '1', valueClass: 'summary-card__metric-value' }
        ]
    },
    {
        id: 'actions',
        title: 'Open Actions',
        value: '4',
        subtitle: 'Items needing attention',
        accentClass: 'summary-card summary-card--coral',
        iconName: 'utility:task',
        iconWrapClass: 'summary-card__icon summary-card__icon--coral',
        metrics: [
            { label: 'Pending docs', value: '1', valueClass: 'summary-card__metric-value summary-card__metric-value--warn' },
            { label: 'Open cases', value: '2', valueClass: 'summary-card__metric-value summary-card__metric-value--warn' },
            { label: 'Tasks due', value: '1', valueClass: 'summary-card__metric-value' }
        ]
    }
];

const LIFECYCLE_STAGES = [
    {
        id: 'first',
        stage: 'First Year',
        status: 'Completed',
        title: 'Onboarding & academic adjustment',
        description: 'Settling in, completing onboarding, finding footing in the first semester.',
        period: 'Aug 2024 - May 2025',
        iconName: 'utility:user',
        rowClass: 'lifecycle-row lifecycle-row--complete',
        iconClass: 'lifecycle-row__icon lifecycle-row__icon--complete',
        badgeClass: 'status-pill status-pill--good'
    },
    {
        id: 'middle',
        stage: 'Middle Years',
        status: 'Active',
        title: 'Academic progression & internship readiness',
        description: 'Keep momentum on credits and attendance, start preparing for internships.',
        period: 'Aug 2025 - present',
        iconName: 'utility:beaker',
        rowClass: 'lifecycle-row lifecycle-row--active',
        iconClass: 'lifecycle-row__icon lifecycle-row__icon--active',
        badgeClass: 'status-pill status-pill--active'
    },
    {
        id: 'final',
        stage: 'Final Year',
        status: 'Upcoming',
        title: 'Graduation & placement readiness',
        description: 'Drive placements, finish remaining credits, clear graduation prerequisites.',
        period: 'Aug 2026 - May 2028',
        iconName: 'utility:briefcase',
        rowClass: 'lifecycle-row',
        iconClass: 'lifecycle-row__icon',
        badgeClass: 'status-pill status-pill--muted'
    },
    {
        id: 'closure',
        stage: 'Graduating & Closure',
        status: 'Upcoming',
        title: 'Closure & alumni activation',
        description: 'Wrap up clearances, certificates, and activate the alumni record.',
        period: 'Spring 2028',
        iconName: 'utility:success',
        rowClass: 'lifecycle-row',
        iconClass: 'lifecycle-row__icon',
        badgeClass: 'status-pill status-pill--muted'
    }
];

const COURSE_CARDS = [
    { code: 'CS301', title: 'Operating Systems', faculty: 'Dr. Rohit Sinha', credits: '4 credits', attendance: 64, iconName: 'utility:settings', tone: 'orange' },
    { code: 'MA401', title: 'Discrete Mathematics', faculty: 'Prof. Kavita Iyer', credits: '3 credits', attendance: 68, iconName: 'utility:summary', tone: 'orange' },
    { code: 'CS305', title: 'Database Systems', faculty: 'Dr. Suman Banerjee', credits: '4 credits', attendance: 82, iconName: 'utility:database', tone: 'green' },
    { code: 'CS307', title: 'Computer Networks', faculty: 'Prof. Meera Nair', credits: '4 credits', attendance: 78, iconName: 'utility:hierarchy', tone: 'green' },
    { code: 'HS401', title: 'Engineering Economics', faculty: 'Dr. Tarun Mehta', credits: '2 credits', attendance: 80, iconName: 'utility:calculator', tone: 'green' },
    { code: 'CS399', title: 'Faculty-Guided Project', faculty: 'Prof. Meera Nair', credits: '2 credits', attendance: 90, iconName: 'utility:beaker', tone: 'green' }
];

const ATTENDANCE_ROWS = [
    { code: 'CS301', title: 'Operating Systems', pct: 64, warning: true },
    { code: 'MA401', title: 'Discrete Mathematics', pct: 68, warning: true },
    { code: 'CS305', title: 'Database Systems', pct: 82, warning: false },
    { code: 'CS307', title: 'Computer Networks', pct: 78, warning: false },
    { code: 'HS401', title: 'Engineering Economics', pct: 80, warning: false },
    { code: 'CS399', title: 'Faculty-Guided Project', pct: 90, warning: false }
];

const TRANSCRIPT_ROWS = [
    { code: 'MA201', title: 'Discrete Mathematics', credits: '4', grade: 'F', gradeClass: 'grade-pill grade-pill--fail', points: '0.0' },
    { code: 'CS201', title: 'Object Oriented Programming', credits: '4', grade: 'A+', gradeClass: 'grade-pill grade-pill--good', points: '9.0' },
    { code: 'CS202', title: 'Computer Organization', credits: '4', grade: 'A', gradeClass: 'grade-pill grade-pill--blue', points: '8.0' },
    { code: 'CS203', title: 'Database Management Systems', credits: '4', grade: 'A', gradeClass: 'grade-pill grade-pill--blue', points: '8.0' },
    { code: 'HS201', title: 'Economics for Engineers', credits: '2', grade: 'B+', gradeClass: 'grade-pill grade-pill--blue', points: '7.0' },
    { code: 'CS291', title: 'OOP Lab', credits: '2', grade: 'A+', gradeClass: 'grade-pill grade-pill--good', points: '9.0' },
    { code: 'CS292', title: 'DBMS Lab', credits: '2', grade: 'A', gradeClass: 'grade-pill grade-pill--blue', points: '8.0' }
];

const FEE_ROWS = [
    { sem: 'Sem 1', head: 'Tuition + lab + library', amount: '₹ 4,03,750', due: '15 Aug 2024', paidOn: '20 May 2024', receipt: 'RCP-2024-09112', status: 'Paid', badgeClass: 'status-pill status-pill--good' },
    { sem: 'Sem 2', head: 'Tuition + lab + library', amount: '₹ 4,03,750', due: '15 Jan 2025', paidOn: '10 Jan 2025', receipt: 'RCP-2025-01188', status: 'Paid', badgeClass: 'status-pill status-pill--good' },
    { sem: 'Sem 3', head: 'Tuition + lab + library', amount: '₹ 4,03,750', due: '15 Aug 2025', paidOn: '12 Aug 2025', receipt: 'RCP-2025-08231', status: 'Paid', badgeClass: 'status-pill status-pill--good' },
    { sem: 'Sem 4', head: 'Tuition + lab + library', amount: '₹ 4,03,750', due: '15 Jan 2026', paidOn: '12 Feb 2026', receipt: 'RCP-2026-02041', status: 'Paid', badgeClass: 'status-pill status-pill--good' },
    { sem: 'Sem 5', head: 'Tuition + lab + library', amount: '₹ 4,03,750', due: '15 Aug 2026', paidOn: '-', receipt: '-', status: 'Upcoming', badgeClass: 'status-pill status-pill--warn' }
];

const DOCUMENT_ROWS = [
    { title: 'Class X marksheet', status: 'Verified', badgeClass: 'status-pill status-pill--good' },
    { title: 'Class XII marksheet', status: 'Verified', badgeClass: 'status-pill status-pill--good' },
    { title: 'JEE Main scorecard', status: 'Verified', badgeClass: 'status-pill status-pill--good' },
    { title: 'Aadhaar', status: 'Verified', badgeClass: 'status-pill status-pill--good' },
    { title: 'Class XII migration cert.', status: 'Pending', badgeClass: 'status-pill status-pill--warn' },
    { title: 'Caste / Category cert.', status: 'Not Applicable', badgeClass: 'status-pill status-pill--muted' }
];

const ATTENTION_ITEMS = [
    { id: 1, title: 'Attendance below threshold in Operating Systems & Discrete Math', action: 'Send notice', iconName: 'utility:warning' },
    { id: 2, title: '1 pending document - Class XII migration certificate', action: 'Request', iconName: 'utility:file' },
    { id: 3, title: 'Advisor check-in due this week with Prof. Meera Nair', action: 'Schedule', iconName: 'utility:user' }
];

const ACTIVITY_ITEMS = [
    { id: 1, title: 'Attendance updated', when: 'Today', iconName: 'utility:date_input' },
    { id: 2, title: 'Fee receipt generated', when: 'Last week', iconName: 'utility:moneybag' },
    { id: 3, title: 'Case resolved', when: '2 days ago', iconName: 'utility:shield' },
    { id: 4, title: 'Document uploaded', when: '5 days ago', iconName: 'utility:file' },
    { id: 5, title: 'Parent communication sent', when: 'Last week', iconName: 'utility:email' }
];

const HEALTH_ITEMS = [
    { id: 1, title: 'Contact verified', note: '', state: 'good' },
    { id: 2, title: 'Parent records linked', note: '', state: 'good' },
    { id: 3, title: 'Documents mostly complete', note: '1 pending', state: 'warn' },
    { id: 4, title: 'No active fee dues', note: '', state: 'good' },
    { id: 5, title: 'Moderate attendance risk', note: '2 courses', state: 'warn' }
];

export default class KenStudent360 extends LightningElement {
    @track activeTab = 'Overview';

    summaryCards = SUMMARY_CARDS;
    lifecycleStages = LIFECYCLE_STAGES;
    transcriptRows = TRANSCRIPT_ROWS;
    feeRows = FEE_ROWS;
    documentRows = DOCUMENT_ROWS;
    attentionItems = ATTENTION_ITEMS;
    activityItems = ACTIVITY_ITEMS;

    get tabs() {
        return TABS.map((tab) => ({
            label: tab,
            cssClass: tab === this.activeTab ? 'record-tab record-tab--active' : 'record-tab'
        }));
    }

    get courseCards() {
        return COURSE_CARDS.map((course) => this.decorateAttendance(course));
    }

    get attendanceRows() {
        return ATTENDANCE_ROWS.map((row) => this.decorateAttendance(row));
    }

    get healthItems() {
        return HEALTH_ITEMS.map((item) => ({
            ...item,
            iconClass: item.state === 'good' ? 'health-icon health-icon--good' : 'health-icon health-icon--warn',
            iconName: item.state === 'good' ? 'utility:success' : 'utility:warning'
        }));
    }

    get isOverview() { return this.activeTab === 'Overview'; }
    get isAdmissions() { return this.activeTab === 'Admissions'; }
    get isAcademics() { return this.activeTab === 'Academics'; }
    get isAttendance() { return this.activeTab === 'Attendance'; }
    get isExaminations() { return this.activeTab === 'Examinations'; }
    get isFees() { return this.activeTab === 'Fees'; }
    get isCampusLife() { return this.activeTab === 'Campus Life'; }
    get isPlacements() { return this.activeTab === 'Placements'; }
    get isDocuments() { return this.activeTab === 'Documents'; }
    get isCommunications() { return this.activeTab === 'Communications'; }
    get isSupport() { return this.activeTab === 'Support'; }
    get isGraduation() { return this.activeTab === 'Graduation'; }

    selectTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    decorateAttendance(item) {
        const isWarning = item.attendance ? item.attendance < 75 : item.pct < 75;
        const pct = item.attendance || item.pct;
        return {
            ...item,
            pct,
            progressStyle: `width: ${pct}%;`,
            progressClass: isWarning ? 'progress-bar__fill progress-bar__fill--warn' : 'progress-bar__fill',
            iconTileClass: item.tone === 'green' ? 'course-card__icon course-card__icon--green' : 'course-card__icon'
        };
    }
}