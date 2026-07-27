import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import DOWNLOAD_DUMMY_PDF from '@salesforce/resourceUrl/DownloadDummyPdf';

const JOBS = [
    {
        id: 1,
        company: 'Paypal',
        title: 'Developer',
        location: 'Mumbai, India',
        salary: '₹ 5,00,000 - ₹ 8,00,000',
        matchText: '57 skills match with your resume',
        domain: 'Fintech',
        type: 'Startup',
        applicationClose: 'Application closes on 08 Oct, 2025'
    },
    {
        id: 2,
        company: 'Hindustan Unilever',
        title: 'Software Engineer',
        location: 'Chennai, India',
        salary: '₹ 6,20,000 - ₹ 9,50,000',
        matchText: '54 skills match with your resume',
        domain: 'Manufacturing & Engineering',
        type: 'Corporate',
        applicationClose: 'Application closes on 11 Oct, 2025'
    },
    {
        id: 3,
        company: 'Reliance Industries',
        title: 'Data Scientist',
        location: 'Bangalore, India',
        salary: '₹ 7,00,000 - ₹ 10,00,000',
        matchText: '52 skills match with your resume',
        domain: 'Consumer Goods',
        type: 'Corporate',
        applicationClose: 'Application closes on 16 Oct, 2025'
    },
    {
        id: 4,
        company: 'Infosys',
        title: 'Cloud Specialist',
        location: 'Delhi NCR, India',
        salary: '₹ 4,50,000 - ₹ 7,50,000',
        matchText: '39 skills match with your resume',
        domain: 'Information Technology',
        type: 'Corporate',
        applicationClose: 'Application closes on 19 Oct, 2025'
    },
    {
        id: 5,
        company: 'Google',
        title: 'Security Analyst',
        location: 'Hybrid, India',
        salary: '₹ 8,00,000 LPA',
        matchText: '41 skills match with your resume',
        domain: 'Information Technology',
        type: 'Corporate',
        applicationClose: 'Application closes on 23 Oct, 2025'
    },
    { 
        id: 6,
        company: 'Wipro',
        title: 'Network Architect',
        location: 'Chennai, India',
        salary: '₹ 6,50,000 LPA',
        matchText: '36 skills match with your resume',
        domain: 'EdTech',
        type: 'Corporate',
        applicationClose: 'Application closes on 27 Oct, 2025'
    },
    {
        id: 7,
        company: 'Amazon',
        title: 'Product Analyst',
        location: 'Hyderabad, India',
        salary: '₹ 7,20,000 - ₹ 9,00,000',
        matchText: '49 skills match with your resume',
        domain: 'Consumer Goods',
        type: 'Corporate',
        applicationClose: 'Application closes on 29 Oct, 2025'
    },
    {
        id: 8,
        company: 'Zoho',
        title: 'UI Engineer',
        location: 'Remote, India',
        salary: '₹ 5,80,000 - ₹ 7,40,000',
        matchText: '47 skills match with your resume',
        domain: 'Information Technology',
        type: 'Startup',
        applicationClose: 'Application closes on 31 Oct, 2025'
    }
];

const PROCESS_STEPS = [
    { id: 'step-1', label: 'Initial Screening', date: '7th Oct, 2025' },
    { id: 'step-2', label: 'Technical Interview', date: '12th Oct, 2025' },
    { id: 'step-3', label: 'Aptitude Test', date: '16th Oct, 2025' },
    { id: 'step-4', label: 'Leadership Round', date: '20th Oct, 2025' },
    { id: 'step-5', label: 'HR Interview', date: '24th Oct, 2025' }
];

