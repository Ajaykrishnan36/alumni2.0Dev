import { LightningElement, api, track } from 'lwc';

const SLIDES = [
    {
        id: 1,
        title: 'Be a Mentor to Your Alumni Community',
        description: 'Share your knowledge and support others. Mentoring can be enabled or paused anytime through your profile settings.',
        illustration: 'mentor'
    },
    {
        id: 2,
        title: 'Reconnect with Your Network',
        description: 'Find old classmates, see where they are now, and rebuild relationships that matter.',
        illustration: 'network'
    },
    {
        id: 3,
        title: 'Discover Events & Opportunities',
        description: 'Stay updated on reunions, fundraisers, jobs, and community events curated for you.',
        illustration: 'events'
    }
];

export default class KenWelcomePageV2 extends LightningElement {
    @api institutionName = '<Institution Name>';
    @api institutionLogoUrl = '';

    @track activeIndex = 0;

    get currentSlide() { return SLIDES[this.activeIndex]; }
    get isLast() { return this.activeIndex === SLIDES.length - 1; }
    get isFirst() { return this.activeIndex === 0; }
    get continueLabel() { return this.isLast ? 'Get Started' : 'Continue'; }
    get welcomeTitle() { return `Welcome to the ${this.institutionName} Alumni Network!`; }

    get dots() {
        return SLIDES.map((_, i) => ({
            key: `dot${i}`,
            dotClass: i === this.activeIndex ? 'dot dot--on' : 'dot'
        }));
    }
    get isMentor() { return this.currentSlide.illustration === 'mentor'; }
    get isNetwork() { return this.currentSlide.illustration === 'network'; }
    get isEvents() { return this.currentSlide.illustration === 'events'; }

    handleSkip() {
        this.dispatchEvent(new CustomEvent('skip'));
    }
    handleContinue() {
        if (this.isLast) {
            this.dispatchEvent(new CustomEvent('finish'));
        } else {
            this.activeIndex += 1;
        }
    }
    handleDot(event) {
        const i = Number(event.currentTarget.dataset.index);
        if (!Number.isNaN(i)) this.activeIndex = i;
    }
}