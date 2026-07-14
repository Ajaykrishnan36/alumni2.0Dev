import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import AlumniAlt from '@salesforce/resourceUrl/AlumniAlt';
import getMentorshipConnections from '@salesforce/apex/KenMentorshipController.getMentorshipConnections';

const ACCEPTED_STATUS = 'Accepted';

export default class KenMyProfileMentorship extends NavigationMixin(LightningElement) {
    @track mentors = [];
    @track isLoading = false;

    @track showPreferencesModal = false;

    @track preferences = {
        expertise: 'Select expertise',
        menteeType: 'Choose mentee type',
        communication: {
            email: false,
            sms: false,
            whatsapp: false,
            inPerson: false
        },
        maxMentees: 0,
        isUnlimited: true,
        showEmail: true,
        showContact: false
    };

    get isUnlimited() {
        return this.preferences.isUnlimited;
    }

    connectedCallback() {
        this.loadConnections();
    }

    loadConnections() {
        this.isLoading = true;
        getMentorshipConnections()
            .then((result) => {
                const rows = Array.isArray(result) ? result : [];
                this.mentors = rows
                    .filter((row) => row.mentorshipStatus === ACCEPTED_STATUS)
                    .map((row) => this.normalizeConnection(row));
            })
            .catch(() => {
                this.mentors = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    normalizeConnection(raw) {
        const isMentor = raw.currentUserIsMentor === true;
        // currentUserIsMentor=true means the current user IS the mentor → the counterpart is a Mentee
        // currentUserIsMentor=false means the current user IS the mentee → the counterpart is a Mentor
        const type = isMentor ? 'Mentee' : 'Mentor';
        const typeClass = isMentor ? 'mentee-badge' : 'mentor-badge';
        return {
            id: raw.personAccountId || raw.id,
            name: raw.name || '',
            designation: raw.title || '',
            location: raw.location || '',
            avatarUrl: raw.profileImage || AlumniAlt,
            isOnline: raw.isOnline === true,
            type,
            typeClass
        };
    }

    handleMentorCardClick(event) {
        const profileId = event.currentTarget.dataset.id;
        if (!profileId) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'network__c' },
            state: { profileId }
        });
    }

    handleEditPreferences() {
        this.showPreferencesModal = true;
    }

    closePreferencesModal() {
        this.showPreferencesModal = false;
    }

    savePreferences() {
        console.log('Saving preferences:', JSON.stringify(this.preferences));
        this.closePreferencesModal();
    }

    handleSort() {
        console.log('Sort clicked');
    }

    handleFilter() {
        console.log('Filter clicked');
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        const group = event.target.dataset.group;

        if (group === 'communication') {
            this.preferences.communication[field] = value;
        } else if (field === 'isUnlimited') {
            this.preferences.isUnlimited = true;
        } else {
            this.preferences[field] = value;
        }
    }

    handleUnlimitedChange(event) {
        this.preferences.isUnlimited = event.target.checked;
        if (this.preferences.isUnlimited) {
            this.preferences.maxMentees = 0;
        }
    }

    handleCountChange(event) {
        this.preferences.maxMentees = event.target.value;
    }
}