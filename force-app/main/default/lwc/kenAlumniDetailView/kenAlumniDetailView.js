import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';
import getAlumniProfile from '@salesforce/apex/KenNetworkController.getAlumniProfile';
import requestConnectionApex from '@salesforce/apex/KenNetworkController.requestConnection';
import removeConnectionApex from '@salesforce/apex/KenNetworkController.removeConnection';
import requestMentorshipApex from '@salesforce/apex/KenNetworkController.requestMentorship';
import removeMentorshipApex from '@salesforce/apex/KenNetworkController.removeMentorship';

const EMPTY_PROFILE = {
    name: '', title: '', company: '', location: '', profileImage: null,
    isOnline: false, batch: null, about: null, email: null, phone: null,
    linkedin: null, willingToHelp: false, isMentor: false, isMyMentor: false,
    programLastAttended: null, specialisation: null, graduationYear: null,
    education: [], experience: [], achievements: []
};

export default class KenAlumniDetailView extends LightningElement {
    @api profileId;

    @track profileData = { ...EMPTY_PROFILE };
    @track connectionStatus = null;
    @track mentorshipStatus = null;
    @track connectionId = null;
    @track isLoading = true;

    // Button loading states
    @track isConnectLoading = false;
    @track isMentorshipLoading = false;

    // Confirmation modal
    @track showConfirmModal = false;
    @track confirmAction = null; // 'removeConnection' | 'removeMentorship'
    @track confirmTitle = '';
    @track confirmMessage = '';

    // Success overlay
    @track showSuccessOverlay = false;
    @track successMessage = '';

    // Chat state
    @track showChatbox = false;
    @track isChatExpanded = false;
    @track messageInput = '';
    @track chatMessages = [
        {
            id: 1,
            type: 'received',
            text: "Hope life is treating you well! 🌟 We've got an exciting alumni networking event on the horizon. It's not just a chance to reminisce but a golden opportunity to expand your professional circle. Imagine connecting with fellow grads, sharing experiences, and maybe discovering new collaborations. Let's catch up, swap stories, and make the most of this networking bonanza.",
            time: '05:10 Pm',
            date: '2026-02-19'
        },
        {
            id: 2,
            type: 'sent',
            text: "Sounds awesome! 🎉 Can't wait to catch up and network with fellow alumni. Count me in for the event. Thanks for the heads up, and looking forward to some great conversations.",
            time: '05:10 Pm',
            date: '2026-02-19'
        }
    ];

    // ─── Wire ────────────────────────────────────────────────────────────────

