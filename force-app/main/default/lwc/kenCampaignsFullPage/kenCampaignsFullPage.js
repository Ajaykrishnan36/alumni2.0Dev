import { LightningElement, track } from 'lwc';
import CoverImage from '@salesforce/resourceUrl/PortalLoginImage';
import listYourBusinessImage from '@salesforce/resourceUrl/Listyourbusiness';
import { NavigationMixin } from 'lightning/navigation';

export default class KenCampaignsFullPage extends NavigationMixin(LightningElement) {

    illustrationImage = listYourBusinessImage;

    @track myCampaigns = [
        {
            id: '1',
            title: 'NextGen Campus',
            status: 'Ongoing',
            statusClass: 'status-badge ongoing-badge',
            showDot: true,
            date: '28 - 31 March, 2025',
            image: CoverImage
        },
        {
            id: '2',
            title: 'In Memory & Tribute',
            status: 'In Review',
            statusClass: 'status-badge in-review-badge',
            showDot: false,
            image: CoverImage
        },
        {
            id: '3',
            title: 'Fuel Dreams',
            status: 'Completed',
            statusClass: 'status-badge completed-badge',
            showDot: false,
            image: CoverImage
        }
    ];

    @track causes = [
        {
            id: '1',
            title: 'Student Scholarships',
            description: 'Support financially constrained students to get the best education they want..',
            image: CoverImage
        },
        {
            id: '2',
            title: 'Infrastructure Development',
            description: 'Give back to your alma mater fo its myraid critical needs..',
            image: CoverImage
        },
        {
            id: '3',
            title: 'Faculty Support & Research',
            description: 'Give back to your alma mater fo its myraid critical needs..',
            image: CoverImage
        },
        {
            id: '4',
            title: 'Emergency Relief',
            description: 'Provide assistance during sudden emergencies or crises..',
            image: CoverImage
        },
        {
            id: '5',
            title: 'Entrepreneurship & startups',
            description: 'Fund emerging startups and bold new ideas by alumni..',
            image: CoverImage
        },
        {
            id: '6',
            title: 'Memorial & tribute funds',
            description: 'Honor the legacy of alumni through meaningful contributions..',
            image: CoverImage
        }
    ];

    handleViewAllCampaigns() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Active_Campaigns__c'
            }
        });
    }

    handleExplore(event) {
        // Handle explore action
    }
    handleOpenFundraiseTabs(){
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'FundraiseTabs__c'
            },
           
           
        });
    }

    handleOpenCreateCampaign() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'create_campaign__c'
            }
        });
    }
}