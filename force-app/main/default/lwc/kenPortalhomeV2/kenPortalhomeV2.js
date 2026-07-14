import { LightningElement, api, track } from 'lwc';

const NAV = [
    { id: 'home',       label: 'Home',              icon: 'home' },
    { id: 'events',     label: 'Events',            icon: 'calendar' },
    { id: 'jobs',       label: 'Jobs',              icon: 'briefcase' },
    { id: 'network',    label: 'Network',           icon: 'users' },
    { id: 'mentorship', label: 'Mentorship',        icon: 'compass' },
    { id: 'giving',     label: 'Giving',            icon: 'heart' },
    { id: 'groups',     label: 'Groups',            icon: 'group' },
    { id: 'feedback',   label: 'Feedback & Survey', icon: 'chat' },
    { id: 'support',    label: 'Service & Support', icon: 'support' }
];

const QUICK_LINKS = [
    'Host an Event', 'Create a Group', 'Contribute Now',
    'Connect', 'Post your Business'
];

const BIRTHDAYS = [
    { id: 1, name: 'Priya Nambiar',  date: '22', month: 'Oct', avatarBg: '#E8B4D6' },
    { id: 2, name: 'Rahul Mehta',    date: '22', month: 'Oct', avatarBg: '#67A1C8' },
    { id: 3, name: 'Siddharth Iyer', date: '22', month: 'Oct', avatarBg: '#9D9D9D' },
    { id: 4, name: 'Liam Thompson',  date: '22', month: 'Oct', avatarBg: '#3F4A60' }
];

const RESOURCES = [
    { id: 1, title: 'Alumni Newsletter',       subtitle: 'October 2025',     color: '#3061FF' },
    { id: 2, title: 'Research Journal',        subtitle: 'Vol. 12',          color: '#19A974' },
    { id: 3, title: 'Placement Brochure',      subtitle: '2024-25',          color: '#B033C8' },
    { id: 4, title: 'Bangalore Alumni Meet',   subtitle: 'Recap PDF',        color: '#F59E0B' }
];

const BUSINESSES = [
    { id: 1, name: 'Quill World', tagline: 'Stationery', initial: 'Q', color: '#3061FF' },
    { id: 2, name: 'iCreate',     tagline: 'Design',     initial: 'i', color: '#B033C8' },
    { id: 3, name: 'Vortex',      tagline: 'Tech',       initial: 'V', color: '#19A974' },
    { id: 4, name: 'HereJump',    tagline: 'Travel',     initial: 'H', color: '#F59E0B' }
];

const FEED = [
    {
        id: 1, type: 'spotlight',
        title: 'In the Spotlight',
        subtitle: 'Ruby House : Inferia',
        excerpt: 'Ruby House has achieved an incredible milestone by winning for sports competitions for the third consecutive year, showcasing their unparalleled talent, teamwork, and dedication.',
        thumbColor: '#FFCB47'
    },
    {
        id: 2, type: 'event',
        title: 'Symposium Mania',
        excerpt: 'The symposium has been postponed due to unforeseen circumstances. The dates will be announced later.',
        meta: '06 Oct 2025  •  29 minutes ago',
        badge: 'News'
    },
    {
        id: 3, type: 'social',
        title: 'Creative thinking',
        excerpt: 'Embrace the power of creative thinking! It is a vital tool that helps us discover new possibilities, unlocking creativity is the key to innovative solutions and breakthroughs. Whether in business, arts, or everyday challenges, nurturing a creative mindset is the spark that transforms ideas into reality.',
        meta: 'Posted via LinkedIn',
        badge: 'Social Media'
    }
];

export default class KenPortalhomeV2 extends LightningElement {
    @api userFirstName = 'Joshua';
    @api userLastName = 'B';
    @api userBatch = 'Batch - 2018';
    @api institutionLogoUrl = '';

    @track activeNav = 'home';
    feedFilter = 'All';

    nav = NAV;
    quickLinks = QUICK_LINKS;
    feed = FEED;

    get birthdays() {
        return BIRTHDAYS.map((b) => ({ ...b, avatarStyle: `background: ${b.avatarBg}; color: #FFFFFF;` }));
    }
    get resources() {
        return RESOURCES.map((r) => ({ ...r, barStyle: `background: ${r.color};` }));
    }
    get businesses() {
        return BUSINESSES.map((b) => ({ ...b, logoStyle: `background: ${b.color}; color: #FFFFFF;` }));
    }

    get userFullName() { return `${this.userFirstName} ${this.userLastName}`.trim(); }
    get userInitial() { return (this.userFirstName || ' ').charAt(0).toUpperCase(); }

    get navItems() {
        return NAV.map((n) => ({
            ...n,
            isActive: n.id === this.activeNav,
            itemClass: n.id === this.activeNav ? 'nav__item nav__item--active' : 'nav__item',
            isHome: n.icon === 'home',
            isCalendar: n.icon === 'calendar',
            isBriefcase: n.icon === 'briefcase',
            isUsers: n.icon === 'users',
            isCompass: n.icon === 'compass',
            isHeart: n.icon === 'heart',
            isGroup: n.icon === 'group',
            isChat: n.icon === 'chat',
            isSupport: n.icon === 'support'
        }));
    }

    get feedDisplay() {
        return this.feed.map((f) => ({
            ...f,
            isSpotlight: f.type === 'spotlight',
            isEvent: f.type === 'event',
            isSocial: f.type === 'social'
        }));
    }

    handleNav(event) {
        const id = event.currentTarget.dataset.id;
        if (id) {
            this.activeNav = id;
            this.dispatchEvent(new CustomEvent('navigate', { detail: { id } }));
        }
    }
    handleViewNewsletter() {
        this.dispatchEvent(new CustomEvent('viewnewsletter'));
    }
    handleLogout() {
        this.dispatchEvent(new CustomEvent('logout'));
    }
}