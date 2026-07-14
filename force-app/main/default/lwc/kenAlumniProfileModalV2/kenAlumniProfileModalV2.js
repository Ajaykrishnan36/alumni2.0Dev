import { LightningElement, api } from 'lwc';

export default class KenAlumniProfileModalV2 extends LightningElement {
    @api alumni;
    @api connected = false;

    get decorated() {
        if (!this.alumni) return null;
        const a = this.alumni;
        return {
            ...a,
            heroAvatarStyle: 'background:linear-gradient(135deg,#E8B4D6,#B033C8);color:#fff;',
            statsLine: `${a.mutual} mutual · ${a.batch} · ${a.follows} follows`,
            connectLabel: this.connected ? 'Connected' : 'Connect',
            connectIcon: this.connected ? '✓' : '+',
            connectBtnClass: this.connected ? 'pf__btn outline' : 'pf__btn primary',
            roleLine: `${a.role} at ${a.company}`,
            cityLine: `📍 ${a.city}`,
            statsIcon: `🤝 ${a.mutual} mutual · ${a.batch} · ${a.follows} follows`,
            showWilling: !!a.willing
        };
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
    handleStopProp(event) { event.stopPropagation(); }
    handleConnect() {
        this.dispatchEvent(new CustomEvent('connect', { detail: { id: this.alumni ? this.alumni.id : null, connected: this.connected } }));
    }
    handleMessage() {
        this.dispatchEvent(new CustomEvent('message', { detail: { id: this.alumni ? this.alumni.id : null } }));
    }
}