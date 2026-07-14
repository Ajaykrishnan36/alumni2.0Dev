import { LightningElement, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import markLoggedInOnce from '@salesforce/apex/KenPortalOnbordingController.markLoggedInOnce';
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import WelcomeImage1 from '@salesforce/resourceUrl/welcomeImage1';
import WelcomeImage2 from '@salesforce/resourceUrl/welcomeImage2';
import WelcomeImage3 from '@salesforce/resourceUrl/welcomeImage3';
import kenPoweredbyLogoUrl from '@salesforce/resourceUrl/kenPoweredbyLogoUrl';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenWelcomePage extends LightningElement {
    @track currentSlide = 1;
    @track institutionName = '';
    roleId = '';

    connectedCallback() {
        getPrimaryColor().then(color => {
            this.institutionName = color?.institutionAlias;
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            this.institutionName = 'Ken42';
            console.log('Error getting primary color');
        });

        this.roleId = this.getRoleIdFromUrl() || window.localStorage.getItem('ConstituentRoleId') || '';
        if (this.roleId) {
            window.localStorage.setItem('ConstituentRoleId', this.roleId);
        }
    }
    kenLogoUrl = KenLogo;
    welcomeImage1Url = WelcomeImage1;
    welcomeImage2Url = WelcomeImage2;
    welcomeImage3Url = WelcomeImage3;
    kenPoweredbyLogoUrl = kenPoweredbyLogoUrl;

    getRoleIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            return url.searchParams.get('roleId');
        } catch (e) {
            return null;
        }
    }

    get isSlide1() {
        return this.currentSlide === 1;
    }

    get isSlide2() {
        return this.currentSlide === 2;
    }

    get isSlide3() {
        return this.currentSlide === 3;
    }

    get hasPrevious() {
        return this.currentSlide > 1;
    }

    get isFirstSlide() {
        return this.currentSlide === 1;
    }

    get isLastSlide() {
        return this.currentSlide === 3;
    }

    get buttonText() {
        if (this.currentSlide === 1) {
            return 'Continue';
        } else if (this.currentSlide === 3) {
            return 'Get Started';
        } else {
            return 'Next';
        }
    }

    get currentSlideDescription() {
        switch (this.currentSlide) {
            case 1:
                return 'Stay connected, grow professionally, and explore opportunities within a vibrant global alumni community.';
            case 2:
                return 'Stay connected, grow professionally, and explore opportunities within a vibrant global alumni community.';
            case 3:
                return 'Stay connected, grow professionally, and explore opportunities within a vibrant global alumni community.';
            default:
                return '';
        }
    }

    get rightSectionTitle() {
        switch (this.currentSlide) {
            case 1:
                return 'Be a mentor to your alumni community';
            case 2:
                return 'Get guidance from alumni who\'ve been there';
            case 3:
                return 'Discover, Connect & Grow';
            default:
                return '';
        }
    }

    get rightSectionSubtitle() {
        switch (this.currentSlide) {
            case 1:
                return 'Share your knowledge and support others. Mentoring can be enabled or paused anytime through your profile settings.';
            case 2:
                return 'Explore the alumni network to seek mentorship and guidance. Find the right mentor to help you plan your next step.';
            case 3:
                return 'Engage with groups, events, and alumni updates while building strong professional connections.';
            default:
                return '';
        }
    }

    get bar1Class() {
        return this.currentSlide === 1 ? 'pagination-bar active' : 'pagination-bar';
    }

    get bar2Class() {
        return this.currentSlide === 2 ? 'pagination-bar active' : 'pagination-bar';
    }

    get bar3Class() {
        return this.currentSlide === 3 ? 'pagination-bar active' : 'pagination-bar';
    }

    async handleNext() {
        if (this.currentSlide < 3) {
            this.currentSlide++;
            return;
        }

        try {
            await markLoggedInOnce({ roleId: this.roleId || null });
        } catch (error) {
            // best-effort update; still redirect
            console.error('Error marking login once', error);
        }

        window.location.href = `${basePath}/`;
    }

    handlePrevious() {
        if (this.currentSlide > 1) {
            this.currentSlide--;
        }
    }

    async handleSkip() {
        // Skip button works like "Get Started" - mark as logged in and redirect
        try {
            await markLoggedInOnce({ roleId: this.roleId || null });
        } catch (error) {
            // best-effort update; still redirect
            console.error('Error marking login once', error);
        }

        window.location.href = `${basePath}/`;
    }

    renderedCallback() {
        // Handle profile image errors
        const profileImages = this.template.querySelectorAll('.profile-image, .call-profile-image, .author-image');
        profileImages.forEach(img => {
            img.addEventListener('error', () => {
                img.src = '/assets/images/default-profile.png';
            });
        });
    }
}