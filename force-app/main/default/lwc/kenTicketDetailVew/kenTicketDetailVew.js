import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getCaseDetail from '@salesforce/apex/KenServiceSupportController.getCaseDetail';
import closeCase from '@salesforce/apex/KenServiceSupportController.closeCase';
import addCaseComment from '@salesforce/apex/KenServiceSupportController.addCaseComment';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';
import getGatePassesForCase from '@salesforce/apex/KenGatePassController.getGatePassesForCase';
import getApprovalHistory from '@salesforce/apex/KenServiceSupportController.getApprovalHistory';

const GATE_PASS_RECORD_TYPE_LABEL = 'Gate Pass Request';

// Status bar progression — stages in order for gate pass cases
const GATE_PASS_STATUS_STAGES = [
    { key: 'submitted',  label: 'Submitted',   statuses: ['New'] },
    { key: 'review',     label: 'Under Review', statuses: ['In Progress', 'Waiting for Student', 'Response Received', 'On Hold'] },
    { key: 'resolved',   label: 'Approved',     statuses: ['Resolved'] },
    { key: 'cancelled',  label: 'Cancelled',    statuses: ['Cancelled', 'Canceled', 'Rejected'] },
    { key: 'closed',     label: 'Closed',       statuses: ['Closed', 'Merged'] }
];

// Status bar for other service types
const SERVICE_STATUS_STAGES = [
    { key: 'submitted',  label: 'Submitted',   statuses: ['New'] },
    { key: 'inprogress', label: 'In Progress',  statuses: ['In Progress', 'Waiting for Student', 'Response Received', 'On Hold', 'Escalated', 'Hostel Approval', 'Mess Approval', 'Finance Approval', 'Refund'] },
    { key: 'resolved',   label: 'Resolved',     statuses: ['Resolved'] },
    { key: 'cancelled',  label: 'Cancelled',    statuses: ['Cancelled', 'Canceled', 'Rejected'] },
    { key: 'closed',     label: 'Closed',       statuses: ['Closed', 'Merged'] }
];

export default class KenTicketDetailVew extends LightningElement {
    @track ticket = {
        title: '',
        status: '',
        requestId: '',
        dateTime: '',
        requestType: ''
    };

