import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import JobsNotFound2 from '@salesforce/resourceUrl/JobsNotFound2';
import JobsNotFound1 from '@salesforce/resourceUrl/JobsNotFound1';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

// Change this single stage value from 1-5 to demo the full jobs flow.
const DEFAULT_STAGE = 5;
const JOBS_STAGES = Object.freeze({
    FIRST_VISIT: 1,
    APPLIED_ONLY: 2,
    PLACEMENT_SUMMARY: 3,
    OFFER_RECEIVED: 4,
    OFFER_ACCEPTED: 5
});

const RECOMMENDED_JOBS = [
    {
        id: 1,
        company: 'Paypal',
        initials: 'P',
        badgeClass: 'brand-badge brand-1',
        title: 'Developer',
        domain: 'Information Technology',
        location: 'Remote',
        type: 'Startup',
        salary: '₹ 5,00,000 - ₹ 8,00,000',
        match: 93
    },
    // {
    //     id: 2,
    //     company: 'Hindustan Unilever',
    //     initials: 'H',
    //     badgeClass: 'brand-badge brand-2',
    //     title: 'Software Engineer',
    //     domain: 'Manufacturing & Engineering',
    //     location: 'Chennai',
    //     type: 'Corporate',
    //     salary: '₹ 6,20,000 - ₹ 9,50,000',
    //     match: 87
    // },
    {
        id: 3,
        company: 'Reliance Industries',
        initials: 'R',
        badgeClass: 'brand-badge brand-3',
        title: 'Data Scientist',
        domain: 'Consumer Goods',
        location: 'Bangalore',
        type: 'Corporate',
        salary: '₹ 7,00,000 - ₹ 10,00,000',
        match: 84
    },
    {
        id: 4,
        company: 'Infosys',
        initials: 'I',
        badgeClass: 'brand-badge brand-4',
        title: 'Cloud Specialist',
        domain: 'Information Technology',
        location: 'Delhi NCR',
        type: 'Corporate',
        salary: '₹ 4,50,000 - ₹ 7,50,000',
        match: 60
    },
    {
        id: 5,
        company: 'Google',
        initials: 'G',
        badgeClass: 'brand-badge brand-5',
        title: 'Security Analyst',
        domain: 'Information Technology',
        location: 'Hybrid',
        type: 'Corporate',
        salary: '₹ 8,00,000 LPA',
        match: 54
    },
    {
        id: 6,
        company: 'Wipro',
        initials: 'W',
        badgeClass: 'brand-badge brand-6',
        title: 'Network Architect',
        domain: 'EdTech',
        location: 'Chennai',
        type: 'Corporate',
        salary: '₹ 6,50,000 LPA',
        match: 45
    }
];

const ALL_JOBS = [
    ...RECOMMENDED_JOBS,
    {
        id: 7,
        company: 'Amazon',
        initials: 'A',
        badgeClass: 'brand-badge brand-2',
        title: 'Product Analyst',
        domain: 'Consumer Goods',
        location: 'Hyderabad',
        type: 'Corporate',
        salary: '₹ 7,20,000 - ₹ 9,00,000',
        match: 72
    },
    {
        id: 8,
        company: 'Zoho',
        initials: 'Z',
        badgeClass: 'brand-badge brand-3',
        title: 'UI Engineer',
        domain: 'Information Technology',
        location: 'Remote',
        type: 'Startup',
        salary: '₹ 5,80,000 - ₹ 7,40,000',
        match: 68
    }
];

const RECOMMENDED_IDS = new Set(RECOMMENDED_JOBS.map((job) => job.id));

const INSTRUCTIONS_NEXT_STEPS = [
    'Download Offer Letter - Keep a copy for your records and future use.',
    'Prepare for Onboarding - Review joining instructions, timelines, and required documents.',
    'Career Compass - Explore long-term growth guidance, certifications, and skills to prepare for your new role.'
];

const INSTRUCTIONS_SUPPORT_POLICIES = [
    'If you face issues such as offer withdrawal, incorrect details, or employer delays, raise a Support Ticket from this dashboard.',
    'Alumni Connect: Reach out to alumni working in your company for tips and onboarding advice.',
    'Resources: Access prep kits and institutional guidance for transitioning into your role.'
];

