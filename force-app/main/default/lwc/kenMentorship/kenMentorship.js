import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import AlumniAlt from '@salesforce/resourceUrl/AlumniAlt';
import MENTORSHIP_EMPTY_STATE from '@salesforce/resourceUrl/MentorshipEmptyState';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getMentorshipConnections from '@salesforce/apex/KenMentorshipController.getMentorshipConnections';
import getCurrentUserMentorPreference from '@salesforce/apex/KenMentorshipController.getCurrentUserMentorPreference';
import getCurrentUserCity from '@salesforce/apex/KenMentorshipController.getCurrentUserCity';
import getAcceptedMentorsForCurrentMentee from '@salesforce/apex/KenMentorshipController.getAcceptedMentorsForCurrentMentee';
import getAcceptedMenteesForCurrentMentor from '@salesforce/apex/KenMentorshipController.getAcceptedMenteesForCurrentMentor';
import getScheduledCallsForCurrentMentee from '@salesforce/apex/KenMentorshipController.getScheduledCallsForCurrentMentee';
import scheduleCallForCurrentMentee from '@salesforce/apex/KenMentorshipController.scheduleCallForCurrentMentee';
import respondToCallRequest from '@salesforce/apex/KenMentorshipController.respondToCallRequest';
import rescheduleCallRequest from '@salesforce/apex/KenMentorshipController.rescheduleCallRequest';
import getTasksForCurrentMentee from '@salesforce/apex/KenMentorshipController.getTasksForCurrentMentee';
import saveTaskForCurrentMentee from '@salesforce/apex/KenMentorshipController.saveTaskForCurrentMentee';
import deleteTaskForCurrentMentee from '@salesforce/apex/KenMentorshipController.deleteTaskForCurrentMentee';

