import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import LandingLogo from '@salesforce/resourceUrl/landingLogo';
import Casual1 from '@salesforce/resourceUrl/casual1';
import Casual2 from '@salesforce/resourceUrl/casual2';
import Casual3 from '@salesforce/resourceUrl/casual3';
import Event1 from '@salesforce/resourceUrl/Event1';
import Event2 from '@salesforce/resourceUrl/Event2';
import Event3 from '@salesforce/resourceUrl/Event3';
import Event4 from '@salesforce/resourceUrl/Event4';
import AlumniCommunityProfile1 from '@salesforce/resourceUrl/AlumniCommunityProfile1';
import AlumniCommunityProfile2 from '@salesforce/resourceUrl/AlumniCommunityProfile2';
import AlumniCommunityProfile3 from '@salesforce/resourceUrl/AlumniCommunityProfile3';
import AlumniCommunityCoverImg1 from '@salesforce/resourceUrl/AlumniCommunityCoverImg1';
import AlumniCommunityCoverImg2 from '@salesforce/resourceUrl/AlumniCommunityCoverImg2';
import AlumniCommunityCoverImg3 from '@salesforce/resourceUrl/AlumniCommunityCoverImg3';
import ClientLogoPost from '@salesforce/resourceUrl/clientLogoPost';
import InstaLogo from '@salesforce/resourceUrl/instaLogo';
import FacebookLogo from '@salesforce/resourceUrl/facebookLogo';
import LinkedinLogo from '@salesforce/resourceUrl/linkedinLogo';
import TwitterLogo from '@salesforce/resourceUrl/twitterLogo';
import StudentsSupported from '@salesforce/resourceUrl/StudentsSupported';
import YearsofGiving from '@salesforce/resourceUrl/YearsofGiving';
import CampaignsCompleted from '@salesforce/resourceUrl/CampaignsCompleted';
import CausesFunded from '@salesforce/resourceUrl/CausesFunded';
import FundraiserCoverImg from '@salesforce/resourceUrl/FundraiserCoverImg';
import NewsletterCoverImage1 from '@salesforce/resourceUrl/NewsletterCoverImage1';
import NewsletterCoverImage2 from '@salesforce/resourceUrl/NewsletterCoverImage2';
import NewsletterCoverImage3 from '@salesforce/resourceUrl/NewsletterCoverImage3';
import JointheAlumniPortalCoverImage from '@salesforce/resourceUrl/JointheAlumniPortalCoverImage';
import PoweredbyKen42WhiteColor from '@salesforce/resourceUrl/PoweredbyKen42WhiteColor';
import FIRA_SANS from '@salesforce/resourceUrl/firasansfont';
import Marcellus_Regular_Font from '@salesforce/resourceUrl/marcellusfont';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getEngagementOptions from '@salesforce/apex/KenEngagementPreferenceController.getOptions';
export default class KenLandingPage extends NavigationMixin(LightningElement) {
    landingLogo = LandingLogo;
    @track institutionName = '';
    @track preferences = [];
    event1 = Event1;
    event2 = Event2;
    event3 = Event3;
    event4 = Event4;
    communityCoverImg1 = AlumniCommunityCoverImg1;
    communityCoverImg2 = AlumniCommunityCoverImg2;
    communityCoverImg3 = AlumniCommunityCoverImg3;
    clientLogoPost = ClientLogoPost;
    instaLogo = InstaLogo;
    facebookLogo = FacebookLogo;
    linkedinLogo = LinkedinLogo;
    twitterLogo = TwitterLogo;
    fundraiserImage = FundraiserCoverImg;
    studentsSupported = StudentsSupported;
    yearsofGiving = YearsofGiving;
    campaignsCompleted = CampaignsCompleted;
    causesFunded = CausesFunded;
    newsletterCoverImage1 = NewsletterCoverImage1;
    newsletterCoverImage2 = NewsletterCoverImage2;
    newsletterCoverImage3 = NewsletterCoverImage3;
    joinPortalCoverImage = JointheAlumniPortalCoverImage;
    poweredByLogo = PoweredbyKen42WhiteColor;
    alumniProfile1 = AlumniCommunityProfile1;
    alumniProfile2 = AlumniCommunityProfile2;
    alumniProfile3 = AlumniCommunityProfile3;
    
