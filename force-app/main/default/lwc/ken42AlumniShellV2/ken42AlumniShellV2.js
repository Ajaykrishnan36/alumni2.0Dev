import basePath from '@salesforce/community/basePath';
import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUserContactDetails from '@salesforce/apex/KenNavBarController.getUserContactDetails';
import getActionCount from '@salesforce/apex/KenNotificationController.getActionCount';

const NAV_TITLES = {
    home: 'Home',
    events: 'Events',
    jobs: 'Jobs',
    network: 'Network',
    mentorship: 'Mentorship',
    giving: 'Giving',
    groups: 'Groups',
    feedback: 'Feedback & Survey',
    business: 'Business Directory',
    support: 'Service & Support'
};

export default class Ken42AlumniShellV2 extends LightningElement {
    // Defaults are blank so we never flash mock identity. Apex populates them
    // in connectedCallback via KenNavBarController.getUserContactDetails().
    @api userFirstName = '';
    @api userLastName = '';
    @api userBatch = '';
    @api userInstitution = '';
    @api userLocation = '';
    @api userTitleCompany = '';
    @api activeNav = 'home';
    @api topbarTitleOverride = '';
    @api hasRail = false;

    // Notification badge for the Feedback & Survey nav item. Default false so the
    // red dot is hidden everywhere until a real unread-count source sets it.
    @api feedbackUnreadCount = 0;

    get showFeedbackDot() {
        return Number(this.feedbackUnreadCount) > 0 && this.activeNav !== 'feedback';
    }

    brand = 'ku';
    view = 'verify';

    // Notifications popover state + bell badge count.
    showNotifications = false;
    notifCount = 0;
    _wiredCount;

    _onDocClick = null;

    // Bell badge — unread notifications + pending approvals. Cacheable Apex.
    @wire(getActionCount)
    wiredCount(result) {
        this._wiredCount = result;
        if (result && result.data != null) this.notifCount = result.data;
    }

    get hasNotifCount() { return Number(this.notifCount) > 0; }
    get notifCountLabel() { return Number(this.notifCount) > 9 ? '9+' : String(this.notifCount); }

    handleBellClick(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showNotifications = !this.showNotifications;
    }
    handleCloseNotifications() { this.showNotifications = false; }
    handleNotifProcessed() {
        // A request was accepted/declined in the popover — refresh the badge.
        if (this._wiredCount) { refreshApex(this._wiredCount); }
    }

    connectedCallback() {
        try {
            const b = localStorage.getItem('a2-brand');
            if (b) this.brand = b;
            const v = localStorage.getItem('a2-view');
            if (v) this.view = v;
        } catch (e) { /* sandboxed - ignore */ }

        // Load real user identity for sidebar.
        getUserContactDetails()
            .then(data => {
                if (!data) return;
                // Prefer FirstName/LastName from PersonAccount; fall back to splitting studentName.
                let fn = data.firstName || '';
                let ln = data.lastName || '';
                if ((!fn && !ln) && data.studentName) {
                    const parts = String(data.studentName).trim().split(/\s+/);
                    fn = parts.shift() || '';
                    ln = parts.join(' ');
                }
                if (fn) this.userFirstName = fn;
                if (ln) this.userLastName = ln;
                if (data.graduationYear) this.userBatch = `Batch ${data.graduationYear}`;
                if (data.institutionName) {
                    this.userInstitution = data.institutionName;
                } else if (!this.userInstitution) {
                    this.userInstitution = 'Alumni';
                }
                if (data.currentLocation) this.userLocation = data.currentLocation;
                // Build "Title · Company" chip when both available; else either alone.
                const title = data.currentTitle || data.specialization || '';
                const company = data.currentCompany || '';
                if (title && company) this.userTitleCompany = `${title} · ${company}`;
                else if (title) this.userTitleCompany = title;
                else if (company) this.userTitleCompany = company;
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNavBarController.getUserContactDetails error', err);
            });

        // Global click delegate (capture phase) — handles data-href navigation only.
        this._onDocClick = (e) => {
            try {
                const path = (e.composedPath && e.composedPath()) || [];
                let el = null;
                for (const node of path) {
                    if (node && node.getAttribute && node.getAttribute('data-href')) {
                        el = node;
                        break;
                    }
                }
                if (!el) return;
                if (el.tagName === 'A' && el.getAttribute('href')) return;
                const href = el.getAttribute('data-href');
                if (!href) return;
                e.preventDefault();
                e.stopPropagation();
                const target = this.resolveHref(href);
                window.location.assign(target.startsWith('/') ? basePath + target : target);
            } catch (err) { /* ignore */ }
        };
        document.addEventListener('click', this._onDocClick, true);

        // Close the notifications popover on outside click. Registered in the
        // BUBBLE phase (not capture) so the popover's own stopPropagation() can
        // shield inside-clicks: any click that still reaches document is, by
        // definition, outside the popover and the bell.
        this._onDocCloseNotif = () => {
            if (this.showNotifications) this.showNotifications = false;
        };
        document.addEventListener('click', this._onDocCloseNotif, false);
    }

