import { LightningElement, track } from 'lwc';

export default class MyProfileJobs extends LightningElement {
    @track currentTab = 'Applied'; // Applied, Saved, Posted

    // Mock Messages for empty states (optional) or data
    @track jobs = [
        {
            id: 1,
            title: 'Sr. Design Associate',
            company: 'Google Pay',
            logoUrl: 'https://cdn.iconscout.com/icon/free/png-256/free-google-pay-2038779-1721670.png',
            types: ['Full-Time', '3-4 years experience', 'Remote'],
            salary: '₹ 15,00,000 - ₹ 20,00,000',
            postedBy: 'Olivia Johnson',
            postedByAvatar: 'https://i.pravatar.cc/150?u=olivia',
            isSaved: true
        },
        {
            id: 2,
            title: 'Sr. Design Associate',
            company: 'Google Pay',
            logoUrl: 'https://cdn.iconscout.com/icon/free/png-256/free-google-pay-2038779-1721670.png',
            types: ['Full-Time', '3-4 years experience', 'Remote'],
            salary: '₹ 15,00,000 - ₹ 20,00,000',
            postedBy: 'Olivia Johnson',
            postedByAvatar: 'https://i.pravatar.cc/150?u=olivia',
            isSaved: true // Icon is filled in second card?
        },
        {
            id: 3,
            title: 'Back-End Developer',
            company: 'PayPal',
            logoUrl: 'https://cdn.iconscout.com/icon/free/png-256/free-paypal-logo-icon-download-in-svg-png-gif-file-formats--finance-payment-gateway-money-credit-card-logos-pack-icons-2038780.png',
            types: ['Full-Time', 'Fresher', 'Bangalore'],
            salary: '₹ 15,00,000 - ₹ 20,00,000',
            postedBy: 'Admin',
            postedByAvatar: 'https://i.pravatar.cc/150?u=admin',
            isSaved: true
        }
    ];

    @track resumes = [
        {
            id: 1,
            name: 'Visual designer',
            lastUsed: 'Last used on 23/03/2024',
            type: 'PDF'
        },
        {
            id: 2,
            name: 'UIUX Designer',
            lastUsed: 'Last used on 23/03/2024',
            type: 'PDF'
        },
        {
            id: 3,
            name: 'Marketing',
            lastUsed: 'Last used on 23/03/2024',
            type: 'PDF'
        }
    ];

    @track employments = [
        {
            id: 1,
            title: 'Sr. Design Associate',
            company: 'Google Pay',
            type: 'Full-time',
            period: 'May 2022 - Present | 1 yr 4 mos',
            location: 'Coimbatore, Tamil Nadu, India | Onsite',
            logoUrl: 'https://cdn.iconscout.com/icon/free/png-256/free-google-pay-2038779-1721670.png',
            isCurrent: true
        },
        {
            id: 2,
            title: 'Front-end Developer',
            company: 'Zoho',
            type: 'Full-time',
            period: 'May 2021 - April 2022 | 1 yr 1 mos',
            location: 'Chennai, Tamil Nadu, India | Onsite',
            logoUrl: 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT6z8c2k5yF5w-K7y4b4a3a1z0e_r6c5t8u9v&s',            isCurrent: false
        }
    ];

    @track certificates = [
        {
            id: 1,
            name: 'Web Accessibility',
            issuer: 'Google certifications',
            date: 'Issued Mar 2023',
            logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/2048px-Google_%22G%22_Logo.svg.png'
        },
        {
            id: 2,
            name: 'AWS Data Engineer',
            issuer: 'Amazon Web Services',
            date: 'Issued Jun 2023',
            logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/9/93/Amazon_Web_Services_Logo.svg/1024px-Amazon_Web_Services_Logo.svg.png'
        }
    ];

    @track skills = [
        'Typography', 'Creativity', 'Communication Skills', 'Time Management', 'Problem-Solving', 'Adaptability'
    ];

    // Modal Flags
    @track showResumeDeleteModal = false;
    @track showEmploymentModal = false;
    @track showCertificateModal = false;
    @track resumeToDelete = null;

