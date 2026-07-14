import { LightningElement } from 'lwc';

const JOBS = [
    {
        id: 1,
        company: 'Paypal',
        initials: 'P',
        badgeClass: 'brand-badge brand-1',
        title: 'Developer',
        jobFunction: 'Engineering',
        industry: 'Information Technology',
        program: 'Alumni Connect 2023',
        specialization: 'Full Stack',
        graduationYear: '2020',
        city: 'Remote',
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
        jobFunction: 'Engineering',
        industry: 'Manufacturing & Engineering',
        program: 'Tech Leaders 2022',
        specialization: 'Backend',
        graduationYear: '2019',
        city: 'Chennai',
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
        jobFunction: 'Data Science',
        industry: 'Consumer Goods',
        program: 'Analytics Summit 2023',
        specialization: 'Machine Learning',
        graduationYear: '2021',
        city: 'Bangalore',
        location: 'Bangalore',
        type: 'Corporate',
        salary: '₹ 7,00,000 - ₹ 10,00,000',
        match: 84
    },
    {
        id: 4,
        company: 'Reliance Industries',
        initials: 'R',
        badgeClass: 'brand-badge brand-3',
        title: 'Data Analyst',
        jobFunction: 'Data Analytics',
        industry: 'Consumer Goods',
        program: 'Analytics Summit 2023',
        specialization: 'Business Analytics',
        graduationYear: '2020',
        city: 'Bangalore',
        location: 'Bangalore',
        type: 'Corporate',
        salary: '₹ 8,00,000 - ₹ 12,00,000',
        match: 84
    },
    {
        id: 5,
        company: 'Infosys',
        initials: 'I',
        badgeClass: 'brand-badge brand-4',
        title: 'Cloud Specialist',
        jobFunction: 'Cloud Engineering',
        industry: 'Information Technology',
        program: 'Cloud Expo 2022',
        specialization: 'DevOps',
        graduationYear: '2018',
        city: 'Delhi NCR',
        location: 'Delhi NCR',
        type: 'Corporate',
        salary: '₹ 4,50,000 - ₹ 7,50,000',
        match: 60
    },
    {
        id: 6,
        company: 'Google',
        initials: 'G',
        badgeClass: 'brand-badge brand-5',
        title: 'Security Analyst',
        jobFunction: 'Security',
        industry: 'Information Technology',
        program: 'Security Week 2021',
        specialization: 'Cybersecurity',
        graduationYear: '2017',
        city: 'Hybrid',
        location: 'Hybrid',
        type: 'Corporate',
        salary: '₹ 8,00,000 LPA',
        match: 54
    },
    {
        id: 7,
        company: 'Wipro',
        initials: 'W',
        badgeClass: 'brand-badge brand-6',
        title: 'Network Architect',
        jobFunction: 'Networking',
        industry: 'EdTech',
        program: 'Campus Hiring 2022',
        specialization: 'Networks',
        graduationYear: '2019',
        city: 'Chennai',
        location: 'Chennai',
        type: 'Corporate',
        salary: '₹ 6,50,000 LPA',
        match: 0
    },
    {
        id: 8,
        company: 'Wipro',
        initials: 'W',
        badgeClass: 'brand-badge brand-6',
        title: 'Software Developer',
        jobFunction: 'Engineering',
        industry: 'EdTech',
        program: 'Campus Hiring 2022',
        specialization: 'Frontend',
        graduationYear: '2020',
        city: 'Chennai',
        location: 'Chennai',
        type: 'Corporate',
        salary: '₹ 7,20,000 per annum',
        match: 0
    },
    {
        id: 9,
        company: 'Infosys',
        initials: 'I',
        badgeClass: 'brand-badge brand-4',
        title: 'Cloud Engineer',
        jobFunction: 'Cloud Engineering',
        industry: 'Information Technology',
        program: 'Cloud Expo 2022',
        specialization: 'DevOps',
        graduationYear: '2021',
        city: 'Delhi NCR',
        location: 'Delhi NCR',
        type: 'Corporate',
        salary: '₹ 5,00,000 - ₹ 8,00,000',
        match: 78
    },
    {
        id: 10,
        company: 'Google',
        initials: 'G',
        badgeClass: 'brand-badge brand-5',
        title: 'Cybersecurity Analyst',
        jobFunction: 'Security',
        industry: 'Information Technology',
        program: 'Security Week 2021',
        specialization: 'Cybersecurity',
        graduationYear: '2018',
        city: 'Hybrid',
        location: 'Hybrid',
        type: 'Corporate',
        salary: '₹ 9,00,000 per annum',
        match: 93
    },
    {
        id: 11,
        company: 'Wipro',
        initials: 'W',
        badgeClass: 'brand-badge brand-6',
        title: 'Mobile App Developer',
        jobFunction: 'Engineering',
        industry: 'EdTech',
        program: 'Campus Hiring 2022',
        specialization: 'Mobile',
        graduationYear: '2022',
        city: 'Chennai',
        location: 'Chennai',
        type: 'Corporate',
        salary: '₹ 7,50,000 per annum',
        match: 70
    },
    {
        id: 12,
        company: 'Wipro',
        initials: 'W',
        badgeClass: 'brand-badge brand-6',
        title: 'Web Developer',
        jobFunction: 'Engineering',
        industry: 'EdTech',
        program: 'Campus Hiring 2022',
        specialization: 'Frontend',
        graduationYear: '2023',
        city: 'Chennai',
        location: 'Chennai',
        type: 'Corporate',
        salary: '₹ 7,00,000 per annum',
        match: 65
    }
];

