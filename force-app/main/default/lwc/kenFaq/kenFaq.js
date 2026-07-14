import { LightningElement, track, wire } from 'lwc';
import getFaqData from '@salesforce/apex/KenServiceSupportController.getFAQs';
import updateFaqVote from '@salesforce/apex/KenServiceSupportController.updateFaqVote';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';
export default class KenFaq extends LightningElement {
    @track filteredFaqData = [];
    @track expandedCategories = new Set();
    @track expandedQuestions = new Set();
    @track questionVotes = {}; // Track votes: { questionId: { thumbsUp: number, thumbsDown: number } }
    @track activeFeedback = {}; // Track active feedback: { questionId: 'up' | 'down' }
   // @track showFeedbackModal = false;
    @track showSuccessDialog = false;
    @track currentFeedbackQuestionId = null;
    @track selectedFeedbackOption = null;
    @track feedbackDescription = '';
    @track searchQuery = '';

    wiredResult;

    connectedCallback() {
        getColors().then(colors => {
            this.applyOrganizationTheme(colors);
        }).catch(() => {
            console.log('Error getting colors');
        });
    }

    get crumbs() {
        return [
            { label: 'Home', url: '' },
            { label: 'Service & Support', url: '/service-support' },
            { label: 'Frequently Asked Questions' }
        ];
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

    @wire(getFaqData)
    wiredFaq(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.filteredFaqData = JSON.parse(JSON.stringify(data));

            this.filteredFaqData.forEach(cat => {
                cat.questions.forEach(q => {
                    const likes = q.likeCount ?? 0;
                    const dislikes = q.dislikeCount ?? 0;
                    this.questionVotes[q.id] = { thumbsUp: likes, thumbsDown: dislikes };
                });
            });

            // Reassign the @track field so the template re-renders after mutation.
            this.questionVotes = { ...this.questionVotes };
        }

        if (error) {
            console.error(error);
        }
    }

       async applyVoteChange(questionId, newType) {
        const oldType = this.activeFeedback[questionId] || null;

        const finalNewType = (oldType === newType) ? null : newType;

        const res = await updateFaqVote({
            faqId: questionId,
            oldReaction: oldType,
            newReaction: finalNewType
        });

        this.activeFeedback = { ...this.activeFeedback };
        if (finalNewType) {
            this.activeFeedback[questionId] = finalNewType;
        } else {
            delete this.activeFeedback[questionId];
        }

        this.questionVotes = {
            ...this.questionVotes,
            [questionId]: {
                thumbsUp: res.likeCount,
                thumbsDown: res.dislikeCount
            }
        };

        this.filteredFaqData = [...this.filteredFaqData];
    }

    get filteredData() {
        const searchLower = this.searchQuery.toLowerCase().trim();
        
        return this.filteredFaqData
            .map(category => {
                const isExpanded = this.expandedCategories.has(category.category);
                
                // Filter questions based on search query
                let filteredQuestions = category.questions;
                if (searchLower) {
                    filteredQuestions = category.questions.filter(q => {
                        const questionMatch = q.question.toLowerCase().includes(searchLower);
                        const answerMatch = q.answer && q.answer.toLowerCase().includes(searchLower);
                        const categoryMatch = category.category.toLowerCase().includes(searchLower);
                        return questionMatch || answerMatch || categoryMatch;
                    });
                }
                
                // If search is active and no questions match, hide the category
                if (searchLower && filteredQuestions.length === 0) {
                    return null;
                }
                
                return {
                    ...category,
                    isExpanded: isExpanded || searchLower.length > 0, // Auto-expand on search
                    iconClass: (isExpanded || searchLower.length > 0) ? 'category-icon expanded' : 'category-icon',
                    questions: filteredQuestions.map(q => {
                        const isQuestionExpanded = this.expandedQuestions.has(q.id) || searchLower.length > 0; // Auto-expand on search
                        const votes = this.questionVotes[q.id] || {
                            thumbsUp: q.likeCount ?? 0,
                            thumbsDown: q.dislikeCount ?? 0
                        };

                        const activeType = this.activeFeedback[q.id] || null;
                        const thumbsUpActive = activeType === 'up';
                        const thumbsDownActive = activeType === 'down';
                        return {
                            ...q,
                            isExpanded: isQuestionExpanded,
                            iconClass: isQuestionExpanded ? 'expand-icon minus-icon' : 'expand-icon plus-icon',
                            itemClass: isQuestionExpanded ? 'question-item expanded' : 'question-item',
                            thumbsUp: votes.thumbsUp || 0,
                            thumbsDown: votes.thumbsDown || 0,
                            thumbsUpActive: thumbsUpActive,
                            thumbsDownActive: thumbsDownActive,
                            thumbsUpBtnClass: thumbsUpActive ? 'feedback-btn thumbs-up-btn active' : 'feedback-btn thumbs-up-btn',
                            thumbsDownBtnClass: thumbsDownActive ? 'feedback-btn thumbs-down-btn active' : 'feedback-btn thumbs-down-btn'
                        };
                    })
                };
            })
            .filter(category => category !== null); // Remove null categories
    }

