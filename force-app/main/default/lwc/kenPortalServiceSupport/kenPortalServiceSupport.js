import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFAQs from '@salesforce/apex/KenServiceSupportController.getFAQs';
import getUserHistory from '@salesforce/apex/KenServiceSupportController.getUserHistory';
import getCurrentUserFullName from '@salesforce/apex/KenServiceSupportController.getCurrentUserFullName';
import createNeedHelpCase from '@salesforce/apex/KenServiceSupportController.createNeedHelpCase';
import getServiceOfferings from '@salesforce/apex/KenServiceSupportController.getServiceOfferings';
import isNeedHelpVisible from '@salesforce/apex/KenServiceSupportController.isNeedHelpVisible';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';

export default class KenPortalServiceSupport extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track userName = '';
    @track searchQuery = '';
    @track showNeedHelpModal = false;
    @track showNeedHelp = true; // controlled by Show_Need_Help__c custom setting
    @track isSuccessToastVisible = false;
    @track successTitle = 'Request submitted';
    @track successDescription = 'Your request has been submitted successfully.';
    @track faqData = [];
    @track serviceHistoryData = [];
    @track supportHistoryData = [];
    @track gatePassHistoryData = [];
    @track serviceOfferingsData = [];
    @track activeHistoryTab = 'service';

    connectedCallback() {
        this.applySearchFromUrl();
        this.checkNeedHelpFromUrl();
        this.checkUrlSuccessFlag();
        this.loadData();

        isNeedHelpVisible()
            .then(visible => { this.showNeedHelp = visible !== false; })
            .catch(() => { this.showNeedHelp = true; });

        Promise.all([
            getColors()
                .then(colors => { this.applyOrganizationTheme(colors); })
                .catch(() => {}),
            getCurrentUserFullName()
                .then(name => { this.userName = name || ''; })
                .catch(() => {})
        ]).finally(() => {
            this.isLoading = false;
        });
    }

    get rightColumnClass() {
        // When Need Help is hidden, use single-card layout so Request card fills the space
        return this.showNeedHelp ? 'right-column' : 'right-column right-column--single';
    }

    disconnectedCallback() {
        window.clearTimeout(this._successTimer);
    }

    checkUrlSuccessFlag() {
        try {
            const url = new URL(window.location.href);
            const successFlag = url.searchParams.get('success');
            if (successFlag === 'request') {
                this.successDescription = 'Your service request has been created successfully.';
                this.showSuccessModalWithTimeout();
            }
            if (successFlag) {
                url.searchParams.delete('success');
                window.history.replaceState({}, document.title, url.pathname + url.hash);
            }
        } catch (e) {
            console.error('Error checking URL parameters', e);}
    }

    loadData() {
        // Load FAQs
        getFAQs()
            .then(result => {
                this.faqData = result || [];
                this.applySearchFilter();
            })
            .catch(error => {
                console.error('FAQ Error:', error);
                this.faqData = [];
            });
        
        const value = localStorage.getItem('ConstituentRoleId');

        // Load Service + Support History
        getUserHistory({constituentRoleId: value})
            .then(result => {
                this.serviceHistoryData  = result.serviceHistory  || [];
                this.supportHistoryData  = result.supportHistory  || [];
                this.gatePassHistoryData = result.gatePassHistory || [];
            })
            .catch(error => {
                console.error('History Error:', error);
                this.serviceHistoryData  = [];
                this.supportHistoryData  = [];
                this.gatePassHistoryData = [];
            });

        // Load Service Offerings filtered by the constituent's target audience
        getServiceOfferings({ constituentRoleId: value })
            .then(services => {
                const seen = new Set();
                this.serviceOfferingsData = (services || [])
                    .map(service => ({
                        id: service.Id,
                        serviceId: service.Service__c || service.Id,
                        title: service.Service__r ? service.Service__r.Name : service.Name,
                        description: service.Service__r ? service.Service__r.Description__c : '',
                        name: service.Name
                    }))
                    .filter(service => {
                        if (seen.has(service.serviceId)) return false;
                        seen.add(service.serviceId);
                        return true;
                    });
            })
            .catch(error => {
                console.error('Service Offerings Error:', error);
                this.serviceOfferingsData = [];
            });
    }

    applySearchFromUrl() {
        try {
            const url = new URL(window.location.href);
            const query = url.searchParams.get('q') || url.searchParams.get('search') || '';
            const trimmed = String(query || '').trim();
            if (trimmed) {
                this.searchQuery = trimmed;
            }
        } catch (e) {
            // Ignore malformed URLs in non-browser contexts.
        }
    }

    checkNeedHelpFromUrl() {
        let shouldOpen = false;
        try {
            const url = new URL(window.location.href);
            if (url.searchParams.get('action') === 'needHelp') {
                shouldOpen = true;
                url.searchParams.delete('action');
                const query = url.searchParams.toString();
                const suffix = query ? `?${query}` : '';
                window.history.replaceState({}, document.title, `${url.pathname}${suffix}${url.hash}`);
            }
        } catch (e) {
            // Ignore malformed URLs in non-browser contexts.
        }

        if (!shouldOpen) {
            try {
                shouldOpen = window.sessionStorage.getItem('kenOpenNeedHelpModal') === '1';
            } catch (e) {
                shouldOpen = false;
            }
        }

        if (shouldOpen) {
            this.showNeedHelpModal = true;
            try {
                window.sessionStorage.removeItem('kenOpenNeedHelpModal');
            } catch (e) {
                // sessionStorage may be unavailable
            }
        }
    }

    applySearchFilter() {
        if (!this.searchQuery) {
            return;
        }
        const faqComponent = this.template.querySelector('c-ken-faq-section');
        if (faqComponent) {
            faqComponent.filterFAQs(this.searchQuery);
        }
    }

    handleSearchChange(event) {
        this.searchQuery = typeof event.detail === 'string' ? event.detail : event.detail?.value || '';
        this.applySearchFilter();
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

    handleNeedHelpClick() {
        this.showNeedHelpModal = true;
    }

    handleCloseModal() {
        this.showNeedHelpModal = false;
    }

    handleHistoryTabChange(event) {
        this.activeHistoryTab = event.detail;
    }

    handleServiceRequestClick() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'request_service__c'
            }
        });
    }

    async handleModalSubmit(event) {
        const { description, issueType, subject, file, serviceOfferingId } = event.detail || {};
        try {
            let fileData;
            let fileName;
            if (file) {
                ({ fileData, fileName } = await this.readFileAsBase64(file));
            }

            const value = localStorage.getItem('ConstituentRoleId');

            const fullDescription = issueType
                ? `Issue Type: ${issueType}\n\n${description || ''}`.trim()
                : description;

            await createNeedHelpCase({
                serviceOfferingId: serviceOfferingId || null,
                subject,
                description: fullDescription,
                fileName,
                fileData,
                constituentRoleId: value
            });
            this.showNeedHelpModal = false;
            this.showSuccessModalWithTimeout();
            this.loadData();
        } catch (error) {
            console.error('Need help submission failed', error);
            const modal = this.template.querySelector('c-need-help-modal');
            const message = error?.body?.message || error?.message || 'An unexpected error occurred.';
            if (modal) {
                modal.showError('Submission failed', message);
            }
        }
    }

    showSuccessModalWithTimeout() {
        window.clearTimeout(this._successTimer);
        this.isSuccessToastVisible = true;
        this._successTimer = window.setTimeout(() => {
            this.isSuccessToastVisible = false;
        }, 1500);
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                resolve({ fileData: base64, fileName: file.name });
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    handleFileDownload(event) {
        const fileUrl = event.detail.fileUrl || event.detail.fileName;
        if (fileUrl) {
            window.open(fileUrl, '_blank');
        }
    }

    handleTicketSelect(event) {
        const { caseId } = event.detail || {};
        if (!caseId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `/service-support/ticket-detail?caseId=${caseId}`
            }
        });
    }

    handleHistoryViewAll() {
        console.debug('[portalServiceSupport] navigating to view-all tickets');
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: '/service-support/all-tickets'
            }
        });
    }

    handleLeaveFeedback(event) {
        const { caseId } = event.detail || {};
        if (!caseId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `/service-support/ticket-detail?caseId=${caseId}`
            }
        });
    }

    get hasSearchQuery() {
        return this.searchQuery && this.searchQuery.trim().length > 0;
    }

    get searchResults() {
        if (!this.hasSearchQuery) {
            return [];
        }

        const query = this.normalizeSearchText(this.searchQuery);
        const queryTerms = query.split(' ').filter(Boolean);
        const results = [];

        // Search FAQs
        if (this.faqData && this.faqData.length > 0) {
            this.faqData.forEach(category => {
                if (category.questions && category.questions.length > 0) {
                    category.questions.forEach(question => {
                        const score = this.getSearchScore(query, queryTerms, [
                            question.question,
                            question.answer,
                            category.category
                        ]);

                        if (score > 0) {
                            results.push({
                                id: `faq-${question.id}`,
                                type: 'FAQ',
                                title: question.question,
                                description: this.stripHtml(question.answer),
                                buttonText: 'FAQ',
                                buttonClass: 'result-btn faq-btn',
                                score
                            });
                        }
                    });
                }
            });
        }

        // Search Services
        if (this.serviceOfferingsData && this.serviceOfferingsData.length > 0) {
            this.serviceOfferingsData.forEach(service => {
                const score = this.getSearchScore(query, queryTerms, [
                    service.title,
                    service.description,
                    service.name
                ]);

                if (score > 0) {
                    results.push({
                        id: `service-${service.id}`,
                        type: 'Service',
                        title: service.title || service.name,
                        description: this.stripHtml(service.description) || 'View details and submit this service request.',
                        buttonText: 'Service',
                        buttonClass: 'result-btn service-btn',
                        serviceId: service.serviceId || service.id,
                        score
                    });
                }
            });
        }

        // Search Support Tickets
        if (this.supportHistoryData && this.supportHistoryData.length > 0) {
            this.supportHistoryData.forEach(ticket => {
                const caseId = this.getHistoryCaseId(ticket);
                const score = this.getSearchScore(query, queryTerms, [
                    ticket.id,
                    caseId,
                    ticket.title,
                    ticket.subject,
                    ticket.description,
                    ticket.status
                ]);

                if (score > 0) {
                    results.push({
                        id: `support-${caseId || ticket.id}`,
                        type: 'Support Ticket',
                        title: ticket.id || `#${caseId}`,
                        description: ticket.title || ticket.subject || 'Title of the support ticket',
                        buttonText: 'Support Ticket',
                        buttonClass: 'result-btn support-ticket-btn',
                        caseId,
                        score
                    });
                }
            });
        }

        // Search Service Requests
        if (this.serviceHistoryData && this.serviceHistoryData.length > 0) {
            this.serviceHistoryData.forEach(request => {
                const caseId = this.getHistoryCaseId(request);
                const score = this.getSearchScore(query, queryTerms, [
                    request.id,
                    caseId,
                    request.title,
                    request.subject,
                    request.description,
                    request.status
                ]);

                if (score > 0) {
                    results.push({
                        id: `service-request-${caseId || request.id}`,
                        type: 'Service Request',
                        title: request.id || `#${caseId}`,
                        description: request.title || request.subject || 'Title of the service request',
                        buttonText: 'Service Request',
                        buttonClass: 'result-btn service-request-btn',
                        caseId,
                        score
                    });
                }
            });
        }

        return results
            .filter((result, index, list) => list.findIndex(item => item.id === result.id) === index)
            .sort((a, b) => b.score - a.score || String(a.title || '').localeCompare(String(b.title || '')));
    }

    normalizeSearchText(value) {
        return String(value || '')
            .replace(/<[^>]*>/g, ' ')
            .toLowerCase()
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .replace(/[^a-z0-9#]+/g, ' ')
            .trim();
    }

    getSearchScore(query, queryTerms, fields) {
        const haystack = this.normalizeSearchText(fields.filter(Boolean).join(' '));
        if (!haystack || !queryTerms.length) return 0;
        if (haystack.includes(query)) return query.length + 20;
        if (queryTerms.every(term => haystack.includes(term))) {
            return queryTerms.reduce((score, term) => score + (haystack.includes(term) ? term.length : 0), 0);
        }
        return 0;
    }

    stripHtml(value) {
        return String(value || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
    }

    getHistoryCaseId(item) {
        return item?.caseId || item?.CaseId || item?.caseID || item?.Id || item?.recordId || '';
    }

    get searchResultsCount() {
        return this.searchResults.length;
    }

}