const DEFAULT_COMPARISON_OFFERS = [
    {
        id: 'offer-1',
        jobId: 1,
        title: 'Developer',
        company: 'Paypal',
        initials: 'P',
        badgeClass: 'brand-badge brand-1',
        domain: 'Information Technology',
        location: 'Remote',
        type: 'Startup',
        salary: '₹ 8,00,000',
        match: 95,
        logoText: 'P',
        totalCtc: 800000,
        breakdown: {
            fixed: 400000,
            variable: 100000,
            bonuses: 300000
        },
        attributes: [
            { icon: 'utility:checkin', text: 'Remote' },
            { icon: 'utility:company', text: 'Startup' },
            { icon: 'utility:trending', text: 'High growth potential with clear promotion path' },
            { icon: 'utility:people', text: '15 alumni work here' }
        ],
        perks: ['Health insurance for family', 'Stock options (ESOPs)', 'Flexible working hours'],
        joining: 'Jan 01, 2026',
        bond: '2 years',
        acceptBy: 'Nov 15, 2025',
        questionLabel: 'Your question(s)',
        question: ''
    },
    // {
    //     id: 'offer-2',
    //     jobId: 2,
    //     title: 'Software Engineer',
    //     company: 'Hindustan Unilever',
    //     initials: 'H',
    //     badgeClass: 'brand-badge brand-2',
    //     domain: 'Manufacturing & Engineering',
    //     location: 'Chennai',
    //     type: 'Corporate',
    //     salary: '₹ 6,20,000',
    //     match: 89,
    //     logoText: 'H',
    //     totalCtc: 620000,
    //     breakdown: {
    //         fixed: 420000,
    //         variable: 150000,
    //         bonuses: 50000
    //     },
    //     attributes: [
    //         { icon: 'utility:checkin', text: 'Chennai' },
    //         { icon: 'utility:company', text: 'Corporate' },
    //         { icon: 'utility:trending', text: 'Structured growth with established learning programs' },
    //         { icon: 'utility:people', text: '8 alumni work here' }
    //     ],
    //     perks: ['Premium health insurance', 'Hybrid work support', 'Annual performance bonus'],
    //     joining: 'Dec 03, 2025',
    //     bond: 'No bond',
    //     acceptBy: 'Nov 11, 2025',
    //     questionLabel: 'Your question(s)',
    //     question: ''
    // },
    {
        id: 'offer-3',
        jobId: 3,
        title: 'Data Scientist',
        company: 'Reliance Industries',
        initials: 'R',
        badgeClass: 'brand-badge brand-3',
        domain: 'Consumer Goods',
        location: 'Bangalore',
        type: 'Corporate',
        salary: '₹ 10,00,000',
        match: 92,
        logoText: 'R',
        totalCtc: 1000000,
        breakdown: {
            fixed: 600000,
            variable: 200000,
            bonuses: 200000
        },
        attributes: [
            { icon: 'utility:checkin', text: 'Bangalore' },
            { icon: 'utility:company', text: 'Corporate' },
            { icon: 'utility:trending', text: 'Strong brand value with cross-functional exposure' },
            { icon: 'utility:people', text: '22 alumni work here' }
        ],
        perks: ['Comprehensive health coverage', 'Provident Fund', 'Annual performance bonus'],
        joining: 'Jan 03, 2026',
        bond: '3 years',
        acceptBy: 'Nov 02, 2025',
        questionLabel: 'Your question(s)',
        question: ''
    }
];

