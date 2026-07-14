import { LightningElement, track } from 'lwc';
import AlumniAlt from '@salesforce/resourceUrl/eventTest2';
import AlumniAlt2 from '@salesforce/resourceUrl/eventTest1';

/*
 * Pure-visual home dashboard mockup.
 * Two states are captured from the design (see plan): 'activate' (new alumni,
 * Finish-setup + Activate-profile) and 'established' (everyday, Needs-attention).
 * No Apex / no data wiring — all content below is static placeholder data.
 * Flip DEFAULT_VIEW to switch states.
 */
const DEFAULT_VIEW = 'activate';

// Shared spotlight (Alumni of the Month + video) — identical in both states.
const SPOTLIGHT = {
    badge: 'ALUMNI OF THE MONTH',
    kicker: 'MAY 2026 · SPOTLIGHT',
    name: 'Priya Nambiar',
    meta: 'Batch 2013 · MCA · Group PM, Atlassian',
    quote: '"KU shaped how I think about products. Mentoring this year reminded me what made me curious in the first place."',
    image: AlumniAlt2,
    video: {
        badge: 'WATCH · 4 MIN',
        caption: '"Why I came back to mentor."',
        sub: 'Priya Nambiar · Batch 2013',
        thumb: AlumniAlt
    }
};

const ACTIVATE = {
    headerActionLabel: 'Continue setup',
    forYou: {
        subtitle: 'Match found · Batch 2020',
        chips: [
            { id: 'c1', variant: 'success', icon: 'utility:check', text: 'Batch 2020 record matched' },
            { id: 'c2', variant: 'warning', icon: 'utility:warning', text: '3 details need confirmation' },
            { id: 'c3', variant: 'info', icon: 'utility:groups', text: '24 batchmates already here' },
            { id: 'c4', variant: 'sky', icon: 'utility:link', text: 'Add LinkedIn for matches' }
        ]
    },
    list: {
        title: 'Finish setup',
        count: '3 of 7 done',
        items: [
            { id: 'l1', accent: 'indigo', icon: 'utility:company', title: 'Add current company & role', tag: 'PROFILE', sub: 'Helps 24 batchmates find you', action: 'Add', dark: true },
            { id: 'l2', accent: 'sky', icon: 'utility:link', title: 'Add LinkedIn profile', tag: 'LINK', sub: 'Auto-match with classmates', action: 'Add', dark: true },
            { id: 'l3', accent: 'green', icon: 'utility:location', title: 'Confirm current city', tag: 'VERIFY', sub: 'Bangalore on record', action: 'Confirm', dark: false },
            { id: 'l4', accent: 'amber', icon: 'utility:groups', title: 'Join Batch 2020 group', tag: 'GROUP', sub: '186 members · your batch', action: 'Join', dark: false },
            { id: 'l5', accent: 'red', icon: 'utility:adduser', title: 'Invite 5 classmates', tag: 'NETWORK', sub: '162 from Batch 2020 off-platform', action: 'Invite', dark: false }
        ]
    },
    quick: {
        subtitle: 'Most-used while activating',
        tiles: [
            { id: 'q1', tint: 'indigo', icon: 'utility:user', label: 'Complete profile', sub: '3 fields left' },
            { id: 'q2', tint: 'sky', icon: 'utility:link', label: 'Add LinkedIn', sub: 'Auto-match alumni' },
            { id: 'q3', tint: 'green', icon: 'utility:search', label: 'Find batchmates', sub: '24 already active' },
            { id: 'q4', tint: 'amber', icon: 'utility:groups', label: 'Join batch group', sub: '186 members' },
            { id: 'q5', tint: 'violet', icon: 'utility:adduser', label: 'Invite classmates', sub: '162 off-platform' },
            { id: 'q6', tint: 'red', icon: 'utility:case', label: 'Raise a ticket', sub: 'Help with verification' }
        ]
    },
    feed: [
        { id: 'f1', tag: 'REUNION', time: 'Today', title: 'Annual Alumni Reunion announced - Dec 14', img: AlumniAlt },
        { id: 'f2', tag: 'EVENT', time: '3d', title: 'Bangalore Alumni Meetup - Friday at The Lalit', img: AlumniAlt2 },
        { id: 'f3', tag: 'STORY', time: '4d', title: "Meera Shah launched iCreate's design platform", img: AlumniAlt },
        { id: 'f4', tag: 'CAMPUS', time: '1w', title: 'New Innovation Hub inaugurated by alumni donors', img: AlumniAlt2 },
        { id: 'f5', tag: 'NEWS', time: '1w', title: 'May alumni newsletter - NIRF Top 50 entry', img: AlumniAlt },
        { id: 'f6', tag: 'MENTOR', time: '1w', title: 'Q2 mentor sign-ups open - 48 students waiting', img: AlumniAlt2 },
        { id: 'f7', tag: 'AWARD', time: '2w', title: 'Three KU alumni named to Forbes 30 Under 30', img: AlumniAlt }
    ],
    contextual: {
        type: 'activate',
        badge: '3/7',
        title: 'Activate your alumni profile',
        sub: '4 steps remaining to unlock the full network',
        progressPct: 43,
        button: 'Continue setup'
    }
};