    handleCategoryToggle(event) {
        const categoryId = event.currentTarget.dataset.categoryId;

        if (this.expandedCategories.has(categoryId)) {
            this.expandedCategories.delete(categoryId);
        } else {
            this.expandedCategories.add(categoryId);
        }

        this.expandedCategories = new Set(this.expandedCategories);
        this.filteredFaqData = [...this.filteredFaqData];
    }

    handleQuestionToggle(event) {
        const questionId = event.currentTarget.dataset.questionId;

        if (this.expandedQuestions.has(questionId)) {
            this.expandedQuestions.delete(questionId);
        } else {
            this.expandedQuestions.add(questionId);
        }

        this.expandedQuestions = new Set(this.expandedQuestions);
        this.filteredFaqData = [...this.filteredFaqData];
    }

       /* async handleFeedback(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const feedbackType = event.currentTarget.dataset.type; // 'up' or 'down'

        // Ensure local structure exists
        if (!this.questionVotes[questionId]) {
            this.questionVotes[questionId] = { thumbsUp: 0, thumbsDown: 0 };
        }

        if (feedbackType === 'down') {
            const currentActive = this.activeFeedback[questionId] || null;

            if (currentActive === 'down') {
                try {
                    await this.applyVoteChange(questionId, 'down');
                } catch (e) {
                    // eslint-disable-next-line no-console
                    console.error(e);
                }
                return;
            }

            // Otherwise open modal first, only commit on submit
            this.currentFeedbackQuestionId = questionId;
            this.selectedFeedbackOption = null;
            this.feedbackDescription = '';
            this.showFeedbackModal = true;
            return;
        }

        // UP button: toggle/switch immediately
        try {
            await this.applyVoteChange(questionId, 'up');
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
        }
    } */

    async handleFeedback(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const feedbackType = event.currentTarget.dataset.type; // 'up' or 'down'

        const currentActive = this.activeFeedback[questionId] || null;

        let newReaction = feedbackType;
        if (currentActive === feedbackType) {
            newReaction = null;
        }

        try {
            const res = await updateFaqVote({
                faqId: questionId,
                oldReaction: currentActive,
                newReaction: newReaction
            });

            // Update local state
            if (newReaction) {
                this.activeFeedback[questionId] = newReaction;
            } else {
                delete this.activeFeedback[questionId];
            }

            this.questionVotes = {
                ...this.questionVotes,
                [questionId]: {
                    thumbsUp: res.likeCount,
                    thumbsDown: res.dislikeCount
                }
            };

            this.activeFeedback = { ...this.activeFeedback };
            this.filteredFaqData = [...this.filteredFaqData];

            if (feedbackType === 'down' && newReaction === 'down') {
                this.currentFeedbackQuestionId = questionId;
                this.selectedFeedbackOption = null;
                this.feedbackDescription = '';
                this.showFeedbackModal = true;
            }

        } catch (error) {
            console.error(error);
        }
    }


    handleFeedbackOptionSelect(event) {
        this.selectedFeedbackOption = event.currentTarget.dataset.option;
    }

    handleDescriptionChange(event) {
        this.feedbackDescription = event.target.value;
    }

    handleMaybeLater() {
      //  this.showFeedbackModal = false;
        this.currentFeedbackQuestionId = null;
        this.selectedFeedbackOption = null;
        this.feedbackDescription = '';
    }

    async handleSubmitFeedback() {
      //  this.showFeedbackModal = false;

        const questionId = this.currentFeedbackQuestionId;

        try {
            await this.applyVoteChange(questionId, 'down');
        } catch (e) {
            console.error(e);
        }

        this.currentFeedbackQuestionId = null;
        this.selectedFeedbackOption = null;
        this.feedbackDescription = '';

        // Show success dialog
        this.showSuccessDialog = true;
        
        // Auto-close success dialog after 3 seconds
        setTimeout(() => {
            this.showSuccessDialog = false;
        }, 3000);
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleMaybeLater();
        }
    }

    handleModalContainerClick(event) {
        event.stopPropagation();
    }

    closeSuccessDialog() {
        this.showSuccessDialog = false;
    }

    get notClearBtnClass() {
        return this.selectedFeedbackOption === 'not-clear' ? 'feedback-option-btn active' : 'feedback-option-btn';
    }

    get tooGenericBtnClass() {
        return this.selectedFeedbackOption === 'too-generic' ? 'feedback-option-btn active' : 'feedback-option-btn';
    }

    get outdatedBtnClass() {
        return this.selectedFeedbackOption === 'outdated' ? 'feedback-option-btn active' : 'feedback-option-btn';
    }

    get missingDetailsBtnClass() {
        return this.selectedFeedbackOption === 'missing-details' ? 'feedback-option-btn active' : 'feedback-option-btn';
    }

    handleSearchChange(event) {
        this.searchQuery = event.target.value;
    }
}