import { LightningElement, track } from 'lwc';

export default class MyProfileMentorship extends LightningElement {
    @track mentors = [
        {
            id: 1,
            name: 'Tanya Singh',
            designation: 'Executive',
            location: 'Pune, India',
            type: 'Mentor',
            typeClass: 'mentor-badge',
            avatarUrl: 'https://i.pravatar.cc/150?u=tanya',
            isOnline: false
        },
        {
            id: 2,
            name: 'Ritika Patel',
            designation: 'Executive',
            location: 'Pune, India',
            type: '',
            avatarUrl: 'https://i.pravatar.cc/150?u=ritika',
            isOnline: true // Green dot in screenshot
        },
        {
            id: 3,
            name: 'Roshni S',
            designation: 'Product Designer',
            location: 'Pune, India',
            type: '',
            avatarUrl: 'https://i.pravatar.cc/150?u=roshni',
            isOnline: false
        }
    ];

    @track showPreferencesModal = false;
    
    // Preferences Form Data
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

    // Handlers
    handleEditPreferences() {
        this.showPreferencesModal = true;
    }

    closePreferencesModal() {
        this.showPreferencesModal = false;
    }

    savePreferences() {
        // Here you would typically validate and save the preferences
        console.log('Saving preferences:', JSON.stringify(this.preferences));
        this.closePreferencesModal();
    }

    handleSort() {
        console.log('Sort clicked');
    }

    handleFilter() {
        console.log('Filter clicked');
    }
    
    // Form handlers
    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        const group = event.target.dataset.group;

        if (group === 'communication') {
            this.preferences.communication[field] = value;
        } else if (field === 'isUnlimited') {
             this.preferences.isUnlimited = true; // Radio button logic might need adjustment if logic is mutually exclusive with number input
        } else {
             this.preferences[field] = value;
        }
    }
    
    handleUnlimitedChange(event) {
         this.preferences.isUnlimited = event.target.checked;
         if(this.preferences.isUnlimited) {
             this.preferences.maxMentees = 0; // Reset or disable input
         }
    }

    handleCountChange(event) {
        // If user changes count, assume unlimited is false/uncheck radio if needed
        this.preferences.maxMentees = event.target.value;
        // Logic for radio/input interaction can be refined
    }
}