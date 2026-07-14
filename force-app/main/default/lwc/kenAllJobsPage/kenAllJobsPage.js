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
    appliedShowMentors = false;
    companyTypeSelection = { ...DEFAULT_COMPANY_TYPES };
    appliedCompanyTypeSelection = { ...DEFAULT_COMPANY_TYPES };
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
    appliedFilters = {
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
        const selected = Object.entries(this.appliedCompanyTypeSelection)
            .filter(([, value]) => value)
            .map(([key]) => (key === 'Startup' ? 'Startups' : `${key}s`));
        return selected.length ? selected.join(', ') : 'Company Type';
    }

    get appliedFilterCount() {
        const companyTypeCount = Object.values(this.appliedCompanyTypeSelection).filter(Boolean).length;
        const formCount = Object.values(this.appliedFilters).filter((value) => Boolean(value)).length;
        const mentorCount = this.appliedShowMentors ? 1 : 0;
        return companyTypeCount + formCount + mentorCount;
    }

    get hasAppliedFilters() {
        return this.appliedFilterCount > 0;
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
        const activeTypes = Object.entries(this.appliedCompanyTypeSelection)
            .filter(([, value]) => value)
            .map(([key]) => key);

        const filteredByType = activeTypes.length
            ? this.jobs.filter((job) => activeTypes.includes(job.type))
            : this.jobs;

        const filteredByForm = filteredByType.filter((job) => {
            if (this.appliedFilters.company && job.company !== this.appliedFilters.company) {
                return false;
            }
            if (this.appliedFilters.industry && job.industry !== this.appliedFilters.industry) {
                return false;
            }
            if (this.appliedFilters.jobFunction && job.jobFunction !== this.appliedFilters.jobFunction) {
                return false;
            }
            if (this.appliedFilters.program && job.program !== this.appliedFilters.program) {
                return false;
            }
            if (this.appliedFilters.specialization && job.specialization !== this.appliedFilters.specialization) {
                return false;
            }
            if (this.appliedFilters.graduationYear && job.graduationYear !== this.appliedFilters.graduationYear) {
                return false;
            }
            if (this.appliedFilters.city && job.city !== this.appliedFilters.city) {
                return false;
            }
            if (this.appliedShowMentors && job.city !== 'Chennai') {
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
        const opening = !this.filtersOpen;
        if (opening) {
            this.syncDraftFromApplied();
        }
        this.filtersOpen = opening;
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
        this._applyDraftLive();
    }

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        this.filters = {
            ...this.filters,
            [field]: event.target.value
        };
        this._applyDraftLive();
    }

    handleBookmarkToggle(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.jobs = this.jobs.map((job) =>
            job.id === id ? { ...job, isBookmarked: !job.isBookmarked } : job
        );
    }

    toggleMentors(event) {
        this.showMentors = event.target.checked;
        this._applyDraftLive();
    }

    resetFilters() {
        this.companyTypeSelection = { ...DEFAULT_COMPANY_TYPES };
        this.appliedCompanyTypeSelection = { ...DEFAULT_COMPANY_TYPES };
        this.showMentors = false;
        this.appliedShowMentors = false;
        this.filters = {
            company: '',
            industry: '',
            jobFunction: '',
            program: '',
            specialization: '',
            graduationYear: '',
            city: ''
        };
        this.appliedFilters = {
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
        this._applyDraftLive();
        this.filtersOpen = false;
    }

    // Mirrors the draft filter state (filters/companyTypeSelection/showMentors) into the
    // applied state that filteredJobs reads, so picking a value filters live instead of
    // waiting for the Apply button. filteredJobs is a plain getter over an in-memory array,
    // so reassigning these fields is enough to trigger recomputation on next render.
    _applyDraftLive() {
        this.appliedFilters = { ...this.filters };
        this.appliedCompanyTypeSelection = { ...this.companyTypeSelection };
        this.appliedShowMentors = this.showMentors;
    }

    get selectedFilterPills() {
        const pills = [];

        if (this.showMentors) {
            pills.push({ key: 'showMentors', label: 'Mentors near me', category: 'toggle' });
        }

        Object.entries(this.companyTypeSelection)
            .filter(([, selected]) => selected)
            .forEach(([type]) => {
                pills.push({
                    key: type,
                    label: `Type: ${type}`,
                    category: 'companyType'
                });
            });

        Object.entries(this.filters)
            .filter(([, value]) => Boolean(value))
            .forEach(([field, value]) => {
                pills.push({
                    key: field,
                    label: `${this.getFilterLabel(field)}: ${value}`,
                    category: 'field'
                });
            });

        return pills;
    }

    get hasSelectedFilterPills() {
        return this.selectedFilterPills.length > 0;
    }

    handlePillRemove(event) {
        const key = event.currentTarget.dataset.key;
        const category = event.currentTarget.dataset.category;

        if (category === 'toggle' && key === 'showMentors') {
            this.showMentors = false;
            return;
        }

        if (category === 'companyType') {
            this.companyTypeSelection = {
                ...this.companyTypeSelection,
                [key]: false
            };
            return;
        }

        if (category === 'field') {
            this.filters = {
                ...this.filters,
                [key]: ''
            };
        }
    }

    syncDraftFromApplied() {
        this.filters = { ...this.appliedFilters };
        this.companyTypeSelection = { ...this.appliedCompanyTypeSelection };
        this.showMentors = this.appliedShowMentors;
    }

    getFilterLabel(field) {
        const labels = {
            company: 'Company',
            industry: 'Industry',
            jobFunction: 'Job function',
            program: 'Program',
            specialization: 'Specialisation',
            graduationYear: 'Graduation year',
            city: 'City'
        };
        return labels[field] || field;
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