import { LightningElement, track } from 'lwc';
import searchVisitorByEmail from '@salesforce/apex/KenVisitorPassController.searchVisitorByEmail';
import saveVisitorContact   from '@salesforce/apex/KenVisitorPassController.saveVisitorContact';
import getColors            from '@salesforce/apex/KenSnSColorController.getColors';

const RELATIONSHIP_OPTIONS = [
    { label: '-- Select --', value: ''        },
    { label: 'Father',       value: 'Father'  },
    { label: 'Mother',       value: 'Mother'  },
    { label: 'Guardian',     value: 'Guardian'},
    { label: 'Spouse',       value: 'Spouse'  }
];

export default class KenVisitorPassForm extends LightningElement {

    @track firstName        = '';
    @track lastName         = '';
    @track email            = '';
    @track phone            = '';
    @track relationshipType = '';

    @track visitorFound = false;
    @track isLookingUp  = false;
    @track isSaving     = false;
    _emailLookupTimer   = null;

    @track emailError        = '';
    @track firstNameError    = '';
    @track lastNameError     = '';
    @track phoneError        = '';

    get relationshipOptions() {
        return RELATIONSHIP_OPTIONS.map(o => ({ ...o, isSelected: o.value === this.relationshipType }));
    }

    connectedCallback() {
        getColors().then(colors => { this._applyTheme(colors); }).catch(() => {});
    }

    _applyTheme(colors) {
        const host = this.template?.host?.style;
        if (!host || !colors) return;
        const primary   = colors.primary   || colors.primaryColor;
        const secondary = colors.secondary || colors.secondaryColor;
        if (primary)   { host.setProperty('--primary-color', String(primary).trim()); }
        if (secondary) { host.setProperty('--secondary-color', String(secondary).trim()); host.setProperty('--primary-light', String(secondary).trim()); }
    }

    get emailInputClass() {
        return 'vf-input' + (this.emailError ? ' vf-input--invalid' : '') + (this.visitorFound ? ' vf-input-found' : '');
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this[field] = event.target.value;
        if (field === 'firstName') this.firstNameError = '';
        if (field === 'lastName')  this.lastNameError  = '';
        if (field === 'phone')     this.phoneError     = '';
        if (field === 'email') {
            this.emailError   = '';
            this.visitorFound = false;
            // Debounce lookup — triggers 600ms after user stops typing
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            clearTimeout(this._emailLookupTimer);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._emailLookupTimer = setTimeout(() => {
                this._doEmailLookup();
            }, 600);
        }
    }

    handleRelationshipChange(event) {
        this.relationshipType = event.target.value;
    }

    handleEmailBlur() {
        // Also trigger on blur in case debounce hasn't fired yet
        clearTimeout(this._emailLookupTimer);
        this._doEmailLookup();
    }

    _doEmailLookup() {
        const email = this.email.trim();
        if (!email || !this._isValidEmail(email)) return;

        this.isLookingUp = true;
        this.visitorFound = false;

        searchVisitorByEmail({ email })
            .then(info => {
                if (info && info.found) {
                    this.firstName        = info.firstName        || '';
                    this.lastName         = info.lastName         || '';
                    this.phone            = info.phone            || '';
                    this.relationshipType = info.relationshipType || '';
                    this.visitorFound     = true;
                }
            })
            .catch(() => {})
            .finally(() => { this.isLookingUp = false; });
    }

    handleContinue() {
        if (!this._validate()) return;

        this.isSaving = true;
        saveVisitorContact({
            firstName:        this.firstName.trim(),
            lastName:         this.lastName.trim(),
            email:            this.email.trim(),
            phone:            this.phone.trim(),
            relationshipType: this.relationshipType
        })
        .then(contactId => {
            this.dispatchEvent(new CustomEvent('visitorready', {
                detail: {
                    visitorContactId: contactId,
                    visitorName:      this.firstName.trim() + ' ' + this.lastName.trim(),
                    email:            this.email.trim(),
                    relationshipType: this.relationshipType
                }
            }));
        })
        .catch(err => {
            const msg = err?.body?.message || 'Failed to save visitor. Please try again.';
            this.emailError = msg;
        })
        .finally(() => { this.isSaving = false; });
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    _validate() {
        let valid = true;

        // Email — must be valid with @
        if (!this.email.trim() || !this._isValidEmail(this.email)) {
            this.emailError = 'Please enter a valid email address (must contain @).';
            valid = false;
        }

        // First name — required, letters and spaces only
        if (!this.firstName.trim()) {
            this.firstNameError = 'First name is required.';
            valid = false;
        } else if (!/^[a-zA-Z\s]+$/.test(this.firstName.trim())) {
            this.firstNameError = 'First name cannot contain numbers or special characters.';
            valid = false;
        }

        // Last name — required, letters and spaces only
        if (!this.lastName.trim()) {
            this.lastNameError = 'Last name is required.';
            valid = false;
        } else if (!/^[a-zA-Z\s]+$/.test(this.lastName.trim())) {
            this.lastNameError = 'Last name cannot contain numbers or special characters.';
            valid = false;
        }

        // Mobile — required, numbers only
        if (!this.phone.trim()) {
            this.phoneError = 'Mobile number is required.';
            valid = false;
        } else if (!/^\d+$/.test(this.phone.trim())) {
            this.phoneError = 'Mobile number must contain only digits.';
            valid = false;
        }

        return valid;
    }

    _isValidEmail(email) {
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    }
}