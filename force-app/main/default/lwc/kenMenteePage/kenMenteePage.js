import { LightningElement, api, track } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

export default class KenMenteePage extends LightningElement {
    @api profileId;
    
    @track profileData = {
        name: 'Nupur Sharma1',
        title: 'Product Designer',
        company: 'Acme Corp',
        location: 'Bangalore',
        profileImage: defaultProfileImage,
        isOnline: true,
        batch: 'UG, Psychology 2022',
        expertise: 'Marketing and Advertising',
        email: 'nupu*****@gmail.com',
        phone: '+91 81694 *****',
        linkedin: 'https://linkedin.com/in/nupur-sharma',
        willingToHelp: true,
        about: 'I am a passionate person who likes to explore and learn new things in every phase of life. I believe in compassion, empathy, integrity, and unhindered dedication. I like to meet new people, connect with them, and be inspired by their journeys.',
        education: [
            {
                id: '1',
                degree: 'B Tech, Electronics and Media Technology',
                institution: 'Sikkim Manipal University',
                duration: '2010 - 2012',
                score: '7.5',
                logo: defaultProfileImage
            },
            {
                id: '2',
                degree: 'Higher Secondary School',
                institution: 'GRG Matric Hr Sec School',
                duration: '2016 - 2017',
                score: '95%',
                logo: defaultProfileImage
            },
            {
                id: '3',
                degree: 'Secondary School (SSLC)',
                institution: 'GRG Matric Hr Sec School',
                duration: '2014 - 2015',
                score: '80%',
                logo: defaultProfileImage
            }
        ],
        experience: [
            {
                id: '1',
                position: 'Sr. Design Associate',
                company: 'Northwind Labs',
                employmentType: 'Full-time',
                location: 'Coimbatore, Tamil Nadu, India',
                workType: 'Onsite',
                duration: 'May 2022 - Present | 1 yr 4 mos',
                companyLogo: defaultProfileImage
            },
            {
                id: '2',
                position: 'Front-end Developer',
                company: 'Contoso Systems',
                employmentType: 'Full-time',
                location: 'Chennai, Tamil Nadu, India',
                workType: 'Onsite',
                duration: 'May 2021 - April 2022 | 1 yr 1 mos',
                companyLogo: defaultProfileImage
            }
        ],
        careerInterests: [
            'Digital Marketing',
            'Social Media Marketing',
            'Search Engine Optimization',
            'Data Analytics',
            'Product Management',
            'Content Marketing'
        ],
        technicalSkills: [
            'Social Media Content and Optimization',
            'Social Media Marketing',
            'Search Marketing',
            'Search Engine Optimization (Content & Backend Optimization)',
            'Paid Marketing Content (Facebook & Instagram Ads)',
            'Content Editing',
            'Content Marketing',
            'Content Writing',
            'Proof-reading',
            'Event Coordination (Project Management)'
        ]
    };

    connectedCallback() {
        // Load profile data based on profileId
        // This would typically fetch from Apex or API
    }
}