    // Temporary objects for forms
    @track tempEmployment = {};
    @track tempCertificate = {};
    @track tempSkills = '';
    @track showSkillsModal = false;

    // Getters for Tab Classes
    get isAppliedTab() { return this.currentTab === 'Applied'; }
    get isSavedTab() { return this.currentTab === 'Saved'; }
    get isPostedTab() { return this.currentTab === 'Posted'; }

    get appliedTabClass() { return `tab-item ${this.currentTab === 'Applied' ? 'active' : ''}`; }
    get savedTabClass() { return `tab-item ${this.currentTab === 'Saved' ? 'active' : ''}`; }
    get postedTabClass() { return `tab-item ${this.currentTab === 'Posted' ? 'active' : ''}`; }

    // Handlers
    handleTabChange(event) {
        this.currentTab = event.target.dataset.tab;
    }

    // Resume Handlers
    handleDeleteResume(event) {
        const resumeId = event.target.dataset.id;
        this.resumeToDelete = this.resumes.find(r => r.id == resumeId);
        this.showResumeDeleteModal = true;
    }

    closeResumeDeleteModal() {
        this.showResumeDeleteModal = false;
        this.resumeToDelete = null;
    }

    confirmDeleteResume() {
        if (this.resumeToDelete) {
            this.resumes = this.resumes.filter(r => r.id !== this.resumeToDelete.id);
        }
        this.closeResumeDeleteModal();
    }

    // Employment Handlers
    handleAddEmployment() {
        this.tempEmployment = {}; // Reset form
        this.showEmploymentModal = true;
    }

    handleEditEmployment(event) {
        const id = event.target.dataset.id;
        const emp = this.employments.find(e => e.id == id);
        this.tempEmployment = { ...emp }; // Clone for edit
        this.showEmploymentModal = true;
    }

    closeEmploymentModal() {
        this.showEmploymentModal = false;
    }

    saveEmployment() {
        // Mock save
        if (this.tempEmployment.id) {
             // Update existing
             this.employments = this.employments.map(e => e.id === this.tempEmployment.id ? {...this.tempEmployment} : e);
        } else {
             // Add new
             this.employments.push({ ...this.tempEmployment, id: Date.now(), logoUrl: 'https://via.placeholder.com/150' });
        }
        this.closeEmploymentModal();
    }

    // Certificate Handlers
    handleAddCertificate() {
        this.tempCertificate = {};
        this.showCertificateModal = true;
    }

    handleEditCertificate(event) {
        const id = event.target.dataset.id;
        const cert = this.certificates.find(c => c.id == id);
        this.tempCertificate = { ...cert };
        this.showCertificateModal = true;
    }

    closeCertificateModal() {
        this.showCertificateModal = false;
    }

    saveCertificate() {
         // Mock save
         if (this.tempCertificate.id) {
            this.certificates = this.certificates.map(c => c.id === this.tempCertificate.id ? {...this.tempCertificate} : c);
       } else {
            this.certificates.push({ ...this.tempCertificate, id: Date.now(), logoUrl: 'https://via.placeholder.com/150' });
       }
       this.closeCertificateModal();
    }

    // Skills Handlers
    handleEditSkills() {
        // For now, reuse add logic or prepopulate
        this.tempSkills = this.skills.join(', ');
        this.showSkillsModal = true;
    }

    handleAddSkills() {
        this.tempSkills = '';
        this.showSkillsModal = true;
    }

    closeSkillsModal() {
        this.showSkillsModal = false;
    }

    saveSkills() {
        if (this.tempSkills) {
            // Split by comma and trim
            this.skills = this.tempSkills.split(',').map(s => s.trim()).filter(s => s.length > 0);
        }
        this.closeSkillsModal();
    }

    // Input Handlers for Modals (Generic)
    handleInputChange(event) {
        const field = event.target.dataset.field;
        const target = event.target.dataset.target; // 'employment', 'certificate', 'skills'
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;

        if (target === 'employment') {
            this.tempEmployment[field] = value;
        } else if (target === 'certificate') {
            this.tempCertificate[field] = value;
        } else if (target === 'skills') {
            this.tempSkills = value;
        }
    }

    handlePostJob() {
        console.log('Post a Job clicked');
    }
}