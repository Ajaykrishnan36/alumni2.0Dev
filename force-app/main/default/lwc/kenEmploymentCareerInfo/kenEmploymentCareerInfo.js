import { LightningElement, track, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenEmploymentCareerInfo extends LightningElement {
    @api careerInfoList = [];
    @track showCareerModal = false;
    @track selectedCareerData = null;
    @track showDeleteConfirm = false;
    careerIdToDelete = null;
    @api nextId = 1;

    get hasCareerInfo() {
        return this.careerInfoList.length > 0;
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

    handleAddCareer() {
        this.selectedCareerData = null;
        this.showCareerModal = true;
    }

    handleEditCareer(event) {
        event.stopPropagation();
        event.preventDefault();

        // Get the ID from the data attribute - try multiple ways
        const button = event.currentTarget || event.target.closest('button');
        const careerId = button?.dataset?.careerId || button?.dataset?.careerid || button?.getAttribute('data-career-id');

        if (!careerId) {
            console.error('Career ID not found', event);
            return;
        }

        // Convert to number for comparison if needed
        const idToFind = isNaN(careerId) ? careerId : Number(careerId);
        const career = this.careerInfoList.find(c => {
            // Compare both as string and number to handle type mismatches
            return String(c.id) === String(careerId) || c.id === idToFind;
        });

        if (career) {
            // Create a copy with the id to identify it as an edit
            this.selectedCareerData = { ...career, id: career.id };
            this.showCareerModal = true;
        } else {
            console.error('Career not found with ID:', careerId, 'Available IDs:', this.careerInfoList.map(c => c.id));
        }
    }

    handleDeleteCareer(event) {
        event.stopPropagation();
        event.preventDefault();

        // Get the ID from the data attribute - try multiple ways
        const button = event.currentTarget || event.target.closest('button');
        const careerId = button?.dataset?.careerId || button?.dataset?.careerid || button?.getAttribute('data-career-id');

        if (!careerId) {
            console.error('Career ID not found', event);
            return;
        }

        // Confirm before removing — mirrors the education step's delete popup.
        this.careerIdToDelete = careerId;
        this.showDeleteConfirm = true;
    }

    handleConfirmDeleteCareer() {
        const careerId = this.careerIdToDelete;
        this.showDeleteConfirm = false;
        this.careerIdToDelete = null;
        if (careerId === null || careerId === undefined || careerId === '') return;

        // Convert to number for comparison if needed
        const idToRemove = isNaN(careerId) ? careerId : Number(careerId);
        // Filter out the item and create a new array to trigger reactivity
        const filteredList = this.careerInfoList.filter(c => {
            // Compare both as string and number to handle type mismatches
            return String(c.id) !== String(careerId) && c.id !== idToRemove;
        });

        // Update the array to trigger reactivity
        this.careerInfoList = [...filteredList];
    }

    handleCancelDeleteCareer() {
        this.showDeleteConfirm = false;
        this.careerIdToDelete = null;
    }

    handleCloseCareerModal() {
        this.showCareerModal = false;
        this.selectedCareerData = null;
    }

    handleSaveCareer(event) {
        const careerData = event.detail;

        if (this.selectedCareerData && this.selectedCareerData.id) {
            // Edit existing
            const index = this.careerInfoList.findIndex(c => c.id === this.selectedCareerData.id);
            if (index !== -1) {
                this.careerInfoList[index] = { ...careerData, id: this.selectedCareerData.id };
                this.careerInfoList = [...this.careerInfoList];
            }
        } else {
            // Add new
            this.careerInfoList = [...this.careerInfoList, { ...careerData, id: this.nextId++ }];
        }

        this.showCareerModal = false;
        this.selectedCareerData = null;
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous', { bubbles: true, composed: true }));
    }

    handleSkip() {
        this.dispatchEvent(new CustomEvent('skip', { bubbles: true, composed: true }));
    }

    handleSaveAndNext() {
        if (!this.careerInfoList || this.careerInfoList.length === 0) {
            this.dispatchNotify('error', 'Required field missing', 'Please add at least one career entry to continue.');
            return;
        }
        this.dispatchEvent(new CustomEvent('saveandnext', {
            detail: { careers: this.careerInfoList },
            bubbles: true,
            composed: true
        }));
    }

    dispatchNotify(type, title, message) {
        this.dispatchEvent(new CustomEvent('notify', {
            detail: { type, title, message },
            bubbles: true,
            composed: true
        }));
    }

    @api
    setEmploymentData(data) {
        if (!data || !Array.isArray(data)) {
            return;
        }
        this.careerInfoList = data.map((item, idx) => ({
            ...item,
            id: item.id != null ? item.id : idx + 1
        }));
        const maxId = this.careerInfoList.reduce((max, c) => Math.max(max, c.id), 0);
        this.nextId = maxId + 1;
    }

    @api
    getEmploymentData() {
        return this.careerInfoList;
    }

    get isSaveNextDisabled() {
        return !this.careerInfoList || this.careerInfoList.length === 0;
    }

}