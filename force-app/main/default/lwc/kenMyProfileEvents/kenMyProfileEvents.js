import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenMyProfileEvents extends LightningElement {
    @track events = [
        {
            id: 1,
            title: 'Pitch Competitions',
            type: 'Free | One-day',
            dateTime: '12 Oct 23, 4pm - 4:45pm IST',
            location: 'Bangalore, India',
            participantsLabel: 'Maximum number of participants: 150',
            participantsCount: 150,
            status: 'In review',
            statusClass: 'status-badge in-review',
            showFeedbackBtn: false,
            isRejected: false
        },
        {
            id: 2,
            title: 'Pitch Competitions',
            type: 'Paid',
            dateTime: '12 Oct 23, 4pm - 4:45pm IST',
            location: 'Bangalore, India',
            participantsLabel: 'Total participants: 50',
            participantsCount: 50,
            status: 'Upcoming',
            statusClass: 'status-badge upcoming',
            showFeedbackBtn: true,
            isRejected: false
        },
        {
            id: 3,
            title: 'Startup Weekends',
            type: 'Free | Multi-day',
            dateTime: '12 Oct 23, 4pm - 4:45pm IST',
            location: 'Bangalore, India',
            participantsLabel: 'Total participants: 50',
            participantsCount: 50,
            status: 'Approved', // Screenshot says Approved (Green), but badge text might be 'Approved'? Badge says 'Approved' in screenshot 3? No, Screenshot 3 is Academic Records success. Screenshot 1 for Events shows 'Approved' for Startup Weekends.
            statusClass: 'status-badge approved',
            showFeedbackBtn: true,
            isRejected: false
        },
        {
            id: 4,
            title: 'Startup Weekends',
            type: 'Free | Multi-day',
            dateTime: '12 Oct 23, 4pm - 4:45pm IST',
            location: 'Bangalore, India',
            participantsLabel: 'Total participants: 50',
            participantsCount: 50,
            status: 'Rejected', // Implied by rejection box
            statusClass: 'status-badge rejected', // Not shown in screenshot, usually hidden or implicit? Screenshot 4 bottom: No badge visible, but "Reason for rejection" box.
            showFeedbackBtn: false,
            isRejected: true,
            rejectionReason: 'The requested venue is not available on the selected dates',
            rejectionTitle: 'Venue not available'
        }
    ];

    handleHostEvent() {
        console.log('Host event clicked');
    }

    handleSetupFeedback(event) {
        const eventId = event.target.dataset.id;
        console.log('Setup feedback for event', eventId);
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