// JSON-style dashboard payload used to switch section layout.
const JOBS_DASHBOARD_JSON = {
    savedJobsCount: 7,
    savedJobs: [
        {
            id: 'saved-1',
            jobId: 6,
            domain: 'Fintech',
            location: 'Remote',
            type: 'Startup'
        },
        {
            id: 'saved-2',
            jobId: 2,
            domain: 'Fintech',
            location: 'Remote',
            type: 'Startup'
        },
        {
            id: 'saved-3',
            jobId: 5,
            domain: 'Fintech',
            location: 'Remote',
            type: 'Startup'
        }
    ],
    applications: [
        {
            id: 'app-1',
            jobId: 1,
            status: 'Shortlisted',
            statusClass: 'application-status status-success',
            ctaLabel: 'View Details',
            ctaClass: 'application-cta application-cta--secondary'
        },
        {
            id: 'app-2',
            jobId: 3,
            status: 'Exam slot open',
            statusClass: 'application-status status-info',
            ctaLabel: 'Take Exam',
            ctaClass: 'application-cta application-cta--primary'
        },
        {
            id: 'app-3',
            jobId: 2,
            status: 'Offer Received',
            statusClass: 'application-status status-success',
            ctaLabel: 'View Offer',
            ctaClass: 'application-cta application-cta--primary'
        }
    ],
    placementSummary: {
        activeApplications: 3,
        offersReceived: 2,
        interviewsScheduled: 3,
        examsScheduled: 1
    },
    acceptedOffer: {
        jobId: 1,
        company: 'Paypal',
        offerLetterUrl: ''
    },
    offers: DEFAULT_COMPARISON_OFFERS,
    schedule: [
        {
            id: 'sched-1',
            title: 'Technical Interview',
            subtitle: 'PayPal Technical Interview scheduled for October 10, 2025, from 9:00 AM to 10:00 AM.',
            timeLabel: '11:28 am',
            callActionLabel: 'Join Call'
        },
        {
            id: 'sched-2',
            title: 'Career Launch Pad',
            subtitle: 'Career Launch Pad session with Rajesh Kumar on Oct 10, 2025, 9:00-10:00 AM at Room 20, Heritage Building.',
            timeLabel: '11:28 am'
        },
        {
            id: 'sched-3',
            title: 'Aptitude exam',
            subtitle: 'Reliance Industries Aptitude exam scheduled for October 25, 2025, from 9:00 AM to 10:00 AM.',
            timeLabel: '11:28 am'
        }
    ]
};

export default class JobsSection extends NavigationMixin(LightningElement) {
    @api dashboardJson;
    @api manualJobFlowPageApiName;
    @api stage = DEFAULT_STAGE;

    JobsNotFound2 = JobsNotFound2;
    JobsNotFound1 = JobsNotFound1;

    jobsTab = 'recommended';
    sideTab = 'applied';
    moduleTab = 'applications';
    isPostJobModalOpen = false;
    isOfferComparisonModalOpen = false;
    offerComparisonStep = 1;
    selectedComparisonOfferIds = [];
    comparisonQuestionInput = '';
    comparisonQuestions = [];
    jobs = ALL_JOBS.map((job) => ({
        ...job,
        isBookmarked: false
    }));

