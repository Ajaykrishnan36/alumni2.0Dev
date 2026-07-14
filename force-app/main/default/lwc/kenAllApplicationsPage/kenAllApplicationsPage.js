import { LightningElement } from 'lwc';

const COMPANY_TYPES = ['Startup', 'Corporate', 'SME', 'PSU'];

const DEFAULT_FILTERS = {
    company: '',
    industry: '',
    jobFunction: '',
    program: '',
    specialization: '',
    graduationYear: '',
    city: ''
};

const APPLICATIONS = [
    {
        id: 1,
        company: 'Google',
        companyInitial: 'G',
        logoClass: 'logo logo-google',
        profile: 'Associate UX/UI designer',
        appliedOn: '03 Oct, 2025',
        companyType: 'Corporate',
        industry: 'Technology',
        jobFunction: 'Design',
        program: 'Design Connect 2024',
        specialization: 'UX',
        graduationYear: '2021',
        city: 'Bangalore',
        mentorNearMe: true,
        stageLabel: 'HR interview',
        stageClass: 'stage-chip stage-blue',
        actions: [
            { id: 'book', label: 'Book Slot', className: 'action-btn action-outline-blue' },
            { id: 'withdraw', label: 'Withdraw', className: 'action-btn action-outline-red' }
        ]
    },
    {
        id: 2,
        company: 'Tata Consultancy Services',
        companyInitial: 'T',
        logoClass: 'logo logo-tcs',
        profile: 'UX/UI designer',
        appliedOn: '03 Oct, 2025',
        companyType: 'Corporate',
        industry: 'Technology',
        jobFunction: 'Design',
        program: 'Design Connect 2024',
        specialization: 'UI',
        graduationYear: '2020',
        city: 'Chennai',
        mentorNearMe: false,
        stageLabel: 'Advanced to Interview R1',
        stageClass: 'stage-chip stage-green',
        actions: [
            { id: 'book', label: 'Book Slot', className: 'action-btn action-outline-blue' },
            { id: 'withdraw', label: 'Withdraw', className: 'action-btn action-outline-red' }
        ]
    },
    {
        id: 3,
        company: 'Infosys',
        companyInitial: 'I',
        logoClass: 'logo logo-infosys',
        profile: 'UI designer',
        appliedOn: '03 Oct, 2025',
        companyType: 'Corporate',
        industry: 'Technology',
        jobFunction: 'Design',
        program: 'Campus Hiring 2023',
        specialization: 'UI',
        graduationYear: '2019',
        city: 'Pune',
        mentorNearMe: false,
        stageLabel: 'Rejected',
        stageClass: 'stage-chip stage-red',
        actions: []
    },
    {
        id: 4,
        company: 'Wipro',
        companyInitial: 'W',
        logoClass: 'logo logo-wipro',
        profile: 'UX designer',
        appliedOn: '03 Oct, 2025',
        companyType: 'Corporate',
        industry: 'IT Services',
        jobFunction: 'Design',
        program: 'Campus Hiring 2023',
        specialization: 'UX',
        graduationYear: '2022',
        city: 'Hyderabad',
        mentorNearMe: true,
        stageLabel: 'In review',
        stageClass: 'stage-chip stage-yellow',
        actions: []
    },
    {
        id: 5,
        company: 'Zoho Corporation',
        companyInitial: 'Z',
        logoClass: 'logo logo-zoho',
        profile: 'Product designer',
        appliedOn: '03 Oct, 2025',
        companyType: 'Startup',
        industry: 'SaaS',
        jobFunction: 'Product Design',
        program: 'Product Guild 2024',
        specialization: 'Product',
        graduationYear: '2023',
        city: 'Chennai',
        mentorNearMe: true,
        stageLabel: 'Aptitude test',
        stageClass: 'stage-chip stage-blue',
        actions: [
            { id: 'exam', label: 'Take Exam', className: 'action-btn action-outline-blue' },
            { id: 'withdraw', label: 'Withdraw', className: 'action-btn action-outline-red' }
        ]
    },
    {
        id: 6,
        company: 'Reddit',
        companyInitial: 'R',
        logoClass: 'logo logo-reddit',
        profile: 'Junior designer',
        appliedOn: '03 Oct, 2025',
        companyType: 'Startup',
        industry: 'Social Media',
        jobFunction: 'Design',
        program: 'Global Product Program',
        specialization: 'Visual Design',
        graduationYear: '2024',
        city: 'Remote',
        mentorNearMe: false,
        stageLabel: 'Job offer received',
        stageClass: 'stage-chip stage-outline',
        actions: [
            { id: 'accept', label: 'Accept Offer', className: 'action-btn action-fill-blue' },
            { id: 'review', label: 'Review Offer', className: 'action-btn action-outline-blue' }
        ]
    },
    {
        id: 7,
        company: 'CraftHub SME',
        companyInitial: 'C',
        logoClass: 'logo logo-sme',
        profile: 'Brand designer',
        appliedOn: '06 Oct, 2025',
        companyType: 'SME',
        industry: 'Retail',
        jobFunction: 'Branding',
        program: 'Design Connect 2024',
        specialization: 'Brand Design',
        graduationYear: '2020',
        city: 'Mumbai',
        mentorNearMe: true,
        stageLabel: 'In review',
        stageClass: 'stage-chip stage-yellow',
        actions: []
    },
    {
        id: 8,
        company: 'State Tech PSU',
        companyInitial: 'S',
        logoClass: 'logo logo-psu',
        profile: 'UI designer',
        appliedOn: '10 Oct, 2025',
        companyType: 'PSU',
        industry: 'Public Sector',
        jobFunction: 'Design',
        program: 'Public Hiring Program',
        specialization: 'UI',
        graduationYear: '2018',
        city: 'Delhi',
        mentorNearMe: false,
        stageLabel: 'HR interview',
        stageClass: 'stage-chip stage-blue',
        actions: [
            { id: 'book', label: 'Book Slot', className: 'action-btn action-outline-blue' }
        ]
    }
];

