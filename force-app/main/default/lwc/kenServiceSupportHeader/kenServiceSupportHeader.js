import { LightningElement, api, track } from 'lwc';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';
export default class KenServiceSupportHeader extends LightningElement {
    @api userName = 'Guest';
    @track isListening = false;
    searchValue = '';
    recognition;

    handleSearchInput(event) {
        this.searchValue = event.target.value;
        this.dispatchSearchEvent();
    }

    handleSearchKeyPress(event) {
        if (event.key === 'Enter') {
            this.dispatchSearchEvent();
        }
    }

    handleVoiceSearch() {
        if (this.isListening) {
            this.stopVoiceSearch();
            return;
        }

        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRecognition) {
            this.dispatchSearchStatus('Voice search is not supported in this browser.');
            return;
        }

        this.recognition = new SpeechRecognition();
        this.recognition.lang = 'en-US';
        this.recognition.interimResults = true;
        this.recognition.continuous = false;

        this.recognition.onstart = () => {
            this.isListening = true;
        };

        this.recognition.onresult = event => {
            const transcript = Array.from(event.results)
                .map(result => result[0]?.transcript || '')
                .join(' ')
                .trim();
            if (transcript) {
                this.searchValue = transcript;
                this.dispatchSearchEvent();
            }
        };

        this.recognition.onerror = () => {
            this.isListening = false;
        };

        this.recognition.onend = () => {
            this.isListening = false;
        };

        try {
            this.recognition.start();
        } catch (error) {
            console.warn('Voice search start failed', error);
            this.isListening = false;
            this.recognition = null;
            this.dispatchSearchStatus('Voice search could not start. Please try again.');
        }
    }

    dispatchSearchEvent() {
        const searchEvent = new CustomEvent('searchchange', {
            detail: this.searchValue,
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(searchEvent);
    }

    dispatchSearchStatus(message) {
        this.dispatchEvent(new CustomEvent('searchstatus', {
            detail: message,
            bubbles: true,
            composed: true
        }));
    }

    stopVoiceSearch() {
        if (this.recognition) {
            try {
                this.recognition.stop();
            } catch (error) {
                console.warn('Voice search stop failed', error);
            }
        }
        this.recognition = null;
        this.isListening = false;
    }

    disconnectedCallback() {
        this.stopVoiceSearch();
    }

    get voiceButtonClass() {
        return this.isListening ? 'voice-search-btn listening' : 'voice-search-btn';
    }

    connectedCallback() {
        getColors().then(colors => {
            this.applyOrganizationTheme(colors);
        }).catch(() => {
            console.log('Error getting colors');
        });
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
}