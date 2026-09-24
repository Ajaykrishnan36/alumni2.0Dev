import { LightningElement } from 'lwc';
import getConfig from '@salesforce/apex/KenKaiChatController.getConfig';
import getUserSession from '@salesforce/apex/KenKaiChatController.getUserSession';

const MOUNT_EVENT = 'kenkaichatmount';
const UPDATE_EVENT = 'kenkaichatupdate';
const UNMOUNT_EVENT = 'kenkaichatunmount';
const FALLBACK_REFRESH_MS = 10 * 60 * 1000;
const MIN_REFRESH_MS = 60 * 1000;
const REFRESH_FRACTION = 0.8;
const EXPIRY_MARGIN_S = 30;

/**
 * Headless mounter for the KAI chatbot; renders nothing of its own. Under Lightning Web Security a
 * global set by a page-level script is not visible from inside a component, so this component never
 * touches the SDK directly. It resolves the per-org config and, for logged-in alumni, a KAI user
 * token, then hands them across the sandbox boundary as window events. The bridge script in the
 * site head markup listens, loads the SDK from the configured URL and calls KaiChatBot.init, so the
 * panel floats above the whole portal and a KAI release is picked up without a deploy. Guests get the
 * public agent without a token; alumni get the authenticated agent with a token renewed before it
 * expires.
 */
export default class KenKaiChat extends LightningElement {
    mounted = false;
    refreshTimer;

    connectedCallback() {
        this.mount().catch((error) => {
            console.error('kenKaiChat: mount failed', error);
        });
    }

    disconnectedCallback() {
        this.teardown();
    }

    async mount() {
        const config = await getConfig();
        if (!config || !config.enabled) {
            return;
        }
        const detail = {
            sdkUrl: config.sdkUrl,
            apiKey: config.apiKey,
            agentId: config.agentId,
            baseUrl: config.baseUrl || ''
        };
        if (!config.isGuest) {
            const session = await getUserSession();
            detail.userToken = session.accessToken;
            detail.userId = session.externalId;
            this.scheduleRefresh(session.accessToken);
        }
        this.mounted = true;
        this.emit(MOUNT_EVENT, detail);
    }

    emit(name, detail) {
        window.dispatchEvent(new CustomEvent(name, { detail }));
    }

    scheduleRefresh(token) {
        this.clearRefresh();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.refreshTimer = setTimeout(() => {
            this.refreshToken();
        }, this.refreshDelayFor(token));
    }

    refreshDelayFor(token) {
        const claims = this.decodeJwt(token);
        if (!claims || !Number.isFinite(claims.exp)) {
            return FALLBACK_REFRESH_MS;
        }
        const nowSeconds = Date.now() / 1000;
        const issuedSeconds = Number.isFinite(claims.iat) ? claims.iat : nowSeconds;
        const lifetime = claims.exp - issuedSeconds;
        const untilExpiry = claims.exp - nowSeconds;
        const delayMs = Math.min(lifetime * REFRESH_FRACTION, untilExpiry - EXPIRY_MARGIN_S) * 1000;
        return Math.max(delayMs, MIN_REFRESH_MS);
    }

    decodeJwt(token) {
        try {
            const payload = String(token).split('.')[1];
            if (!payload) {
                return null;
            }
            const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
            const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
            return JSON.parse(atob(padded));
        } catch (error) {
            return null;
        }
    }

    async refreshToken() {
        try {
            const session = await getUserSession();
            this.emit(UPDATE_EVENT, { userToken: session.accessToken });
            this.scheduleRefresh(session.accessToken);
        } catch (error) {
            console.error('kenKaiChat: token renewal failed', error);
            this.teardown();
        }
    }

    clearRefresh() {
        if (this.refreshTimer) {
            clearTimeout(this.refreshTimer);
            this.refreshTimer = undefined;
        }
    }

    teardown() {
        this.clearRefresh();
        if (this.mounted) {
            this.mounted = false;
            this.emit(UNMOUNT_EVENT, {});
        }
    }
}