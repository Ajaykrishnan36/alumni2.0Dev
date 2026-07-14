import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenFeeSetup extends LightningElement {
    @api feeRowsByDate = [];
    @api feeSummaryTotal = 0; // kept for backward compatibility (session-wise total)

    @api eventTitle = '';
    @api mealsPaidAddonEnabled = false;
    @api mealFees = '';

    @api pricingMode = null; // 'SESSION_WISE' | 'OVERALL' | null
    @api overallPrice = '';
    @api overallIsFree = false;

    @track showSummary = false;

    get isSessionWiseSelected() {
        return this.pricingMode === 'SESSION_WISE';
    }

    get isOverallSelected() {
        return this.pricingMode === 'OVERALL';
    }


    get sessionWiseCardClass() {
        return this.isSessionWiseSelected ? 'fee-mode-card selected' : 'fee-mode-card';
    }

    get overallCardClass() {
        return this.isOverallSelected ? 'fee-mode-card selected' : 'fee-mode-card';
    }

    get summaryChevronClass() {
        return this.showSummary ? 'fee-chevron up' : 'fee-chevron';
    }

    get isMealFeesDisabled() {
        return !this.mealsPaidAddonEnabled;
    }

    // Totals
    get sessionWiseTotal() {
        let total = 0;
        (this.feeRowsByDate || []).forEach(day => {
            (day.sessions || []).forEach(s => {
                if (!s.isFree && s.price !== '' && s.price !== null && s.price !== undefined) {
                    total += Number(s.price) || 0;
                }
            });
        });
        if (this.mealsPaidAddonEnabled) {
            total += Number(this.mealFees) || 0;
        }
        return total;
    }

    get sessionWiseTotalFormatted() {
        return this.sessionWiseTotal.toFixed(2);
    }

    get overallWithoutMeal() {
        if (this.overallIsFree) return 0;
        return Number(this.overallPrice) || 0;
    }

    get overallWithMeal() {
        const base = this.overallWithoutMeal;
        const meal = this.mealsPaidAddonEnabled ? (Number(this.mealFees) || 0) : 0;
        return base + meal;
    }

    get overallWithMealFormatted() {
        return this.overallWithMeal.toFixed(2);
    }

    get overallWithoutMealFormatted() {
        return this.overallWithoutMeal.toFixed(2);
    }

    get overallTotal() {
        return this.mealsPaidAddonEnabled ? this.overallWithMeal : this.overallWithoutMeal;
    }

    get overallTotalFormatted() {
        return this.overallTotal.toFixed(2);
    }

    get mealFeesFormatted() {
        const meal = this.mealsPaidAddonEnabled ? (Number(this.mealFees) || 0) : 0;
        return meal.toFixed(2);
    }

    // Mode selection
    handleSelectSessionWise() {
        this.dispatchEvent(new CustomEvent('modechange', {
            detail: { pricingMode: 'SESSION_WISE' },
            bubbles: true,
            composed: true
        }));
    }

    handleSelectOverall() {
        this.dispatchEvent(new CustomEvent('modechange', {
            detail: { pricingMode: 'OVERALL' },
            bubbles: true,
            composed: true
        }));
    }

    // Session-wise handlers
    handleSessionPriceChange(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        const dateKey = event.currentTarget.dataset.dateKey;
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('sessionpricechange', {
            detail: { sessionId, dateKey, value },
            bubbles: true,
            composed: true
        }));
    }

    handleSessionFreeToggle(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        const dateKey = event.currentTarget.dataset.dateKey;
        const isFree = event.target.checked;
        this.dispatchEvent(new CustomEvent('sessionfreetoggle', {
            detail: { sessionId, dateKey, isFree },
            bubbles: true,
            composed: true
        }));
    }

    // Overall handlers
    handleOverallPriceChange(event) {
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('overallpricechange', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleOverallFreeToggle(event) {
        const isFree = event.target.checked;
        this.dispatchEvent(new CustomEvent('overallfreetoggle', {
            detail: { isFree },
            bubbles: true,
            composed: true
        }));
    }

    handleMealFeesChange(event) {
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('mealfeeschanged', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleToggleSummary() {
        this.showSummary = !this.showSummary;
    }

    handleViewSummary() {
        this.dispatchEvent(new CustomEvent('viewsummary', {
            bubbles: true,
            composed: true
        }));
    }
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            document.documentElement.style.setProperty('--primary-color', '#B7202E');
            document.documentElement.style.setProperty('--secondary-color', '#E9BABE');
            document.documentElement.style.setProperty('--tertiary-color', '#F8E9EA');
        });
    }
}