import { LightningElement } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenJobs extends LightningElement {
    jobs = [
        {
            id: 'job-1',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-2',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-3',
            company: 'PayPal',
            title: 'Back-End Developer',
            type: 'Full-Time',
            experience: 'Fresher',
            location: 'Bangalore',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Admin',
            initials: 'P',
            color: 'brand-2'
        },
        {
            id: 'job-4',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-5',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-6',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-7',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-8',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-9',
            company: 'PayPal',
            title: 'Back-End Developer',
            type: 'Full-Time',
            experience: 'Fresher',
            location: 'Bangalore',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Admin',
            initials: 'P',
            color: 'brand-2'
        },
          {
            id: 'job-8',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-9',
            company: 'PayPal',
            title: 'Back-End Developer',
            type: 'Full-Time',
            experience: 'Fresher',
            location: 'Bangalore',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Admin',
            initials: 'P',
            color: 'brand-2'
        },
          {
            id: 'job-8',
            company: 'Google Pay',
            title: 'Sr. Design Associate',
            type: 'Full-Time',
            experience: '3-4 years experience',
            location: 'Remote',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Olivia Johnson',
            initials: 'G',
            color: 'brand-1'
        },
        {
            id: 'job-9',
            company: 'PayPal',
            title: 'Back-End Developer',
            type: 'Full-Time',
            experience: 'Fresher',
            location: 'Bangalore',
            salary: 'INR 15,00,000 - 20,00,000',
            postedBy: 'Admin',
            initials: 'P',
            color: 'brand-2'
        },
    ];

    appliedJobs = [
        {
            id: 'applied-1',
            company: 'Google Drive',
            title: 'Sr. Visual Designer',
            location: 'Bangalore, India',
            tags: ['Full-Time', 'Remote', 'Fintech'],
            initials: 'G',
            color: 'brand-3'
        },
        {
            id: 'applied-2',
            company: 'Reddit',
            title: 'Sr. Developer',
            location: 'Bangalore, India',
            tags: ['Full-Time', 'Remote', 'Fintech'],
            initials: 'R',
            color: 'brand-4'
        },
        {
            id: 'applied-3',
            company: 'ChirpNet',
            title: 'Lead Engineer',
            location: 'Tech City, India',
            tags: ['Part-Time', 'In-Office', 'Digital Finance'],
            initials: 'C',
            color: 'brand-5'
        }
    ];
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