import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getUserHistory from '@salesforce/apex/KenServiceSupportController.getUserHistory';
import getPrimaryColor from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';

export default class KenPortalViewAllTickets extends NavigationMixin(LightningElement) {
    @track serviceHistoryData = [];
    @track supportHistoryData = [];
    @track activeTab = 'service';

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        this.loadHistory();
    }

    loadHistory() {
        getUserHistory()
            .then(result => {
                this.serviceHistoryData = result?.serviceHistory || [];
                this.supportHistoryData = result?.supportHistory || [];
            })
            .catch(error => {
                console.error('History Error:', error);
                this.serviceHistoryData = [];
                this.supportHistoryData = [];
            });
    }

    handleTabChange(event) {
        this.activeTab = event.detail;
    }

    handleTicketSelect(event) {
        const { caseId } = event.detail || {};
        if (!caseId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `/service-support/ticket-detail-view?caseId=${caseId}`
            }
        });
    }

    handleFileDownload(event) {
        const fileUrl = event.detail.fileUrl || event.detail.fileName;
        if (fileUrl) {
            window.open(fileUrl, '_blank');
        }
    }
}