    caseId;
    _caseDetailRequested = false;
    isLoading = false;
    isClosing = false;
    isPostingComment = false;
    loadError = '';
    isToastVisible = false;
    toastTitle = '';
    toastMessage = '';
    toastVariant = 'success';
    toastTimer;
    @track conversation = [];
    @track comments = [];
    @track commentDraft = '';
    @track gatePassRecord = null;
    @track showGatePassModal = false;
    @track showFeedbackModal = false;
    @track showFeedbackSuccessDialog = false;
    @track selectedRating = 0;
    @track feedbackText = '';
    @track hasSubmittedFeedback = false;
    @track approvalHistory = [];

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const state = pageRef?.state || {};
        const { caseId } = state;
        if (caseId && caseId !== this.caseId) {
            this.caseId = caseId;
            this._caseDetailRequested = true;
            this.loadCaseDetails();
        }
    }

    connectedCallback() {
        getColors().then(colors => {
            this.applyOrganizationTheme(colors);
        }).catch(() => {});
        this.ensureParamsFromUrl();
        if (this.caseId && !this._caseDetailRequested) {
            this._caseDetailRequested = true;
            this.loadCaseDetails();
        }
    }

    disconnectedCallback() {
        window.clearTimeout(this.toastTimer);
    }

    applyOrganizationTheme(colors) {
        if (!this.template?.host || !colors) return;
        const primary = colors.primary || colors.primaryColor;
        const secondary = colors.secondary || colors.secondaryColor;
        if (primary && typeof primary === 'string') {
            this.template.host.style.setProperty('--primary-color', primary);
        }
        if (secondary && typeof secondary === 'string') {
            this.template.host.style.setProperty('--secondary-color', secondary);
        }
    }

    async loadCaseDetails() {
        if (!this.caseId) {
            return;
        }
        this.isLoading = true;
        this.loadError = '';
        try {
            const detail = await getCaseDetail({ caseId: this.caseId });
            if (!detail) {
                this.ticket = this.buildEmptyTicket();
                this.conversation = [];
                this.comments = [];
                return;
            }
            this.ticket = this.buildTicket(detail);
            this.conversation = this.buildConversation(detail.responses, detail);
            this.comments = this.buildComments(detail.comments);
            this.hasSubmittedFeedback = !!detail.hasFeedbackSubmitted;
            if (detail.recordType === GATE_PASS_RECORD_TYPE_LABEL) {
                this.loadGatePass(this.caseId);
            }
            this.loadApprovalHistory(this.caseId);
        } catch (error) {
            console.error('Ticket detail fetch error', error);
            this.loadError = error?.body?.message || error?.message || 'Unable to load ticket details';
            this.conversation = [];
            this.comments = [];
        } finally {
            this.isLoading = false;
        }
    }

    get isGatePass() {
        return (this.ticket?.requestType || '') === GATE_PASS_RECORD_TYPE_LABEL;
    }

    // Show View Pass button only for gate pass cases that have an issued pass
    get showViewPassButton() {
        return this.isGatePass && this.gatePassRecord != null;
    }

    get studentInitials() {
        const name = this.gatePassRecord?.contactName || '';
        const parts = name.trim().split(/\s+/).filter(Boolean);
        if (parts.length === 0) return '?';
        if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
        return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }

    handleViewPass() {
        this.showGatePassModal = true;
    }

    handleCloseGatePassModal() {
        this.showGatePassModal = false;
    }

    stopModalClose(event) {
        event.stopPropagation();
    }

    get gatePassQrUrl() {
        if (!this.gatePassRecord?.name) return null;
        return 'https://api.qrserver.com/v1/create-qr-code/?data='
            + encodeURIComponent(this.gatePassRecord.name)
            + '&size=220x220&ecc=M';
    }

    get gatePassExitTimeFormatted() {
        return this._formatGatePassDateTime(this.gatePassRecord?.exitTime);
    }

    get gatePassEntryTimeFormatted() {
        return this._formatGatePassDateTime(this.gatePassRecord?.entryTime);
    }

    _formatGatePassDateTime(value) {
        if (!value) return '—';
        try {
            // Salesforce returns "2026-06-24 08:37:30" (space separator).
            // Replace space with T so all browsers (incl. Safari) parse it correctly.
            const normalized = typeof value === 'string' ? value.replace(' ', 'T') : value;
            const d = new Date(normalized);
            const day   = String(d.getDate()).padStart(2, '0');
            const month = d.toLocaleString('en-US', { month: 'short' });
            const year  = d.getFullYear();
            const hours = String(d.getHours()).padStart(2, '0');
            const mins  = String(d.getMinutes()).padStart(2, '0');
            return `${day} ${month} ${year}, ${hours}:${mins}`;
        } catch (e) {
            return String(value);
        }
    }

    get statusSteps() {
        const currentStatus = this.ticket?.status || '';
        const stages = this.isGatePass ? GATE_PASS_STATUS_STAGES : SERVICE_STATUS_STAGES;
        let activeIdx = -1;
        stages.forEach((stage, idx) => {
            if (stage.statuses.includes(currentStatus)) activeIdx = idx;
        });
        return stages.map((stage, idx) => ({
            key:       stage.key,
            label:     stage.label,
            isDone:    idx < activeIdx,
            isActive:  idx === activeIdx,
            isPending: idx > activeIdx,
            stepClass: idx < activeIdx
                ? 'status-step status-step--done'
                : idx === activeIdx
                    ? 'status-step status-step--active'
                    : 'status-step status-step--pending'
        }));
    }

    handleQrDownload() {
        if (this.gatePassQrUrl) {
            window.open(this.gatePassQrUrl + '&download=1', '_blank');
        }
    }

    loadGatePass(caseId) {
        if (!caseId) return;
        getGatePassesForCase({ caseId })
            .then(passes => {
                this.gatePassRecord = (passes && passes.length > 0) ? passes[0] : null;
            })
            .catch(() => { this.gatePassRecord = null; });
    }

    loadApprovalHistory(caseId) {
        if (!caseId) return;
        getApprovalHistory({ caseId })
            .then(steps => {
                this.approvalHistory = (steps || []).map(step => ({
                    id:             step.createdDate,
                    actorName:      step.actorName,
                    decisionLabel:  step.decisionLabel,
                    decisionClass:  step.decisionClass,
                    commentsDisplay: step.commentsDisplay,
                    showComment:    step.decisionLabel === 'Rejected',
                    dateFormatted:  this._formatGatePassDateTime(step.createdDate)
                }));
            })
            .catch(() => { this.approvalHistory = []; });
    }

    get hasApprovalHistory() {
        return (this.approvalHistory || []).length > 0;
    }

    get hasAnyRejection() {
        return (this.approvalHistory || []).some(e => e.showComment);
    }

    get ahTableClass() {
        return this.hasAnyRejection ? 'ah-table ah-table-3col' : 'ah-table ah-table-2col';
    }

    buildConversation(responses, detail) {
        const isSupport = (detail?.recordType || '').toLowerCase() === 'support';

        let sections = [];
        if (isSupport) {
            if (detail?.subject) {
                sections.push({
                    label: 'Subject',
                    text: detail.subject,
                    isFileUpload: false,
                    attachment: null
                });
            }
            if (detail?.description) {
                sections.push({
                    label: 'Description',
                    text: detail.description,
                    isFileUpload: false,
                    attachment: null
                });
            }
            if (detail?.serviceOfferingName) {
                sections.push({
                    label: 'Issue Type',
                    text: detail.serviceOfferingName,
                    isFileUpload: false,
                    attachment: null
                });
            }
            if (detail?.attachmentUrl) {
                sections.push({
                    label: 'Attachment',
                    text: '',
                    isFileUpload: true,
                    attachment: {
                        name: detail.attachmentName || 'Attachment',
                        url: detail.attachmentUrl
                    }
                });
            }
        } else {
            sections = (responses || []).map((resp, idx) => {
                const questionLabel =
                    resp?.Questionnaire_Parameter__r?.Question_Label__c || `Question ${idx + 1}`;
                const responseText = resp?.Response__c || 'No response captured';
                const questionType = (resp?.Questionnaire_Parameter__r?.Question_Type__c || '').toLowerCase();
                const responseLooksLikeFile = (responseText || '').toLowerCase().includes('attachment uploaded');
                const isFileUpload = questionType.includes('file') || responseLooksLikeFile;

                let attachment = null;
                if (isFileUpload) {
                    const nameFromDetail = detail?.attachmentName || null;
                    const urlFromDetail = detail?.attachmentUrl || null;
                    const nameFromText = responseText?.includes(':')
                        ? responseText.split(':').pop().trim()
                        : responseText;
                    const attachmentName = nameFromDetail || nameFromText || 'Attachment';
                    if (urlFromDetail) {
                        attachment = { name: attachmentName, url: urlFromDetail };
                    } else {
                        attachment = { name: attachmentName, url: null };
                    }
                }

                return {
                    label: questionLabel,
                    text: isFileUpload && !attachment?.url ? responseText || 'No attachment provided' : responseText,
                    isFileUpload,
                    attachment
                };
            });
        }

        if (!sections.length) {
            sections = [];
        }

        const timeline = [];
        if (sections.length) {
            timeline.push({
                id: 'outbound',
                author: 'You',
                date: this.ticket.dateTime || '',
                type: 'outbound',
                sections,
                hasAttachments: false,
                attachments: [],
                additionalInfo: []
            });
        }

        return timeline;
    }

    buildComments(comments = []) {
        return (comments || []).map((comment, idx) => {
            const isCurrentUser = !!comment?.isCurrentUser;
            const rawAuthor = comment?.author || '';
            const isAutoGenerated = /^User\d{10,}$/.test(rawAuthor);
            const displayAuthor = isCurrentUser ? 'You' : (isAutoGenerated || !rawAuthor ? 'Support Team' : rawAuthor);
            return {
                id: comment?.id || `comment-${idx}`,
                author: displayAuthor,
                body: comment?.body || '',
                date: this.formatDate(comment?.createdDate),
                isAdmin: !isCurrentUser,
                wrapperClass: `comment-item ${isCurrentUser ? 'comment-item-outbound' : 'comment-item-inbound'}`,
                bubbleClass: `comment-bubble ${isCurrentUser ? 'comment-bubble-outbound' : 'comment-bubble-inbound'}`
            };
        });
    }

    get timelineItems() {
        return (this.conversation || []).map(item => {
            return {
                ...item,
                isOutbound: item.type === 'outbound',
                isInbound: item.type === 'inbound',
                containerClass: `message-container ${item.type}`,
                firstAttachment: item.attachments && item.attachments.length ? item.attachments[0] : null
            };
        });
    }

    get hasConversation() {
        return this.timelineItems.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.loadError && !this.hasConversation;
    }

    get hasComments() {
        return (this.comments || []).length > 0;
    }

    get commentCountLabel() {
        return `${(this.comments || []).length} ${(this.comments || []).length === 1 ? 'comment' : 'comments'}`;
    }

    get isPostCommentDisabled() {
        return !this.caseId || this.isLoading || this.isPostingComment;
    }

    get commentButtonLabel() {
        return this.isPostingComment ? 'Posting...' : 'Post Comment';
    }

    get crumbs() {
        const currentLabel = this.ticket?.requestId || this.ticket?.title || 'Ticket Detail';
        return [
            { label: 'Home', url: '' },
            { label: 'Service & Support', url: '/service-support' },
            { label: this.historyCrumbLabel, url: '/service-support/all-tickets' },
            { label: currentLabel }
        ];
    }

    get historyCrumbLabel() {
        return (this.ticket?.requestType || '').toLowerCase() === 'support'
            ? 'Support Tickets'
            : 'Service Requests';
    }

    get isTicketClosed() {
        if (!this.ticket || !this.ticket.status) {
            return false;
        }
        return this.ticket.status.toLowerCase().includes('closed');
    }

    get hasTicketStatus() {
        return !!(this.ticket?.status || '').trim();
    }

    get statusBadgeClass() {
        const status = (this.ticket?.status || '').toLowerCase();
        if (status.includes('closed')) {
            return 'status-badge status-closed';
        }
        if (status.includes('cancel')) {
            return 'status-badge status-canceled';
        }
        if (status.includes('reject')) {
            return 'status-badge status-rejected';
        }
        if (status.includes('review') || status.includes('pending')) {
            return 'status-badge status-review';
        }
        if (status.includes('resolved')) {
            return 'status-badge status-resolved';
        }
        return 'status-badge';
    }

    get canCancelRequest() {
        const status = (this.ticket?.status || '').toLowerCase();
        if (!status) {
            return true;
        }
        return !(status.includes('closed') || status.includes('cancel') || status.includes('reject') || status.includes('resolved'));
    }

    buildEmptyTicket() {
        return {
            title: 'Case Detail',
            status: '',
            requestId: '',
            dateTime: '',
            requestType: ''
        };
    }

    buildTicket(detail) {
        return {
            title: detail?.subject || 'Case Detail',
            status: detail?.status || '',
            requestId: detail?.caseNumber ? `#${detail.caseNumber}` : '',
            dateTime: detail?.createdDate ? this.formatDate(detail.createdDate) : '',
            requestType: detail?.recordType || '',
            issueType: detail?.serviceOfferingName || ''
        };
    }

    ensureParamsFromUrl() {
        const search = window?.location?.search;
        if (!search || this.caseId) {
            return;
        }
        const params = new URLSearchParams(search);
        const caseId = params.get('caseId');
        if (caseId) {
            this.caseId = caseId;
        }
    }

    formatDate(dateValue) {
        if (!dateValue) {
            return '';
        }
        try {
            const dt = new Date(dateValue);
            if (Number.isNaN(dt.getTime())) {
                return '';
            }
            return dt.toLocaleString();
        } catch (e) {
            return '';
        }
    }

    async handleCancelRequest() {
        if (!this.caseId || this.isClosing) {
            return;
        }

        this.isClosing = true;
        this.loadError = '';
        try {
            await closeCase({ caseId: this.caseId });
            await this.loadCaseDetails();
            this.showToast('Request Cancelled', 'Your request has been cancelled successfully.');
            window.setTimeout(() => {
                this.navigateBack();
            }, 1500);
        } catch (error) {
            console.error('Cancel request error', error);
            this.loadError = error?.body?.message || error?.message || 'Unable to cancel the request';
        } finally {
            this.isClosing = false;
        }
    }

    navigateBack() {
        // Navigate back to the previous page (View All Tickets)
        window.history.back();
    }

    handleCommentInput(event) {
        this.commentDraft = event.target.value;
    }

    clearCommentComposer() {
        this.commentDraft = '';
        const commentTextarea = this.template.querySelector('.comment-textarea');
        if (commentTextarea) {
            commentTextarea.value = '';
        }
    }

    async handleSubmitComment() {
        const commentBody = (this.commentDraft || '').trim();
        if (!commentBody) {
            this.showToast('Comment Required', 'Enter a comment before posting it.', 'error');
            return;
        }

        this.isPostingComment = true;
        try {
            await addCaseComment({
                caseId: this.caseId,
                commentBody
            });
            this.clearCommentComposer();
            await this.loadCaseDetails();
            this.clearCommentComposer();
            this.showToast('Comment Posted', 'Your comment has been added to the case.');
        } catch (error) {
            console.error('Case comment error', error);
            const message = error?.body?.message || error?.message || 'Unable to post the comment.';
            this.showToast('Unable to Post Comment', message, 'error');
        } finally {
            this.isPostingComment = false;
        }
    }

    handleLeaveFeedback() {
        this.selectedRating = 0;
        this.feedbackText = '';
        this.showFeedbackModal = true;
    }

    handleStarClick(event) {
        const rating = parseInt(event.currentTarget.dataset.rating, 10);
        this.selectedRating = rating;
    }

    handleFeedbackTextChange(event) {
        this.feedbackText = event.target.value;
    }

    handleCancelFeedback() {
        this.showFeedbackModal = false;
        this.selectedRating = 0;
        this.feedbackText = '';
    }

    handleSubmitFeedback() {
        if (!this.caseId || this.selectedRating < 1) {
            return;
        }
        const rating = String(this.selectedRating);
        const feedback = this.feedbackText;
        submitCaseFeedback({ caseId: this.caseId, rating, feedback })
            .then(() => {
                this.hasSubmittedFeedback = true;
                this.showFeedbackModal = false;
                this.selectedRating = 0;
                this.feedbackText = '';
                this.showFeedbackSuccessDialog = true;
                setTimeout(() => {
                    this.showFeedbackSuccessDialog = false;
                }, 1500);
            })
            .catch((error) => {
                this.loadError = error?.body?.message || 'Failed to submit feedback.';
            });
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCancelFeedback();
        }
    }

    handleModalContainerClick(event) {
        event.stopPropagation();
    }

    closeFeedbackSuccessDialog() {
        this.showFeedbackSuccessDialog = false;
    }

    showToast(title, message = '', variant = 'success') {
        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = variant;
        this.isToastVisible = true;

        window.clearTimeout(this.toastTimer);
        this.toastTimer = window.setTimeout(() => {
            this.isToastVisible = false;
        }, 1800);
    }

    get starRatings() {
        return [1, 2, 3, 4, 5].map(rating => ({
            value: rating,
            isFilled: rating <= this.selectedRating
        }));
    }

    get ratingBadge() {
        if (this.selectedRating === 0) {
            return null;
        }
        const badges = {
            1: { text: 'Poor', class: 'rating-badge-poor' },
            2: { text: 'Fair', class: 'rating-badge-fair' },
            3: { text: 'Good', class: 'rating-badge-good' },
            4: { text: 'Very Good', class: 'rating-badge-very-good' },
            5: { text: 'Excellent', class: 'rating-badge-excellent' }
        };
        return badges[this.selectedRating] || null;
    }
}