    @track currentSlide = 0;
    @track isMenuOpen = false;
    
    carouselImages = [Casual1, Casual2, Casual3];
    
    connectedCallback() {  // use effect -> in react 
        getPrimaryColor().then(color => {
            this.institutionName = color?.institutionName;
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        // Load custom fonts
        this.loadCustomFonts();
        this.loadCustomFonts1();
        this.loadPreferences();
        // Auto-rotate carousel every 5 seconds
        this.carouselInterval = setInterval(() => {
            this.nextSlide();
        }, 5000);
    }

    get hasPreferences() {
        return this.preferences && this.preferences.length > 0;
    }

    // Loads active engagement preferences for the "Make a Difference" cards.
    loadPreferences() {
        getEngagementOptions()
            .then(records => {
                const list = Array.isArray(records) ? records : [];
                this.preferences = list.map(rec => {
                    const icon = rec.iconUrl || '';
                    const isSldsIcon = /^[a-z]+:[a-z0-9_]+$/i.test(icon);
                    const email = (rec.email || '').trim();
                    return {
                        id: rec.id,
                        name: rec.name,
                        description: rec.description,
                        iconUrl: icon,
                        isSldsIcon,
                        isImageIcon: !!icon && !isSldsIcon,
                        email,
                        mailtoHref: email
                            ? `mailto:${email}?subject=${encodeURIComponent(rec.name || 'Enquiry')}`
                            : null
                    };
                });
            })
            .catch(error => {
                console.error('Error loading engagement preferences', error);
                this.preferences = [];
            });
    }
    loadCustomFonts1() {
        // Get the base path properly
    
        const basePath = window.location.origin;
        const Marcellus = `${basePath}/sfsites/c/resource/marcellusfont/Marcellus-Regular.ttf`;
        const Marcellus2 = `${basePath}/sfsites/c/resource/marcellusfont/Marcellus-Regular.ttf`;
    
        const style = document.createElement('style');
        style.innerText = `
          @font-face {
            font-family: 'Marcellus';
            src: url('${Marcellus}') format('truetype');
            font-style: normal;
            font-display: swap;
          }
          @font-face {
            font-family: 'Marcellus2';
            src: url('${Marcellus2}') format('truetype');
            font-style: normal;
            font-display: swap;
          }
        `;
        document.head.appendChild(style);
      }
    loadCustomFonts() {
        // Get the base path properly
        const basePath = window.location.origin;
        // Load Fira Sans font from static resource
        // Try both paths: with subdirectory and root
        const firaSansBasePath = FIRA_SANS;
        const fontRegularUrl = `${firaSansBasePath}/FiraSans-Regular.woff2`;
        const fontMediumUrl = `${firaSansBasePath}/FiraSans-Medium.woff2`;
        const fontSemiBoldUrl = `${firaSansBasePath}/FiraSans-SemiBold.woff2`;
        const fontBoldUrl = `${firaSansBasePath}/FiraSans-Bold.woff2`;
        const fontExtraBoldUrl = `${firaSansBasePath}/FiraSans-ExtraBold.woff2`;
        
        // Fallback paths if files are in subdirectory
        const fontRegularUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-Regular.woff2`;
        const fontMediumUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-Medium.woff2`;
        const fontSemiBoldUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-SemiBold.woff2`;
        const fontBoldUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-Bold.woff2`;
        const fontExtraBoldUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-ExtraBold.woff2`;
        
        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontRegularUrl}') format('woff2'),
                     url('${fontRegularUrlAlt}') format('woff2');
                font-weight: 400;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontMediumUrl}') format('woff2'),
                     url('${fontMediumUrlAlt}') format('woff2');
                font-weight: 500;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontSemiBoldUrl}') format('woff2'),
                     url('${fontSemiBoldUrlAlt}') format('woff2');
                font-weight: 600;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontBoldUrl}') format('woff2'),
                     url('${fontBoldUrlAlt}') format('woff2');
                font-weight: 700;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontExtraBoldUrl}') format('woff2'),
                     url('${fontExtraBoldUrlAlt}') format('woff2');
                font-weight: 800;
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);
    }
    
    disconnectedCallback() {
        if (this.carouselInterval) {
            clearInterval(this.carouselInterval);
        }
    }
    
    get currentImage() {
        return this.carouselImages[this.currentSlide];
    }
    
    get backgroundImageStyle() {
        return `background-image: url('${this.currentImage}'); background-size: cover; background-position: center center; background-repeat: no-repeat;`;
    }
    
    get indicators() {
        return this.carouselImages.map((image, index) => ({
            index: index,
            isActive: this.currentSlide === index,
            cssClass: this.currentSlide === index ? 'indicator active' : 'indicator'
        }));
    }
    
    get event1Background() {
        return `background-image: url('${this.event1}');`;
    }
    
    get event2Background() {
        return `background-image: url('${this.event2}');`;
    }
    
    get event3Background() {
        return `background-image: url('${this.event3}');`;
    }
    
    get event4Background() {
        return `background-image: url('${this.event4}');`;
    }
    
    get ctaBackgroundStyle() {
        return `background-image: url('${this.joinPortalCoverImage}');`;
    }
    
    nextSlide() {
        this.currentSlide = (this.currentSlide + 1) % this.carouselImages.length;
    }
    
    handleIndicatorClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.goToSlide(index);
    }
    
    goToSlide(index) {
        this.currentSlide = index;
        // Reset auto-rotate timer
        if (this.carouselInterval) {
            clearInterval(this.carouselInterval);
        }
        this.carouselInterval = setInterval(() => {
            this.nextSlide();
        }, 5000);
    }

    handleLogin() {
        // Navigate to login page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Login'
            }
        });
    }

    handleJoin() {
        // Navigate to registration page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Register'
            }
        });
    }

    handleViewAllEvents() {
        // Navigate to events page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'All_Events'
            }
        });
    }

    toggleMenu() {
        this.isMenuOpen = !this.isMenuOpen;
    }

    closeMenu() {
        this.isMenuOpen = false;
    }

    handleNavClick(event) {
        event.preventDefault();
        const target = event.currentTarget.dataset.target;
        if (target === 'always' || target === 'join') {
            return;
        }
        // For mobile: close menu first, then scroll after DOM updates
        if (this.isMenuOpen) {
            this.closeMenu();
            requestAnimationFrame(() => {
                this.scrollToSection(target);
            });
        } else {
            this.scrollToSection(target);
        }
    }

    scrollToSection(sectionKey) {
        const targetEl = this.template.querySelector(`[data-section="${sectionKey}"]`);
        if (!targetEl) {
            return;
        }
        const header = this.template.querySelector('.landing-header');
        const headerHeight = header ? header.getBoundingClientRect().height : 0;
        // Prefer .landing-page if it scrolls; else try host (when :host has overflow); else window
        const landingPage = this.template.querySelector('.landing-page');
        const container = (landingPage && landingPage.scrollHeight > landingPage.clientHeight)
            ? landingPage
            : (this.scrollHeight > this.clientHeight ? this : null);
        if (container) {
            const containerRect = container.getBoundingClientRect();
            const targetRect = targetEl.getBoundingClientRect();
            const top = (targetRect.top - containerRect.top) + container.scrollTop - headerHeight;
            container.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
        } else {
            const targetRect = targetEl.getBoundingClientRect();
            const top = targetRect.top + (window.pageYOffset || document.documentElement.scrollTop) - headerHeight;
            window.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
        }
    }

    get mobileMenuClass() {
        return this.isMenuOpen ? 'mobile-menu active' : 'mobile-menu';
    }

    handleTestimonialsPrev() {
        const cardsContainer = this.template.querySelector('.testimonials-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.testimonial-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: -scrollAmount,
                behavior: 'smooth'
            });
        }
    }

    handleTestimonialsNext() {
        const cardsContainer = this.template.querySelector('.testimonials-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.testimonial-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: scrollAmount,
                behavior: 'smooth'
            });
        }
    }

    handleNewsletterPrev() {
        const cardsContainer = this.template.querySelector('.newsletter-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.newsletter-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: -scrollAmount,
                behavior: 'smooth'
            });
        }
    }

    handleNewsletterNext() {
        const cardsContainer = this.template.querySelector('.newsletter-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.newsletter-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: scrollAmount,
                behavior: 'smooth'
            });
        }
    }
}