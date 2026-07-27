import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

/*
 * Wrapper usage (e.g. in a parent page that switches by viewport):
 *   <template if:true={isDesktop}><c-ken-chat></c-ken-chat></template>
 *   <template if:true={isMobile}><c-ken-mobile-chat></c-ken-mobile-chat></template>
 * where isDesktop = window.matchMedia('(min-width: 769px)').matches and
 * isMobile = window.matchMedia('(max-width: 768px)').matches (with resize listener).
 * Alternatively use CSS: .ken-chat { display: block } @media (max-width:768px) { .ken-chat { display: none } }
 * and .ken-mobile-chat { display: none } @media (max-width:768px) { .ken-mobile-chat { display: block } }
 */

const INDIVIDUALS = [
    { id: 'i1', type: 'individual', name: 'Rohit Sharma', avatarUrl: '', lastMessage: 'Hiii..', lastTime: 'Just now', pillTag: 'Mentor', online: true },
    { id: 'i2', type: 'individual', name: 'Florencio Dorrance', avatarUrl: '', lastMessage: 'Thank you!', lastTime: '10m', pillTag: null, online: false },
    { id: 'i3', type: 'individual', name: 'Florencio Dorrance', avatarUrl: '', lastMessage: 'Welcome', lastTime: '1 day ago', pillTag: 'Mentor', online: false },
    { id: 'i4', type: 'individual', name: 'Florencio Dorrance', avatarUrl: '', lastMessage: 'Thank you!', lastTime: '2 day ago', pillTag: null, online: false },
    { id: 'i5', type: 'individual', name: 'Rohit Sharma', avatarUrl: '', lastMessage: 'Hiii..', lastTime: '1 week ago', pillTag: 'Mentor', online: false },
    { id: 'i6', type: 'individual', name: 'Florencio Dorrance', avatarUrl: '', lastMessage: 'Welcome', lastTime: '2 weeks ago', pillTag: null, online: false }
];

const GROUPS = [
    { id: 'g1', type: 'group', name: 'Eco Warriors', avatarUrl: '', lastMessage: 'Hiii..', lastTime: 'Just now', pillTag: null, online: false, membersCount: 50, onlineMembersCount: 25 },
    { id: 'g2', type: 'group', name: 'Tech Titans', avatarUrl: '', lastMessage: 'Thank you!', lastTime: '10m', pillTag: 'You are the Admin', online: false, membersCount: 12, onlineMembersCount: 3 },
    { id: 'g3', type: 'group', name: 'Literary League', avatarUrl: '', lastMessage: 'Start Conversation', lastTime: '1 day ago', pillTag: null, online: false, membersCount: 8, onlineMembersCount: 0 },
    { id: 'g4', type: 'group', name: 'The Brainstorm Brigade', avatarUrl: '', lastMessage: 'Welcome', lastTime: '2 day ago', pillTag: null, online: false, membersCount: 15, onlineMembersCount: 5 },
    { id: 'g5', type: 'group', name: 'Diversity Dialogue', avatarUrl: '', lastMessage: 'Shall we connect now?', lastTime: '1 week ago', pillTag: null, online: false, membersCount: 20, onlineMembersCount: 2 },
    { id: 'g6', type: 'group', name: 'Tech Titans', avatarUrl: '', lastMessage: 'Thank you so much', lastTime: '2 weeks ago', pillTag: null, online: false, membersCount: 12, onlineMembersCount: 1 }
];

const MESSAGES_BY_CHAT = {
    i1: [
        { id: 'm1', text: 'perfect! ✔', time: '3:00 am', isOutgoing: false, senderName: 'Rohit Sharma', dateLabel: 'Yesterday' },
        { id: 'm2', text: "I'll be there in 2 mins ⏰", time: '3:01 am', isOutgoing: false, senderName: 'Rohit Sharma', dateLabel: null },
        { id: 'm3', text: 'woohoooo 🔥', time: '7:02 am', isOutgoing: false, senderName: 'Rohit Sharma', dateLabel: null },
        { id: 'm4', text: "Haha that's terrifying 🍔", time: '3:35 am', isOutgoing: true, senderName: 'You', dateLabel: null },
        { id: 'm5', text: 'Hiii..', time: '8:05 am', isOutgoing: true, senderName: 'You', dateLabel: 'Today' }
    ],
    g1: [
        { id: 'm1', text: 'Hii everyone', time: '3:00 am', isOutgoing: false, senderName: 'Sam Mattew', dateLabel: 'Today' },
        { id: 'm2', text: 'Hii, Any update regarding our projects', time: '3:00 am', isOutgoing: false, senderName: 'Sam Mattew', dateLabel: null },
        { id: 'm3', text: 'Hiii everyone!', time: '3:00 am', isOutgoing: true, senderName: 'You', dateLabel: null },
        { id: 'm4', text: 'Hiii', time: '3:00 am', isOutgoing: true, senderName: 'You', dateLabel: null }
    ]
};

