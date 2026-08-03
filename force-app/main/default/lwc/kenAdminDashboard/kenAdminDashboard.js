import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPortalConfigs from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';
import getDashboardMetrics from '@salesforce/apex/KenAlumniAdminDashboardController.getDashboardMetrics';
import getLifecycleFunnel from '@salesforce/apex/KenAlumniAdminDashboardController.getLifecycleFunnel';
import getSourceDistribution from '@salesforce/apex/KenAlumniAdminDashboardController.getSourceDistribution';
import getDataHealthBreakdown from '@salesforce/apex/KenAlumniAdminDashboardController.getDataHealthBreakdown';
import getOnboardingTrend from '@salesforce/apex/KenAlumniAdminDashboardController.getOnboardingTrend';
import getEngagementSummary from '@salesforce/apex/KenAlumniAdminDashboardController.getEngagementSummary';
import getSuggestedActions from '@salesforce/apex/KenAlumniAdminDashboardController.getSuggestedActions';
import getCommunicationsSnapshot from '@salesforce/apex/KenAlumniAdminDashboardController.getCommunicationsSnapshot';
import getRecentActivity from '@salesforce/apex/KenAlumniAdminDashboardController.getRecentActivity';
import getProfileCompleteness from '@salesforce/apex/KenAlumniAdminDashboardController.getProfileCompleteness';
import getRegionalDemographics from '@salesforce/apex/KenAlumniAdminDashboardController.getRegionalDemographics';
import getAgeDistribution from '@salesforce/apex/KenAlumniAdminDashboardController.getAgeDistribution';
import getEmploymentStatus from '@salesforce/apex/KenAlumniAdminDashboardController.getEmploymentStatus';

const FALLBACK_PALETTE = ['#1E3A8A', '#14B8A6', '#4F46E5', '#3B82F6', '#06B6D4', '#94A3B8', '#7C5CF0', '#E11D48', '#D97706', '#059669'];

export default class KenAdminDashboard extends NavigationMixin(LightningElement) {
    metrics;
    lifecycleFunnel;
    sourceSlices;
    healthBars;
    trendPoints;
    trendHoverIdx = -1;
    engagementChannels;
    suggestedActions;
    commsSnapshot;
    recentActivity;
    completenessBuckets;
    regionRows;
    ageBars;
    employmentSlices;

    brandPalette = [];
    @track audience = 'all';

    @wire(getPortalConfigs)
    wiredTheme({ data }) {
        if (!data) return;
        const host = this.template.host;
        if (data.primaryColor) {
            host.style.setProperty('--brand-primary',      data.primaryColor);
            host.style.setProperty('--brand-primary-soft', this.toSoft(data.primaryColor));
        }
        if (data.secondaryColor) host.style.setProperty('--brand-secondary', data.secondaryColor);
        if (data.tertiaryColor)  host.style.setProperty('--brand-tertiary',  data.tertiaryColor);
        this.brandPalette = [data.primaryColor, data.secondaryColor, data.tertiaryColor].filter(Boolean);
        if (this.sourceSlicesRaw) this.recolorSourceSlices();
        if (this.employmentRaw)   this.recolorEmploymentSlices();
    }

    toSoft(hex) {
        if (!hex || typeof hex !== 'string') return 'rgba(185,28,92,.10)';
        const v = hex.replace('#', '');
        if (v.length !== 3 && v.length !== 6) return 'rgba(185,28,92,.10)';
        const expand = v.length === 3 ? v.split('').map(c => c + c).join('') : v;
        const r = parseInt(expand.slice(0, 2), 16);
        const g = parseInt(expand.slice(2, 4), 16);
        const b = parseInt(expand.slice(4, 6), 16);
        return `rgba(${r},${g},${b},.10)`;
    }

    paletteColor(i) {
        if (this.brandPalette.length > 0 && i < this.brandPalette.length) return this.brandPalette[i];
        return FALLBACK_PALETTE[i % FALLBACK_PALETTE.length];
    }

