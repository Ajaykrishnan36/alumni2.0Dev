import { LightningElement } from 'lwc';

export default class SettingAccount extends LightningElement {
    handleTermsClick() {
        // Navigate to terms of service
        // You can use NavigationMixin or window.open here
    }

    handlePrivacyClick() {
        // Navigate to privacy policy
        // You can use NavigationMixin or window.open here
    }

    handleDeleteAccountClick() {
        // Show confirmation modal or navigate to delete account page
        // You can dispatch a custom event or show a modal here
    }
}