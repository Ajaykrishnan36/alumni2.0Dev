import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenMyProfileBusinesses extends LightningElement {
    @track businesses = [
        {
            id: 1,
            name: 'SpaceMan',
            location: 'Chennai, India',
            category: 'Technology',
            status: 'In review',
            statusClass: 'status-badge in-review',
            iconUrl: 'https://i.pravatar.cc/150?u=spaceman', // Placeholder
            isRejected: false,
            isActive: false,
            isDeactivated: false
        },
        {
            id: 2,
            name: 'SpaceMan',
            location: 'Chennai, India',
            category: 'Technology',
            status: 'Active',
            statusClass: 'status-badge active',
            iconUrl: 'https://i.pravatar.cc/150?u=spaceman2',
            isRejected: false,
            isActive: true,
            isDeactivated: false
        },
        {
            id: 3,
            name: 'SpaceMan',
            location: 'Chennai, India',
            category: 'Technology',
            status: 'Rejected',
            statusClass: 'status-badge rejected',
            iconUrl: 'https://i.pravatar.cc/150?u=spaceman3',
            isRejected: true,
            isActive: false,
            isDeactivated: false,
            rejectionReason: 'The business contains incomplete or inaccurate information'
        },
        {
            id: 4,
            name: 'SpaceMan',
            location: 'Chennai, India',
            category: 'Technology',
            status: 'De-activated',
            statusClass: 'status-badge deactivated',
            iconUrl: 'https://i.pravatar.cc/150?u=spaceman4',
            isRejected: false,
            isActive: false,
            isDeactivated: true
        }
    ];

    handleListBusiness() {
        console.log('List Your Business clicked');
    }
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
}