    recolorSourceSlices() {
        if (!this.sourceSlicesRaw) return;
        this.sourceSlices = this.sourceSlicesRaw.map((s, i) => ({
            label: s.label,
            value: s.value,
            color: this.paletteColor(i),
            style: `background:${this.paletteColor(i)}`
        }));
    }

    @wire(getDashboardMetrics)
    wiredMetrics({ data }) {
        if (data) this.metrics = data;
    }

    @wire(getLifecycleFunnel)
    wiredLifecycleFunnel({ data }) {
        if (data) this.lifecycleFunnel = this.decorateFunnel(data);
    }

    @wire(getSourceDistribution)
    wiredSource({ data }) {
        if (data) {
            this.sourceSlicesRaw = data;
            this.recolorSourceSlices();
        }
    }

    @wire(getDataHealthBreakdown)
    wiredHealth({ data }) {
        if (data) {
            this.healthBars = data.map(b => ({
                field: b.field,
                percent: b.percent,
                warning: b.warning,
                rowClass: b.warning ? 'dh-row amber' : 'dh-row',
                barClass: b.warning ? 'dh-bar amber' : 'dh-bar',
                fillStyle: `width:${b.percent}%`,
                percentLabel: `${b.percent}%`
            }));
        }
    }

    @wire(getOnboardingTrend)
    wiredTrend({ data }) {
        if (data) this.trendPoints = data;
    }

    @wire(getProfileCompleteness, { audience: '$audience' })
    wiredCompleteness({ data }) {
        if (data) {
            const palette = ['#10B981', '#22C55E', '#F59E0B', '#F97316', '#E11D48'];
            const max = data.reduce((m, b) => Math.max(m, b.count || 0), 0);
            this.completenessBuckets = data.map((b, i) => ({
                label: b.label,
                count: this.formatNumber(b.count),
                fillStyle: `width:${max === 0 ? 0 : Math.round(100 * b.count / max)}%;background:${palette[i % palette.length]}`
            }));
        }
    }

    @wire(getRegionalDemographics, { audience: '$audience' })
    wiredRegions({ data }) {
        if (data) {
            this.regionRows = data.map(r => ({
                city: r.city,
                count: this.formatNumber(r.count),
                barStyle: `width:${r.percent}%`
            }));
        }
    }

    @wire(getAgeDistribution, { audience: '$audience' })
    wiredAge({ data }) {
        if (data) {
            const max = data.reduce((m, b) => Math.max(m, b.count || 0), 0);
            this.ageBars = data.map(b => ({
                label: b.label,
                count: b.count,
                fillStyle: `height:${max === 0 ? 0 : Math.round(100 * b.count / max)}%`
            }));
        }
    }

    @wire(getEmploymentStatus, { audience: '$audience' })
    wiredEmployment({ data }) {
        if (data) this.employmentRaw = data;
        this.recolorEmploymentSlices();
    }

    recolorEmploymentSlices() {
        if (!this.employmentRaw) return;
        const palette = ['#10476e', '#14B8A6', '#E11D48', '#D97706', '#059669', '#CBD5E1'];
        this.employmentSlices = this.employmentRaw.map((s, i) => {
            const c = palette[i % palette.length];
            return {
                label: s.label,
                count: s.count,
                percent: s.percent,
                color: c,
                dotStyle: `background:${c}`
            };
        });
    }

    @wire(getEngagementSummary)
    wiredEngagement({ data }) {
        if (data) {
            this.engagementChannels = data.map((c, i) => {
                const repeat = c.repeatRatePct || 0;
                const reach = c.reachPct || 0;
                let insightVariant = '';
                if (!c.trendingUp) insightVariant = 'red';
                else if (repeat < 30 || (reach > 0 && reach < 10)) insightVariant = 'amber';
                return {
                    key: `${c.channel}-${i}`,
                    channel: c.channel,
                    reachPctLabel: `${c.reachPct}%`,
                    engagedLabel: `${this.formatNumber(c.engaged)} engaged of ${this.formatNumber(this.metrics ? this.metrics.totalAlumni : c.engaged)}`,
                    active90d: this.formatNumber(c.active90d),
                    active90dShare: c.engaged > 0 ? `${Math.round((c.active90d / c.engaged) * 100)}% of engaged` : '—',
                    repeatRatePctLabel: `${c.repeatRatePct}%`,
                    newPerMonthLabel: `+${this.formatNumber(c.newPerMonth)}`,
                    trendingUp: c.trendingUp,
                    trendClass: c.trendingUp ? 'eng-trend up' : 'eng-trend down',
                    trendLabel: c.trendingUp ? '↗ 90d' : '↘ 90d',
                    insight: c.insight,
                    insightClass: insightVariant ? `eng-insight ${insightVariant}` : 'eng-insight'
                };
            });
        }
    }

