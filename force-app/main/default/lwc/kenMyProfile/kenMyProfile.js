import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

import getMyProfile from '@salesforce/apex/KenMyProfileController.getMyProfile';
import getPersonalDetails from '@salesforce/apex/KenSettingsController.getPersonalDetails';
import saveAboutText from '@salesforce/apex/KenMyProfileController.saveAbout';
import saveEducationRecord from '@salesforce/apex/KenMyProfileController.saveEducation';
import archiveEducationRecord from '@salesforce/apex/KenMyProfileController.archiveEducation';
import saveExperienceRecord from '@salesforce/apex/KenMyProfileController.saveExperience';
import archiveExperienceRecord from '@salesforce/apex/KenMyProfileController.archiveExperience';
import saveAchievementRecord from '@salesforce/apex/KenMyProfileController.saveAchievement';
import archiveAchievementRecord from '@salesforce/apex/KenMyProfileController.archiveAchievement';

const KEN_HEADER_CHAT_OPEN_KEY = 'ken_header_open_chat';

const EMPTY_PROFILE = {
    name: '',
    title: '',
    company: '',
    location: '',
    profileImage: '',
    isOnline: false,
    batch: '',
    expertise: '',
    email: '',
    phone: '',
    linkedin: '',
    willingToHelp: true,
    about: '',
    registrationNumber: null,
    education: [],
    experience: [],
    achievements: []
};

