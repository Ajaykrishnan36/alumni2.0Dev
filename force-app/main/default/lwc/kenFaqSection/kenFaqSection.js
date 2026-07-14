import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFaqData from '@salesforce/apex/KenServiceSupportController.getFAQs';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';
export default class KenFaqSection extends NavigationMixin(LightningElement) {
    @track faqData = [];
    @api searchQuery = '';
    @track expandedCategories = new Set();
    @track expandedQuestions = new Set();
    @track questionVotes = {};
    @track activeFeedback = {};
    @track showSuccessDialog = false;
    @track isLoading = true;

    connectedCallback() {

        getColors().then(colors => {
            if (colors?.primary) {
                document.documentElement.style.setProperty('--primary-color', colors.primary);
            }
            if (colors?.secondary) {
                document.documentElement.style.setProperty('--secondary-color', colors.secondary);
            }
        }).catch(() => {
            console.log('Error getting colors');
        });
    }

    @wire(getFaqData)
    wiredFaq({ data, error }) {
        if (data) {
            this.faqData = JSON.parse(JSON.stringify(data));
            this.isLoading = false;
        }
        if (error) {
            // Handle UI errors if needed
            console.error(error);
            this.faqData = [];
            this.isLoading = false;
        }
    }

    get filteredData() {
        const list = this.faqData.slice(0, 3);
        const query = this.searchQuery?.toLowerCase()?.trim();

        return list.map((cat) => {
            const catExpanded = this.expandedCategories.has(cat.category);

            let questions = cat.questions.slice(0, 3).map(q => {
                const isExpanded = this.expandedQuestions.has(q.id);
                const votes = this.questionVotes[q.id] || { thumbsUp: 0, thumbsDown: 0 };
                const activeType = this.activeFeedback[q.id] || null;
                const thumbsUpActive = activeType === 'up';
                const thumbsDownActive = activeType === 'down';
                return {
                    ...q,
                    isExpanded: isExpanded,
                    iconClass: isExpanded ? 'expand-icon minus-icon' : 'expand-icon plus-icon',
                    itemClass: isExpanded ? 'question-item expanded' : 'question-item',
                    thumbsUp: votes.thumbsUp || 0,
                    thumbsDown: votes.thumbsDown || 0,
                    thumbsUpActive: thumbsUpActive,
                    thumbsDownActive: thumbsDownActive,
                    thumbsUpBtnClass: thumbsUpActive ? 'feedback-btn thumbs-up-btn active' : 'feedback-btn thumbs-up-btn',
                    thumbsDownBtnClass: thumbsDownActive ? 'feedback-btn thumbs-down-btn active' : 'feedback-btn thumbs-down-btn'
                };
            });

            if (query) {
                const filtered = cat.questions.filter(q =>
                    q.question.toLowerCase().includes(query) ||
                    (q.answer && q.answer.toLowerCase().includes(query))
                );
                questions = filtered.slice(0, 3).map(q => {
                    const isExpanded = this.expandedQuestions.has(q.id);
                    const votes = this.questionVotes[q.id] || { thumbsUp: 0, thumbsDown: 0 };
                    const activeType = this.activeFeedback[q.id] || null;
                    const thumbsUpActive = activeType === 'up';
                    const thumbsDownActive = activeType === 'down';
                    return {
                        ...q,
                        isExpanded: isExpanded,
                        iconClass: isExpanded ? 'expand-icon minus-icon' : 'expand-icon plus-icon',
                        itemClass: isExpanded ? 'question-item expanded' : 'question-item',
                        thumbsUp: votes.thumbsUp || 0,
                        thumbsDown: votes.thumbsDown || 0,
                        thumbsUpActive: thumbsUpActive,
                        thumbsDownActive: thumbsDownActive,
                        thumbsUpBtnClass: thumbsUpActive ? 'feedback-btn thumbs-up-btn active' : 'feedback-btn thumbs-up-btn',
                        thumbsDownBtnClass: thumbsDownActive ? 'feedback-btn thumbs-down-btn active' : 'feedback-btn thumbs-down-btn'
                    };
                });
            }

            return {
                ...cat,
                isExpanded: catExpanded,
                iconClass: catExpanded ? 'category-icon expanded' : 'category-icon',
                headerClass: catExpanded ? 'category-header is-open' : 'category-header',
                questions,
                hasQuestions: questions.length > 0
            };
        });
    }

    get hasVisibleFaqs() {
        return this.visibleFilteredData.length > 0;
    }

    get visibleFilteredData() {
        return this.filteredData.filter(category => category.hasQuestions);
    }

    get noResultsMessage() {
        return this.searchQuery && this.searchQuery.trim()
            ? 'No FAQs found matching your search.'
            : 'No FAQs available.';
    }

    @api
    filterFAQs(query) {
        this.searchQuery = query;

        if (query && query.trim()) {
            this.filteredData.forEach(cat => {
                if (cat.questions.length > 0) {
                    this.expandedCategories.add(cat.category);
                }
            });
        }
    }

    handleCategoryToggle(event) {
        const id = event.currentTarget.dataset.categoryId;
        this.toggleSetValue(this.expandedCategories, id);
    }

    handleQuestionToggle(event) {
        const id = event.currentTarget.dataset.questionId;
        this.toggleSetValue(this.expandedQuestions, id);
    }

    toggleSetValue(setObj, id) {
        if (setObj.has(id)) {
            setObj.delete(id);
        } else {
            setObj.add(id);
        }
        // Reassign for reactivity
        this.expandedCategories = new Set(this.expandedCategories);
        this.expandedQuestions = new Set(this.expandedQuestions);
    }

    handleFeedback(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const feedbackType = event.currentTarget.dataset.type;

        if (!this.questionVotes[questionId]) {
            this.questionVotes[questionId] = { thumbsUp: 0, thumbsDown: 0 };
        }

        const currentActive = this.activeFeedback[questionId];
        const voteKey = feedbackType === 'up' ? 'thumbsUp' : 'thumbsDown';
        const otherKey = feedbackType === 'up' ? 'thumbsDown' : 'thumbsUp';

        if (currentActive === feedbackType) {
            delete this.activeFeedback[questionId];
            if (this.questionVotes[questionId][voteKey] > 0) {
                this.questionVotes[questionId][voteKey] -= 1;
            }
        } else {
            if (currentActive) {
                if (this.questionVotes[questionId][otherKey] > 0) {
                    this.questionVotes[questionId][otherKey] -= 1;
                }
            }
            this.activeFeedback[questionId] = feedbackType;
            this.questionVotes[questionId][voteKey] = (this.questionVotes[questionId][voteKey] || 0) + 1;

            if (feedbackType === 'down') {
                this.showSuccessDialog = true;
                setTimeout(() => { this.showSuccessDialog = false; }, 3000);
            }
        }

        this.questionVotes = { ...this.questionVotes };
        this.activeFeedback = { ...this.activeFeedback };
    }

    handleModalContainerClick(event) {
        event.stopPropagation();
    }

    closeSuccessDialog() {
        this.showSuccessDialog = false;
    }

    handleViewMore() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'faqs__c'
            }
        });
    }
}