    @wire(getSuggestedActions)
    wiredActions({ data }) {
        if (data) {
            this.suggestedActions = data.map((a, i) => ({
                key: `${a.ctaKey}-${i}`,
                message: a.message,
                ctaLabel: a.ctaLabel,
                ctaKey: a.ctaKey
            }));
        }
    }

    @wire(getCommunicationsSnapshot)
    wiredComms({ data }) {
        if (data) this.commsSnapshot = data;
    }

    @wire(getRecentActivity)
    wiredActivity({ data }) {
        if (data) {
            this.recentActivity = data.map((a, i) => ({
                key: `${i}-${a.occurredAt}`,
                title: a.title,
                actor: a.actor,
                occurredAt: a.occurredAt,
                relative: this.relativeTime(a.occurredAt)
            }));
        }
    }

    decorateFunnel(f) {
        const FILTER_KEYS = {
            lifecycle: ['life-leads', 'life-registered', 'life-onboarding', 'life-active']
        };
        const keys = FILTER_KEYS[f.funnelKey] || [];
        return {
            funnelKey: f.funnelKey,
            title: f.title,
            steps: (f.steps || []).map((s, i) => ({
                key: `${f.funnelKey}-${i}`,
                label: s.label,
                value: this.formatCompact(s.value),
                showArrow: i > 0,
                dashboardFilter: keys[i] || ''
            }))
        };
    }

    handleAudienceChange(evt) {
        const v = evt.currentTarget.dataset.audience || 'all';
        if (v === this.audience) return;
        this.audience = v;
    }

    get qrTabAllClass()    { return 'qr-tab' + (this.audience === 'all'    ? ' active' : ''); }
    get qrTabActiveClass() { return 'qr-tab' + (this.audience === 'active' ? ' active' : ''); }
    get audienceTotalDisplay() {
        if (!this.metrics) return '—';
        return this.audience === 'active'
            ? this.formatNumber(this.metrics.portalRegistered)
            : this.formatNumber(this.metrics.totalAlumni);
    }
    get audienceMetaLabel() {
        return this.audience === 'active'
            ? 'Registered and active on the new portal'
            : 'Everyone in the master database (incl. unregistered, leads, referrals)';
    }

    handleFunnelStepClick(evt) {
        const dashboardFilter = evt.currentTarget.dataset.dashboardfilter || '';
        this._navigateToMasterRecords(dashboardFilter);
    }

    handleKpiClick(evt) {
        const dashboardFilter = evt.currentTarget.dataset.dashboardfilter || '';
        this._navigateToMasterRecords(dashboardFilter);
    }

    _navigateToMasterRecords(dashboardFilter) {
        const intent = { tabKey: 'all', portalStatus: '', dashboardFilter, ts: Date.now() };
        try {
            sessionStorage.setItem('ken_dashboard_nav', JSON.stringify(intent));
        } catch (e) { /* sessionStorage may be blocked */ }
        try {
            window.dispatchEvent(new CustomEvent('kendash:navigate', { detail: intent }));
        } catch (e) { /* ignore */ }
        this.dispatchEvent(new CustomEvent('dashboardnavigate', {
            bubbles: true, composed: true,
            detail: { destination: 'masterRecords', ...intent }
        }));
        this._switchFlexipageTab('Master Records');
    }

