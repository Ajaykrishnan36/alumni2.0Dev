import { LightningElement, track } from 'lwc';
import CoverImage from '@salesforce/resourceUrl/PortalLoginImage';

export default class KenJoinedGroupDetailView extends LightningElement {
    coverUrl = CoverImage;

    @track activeTab = 'About';
    @track showLeaveConfirm = false;
    @track showLeaveSuccess = false;

    dateString = '12 Jun 2023';
    membersCountText = '13 members';

    @track mockMembersList = [
        { id: '1', name: 'Rahul Mehta',    batch: 'Batch - 2020', avatar: CoverImage },
        { id: '2', name: 'Siddharth Iyer', batch: 'Batch - 2020', avatar: CoverImage },
        { id: '3', name: 'Anjali Sinha',   batch: 'Batch - 2020', avatar: CoverImage },
        { id: '4', name: 'Neha Kulkarni',  batch: 'Batch - 2020', avatar: CoverImage },
        { id: '5', name: 'Priya Nambiar',  batch: 'Batch - 2020', avatar: CoverImage }
    ];

    // ── Tab visibility ───────────────────────────────────────────────
    get showAbout()   { return this.activeTab === 'About'; }
    get showFeed()    { return this.activeTab === 'Feed'; }
    get showEvents()  { return this.activeTab === 'Events'; }
    get showMembers() { return this.activeTab === 'Members'; }

    // ── Tab CSS classes ──────────────────────────────────────────────
    get tabAboutClass()   { return this.activeTab === 'About'   ? 'tab active' : 'tab'; }
    get tabFeedClass()    { return this.activeTab === 'Feed'    ? 'tab active' : 'tab'; }
    get tabEventsClass()  { return this.activeTab === 'Events'  ? 'tab active' : 'tab'; }
    get tabMembersClass() { return this.activeTab === 'Members' ? 'tab active' : 'tab'; }

    openAboutTab()   { this.activeTab = 'About'; }
    openFeedTab()    { this.activeTab = 'Feed'; }
    openEventsTab()  { this.activeTab = 'Events'; }
    openMembersTab() { this.activeTab = 'Members'; }

    // ── Leave flow ───────────────────────────────────────────────────
    handleLeaveClick() {
        this.showLeaveConfirm = true;
    }

    cancelLeave() {
        this.showLeaveConfirm = false;
    }

    confirmLeave() {
        this.showLeaveConfirm = false;
        this.showLeaveSuccess = true;
        // Auto-dismiss success modal after 2s
        setTimeout(() => {
            this.showLeaveSuccess = false;
        }, 2000);
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}