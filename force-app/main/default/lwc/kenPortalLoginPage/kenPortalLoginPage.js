import { LightningElement, api, wire ,track} from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import CoverImageLeftSide from '@salesforce/resourceUrl/PortalLoginImage';	
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import basePath from '@salesforce/community/basePath';
import KenPoweredbyLogo from '@salesforce/resourceUrl/kenPoweredbyLogo';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import instituteWhiteLogo from '@salesforce/resourceUrl/instituteWhiteLogo';
export default class StudentPortalLoginPage extends NavigationMixin(LightningElement) {
    @track institutionName = '';
    @track isMobile = false;
    @track instituteWhiteLogo = instituteWhiteLogo;
    @track redirectingToReset = false;
    @api get crpage() {
        return this.currentPage;
    }
    set crpage(value) {
        this.currentPage = value;
    }
    carouselImage = CoverImageLeftSide;
    KenLogo = KenLogo;
    KenPoweredbyLogo = KenPoweredbyLogo;
    currentPage = 'login';
    email;
    startUrl;

    renderedCallback() {
        const style = document.createElement('style');
        style.innerText = `
            .slds-carousel__content { display: none; }
            .slds-carousel__autoplay { display: none; }
            .slds-carousel__panel-action { margin: 0; }
            .slds-carousel__indicators { display: none; }
        `;
        const carousel = this.template.querySelector('lightning-carousel');
        if (carousel) {
            carousel.appendChild(style);
        }
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        if (!currentPageReference || !currentPageReference.state) {
            return;
        }
        const isLoginPage = currentPageReference.state.isLoginPage;
        if (isLoginPage === 'true') {
            this.currentPage = 'login';
        }

        this.startUrl = currentPageReference.state.startURL;
    }

    get isLoginPage() {
        return this.currentPage === 'login';
    }

    // Feeds the hero image into the blurred background layer so the right side
    // (and the glass card) picks up a soft gradient derived from that image.
    get heroBgStyle() {
        return `--hero-bg: url(${this.carouselImage});`;
    }

    handleLogin() {
        this.currentPage = 'login';
    }

    get containerClass() {
        return this.isMobile ? 'loginPageRightContainer mobile-container' : 'loginPageRightContainer';
    }

    redirectToResetPasswordIfRequested() {
        try {
            let resetUrl = null;
            const stored = sessionStorage.getItem('AlumniPendingPasswordReset');
            if (stored) {
                sessionStorage.removeItem('AlumniPendingPasswordReset');
                const data = JSON.parse(stored);
                const email = data && data.email;
                if (email) {
                    resetUrl = `${basePath}/ForgotPassword?step=newpassword&email=${encodeURIComponent(email)}`;
                }
            }
            if (!resetUrl) {
                const params = new URLSearchParams(window.location.search || '');
                const redirectToReset = params.get('redirectToReset');
                const email = params.get('email');
                if (redirectToReset === '1' && email && email.trim()) {
                    resetUrl = `${basePath}/ForgotPassword?step=newpassword&email=${encodeURIComponent(email.trim())}`;
                }
            }
            if (resetUrl) {
                this.redirectingToReset = true;
                setTimeout(() => {
                    window.location.replace(resetUrl);
                }, 0);
            }
        } catch (e) {
            // ignore
        }
    }

    handleForgotPassword() {
        window.location.href = `${basePath}/ForgotPassword`;
    }

    handleSignup() {
        window.location.href = `${basePath}/SelfRegister`;
    }

    handleResendVerificationLink() {
        window.location.href = `${basePath}/SelfRegister`;
    }

    connectedCallback() {
        this.redirectToResetPasswordIfRequested();
        document.documentElement.style.setProperty('--primary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--secondary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--tertiary-color', '#FFFFFF');
        getPrimaryColor().then(color => {
            console.log(color,'color1234567890ajay');
            this.institutionName = color?.institutionName;
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        })
        this.isMobile = window.innerWidth <= 1024;
        window.addEventListener('resize', this.handleResize);
        const fontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Regular.woff2`;

        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: 'GeneralSansCustom';
                src: url('${fontUrl}') format('woff2');
                font-weight: normal;
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);

        const style2 = document.createElement('style');
        style2.innerText = `
            .salesforceIdentityLoginBody2 .cCenterPanel {
                max-width: none !important;
            }
        `;
        document.head.appendChild(style2);
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this.handleResize);
    }

    handleResize = () => {
        this.isMobile = window.innerWidth <= 1024;
    };
}