    disconnectedCallback() {
        if (this._onDocClick) {
            document.removeEventListener('click', this._onDocClick, true);
            this._onDocClick = null;
        }
        if (this._onDocCloseNotif) {
            document.removeEventListener('click', this._onDocCloseNotif, false);
            this._onDocCloseNotif = null;
        }
    }

    /**
     * Public hook so a host page (e.g. kenMyProfileV2) can push freshly-saved
     * identity into the sidebar + topbar without a page reload. Only non-null
     * fields are applied, so a caller can update just the name and leave the
     * batch/title intact. userName / userInitials / topbarTitle are getters, so
     * assigning the backing fields re-renders the sidebar instantly.
     */
    @api refreshIdentity(detail) {
        if (!detail) return;
        if (detail.firstName != null) this.userFirstName = detail.firstName;
        if (detail.lastName != null) this.userLastName = detail.lastName;
        if (detail.batch != null) {
            const b = String(detail.batch).replace(/^Batch\s+/i, '').trim();
            this.userBatch = b ? `Batch ${b}` : '';
        }
    }

    resolveHref(href) {
        let h = String(href).trim();
        if (h.startsWith('screens/')) h = h.slice('screens/'.length);
        if (h.endsWith('.html')) h = h.slice(0, -5);
        const firstSeg = h.split('/')[0];
        const knownSections = ['events','jobs','network','mentorship','giving','groups','feedback','support','calendar','notifications','chat','gallery','resources','business','settings','my-profile','surveys'];
        if (knownSections.indexOf(firstSeg) >= 0) {
            return '/' + firstSeg;
        }
        if (h === '' || h === 'home' || h === 'index') return '/';
        if (h.startsWith('/')) return h;
        return '/' + h;
    }

    // ===== Global topbar search =====
    // The topbar search is present on every module page. It routes to the Network
    // (alumni) search with the typed term so it returns real results from anywhere
    // in the app. Press Enter (or click the search icon) to run it.
    globalSearchTerm = '';

    handleGlobalSearchInput(event) {
        this.globalSearchTerm = (event && event.target && event.target.value) || '';
    }
    handleGlobalSearchKey(event) {
        if (event && event.key === 'Enter') {
            event.preventDefault();
            this.runGlobalSearch();
        }
    }
    handleGlobalSearchClick() {
        this.runGlobalSearch();
    }
    runGlobalSearch() {
        const term = (this.globalSearchTerm || '').trim();
        if (!term) {
            // Empty search just opens the Network directory.
            try { window.location.assign(basePath + '/network'); } catch (e) { window.location.href = basePath + '/network'; }
            return;
        }
        const target = basePath + '/network?tab=all&view=grid&q=' + encodeURIComponent(term);
        try { window.location.assign(target); } catch (e) { window.location.href = target; }
    }

    get appClass() {
        return this.hasRail ? 'a2-app a2-app--with-rail' : 'a2-app';
    }

    handleNotificationClick() {}

    handleGearClick(event) {
        event.stopPropagation();
        event.preventDefault();
        try { window.location.assign(basePath + '/settings'); } catch (e) { /* ignore */ }
    }

    handleLogout() {
        try {
            window.location.assign('/secur/logout.jsp');
        } catch (e) { /* ignore */ }
    }

    get userInitials() {
        const f = (this.userFirstName || '').charAt(0);
        const l = (this.userLastName || '').charAt(0);
        return (f + l).toUpperCase();
    }
    get userName() {
        return `${this.userFirstName || ''} ${this.userLastName || ''}`.trim();
    }
    get profileMeta() {
        // "Alumni · Batch 2020" — drops the batch chunk if we don't have one yet.
        const parts = ['Alumni'];
        if (this.userBatch) parts.push(this.userBatch);
        return parts.join(' · ');
    }
    get showLocationChip() { return !!this.userLocation; }
    get showRoleChip() { return !!this.userTitleCompany; }
    get topbarTitle() {
        if (this.topbarTitleOverride) return this.topbarTitleOverride;
        if (this.activeNav === 'home') {
            const name = `${this.userFirstName || ''} ${this.userLastName || ''}`.trim();
            return name ? `Welcome back, ${name}` : 'Welcome back';
        }
        return NAV_TITLES[this.activeNav] || 'Alumni Portal';
    }

    isActiveNav(navId) { return this.activeNav === navId; }
    get homeNavClass()       { return this.isActiveNav('home')       ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get eventsNavClass()     { return this.isActiveNav('events')     ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get jobsNavClass()       { return this.isActiveNav('jobs')       ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get networkNavClass()    { return this.isActiveNav('network')    ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get mentorshipNavClass() { return this.isActiveNav('mentorship') ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get givingNavClass()     { return this.isActiveNav('giving')     ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get groupsNavClass()     { return this.isActiveNav('groups')     ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get feedbackNavClass()   { return this.isActiveNav('feedback')   ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get businessNavClass()   { return this.isActiveNav('business')   ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }
    get supportNavClass()    { return this.isActiveNav('support')    ? 'a2-nav__item a2-nav__item--active' : 'a2-nav__item'; }

    get brandLogoLetter() {
        if (this.brand === 'smu') return 'S';
        const inst = this.userInstitution || 'A';
        return inst.charAt(0).toUpperCase();
    }
    get brandName() {
        return this.brand === 'smu' ? 'Sikkim Manipal University Alumni' : this.userInstitution;
    }
}