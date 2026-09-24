import { LightningElement, api } from "lwc";
import { getPortalConfigs as getPrimaryColor } from "c/kenThemeConfig";
import defaultEducationLogo from "@salesforce/resourceUrl/AlumniAlt";
export default class KenEducationCard extends LightningElement {
  @api recordId;
  @api degree;
  @api institution;
  @api program;
  @api institutionType;
  @api duration;
  @api score;
  @api logo;
  @api isMyProfile = false;
  showDeleteConfirm = false;

  handleEdit() {
    this.dispatchEvent(
      new CustomEvent("edit", {
        detail: { id: this.recordId },
        bubbles: true
      })
    );
  }

  handleDelete() {
    this.showDeleteConfirm = true;
  }

  handleConfirmDelete() {
    this.showDeleteConfirm = false;
    this.dispatchEvent(
      new CustomEvent("delete", {
        detail: { id: this.recordId },
        bubbles: true
      })
    );
  }

  handleCancelDelete() {
    this.showDeleteConfirm = false;
  }

  get displayLogo() {
    return this.logo || defaultEducationLogo;
  }

  get metaLine() {
    const duration = (this.duration || "").trim();
    const score = (this.score || "").toString().trim();
    if (duration && score) return `${duration} | ${score}`;
    return duration || score || "";
  }

  // The admin 360 Academic Record table shows Program as its own column;
  // the portal card carried the value all along but never rendered it.
  get programLine() {
    return (this.program || "").trim();
  }

  get hasProgramLine() {
    return this.programLine !== "";
  }

  handleLogoError(event) {
    if (event && event.target) {
      event.target.style.display = "none";
    }
  }
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
      .catch(() => {
        console.log("Error getting primary color");
      });
  }
}