function toOptions(data, key) {
    const values = [...new Set(data.map((item) => item[key]).filter(Boolean))].sort();
    return values.map((value) => ({ label: value, value }));
}

export default class KenAllApplicationsPage extends LightningElement {
    isCompanyTypeOpen = false;
    isFiltersOpen = false;

    selectedCompanyTypes = [];

    appliedShowMentors = false;
    draftShowMentors = false;

    appliedFilters = { ...DEFAULT_FILTERS };
    draftFilters = { ...DEFAULT_FILTERS };

    get companyTypeLabel() {
        if (this.selectedCompanyTypes.length === 0) {
            return 'Company Type';
        }
        return this.selectedCompanyTypes
            .map((item) => (item === 'Corporate' ? 'Corporates' : `${item}s`))
            .join(', ');
    }

    get companyTypeSelection() {
        return {
            Startup: this.selectedCompanyTypes.includes('Startup'),
            Corporate: this.selectedCompanyTypes.includes('Corporate'),
            SME: this.selectedCompanyTypes.includes('SME'),
            PSU: this.selectedCompanyTypes.includes('PSU')
        };
    }

    get companyOptions() {
        return toOptions(APPLICATIONS, 'company');
    }

    get industryOptions() {
        return toOptions(APPLICATIONS, 'industry');
    }

    get jobFunctionOptions() {
        return toOptions(APPLICATIONS, 'jobFunction');
    }

    get programOptions() {
        return toOptions(APPLICATIONS, 'program');
    }

    get specializationOptions() {
        return toOptions(APPLICATIONS, 'specialization');
    }

    get graduationYearOptions() {
        return toOptions(APPLICATIONS, 'graduationYear');
    }

    get cityOptions() {
        return toOptions(APPLICATIONS, 'city');
    }

    get visibleApplications() {
        return APPLICATIONS.filter((item) => {
            if (
                this.selectedCompanyTypes.length > 0
                && !this.selectedCompanyTypes.includes(item.companyType)
            ) {
                return false;
            }

            if (this.appliedShowMentors && !item.mentorNearMe) {
                return false;
            }

            if (this.appliedFilters.company && item.company !== this.appliedFilters.company) {
                return false;
            }
            if (this.appliedFilters.industry && item.industry !== this.appliedFilters.industry) {
                return false;
            }
            if (this.appliedFilters.jobFunction && item.jobFunction !== this.appliedFilters.jobFunction) {
                return false;
            }
            if (this.appliedFilters.program && item.program !== this.appliedFilters.program) {
                return false;
            }
            if (
                this.appliedFilters.specialization
                && item.specialization !== this.appliedFilters.specialization
            ) {
                return false;
            }
            if (
                this.appliedFilters.graduationYear
                && item.graduationYear !== this.appliedFilters.graduationYear
            ) {
                return false;
            }
            if (this.appliedFilters.city && item.city !== this.appliedFilters.city) {
                return false;
            }

            return true;
        });
    }

    toggleCompanyTypeMenu() {
        this.isCompanyTypeOpen = !this.isCompanyTypeOpen;
    }

    handleCompanyTypeChange(event) {
        const type = event.target.dataset.type;
        const isChecked = event.target.checked;

        if (!type || !COMPANY_TYPES.includes(type)) {
            return;
        }

        const selection = new Set(this.selectedCompanyTypes);
        if (isChecked) {
            selection.add(type);
        } else {
            selection.delete(type);
        }
        this.selectedCompanyTypes = [...selection];
    }

    toggleFilters() {
        this.isFiltersOpen = !this.isFiltersOpen;
        if (this.isFiltersOpen) {
            this.draftFilters = { ...this.appliedFilters };
            this.draftShowMentors = this.appliedShowMentors;
        }
    }

    handleDraftFilterChange(event) {
        const field = event.target.dataset.field;
        if (!field) {
            return;
        }

        this.draftFilters = {
            ...this.draftFilters,
            [field]: event.target.value
        };
        this._applyDraftLive();
    }

    handleDraftMentorsToggle(event) {
        this.draftShowMentors = event.target.checked;
        this._applyDraftLive();
    }

    resetDraftFilters() {
        this.draftFilters = { ...DEFAULT_FILTERS };
        this.draftShowMentors = false;
        this._applyDraftLive();
    }

    applyFilters() {
        this._applyDraftLive();
        this.isFiltersOpen = false;
    }

    // Mirrors draftFilters/draftShowMentors into the applied state that visibleApplications
    // reads, so picking a value filters live instead of waiting for the Apply button.
    // visibleApplications is a plain getter over the in-memory APPLICATIONS array, so
    // reassigning these fields is enough to trigger recomputation on next render.
    _applyDraftLive() {
        this.appliedFilters = { ...this.draftFilters };
        this.appliedShowMentors = this.draftShowMentors;
    }
}