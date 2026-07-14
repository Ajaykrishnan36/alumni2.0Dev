import { LightningElement, api, track } from 'lwc';

export default class KenVerifyLinkV2 extends LightningElement {
    @api email = '';
    @api otpLength = 4;
    @api expirySeconds = 120;
    @api institutionLogoUrl = '';
    @api poweredByLogoUrl = '';

    @track digits = [];
    @track secondsLeft = 120;
    _timerId = null;

    connectedCallback() {
        this.digits = Array.from({ length: this.otpLength }, (_, i) => ({ key: `d${i}`, value: '' }));
        this.secondsLeft = this.expirySeconds;
        this._startTimer();
    }

    disconnectedCallback() {
        this._stopTimer();
    }

    _startTimer() {
        this._stopTimer();
        this._timerId = setInterval(() => {
            if (this.secondsLeft > 0) this.secondsLeft -= 1;
            else this._stopTimer();
        }, 1000);
    }

    _stopTimer() {
        if (this._timerId) {
            clearInterval(this._timerId);
            this._timerId = null;
        }
    }

    get expiresLabel() {
        const m = String(Math.floor(this.secondsLeft / 60)).padStart(2, '0');
        const s = String(this.secondsLeft % 60).padStart(2, '0');
        return `Expires in ${m}:${s}`;
    }

    get otpComplete() {
        return this.digits.every((d) => d.value.length === 1);
    }

    get verifyDisabled() {
        return !this.otpComplete;
    }

    get verifyClass() {
        return this.verifyDisabled ? 'verify verify--disabled' : 'verify';
    }

    handleDigit(event) {
        const idx = Number(event.target.dataset.index);
        const raw = event.target.value.replace(/[^0-9]/g, '');
        const value = raw.slice(-1);
        const next = [...this.digits];
        next[idx] = { ...next[idx], value };
        this.digits = next;
        event.target.value = value;
        if (value && idx < this.digits.length - 1) {
            const inputs = this.template.querySelectorAll('.otp__input');
            if (inputs[idx + 1]) inputs[idx + 1].focus();
        }
    }

    handleKeydown(event) {
        if (event.key !== 'Backspace') return;
        const idx = Number(event.target.dataset.index);
        if (!this.digits[idx].value && idx > 0) {
            const inputs = this.template.querySelectorAll('.otp__input');
            if (inputs[idx - 1]) inputs[idx - 1].focus();
        }
    }

    handleEditEmail() {
        this.dispatchEvent(new CustomEvent('editemail'));
    }

    handleResend(event) {
        event.preventDefault();
        this.secondsLeft = this.expirySeconds;
        this._startTimer();
        this.dispatchEvent(new CustomEvent('resend'));
    }

    handleVerify() {
        if (!this.otpComplete) return;
        const code = this.digits.map((d) => d.value).join('');
        this.dispatchEvent(new CustomEvent('verify', { detail: { code, email: this.email } }));
    }
}