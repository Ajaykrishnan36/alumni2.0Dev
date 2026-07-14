import { LightningElement, api, track } from 'lwc';

export default class KenJobApplicantsViewV2 extends LightningElement {
    @api jobTitle = '';
    @api jobCompany = '';
    @api jobLocation = '';
    @api jobSalary = '';
    @api logoLetter = '';
    @api jobId = '';
    @api applicants = [];

    @track activeTab = 'applicants';
    @track shareToastMsg = '';
    @track showShareToast = false;

    pills = ['Remote', 'Fintech', 'Startup'];

    get applicantsList() { return this.applicants || []; }
    get hasApplicants() { return (this.applicants || []).length > 0; }
    get applicantCountLabel() {
        const n = (this.applicants || []).length;
        const padded = n < 10 ? '0' + n : '' + n;
        return 'Applicants (' + padded + ')';
    }
    get detailsTabClass() {
        return this.activeTab === 'details' ? 'tab tab--active' : 'tab';
    }
    get applicantsTabClass() {
        return this.activeTab === 'applicants' ? 'tab tab--active' : 'tab';
    }

    handleDetailsTab() { this.dispatchEvent(new CustomEvent('viewdetails')); }
    handleApplicantsTab() { this.activeTab = 'applicants'; }
    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
    handleEdit() { this.dispatchEvent(new CustomEvent('edit')); }
    handleDeactivate() { this.dispatchEvent(new CustomEvent('deactivate')); }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleViewResume(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('viewresume', { detail: { id } }));
    }

    handleShareJob() {
        const url = (typeof window !== 'undefined' && window.location)
            ? window.location.origin + '/jobs?view=detail&id=' + (this.jobId || '')
            : '';
        const fire = (msg) => {
            this.shareToastMsg = msg;
            this.showShareToast = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.showShareToast = false; }, 2200);
        };
        try {
            if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(url)
                    .then(() => fire('Job link copied to clipboard'))
                    .catch(() => fire('Could not copy link'));
            } else {
                fire('Job link: ' + url);
            }
        } catch (e) {
            fire('Could not copy link');
        }
    }
}