export default class KenChat extends LightningElement {
    @track activeTab = 'individuals';
    @track searchTerm = '';
    @track selectedChat = INDIVIDUALS[0] || null;
    @track newMessageText = '';

    individualsList = INDIVIDUALS;
    groupsList = GROUPS;
    messagesByChat = MESSAGES_BY_CHAT;
    _initialScrollDone = false;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    get isIndividuals() {
        return this.activeTab === 'individuals';
    }

    get isGroups() {
        return this.activeTab === 'groups';
    }

    get currentList() {
        return this.activeTab === 'individuals' ? this.individualsList : this.groupsList;
    }

    get filteredList() {
        const list = this.currentList;
        const term = (this.searchTerm || '').toLowerCase().trim();
        const filtered = term ? list.filter(item => (item.name || '').toLowerCase().includes(term)) : list;
        const selId = this.selectedChatId;
        return filtered.map(item => ({ ...item, key: item.id, isSelected: item.id === selId }));
    }

    get selectedChatId() {
        return this.selectedChat ? this.selectedChat.id : null;
    }

    get currentMessages() {
        if (!this.selectedChat) return [];
        const msgs = this.messagesByChat[this.selectedChat.id] || [];
        return msgs.map((m, i) => ({ ...m, key: m.id || `msg-${i}` }));
    }

    get hasSelectedChat() {
        return !!this.selectedChat;
    }

    get isGroupSelected() {
        return this.selectedChat && this.selectedChat.type === 'group';
    }

    get chatHeaderSubline() {
        if (!this.selectedChat) return '';
        if (this.selectedChat.type === 'group') {
            return `${this.selectedChat.membersCount || 0} members`;
        }
        return this.selectedChat.online ? 'Online' : 'Offline';
    }

    get chatHeaderOnlineText() {
        if (!this.selectedChat || this.selectedChat.type !== 'group') return '';
        return `${this.selectedChat.onlineMembersCount || 0} members online`;
    }

    handleTabChange(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab) this.activeTab = tab;
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
    }

    handleChatSelect(event) {
        const id = event.currentTarget.dataset.id;
        const list = this.currentList;
        this.selectedChat = list.find(c => c.id === id) || null;
        this._scrollMessagesToBottomAfterRender();
    }

    renderedCallback() {
        if (this.hasSelectedChat && !this._initialScrollDone) {
            this._initialScrollDone = true;
            this._scrollMessagesToBottomAfterRender();
        }
    }

    scrollMessagesToBottom() {
        const el = this.template.querySelector('.chat-messages');
        if (el) el.scrollTop = el.scrollHeight;
    }

    _scrollMessagesToBottomAfterRender() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.scrollMessagesToBottom(), 0);
    }

    handleSend() {
        if (!this.selectedChat || !this.newMessageText.trim()) return;
        const chatId = this.selectedChat.id;
        const list = this.messagesByChat[chatId] ? [...this.messagesByChat[chatId]] : [];
        const now = new Date();
        const timeStr = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
        list.push({
            id: `new-${Date.now()}`,
            text: this.newMessageText.trim(),
            time: timeStr,
            isOutgoing: true,
            senderName: 'You',
            dateLabel: null
        });
        this.messagesByChat = { ...this.messagesByChat, [chatId]: list };
        const item = this.currentList.find(c => c.id === chatId);
        if (item) {
            item.lastMessage = this.newMessageText.trim();
            item.lastTime = 'Just now';
        }
        this.newMessageText = '';
        this._scrollMessagesToBottomAfterRender();
    }

    handleComposerInput(event) {
        this.newMessageText = event.target.value;
    }

    handleComposerKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSend();
        }
    }
}