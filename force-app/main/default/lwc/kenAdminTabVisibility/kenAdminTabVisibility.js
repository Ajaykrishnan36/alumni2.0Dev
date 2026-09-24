import { LightningElement } from 'lwc';
import { getModuleVisibility } from 'c/kenModuleConfig';

/**
 * Maps a tab label on the Alumni Management home page to its
 * Ken_Alm_Module_Settings__c toggle key. Labels absent from this map -- Dashboard,
 * Report, Master Records, Data Management, Communications -- are core admin
 * screens with no module switch behind them, so they are never hidden.
 */
const TAB_TO_MODULE_FLAG = {
    Event: 'events',
    Support: 'serviceSupport',
    Survey: 'feedbackSurvey',
    Network: 'network',
    Mentorship: 'mentorship',
    Groups: 'groups',
    Fundraise: 'fundraise',
    'Business Directory': 'businessDirectory'
};

const RETRY_LIMIT = 40;
const RETRY_DELAY = 150;

/**
 * Headless companion for the Alumni Management home page. Salesforce refuses a
 * visibility rule on a flexipage:tab ("You can't set a rule on a 'flexipage:tab'
 * component"), and component visibility filters cannot read a hierarchy custom
 * setting in any case, so a switched-off module has to be taken out of the tab
 * strip here instead of in App Builder.
 */
export default class KenAdminTabVisibility extends LightningElement {
    _hiddenLabels = [];
    _observer;
    _timer;
    _attempts = 0;

    connectedCallback() {
        getModuleVisibility()
            .then((visibility) => {
                this._hiddenLabels = Object.keys(TAB_TO_MODULE_FLAG).filter(
                    (label) => visibility && visibility[TAB_TO_MODULE_FLAG[label]] === false
                );
                if (this._hiddenLabels.length) {
                    this._waitForTabs();
                }
            })
            .catch(() => {
                // Fail open, exactly as the portal nav does: every tab stays visible.
            });
    }

    disconnectedCallback() {
        if (this._observer) {
            this._observer.disconnect();
            this._observer = undefined;
        }
        if (this._timer) {
            window.clearTimeout(this._timer);
            this._timer = undefined;
        }
    }

    /** The tab strip belongs to the page, not to this component, so it renders on its own schedule. */
    _waitForTabs() {
        if (this._applyVisibility()) {
            this._observe();
            return;
        }
        if (this._attempts >= RETRY_LIMIT) {
            return;
        }
        this._attempts += 1;
        this._timer = window.setTimeout(() => this._waitForTabs(), RETRY_DELAY);
    }

    /**
     * Reached through the document because the tabset sits outside this component's
     * shadow root -- the same route kenAdminDashboard already uses to switch tabs.
     */
    _applyVisibility() {
        const tabs = document.querySelectorAll('[role="tab"]');
        if (!tabs.length) {
            return false;
        }
        let activeWasHidden = false;
        tabs.forEach((tab) => {
            if (!this._hiddenLabels.includes(this._labelOf(tab))) {
                return;
            }
            const item = tab.closest('li') || tab.parentElement;
            if (item) {
                item.style.display = 'none';
            }
            if (tab.getAttribute('aria-selected') === 'true') {
                activeWasHidden = true;
            }
        });
        if (activeWasHidden) {
            this._selectFirstVisibleTab();
        }
        return true;
    }

    /** A hidden tab must not stay selected, or the page opens on a module that is switched off. */
    _selectFirstVisibleTab() {
        const tabs = document.querySelectorAll('[role="tab"]');
        for (const tab of tabs) {
            if (!this._hiddenLabels.includes(this._labelOf(tab))) {
                tab.click();
                return;
            }
        }
    }

    _labelOf(tab) {
        return (tab.title || tab.getAttribute('aria-label') || tab.textContent || '').trim();
    }

    /** The tabset re-renders on navigation, which would bring the hidden tabs back. */
    _observe() {
        const list = document.querySelector('[role="tablist"]');
        if (!list || this._observer) {
            return;
        }
        this._observer = new MutationObserver(() => this._applyVisibility());
        this._observer.observe(list, { childList: true, subtree: true });
    }
}