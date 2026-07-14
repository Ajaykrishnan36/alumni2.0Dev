import { LightningElement, track, wire } from 'lwc';
import getHostedEvents from '@salesforce/apex/KenPortalEventController.getHostedEvents';
import bgimg from '@salesforce/resourceUrl/hostEvent';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getPrimaryColor from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';
export default class HostEvent extends NavigationMixin(LightningElement) {
    @track bgimage = bgimg;
    @track screenWidth = window.innerWidth;
    @track eventRequests = [];

    // @wire(getHostedEvents)
    // wiredHostedEvents({ error, data }) {
    //     if (data) {
    //         this.processEventData(data);
    //     } else if (error) {
    //         console.error('Error fetching hosted events:', error);
    //         this.eventRequests = [];
    //     }
    // }

    connectedCallback() {
        this.loadHostedEvents();
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
         const regularFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Regular.woff2`;
        const boldFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Light.woff2`;
        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: 'GeneralSansCustom';
                src: url('${regularFontUrl}') format('woff2');
                font-style: normal;
                font-display: swap;
            }
    
            @font-face {
                font-family: 'GeneralSansCustomBold';
                src: url('${boldFontUrl}') format('woff2');
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);
    }

    async loadHostedEvents() {
        try {
            const constituentRoleId = sessionStorage.getItem('ConstituentRoleId');
            const data = await getHostedEvents({ constituentRoleId });
            this.processEventData(data);
        } catch (error) {
            console.error('Error fetching hosted events:', error);
        }
    }

    processEventData(data) {
        this.eventRequests = data.map(event => {

            return {
                eventtitle: event.Name ? event.Name : 'No Title',
                id: event.Id,
                status: event.Event_Status__c ? this.getStatusText(event.Event_Status__c) : 'In review',
                imgurl: event.Event_banner__c ? event.Event_banner__c : ''
            };
        });
    }
 
    get hasEventRequests() {
        return this.eventRequests && Array.isArray(this.eventRequests) && this.eventRequests.length > 0;
    }

get processedEventRequests() {
    if (!this.eventRequests || !Array.isArray(this.eventRequests)) {
        return [];
    }

    const processedEvents = [...this.eventRequests];

    if (FORM_FACTOR === 'Large') {
        return processedEvents.slice(0, 3);
    } else {
        // Small (or anything else)
        return processedEvents.slice(0, 2);
    }
}
    getStatusText(status) {
        const statusMap = {
            'Pending Approval': 'In review',
            'Approved': 'Approved',
            'Reject': 'Rejected'
        };
        return statusMap[status] || status;
    }

    // Event handlers
    openModal() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'host_event__c'
            }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'hosted_events__c'
            }
        });
    }

    handleHostEvent() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'host_event__c'
            }
        });
    }
}