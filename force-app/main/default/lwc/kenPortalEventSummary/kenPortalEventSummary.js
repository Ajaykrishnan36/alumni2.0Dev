import { LightningElement, api } from 'lwc';

export default class KenPortalEventSummary extends LightningElement {
    // Step 7 (Summary) inputs from parent wizard
    @api eventData;
    @api selectedDates = [];
    @api sessionsByDate = {};
    @api feeRowsByDate = [];
    @api feeSummaryTotal = 0;

    // Dummy JSON to drive UI (backend wiring later)
    summaryData = {
        eventSetup: {
            title: 'Entrepreneurship Bootcamp',
            category: 'Workshops',
            language: 'English',
            brochure: { name: 'Entrepreneurship Bootcamp.PDF', url: '#' }
        },
        targetAudience: {
            groupName: 'Group 1',
            segment: 'Students',
            membersCount: 124
        },
        datesSelected: ['2026-12-12', '2026-12-13'],
        preEventSurveys: {
            meals: {
                enabled: true,
                byDate: [
                    { dateISO: '2026-12-12', meals: ['Breakfast', 'Lunch', 'Snacks', 'Dinner'] },
                    { dateISO: '2026-12-13', meals: ['Breakfast', 'Lunch', 'Snacks', 'Dinner'] }
                ]
            },
            customSurvey: { enabled: true, questionsCount: 5 }
        },
        sessionDetails: {
            mode: 'SESSION_WISE',
            days: [
                {
                    dateISO: '2026-12-12',
                    sessions: [
                        { index: 1, title: 'Introduction to Fin-tech Ecosystem', price: 250, feedbackQuestions: 5 }
                    ]
                },
                {
                    dateISO: '2026-12-13',
                    sessions: [
                        { index: 1, title: 'Blockchain and Cryptocurrency Demystified', price: 250, feedbackQuestions: 5 },
                        { index: 2, title: 'Digital Banking Innovations', price: null, feedbackQuestions: null }
                    ]
                }
            ],
            mealFees: 250,
            totalCost: 750
        }
    };

    get cards() {
        const d = this.summaryData;
        return {
            eventSetup: d.eventSetup,
            targetAudience: d.targetAudience,
            datesSelected: (d.datesSelected || []).map(dateISO => this.formatDate(dateISO)),
            preEventSurveys: {
                mealsEnabled: !!d.preEventSurveys?.meals?.enabled,
                mealsByDate: (d.preEventSurveys?.meals?.byDate || []).map(x => ({
                    dateISO: x.dateISO,
                    dateLabel: this.formatDate(x.dateISO),
                    mealsText: (x.meals || []).join(', ')
                })),
                customEnabled: !!d.preEventSurveys?.customSurvey?.enabled,
                questionsCount: d.preEventSurveys?.customSurvey?.questionsCount || 0
            },
            sessionDetails: {
                days: (d.sessionDetails?.days || []).map(day => ({
                    dateISO: day.dateISO,
                    dateLabel: this.formatDate(day.dateISO),
                    sessions: (day.sessions || []).map(s => ({
                        ...s,
                        priceText: this.formatCurrency(s.price),
                        feedbackText: s.feedbackQuestions ? `${s.feedbackQuestions} Questions` : '-'
                    }))
                })),
                mealFeesText: this.formatCurrency(d.sessionDetails?.mealFees),
                totalCostText: this.formatCurrency(d.sessionDetails?.totalCost)
            }
        };
    }

    formatDate(dateISO) {
        if (!dateISO) return '';
        const [y, m, d] = dateISO.split('-').map(n => parseInt(n, 10));
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const dd = String(d).padStart(2, '0');
        const mon = months[(m || 1) - 1] || '';
        return `${dd} ${mon}, ${y}`;
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') {
            return '₹-';
        }
        const num = Number(value);
        if (Number.isNaN(num)) return '₹-';
        return `₹${num.toFixed(2)}`;
    }

    // Navigation events (parent wizard will handle currentStep change)
    navigate(stepIndex, focus) {
        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { stepIndex, focus },
            bubbles: true,
            composed: true
        }));
    }

    handleEditEventSetup() {
        this.navigate(1, 'eventSetup');
    }

    handleEditTargetAudience() {
        this.navigate(2, 'targetAudience');
    }

    handleEditDatesSelected() {
        // Dates are selected in Event Setup in this wizard
        this.navigate(1, 'dates');
    }

    handleEditPreEventSurveys() {
        this.navigate(4, 'survey');
    }

    handleEditSession() {
        this.navigate(3, 'sessions');
    }

    handleEditFees() {
        this.navigate(5, 'fees');
    }

    handleEditFeedback() {
        this.navigate(6, 'feedback');
    }

    handleDownloadBrochure(evt) {
        evt.preventDefault();
        // Dummy behavior for now
    }
}