import { LightningElement, api } from "lwc";

export default class AudienceFilterRow extends LightningElement {
  @api row;
  @api index;
  @api fieldOptions = [];
  @api operatorOptions = [];

  get rowNumber() {
    return (this.index ?? 0) + 1;
  }

  get placeholder() {
    const op = (this.row?.operator || "").toLowerCase();
    if (op === "in" || op === "includes" || op === "excludes") return "Example: A,B,C";
    return "Enter value";
  }

  get isPicklist() {
    return this.row?.dataType?.toLowerCase?.() === "picklist" && (this.row?.picklistValues || []).length > 0;
  }

  get isBoolean() {
    return this.row?.dataType?.toLowerCase?.() === "boolean";
  }

  get booleanValue() {
    return String(this.row?.value).toLowerCase() === "true";
  }

  get isDate() {
    return this.row?.dataType?.toLowerCase?.() === "date";
  }

  get isDateTime() {
    return this.row?.dataType?.toLowerCase?.() === "datetime";
  }

  get inputType() {
    const t = this.row?.dataType?.toLowerCase?.() || "text";
    if (t === "integer" || t === "number" || t === "currency" || t === "percent") return "number";
    if (t === "date") return "date";
    if (t === "datetime") return "datetime";
    return "text";
  }

  emit(row) {
    this.dispatchEvent(
      new CustomEvent("rowchange", {
        detail: { row },
        bubbles: true,
        composed: true
      })
    );
  }

  onFieldChange = (e) => this.emit({ ...this.row, fieldApi: e.detail.value });
  onOperatorChange = (e) => this.emit({ ...this.row, operator: e.detail.value });
  onValueChange = (e) => this.emit({ ...this.row, value: e.target.value });
  onPicklistChange = (e) => this.emit({ ...this.row, value: e.detail.value });
  onBooleanChange = (e) => this.emit({ ...this.row, value: e.target.checked ? "true" : "false" });

  onRemove = () => {
    this.dispatchEvent(
      new CustomEvent("remove", {
        detail: { id: this.row.id },
        bubbles: true,
        composed: true
      })
    );
  };
}