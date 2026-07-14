// V2 wiring — calls OLD KenSettingsController. Do not modify the OLD controller.
// Imperative calls. Each section getter is wired on load; savers are wired to handleSave
// based on which sub-section is currently active. Mock fallback preserved on error.
import { LightningElement, track } from 'lwc';
import getPersonalDetails from '@salesforce/apex/KenSettingsController.getPersonalDetails';
import savePersonalDetails from '@salesforce/apex/KenSettingsController.savePersonalDetails';
import getPreferences from '@salesforce/apex/KenSettingsController.getPreferences';
import savePreferences from '@salesforce/apex/KenSettingsController.savePreferences';
import getEventPreferences from '@salesforce/apex/KenSettingsController.getEventPreferences';
import saveEventPreferences from '@salesforce/apex/KenSettingsController.saveEventPreferences';
import getGroupPreferences from '@salesforce/apex/KenSettingsController.getGroupPreferences';
import saveGroupPreferences from '@salesforce/apex/KenSettingsController.saveGroupPreferences';
import getMentorshipPreferences from '@salesforce/apex/KenSettingsController.getMentorshipPreferences';
import saveMentorshipPreferences from '@salesforce/apex/KenSettingsController.saveMentorshipPreferences';
import getJobPreferences from '@salesforce/apex/KenSettingsController.getJobPreferences';
import saveJobPreferences from '@salesforce/apex/KenSettingsController.saveJobPreferences';
import saveAccountSettingsApex from '@salesforce/apex/KenSettingsController.saveAccountSettings';
import saveNotificationSettingsApex from '@salesforce/apex/KenSettingsController.saveNotificationSettings';

const SECTIONS = [
    { id:'personal',      label:'Personal Details', icon:'👤' },
    { id:'preferences',   label:'Preferences',      icon:'⚙️' },
    { id:'events',        label:'Events',           icon:'📅' },
    { id:'groups',        label:'Groups',           icon:'👥' },
    { id:'mentorship',    label:'Mentorship',       icon:'🧭' },
    { id:'jobs',          label:'Jobs',             icon:'💼' },
    { id:'account',       label:'Account',          icon:'🔒' },
    { id:'notifications', label:'Notifications',    icon:'🔔' }
];

export default class KenSettingV2 extends LightningElement {
    @track active = 'personal';
    @track isLoading = true;
    @track prefs = {
        // User identity defaults blank — populated from Apex (KenSettingsController.getPersonalDetails).
        firstName:'', lastName:'', email:'', phone:'', batch:'', city:'', bio:'',
        // Non-identity UI defaults (toggles/locale) stay reasonable so the form has a starting state.
        theme:'Light', language:'English', timezone:'Asia/Kolkata',
        eventReminders:true, eventDigest:true, eventRsvpReminder:true,
        groupMentions:true, groupDigest:false, groupNewPost:true,
        mentorshipEnabled:true, mentorshipPause:false, mentorshipMaxSessions:'4',
        jobAlerts:true, jobRoles:'', jobCities:'',
        twoFA:false,
        emailEvents:true, emailJobs:true, emailNewsletters:true, emailDigests:false,
        pushEvents:true, pushMessages:true, pushBirthdays:false
    };

