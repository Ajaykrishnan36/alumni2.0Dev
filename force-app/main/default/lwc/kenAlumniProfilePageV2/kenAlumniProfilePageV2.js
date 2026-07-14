import { LightningElement, api } from 'lwc';
import basePath from '@salesforce/community/basePath';

export default class KenAlumniProfilePageV2 extends LightningElement {
    @api alumni;
    @api connected = false;

    get hasWork() { return Array.isArray(this.alumni?.work) && this.alumni.work.length > 0; }
    get hasEducation() { return Array.isArray(this.alumni?.education) && this.alumni.education.length > 0; }
    get hasActivity() { return Array.isArray(this.alumni?.recentActivity) && this.alumni.recentActivity.length > 0; }
    get hasMutual() { return Array.isArray(this.alumni?.mutualConnections) && this.alumni.mutualConnections.length > 0; }

    get decorated() {
        if (!this.alumni) return null;
        const a = this.alumni;
        // Defensive defaults — any of role/company/city/batch can arrive null from Apex.
        const role = a.role || '';
        const company = a.company || '';
        const city = a.city || '';
        const batch = a.batch || '';
        const roleLine = role && company ? `${role} at ${company}` : (role || company);
        return {
            ...a,
            heroAvatarStyle: 'background:linear-gradient(135deg,#E8B4D6,#B033C8);color:#fff;',
            connectLabel: this.connected === true ? 'Connected' : 'Connect',
            connectIcon: this.connected === true ? '✓' : '+',
            connectBtnClass: this.connected === true ? 'pf__btn outline' : 'pf__btn primary',
            // Chat is only available between accepted connections. The button stays
            // disabled (with an explanatory tooltip) until `connected` is true, then
            // unlocks reactively — no page refresh needed.
            canChat: this.connected === true,
            cannotChat: this.connected !== true,
            chatLabel: this.connected === true ? 'Chat' : 'Message',
            chatTitle: this.connected === true ? 'Open chat' : 'Connect first to start chatting',
            roleLine,
            cityLine: city ? `📍 ${city}` : '',
            statsIcon: `🤝 ${Number(a.mutual) || 0} mutual · ${batch} · ${Number(a.follows) || 0} follows`,
            showWilling: a.willing === true || a.willing === 'true',
            // isMentor: derived from the alumni record. Sources, in priority order:
            //   a.isMentor (explicit) | a.willingToMentor | a.willing (legacy "Willing to help" flag).
            // Anything truthy turns on the hero "Mentor" pill.
            isMentor: a.isMentor === true || a.isMentor === 'true'
                || a.willingToMentor === true || a.willingToMentor === 'true'
                || a.willing === true || a.willing === 'true'
        };
    }

    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
    handleConnect() {
        this.dispatchEvent(new CustomEvent('connect', { detail: { id: this.alumni ? this.alumni.id : null, connected: this.connected } }));
    }
    handleMessage() {
        // Hard guard: chat is gated on an accepted connection. Even if the disabled
        // button were bypassed, never hand off to /chat for a non-connection.
        if (this.connected !== true) {
            this.dispatchEvent(new CustomEvent('messageblocked'));
            return;
        }
        const a = this.alumni || {};
        const targetId = a.id; // Person Account Id — Apex resolves to PersonContactId
        const targetName = a.name || '';
        // Always notify parent (preserves analytics/back-compat hooks).
        this.dispatchEvent(new CustomEvent('message', { detail: { id: targetId || null } }));
        // Validate target id — must look like a Salesforce 15/18-char Id starting with 001 (Account) or 003 (Contact).
        // Anything else (null, empty, mock numeric id) would produce a stale handoff that throws on chat-side resolver.
        const isValid = typeof targetId === 'string' && /^(001|003)[a-zA-Z0-9]{12,15}$/.test(targetId);
        // Diagnostic: log the exact id about to be handed off, so we can trace future bugs.
        // eslint-disable-next-line no-console
        console.log('[kenAlumniProfilePageV2] Chat handoff →', { targetId, name: targetName, isValidSfId: isValid, alumniSnapshot: { id: a.id, name: a.name } });
        if (!isValid) return;
        try {
            sessionStorage.setItem('a2-chat-target', JSON.stringify({
                contactId: targetId,
                name: targetName,
                ts: Date.now()
            }));
        } catch (e) { /* sandboxed — ignore */ }
        try { window.location.assign(basePath + '/chat'); } catch (e) { /* ignore */ }
    }
}