export default class KenMyProfile extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track isWorking = false;
    @track loadingText = 'Loading profile...';
    @track showSuccessPopup = false;
    @track successMessage = '';

    @track showChatbox = false;
    @track isChatExpanded = false;
    @track messageInput = '';
    @track chatMessages = [
        {
            id: 1,
            type: 'received',
            text: 'Hope life is treating you well! We have got an exciting alumni networking event on the horizon.',
            time: '05:10 PM',
            date: '2026-02-19'
        },
        {
            id: 2,
            type: 'sent',
            text: 'Sounds awesome! Can\'t wait to catch up and network with fellow alumni.',
            time: '05:10 PM',
            date: '2026-02-19'
        }
    ];

    @track showAboutModal = false;
    @track showExperienceModal = false;
    @track showEducationModal = false;
    @track showAchievementModal = false;
    @track aboutEditText = '';
    @track isAboutBoldActive = false;
    @track isAboutItalicActive = false;
    @track isAboutUnorderedListActive = false;
    @track isAboutOrderedListActive = false;
    @track activeTab = 'about';
    @track paymentSearchTerm = '';
    @track experienceModalCareerData = null;
    @track experienceModalTitle = 'Add Experience';
    @track educationModalData = null;
    @track achievementModalData = null;
    @track profileData = { ...EMPTY_PROFILE };

    currentEditExperienceId = null;
    currentEditEducationId = null;
    currentEditAchievementId = null;
    successPopupTimeout = null;
    aboutRichTextEditor = null;
    aboutLastValidHtml = '';

    connectedCallback() {
        this.loadProfile({ showLoader: true, loadingText: 'Loading profile...' });

        try {
            if (sessionStorage.getItem(KEN_HEADER_CHAT_OPEN_KEY)) {
                sessionStorage.removeItem(KEN_HEADER_CHAT_OPEN_KEY);
                this.showChatbox = true;
            }
        } catch (e) {
            // ignore
        }
    }

    disconnectedCallback() {
        if (this.successPopupTimeout) {
            window.clearTimeout(this.successPopupTimeout);
            this.successPopupTimeout = null;
        }
    }

    renderedCallback() {
        if (!this.showAboutModal) {
            this.aboutRichTextEditor = null;
            return;
        }

        const editor = this.template.querySelector('.about-rich-text-area');
        if (!editor) {
            return;
        }

        if (editor !== this.aboutRichTextEditor) {
            this.aboutRichTextEditor = editor;
            editor.innerHTML = this.aboutEditText || '';
            this.aboutLastValidHtml = editor.innerHTML;
            this.ensureAboutListFormatting();
            this.updateAboutToolbarStates();
        } else if (editor.innerHTML !== (this.aboutEditText || '')) {
            editor.innerHTML = this.aboutEditText || '';
            this.ensureAboutListFormatting();
        }
    }

    get showLoader() {
        return this.isLoading || this.isWorking;
    }

    showSuccess(message) {
        this.successMessage = message || 'Saved successfully';
        this.showSuccessPopup = true;
        if (this.successPopupTimeout) {
            window.clearTimeout(this.successPopupTimeout);
        }
        this.successPopupTimeout = window.setTimeout(() => {
            this.showSuccessPopup = false;
            this.successPopupTimeout = null;
        }, 2000);
    }

    async runWithLoader(loadingText, operation) {
        this.isWorking = true;
        this.loadingText = loadingText || 'Processing...';
        try {
            return await operation();
        } finally {
            this.isWorking = false;
        }
    }

    async loadProfile(options = {}) {
        const { showLoader = false, loadingText = 'Loading profile...' } = options;
        if (showLoader) {
            this.isLoading = true;
            this.loadingText = loadingText;
        }
        try {
            const [data, settings] = await Promise.all([getMyProfile(), getPersonalDetails()]);
            this.profileData = {
                ...EMPTY_PROFILE,
                ...(data || {}),
                profileImage: settings?.profileImageUrl || data?.profileImage || defaultProfileImage,
                education: data?.education || [],
                experience: data?.experience || [],
                achievements: data?.achievements || []
            };
        } catch (e) {
            // Keep existing data on error
            // eslint-disable-next-line no-console
            console.error('Failed to load my profile', e);
        } finally {
            if (showLoader) {
                this.isLoading = false;
            }
        }
    }

    get aboutTabClass() { return this.activeTab === 'about' ? 'ken-tab active' : 'ken-tab'; }
    get achievementsTabClass() { return this.activeTab === 'achievements' ? 'ken-tab active' : 'ken-tab'; }
    get paymentsTabClass() { return this.activeTab === 'payments' ? 'ken-tab active' : 'ken-tab'; }

    get isAbout() { return this.activeTab === 'about'; }
    get isAchievements() { return this.activeTab === 'achievements'; }
    get isPayments() { return this.activeTab === 'payments'; }

    selectAbout() { this.activeTab = 'about'; }
    selectAchievements() { this.activeTab = 'achievements'; }
    selectPayments() { this.activeTab = 'payments'; }

    get payments() {
        return [
            { id: '1', particulars: 'Event Payment', transactionId: 'alfly000002EVirAAG', paymentMode: 'Online', currency: 'Rupee', paidAmount: 'Rs 50,000', transactionDate: '17 Aug 2026' },
            { id: '2', particulars: 'Event Payment', transactionId: 'alfly000002EVirAAG', paymentMode: 'Online', currency: 'Rupee', paidAmount: 'Rs 50,000', transactionDate: '17 Aug 2026' },
            { id: '3', particulars: 'Event Payment', transactionId: 'alfly000002EVirAAG', paymentMode: 'Online', currency: 'Rupee', paidAmount: 'Rs 50,000', transactionDate: '17 Aug 2026' }
        ];
    }

    get filteredPayments() {
        const term = (this.paymentSearchTerm || '').toLowerCase().trim();
        const list = this.payments || [];
        if (!term) return list;
        return list.filter(p => {
            const particulars = (p.particulars || '').toLowerCase();
            const transactionId = (p.transactionId || '').toLowerCase();
            const paymentMode = (p.paymentMode || '').toLowerCase();
            const currency = (p.currency || '').toLowerCase();
            return particulars.includes(term) || transactionId.includes(term) || paymentMode.includes(term) || currency.includes(term);
        });
    }

    get chatContainerClass() {
        return this.isChatExpanded ? 'chatbox-container expanded' : 'chatbox-container';
    }

    get chatExpandIcon() {
        return this.isChatExpanded ? 'utility:contract_alt' : 'utility:expand_alt';
    }

    get displayMessages() {
        const items = [];
        let lastDateString = null;

        const getRelativeDateLabel = (dateString) => {
            if (!dateString) return '';
            const msgDate = new Date(dateString);
            const today = new Date();
            const yesterday = new Date(today);
            yesterday.setDate(yesterday.getDate() - 1);
            if (msgDate.toDateString() === today.toDateString()) return 'Today';
            if (msgDate.toDateString() === yesterday.toDateString()) return 'Yesterday';
            return msgDate.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
        };

        this.chatMessages.forEach((msg, index) => {
            const currentDateString = msg.date || new Date().toISOString().split('T')[0];
            const dateLabel = getRelativeDateLabel(currentDateString);
            if (dateLabel !== lastDateString) {
                items.push({ id: 'date-' + index, isDateSeparator: true, dateLabel });
                lastDateString = dateLabel;
            }
            items.push({ ...msg, isSent: msg.type === 'sent', isReceived: msg.type === 'received' });
        });
        return items;
    }

    get educationLine() {
        const list = this.profileData?.education;
        if (!list || !list.length) return this.profileData?.batch || '';
        const parts = list.slice(0, 2).map(e => {
            const degree = (e.degree || '').trim();
            const year = (e.endYear || '').trim();
            return year ? `${degree} ${year}` : degree;
        });
        return parts.filter(Boolean).join(' | ') || this.profileData?.batch || '';
    }

    get hasEducationRecords() {
        return Array.isArray(this.profileData?.education) && this.profileData.education.length > 0;
    }

    get hasExperienceRecords() {
        return Array.isArray(this.profileData?.experience) && this.profileData.experience.length > 0;
    }

    get hasAchievementRecords() {
        return Array.isArray(this.profileData?.achievements) && this.profileData.achievements.length > 0;
    }

    handleMessage() {
        this.showChatbox = true;
    }

    handleToggleExpand() {
        this.isChatExpanded = !this.isChatExpanded;
    }

    handleCloseChat() {
        this.showChatbox = false;
        this.isChatExpanded = false;
    }

    handleImageError(event) {
        if (event && event.target) event.target.src = defaultProfileImage;
    }

    handleInputChange(event) {
        this.messageInput = event.target.value;
    }

    handleInputKeyup(event) {
        if (event.key === 'Enter') this.handleSendMessage();
    }

    handleSendMessage() {
        if (!this.messageInput || !this.messageInput.trim()) return;
        const now = new Date();
        const timeString = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const newMessage = {
            id: this.chatMessages.length + 1,
            type: 'sent',
            text: this.messageInput,
            time: timeString,
            date: now.toISOString().split('T')[0]
        };
        this.chatMessages = [...this.chatMessages, newMessage];
        this.messageInput = '';
        setTimeout(() => {
            const chatBody = this.template.querySelector('.chatbox-body');
            if (chatBody) chatBody.scrollTop = chatBody.scrollHeight;
        }, 0);
    }

    openAboutEdit() {
        this.aboutEditText = this.profileData.about || '';
        this.aboutLastValidHtml = this.aboutEditText || '';
        this.showAboutModal = true;
    }

    closeAboutModal() {
        this.showAboutModal = false;
    }

    handleAboutDiscard() {
        this.closeAboutModal();
    }

    handleAboutChange(event) {
        this.aboutEditText = event.detail.value || '';
    }

    async handleAboutSave() {
        await this.runWithLoader('Saving about...', async () => {
            try {
                await saveAboutText({ aboutText: this.aboutEditText || '' });
                this.profileData = { ...this.profileData, about: this.aboutEditText || '' };
                this.closeAboutModal();
                this.showSuccess('About updated successfully');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Failed to save about', e);
            }
        });
    }

    handleAboutEditInput(event) {
        this.aboutEditText = event.target.value;
    }

    get aboutEditLength() {
        return this.getPlainTextLength(this.aboutEditText);
    }

    get aboutBoldButtonClass() {
        return `toolbar-button ${this.isAboutBoldActive ? 'active' : ''}`;
    }

    get aboutItalicButtonClass() {
        return `toolbar-button ${this.isAboutItalicActive ? 'active' : ''}`;
    }

    get aboutUnorderedListButtonClass() {
        return `toolbar-button ${this.isAboutUnorderedListActive ? 'active' : ''}`;
    }

    get aboutOrderedListButtonClass() {
        return `toolbar-button ${this.isAboutOrderedListActive ? 'active' : ''}`;
    }

    getPlainTextLength(htmlValue) {
        const helper = document.createElement('div');
        helper.innerHTML = htmlValue || '';
        const text = (helper.textContent || '').replace(/\s+/g, ' ').trim();
        return text.length;
    }

    handleAboutRichTextInput(event) {
        const html = event.target.innerHTML || '';
        if (this.getPlainTextLength(html) <= 1200) {
            this.aboutEditText = html;
            this.aboutLastValidHtml = html;
        } else {
            event.target.innerHTML = this.aboutLastValidHtml || '';
            this.placeCaretAtEnd(event.target);
        }
        this.ensureAboutListFormatting();
        this.updateAboutToolbarStates();
    }

    handleAboutRichTextFocus() {
        this.updateAboutToolbarStates();
    }

    handleAboutRichTextSelection() {
        this.updateAboutToolbarStates();
    }

    handleAboutRichTextBlur() {
        if (!this.aboutRichTextEditor) return;
        this.aboutEditText = this.aboutRichTextEditor.innerHTML || '';
        this.aboutLastValidHtml = this.aboutEditText;
        this.updateAboutToolbarStates();
    }

    executeAboutCommand(command) {
        if (!this.aboutRichTextEditor) return;
        this.aboutRichTextEditor.focus();

        if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
            const selection = window.getSelection();
            if (selection && (selection.rangeCount === 0 || selection.isCollapsed)) {
                const range = document.createRange();
                const textNode = this.aboutRichTextEditor.childNodes[0] || this.aboutRichTextEditor;
                range.setStart(textNode, 0);
                range.setEnd(textNode, textNode.textContent ? textNode.textContent.length : 0);
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }

        document.execCommand(command, false, null);
        this.aboutEditText = this.aboutRichTextEditor.innerHTML || '';
        this.aboutLastValidHtml = this.aboutEditText;
        this.ensureAboutListFormatting();
        this.updateAboutToolbarStates();
    }

    handleAboutBold(event) {
        event.preventDefault();
        this.executeAboutCommand('bold');
    }

    handleAboutItalic(event) {
        event.preventDefault();
        this.executeAboutCommand('italic');
    }

    handleAboutUnorderedList(event) {
        event.preventDefault();
        this.executeAboutCommand('insertUnorderedList');
    }

    handleAboutOrderedList(event) {
        event.preventDefault();
        this.executeAboutCommand('insertOrderedList');
    }

    updateAboutToolbarStates() {
        try {
            this.isAboutBoldActive = document.queryCommandState('bold');
            this.isAboutItalicActive = document.queryCommandState('italic');

            let isInUnorderedList = false;
            let isInOrderedList = false;
            const selection = window.getSelection();
            if (selection && selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                let container = range.commonAncestorContainer;
                while (container && container !== this.aboutRichTextEditor) {
                    if (container.nodeType === 1) {
                        const tagName = container.tagName.toUpperCase();
                        if (tagName === 'UL') {
                            isInUnorderedList = true;
                            break;
                        }
                        if (tagName === 'OL') {
                            isInOrderedList = true;
                            break;
                        }
                        if (tagName === 'LI') {
                            const parent = container.parentElement;
                            if (parent) {
                                const parentTag = parent.tagName.toUpperCase();
                                if (parentTag === 'UL') isInUnorderedList = true;
                                if (parentTag === 'OL') isInOrderedList = true;
                            }
                            break;
                        }
                    }
                    container = container.parentElement || container.parentNode;
                }
            }
            this.isAboutUnorderedListActive = isInUnorderedList;
            this.isAboutOrderedListActive = isInOrderedList;
        } catch (e) {
            // ignore
        }
    }

    ensureAboutListFormatting() {
        if (!this.aboutRichTextEditor) return;
        const lists = this.aboutRichTextEditor.querySelectorAll('ul, ol');
        lists.forEach(list => {
            if (!list.style.marginLeft) {
                list.style.marginLeft = '1.5rem';
                list.style.marginTop = '0.5rem';
                list.style.marginBottom = '0.5rem';
            }
        });
        const listItems = this.aboutRichTextEditor.querySelectorAll('li');
        listItems.forEach(li => {
            if (!li.style.marginBottom) {
                li.style.marginBottom = '0.25rem';
            }
        });
    }

    placeCaretAtEnd(element) {
        if (!element) return;
        const range = document.createRange();
        range.selectNodeContents(element);
        range.collapse(false);
        const selection = window.getSelection();
        if (!selection) return;
        selection.removeAllRanges();
        selection.addRange(range);
    }

    handlePaymentSearchInput(event) {
        this.paymentSearchTerm = event.target.value;
    }

    navigateToSettings() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'settings__c' }
        });
    }

    openAddExperience() {
        this.currentEditExperienceId = null;
        this.experienceModalCareerData = null;
        this.experienceModalTitle = 'Add Experience';
        this.showExperienceModal = true;
    }

    handleEditExperience(event) {
        const id = event.detail.id;
        const exp = (this.profileData.experience || []).find(e => e.id === id);
        if (!exp) return;

        const startDate = exp.startYear && exp.startMonth ? `${exp.startYear}-${exp.startMonth}-01` : null;
        const endDate = exp.endYear && exp.endMonth ? `${exp.endYear}-${exp.endMonth}-01` : null;

        this.currentEditExperienceId = id;
        this.experienceModalCareerData = {
            id,
            jobTitle: exp.position || '',
            organization: exp.company || '',
            employmentType: exp.employmentType || '',
            location: exp.location || '',
            roleDescription: exp.description || '',
            isCurrentJob: exp.isCurrentJob || false,
            startDate,
            endDate,
            jobRole: exp.jobRole || ''
        };
        this.experienceModalTitle = 'Edit Experience';
        this.showExperienceModal = true;
    }

    async handleDeleteExperience(event) {
        const id = event.detail.id;
        await this.runWithLoader('Deleting experience...', async () => {
            try {
                await archiveExperienceRecord({ recordId: id });
                await this.loadProfile();
                this.showSuccess('Experience deleted successfully');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Failed to archive experience', e);
            }
        });
    }

    handleCloseExperienceModal() {
        this.showExperienceModal = false;
        this.currentEditExperienceId = null;
    }

    async handleSaveExperience(event) {
        const d = event.detail || {};
        const start = this.extractMonthYear(d.startDate);
        const end = this.extractMonthYear(d.endDate);

        await this.runWithLoader('Saving experience...', async () => {
            try {
                await saveExperienceRecord({
                    input: {
                        id: this.currentEditExperienceId || null,
                        jobTitle: d.jobTitle || '',
                        organization: d.organization || '',
                        employmentType: d.employmentType || '',
                        location: d.location || '',
                        startMonth: d.startMonth || start.month,
                        startYear: d.startYear || start.year,
                        endMonth: d.endMonth || end.month,
                        endYear: d.endYear || end.year,
                        isCurrentJob: d.isCurrentJob || false,
                        roleDescription: d.roleDescription || '',
                        workType: 'Onsite',
                        jobRole: d.jobRole || d.employmentStatus || ''
                    }
                });
                this.showExperienceModal = false;
                this.currentEditExperienceId = null;
                await this.loadProfile();
                this.showSuccess('Experience saved successfully');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Failed to save experience', e);
            }
        });
    }
    get educationModalTitle() {
        return this.currentEditEducationId ? 'Edit Education' : 'Add Education';
    }

    openAddEducation() {
        this.currentEditEducationId = null;
        this.educationModalData = null;
        this.showEducationModal = true;
    }

    handleEditEducation(event) {
        const id = event.detail.id;
        const edu = (this.profileData.education || []).find(e => e.id === id);
        if (!edu) return;

        this.currentEditEducationId = id;
        this.educationModalData = {
            id,
            degree: edu.degree || '',
            institution: edu.institution || '',
            institutionType: edu.institutionType || '',
            programPlan: edu.programPlan || '',
            registrationNumber: edu.registrationNumber || '',
            startMonth: edu.startMonth || '',
            startYear: edu.startYear || '',
            endMonth: edu.endMonth || '',
            endYear: edu.endYear || '',
            gradingFormat: edu.gradingFormat || 'CGPA',
            cgpa: edu.cgpa || (edu.score || '').replace('%', '')
        };
        this.showEducationModal = true;
    }

    async handleDeleteEducation(event) {
        const id = event.detail.id;
        await this.runWithLoader('Deleting education...', async () => {
            try {
                await archiveEducationRecord({ recordId: id });
                await this.loadProfile();
                this.showSuccess('Education deleted successfully');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Failed to archive education', e);
            }
        });
    }

    handleCloseEducationModal() {
        this.showEducationModal = false;
        this.currentEditEducationId = null;
        this.educationModalData = null;
    }

    async handleSaveEducation(event) {
        const d = event.detail || {};

        await this.runWithLoader('Saving education...', async () => {
            try {
                await saveEducationRecord({
                    input: {
                        id: this.currentEditEducationId || null,
                        degree: d.degree || '',
                        institution: d.institution || '',
                        institutionType: d.institutionType || 'institute',
                        programPlan: d.programPlan || null,
                        registrationNumber: d.registrationNumber || null,
                        startMonth: d.startMonth || null,
                        startYear: d.startYear || null,
                        endMonth: d.endMonth || null,
                        endYear: d.endYear || null,
                        gradingFormat: d.gradingFormat || 'CGPA',
                        cgpa: d.cgpa || ''
                    }
                });
                this.handleCloseEducationModal();
                await this.loadProfile();
                this.showSuccess('Education saved successfully');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Failed to save education', e);
            }
        });
    }

    get achievementModalTitle() {
        return this.currentEditAchievementId ? 'Edit Achievement' : 'Add Achievement';
    }

    openAddAchievement() {
        this.currentEditAchievementId = null;
        this.achievementModalData = null;
        this.showAchievementModal = true;
    }

    handleEditAchievement(event) {
        const id = event.detail.id;
        const ach = (this.profileData.achievements || []).find(a => a.id === id);
        if (!ach) return;

        this.currentEditAchievementId = id;
        this.achievementModalData = {
            id,
            type: ach.type || 'Honors & Awards',
            title: ach.title || '',
            organization: ach.organization || '',
            dateMonth: ach.dateMonth || '',
            dateYear: ach.dateYear || '',
            description: ach.description || '',
            patentNumber: ach.patentNumber || '',
            status: ach.status || '',
            role: ach.role || '',
            referenceUrl: ach.referenceUrl || '',
            paperType: ach.paperType || ''
        };
        this.showAchievementModal = true;
    }

    async handleDeleteAchievement(event) {
        const id = event.detail.id;
        await this.runWithLoader('Deleting achievement...', async () => {
            try {
                await archiveAchievementRecord({ recordId: id });
                await this.loadProfile();
                this.showSuccess('Achievement deleted successfully');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Failed to archive achievement', e);
            }
        });
    }

    handleCloseAchievementModal() {
        this.showAchievementModal = false;
        this.currentEditAchievementId = null;
        this.achievementModalData = null;
    }

    async handleSaveAchievement(event) {
        const d = event.detail || {};

        await this.runWithLoader('Saving achievement...', async () => {
            try {
                await saveAchievementRecord({
                    input: {
                        id: this.currentEditAchievementId || null,
                        type: d.type || 'Honors & Awards',
                        title: d.title || '',
                        organization: d.organization || '',
                        dateMonth: d.dateMonth || null,
                        dateYear: d.dateYear || null,
                        description: d.description || '',
                        patentNumber: d.patentNumber || '',
                        status: d.status || null,
                        role: d.role || null,
                        referenceUrl: d.referenceUrl || '',
                        paperType: d.paperType || null
                    }
                });
                this.handleCloseAchievementModal();
                await this.loadProfile();
                this.showSuccess('Achievement saved successfully');
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Failed to save achievement', e);
            }
        });
    }

    extractMonthYear(dateString) {
        if (!dateString) return { month: null, year: null };
        const parts = String(dateString).split('-');
        if (parts.length < 2) return { month: null, year: null };
        return { year: parts[0], month: parts[1] };
    }
}