    @track showDeleteConfirm = false;
    @track showChangePass = false;
    @track passForm = { current:'', next:'', confirm:'' };

    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const VALID_TABS = ['personal', 'preferences', 'events', 'groups', 'mentorship', 'jobs', 'account', 'notifications'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.active = tab;
        } catch (e) { /* ignore */ }
        this.loadAllSettings();
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.active) params.set('tab', this.active); else params.delete('tab');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadAllSettings() {
        this.isLoading = true;
        const safe = (p) => p.catch(() => null);
        Promise.all([
            safe(getPersonalDetails()),
            safe(getPreferences()),
            safe(getEventPreferences()),
            safe(getGroupPreferences()),
            safe(getMentorshipPreferences()),
            safe(getJobPreferences())
        ]).then(([pd, pref, ev, grp, mn, jb]) => {
            const next = { ...this.prefs };
            if (pd) {
                if (pd.firstName)   next.firstName = pd.firstName;
                if (pd.lastName)    next.lastName  = pd.lastName;
                if (pd.maskedEmail) next.email     = pd.maskedEmail;
                if (pd.maskedPhone) next.phone     = pd.maskedPhone;
                if (pd.city)        next.city      = pd.city;
                if (pd.country)     next.country   = pd.country;
                if (pd.linkedinUrl) next.linkedin  = pd.linkedinUrl;
                if (pd.twitterUrl)  next.twitter   = pd.twitterUrl;
                if (pd.profileImageUrl) next.profileImageUrl = pd.profileImageUrl;
            }
            if (pref) {
                next.isPrivateAccount = pref.isPrivateAccount === true;
                if (pref.preferredCommunication) next.preferredCommunication = pref.preferredCommunication;
                if (pref.howOften)               next.howOften = pref.howOften;
                next.notifyRealTime = pref.notifyRealTime === true;
                if (pref.notifyFor)              next.notifyFor = pref.notifyFor;
            }
            if (ev) {
                if (ev.whoCanInvite)      next.eventWhoCanInvite = ev.whoCanInvite;
                next.eventReceiveAlerts   = ev.receiveAlerts === true;
                if (ev.reminderFrequency) next.eventReminderFrequency = ev.reminderFrequency;
            }
            if (grp) {
                if (grp.whoCanInvite)   next.groupWhoCanInvite = grp.whoCanInvite;
                next.groupReceiveUpdates = grp.receiveUpdates === true;
                if (grp.notifyFor)      next.groupNotifyFor = grp.notifyFor;
            }
            if (mn) {
                next.mentorshipWilling   = mn.willingToBeMentor === true;
                if (mn.availabilityDays) next.mentorshipDays = mn.availabilityDays;
                if (mn.expertiseAreas)   next.mentorshipExpertise = mn.expertiseAreas;
                if (mn.commModes)        next.mentorshipCommModes = mn.commModes;
            }
            if (jb) {
                next.jobOpenToWork              = jb.openToWork === true;
                if (jb.preferredJobTitles)      next.jobRoles = jb.preferredJobTitles;
                if (jb.skillSet)                next.jobSkills = jb.skillSet;
                if (jb.preferredLocationTypes)  next.jobLocationTypes = jb.preferredLocationTypes;
                if (jb.locationOnSite)          next.jobCities = jb.locationOnSite;
                if (jb.employmentTypes)         next.jobEmploymentTypes = jb.employmentTypes;
            }
            this.prefs = next;
            this.isLoading = false;
        });
    }

    // Section -> [save Apex, payload-builder]
    _savePayloads() {
        const p = this.prefs;
        return {
            personal: () => savePersonalDetails({ requestJson: JSON.stringify({
                firstName: p.firstName, lastName: p.lastName,
                linkedinUrl: p.linkedin || '', twitterUrl: p.twitter || '',
                city: p.city || '', country: p.country || ''
            })}),
            preferences: () => savePreferences({ requestJson: JSON.stringify({
                isPrivateAccount: !!p.isPrivateAccount,
                preferredCommunication: p.preferredCommunication || '',
                howOften: p.howOften || '',
                notifyRealTime: !!p.notifyRealTime,
                notifyFor: p.notifyFor || ''
            })}),
            events: () => saveEventPreferences({ requestJson: JSON.stringify({
                whoCanInvite: p.eventWhoCanInvite || '',
                receiveAlerts: !!p.eventReceiveAlerts,
                reminderFrequency: p.eventReminderFrequency || ''
            })}),
            groups: () => saveGroupPreferences({ requestJson: JSON.stringify({
                whoCanInvite: p.groupWhoCanInvite || '',
                receiveUpdates: !!p.groupReceiveUpdates,
                notifyFor: p.groupNotifyFor || ''
            })}),
            mentorship: () => saveMentorshipPreferences({ requestJson: JSON.stringify({
                willingToBeMentor: !!p.mentorshipWilling,
                availabilityDays: p.mentorshipDays || '',
                expertiseAreas: p.mentorshipExpertise || '',
                commModes: p.mentorshipCommModes || ''
            })}),
            jobs: () => saveJobPreferences({ requestJson: JSON.stringify({
                openToWork: !!p.jobOpenToWork,
                preferredJobTitles: p.jobRoles || '',
                skillSet: p.jobSkills || '',
                preferredLocationTypes: p.jobLocationTypes || '',
                locationOnSite: p.jobCities || '',
                employmentTypes: p.jobEmploymentTypes || ''
            })}),
            account: () => saveAccountSettingsApex({ req: this._buildAccountPayload() }),
            notifications: () => saveNotificationSettingsApex({ req: this._buildNotificationPayload() })
        };
    }

    // Account-tab UI currently exposes only password/2FA/delete buttons (no editable
    // identity fields). Payload mirrors getPersonalDetails(); masked email/phone are
    // skipped server-side. Sends whatever identity state we have so the tab is ready
    // to grow editable fields without further wiring.
    _buildAccountPayload() {
        const p = this.prefs;
        return {
            firstName: p.firstName || '',
            lastName:  p.lastName  || '',
            email:     p.email     || '',
            phone:     p.phone     || '',
            linkedinUrl: p.linkedin || '',
            twitterUrl:  p.twitter  || ''
        };
    }

    _buildNotificationPayload() {
        const p = this.prefs;
        return {
            emailEvents:      !!p.emailEvents,
            emailJobs:        !!p.emailJobs,
            emailNewsletters: !!p.emailNewsletters,
            emailDigests:     !!p.emailDigests,
            pushEvents:       !!p.pushEvents,
            pushMessages:     !!p.pushMessages,
            pushBirthdays:    !!p.pushBirthdays
        };
    }

    get sections() {
        return SECTIONS.map(s => ({ ...s, sectionClass: s.id === this.active ? 'side__item side__item--active' : 'side__item' }));
    }
    get isPersonal()      { return !this.isLoading && this.active === 'personal'; }
    get isPreferences()   { return !this.isLoading && this.active === 'preferences'; }
    get isEvents()        { return !this.isLoading && this.active === 'events'; }
    get isGroups()        { return !this.isLoading && this.active === 'groups'; }
    get isMentorship()    { return !this.isLoading && this.active === 'mentorship'; }
    get isJobs()          { return !this.isLoading && this.active === 'jobs'; }
    get isAccount()       { return !this.isLoading && this.active === 'account'; }
    get isNotifications() { return !this.isLoading && this.active === 'notifications'; }

    handleSectionChange(event) { this.active = event.detail.id; this.syncUrl(); }

    // Inline (panels still in parent) field input
    handleField(event) {
        const f = event.target.dataset.field;
        if (!f) return;
        const val = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.prefs = { ...this.prefs, [f]: val };
    }

    // From child panels (Personal, Preferences)
    handleChildField(event) {
        const { field, value } = event.detail;
        if (!field) return;
        this.prefs = { ...this.prefs, [field]: value };
    }

    handleSave() {
        const builders = this._savePayloads();
        const fn = builders[this.active];
        if (!fn) {
            this._showToast('This section cannot be saved yet');
            return;
        }
        fn().then(() => this._showToast('Settings saved'))
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenSettingsController save error for ' + this.active, err);
                const msg = (err && err.body && err.body.message) || 'Could not save. Please try again.';
                this._showToast(msg);
            });
    }
    handleCancel() {
        this._showToast('Changes discarded');
        this.loadAllSettings();
    }

    /* Change password */
    handleOpenChangePass() {
        this.passForm = { current:'', next:'', confirm:'' };
        this.showChangePass = true;
    }
    handleCloseChangePass() { this.showChangePass = false; }
    handlePassFieldChild(event) {
        const { field, value } = event.detail;
        if (field) this.passForm = { ...this.passForm, [field]: value };
    }
    handlePassSubmit() {
        // The modal now owns the full OTP flow (sendResetOtp -> verifyResetOtp -> resetPassword).
        // This handler is kept for back-compat with the legacy submitform event but is a no-op.
    }
    handleResetDone() {
        this.showChangePass = false;
        this._showToast('Password updated');
    }

    handleEnable2FA() {
        this.prefs = { ...this.prefs, twoFA: !this.prefs.twoFA };
        this._showToast(this.prefs.twoFA ? 'Two-factor authentication enabled' : 'Two-factor authentication disabled');
    }

    /* Delete confirm */
    handleOpenDelete() { this.showDeleteConfirm = true; }
    handleCloseDelete() { this.showDeleteConfirm = false; }
    handleConfirmDelete() {
        this.showDeleteConfirm = false;
        this._showToast('Account deletion requested');
    }

    _showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }
}