    @wire(getAlumniProfile, { accountId: '$profileId' })
    wiredProfile({ data, error }) {
        if (!data && !error) return;
        this.isLoading = false;
        if (data) {
            this.profileData = {
                name:         data.name         || '',
                title:        data.title        || '',
                company:      data.company      || '',
                location:     data.location     || '',
                profileImage: data.profileImage || null,
                isOnline:     data.isOnline      || false,
                batch:        data.batch        || null,
                about:        data.about        || null,
                programLastAttended: data.programLastAttended || null,
                specialisation:      data.specialisation      || null,
                graduationYear:      data.graduationYear      || null,
                email:        data.email        || null,
                phone:        data.phone        || null,
                linkedin:     data.linkedin     || null,
                willingToHelp: data.willingToHelp === true,
                isMentor: data.isMentor === true,
                isMyMentor: data.isMyMentor === true,
                education:    (data.education    || []).map(e => ({ ...e })),
                experience:   (data.experience   || []).map(e => ({ ...e })),
                achievements: (data.achievements || []).map(a => ({ ...a }))
            };
            this.connectionStatus  = data.connectionStatus  || null;
            this.connectionId      = data.connectionId      || null;
            this.mentorshipStatus  = data.mentorshipStatus  || null;
        } else if (error) {
            this.profileData = { ...EMPTY_PROFILE };
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading profile',
                message: error.body?.message || 'An unexpected error occurred.',
                variant: 'error'
            }));
        }
    }

    // ─── Computed ────────────────────────────────────────────────────────────

    get hasEducation() {
        return this.profileData?.education?.length > 0;
    }

    get hasExperience() {
        return this.profileData?.experience?.length > 0;
    }

    get hasAchievements() {
        return this.profileData?.achievements?.length > 0;
    }

    get educationLine() {
        const list = this.profileData?.education;
        if (list && list.length > 0) {
            const parts = list.slice(0, 2).map(e => {
                const degree = (e.degree || '').trim();
                const match  = (e.duration || '').match(/\d{4}/g);
                const year   = match ? match[match.length - 1] : '';
                return year ? `${degree} ${year}` : degree;
            }).filter(Boolean);
            if (parts.length > 0) return parts.join(' | ');
        }
        const program = (this.profileData?.programLastAttended || '').trim();
        const year    = (this.profileData?.graduationYear      || '').trim();
        if (program && year) return `${program} | ${year}`;
        if (program) return program;
        return this.profileData?.batch || '';
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
            const msgDate   = new Date(dateString);
            const today     = new Date();
            const yesterday = new Date(today);
            yesterday.setDate(yesterday.getDate() - 1);
            if (msgDate.toDateString() === today.toDateString())     return 'Today';
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

    // ─── Connection handlers ──────────────────────────────────────────────────

    handleRequestConnection() {
        if (!this.profileId || this.isConnectLoading) return;
        if (this.connectionStatus === 'Accepted' || this.connectionStatus === 'Requested') return;

        this.isConnectLoading = true;
        requestConnectionApex({ targetAccountId: this.profileId })
            .then(status => {
                this.connectionStatus = status;
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Failed to send connection request.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isConnectLoading = false;
            });
    }

    handleRemoveConnection() {
        this.confirmAction  = 'removeConnection';
        this.confirmTitle   = 'Remove Connection';
        this.confirmMessage = 'Are you sure you want to remove this connection?';
        this.showConfirmModal = true;
    }

    // ─── Mentorship handlers ──────────────────────────────────────────────────

    handleRequestMentorship() {
        if (!this.connectionId || this.isMentorshipLoading) return;

        this.isMentorshipLoading = true;
        requestMentorshipApex({ connectionId: this.connectionId })
            .then(() => {
                this.mentorshipStatus = 'Requested';
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Failed to request mentorship.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isMentorshipLoading = false;
            });
    }

    handleRemoveMentorship() {
        this.confirmAction  = 'removeMentorship';
        this.confirmTitle   = 'Remove Mentorship';
        this.confirmMessage = 'Are you sure you want to remove this mentorship?';
        this.showConfirmModal = true;
    }

    // ─── Confirmation modal ───────────────────────────────────────────────────

    handleConfirmCancel() {
        this.showConfirmModal = false;
        this.confirmAction = null;
    }

    handleConfirmYes() {
        this.showConfirmModal = false;
        if (this.confirmAction === 'removeConnection') {
            this._doRemoveConnection();
        } else if (this.confirmAction === 'removeMentorship') {
            this._doRemoveMentorship();
        }
        this.confirmAction = null;
    }

    _doRemoveConnection() {
        if (!this.connectionId) return;
        removeConnectionApex({ connectionId: this.connectionId })
            .then(() => {
                this.connectionStatus = 'Cancelled';
                this.mentorshipStatus = null;
                this.connectionId = null;
                this._showSuccess('Connection Removed');
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Failed to remove connection.',
                    variant: 'error'
                }));
            });
    }

    _doRemoveMentorship() {
        if (!this.connectionId) return;
        removeMentorshipApex({ connectionId: this.connectionId })
            .then(() => {
                this.mentorshipStatus = null;
                this._showSuccess('Mentorship Removed');
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Failed to remove mentorship.',
                    variant: 'error'
                }));
            });
    }

    // ─── Success overlay ──────────────────────────────────────────────────────

    _showSuccess(message) {
        this.successMessage = message;
        this.showSuccessOverlay = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showSuccessOverlay = false;
        }, 2500);
    }

    // ─── Chat handlers ────────────────────────────────────────────────────────

    handleMessage() {
        this.showChatbox = true;
    }

    handleToggleExpand() {
        this.isChatExpanded = !this.isChatExpanded;
    }

    handleCloseChat() {
        this.showChatbox  = false;
        this.isChatExpanded = false;
    }

    handleImageError(event) {
        event.target.src = defaultProfileImage;
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
        this.chatMessages = [
            ...this.chatMessages,
            {
                id:   this.chatMessages.length + 1,
                type: 'sent',
                text: this.messageInput,
                time: timeString,
                date: now.toISOString().split('T')[0]
            }
        ];
        this.messageInput = '';

        setTimeout(() => {
            const chatBody = this.template.querySelector('.chatbox-body');
            if (chatBody) chatBody.scrollTop = chatBody.scrollHeight;
        }, 0);
    }
}