const ESTABLISHED = {
    headerActionLabel: 'Share an update',
    forYou: {
        subtitle: 'Highlights from your network and KU',
        chips: [
            { id: 'c1', variant: 'success', icon: 'utility:company', text: '3 alumni hiring PMs in Bangalore' },
            { id: 'c2', variant: 'warning', icon: 'utility:event', text: 'Bangalore Meetup - this Friday' },
            { id: 'c3', variant: 'info', icon: 'utility:groups', text: '8 batchmates joined this month' },
            { id: 'c4', variant: 'sky', icon: 'utility:world', text: 'KU enters NIRF Top 50' }
        ]
    },
    list: {
        title: 'Needs attention',
        count: '2 need action',
        items: [
            { id: 'l1', accent: 'red', icon: 'utility:edit', title: 'Recommendation - Aarav Sharma', tag: 'ACTION', sub: 'Due May 18', action: 'Write', dark: true },
            { id: 'l2', accent: 'indigo', icon: 'utility:file', title: 'Transcript request', tag: 'FEE', sub: '₹500 fee due', action: 'Pay', dark: true },
            { id: 'l3', accent: 'amber', icon: 'utility:knowledge_base', title: 'Mentor application - PM track', tag: 'REVIEW', sub: 'Submitted Apr 28', action: 'View', dark: false },
            { id: 'l4', accent: 'sky', icon: 'utility:event', title: 'Event proposal - Career Talk', tag: 'AWAITING', sub: 'Awaiting Dean approval', action: 'View', dark: false },
            { id: 'l5', accent: 'green', icon: 'utility:user', title: 'Alumni ID renewal - 2026', tag: 'REMINDER', sub: 'Upload current photo', action: 'Upload', dark: false }
        ]
    },
    quick: {
        subtitle: 'Most-used by alumni',
        tiles: [
            { id: 'q1', tint: 'green', icon: 'utility:company', label: 'Post a job', sub: 'Hire from KU' },
            { id: 'q2', tint: 'amber', icon: 'utility:event', label: 'Propose an event', sub: 'Talk · meetup · panel' },
            { id: 'q3', tint: 'violet', icon: 'utility:favorite', label: 'Offer to mentor', sub: '3 students waiting' },
            { id: 'q4', tint: 'indigo', icon: 'utility:edit', label: 'Make a request', sub: 'Transcript · letter · ID' },
            { id: 'q5', tint: 'sky', icon: 'utility:groups', label: 'Join a group', sub: 'Batch · city · interest' },
            { id: 'q6', tint: 'red', icon: 'utility:chat', label: 'Talk to KU', sub: 'Office hours with staff' }
        ]
    },
    feed: [
        { id: 'f1', tag: 'MOVE', time: '2d', title: 'Priya Nambiar moved to Atlassian as Group PM', img: AlumniAlt2 },
        { id: 'f2', tag: 'STORY', time: '3d', title: "Meera Shah launched iCreate's design platform", img: AlumniAlt },
        { id: 'f3', tag: 'RECAP', time: '5d', title: 'Bangalore Chapter - May meetup recap is live', img: AlumniAlt2 },
        { id: 'f4', tag: 'COHORT', time: '6d', title: 'Startup Founders Circle Q2 cohort opened', img: AlumniAlt },
        { id: 'f5', tag: 'NEWS', time: '1w', title: 'May alumni newsletter - NIRF Top 50 entry', img: AlumniAlt2 },
        { id: 'f6', tag: 'AWARD', time: '1w', title: 'Three KU alumni named to Forbes 30 Under 30', img: AlumniAlt },
        { id: 'f7', tag: 'MENTOR', time: '2w', title: 'Q2 mentor sign-ups open - 48 students waiting', img: AlumniAlt2 }
    ],
    contextual: {
        type: 'event',
        kicker: 'THIS FRIDAY',
        title: 'Bangalore Alumni Meetup',
        sub: '42 alumni attending · The Lalit',
        button: 'RSVP now'
    }
};

