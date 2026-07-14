import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import JobsNotFound2 from '@salesforce/resourceUrl/JobsNotFound2';
import JobsNotFound1 from '@salesforce/resourceUrl/JobsNotFound1';

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
    {
        id: 2,
        company: 'Hindustan Unilever',
        initials: 'H',
        badgeClass: 'brand-badge brand-2',
        title: 'Software Engineer',
        domain: 'Manufacturing & Engineering',
        location: 'Chennai',
        type: 'Corporate',
        salary: '₹ 6,20,000 - ₹ 9,50,000',
        match: 87
    },
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

export default class JobsSection extends NavigationMixin(LightningElement) {
    JobsNotFound2 = JobsNotFound2;
    JobsNotFound1 = JobsNotFound1;

    jobsTab = 'recommended';
    sideTab = 'applied';
    jobs = ALL_JOBS.map((job) => ({
        ...job,
        isBookmarked: false
    }));

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

    handleBookmarkToggle(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.jobs = this.jobs.map((job) =>
            job.id === id ? { ...job, isBookmarked: !job.isBookmarked } : job
        );
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'ViewAllJobs__c' }
        });
    }

    handlePostJob() {
        // Placeholder for future navigation or modal.
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
}