import { LightningElement, api } from 'lwc';

export default class KenChatConversationV2 extends LightningElement {
    static renderMode = 'light';
    @api activeName = '';
    @api activeStatus = '';
    @api activeInitial = '';
    @api activeAvatarStyle = '';
    @api messages = [];
    @api draft = '';

    handleDraft(event) {
        this.dispatchEvent(new CustomEvent('draftchange', {
            detail: { value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }
    handleSend() {
        this.dispatchEvent(new CustomEvent('send', { bubbles: true, composed: true }));
    }
    handleEnter(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.dispatchEvent(new CustomEvent('send', { bubbles: true, composed: true }));
        }
    }
    handleCall()   { this.dispatchEvent(new CustomEvent('call',   { bubbles: true, composed: true })); }
    handleVideo()  { this.dispatchEvent(new CustomEvent('video',  { bubbles: true, composed: true })); }
    handleMore()   { this.dispatchEvent(new CustomEvent('more',   { bubbles: true, composed: true })); }
    handleAttach() { this.dispatchEvent(new CustomEvent('attach', { bubbles: true, composed: true })); }
}