const DATASETS = { activate: ACTIVATE, established: ESTABLISHED };

export default class KenPortalhome extends LightningElement {
    @track viewMode = DEFAULT_VIEW;
    userName = 'Joshua B';
    spotlight = SPOTLIGHT;

    get vm() {
        return DATASETS[this.viewMode] || ACTIVATE;
    }

    get isActivate() {
        return this.viewMode === 'activate';
    }

    get greeting() {
        return `Welcome back, ${this.userName}`;
    }

    get headerActionLabel() {
        return this.vm.headerActionLabel;
    }

    get forYouSubtitle() {
        return this.vm.forYou.subtitle;
    }

    get chips() {
        return this.vm.forYou.chips.map((c) => ({
            ...c,
            cssClass: `chip chip-${c.variant}`
        }));
    }

    get listTitle() {
        return this.vm.list.title;
    }

    get listCount() {
        return this.vm.list.count;
    }

    get listItems() {
        return this.vm.list.items.map((i) => ({
            ...i,
            accentClass: `item-accent item-accent-${i.accent}`,
            iconWrapClass: `item-icon item-icon-${i.accent}`,
            btnClass: i.dark ? 'item-btn item-btn-dark' : 'item-btn item-btn-light'
        }));
    }

    get quickSubtitle() {
        return this.vm.quick.subtitle;
    }

    get quickTiles() {
        return this.vm.quick.tiles.map((t) => ({
            ...t,
            iconWrapClass: `tile-icon tile-icon-${t.tint}`
        }));
    }

    get feedItems() {
        return this.vm.feed;
    }

    get contextual() {
        return this.vm.contextual;
    }

    get isActivateCard() {
        return this.contextual.type === 'activate';
    }

    get isEventCard() {
        return this.contextual.type === 'event';
    }

    get progressStyle() {
        return `width: ${this.contextual.progressPct || 0}%`;
    }

    // Inert handlers — this is a visual mockup; wire to real actions later.
    handleHeaderAction() {
        // no-op (mockup)
    }

    handleItemAction(event) {
        // no-op (mockup) — event.currentTarget.dataset.id available when wired
        // eslint-disable-next-line no-unused-vars
        const _id = event.currentTarget.dataset.id;
    }

    handleTile(event) {
        // eslint-disable-next-line no-unused-vars
        const _id = event.currentTarget.dataset.id;
    }

    handleFeedItem(event) {
        // eslint-disable-next-line no-unused-vars
        const _id = event.currentTarget.dataset.id;
    }

    handleContextual() {
        // no-op (mockup)
    }

    handleFeedback() {
        // no-op (mockup)
    }
}