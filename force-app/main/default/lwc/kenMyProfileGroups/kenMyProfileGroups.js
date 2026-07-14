import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenMyProfileGroups extends LightningElement {
    @track groups = [
        {
            id: 1,
            name: '5K Runners Group',
            membersCount: '1.2k members',
            bannerUrl: 'https://cdn.dribbble.com/users/1769954/screenshots/11379768/media/682281a8b308e92822d56c52a061488c.png', // Artistic colorful banner
            isPrivate: true,
            status: '', // No status badge for first item
            statusClass: '',
            avatars: [
                'https://i.pravatar.cc/150?img=11',
                'https://i.pravatar.cc/150?img=12',
                'https://i.pravatar.cc/150?img=13'
            ],
            friendsText: 'Sajin and 24 friends are members'
        },
        {
            id: 2,
            name: 'IMS',
            membersCount: '1.2k members',
            bannerUrl: 'https://images.unsplash.com/photo-1506784983877-45594efa4cbe?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80', // Silhouette group sunset
            isPrivate: true,
            status: '',
            statusClass: '',
            avatars: [
                'https://i.pravatar.cc/150?img=4',
                'https://i.pravatar.cc/150?img=5',
                'https://i.pravatar.cc/150?img=6'
            ],
            friendsText: 'Sajin and 24 friends are members'
        },
        {
            id: 3,
            name: 'Entrepreneurs of Ken42',
            membersCount: '1.2k members',
            bannerUrl: 'https://images.unsplash.com/photo-1522071820081-009f0129c71c?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80', // People working
            isPrivate: true,
            status: 'In Review',
            statusClass: 'status-badge in-review',
            avatars: [
                'https://i.pravatar.cc/150?img=7',
                'https://i.pravatar.cc/150?img=8',
                'https://i.pravatar.cc/150?img=9'
            ],
            friendsText: 'Sajin and 24 friends are members'
        },
        {
            id: 4,
            name: 'Short film Enthusiasts',
            membersCount: '1.2k members',
            bannerUrl: 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80', // Abstract lights
            isPrivate: true,
            status: 'Rejected',
            statusClass: 'status-badge rejected',
            avatars: [
                'https://i.pravatar.cc/150?img=10',
                'https://i.pravatar.cc/150?img=14',
                'https://i.pravatar.cc/150?img=15'
            ],
            friendsText: 'Sajin and 24 friends are members'
        }
    ];

    handleCreateGroup() {
        console.log('Create a New Group clicked');
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