function today() {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function addDays(d, days) {
    const out = new Date(d);
    out.setDate(out.getDate() + days);
    return new Date(out.getFullYear(), out.getMonth(), out.getDate());
}

function parseLocalIsoDate(dateIso) {
    if (!dateIso || typeof dateIso !== 'string') {
        return null;
    }
    const parts = dateIso.split('-').map((part) => Number(part));
    if (parts.length !== 3 || parts.some((part) => Number.isNaN(part))) {
        return null;
    }
    return new Date(parts[0], parts[1] - 1, parts[2]);
}

export default class KenMentorship extends NavigationMixin(LightningElement) {
    @track selectedDate = today();
    @track mentors = [];
    @track isLoadingMentors = false;
    @track mentorsError = '';
    @track mentorOptions = [];
    @track menteeOptions = [];
    @track scheduleEvents = [];
    @track isSchedulingCall = false;
    @track isRespondingCallRequest = false;
    @track isSavingTask = false;
    @track scheduleError = '';
    @track showToast = false;
    @track toastTitle = '';
    @track toastMessage = '';
    @track toastVariant = 'success';
    @track isBeAMentorOn = false;
    @track isMentorPrefLoaded = false;
    @track currentUserCity = '';

    @wire(getCurrentUserCity)
    wiredUserCity({ data }) {
        if (data !== undefined) {
            this.currentUserCity = data || '';
        }
    }

    toastTimeout;

    @track tasks = [];

    // If a notification deep-links here with ?recordId=<mentorshipId>, this captures it
    // so child components / scroll-into-view can focus on the specific request/session.
    @track focusedMentorshipId = null;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this.focusedMentorshipId = pageRef?.state?.recordId || null;
    }

    get hasConnections() {
        return this.mentors.length > 0;
    }

    get showEmptyLanding() {
        return !this.isLoadingMentors && !this.hasConnections && !this.isBeAMentorOn && this.isMentorPrefLoaded;
    }

    get showMainPage() {
        return !this.showEmptyLanding;
    }

    get emptyStateImageUrl() {
        return MENTORSHIP_EMPTY_STATE;
    }

    handleDateChange(event) {
        this.selectedDate = event.detail.date;
    }

    get taskMentorOptions() {
        const options = [];
        const seen = new Set();

        (this.mentorOptions || []).forEach((option) => {
            const value = option?.value ? String(option.value) : '';
            const label = option?.label || '';
            if (value && label && !seen.has(value)) {
                seen.add(value);
                options.push({ label, value });
            }
        });

        (this.tasks || []).forEach((task) => {
            // Only mentor-assigned task assignees may extend the mentor list —
            // without this filter every past assignee (mentees included) leaked
            // into the picker, unlike the role-specific call-schedule lists.
            if ((task?.assignTo || '').toLowerCase() !== 'mentor') {
                return;
            }
            const label = task?.assigneeName || '';
            const value = task?.assigneeId ? String(task.assigneeId) : '';
            if (value && label && !seen.has(value)) {
                seen.add(value);
                options.push({ label, value });
            }
        });

        return options;
    }

    get taskMenteeOptions() {
        const options = [];
        const seen = new Set();

        (this.menteeOptions || []).forEach((option) => {
            const value = option?.value ? String(option.value) : '';
            const label = option?.label || '';
            if (value && label && !seen.has(value)) {
                seen.add(value);
                options.push({ label, value });
            }
        });

        (this.tasks || []).forEach((task) => {
            if ((task?.assignTo || '').toLowerCase() !== 'mentee') {
                return;
            }
            const label = task?.assigneeName || '';
            const value = task?.assigneeId ? String(task.assigneeId) : '';
            if (value && label && !seen.has(value)) {
                seen.add(value);
                options.push({ label, value });
            }
        });

        return options;
    }

    handleAddTask(event) {
        this.saveTask(event.detail || {}, 'Task added successfully.');
    }

    handleEditTask(event) {
        const taskData = event.detail || {};
        if (!taskData.id) {
            return;
        }
        this.saveTask(taskData, 'Task updated successfully.');
    }

    handleTaskAction(event) {
        const { action, taskId } = event.detail || {};
        if (action === 'delete' && taskId !== undefined && taskId !== null && !this.isSavingTask) {
            this.isSavingTask = true;
            deleteTaskForCurrentMentee({ taskId: String(taskId) })
                .then(() => {
                    this.tasks = (this.tasks || []).filter((task) => String(task.id) !== String(taskId));
                    this.showToastNotification('Success', 'Task deleted successfully.', 'success');
                })
                .catch((error) => {
                    const message = this.extractErrorMessage(error, 'Unable to delete task right now.');
                    this.showToastNotification('Error', message, 'error');
                })
                .finally(() => {
                    this.isSavingTask = false;
                });
        }
    }

    handleCalendarToast(event) {
        const detail = event?.detail;
        if (!detail?.message) {
            return;
        }
        this.showToastNotification(
            detail.title || 'Error',
            detail.message,
            detail.variant || 'error'
        );
    }

    // Open the call's feedback form in the survey module, returning to this page
    // afterward (the page reload refreshes the "Leave Feedback" prompt state).
    handleTakeFeedback(event) {
        const recordId = event?.detail?.recordId;
        if (!recordId) {
            return;
        }
        // Survey form returns here via browser history after submit (no returnUrl param).
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'survey_form__c' },
            state: { recId: recordId }
        });
    }

    handleMentorClick(event) {
        const profileId = event?.detail?.id;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'network__c' },
            state: { profileId }
        });
    }

    normalizeMentor(raw) {
        const isMentor = raw?.currentUserIsMentor === true;
        return {
            id: raw?.personAccountId || raw?.id,
            isMentor,
            personIsMentor: !isMentor,
            type: isMentor ? 'Mentee' : 'Mentor',
            typeClass: isMentor ? 'mentee-badge' : 'mentor-badge',
            name: raw?.name || '',
            title: raw?.title || '',
            location: raw?.location || '',
            profileImage: raw?.profileImage || AlumniAlt,
            isOnline: raw?.isOnline === true,
            company: raw?.company || '',
            industry: raw?.industry || '',
            jobFunction: raw?.jobFunction || '',
            programLastAttended: raw?.programLastAttended || '',
            specialisation: raw?.specialisation || '',
            graduationYear: raw?.graduationYear || '',
            education: raw?.educationLine || this.buildEducationLine(raw?.programLastAttended, raw?.graduationYear),
            currentCity: raw?.currentCity || '',
            willingToHelp: raw?.willingToHelp === true,
            mentorshipStatus: raw?.mentorshipStatus || '',
            callRequestStatus: raw?.callRequestStatus || '',
            recordType: raw?.recordType || '',
            networkStatus: raw?.networkStatus || ''
        };
    }

    // Same shape as kenAlumniDetailView.educationLine: "program | year", else program.
    buildEducationLine(program, year) {
        const p = (program || '').toString().trim();
        const y = (year || '').toString().trim();
        if (p && y) return `${p} | ${y}`;
        return p;
    }

    loadMentors() {
        this.isLoadingMentors = true;
        this.mentorsError = '';

        getMentorshipConnections()
            .then((result) => {
                const rows = Array.isArray(result) ? result : [];
                this.mentors = rows
                    .filter((row) => row.mentorshipStatus === 'Accepted')
                    .map((row) => this.normalizeMentor(row));
            })
            .catch((error) => {
                this.mentors = [];
                this.mentorsError = error?.body?.message || 'Unable to load mentorship connections.';
            })
            .finally(() => {
                this.isLoadingMentors = false;
            });
    }

    loadAcceptedMentors() {
        getAcceptedMentorsForCurrentMentee()
            .then((result) => {
                const options = Array.isArray(result) ? result : [];
                this.mentorOptions = options
                    .filter((option) => option?.value && option?.label)
                    .map((option) => ({
                        value: option.value,
                        label: option.label
                    }));
            })
            .catch(() => {
                this.mentorOptions = [];
            });
    }

    loadAcceptedMentees() {
        getAcceptedMenteesForCurrentMentor()
            .then((result) => {
                const options = Array.isArray(result) ? result : [];
                this.menteeOptions = options
                    .filter((option) => option?.value && option?.label)
                    .map((option) => ({
                        value: option.value,
                        label: option.label
                    }));
            })
            .catch(() => {
                this.menteeOptions = [];
            });
    }

    normalizeScheduleEvent(raw) {
        return {
            id: raw?.id,
            date: parseLocalIsoDate(raw?.dateIso),
            dateIso: raw?.dateIso || '',
            time: raw?.timeLabel || '',
            startTime: raw?.startTime || '',
            endTime: raw?.endTime || '',
            title: raw?.title || 'Mentorship Call',
            mentor: raw?.mentor || '',
            counterpartTitle: raw?.counterpartTitle || '',
            mentorImage: raw?.mentorImage || AlumniAlt,
            meetingDescription: raw?.meetingDescription || '',
            meetingDescriptionHtml: raw?.meetingDescriptionHtml || '',
            meetingType: raw?.meetingType || '',
            meetingLink: raw?.meetingLink || '',
            meetingLocation: raw?.meetingLocation || '',
            callRequestStatus: raw?.callRequestStatus || '',
            requesterName: raw?.requesterName || '',
            status: raw?.status || 'request',
            topic: raw?.topic || null,
            canRespond: raw?.canRespond === true,
            hasFeedbackForm: raw?.hasFeedbackForm === true,
            feedbackSubmitted: raw?.feedbackSubmitted === true
        };
    }

    normalizeTask(raw) {
        return {
            id: raw?.id,
            title: raw?.title || '',
            status: raw?.status || 'Pending',
            description: raw?.description || '',
            descriptionHtml: raw?.descriptionHtml || '',
            priority: raw?.priority || 'Low',
            endDate: raw?.endDate || '',
            assignTo: raw?.assignTo || '',
            mentorId: raw?.mentorId || '',
            assigneeId: raw?.assigneeId || '',
            assigneeName: raw?.assigneeName || '',
            assigneeAvatar: raw?.assigneeAvatar || AlumniAlt,
            // Only the creator may edit/delete; backend enforces this too.
            canEdit: raw?.canEdit === true
        };
    }

    loadTasks() {
        getTasksForCurrentMentee()
            .then((result) => {
                const rows = Array.isArray(result) ? result : [];
                this.tasks = rows.map((row) => this.normalizeTask(row));
            })
            .catch((error) => {
                this.tasks = [];
                const message = this.extractErrorMessage(error, 'Unable to load tasks.');
                this.showToastNotification('Error', message, 'error');
            });
    }

    saveTask(taskData, successMessage) {
        if (this.isSavingTask) {
            return;
        }

        this.isSavingTask = true;
        saveTaskForCurrentMentee({ request: taskData })
            .then((result) => {
                const savedTask = this.normalizeTask(result || {});
                const existingIndex = (this.tasks || []).findIndex(
                    (task) => String(task.id) === String(savedTask.id)
                );
                if (existingIndex >= 0) {
                    const updated = [...this.tasks];
                    updated[existingIndex] = savedTask;
                    this.tasks = updated;
                } else {
                    this.tasks = [savedTask, ...(this.tasks || [])];
                }
                this.showToastNotification('Success', successMessage, 'success');
            })
            .catch((error) => {
                const message = this.extractErrorMessage(error, 'Unable to save task right now.');
                this.showToastNotification('Error', message, 'error');
            })
            .finally(() => {
                this.isSavingTask = false;
            });
    }

    loadScheduledCalls() {
        getScheduledCallsForCurrentMentee()
            .then((result) => {
                const rows = Array.isArray(result) ? result : [];
                this.scheduleEvents = rows.map((row) => this.normalizeScheduleEvent(row));
            })
            .catch((error) => {
                this.scheduleEvents = [];
                this.scheduleError = this.extractErrorMessage(error, 'Unable to load scheduled calls.');
            });
    }

    handleScheduleCallRequest(event) {
        if (this.isSchedulingCall) {
            return;
        }

        const requestPayload = event?.detail || null;
        if (!requestPayload) {
            this.showToastNotification('Error', 'Schedule request payload is missing.', 'error');
            return;
        }

        this.isSchedulingCall = true;
        this.scheduleError = '';

        scheduleCallForCurrentMentee({ request: requestPayload })
            .then(() => {
                const requestDate = parseLocalIsoDate(requestPayload.meetingDate);
                this.selectedDate = requestDate || this.selectedDate || addDays(today(), 0);
                this.showToastNotification('Success', 'Call request sent successfully.', 'success');
                this.loadScheduledCalls();
            })
            .catch((error) => {
                this.scheduleError = this.extractErrorMessage(error, 'Unable to schedule this call right now.');
                this.showToastNotification('Error', this.scheduleError, 'error');
            })
            .finally(() => {
                this.isSchedulingCall = false;
            });
    }

    handleRespondCallRequest(event) {
        if (this.isRespondingCallRequest) {
            return;
        }

        const callRequestId = event?.detail?.callRequestId;
        const action = event?.detail?.action;
        if (!callRequestId || !action) {
            this.showToastNotification('Error', 'Call request response is missing.', 'error');
            return;
        }

        this.isRespondingCallRequest = true;
        respondToCallRequest({ callRequestId: String(callRequestId), action })
            .then(() => {
                const verb = String(action).toLowerCase() === 'accept' ? 'accepted' : 'declined';
                this.showToastNotification('Success', `Call request ${verb} successfully.`, 'success');
                this.loadScheduledCalls();
            })
            .catch((error) => {
                const message = this.extractErrorMessage(error, 'Unable to update call request right now.');
                this.showToastNotification('Error', message, 'error');
            })
            .finally(() => {
                this.isRespondingCallRequest = false;
            });
    }

    handleRescheduleCallRequest(event) {
        if (this.isRespondingCallRequest) {
            return;
        }

        const callRequestId = event?.detail?.callRequestId;
        const meetingDate = event?.detail?.meetingDate;
        const startTime = event?.detail?.startTime;
        const endTime = event?.detail?.endTime;
        if (!callRequestId || !meetingDate || !startTime || !endTime) {
            this.showToastNotification('Error', 'Reschedule payload is missing.', 'error');
            return;
        }

        this.isRespondingCallRequest = true;
        rescheduleCallRequest({ callRequestId: String(callRequestId), meetingDate, startTime, endTime })
            .then(() => {
                this.showToastNotification('Success', 'Call request updated and accepted successfully.', 'success');
                this.loadScheduledCalls();
            })
            .catch((error) => {
                const message = this.extractErrorMessage(error, 'Unable to update call request right now.');
                this.showToastNotification('Error', message, 'error');
            })
            .finally(() => {
                this.isRespondingCallRequest = false;
            });
    }

    extractErrorMessage(error, fallbackMessage) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length > 0 && error.body[0]?.message) {
            return error.body[0].message;
        }
        return fallbackMessage;
    }

    showToastNotification(title, message, variant) {
        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = variant;
        this.showToast = true;
        window.clearTimeout(this.toastTimeout);
        this.toastTimeout = window.setTimeout(() => {
            this.showToast = false;
        }, 2000);
    }

    handleFindMentors() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'network__c' }
        });
    }

    handleBecomeAMentor() {
        try {
            sessionStorage.setItem('ken_setting_active_tab', 'Mentorship');
        } catch (e) { /* ignore */ }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'settings__c' }
        });
    }

    connectedCallback() {
        this.loadMentorPreference();
        this.loadMentors();
        this.loadAcceptedMentors();
        this.loadAcceptedMentees();
        this.loadScheduledCalls();
        this.loadTasks();
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
    }

    loadMentorPreference() {
        getCurrentUserMentorPreference()
            .then((result) => {
                this.isBeAMentorOn = result === true;
                this.isMentorPrefLoaded = true;
            })
            .catch(() => {
                this.isBeAMentorOn = false;
                this.isMentorPrefLoaded = true;
            });
    }

    disconnectedCallback() {
        window.clearTimeout(this.toastTimeout);
    }
}