const PROCESS_VIEWS = {
    slot_closed: {
        status: { label: 'Slot Closed', type: 'slot-closed' },
        stepStates: ['completed', 'locked', 'upcoming', 'upcoming', 'upcoming'],
        panel: {
            title: 'Initial screening',
            subtitle: 'Please choose your preferred time slot for the technical interview.',
            showBookSlotButton: true,
            showJoinMeetButton: false,
            isJoinMeetDisabled: true,
            showPreparationTips: false,
            tips: [],
            rightBanner: {
                type: 'dark',
                title: 'Booking Closed',
                text: 'Slot booking date has passed by. Unfortunately, you cannot proceed further.'
            },
            showRejectedBanner: false
        }
    },
    after_round1: {
        status: { label: 'Shortlisted', type: 'shortlisted' },
        stepStates: ['completed', 'current', 'upcoming', 'upcoming', 'upcoming'],
        panel: {
            title: 'Initial screening',
            subtitle: 'Interview scheduled at 8th Oct, 2025, 10:00 pm IST',
            showBookSlotButton: false,
            showJoinMeetButton: true,
            isJoinMeetDisabled: true,
            showPreparationTips: true,
            tips: [
                'Review resume & job description',
                'Practice communication & intro pitch',
                'Know your notice period & expected CTC'
            ],
            rightBanner: null,
            showRejectedBanner: false
        }
    },
    in_review: {
        status: { label: 'Shortlisted', type: 'shortlisted' },
        stepStates: ['completed', 'completed', 'upcoming', 'upcoming', 'upcoming'],
        panel: {
            title: 'Technical Interview',
            subtitle: 'Completed on 12th Oct, 2025',
            showBookSlotButton: false,
            showJoinMeetButton: false,
            isJoinMeetDisabled: true,
            showPreparationTips: false,
            tips: [],
            rightBanner: {
                type: 'review',
                title: 'In review',
                text: 'Your 1st round initial screening is currently under review.'
            },
            showRejectedBanner: false
        }
    },
    round1_success: {
        status: { label: 'Shortlisted', type: 'shortlisted' },
        stepStates: ['completed', 'completed', 'current', 'upcoming', 'upcoming'],
        panel: {
            title: 'Technical Interview',
            subtitle: 'Completed on 12th Oct, 2025',
            showBookSlotButton: false,
            showJoinMeetButton: false,
            isJoinMeetDisabled: true,
            showPreparationTips: false,
            tips: [],
            rightBanner: {
                type: 'success',
                title: 'Congratulations',
                text: 'You have been shortlisted for Round 2 interview (Technical Interview).'
            },
            showRejectedBanner: false
        }
    },
    rejected: {
        status: { label: 'Rejected', type: 'rejected' },
        stepStates: ['rejected', 'upcoming', 'upcoming', 'upcoming', 'upcoming'],
        panel: {
            title: '',
            subtitle: '',
            showBookSlotButton: false,
            showJoinMeetButton: false,
            isJoinMeetDisabled: true,
            showPreparationTips: false,
            tips: [],
            rightBanner: null,
            showRejectedBanner: true
        }
    },
    join_before_15: {
        status: { label: 'Shortlisted', type: 'shortlisted' },
        stepStates: ['completed', 'current', 'upcoming', 'upcoming', 'upcoming'],
        panel: {
            title: 'Initial screening',
            subtitle: 'Interview scheduled at 8th Oct, 2025, 10:00 pm IST',
            showBookSlotButton: false,
            showJoinMeetButton: true,
            isJoinMeetDisabled: false,
            showPreparationTips: true,
            tips: [
                'Review resume & job description',
                'Practice communication & intro pitch',
                'Know your notice period & expected CTC'
            ],
            rightBanner: null,
            showRejectedBanner: false
        }
    }
};

const ABOUT_JOB = `At {company}, work is more than a job - it is a calling: to build, to design, to code, to consult,
think along with clients and sell. To make markets. To invent. To collaborate. Not just to do something better,
but to attempt things you have never thought possible.`;

const KEY_RESPONSIBILITIES = [
    'Develop new user-facing features using modern JavaScript frameworks.',
    'Build reusable components and front-end libraries for future use.',
    'Optimize components for maximum performance across browsers and devices.',
    'Collaborate with UX/UI designers and backend teams for feature delivery.',
    'Maintain quality, scalability and reliability of frontend architecture.',
    'Write clean, maintainable and well-documented code.',
    'Troubleshoot issues to ensure strong user experience.',
    'Stay updated with trends in frontend and React ecosystem.'
];

