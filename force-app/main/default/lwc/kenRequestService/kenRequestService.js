import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getServices from '@salesforce/apex/KenServiceSupportController.getServices';
import getServiceOfferingDetail from '@salesforce/apex/KenServiceSupportController.getServiceOfferingDetail';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';

const DEFAULT_ICON_PATH = 'M12 2L2 7L12 12L22 7L12 2ZM2 17L12 22L22 17M2 12L12 17L22 12';
const GATE_PASS_CATEGORY = 'Gate_Pass';

export default class KenRequestService extends NavigationMixin(LightningElement) {
    @track serviceData = [];
    @track navigating = false;

    // Gate Pass type selector popup
    @track showPassTypeModal  = false;
    @track _pendingServiceId  = null;
    @track _visitorConstituentRoleId = null;
    @track showVisitorFormInModal = false;

    get showPassTypeSelector() { return this.showPassTypeModal && !this.showVisitorFormInModal; }
    get showVisitorInModal()   { return this.showPassTypeModal && this.showVisitorFormInModal; }

    handleSelectStudent() {
        this.showPassTypeModal = false;
        this._navigateToDetail(this._pendingServiceId);
    }

    handleSelectVisitor() {
        this.showVisitorFormInModal = true;
    }

    handleVisitorReady(event) {
        const { visitorContactId } = event.detail;
        this.showPassTypeModal = false;
        this.showVisitorFormInModal = false;
        // Store visitor contact ID so questionnaire page can reference it if needed
        if (visitorContactId) {
            localStorage.setItem('VisitorContactId', visitorContactId);
        }
        this._navigateToDetail(this._pendingServiceId);
    }

    handleVisitorBackInModal() {
        this.showVisitorFormInModal = false;
    }

    handleClosePassModal() {
        this.showPassTypeModal = false;
        this.showVisitorFormInModal = false;
        this._pendingServiceId = null;
        this._visitorConstituentRoleId = null;
    }

    stopProp(event) { event.stopPropagation(); }

    _navigateToDetail(serviceId) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'request_service_detail__c' },
            state: { serviceId }
        });
    }

    connectedCallback() {
        getColors().then(colors => { this.applyOrganizationTheme(colors); }).catch(() => {});
        this.loadServiceData();
    }

    get crumbs() {
        return [
            { label: 'Home', url: '' },
            { label: 'Service & Support', url: '/service-support' },
            { label: 'Request for a Service' }
        ];
    }

    applyOrganizationTheme(colors) {
        const host = this.template?.host?.style;
        if (!host || !colors) return;

        const primary = colors.primary || colors.primaryColor;
        const secondary = colors.secondary || colors.secondaryColor;

        if (primary && typeof primary === 'string') {
            host.setProperty('--primary-color', primary);
            host.setProperty('--brand-primary', primary);
        }
        if (secondary && typeof secondary === 'string') {
            host.setProperty('--secondary-color', secondary);
            host.setProperty('--primary-light', secondary);
        }
    }

    loadServiceData() {
        const constituentRoleId = localStorage.getItem('ConstituentRoleId');
        getServices({ constituentRoleId })
            .then(services => {
                this.serviceData = (services || []).map(service => ({
                    id: service.Id,
                    serviceId: service.Id,
                    title: service.Name,
                    description: service.Description__c || '',
                    name: service.Name,
                    category: service.Service_Category__c || '',
                    iconPath: DEFAULT_ICON_PATH
                }));
            })
            .catch(error => {
                console.error('Services load error', error);
            });
    }

    handleServiceClick(event) {
        if (this.navigating) return;

        const serviceId = event.currentTarget.dataset.serviceId;
        const offeringId = event.currentTarget.dataset.offeringId;
        const selectedService = this.serviceData.find(service => service.serviceId === serviceId || service.id === offeringId);

        if (!selectedService) return;

        const targetServiceId = selectedService.serviceId || selectedService.id;

        // Gate Pass: show Student/Visitor type selector popup before navigating
        if (selectedService.category === GATE_PASS_CATEGORY) {
            this._pendingServiceId = targetServiceId;
            this.showPassTypeModal  = true;
            this.showVisitorFormInModal = false;
            return;
        }

        this.navigating = true;
        getServiceOfferingDetail({ serviceId: targetServiceId })
            .then(result => {
                if (result && result.length > 0) {
                    this._navigateToDetail(targetServiceId);
                }
            })
            .catch(() => {})
            .finally(() => { this.navigating = false; });
    }
}