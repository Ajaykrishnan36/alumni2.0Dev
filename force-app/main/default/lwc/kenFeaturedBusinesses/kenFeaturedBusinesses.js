import { LightningElement, track } from "lwc";
import getFeaturedBusinesses from "@salesforce/apex/KenBusinessController.getFeaturedBusinesses";
import defaultBusinessImage from "@salesforce/resourceUrl/AlumniAlt";

export default class KenFeaturedBusinesses extends LightningElement {
  @track featured = [];
  @track activeIndex = 0;

  connectedCallback() {
    getFeaturedBusinesses()
      .then((data) => {
        this.featured = (data || []).map((b) => ({
          ...b,
          logo: b.logo || defaultBusinessImage,
          ownerImage: b.ownerImage || defaultBusinessImage
        }));
        this.activeIndex = 0;
      })
      .catch(() => {
        this.featured = [];
      });
  }

  get hasFeatured() {
    return this.featured && this.featured.length > 0;
  }

  get hasMultiple() {
    return this.featured && this.featured.length > 1;
  }

  get current() {
    return this.hasFeatured ? this.featured[this.activeIndex] : null;
  }

  get currentHasLocation() {
    return !!(this.current && this.current.location);
  }

  get dots() {
    return (this.featured || []).map((b, i) => ({
      key: b.id,
      className: i === this.activeIndex ? "dot dot-active" : "dot"
    }));
  }

  handlePrev() {
    if (!this.hasFeatured) return;
    const n = this.featured.length;
    this.activeIndex = (this.activeIndex - 1 + n) % n;
  }

  handleNext() {
    if (!this.hasFeatured) return;
    const n = this.featured.length;
    this.activeIndex = (this.activeIndex + 1) % n;
  }

  handleImageError(event) {
    if (event && event.target) {
      event.target.src = defaultBusinessImage;
    }
  }

  handleView() {
    const b = this.current;
    if (b) {
      this.dispatchEvent(
        new CustomEvent("businessselect", {
          detail: { businessId: b.id },
          bubbles: true,
          composed: true
        })
      );
    }
  }
}