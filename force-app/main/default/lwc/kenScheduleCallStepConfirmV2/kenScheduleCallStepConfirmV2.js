import { LightningElement, api } from 'lwc';

export default class KenScheduleCallStepConfirmV2 extends LightningElement {
    @api mentorName = '';
    @api selectedDate = '';
    @api selectedSlot = '';
    @api selectedDuration = '';
    @api topic = '';
    @api agenda = '';
}