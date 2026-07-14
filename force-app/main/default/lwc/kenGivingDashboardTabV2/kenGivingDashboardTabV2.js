import { LightningElement, track, wire } from 'lwc';
import getDashboardMetrics  from '@salesforce/apex/KenGivingDashboardController.getDashboardMetrics';
import getDashboardRightRail from '@salesforce/apex/KenGivingDashboardController.getDashboardRightRail';
import getImpactUpdates     from '@salesforce/apex/KenGivingDashboardController.getImpactUpdates';
import getLeaderboard       from '@salesforce/apex/KenGivingDashboardController.getLeaderboard';

// Subtle indigo gradient used when an image record has no Image_URL__c. Defined here
// (not in CSS) so the same value applies to inline `style` overrides.
const IMG_FALLBACK = 'linear-gradient(135deg, #eef2ff 0%, #c7d2fe 60%, #a5b4fc 100%)';

function imgStyleFor(url) {
    if (url && /^https?:\/\//i.test(url)) {
        return `background-image:url('${String(url).replace(/'/g, "\\'")}');background-size:cover;background-position:center;`;
    }
    return `background:${IMG_FALLBACK};`;
}

export default class KenGivingDashboardTabV2 extends LightningElement {
    @track metrics = {};
    @track rail = { actionItems: [], recentContributors: [], corporateSupporters: [], privateContributorsCount: 0 };
    @track impactUpdates = [];
    @track leaderboard = [];
    loading = true;

    @wire(getDashboardMetrics)
    wiredMetrics({ data }) { if (data) { this.metrics = data; this.loading = false; } }

    @wire(getDashboardRightRail)
    wiredRail({ data }) { if (data) { this.rail = data; } }

    @wire(getImpactUpdates)
    wiredImpact({ data }) {
        if (data) {
            // Figma shows a maximum of 2 cards on the dashboard. Surplus updates live on
            // the dedicated Impact Updates tab (deep-linked via the "All updates →" CTA).
            this.impactUpdates = data.slice(0, 2).map(u => ({
                ...u,
                imgStyle: imgStyleFor(u.imageUrl),
                hasImage: !!(u.imageUrl && /^https?:\/\//i.test(u.imageUrl))
            }));
        }
    }

    @wire(getLeaderboard)
    wiredLeaderboard({ data }) { if (data) { this.leaderboard = data; } }

    get hasImpactUpdates() { return this.impactUpdates && this.impactUpdates.length > 0; }
    get hasLeaderboard() { return this.leaderboard && this.leaderboard.length > 0; }

    get hasActionItems() { return this.rail && this.rail.actionItems && this.rail.actionItems.length > 0; }
    get hasContributors() { return this.rail && this.rail.recentContributors && this.rail.recentContributors.length > 0; }
    get hasSupporters() { return this.rail && this.rail.corporateSupporters && this.rail.corporateSupporters.length > 0; }
    get privateLine() {
        const n = (this.rail && this.rail.privateContributorsCount) || 0;
        return n > 0 ? n + ' private not shown' : '';
    }
    get contributorRows() {
        return (this.rail.recentContributors || []).map(c => {
            const anon = c.isAnonymous === true;
            return {
                ...c,
                // Empty grey circle for anonymous, palette color for public donors.
                avatarStyle: anon
                    ? 'background:#e5e7eb;color:transparent;'
                    : 'background:' + (c.avatarColor || '#7c3aed') + ';color:#fff;',
                showInitial: !anon,
                amountClass: anon ? 'gd-contributor__amt gd-contributor__amt--private'
                                  : 'gd-contributor__amt'
            };
        });
    }

    // "All updates →" — let the parent wrapper switch the active tab.
    handleAllUpdates() {
        this.dispatchEvent(new CustomEvent('tabchange', {
            detail: { key: 'impact-updates' },
            bubbles: true,
            composed: true
        }));
    }
    get contributorsSubtotal() {
        // Show "+N kept private" on the metrics ribbon under contributor count.
        const p = (this.metrics && this.metrics.privateContributorsCount) || 0;
        return p > 0 ? '+' + p + ' kept private' : '';
    }
    get topBatchLine() {
        const m = this.metrics || {};
        if (!m.topBatchRaisedDisplay && !m.topBatchAlumni) return '';
        const parts = [];
        if (m.topBatchRaisedDisplay) parts.push(m.topBatchRaisedDisplay);
        if (m.topBatchAlumni) parts.push(m.topBatchAlumni + ' alumni');
        return parts.join(' · ');
    }
    get acrossLiveLine() {
        const n = (this.metrics && this.metrics.liveCampaignsCount) || 0;
        return n > 0 ? 'across ' + n + ' live campaigns' : 'across 0 live campaigns';
    }
    get liveAllApprovedLine() { return 'all institution-approved'; }
}