const DEFAULT_COMPANY_TYPES = {
    Startup: false,
    Corporate: false,
    SME: false,
    PSU: false
};

export default class AllJobsPage extends LightningElement {
    viewMode = 'card';
    filtersOpen = false;
    isCompanyTypeOpen = false;
    showMentors = false;
    companyTypeSelection = { ...DEFAULT_COMPANY_TYPES };
    jobs = JOBS.map((job) => ({ ...job, isBookmarked: false }));
    filters = {
        company: '',
        industry: '',
        jobFunction: '',
        program: '',
        specialization: '',
        graduationYear: '',
        city: ''
    };

    get isCardView() {
        return this.viewMode === 'card';
    }

    get isListView() {
        return this.viewMode === 'list';
    }

    get cardViewClass() {
        return `view-btn${this.isCardView ? ' active' : ''}`;
    }

    get listViewClass() {
        return `view-btn${this.isListView ? ' active' : ''}`;
    }

    get filterButtonClass() {
        return `filter-btn${this.filtersOpen ? ' active' : ''}`;
    }

    get companyTypeLabel() {
        const selected = Object.entries(this.companyTypeSelection)
            .filter(([, value]) => value)
            .map(([key]) => (key === 'Startup' ? 'Startups' : `${key}s`));
        return selected.length ? selected.join(', ') : 'Company Type';
    }

    get companyOptions() {
        return this.getUniqueOptions('company');
    }

    get industryOptions() {
        return this.getUniqueOptions('industry');
    }

    get jobFunctionOptions() {
        return this.getUniqueOptions('jobFunction');
    }

    get programOptions() {
        return this.getUniqueOptions('program');
    }

    get specializationOptions() {
        return this.getUniqueOptions('specialization');
    }

    get graduationYearOptions() {
        return this.getUniqueOptions('graduationYear');
    }

    get cityOptions() {
        return this.getUniqueOptions('city');
    }

    get filteredJobs() {
        const activeTypes = Object.entries(this.companyTypeSelection)
            .filter(([, value]) => value)
            .map(([key]) => key);

        const filteredByType = activeTypes.length
            ? this.jobs.filter((job) => activeTypes.includes(job.type))
            : this.jobs;

        const filteredByForm = filteredByType.filter((job) => {
            if (this.filters.company && job.company !== this.filters.company) {
                return false;
            }
            if (this.filters.industry && job.industry !== this.filters.industry) {
                return false;
            }
            if (this.filters.jobFunction && job.jobFunction !== this.filters.jobFunction) {
                return false;
            }
            if (this.filters.program && job.program !== this.filters.program) {
                return false;
            }
            if (this.filters.specialization && job.specialization !== this.filters.specialization) {
                return false;
            }
            if (this.filters.graduationYear && job.graduationYear !== this.filters.graduationYear) {
                return false;
            }
            if (this.filters.city && job.city !== this.filters.city) {
                return false;
            }
            if (this.showMentors && job.city !== 'Chennai') {
                return false;
            }
            return true;
        });

        return filteredByForm.map((job) => this.decorateJob(job));
    }

    handleCardView() {
        this.viewMode = 'card';
    }

    handleListView() {
        this.viewMode = 'list';
    }

    toggleFilters() {
        this.filtersOpen = !this.filtersOpen;
    }

    toggleCompanyTypeMenu() {
        this.isCompanyTypeOpen = !this.isCompanyTypeOpen;
    }

    handleCompanyTypeChange(event) {
        const type = event.target.dataset.type;
        this.companyTypeSelection = {
            ...this.companyTypeSelection,
            [type]: event.target.checked
        };
    }

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        this.filters = {
            ...this.filters,
            [field]: event.target.value
        };
    }

    handleBookmarkToggle(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.jobs = this.jobs.map((job) =>
            job.id === id ? { ...job, isBookmarked: !job.isBookmarked } : job
        );
    }

    toggleMentors(event) {
        this.showMentors = event.target.checked;
    }

    resetFilters() {
        this.companyTypeSelection = { ...DEFAULT_COMPANY_TYPES };
        this.showMentors = false;
        this.filters = {
            company: '',
            industry: '',
            jobFunction: '',
            program: '',
            specialization: '',
            graduationYear: '',
            city: ''
        };
    }

    applyFilters() {
        this.filtersOpen = false;
    }

    getUniqueOptions(field) {
        const values = Array.from(new Set(this.jobs.map((job) => job[field]).filter(Boolean)));
        return values.map((value) => ({ label: value, value }));
    }

    decorateJob(job) {
        const isEligible = job.match > 0;
        return {
            ...job,
            matchClass: `match-icon${isEligible ? ' success' : ' fail'}`,
            matchIcon: isEligible ? 'utility:check' : 'utility:close',
            matchText: isEligible ? `Skills match: ${job.match}%` : 'Not eligible',
            bookmarkClass: `bookmark-btn${job.isBookmarked ? ' bookmarked' : ''}`
        };
    }
}