const SKILLS_REQUIRED = ['CSS', 'HTML', 'JavaScript', 'Node.js', 'ReactJS', 'Redux', 'REST API'];

const OTHER_REQUIREMENTS = [
    'Computer science background or equivalent practical experience.',
    'Strong understanding of JavaScript (ES6+), HTML5, CSS3 and responsive web principles.',
    'Experience with state management libraries such as Redux or Context API.',
    'Familiarity with RESTful APIs and frontend-backend integration.'
];

const PERKS = ['Informal dress code', 'Free snacks & beverages', 'Health Insurance', 'Life Insurance'];
const SLOT_OPTIONS = [
    { period: 'Morning', time: '09:00 AM IST' },
    { period: 'Morning', time: '12:00 AM IST' },
    { period: 'Afternoon', time: '02:00 PM IST' },
    { period: 'Afternoon', time: '03:45 PM IST' }
];
const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export default class KenJobDetailsPage extends LightningElement {
    selectedJobId = 1;
    isApplyModalOpen = false;
    isAppliedModalOpen = false;
    isJobApplied = false;
    processView = 'after_round1';
    isBookSlotModalOpen = false;
    isBookedToastOpen = false;
    selectedSlot = '';
    currentCalendarDate = new Date(2024, 2, 1);
    selectedDateKey = '';
    showOnlyAvailableDates = false;
    bookedDate = '13th March';

    resumeOptions = [
        {
            id: 'resume-1',
            fileName: 'Resume_compressed.pdf',
            lastUsed: 'Last used on 8/7/2024',
            previewAvailable: true,
            isUploaded: false,
            previewUrl: DOWNLOAD_DUMMY_PDF,
            downloadUrl: DOWNLOAD_DUMMY_PDF
        },
        {
            id: 'resume-2',
            fileName: 'Visual designer.pdf',
            lastUsed: 'Last used on 6/5/2024',
            previewAvailable: true,
            isUploaded: false,
            previewUrl: DOWNLOAD_DUMMY_PDF,
            downloadUrl: DOWNLOAD_DUMMY_PDF
        }
    ];

    selectedResumeId = 'resume-2';

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const jobId = Number(pageRef?.state?.jobId);
        if (!Number.isNaN(jobId) && jobId > 0) {
            this.selectedJobId = jobId;
        }

        const requestedView = pageRef?.state?.processView;
        const normalizedView = requestedView ? String(requestedView).toLowerCase().replace(/-/g, '_') : '';
        if (normalizedView && PROCESS_VIEWS[normalizedView]) {
            this.processView = normalizedView;
        }
    }

    get job() {
        return JOBS.find((item) => item.id === this.selectedJobId) || JOBS[0];
    }

    get companyInitial() {
        return this.job.company.charAt(0).toUpperCase();
    }

    get processSteps() {
        const steps = PROCESS_STEPS;
        const states = this.currentProcessView.stepStates || [];

        return steps.map((step, index) => {
            const state = states[index] || 'upcoming';
            return {
                ...step,
                dotClass: `process-dot ${state}`,
                boxClass: `process-box ${state}`
            };
        });
    }

    get currentProcessView() {
        return PROCESS_VIEWS[this.processView] || PROCESS_VIEWS.after_round1;
    }

    get showStatusBadge() {
        return Boolean(this.currentProcessView?.status?.label);
    }

    get statusBadgeLabel() {
        return this.currentProcessView?.status?.label || '';
    }

    get statusBadgeClass() {
        const type = this.currentProcessView?.status?.type || '';
        return `status-pill ${type}`;
    }

    get processPanel() {
        return this.currentProcessView?.panel || {};
    }

    get processPanelTitle() {
        return this.processPanel.title || '';
    }

    get processPanelSubtitle() {
        return this.processPanel.subtitle || '';
    }

    get showBookSlotButton() {
        return Boolean(this.processPanel.showBookSlotButton);
    }

    get showJoinMeetButton() {
        return Boolean(this.processPanel.showJoinMeetButton);
    }

    get isJoinMeetDisabled() {
        return Boolean(this.processPanel.isJoinMeetDisabled);
    }

    get showPreparationTips() {
        return Boolean(this.processPanel.showPreparationTips);
    }

    get preparationTips() {
        return this.processPanel.tips || [];
    }

    get showRightBanner() {
        return Boolean(this.processPanel.rightBanner);
    }

    get rightBannerClass() {
        const type = this.processPanel?.rightBanner?.type || 'dark';
        return `right-banner ${type}`;
    }

    get rightBannerTitle() {
        return this.processPanel?.rightBanner?.title || '';
    }

    get rightBannerText() {
        return this.processPanel?.rightBanner?.text || '';
    }

    get showRejectedBanner() {
        return Boolean(this.processPanel.showRejectedBanner);
    }

    get slotOptions() {
        const options = this.getSlotsForDate(this.selectedDateKey);
        return options.map((slot) => ({
            ...slot,
            className: this.selectedSlot === slot.id ? 'slot-card selected' : 'slot-card',
            isSelected: this.selectedSlot === slot.id
        }));
    }

    get bookedSlotSummary() {
        const slot = this.slotOptions.find((item) => item.id === this.selectedSlot);
        return `${this.bookedDate}  |  ${slot ? slot.time : ''}`;
    }

    get monthLabel() {
        return this.currentCalendarDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
    }

    get weekdayLabels() {
        return WEEKDAY_LABELS;
    }

    get calendarCells() {
        const year = this.currentCalendarDate.getFullYear();
        const month = this.currentCalendarDate.getMonth();
        const firstDay = new Date(year, month, 1).getDay();
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const prevMonthDays = new Date(year, month, 0).getDate();
        const cells = [];

        for (let i = firstDay - 1; i >= 0; i -= 1) {
            const day = prevMonthDays - i;
            const date = new Date(year, month - 1, day);
            cells.push(this.buildCalendarCell(date, false));
        }

        for (let day = 1; day <= daysInMonth; day += 1) {
            const date = new Date(year, month, day);
            cells.push(this.buildCalendarCell(date, true));
        }

        while (cells.length % 7 !== 0) {
            const day = cells.length - (firstDay + daysInMonth) + 1;
            const date = new Date(year, month + 1, day);
            cells.push(this.buildCalendarCell(date, false));
        }

        return cells;
    }

    get availableDatesLabel() {
        return this.showOnlyAvailableDates ? 'Showing available dates only' : 'Available Dates';
    }

    get hasSlotsForSelectedDate() {
        return this.slotOptions.length > 0;
    }

    connectedCallback() {
        this.ensureSelectedDateForMonth();
    }

    get aboutJobText() {
        return ABOUT_JOB.replace('{company}', this.job.company);
    }

    get keyResponsibilities() {
        return KEY_RESPONSIBILITIES;
    }

    get skillsRequired() {
        return SKILLS_REQUIRED;
    }

    get otherRequirements() {
        return OTHER_REQUIREMENTS;
    }

    get perks() {
        return PERKS;
    }

    get companyWebsite() {
        return `https://www.${this.job.company.toLowerCase().replace(/\s+/g, '')}.com`;
    }

    get selectedResume() {
        return this.resumeOptions.find((item) => item.id === this.selectedResumeId) || this.resumeOptions[0];
    }

    get mappedResumeOptions() {
        return this.resumeOptions.map((item) => ({
            ...item,
            cardClass: item.id === this.selectedResumeId ? 'resume-card selected' : 'resume-card',
            indicatorClass:
                item.id === this.selectedResumeId ? 'resume-select-indicator selected' : 'resume-select-indicator',
            showPreview: item.previewAvailable && item.id === this.selectedResumeId,
            detailText: item.isUploaded && item.fileSizeLabel ? item.fileSizeLabel : item.lastUsed
        }));
    }

    get applyButtonClass() {
        return this.isJobApplied ? 'apply-btn applied' : 'apply-btn';
    }

    handleApplyClick() {
        if (!this.isJobApplied) {
            this.isApplyModalOpen = true;
        }
    }

    closeApplyModal() {
        this.isApplyModalOpen = false;
    }

    handleApplyModalOverlayClick(event) {
        if (event.target.classList.contains('modal-overlay')) {
            this.closeApplyModal();
        }
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }

    handleUploadResumeClick() {
        const uploadInput = this.template.querySelector('.resume-upload-input');
        if (uploadInput) {
            uploadInput.click();
        }
    }

    handleResumeUploadChange(event) {
        const uploadedFile = event.target.files?.[0];
        if (!uploadedFile) {
            return;
        }

        const currentDate = new Date();
        const formattedDate = `${currentDate.getDate()}/${currentDate.getMonth() + 1}/${currentDate.getFullYear()}`;
        const newResumeId = `resume-${currentDate.getTime()}`;

        this.resumeOptions = [
            ...this.resumeOptions,
            {
                id: newResumeId,
                fileName: uploadedFile.name,
                lastUsed: `Last used on ${formattedDate}`,
                fileSizeLabel: `Size: ${this.formatFileSize(uploadedFile.size)}`,
                previewAvailable: true,
                isUploaded: true,
                file: uploadedFile
            }
        ];
        this.selectedResumeId = newResumeId;
        event.target.value = '';
    }

    handleResumeSelect(event) {
        const selectedId = event.currentTarget?.dataset?.resumeId;
        if (selectedId) {
            this.selectedResumeId = selectedId;
        }
    }

    handleResumeDownload(event) {
        event.stopPropagation();
        const resumeId = event.currentTarget?.dataset?.resumeId;
        const resume = this.resumeOptions.find((item) => item.id === resumeId);
        if (!resume) {
            return;
        }

        const anchor = document.createElement('a');
        let fileUrl;

        if (resume.file) {
            fileUrl = URL.createObjectURL(resume.file);
            anchor.href = fileUrl;
        } else if (resume.downloadUrl) {
            anchor.href = resume.downloadUrl;
        } else {
            return;
        }

        anchor.download = resume.fileName || 'resume';
        anchor.target = '_blank';
        anchor.rel = 'noopener';
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
        if (fileUrl) {
            setTimeout(() => URL.revokeObjectURL(fileUrl), 1000);
        }
    }

    handleApplyUsingResume() {
        this.isApplyModalOpen = false;
        this.isJobApplied = true;
        this.isAppliedModalOpen = true;
        this.processView = 'after_round1';
    }

    closeAppliedModal() {
        this.isAppliedModalOpen = false;
    }

    handleExploreSimilarJobs() {
        this.closeAppliedModal();
    }

    handleOpenPreview(event) {
        event.stopPropagation();
        const resumeId = event.currentTarget?.dataset?.resumeId;
        const resume = this.resumeOptions.find((item) => item.id === resumeId);
        if (!resume) {
            return;
        }

        if (resume.file) {
            const fileUrl = URL.createObjectURL(resume.file);
            window.open(fileUrl, '_blank', 'noopener');
            setTimeout(() => URL.revokeObjectURL(fileUrl), 3000);
            return;
        }

        if (resume.previewUrl || resume.downloadUrl) {
            window.open(resume.previewUrl || resume.downloadUrl, '_blank', 'noopener');
        }
    }

    handleBookSlotClick() {
        this.isBookSlotModalOpen = true;
        this.ensureSelectedDateForMonth();
    }

    closeBookSlotModal() {
        this.isBookSlotModalOpen = false;
    }

    handleSlotSelect(event) {
        const selectedValue = event.currentTarget?.dataset?.value;
        if (selectedValue) {
            this.selectedSlot = selectedValue;
        }
    }

    handleConfirmSlotBooking() {
        this.isBookSlotModalOpen = false;
        this.isBookedToastOpen = true;
        this.processView = 'join_before_15';
        this.bookedDate = this.formatReadableDate(this.selectedDateKey);
        window.setTimeout(() => {
            this.isBookedToastOpen = false;
        }, 1800);
    }

    closeBookedToast() {
        this.isBookedToastOpen = false;
    }

    formatFileSize(bytes) {
        if (!bytes && bytes !== 0) {
            return '';
        }
        if (bytes < 1024) {
            return `${bytes} B`;
        }
        const kb = bytes / 1024;
        if (kb < 1024) {
            return `${kb.toFixed(1)} KB`;
        }
        const mb = kb / 1024;
        return `${mb.toFixed(2)} MB`;
    }

    handlePreviousMonth() {
        this.currentCalendarDate = new Date(
            this.currentCalendarDate.getFullYear(),
            this.currentCalendarDate.getMonth() - 1,
            1
        );
        this.ensureSelectedDateForMonth();
    }

    handleNextMonth() {
        this.currentCalendarDate = new Date(
            this.currentCalendarDate.getFullYear(),
            this.currentCalendarDate.getMonth() + 1,
            1
        );
        this.ensureSelectedDateForMonth();
    }

    handleCalendarDateClick(event) {
        const dateKey = event.currentTarget?.dataset?.date;
        if (!dateKey || !this.isDateAvailable(dateKey)) {
            return;
        }
        this.selectedDateKey = dateKey;
        const firstSlot = this.getSlotsForDate(dateKey)[0];
        this.selectedSlot = firstSlot ? firstSlot.id : '';
    }

    handleAvailableDatesToggle(event) {
        this.showOnlyAvailableDates = event.target.checked;
    }

    buildCalendarCell(date, isCurrentMonth) {
        const dateKey = this.formatDateKey(date);
        const isAvailable = isCurrentMonth && this.isDateAvailable(dateKey);
        const isSelected = this.selectedDateKey === dateKey;
        const isHidden = this.showOnlyAvailableDates && isCurrentMonth && !isAvailable;
        let className = 'calendar-date-cell';

        if (!isCurrentMonth) {
            className += ' outside';
        } else if (isSelected) {
            className += ' selected';
        } else if (isAvailable) {
            className += ' available';
        } else {
            className += ' unavailable';
        }

        if (isHidden) {
            className += ' hidden';
        }

        return {
            key: dateKey,
            label: date.getDate(),
            dateKey,
            className,
            isDisabled: !isAvailable
        };
    }

    ensureSelectedDateForMonth() {
        const year = this.currentCalendarDate.getFullYear();
        const month = this.currentCalendarDate.getMonth();
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        let candidate = '';

        for (let day = 1; day <= daysInMonth; day += 1) {
            const dateKey = this.formatDateKey(new Date(year, month, day));
            if (this.isDateAvailable(dateKey)) {
                candidate = dateKey;
                break;
            }
        }

        this.selectedDateKey = candidate;
        const firstSlot = this.getSlotsForDate(candidate)[0];
        this.selectedSlot = firstSlot ? firstSlot.id : '';
    }

    isDateAvailable(dateKey) {
        if (!dateKey) {
            return false;
        }
        const [year, month, day] = dateKey.split('-').map(Number);
        const date = new Date(year, month - 1, day);
        const weekday = date.getDay();
        return weekday !== 0 && weekday !== 6;
    }

    getSlotsForDate(dateKey) {
        if (!this.isDateAvailable(dateKey)) {
            return [];
        }
        return SLOT_OPTIONS.map((slot, index) => ({
            ...slot,
            id: `${dateKey}-${index + 1}`
        }));
    }

    formatDateKey(date) {
        const year = date.getFullYear();
        const month = `${date.getMonth() + 1}`.padStart(2, '0');
        const day = `${date.getDate()}`.padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatReadableDate(dateKey) {
        if (!dateKey) {
            return '';
        }
        const [year, month, day] = dateKey.split('-').map(Number);
        const date = new Date(year, month - 1, day);
        const dayWithSuffix = `${date.getDate()}${this.getOrdinal(date.getDate())}`;
        const monthName = date.toLocaleDateString('en-US', { month: 'short' });
        return `${dayWithSuffix} ${monthName}`;
    }

    getOrdinal(day) {
        if (day > 3 && day < 21) {
            return 'th';
        }
        switch (day % 10) {
            case 1:
                return 'st';
            case 2:
                return 'nd';
            case 3:
                return 'rd';
            default:
                return 'th';
        }
    }
}