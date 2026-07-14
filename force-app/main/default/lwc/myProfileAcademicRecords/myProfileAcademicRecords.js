import { LightningElement, track } from 'lwc';

export default class MyProfileAcademicRecords extends LightningElement {
    @track showAddModal = false;
    @track isSuccessToastVisible = false;

    // Mock initial data based on screenshot
    @track academicRecords = [
        {
            id: 1,
            institute: 'B Tech, Electronics and Media Technology',
            schoolName: 'Ken42', // Assuming this is the institute/school name based on screenshot layout (Bold title, subtitle)
            // Wait, screenshot shows: "B Tech..." (Title), "Ken42" (Subtitle). 
            // My previous analysis: "Name of institute" -> "Ken42"? "Type of study" -> "B Tech"? 
            // Let's structure it: title (Type/Field), subtitle (Institute).
            typeAndField: 'B Tech, Electronics and Media Technology',
            instituteName: 'Ken42',
            grade: 'CGPA: 8.4',
            period: '2010 - 2012',
            iconUrl: 'https://i.pravatar.cc/150?img=1' // Placeholder or use a specific icon if available
        },
        {
            id: 2,
            instituteName: 'GRG Matric Hr Sec School',
            typeAndField: 'Higher Secondary School',
            grade: '80%',
            period: '2016-2017',
            iconUrl: 'https://i.pravatar.cc/150?img=2'
        },
        {
            id: 3,
            instituteName: 'GRG Matric Hr Sec School',
            typeAndField: 'Higher Secondary School',
            grade: '80%',
            period: '2016-2017',
            iconUrl: 'https://i.pravatar.cc/150?img=3'
        }
    ];

    // Form inputs
    @track tempRecord = {
        institute: '',
        typeOfStudy: 'SSLC',
        fieldOfStudy: '',
        startDate: '',
        endDate: '',
        gradingFormat: 'CGPA', // 'CGPA' or 'Percentage'
        score: ''
    };

    get typeOptions() {
        return [
            { label: 'SSLC', value: 'SSLC' },
            { label: 'HSC', value: 'HSC' },
            { label: 'Diploma', value: 'Diploma' },
            { label: 'Bachelor\'s', value: 'Bachelor\'s' },
            { label: 'Master\'s', value: 'Master\'s' },
            { label: 'PhD', value: 'PhD' }
        ];
    }

    get isCgpa() {
        return this.tempRecord.gradingFormat === 'CGPA';
    }

    handleAddRecord() {
        this.resetForm();
        this.showAddModal = true;
    }

    closeAddModal() {
        this.showAddModal = false;
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        this.tempRecord[field] = event.target.value;
    }

    handleTypeChange(event) {
        this.tempRecord.typeOfStudy = event.target.value; // For combobox
    }
    
    // For native select if used
    handleTypeSelect(event) {
         this.tempRecord.typeOfStudy = event.target.value;
    }

    handleGradingFormatChange(event) {
        this.tempRecord.gradingFormat = event.target.value; 
        // value comes from radio input value attribute
    }

    saveRecord() {
        // Basic validation
        if (!this.tempRecord.institute || !this.tempRecord.typeOfStudy) {
            // Show error or just return
            return;
        }

        // Create new record object
        const newRecord = {
            id: Date.now(),
            instituteName: this.tempRecord.institute,
            typeAndField: `${this.tempRecord.typeOfStudy}${this.tempRecord.fieldOfStudy ? ', ' + this.tempRecord.fieldOfStudy : ''}`,
            grade: this.tempRecord.gradingFormat === 'CGPA' ? `CGPA: ${this.tempRecord.score}` : `${this.tempRecord.score}%`,
            period: `${this.getYear(this.tempRecord.startDate)} - ${this.getYear(this.tempRecord.endDate)}`,
            iconUrl: 'https://i.pravatar.cc/150?u=new' // Placeholder
        };

        this.academicRecords = [...this.academicRecords, newRecord];
        this.closeAddModal();
        this.showPopup();
    }

    getYear(dateString) {
        if (!dateString) return '';
        return new Date(dateString).getFullYear();
    }

    resetForm() {
        this.tempRecord = {
            institute: '',
            typeOfStudy: 'SSLC',
            fieldOfStudy: '',
            startDate: '',
            endDate: '',
            gradingFormat: 'CGPA',
            score: ''
        };
    }

    // Success Popup
    showPopup() {
        this.isSuccessToastVisible = true;
        // Auto hide after 3 seconds
        setTimeout(() => {
            this.isSuccessToastVisible = false;
        }, 1500);
    }
    
    // Optional: if user clicks close on popup manually (though screenshot doesn't show close btn, usually auto or click out)
}