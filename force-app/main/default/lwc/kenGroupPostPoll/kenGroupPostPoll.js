import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import votePoll from '@salesforce/apex/KenGroupFeedController.votePoll';

export default class KenGroupPostPoll extends LightningElement {
    @track _poll;
    @track isVoting = false;

    @api
    get poll() { return this._poll; }
    set poll(value) {
        this._poll = value ? { ...value, options: this.decorate(value) } : value;
    }

    decorate(poll) {
        if (!poll || !poll.options) return [];
        const showResults = poll.hasVoted || poll.isClosed;
        return poll.options.map(o => ({
            ...o,
            showResults,
            barStyle: `width: ${o.votePercent || 0}%`,
            optionClass: `poll-option${o.votedByMe ? ' is-mine' : ''}${showResults ? ' is-results' : ''}`
        }));
    }

    get showResults()    { return this._poll && (this._poll.hasVoted || this._poll.isClosed); }
    get votersLabel() {
        if (!this._poll) return '';
        const n = this._poll.totalVotes || 0;
        if (n === 0) return 'No votes yet';
        return n === 1 ? '1 vote' : `${n} votes`;
    }
    get statusLabel() {
        if (!this._poll || !this._poll.endsAt) return '';
        if (this._poll.isClosed) return 'Poll closed';
        const end = new Date(this._poll.endsAt);
        const diffMs = end.getTime() - Date.now();
        if (diffMs <= 0) return 'Poll closed';
        const days = Math.floor(diffMs / 86400000);
        const hours = Math.floor((diffMs % 86400000) / 3600000);
        if (days > 0) return `${days}d left`;
        if (hours > 0) return `${hours}h left`;
        return 'Closing soon';
    }

    handleVote(event) {
        if (this.isVoting || !this._poll || this._poll.hasVoted || this._poll.isClosed) return;
        const optionText = event.currentTarget.dataset.id; // text doubles as the option key now
        if (!optionText) return;
        this.isVoting = true;
        votePoll({ pollId: this._poll.pollId, optionText })
            .then(updated => {
                if (updated) {
                    this._poll = { ...updated, options: this.decorate(updated) };
                }
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Could not vote',
                    message: this.extractError(err),
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isVoting = false;
            });
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }
}