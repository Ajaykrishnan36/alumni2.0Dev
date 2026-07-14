import { LightningElement, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getAllBusinesses from "@salesforce/apex/KenBusinessController.getAllBusinesses";
import getMyBusinesses from "@salesforce/apex/KenBusinessController.getMyBusinesses";
import createBusiness from "@salesforce/apex/KenBusinessController.createBusiness";
export default class KenBusinessDirectory extends NavigationMixin(LightningElement) {
    _roleId = localStorage.getItem('ConstituentRoleId');
  @track searchTerm = "";
  @track showFiltersPopup = false;
  @track selectedLocation = "";
  @track selectedBusinessType = "";
  @track popupStyle = "";
  @track showBusinessListingForm = false;
  @track businesses = [];

  connectedCallback() {
    getPrimaryColor()
      .then((color) => {
        document.documentElement.style.setProperty(
          "--primary-color",
          color?.primaryColor
        );
        document.documentElement.style.setProperty(
          "--secondary-color",
          color?.secondaryColor
        );
        document.documentElement.style.setProperty(
          "--tertiary-color",
          color?.tertiaryColor
        );
      })
      .catch(() => {});

    this.refreshLists();
  }

  @track myBusinesses = [];

  get filteredBusinesses() {
    let list = this.businesses || [];

    const term = (this.searchTerm || "").toLowerCase().trim();
    if (term) {
      list = list.filter(
        (business) =>
          (business.name || "").toLowerCase().includes(term) ||
          (business.category || "").toLowerCase().includes(term) ||
          (business.location || "").toLowerCase().includes(term) ||
          (business.ownerName || "").toLowerCase().includes(term)
      );
    }

    if (this.selectedLocation) {
      const loc = this.selectedLocation.toLowerCase();
      list = list.filter((business) =>
        (business.location || "").toLowerCase().includes(loc)
      );
    }

    if (this.selectedBusinessType) {
      const type = this.selectedBusinessType.toLowerCase();
      list = list.filter((business) =>
        (business.category || "").toLowerCase().includes(type)
      );
    }

    return list;
  }

  handleSearch(event) {
    this.searchTerm = event.detail.value || "";
  }

  handleFiltersClick() {
    this.showFiltersPopup = !this.showFiltersPopup;
  }

  renderedCallback() {
    if (this.showFiltersPopup) {
      this.positionPopup();
    }
  }

  positionPopup() {
    const filterBtn = this.template.querySelector('[data-filter-btn="true"]');
    const popup = this.template.querySelector(".filters-popup");

    if (filterBtn && popup) {
      const rect = filterBtn.getBoundingClientRect();
      const popupWidth = 400;
      const viewportWidth = window.innerWidth;
      const viewportHeight = window.innerHeight;

      // Calculate position - align to bottom-right of button
      let top = rect.bottom + 8;
      let right = viewportWidth - rect.right;

      // Adjust if popup would go off screen
      if (top + 500 > viewportHeight) {
        top = rect.top - 500 - 8;
        if (top < 0) {
          top = 8;
        }
      }

      if (right + popupWidth > viewportWidth) {
        right = 24;
      }

      this.popupStyle = `top: ${top}px; right: ${right}px;`;
    }
  }

  handleFiltersOverlayClick() {
    // Close popup when clicking on overlay
    this.showFiltersPopup = false;
  }

  handleFiltersPopupClick(event) {
    // Prevent closing when clicking inside the popup
    event.stopPropagation();
  }

  handleLocationChange(event) {
    this.selectedLocation = event.detail.value;
  }

  handleBusinessTypeChange(event) {
    this.selectedBusinessType = event.detail.value;
  }

  handleResetFilters() {
    this.selectedLocation = "";
    this.selectedBusinessType = "";
  }

  handleApplyFilters() {
    // Apply filter logic here
    this.showFiltersPopup = false;
  }

  get locationOptions() {
    return [
      { label: "Maharashtra, India", value: "maharashtra" },
      { label: "Uttarakhand, India", value: "uttarakhand" },
      { label: "Chennai, India", value: "chennai" }
    ];
  }

  get businessTypeOptions() {
    return [
      { label: "Food & beverage", value: "food" },
      { label: "Immersive experiences", value: "immersive" },
      { label: "Wooden toys", value: "toys" },
      { label: "Technology", value: "technology" }
    ];
  }

  handleBusinessClick(event) {
    this.navigateToDetail(event.detail.businessId);
  }

  handleBusinessSelectFromDetail(event) {
    this.navigateToDetail(event.detail && event.detail.businessId);
  }

  navigateToDetail(recordId) {
    if (!recordId) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: "business_detail__c" },
      state: { recordId }
    });
  }

  handleListBusiness() {
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: "create_business__c" }
    });
  }

  handleCancelListingForm() {
    this.showBusinessListingForm = false;
  }

  handleSubmitListingForm(event) {
    const payload = event.detail || {};

    const req = {
      businessName: payload.businessName,
      businessType: payload.businessType,
      phone: payload.phone,
      hidePhone: payload.hidePhone,
      email: payload.email,
      hideEmail: payload.hideEmail,
      website: payload.website,
      address: payload.address,
      mapUrl: payload.mapUrl,
      description: payload.description,
      coverPictureName: payload.coverPictureName,
      coverPictureBase64: payload.coverPictureBase64,
      logoName: payload.logoName,
      logoBase64: payload.logoBase64
    };

    const form = this.template.querySelector("c-ken-business-listing-form");
    createBusiness({ req, constituentRoleId: this._roleId })
      .then(() => this.refreshLists())
      .then(() => {
        if (form) {
          form.confirmSaved();
        } else {
          this.showBusinessListingForm = false;
        }
      })
      .catch(() => {
        if (form) form.resetSave();
      });
  }

  handleListingClose() {
    this.showBusinessListingForm = false;
  }

  handleMyBusinessClick(event) {
    this.navigateToDetail(event.detail.businessId);
  }

  refreshLists() {
    return Promise.all([
      getAllBusinesses({ constituentRoleId: this._roleId })
        .then((data) => {
          this.businesses = data || [];
        })
        .catch(() => {
          this.businesses = [];
        }),
      getMyBusinesses({ constituentRoleId: this._roleId })
        .then((data) => {
          this.myBusinesses = data || [];
        })
        .catch(() => {
          this.myBusinesses = [];
        })
    ]);
  }
}