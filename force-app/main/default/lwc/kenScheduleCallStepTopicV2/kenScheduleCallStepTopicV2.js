import { LightningElement, api } from 'lwc';

export default class KenScheduleCallStepTopicV2 extends LightningElement {
    @api topic = '';
    @api agenda = '';

    handleTopic(event) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'topic', value: event.target.value } }));
    }
    handleAgenda(event) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'agenda', value: event.target.value } }));
    }
}