    handleReportClick(evt) {
        const reportKey = evt.currentTarget.dataset.reportkey || '';
        try {
            sessionStorage.setItem('ken_dashboard_report', JSON.stringify({
                reportKey, ts: Date.now()
            }));
        } catch (e) { /* sessionStorage may be blocked */ }
        this.dispatchEvent(new CustomEvent('dashboardnavigate', {
            bubbles: true, composed: true,
            detail: { destination: 'reports', reportKey }
        }));
        if (!this._switchFlexipageTab('Report')) {
            this._switchFlexipageTab('Reports');
        }
    }

    /**
     * The admin console is one FlexiPage whose tabset always starts on
     * Dashboard, and its selection is not part of the URL. So when the address
     * bar describes a Master Records screen — a refresh, or a pasted deep link
     * like ?c__page=alumni360&c__alumni=… — reopen that sub-tab. kenAdminAlumni
     * then restores the rest of the screen from the same params as it mounts.
     *
     * This runs only on the very first render: the tab anchors have to exist
     * before they can be clicked, and once the admin has moved around by hand
     * their choice must not be overridden.
     */
    renderedCallback() {
        if (this._deepLinkChecked) return;
        this._deepLinkChecked = true;
        let page = '';
        try {
            const params = new URLSearchParams(window.location.search);
            page = params.get('c__page') || params.get('page') || '';
        } catch (e) {
            return;
        }
        // page=list counts too: it means the admin was on the Master Records
        // list itself, which is just as much "where I was" as the 360 is.
        page = page.replace(/^['"]|['"]$/g, '').trim();
        if (!page) return;
        // The tabset can render a beat after this component does.
        let attempts = 0;
        const tryOpen = () => {
            if (this._switchFlexipageTab('Master Records')) return;
            if (++attempts < 10) setTimeout(tryOpen, 150);
        };
        tryOpen();
    }

    _switchFlexipageTab(label) {
        try {
            const anchors = document.querySelectorAll('a[role="tab"], [role="tab"]');
            for (const a of anchors) {
                const t = (a.title || a.getAttribute('aria-label') || a.textContent || '').trim();
                if (t === label) {
                    a.click();
                    return true;
                }
            }
        } catch (e) { /* cross-shadow may block */ }
        return false;
    }

    formatCompact(n) {
        if (n === null || n === undefined) return '0';
        const abs = Math.abs(n);
        if (abs >= 1000) {
            const v = n / 1000;
            return `${v.toFixed(v < 10 ? 1 : 0)}k`;
        }
        return String(n);
    }

    formatNumber(n) {
        if (n === null || n === undefined) return '0';
        return Number(n).toLocaleString();
    }

    relativeTime(ts) {
        if (!ts) return '';
        const then = new Date(ts).getTime();
        const now = Date.now();
        const diff = Math.max(0, now - then);
        const mins = Math.floor(diff / 60000);
        if (mins < 1) return 'just now';
        if (mins < 60) return `${mins} min${mins === 1 ? '' : 's'} ago`;
        const hours = Math.floor(mins / 60);
        if (hours < 24) return `${hours} hour${hours === 1 ? '' : 's'} ago`;
        const days = Math.floor(hours / 24);
        if (days < 30) return `${days} day${days === 1 ? '' : 's'} ago`;
        const months = Math.floor(days / 30);
        if (months < 12) return `${months} month${months === 1 ? '' : 's'} ago`;
        const years = Math.floor(months / 12);
        return `${years} year${years === 1 ? '' : 's'} ago`;
    }

    /* ============================================================
       Getters — loading / empty / formatted KPI display
       ============================================================ */
    get hasMetrics() { return !!this.metrics; }
    get isLoadingMetrics() { return !this.metrics; }
    get unverifiedLeadsDisplay() { return this.hasMetrics ? this.formatNumber(this.metrics.unverifiedLeads) : '—'; }
    get registeredAlumniDisplay() { return this.hasMetrics ? this.formatNumber(this.metrics.registeredAlumni) : '—'; }
    get activeAlumniDisplay() { return this.hasMetrics ? this.formatNumber(this.metrics.activeAlumni) : '—'; }

    get isLoadingLifecycle() { return !this.lifecycleFunnel; }
    get lifecycleTitle() { return this.lifecycleFunnel ? this.lifecycleFunnel.title : 'Lead Lifecycle'; }

    get isLoadingSource() { return !this.sourceSlices; }
    get hasSource() { return this.sourceSlices && this.sourceSlices.length > 0; }
    get isSourceEmpty() { return this.sourceSlices && this.sourceSlices.length === 0; }

    get isLoadingHealth() { return !this.healthBars; }
    get hasHealth() { return this.healthBars && this.healthBars.length > 0; }
    get isHealthEmpty() { return this.healthBars && this.healthBars.length === 0; }

    get isLoadingTrend() { return !this.trendPoints; }
    get isTrendEmpty() { return this.trendPoints && this.trendPoints.length === 0; }

    get isLoadingEngagement() { return !this.engagementChannels; }
    get hasEngagement() { return this.engagementChannels && this.engagementChannels.length > 0; }
    get isEngagementEmpty() { return this.engagementChannels && this.engagementChannels.length === 0; }

    get isLoadingActions() { return !this.suggestedActions; }
    get hasActions() { return this.suggestedActions && this.suggestedActions.length > 0; }
    get isActionsEmpty() { return this.suggestedActions && this.suggestedActions.length === 0; }

    get isLoadingComms() { return !this.commsSnapshot; }
    get messagesSentDisplay() { return this.commsSnapshot ? this.formatNumber(this.commsSnapshot.messagesSent) : '—'; }
    get campaignsDisplay() { return this.commsSnapshot ? `across ${this.commsSnapshot.campaigns} campaigns` : ''; }
    get deliveryDisplay() { return this.commsSnapshot ? `${this.commsSnapshot.deliveryPct}%` : '—'; }
    get bouncedDisplay() { return this.commsSnapshot ? `${this.commsSnapshot.bouncedPct}%` : '—'; }
    get openRateDisplay() { return this.commsSnapshot ? `${this.commsSnapshot.openRatePct}%` : '—'; }
    get clickRateDisplay() { return this.commsSnapshot ? `${this.commsSnapshot.clickRatePct}%` : '—'; }
    get emailSentDisplay() { return this.commsSnapshot ? this.formatNumber(this.commsSnapshot.emailSent) : '—'; }
    get whatsappSentDisplay() { return this.commsSnapshot ? this.formatNumber(this.commsSnapshot.whatsappSent) : '—'; }
    get smsSentDisplay() { return this.commsSnapshot ? this.formatNumber(this.commsSnapshot.smsSent) : '—'; }
    get scheduledDisplay() { return this.commsSnapshot ? this.formatNumber(this.commsSnapshot.scheduled) : '—'; }
    get awaitingReplyDisplay() { return this.commsSnapshot ? this.formatNumber(this.commsSnapshot.awaitingReply) : '—'; }

    get isLoadingActivity() { return !this.recentActivity; }
    get hasActivity() { return this.recentActivity && this.recentActivity.length > 0; }
    get isActivityEmpty() { return this.recentActivity && this.recentActivity.length === 0; }

    get isLoadingCompleteness() { return !this.completenessBuckets; }
    get isCompletenessEmpty() { return this.completenessBuckets && this.completenessBuckets.length === 0; }

    get isLoadingRegions() { return !this.regionRows; }
    get isRegionsEmpty() { return this.regionRows && this.regionRows.length === 0; }

    get isLoadingAge() { return !this.ageBars; }
    get isAgeEmpty() {
        if (!this.ageBars) return false;
        return this.ageBars.every(b => (b.count || 0) === 0);
    }

    get isLoadingEmployment() { return !this.employmentSlices; }
    get isEmploymentEmpty() { return this.employmentSlices && this.employmentSlices.length === 0; }

    get employmentDonutStyle() {
        if (!this.employmentSlices || this.employmentSlices.length === 0) {
            return 'background:conic-gradient(var(--slate-200) 0 360deg)';
        }
        const total = this.employmentSlices.reduce((s, x) => s + (x.count || 0), 0);
        if (total === 0) return 'background:conic-gradient(var(--slate-200) 0 360deg)';
        let acc = 0;
        const stops = this.employmentSlices.map(s => {
            const start = acc;
            acc += (s.count || 0) / total * 360;
            return `${s.color} ${start}deg ${acc}deg`;
        });
        return `background:conic-gradient(${stops.join(',')})`;
    }

    /* CSS conic-gradient donut */
    get donutGradientStyle() {
        if (!this.sourceSlices || this.sourceSlices.length === 0) {
            return 'background:conic-gradient(var(--slate-200) 0 360deg)';
        }
        const total = this.sourceSlices.reduce((s, x) => s + (x.value || 0), 0);
        if (total === 0) return 'background:conic-gradient(var(--slate-200) 0 360deg)';
        let acc = 0;
        const stops = this.sourceSlices.map(s => {
            const start = acc;
            acc += (s.value || 0) / total * 360;
            return `${s.color} ${start}deg ${acc}deg`;
        });
        return `background:conic-gradient(${stops.join(',')})`;
    }

    /* Trend line SVG (viewBox 0 0 600 200) — 3 series with axis ticks */
    get trendChartMax() {
        if (!this.trendPoints || this.trendPoints.length === 0) return 1;
        let m = 0;
        for (const p of this.trendPoints) {
            m = Math.max(m, p.registered || 0, p.invited || 0, p.active || 0);
        }
        return Math.max(1, m);
    }
    _seriesDots(field) {
        if (!this.trendPoints || this.trendPoints.length === 0) return [];
        const max = this.trendChartMax;
        const step = this.trendPoints.length > 1 ? 600 / (this.trendPoints.length - 1) : 0;
        return this.trendPoints.map((p, i) => ({
            label: p.label,
            x: Math.round(i * step),
            y: Math.round(200 - ((p[field] || 0) / max) * 180 - 10)
        }));
    }
    get trendDots() { return this._seriesDots('registered'); }
    get trendInvitedPoints() {
        return this._seriesDots('invited').map(d => `${d.x},${d.y}`).join(' ');
    }
    get trendActivePoints() {
        return this._seriesDots('active').map(d => `${d.x},${d.y}`).join(' ');
    }
    get trendLinePoints() {
        return this.trendDots.map(d => `${d.x},${d.y}`).join(' ');
    }
    get trendAreaPoints() {
        const dots = this.trendDots;
        if (dots.length === 0) return '';
        return `0,200 ${dots.map(d => `${d.x},${d.y}`).join(' ')} 600,200`;
    }
    handleTrendMove(evt) {
        if (!this.trendPoints || this.trendPoints.length < 2) return;
        const rect = evt.currentTarget.getBoundingClientRect();
        if (rect.width <= 0) return;
        const x = evt.clientX - rect.left;
        const n = this.trendPoints.length;
        let idx = Math.round((x / rect.width) * (n - 1));
        if (idx < 0) idx = 0;
        if (idx > n - 1) idx = n - 1;
        this.trendHoverIdx = idx;
    }
    handleTrendLeave() {
        this.trendHoverIdx = -1;
    }
    get trendHover() {
        const i = this.trendHoverIdx;
        if (i < 0 || !this.trendPoints || !this.trendPoints[i]) return null;
        const p = this.trendPoints[i];
        const reg = this._seriesDots('registered')[i];
        const inv = this._seriesDots('invited')[i];
        const act = this._seriesDots('active')[i];
        const n = this.trendPoints.length;
        const leftPct = n > 1 ? (i / (n - 1)) * 100 : 0;
        const flip = leftPct > 70;
        return {
            label: p.label,
            x: reg.x,
            regY: reg.y,
            invY: inv.y,
            actY: act.y,
            registered: p.registered || 0,
            invited: p.invited || 0,
            active: p.active || 0,
            tooltipStyle: `left:${leftPct}%`,
            tooltipClass: flip ? 'trend-tooltip flip' : 'trend-tooltip'
        };
    }
    get trendYTicks() {
        const top = this.trendChartMax;
        const steps = 4;
        const out = [];
        for (let i = 0; i <= steps; i++) {
            const val = Math.round(top * (1 - i / steps));
            out.push({ value: val, y: Math.round(10 + (180 * i / steps)) });
        }
        return out;
    }

}