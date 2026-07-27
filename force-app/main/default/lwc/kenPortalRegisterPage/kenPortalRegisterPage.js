import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import CoverImageLeftSide from '@salesforce/resourceUrl/PortalLoginImage';	
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import KenPoweredbyLogo from '@salesforce/resourceUrl/kenPoweredbyLogo';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import instituteWhiteLogo from '@salesforce/resourceUrl/instituteWhiteLogo';
export default class KenPortalRegisterPage extends LightningElement {
    @track isMobile = false;
    @track institutionName = '';
    instituteWhiteLogo = instituteWhiteLogo;
    KenLogo = KenLogo;
    @api get crpage() {
        return this.currentPage;
    }
    set crpage(value) {
        this.currentPage = value;
    }
    carouselImage = CoverImageLeftSide;
    kenPoweredbyLogo = KenPoweredbyLogo;

    currentPage = 'register';
    email;
    startUrl;

    get isRegisterPage() {
        return this.currentPage === 'register';
    }

    // Feeds the hero image into the blurred background layer so the right side
    // (and the glass card) picks up a soft gradient derived from that image.
    get heroBgStyle() {
        return `--hero-bg: url(${this.carouselImage});`;
    }

    get containerClass() {
        return this.isMobile ? 'loginPageRightContainer mobile-container' : 'loginPageRightContainer';
    }

    handleLogin() {
        window.location.href = `${basePath}/login`;
    }

    connectedCallback() {
        this.isMobile = window.innerWidth <= 1024;
        document.documentElement.style.setProperty('--primary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--secondary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--tertiary-color', '#FFFFFF'); 
        getPrimaryColor().then(color => {
            this.institutionName = color?.institutionName;
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
            this.institutionName = 'Institute Name';
        });
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