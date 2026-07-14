import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenDateSelection extends LightningElement {
    @api selectedDates = [];
    @api currentDate;
    @api calendarDays = [];
    @api currentMonthYear = '';

    handleDateClick(event) {
        const date = event.currentTarget.dataset.date;
        this.dispatchEvent(new CustomEvent('datechange', {
            detail: { date },
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveDate(event) {
        const date = event.currentTarget.dataset.date;
        this.dispatchEvent(new CustomEvent('removedate', {
            detail: { date },
            bubbles: true,
            composed: true
        }));
    }

    handlePrevMonth() {
        this.dispatchEvent(new CustomEvent('monthchange', {
            detail: { direction: 'prev' },
            bubbles: true,
            composed: true
        }));
    }

    handleNextMonth() {
        this.dispatchEvent(new CustomEvent('monthchange', {
            detail: { direction: 'next' },
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
            console.log('Error getting primary color');
        });
    }
}