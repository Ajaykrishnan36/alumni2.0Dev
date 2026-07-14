import { LightningElement } from 'lwc';
import updateLastActive from '@salesforce/apex/UserActivityController.updateLastActive';

const HEARTBEAT_INTERVAL_MS = 60 * 1000;
const ACTIVITY_EVENTS = ['click', 'keydown', 'scroll', 'mousemove'];

export default class AlumniPresenceTracker extends LightningElement {
    lastPingAt = 0;
    pingIntervalId = null;
    inFlight = false;

    boundHandleActivity;
    boundHandleVisibilityChange;

    connectedCallback() {
        this.boundHandleActivity = this.handleActivity.bind(this);
        this.boundHandleVisibilityChange = this.handleVisibilityChange.bind(this);

        ACTIVITY_EVENTS.forEach((eventName) => {
            window.addEventListener(eventName, this.boundHandleActivity, { passive: true });
        });
        document.addEventListener('visibilitychange', this.boundHandleVisibilityChange);

        this.sendPing({ force: true });
        this.pingIntervalId = window.setInterval(() => {
            if (!document.hidden) {
                this.sendPing();
            }
        }, HEARTBEAT_INTERVAL_MS);
    }

    disconnectedCallback() {
        ACTIVITY_EVENTS.forEach((eventName) => {
            window.removeEventListener(eventName, this.boundHandleActivity);
        });
        document.removeEventListener('visibilitychange', this.boundHandleVisibilityChange);

        if (this.pingIntervalId) {
            window.clearInterval(this.pingIntervalId);
            this.pingIntervalId = null;
        }
    }

    handleActivity() {
        this.sendPing();
    }

    handleVisibilityChange() {
        if (!document.hidden) {
            this.sendPing({ force: true });
        }
    }

    async sendPing({ force = false } = {}) {
        if (document.hidden) {
            return;
        }

        const now = Date.now();
        const elapsedMs = now - this.lastPingAt;
        if (!force && elapsedMs < HEARTBEAT_INTERVAL_MS) {
            return;
        }
        if (this.inFlight) {
            return;
        }

        this.inFlight = true;
        try {
            await updateLastActive();
            this.lastPingAt = Date.now();
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('alumniPresenceTracker.sendPing failed', error);
        } finally {
            this.inFlight = false;
        }
    }
}