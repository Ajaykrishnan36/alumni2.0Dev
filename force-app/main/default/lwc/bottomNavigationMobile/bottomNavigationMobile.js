import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';

// icons
import HomeIcon from '@salesforce/resourceUrl/HomeIcon'; 
import CalendarIcon from '@salesforce/resourceUrl/CalendarIconBottomNav'; 
import CampusLifeIcon from '@salesforce/resourceUrl/CampusLifeIcon'; 
import ResourcesIcon from '@salesforce/resourceUrl/ResourcesIcon';


// Active icons (gradient/highlight versions)
import HomeIconActive from '@salesforce/resourceUrl/HomeIconActive';
import CalendarIconActive from '@salesforce/resourceUrl/CalendarIconBottomNavActive';
import CampusLifeIconActive from '@salesforce/resourceUrl/CampusLifeIconActive';
import ResourcesIconActive from '@salesforce/resourceUrl/ResourcesIconActive';

export default class BottomNavigationMobile extends NavigationMixin(LightningElement) {
    @track activeTab = '';

    // Keep apiName for Navigate; pathSuffix used for URL detection (after basePath)
    menuItems = [
        { id: 1, label: 'Home', apiName: 'Home', icon: HomeIcon, iconActive: HomeIconActive, pathSuffix: '/' },
        { id: 2, label: 'Calendar', apiName: 'Calendar__c', icon: CalendarIcon, iconActive: CalendarIconActive, pathSuffix: '/calendar' },
        { id: 3, label: 'Events', apiName: 'events__c', icon: CampusLifeIcon, iconActive: CampusLifeIconActive, pathSuffix: '/events' },
        { id: 4, label: 'Resources', apiName: 'Resources__c', icon: ResourcesIcon, iconActive: ResourcesIconActive, pathSuffix: '/resources' }
    ];
    

    connectedCallback() {
        this.setActiveTabFromUrl();
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
    }

    // --- Helpers ---
    normalize(path) {
        return (path || '').toLowerCase().replace(/\/+$/,''); // trim trailing slash
    }

    // Detect current tab from URL (robust to trailing slashes and deeper routes)
    setActiveTabFromUrl() {
        try {
            const pathNow = this.normalize(window.location.pathname);
            const base = this.normalize(basePath);
            const rel = pathNow.startsWith(base) ? pathNow.slice(base.length) || '/' : pathNow;

            // Debug console to help you verify quickly
            // (leave these while testing)
            // eslint-disable-next-line no-console
            console.log('[BottomNav] basePath=', basePath, 'pathNow=', pathNow, 'rel=', rel);

            let active = '';
            if (rel === '' || rel === '/') {
                active = 'Home';
            } else if (rel.startsWith('/calendar')) {
                active = 'Calendar__c';
            } else if (rel.startsWith('/events')) {
                active = 'events__c';
            } else if (rel.startsWith('/resources')) {
                active = 'Resources__c';
            }
            this.activeTab = active;

            // eslint-disable-next-line no-console
            console.log('[BottomNav] activeTab set from URL ->', this.activeTab);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[BottomNav] setActiveTabFromUrl error', e);
        }
    }
get styledMenuItems() {
    return this.menuItems.map(item => {
        const isActive = item.apiName === this.activeTab;
        return {
            ...item,
            iconToShow: isActive ? item.iconActive : item.icon,
            class: isActive ? 'nav-item active-tab' : 'nav-item'
        };
    });
}


    handleNavigation(event) {
        const apiName = event.currentTarget.dataset.apiName;
        this.activeTab = apiName;
        // eslint-disable-next-line no-console
        console.log('[BottomNav] navigate ->', apiName, event.currentTarget.dataset);

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: apiName }
        });
    }
}