    connectedCallback() {
        getPrimaryColor().then((color) => {
            if (color?.primaryColor) {
                document.documentElement.style.setProperty('--primary-color', color.primaryColor);
            }
            if (color?.secondaryColor) {
                document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
            }
            if (color?.tertiaryColor) {
                document.documentElement.style.setProperty('--tertiary-color', color.tertiaryColor);
            }
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    get recommendedTabClass() {
        return `tab${this.jobsTab === 'recommended' ? ' active' : ''}`;
    }

    get allTabClass() {
        return `tab${this.jobsTab === 'all' ? ' active' : ''}`;
    }

    get appliedTabClass() {
        return `tab${this.sideTab === 'applied' ? ' active' : ''}`;
    }

    get savedTabClass() {
        return `tab${this.sideTab === 'saved' ? ' active' : ''}`;
    }

    get isAppliedTab() {
        return this.sideTab === 'applied';
    }

    get isSavedTab() {
        return this.sideTab === 'saved';
    }

    get visibleJobs() {
        if (this.jobsTab === 'recommended') {
            return this.jobs
                .filter((job) => RECOMMENDED_IDS.has(job.id))
                .map((job) => this.decorateJob(job));
        }
        return this.jobs.map((job) => this.decorateJob(job));
    }

    get currentStage() {
        const stageValue = Number(this.stage);
        if (!Number.isFinite(stageValue)) {
            return DEFAULT_STAGE;
        }

        return Math.max(JOBS_STAGES.FIRST_VISIT, Math.min(JOBS_STAGES.OFFER_ACCEPTED, Math.floor(stageValue)));
    }

    get hasAppliedJobs() {
        return this.currentStage >= JOBS_STAGES.APPLIED_ONLY;
    }

    get jobsCardBodyStyle() {
        const height = this.hasAppliedJobs
            ? 'calc(50vh - 99px)'
            : 'calc(100vh - 269px)';

        return `height: ${height};`;
    }

    get applicationsModuleTabClass() {
        return `tab${this.moduleTab === 'applications' ? ' active' : ''}`;
    }

    get savedJobsModuleTabClass() {
        return `tab${this.moduleTab === 'saved' ? ' active' : ''}`;
    }

    get isApplicationsModuleTab() {
        return this.moduleTab === 'applications';
    }

    get isSavedJobsModuleTab() {
        return this.moduleTab === 'saved';
    }

    get applicationsCount() {
        return this.dashboardData.applications.length;
    }

    get savedJobsCount() {
        if (this.dashboardData.savedJobs.length > 0) {
            return this.dashboardData.savedJobs.length;
        }
        return this.dashboardData.savedJobsCount;
    }

    get applicationCards() {
        return this.stageApplications.map((application) => {
            const job = this.jobs.find((item) => item.id === application.jobId);
            if (!job) {
                return null;
            }

            return {
                ...application,
                company: job.company,
                title: job.title,
                initials: job.initials,
                badgeClass: job.badgeClass
            };
        }).filter(Boolean);
    }

    get stageApplications() {
        if (this.currentStage === JOBS_STAGES.FIRST_VISIT) {
            return [];
        }

        if (this.currentStage === JOBS_STAGES.OFFER_RECEIVED) {
            return this.dashboardData.applications;
        }

        return this.dashboardData.applications.filter((application) => application.status !== 'Offer Received');
    }

    get placementSummary() {
        const summary = this.dashboardData.placementSummary;
        if (this.currentStage === JOBS_STAGES.PLACEMENT_SUMMARY) {
            return {
                ...summary,
                offersReceived: 0
            };
        }

        if (this.currentStage === JOBS_STAGES.OFFER_RECEIVED) {
            return {
                ...summary,
                offersReceived: Number(summary.offersReceived) || this.comparisonOffers.length || 1
            };
        }

        return summary;
    }

    get showPlacementSummary() {
        return this.currentStage >= JOBS_STAGES.PLACEMENT_SUMMARY;
    }

    get hasAcceptedOffer() {
        return this.currentStage === JOBS_STAGES.OFFER_ACCEPTED && Boolean(this.dashboardData.acceptedOffer);
    }

    get acceptedOffer() {
        if (!this.hasAcceptedOffer) {
            return null;
        }

        const offer = this.dashboardData.acceptedOffer;
        const job = this.jobs.find((item) => item.id === offer.jobId) || {};
        const company = offer.company || job.company || '';

        return {
            ...offer,
            company,
            role: offer.role || job.title || '',
            initials: offer.initials || job.initials || (company ? company.charAt(0) : 'J'),
            badgeClass: offer.badgeClass || job.badgeClass || 'brand-badge brand-1'
        };
    }

    get hasReceivedOffers() {
        return this.currentStage === JOBS_STAGES.OFFER_RECEIVED;
    }

    get placementSummaryCardClass() {
        if (this.hasAcceptedOffer) {
            return 'placement-summary placement-summary--accepted';
        }

        return `placement-summary${this.hasReceivedOffers ? ' placement-summary--offers' : ''}`;
    }

    get acceptedOfferMessage() {
        return this.acceptedOffer?.company
            ? `You've accepted an offer with ${this.acceptedOffer.company}`
            : 'You\'ve accepted an offer';
    }

    get showJobsListingSection() {
        return this.currentStage !== JOBS_STAGES.OFFER_ACCEPTED;
    }

    get jobsCardStyle() {
        if (this.hasAcceptedOffer) {
            return 'height: calc(53vh - 7px); overflow-y: auto;';
        }

        return '';
    }

    get instructionsNextSteps() {
        return INSTRUCTIONS_NEXT_STEPS;
    }

    get instructionsSupportPolicies() {
        return INSTRUCTIONS_SUPPORT_POLICIES;
    }

    get canCompareOffers() {
        return this.comparisonOffers.length > 1;
    }

    get disableCompareOffersLaunch() {
        return !this.canCompareOffers;
    }

    get comparisonOffers() {
        return this.dashboardData.offers.map((offer, index) => this.decorateComparisonOffer(offer, index));
    }

    get comparisonOfferSelectionCards() {
        const selectedIds = new Set(this.selectedComparisonOfferIds);
        return this.comparisonOffers.map((offer) => {
            const isSelected = selectedIds.has(offer.id);
            return {
                ...offer,
                isSelected,
                selectionClass: `offer-selection-card${isSelected ? ' offer-selection-card--selected' : ''}`,
                selectionLabel: isSelected ? 'Selected' : 'Select'
            };
        });
    }

    get isOfferComparisonStepOne() {
        return this.offerComparisonStep === 1;
    }

    get isOfferComparisonStepTwo() {
        return this.offerComparisonStep === 2;
    }

    get disableOfferComparisonContinue() {
        return this.selectedComparisonOfferIds.length < 2;
    }

    get comparisonQuestionsWithIndex() {
        return this.comparisonQuestions.map((question, index) => ({
            id: `question-${index + 1}`,
            index: index + 1,
            text: question
        }));
    }

    get nextComparisonQuestionNumber() {
        return this.comparisonQuestions.length + 1;
    }

    get scheduleItems() {
        return this.dashboardData.schedule;
    }

    get moduleSavedJobCards() {
        return this.dashboardData.savedJobs.map((savedJob, index) => {
            const job = this.jobs.find((item) => item.id === savedJob.jobId) || {};
            const fallbackBadgeClass = `brand-badge brand-${(index % 6) + 1}`;
            const company = savedJob.company || job.company || '';
            return {
                id: savedJob.id || `saved-${index + 1}`,
                badgeClass: savedJob.badgeClass || job.badgeClass || fallbackBadgeClass,
                initials: savedJob.initials || job.initials || (company ? company.charAt(0) : 'J'),
                company,
                title: savedJob.title || job.title || '',
                domain: savedJob.domain || job.domain || '',
                location: savedJob.location || job.location || '',
                type: savedJob.type || job.type || '',
                salary: savedJob.salary || job.salary || ''
            };
        });
    }

    get hasModuleSavedJobs() {
        return this.moduleSavedJobCards.length > 0;
    }

    get noModuleSavedJobs() {
        return !this.hasModuleSavedJobs;
    }

    get savedJobs() {
        return this.jobs.filter((job) => job.isBookmarked).map((job) => this.decorateJob(job));
    }

    get hasSavedJobs() {
        return this.savedJobs.length > 0;
    }

    get noSavedJobs() {
        return !this.hasSavedJobs;
    }

    handleJobsTabClick(event) {
        const nextTab = event.currentTarget.dataset.tab;
        if (nextTab && nextTab !== this.jobsTab) {
            this.jobsTab = nextTab;
        }
    }

    handleSideTabClick(event) {
        const nextTab = event.currentTarget.dataset.tab;
        if (nextTab && nextTab !== this.sideTab) {
            this.sideTab = nextTab;
        }
    }

    handleModuleTabClick(event) {
        const nextTab = event.currentTarget.dataset.tab;
        if (nextTab && nextTab !== this.moduleTab) {
            this.moduleTab = nextTab;
        }
    }

    handleBookmarkToggle(event) {
        event.stopPropagation();
        const id = Number(event.currentTarget.dataset.id);
        this.jobs = this.jobs.map((job) =>
            job.id === id ? { ...job, isBookmarked: !job.isBookmarked } : job
        );
    }

    handleJobCardClick(event) {
        const jobId = event.currentTarget.dataset.id;
        if (!jobId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'job_detail__c'
            },
            state: {
                jobId
            }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'all_jobs__c' }
        });
    }

    handleApplicationsViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'all_applications__c' }
        });
    }

    handleDownloadOfferLetter() {
        const offerLetterUrl = this.acceptedOffer?.offerLetterUrl;
        if (offerLetterUrl && typeof window !== 'undefined') {
            window.open(offerLetterUrl, '_blank');
        }
    }

    handleOpenOfferComparisonModal() {
        if (!this.canCompareOffers) {
            return;
        }

        this.offerComparisonStep = 1;
        this.selectedComparisonOfferIds = [];
        this.comparisonQuestionInput = '';
        this.comparisonQuestions = [];
        this.isOfferComparisonModalOpen = true;
    }

    closeOfferComparisonModal() {
        this.resetOfferComparisonState();
    }

    handleOfferSelectionToggle(event) {
        const offerId = event.currentTarget.dataset.id;
        if (!offerId) {
            return;
        }

        const selectedIds = new Set(this.selectedComparisonOfferIds);
        if (selectedIds.has(offerId)) {
            selectedIds.delete(offerId);
        } else if (selectedIds.size < 3) {
            selectedIds.add(offerId);
        }

        this.selectedComparisonOfferIds = [...selectedIds];
    }

    handleOfferComparisonContinue() {
        if (this.disableOfferComparisonContinue) {
            return;
        }

        this.offerComparisonStep = 2;
    }

    handleOfferComparisonBack() {
        this.offerComparisonStep = 1;
    }

    handleComparisonQuestionInput(event) {
        this.comparisonQuestionInput = event.target.value;
    }

    handleComparisonQuestionKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.commitComparisonQuestion();
        }
    }

    handleFinalizeOfferComparison() {
        if (this.disableOfferComparisonContinue) {
            return;
        }

        const comparisonQuestions = this.getComparisonQuestionsForNavigation();
        const selectedOffers = this.comparisonOffers
            .filter((offer) => this.selectedComparisonOfferIds.includes(offer.id))
            .map((offer) => ({
                ...offer,
                question: comparisonQuestions.join(' | ')
            }));

        this.resetOfferComparisonState();
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'offers_comparison__c'
            },
            state: {
                selectedOffers: JSON.stringify(selectedOffers),
                comparisonQuestions: JSON.stringify(comparisonQuestions)
            }
        });
    }

    handlePostJob() {
        this.isPostJobModalOpen = true;
    }

    closePostJobModal() {
        this.isPostJobModalOpen = false;
    }

    handleCreateManually() {
        this.isPostJobModalOpen = false;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'PostJob__c'
            }
        });
    }

    handleUploadJobDescription() {
        this.isPostJobModalOpen = false;
    }

    get dashboardData() {
        if (!this.dashboardJson) {
            return JOBS_DASHBOARD_JSON;
        }

        const parsed = typeof this.dashboardJson === 'string'
            ? this.parseDashboardJson(this.dashboardJson)
            : this.dashboardJson;

        if (!parsed || typeof parsed !== 'object') {
            return JOBS_DASHBOARD_JSON;
        }

        return {
            savedJobsCount: Number(parsed.savedJobsCount) || 0,
            savedJobs: Array.isArray(parsed.savedJobs) ? parsed.savedJobs : [],
            applications: Array.isArray(parsed.applications) ? parsed.applications : [],
            placementSummary: {
                activeApplications: parsed.placementSummary?.activeApplications ?? 0,
                offersReceived: parsed.placementSummary?.offersReceived ?? 0,
                interviewsScheduled: parsed.placementSummary?.interviewsScheduled ?? 0,
                examsScheduled: parsed.placementSummary?.examsScheduled ?? 0
            },
            acceptedOffer: parsed.acceptedOffer && typeof parsed.acceptedOffer === 'object'
                ? parsed.acceptedOffer
                : null,
            offers: Array.isArray(parsed.offers) && parsed.offers.length > 0
                ? parsed.offers
                : this.buildOffersFromApplications(Array.isArray(parsed.applications) ? parsed.applications : []),
            schedule: Array.isArray(parsed.schedule) ? parsed.schedule : []
        };
    }

    parseDashboardJson(value) {
        try {
            return JSON.parse(value);
        } catch (error) {
            return null;
        }
    }

    decorateJob(job) {
        const isBookmarked = job.isBookmarked === true;
        return {
            ...job,
            isBookmarked,
            bookmarkIcon: 'utility:bookmark',
            bookmarkClass: `bookmark-btn${isBookmarked ? ' bookmarked' : ''}`
        };
    }

    decorateComparisonOffer(offer, index) {
        const job = this.jobs.find((item) => item.id === offer.jobId) || {};
        const company = offer.company || job.company || '';
        const fallbackBadgeClass = `brand-badge brand-${(index % 6) + 1}`;
        const totalCtc = Number(offer.totalCtc);
        const resolvedSalary = offer.salary || (Number.isFinite(totalCtc) ? this.formatInr(totalCtc) : job.salary || '');

        return {
            ...offer,
            id: offer.id || `offer-${index + 1}`,
            jobId: offer.jobId || job.id,
            company,
            role: offer.role || offer.title || job.title || '',
            title: offer.title || job.title || '',
            initials: offer.initials || job.initials || (company ? company.charAt(0) : 'J'),
            badgeClass: offer.badgeClass || job.badgeClass || fallbackBadgeClass,
            logoText: offer.logoText || offer.initials || job.initials || (company ? company.charAt(0) : 'J'),
            domain: offer.domain || job.domain || '',
            location: offer.location || job.location || '',
            type: offer.type || job.type || '',
            salary: resolvedSalary,
            match: offer.match ?? job.match ?? 0
        };
    }

    buildOffersFromApplications(applications) {
        if (!applications.length) {
            return DEFAULT_COMPARISON_OFFERS;
        }

        return applications.slice(0, 3).map((application, index) => {
            const job = this.jobs.find((item) => item.id === application.jobId) || {};
            const totalCtc = this.parseSalaryToNumber(job.salary) || 600000 + (index * 120000);
            const fixed = Math.round(totalCtc * 0.6);
            const variable = Math.round(totalCtc * 0.2);
            const bonuses = totalCtc - fixed - variable;
            const company = job.company || `Company ${index + 1}`;
            const initials = job.initials || company.charAt(0) || 'J';

            return {
                id: application.id || `offer-${index + 1}`,
                jobId: job.id,
                role: job.title || `Role ${index + 1}`,
                title: job.title || `Role ${index + 1}`,
                company,
                initials,
                badgeClass: job.badgeClass || `brand-badge brand-${(index % 6) + 1}`,
                domain: job.domain || 'Information Technology',
                location: job.location || 'Remote',
                type: job.type || 'Corporate',
                salary: this.formatInr(totalCtc),
                match: job.match ?? 80,
                logoText: initials,
                totalCtc,
                breakdown: {
                    fixed,
                    variable,
                    bonuses
                },
                attributes: [
                    { icon: 'utility:checkin', text: job.location || 'Remote' },
                    { icon: 'utility:company', text: job.type || 'Corporate' },
                    { icon: 'utility:trending', text: `${company} offer ready for comparison` },
                    { icon: 'utility:people', text: 'Alumni insights available' }
                ],
                perks: ['Health insurance', 'Performance bonus', 'Learning support'],
                joining: 'Jan 01, 2026',
                bond: 'No bond',
                acceptBy: 'Nov 15, 2025',
                questionLabel: 'Your question(s)',
                question: ''
            };
        });
    }

    formatInr(value) {
        const amount = Number(value);
        if (!Number.isFinite(amount)) {
            return '';
        }

        return `₹ ${new Intl.NumberFormat('en-IN').format(amount)}`;
    }

    parseSalaryToNumber(value) {
        if (!value) {
            return null;
        }

        const matches = String(value).match(/[\d,]+/g);
        if (!matches || !matches.length) {
            return null;
        }

        const lastValue = matches[matches.length - 1].replace(/,/g, '');
        const parsed = Number(lastValue);
        return Number.isFinite(parsed) ? parsed : null;
    }

    commitComparisonQuestion() {
        const question = this.comparisonQuestionInput.trim();
        if (!question) {
            return;
        }

        this.comparisonQuestions = [...this.comparisonQuestions, question];
        this.comparisonQuestionInput = '';
    }

    getComparisonQuestionsForNavigation() {
        const draftQuestion = this.comparisonQuestionInput.trim();
        return draftQuestion
            ? [...this.comparisonQuestions, draftQuestion]
            : [...this.comparisonQuestions];
    }

    resetOfferComparisonState() {
        this.isOfferComparisonModalOpen = false;
        this.offerComparisonStep = 1;
        this.selectedComparisonOfferIds = [];
        this.comparisonQuestionInput = '';
        this.comparisonQuestions = [];
    }
}