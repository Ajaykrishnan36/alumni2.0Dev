import { LightningElement, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import getTargetRoles from "@salesforce/apex/KenAudienceEngineService.getTargetRoles";
import getRoleContext from "@salesforce/apex/KenAudienceEngineService.getRoleContext";
import preview from "@salesforce/apex/KenAudienceEngineService.preview";
import saveSegmentation from "@salesforce/apex/KenAudienceEngineService.saveSegmentation";

const OPERATOR_SETS = {
  text: [
    { label: "=", value: "=" },
    { label: "!=", value: "!=" },
    { label: "contains", value: "contains" },
    { label: "startsWith", value: "startsWith" },
    { label: "in (comma-separated)", value: "in" }
  ],
  number: [
    { label: "=", value: "=" },
    { label: "!=", value: "!=" },
    { label: ">", value: ">" },
    { label: ">=", value: ">=" },
    { label: "<", value: "<" },
    { label: "<=", value: "<=" },
    { label: "in (comma-separated)", value: "in" }
  ],
  date: [
    { label: "=", value: "=" },
    { label: "!=", value: "!=" },
    { label: ">", value: ">" },
    { label: ">=", value: ">=" },
    { label: "<", value: "<" },
    { label: "<=", value: "<=" }
  ],
  boolean: [
    { label: "=", value: "=" },
    { label: "!=", value: "!=" }
  ],
  picklist: [
    { label: "=", value: "=" },
    { label: "!=", value: "!=" }
  ],
  multipicklist: [
    { label: "includes (comma-separated)", value: "includes" },
    { label: "excludes (comma-separated)", value: "excludes" }
  ]
};

export default class KenAudienceBuilder extends LightningElement {
  // header
  audienceName = "";
  description = "";
  targetRole = "";
  active = true;

  // match
  matchMode = "AND";
  customLogic = "";

  // loading
  loadingFields = false;
  loadingPreview = false;

  // role context
  categories = [];
  categoryCount = 0;
  targetObject = "Account";
  fieldSetName = "";
  personAccountsOnly = true;

  // field catalog
  fieldOptions = [];
  fieldMetaByApi = new Map();

  // filters
  @track filters = [];

  // preview
  previewCount = 0;
  previewRows = [];
  previewPills = [];
  previewColumns = [
    { label: "Name", fieldName: "name" },
    { label: "Email", fieldName: "email" }
  ];

  // roles
  targetRoleOptions = [];

  @wire(getTargetRoles)
  wiredRoles({ data, error }) {
    if (data) {
      this.targetRoleOptions = data.map((o) => ({ label: o.label, value: o.value }));
    } else if (error) {
      this.toast("Error loading roles", this.reduceError(error), "error");
    }
  }

  // UI helpers
  get operatorOptions() { return OPERATOR_SETS.text; }
  get andVariant() { return this.matchMode === "AND" ? "brand" : "neutral"; }
  get orVariant() { return this.matchMode === "OR" ? "brand" : "neutral"; }
  get customVariant() { return this.matchMode === "CUSTOM" ? "brand" : "neutral"; }
  get isCustomMode() { return this.matchMode === "CUSTOM"; }

  get hasNoFields() { return !this.targetRole || this.fieldOptions.length === 0; }
  get disableAddFilter() { return this.hasNoFields; }
  get fieldSetLabel() { return this.fieldSetName || "AudienceFilters"; }

  get disablePreview() {
    if (!this.targetRole || this.filters.length === 0) return true;
    // require all rows to have required values
    return !this.filters.every((f) => f.fieldApi && f.operator && f.value);
  }

  get disableSave() { return !this.audienceName || !this.targetRole; }
  get hasPills() { return (this.previewPills || []).length > 0; }

  // header handlers
  onAudienceNameChange = (e) => (this.audienceName = e.target.value);
  onDescriptionChange = (e) => (this.description = e.target.value);
  onActiveChange = (e) => (this.active = e.target.checked);

  // match handlers
  onMatchModeClick(e) { this.matchMode = e.target.dataset.mode; }
  onCustomLogicChange = (e) => (this.customLogic = e.target.value);

  // role selection
  async onTargetRoleChange(e) {
    this.targetRole = e.detail.value;

    // reset on role change
    this.categories = [];
    this.categoryCount = 0;
    this.targetObject = "Account";
    this.fieldSetName = "";
    this.personAccountsOnly = true;
    this.fieldOptions = [];
    this.fieldMetaByApi = new Map();
    this.filters = [];

    this.previewCount = 0;
    this.previewRows = [];
    this.previewPills = [];

    await this.loadRoleContext();
  }

  async loadRoleContext() {
    if (!this.targetRole) return;

    this.loadingFields = true;
    try {
      const ctx = await getRoleContext({ targetRole: this.targetRole });

      this.categories = ctx?.categories || [];
      this.categoryCount = this.categories.length;
      this.targetObject = ctx?.targetObject || "Account";
      this.fieldSetName = ctx?.fieldSetName || "";
      this.personAccountsOnly = ctx?.personAccountsOnly ?? (this.targetObject === "Account");

      const fields = ctx?.fields || [];

      // Optional: show category name in label
      this.fieldOptions = fields.map((f) => ({
        label: f.categoryName ? `${f.label} (${f.categoryName})` : f.label,
        value: f.apiName
      }));

      this.fieldMetaByApi = new Map();
      fields.forEach((f) =>
        this.fieldMetaByApi.set(f.apiName, {
          dataType: f.dataType || "Text",
          picklistValues: f.picklistValues || []
        })
      );

      // nice UX: add one empty filter row if fields exist
      if (this.fieldOptions.length > 0) this.onAddFilter();
    } catch (err) {
      this.toast("Error loading fields", this.reduceError(err), "error");
    } finally {
      this.loadingFields = false;
    }
  }

  // filter CRUD
  onAddFilter() {
    const id = `row-${Date.now()}-${Math.random()}`;
    this.filters = [
      ...this.filters,
      {
        id,
        fieldApi: "",
        operator: "=",
        value: "",
        dataType: "Text",
        picklistValues: [],
        operatorOptions: this.getOperatorOptions("Text")
      }
    ];
  }

  onRemoveRow(event) {
    const id = event.detail.id;
    this.filters = this.filters.filter((f) => f.id !== id);
  }

  onRowChange(event) {
    const updated = { ...event.detail.row };

    if (updated.fieldApi) {
      const meta = this.fieldMetaByApi.get(updated.fieldApi);
      if (meta) {
        updated.dataType = meta.dataType;
        updated.picklistValues = meta.picklistValues || [];
      }
    }
    updated.operatorOptions = this.getOperatorOptions(updated.dataType);
    if (!updated.operatorOptions.find((o) => o.value === updated.operator)) {
      updated.operator = updated.operatorOptions[0]?.value || "=";
    }
    this.filters = this.filters.map((f) => (f.id === updated.id ? updated : f));
  }

  // preview
  async onPreview() {
    this.loadingPreview = true;
    try {
      const payload = this.buildPayload();
      const res = await preview({ requestJson: JSON.stringify(payload) });

      this.previewCount = res.count || 0;
      this.previewRows = res.sample || [];
      this.previewPills = res.pills || [];
    } catch (err) {
      this.toast("Preview failed", this.reduceError(err), "error");
    } finally {
      this.loadingPreview = false;
    }
  }

  // save
  async onSave() {
    try {
      const payload = this.buildPayload();
      const id = await saveSegmentation({ requestJson: JSON.stringify(payload) });
      this.toast("Saved", `Segmentation created: ${id}`, "success");
    } catch (err) {
      this.toast("Save failed", this.reduceError(err), "error");
    }
  }

  buildPayload() {
    return {
      audienceName: this.audienceName,
      description: this.description,
      targetRole: this.targetRole,
      active: this.active,
      targetObject: this.targetObject,
      personAccountsOnly: this.personAccountsOnly,
      matchMode: this.matchMode,
      customLogic: this.customLogic,
      filters: this.filters
    };
  }

  getOperatorOptions(dataType) {
    const key = String(dataType || "Text").toLowerCase();
    if (key === "boolean") return OPERATOR_SETS.boolean;
    if (key === "date" || key === "datetime") return OPERATOR_SETS.date;
    if (key === "integer" || key === "number" || key === "currency" || key === "percent") return OPERATOR_SETS.number;
    if (key === "picklist") return OPERATOR_SETS.picklist;
    if (key === "multipicklist") return OPERATOR_SETS.multipicklist;
    return OPERATOR_SETS.text;
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(err) {
    if (Array.isArray(err?.body)) return err.body.map((e) => e.message).join(", ");
    return err?.body?.message || err?.message || "Unknown error";
  }
}