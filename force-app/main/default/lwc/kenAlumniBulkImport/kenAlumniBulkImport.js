import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import { getPortalConfigs } from "c/kenThemeConfig";
import getSessionStatus from "@salesforce/apex/KenAlumniBulkImportController.getSessionStatus";
import getLatestImportSession from "@salesforce/apex/KenAlumniBulkImportController.getLatestImportSession";
import getImportErrors from "@salesforce/apex/KenAlumniBulkImportController.getImportErrors";
import createImportSession from "@salesforce/apex/KenAlumniBulkImportController.createImportSession";
import saveImportChunk from "@salesforce/apex/KenAlumniBulkImportController.saveImportChunk";
import startChunkedImport from "@salesforce/apex/KenAlumniBulkImportController.startChunkedImport";

const IMPORT_CHUNK_SIZE = 1000;
const STORAGE_KEY = "kenAlumniBulkImport.activeJob";
const BOM = String.fromCharCode(0xfeff);
const RUNNING = ["Holding", "Queued", "Preparing", "Processing"];
// A chained import briefly shows "Stalled" between one batch job finishing and
// the next starting; only treat the session as finished after this many
// consecutive stalled polls so failed rows are never revealed mid-import.
const STALLED_POLL_GRACE = 5;

export default class KenAlumniBulkImport extends LightningElement {
  file;
  rows = [];
  headers = [
    "Registration Number",
    "First Name",
    "Last Name",
    "Email",
    "Phone",
    "Program",
    "Status",
    "Year of Enrollment",
    "Year of Graduation",
    "Current Company",
    "Current Location",
    "Industry",
    "Specialization",
    // --- Personal & contact (Person Account) ---
    "Date of Birth",
    "Nationality",
    "Gender",
    "Blood Group",
    "LinkedIn URL",
    "Languages Known",
    "Address Street",
    "Address City",
    "Address State",
    "Address Postal Code",
    "Address Country",
    // --- Current employment (PersonEmployment) ---
    "Current Designation",
    "Employment Start Date",
    // --- Education: Class 10 (PersonEducation) ---
    "10th School",
    "10th Grade",
    "10th Grade Type",
    "10th Year",
    // --- Education: Class 12 (PersonEducation) ---
    "12th School",
    "12th Grade",
    "12th Grade Type",
    "12th Year",
    // --- Education: Bachelors (PersonEducation) ---
    "Bachelors Institute",
    "Bachelors Degree",
    "Bachelors Grade",
    "Bachelors Grade Type",
    "Bachelors Year",
    // --- Education: Masters (PersonEducation) ---
    "Masters Institute",
    "Masters Degree",
    "Masters Grade",
    "Masters Grade Type",
    "Masters Year",
  ];
  requiredHeaders = ["First Name", "Last Name", "Email", "Program", "Status", "Year of Graduation"];

  dataSourceOptions = [
    { label: "Historic Records", value: "Historic Import" },
    { label: "Old Portal Migration", value: "Portal Migration" },
  ];
  selectedDataSource = "Historic Import";

  parsedHeaders = [];
  sessionKey;
  jobStatus = "";
  totalRecords = 0;
  jobProcessed = 0;
  jobTotal = 0;
  jobErrors = 0;
  jobCompleted = false;
  stalledPolls = 0;
  isImporting = false;
  processedSuccess = 0;
  failedRowIndexes = [];
  failedRowErrors = {};
  unmatchedErrors = [];
  pollHandle;
  previewScrollHandle;
  showHelpModal = false;

  searchTerm = "";
  sortField = null;
  sortDirection = "asc";
  pageSize = 10;
  currentPage = 1;
  previewVisible = false;

  headerAliases = {
    "Registration Number": ["Registration Number", "Reg No", "Roll Number", "Roll No", "Registration No"],
    "First Name": ["First Name", "Firstname", "Given Name"],
    "Last Name": ["Last Name", "Lastname", "Surname"],
    Email: ["Email", "Email Address", "Email Id"],
    Phone: ["Phone", "Mobile", "Contact Number", "Phone Number"],
    Program: ["Program", "Programme", "Course", "Program Plan", "Program Name"],
    Status: ["Status", "Registration Status", "Constituent Status", "Registration Stage"],
    "Year of Enrollment": ["Year of Enrollment", "Enrollment Year", "Intake", "Intake Year", "Year of Joining", "Joining Year", "Admission Year"],
    "Year of Graduation": ["Year of Graduation", "Graduation Year", "Batch", "Passing Year"],
    "Current Company": ["Current Company", "Company", "Employer"],
    "Current Location": ["Current Location", "Location", "City"],
    Industry: ["Industry"],
    Specialization: ["Specialization", "Specialisation", "Major"],
    // --- Personal & contact ---
    "Date of Birth": ["Date of Birth", "DOB", "Birth Date", "Birthdate"],
    Nationality: ["Nationality", "Citizenship"],
    Gender: ["Gender", "Gender Identity", "Sex"],
    "Blood Group": ["Blood Group", "Blood Type", "Bloodgroup"],
    "LinkedIn URL": ["LinkedIn URL", "LinkedIn", "Linkedin Profile", "LinkedIn Profile URL", "Linkedin Url"],
    "Languages Known": ["Languages Known", "Languages", "Known Languages"],
    "Address Street": ["Address Street", "Street", "Address Line 1", "Address"],
    "Address City": ["Address City"],
    "Address State": ["Address State", "State", "Province"],
    "Address Postal Code": ["Address Postal Code", "Postal Code", "Pincode", "Pin Code", "Zip", "Zip Code"],
    "Address Country": ["Address Country", "Country"],
    // --- Current employment ---
    "Current Designation": ["Current Designation", "Designation", "Job Title", "Current Role", "Title"],
    "Employment Start Date": ["Employment Start Date", "Job Start Date", "Work Start Date"],
    // --- Education: Class 10 ---
    "10th School": ["10th School", "10th Institute", "Class X School", "SSC School", "10th Institution"],
    "10th Grade": ["10th Grade", "10th Marks", "Class X Grade", "SSC Grade"],
    "10th Grade Type": ["10th Grade Type", "Class X Grade Type"],
    "10th Year": ["10th Year", "10th Year of Completion", "Class X Year", "10th Passing Year"],
    // --- Education: Class 12 ---
    "12th School": ["12th School", "12th Institute", "Class XII School", "HSC School", "12th Institution"],
    "12th Grade": ["12th Grade", "12th Marks", "Class XII Grade", "HSC Grade"],
    "12th Grade Type": ["12th Grade Type", "Class XII Grade Type"],
    "12th Year": ["12th Year", "12th Year of Completion", "Class XII Year", "12th Passing Year"],
    // --- Education: Bachelors ---
    "Bachelors Institute": ["Bachelors Institute", "Bachelor Institute", "UG Institute", "Bachelors College", "Undergraduate Institute"],
    "Bachelors Degree": ["Bachelors Degree", "Bachelor Degree", "UG Degree", "Undergraduate Degree"],
    "Bachelors Grade": ["Bachelors Grade", "Bachelor Grade", "UG Grade"],
    "Bachelors Grade Type": ["Bachelors Grade Type", "Bachelor Grade Type", "UG Grade Type"],
    "Bachelors Year": ["Bachelors Year", "Bachelor Year", "UG Year", "Bachelors Year of Completion"],
    // --- Education: Masters ---
    "Masters Institute": ["Masters Institute", "Master Institute", "PG Institute", "Masters College", "Postgraduate Institute"],
    "Masters Degree": ["Masters Degree", "Master Degree", "PG Degree", "Postgraduate Degree"],
    "Masters Grade": ["Masters Grade", "Master Grade", "PG Grade"],
    "Masters Grade Type": ["Masters Grade Type", "Master Grade Type", "PG Grade Type"],
    "Masters Year": ["Masters Year", "Master Year", "PG Year", "Masters Year of Completion"],
  };

  connectedCallback() {
    getPortalConfigs().then((configs) => {
      if (configs && configs.primaryColor) {
        this.template.host.style.setProperty("--ci-accent", configs.primaryColor);
        this.template.host.style.setProperty("--ci-accent-strong", configs.primaryColor);
      }
    }).catch(() => {});
    this.resumeActiveJob();
  }

  disconnectedCallback() {
    window.clearInterval(this.pollHandle);
    window.clearTimeout(this.previewScrollHandle);
  }

  // --------------------------------------------------------------------
  // Progress persistence (survives tab close / reopen)
  // --------------------------------------------------------------------
  async resumeActiveJob() {
    const saved = this.loadState();
    if (saved && saved.sessionKey) {
      this.sessionKey = saved.sessionKey;
      this.totalRecords = saved.totalRecords || 0;
      this.rows = Array.isArray(saved.rows) ? saved.rows : [];
      this.selectedDataSource = saved.dataSource || this.selectedDataSource;
      this.isImporting = true;
      this.jobStatus = "Reconnecting...";
      this.refreshSession();
      return;
    }
    // No local record — ask the server if a session is still running for this user.
    try {
      const info = await getLatestImportSession();
      if (info && info.sessionKey && info.isRunning) {
        this.sessionKey = info.sessionKey;
        this.totalRecords = info.total || 0;
        this.isImporting = true;
        this.applyStatus(info);
        this.startPolling();
      }
    } catch (error) {
      // ignore — nothing to resume
    }
  }

  refreshSession() {
    getSessionStatus({ sessionKey: this.sessionKey })
      .then((info) => {
        if (!info) {
          this.clearState();
          this.resetStatusState();
          return;
        }
        this.applyStatus(info);
        if (info.status === "Completed") {
          this.handleJobComplete();
        } else {
          this.startPolling();
        }
      })
      .catch(() => {
        this.clearState();
        this.resetStatusState();
      });
  }

  applyStatus(info) {
    this.jobStatus = info.status;
    this.jobProcessed = info.processed;
    this.jobTotal = info.total;
    this.jobErrors = info.errors;
  }

  persistState() {
    const base = {
      sessionKey: this.sessionKey,
      totalRecords: this.totalRecords,
      dataSource: this.selectedDataSource,
    };
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...base, rows: this.rows }));
    } catch (error) {
      // Very large files exceed the localStorage quota — keep the session key
      // so progress survives reload, even if the failed-row export loses row data.
      try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(base));
      } catch (ignored) {
        // localStorage unavailable — progress simply won't survive reload.
      }
    }
  }

  loadState() {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (error) {
      return null;
    }
  }

  clearState() {
    try {
      window.localStorage.removeItem(STORAGE_KEY);
    } catch (error) {
      // ignore
    }
  }

  // --------------------------------------------------------------------
  // Getters
  // --------------------------------------------------------------------
  get fileName() {
    return this.file ? this.file.name : "No file chosen";
  }

  get hasFile() {
    return !!this.file;
  }

  get showPreview() {
    return this.hasFile && this.rows.length > 0 && this.previewVisible;
  }

  get pageSizeValue() {
    return String(this.pageSize);
  }

  get importDisabled() {
    return !this.selectedDataSource || !this.rows.length || this.isImporting;
  }

  get showStatus() {
    return this.isImporting || !!this.sessionKey;
  }

  get failedCount() {
    return this.failedRowIndexes.length + this.unmatchedErrors.length;
  }

  // The skipped count is intentionally omitted while jobs are still running —
  // failed rows are only revealed in bulk once every chained batch completes.
  get statusLine() {
    const base = `Status: ${this.jobStatus} - Processed ${this.processedDisplay}/${this.totalRecords}`;
    return this.jobCompleted ? `${base} - Skipped ${this.failedCount}` : base;
  }

  get failedDownloadDisabled() {
    return this.failedCount === 0;
  }

  get hasFailures() {
    return this.jobCompleted && this.failedCount > 0;
  }

  get failureList() {
    const list = [];
    for (const index of this.failedRowIndexes) {
      list.push({
        key: `f-${index}`,
        rowLabel: String(index + 1),
        message: this.failedRowErrors[index] || "",
      });
    }
    let counter = 0;
    for (const message of this.unmatchedErrors) {
      list.push({ key: `u-${counter++}`, rowLabel: "-", message });
    }
    return list;
  }

  get processedDisplay() {
    if (this.jobCompleted) {
      return this.processedSuccess;
    }
    if (this.jobTotal > 0 && this.totalRecords > 0) {
      return Math.min(Math.floor((this.jobProcessed / this.jobTotal) * this.totalRecords), this.totalRecords);
    }
    return 0;
  }

  get requiredHeaderSet() {
    return new Set((this.requiredHeaders || []).map((header) => this.normalize(header)));
  }

  // Appends " *" to required column names — used for the downloaded template's header row.
  decorateRequired(header) {
    return this.requiredHeaderSet.has(this.normalize(header)) ? `${header} *` : header;
  }

  get helpExampleHeaders() {
    const required = this.requiredHeaderSet;
    return this.headers.map((header, index) => ({
      key: `alumni-help-h-${index}`,
      label: header,
      required: required.has(this.normalize(header)),
    }));
  }

  get helpExampleRow() {
    const sample = this.sampleRow();
    return this.headers.map((header, index) => ({
      key: `alumni-help-${index}`,
      value: sample[header] || "",
    }));
  }

  get filteredRows() {
    const term = (this.searchTerm || "").trim().toLowerCase();
    if (!term) return this.rows || [];
    return (this.rows || []).filter((row) => {
      for (const key in row) {
        if (!Object.prototype.hasOwnProperty.call(row, key)) continue;
        const value = row[key];
        if (value != null && String(value).toLowerCase().includes(term)) {
          return true;
        }
      }
      return false;
    });
  }

  get sortedRows() {
    const rows = this.filteredRows.slice();
    if (!this.sortField) return rows;
    const direction = this.sortDirection === "asc" ? 1 : -1;
    rows.sort((left, right) => {
      const leftValue = left && left[this.sortField] != null ? String(left[this.sortField]) : "";
      const rightValue = right && right[this.sortField] != null ? String(right[this.sortField]) : "";
      if (leftValue === rightValue) return 0;
      return leftValue < rightValue ? -1 * direction : 1 * direction;
    });
    return rows;
  }

  get totalPages() {
    const length = this.sortedRows.length || 0;
    if (this.pageSize >= length) return 1;
    return Math.max(1, Math.ceil(length / this.pageSize));
  }

  get displayedRows() {
    const start = (this.currentPage - 1) * this.pageSize;
    if (this.pageSize >= this.sortedRows.length) return this.sortedRows;
    return this.sortedRows.slice(start, start + this.pageSize);
  }

  get previewHeaders() {
    return [{ label: "#", field: "#" }].concat((this.headers || []).map((header) => ({ label: header, field: header })));
  }

  get previewRowValues() {
    const headers = this.previewHeaders;
    const baseIndex = (this.currentPage - 1) * this.pageSize;
    return (this.displayedRows || []).map((row, rowIndex) => ({
      rowKey: `row-${baseIndex + rowIndex}`,
      cells: headers.map((header, columnIndex) => {
        if (columnIndex === 0) {
          return {
            key: `cell-${baseIndex + rowIndex}-${columnIndex}`,
            value: String(baseIndex + rowIndex + 1),
          };
        }
        return {
          key: `cell-${baseIndex + rowIndex}-${columnIndex}`,
          value: row && row[header.field] != null ? row[header.field] : "",
        };
      }),
    }));
  }

  get sortActive() {
    return !!this.sortField;
  }

  get sortStatusText() {
    if (!this.sortField) return "";
    return `${this.sortField} (${this.sortDirection === "asc" ? "A-Z" : "Z-A"})`;
  }

  get prevDisabled() {
    return this.currentPage <= 1;
  }

  get nextDisabled() {
    return this.currentPage >= this.totalPages;
  }

  // --------------------------------------------------------------------
  // File handling
  // --------------------------------------------------------------------
  handleDataSourceChange(event) {
    this.selectedDataSource = event.detail.value;
  }

  handleFileChange(event) {
    const file = event.target.files[0];
    if (!file) return;
    if (!/\.csv$/i.test(file.name || "")) {
      this.resetFileState();
      event.target.value = null;
      this.showToast("Invalid file", "Please upload a CSV file.", "error");
      return;
    }

    this.file = file;
    const reader = new FileReader();
    reader.onload = () => {
      const parsedRows = this.parseCsv(reader.result);
      const missing = this.missingRequiredHeaders();
      if (missing.length) {
        this.resetFileState();
        event.target.value = null;
        this.showToast("Missing columns", `Your file is missing required column(s): ${missing.join(", ")}. Download the template for the exact headers.`, "error");
        return;
      }
      this.rows = parsedRows;
      this.searchTerm = "";
      this.sortField = null;
      this.sortDirection = "asc";
      this.pageSize = 10;
      this.currentPage = 1;
      this.previewVisible = true;
      this.scrollPreviewIntoView();
    };
    reader.readAsText(file);
  }

  handleDeleteFile() {
    this.resetFileState();
  }

  handleSearchChange(event) {
    this.searchTerm = event.target.value || "";
    this.currentPage = 1;
  }

  handlePageSizeChange(event) {
    const nextValue = parseInt(event.target.value, 10);
    this.pageSize = Number.isNaN(nextValue) ? 10 : nextValue;
    this.currentPage = 1;
  }

  handlePrevPage() {
    if (this.currentPage > 1) {
      this.currentPage -= 1;
    }
  }

  handleNextPage() {
    if (this.currentPage < this.totalPages) {
      this.currentPage += 1;
    }
  }

  handleSort(event) {
    const field = event.currentTarget.dataset.field;
    if (!field || field === "#") return;
    if (this.sortField === field) {
      this.sortDirection = this.sortDirection === "asc" ? "desc" : "asc";
    } else {
      this.sortField = field;
      this.sortDirection = "asc";
    }
    this.currentPage = 1;
  }

  // --------------------------------------------------------------------
  // Import
  // --------------------------------------------------------------------
  async handleImport() {
    if (this.importDisabled) return;

    const confirmed = await LightningConfirm.open({
      label: "Confirm import",
      message: `Start importing ${this.rows.length} alumni record${this.rows.length === 1 ? "" : "s"}?`,
      theme: "warning",
    });
    if (!confirmed) return;

    this.failedRowIndexes = [];
    this.failedRowErrors = {};
    this.unmatchedErrors = [];
    this.jobCompleted = false;
    this.processedSuccess = 0;
    this.sessionKey = null;
    this.jobProcessed = 0;
    this.jobTotal = 0;
    this.jobErrors = 0;

    this.totalRecords = this.rows.length;
    this.isImporting = true;
    this.jobStatus = "Preparing...";
    this.showToast("Import started", `Preparing ${this.totalRecords} row${this.totalRecords === 1 ? "" : "s"} for import.`, "info");

    try {
      const sessionKey = await createImportSession();
      const rowChunks = this.chunkRows(this.rows, IMPORT_CHUNK_SIZE);
      for (let index = 0; index < rowChunks.length; index += 1) {
        await saveImportChunk({
          sessionKey,
          chunkIndex: index,
          chunkJson: JSON.stringify(rowChunks[index]),
        });
        this.jobStatus = `Uploading ${index + 1}/${rowChunks.length}`;
      }

      await startChunkedImport({
        sessionKey,
        dataSource: this.selectedDataSource,
        totalRows: this.totalRecords,
      });

      this.sessionKey = sessionKey;
      this.jobStatus = "Queued";
      this.persistState();
      this.startPolling();
      this.showToast("Import queued", "Alumni import is now running in the background. You can leave this page — progress will resume when you return.", "success");
    } catch (error) {
      this.isImporting = false;
      this.jobStatus = "";
      this.clearState();
      this.showToast("Import failed", this.reduceError(error), "error");
    }
  }

  chunkRows(rows, chunkSize) {
    const chunks = [];
    for (let index = 0; index < rows.length; index += chunkSize) {
      chunks.push(rows.slice(index, index + chunkSize));
    }
    return chunks;
  }

  startPolling() {
    window.clearInterval(this.pollHandle);
    this.stalledPolls = 0;
    this.pollHandle = window.setInterval(() => {
      getSessionStatus({ sessionKey: this.sessionKey })
        .then((info) => {
          if (!info) return;
          this.applyStatus(info);
          if (info.isRunning) {
            this.stalledPolls = 0;
            return;
          }
          if (info.status === "Stalled" && this.stalledPolls < STALLED_POLL_GRACE) {
            this.stalledPolls += 1;
            return;
          }
          window.clearInterval(this.pollHandle);
          this.pollHandle = null;
          this.handleJobComplete();
        })
        .catch(() => {});
    }, 2000);
  }

  handleJobComplete() {
    getImportErrors({ sessionKey: this.sessionKey })
      .then((errors) => {
        const messages = errors || [];
        const rowIndexes = new Set();
        const rowErrors = {};
        const unmatched = [];
        for (const message of messages) {
          const match = /Row\s+(\d+)/i.exec(message || "");
          if (match) {
            const rowIndex = parseInt(match[1], 10) - 1;
            rowIndexes.add(rowIndex);
            rowErrors[rowIndex] = rowErrors[rowIndex] ? `${rowErrors[rowIndex]} | ${message}` : message;
          } else {
            unmatched.push(message);
          }
        }
        this.failedRowIndexes = Array.from(rowIndexes).sort((a, b) => a - b);
        this.failedRowErrors = rowErrors;
        this.unmatchedErrors = unmatched;
        this.jobCompleted = true;
        this.isImporting = false;
        this.processedSuccess = Math.max(this.totalRecords - this.failedRowIndexes.length, 0);
        const failed = this.failedCount;
        if (failed > 0) {
          this.showToast(
            "Import finished",
            `${this.processedSuccess} imported, ${failed} skipped. Review the failed rows below or download them.`,
            "warning",
          );
        } else {
          this.showToast("Import completed", "All records imported successfully.", "success");
        }
      })
      .catch((error) => {
        this.isImporting = false;
        this.jobCompleted = true;
        this.showToast("Import finished", this.reduceError(error), "warning");
      });
  }

  handleDismissResults() {
    this.clearState();
    this.resetStatusState();
  }

  // --------------------------------------------------------------------
  // Help + downloads
  // --------------------------------------------------------------------
  handleOpenHelp() {
    this.showHelpModal = true;
  }

  handleCloseHelp() {
    this.showHelpModal = false;
  }

  sampleRow() {
    return {
      "Registration Number": "2018CSE0123",
      "First Name": "Asha",
      "Last Name": "Rao",
      Email: "asha.rao@example.com",
      Phone: "9876543210",
      Program: "",
      Status: "Registered",
      "Year of Enrollment": "2014",
      "Year of Graduation": "2018",
      "Current Company": "Acme Corp",
      "Current Location": "Bangalore",
      Industry: "Technology",
      Specialization: "",
      "Date of Birth": "12/04/1996",
      Nationality: "Indian",
      Gender: "",
      "Blood Group": "O+",
      "LinkedIn URL": "https://www.linkedin.com/in/asha-rao",
      "Languages Known": "English, Hindi, Kannada",
      "Address Street": "12 MG Road",
      "Address City": "Bangalore",
      "Address State": "Karnataka",
      "Address Postal Code": "560001",
      "Address Country": "India",
      "Current Designation": "Senior Software Engineer",
      "Employment Start Date": "01/06/2021",
      "10th School": "St. Joseph's High School",
      "10th Grade": "92",
      "10th Grade Type": "Percentage",
      "10th Year": "2012",
      "12th School": "St. Joseph's PU College",
      "12th Grade": "88",
      "12th Grade Type": "Percentage",
      "12th Year": "2014",
      "Bachelors Institute": "RV College of Engineering",
      "Bachelors Degree": "B.E. Computer Science",
      "Bachelors Grade": "8.4",
      "Bachelors Grade Type": "CGPA",
      "Bachelors Year": "2018",
      "Masters Institute": "",
      "Masters Degree": "",
      "Masters Grade": "",
      "Masters Grade Type": "",
      "Masters Year": "",
    };
  }

  handleDownloadTemplate() {
    try {
      const sample = this.sampleRow();
      const content = [
        this.headers.map((header) => this.decorateRequired(header)).join(","),
        this.headers.map((header) => this.csvCell(sample[header] || "")).join(","),
      ].join("\n");
      this.downloadCsv(BOM + content, "alumni_import_template.csv");
    } catch (error) {
      this.showToast("Download failed", this.reduceError(error), "error");
    }
  }

  handleDownloadFailed() {
    try {
      const headers = this.headers.concat(["ErrorMessage"]);
      const lines = [headers.join(",")];
      for (const index of this.failedRowIndexes) {
        const row = this.rows[index] || {};
        const cells = this.headers.map((header) => this.csvCell(row[header] || ""));
        cells.push(this.csvCell(this.failedRowErrors[index] || ""));
        lines.push(cells.join(","));
      }
      for (const message of this.unmatchedErrors) {
        lines.push([new Array(this.headers.length).fill("").join(","), this.csvCell(message)].join(","));
      }
      this.downloadCsv(BOM + lines.join("\n"), "alumni_import_failed_rows.csv");
    } catch (error) {
      this.showToast("Download failed", this.reduceError(error), "error");
    }
  }

  // --------------------------------------------------------------------
  // CSV parsing / writing
  // --------------------------------------------------------------------
  parseCsv(text) {
    const rows = this.readCsvRows(text);
    if (!rows.length) return [];
    this.parsedHeaders = (rows[0] || []).map((header) => String(header || "").trim());
    const canonicalHeaders = this.parsedHeaders.map((header) => this.toCanonicalHeader(header));
    return rows.slice(1).map((cells, index) => {
      const row = { RowNumber: String(index + 1) };
      canonicalHeaders.forEach((header, cellIndex) => {
        row[header] = cells[cellIndex] != null ? String(cells[cellIndex]).trim() : "";
      });
      return row;
    });
  }

  readCsvRows(text) {
    const input = String(text || "").replace(new RegExp(`^${BOM}`), "");
    const rows = [];
    let row = [];
    let cell = "";
    let inQuotes = false;

    for (let i = 0; i < input.length; i++) {
      const character = input[i];
      if (character === "\"") {
        if (inQuotes && input[i + 1] === "\"") {
          cell += "\"";
          i += 1;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }
      if (character === "," && !inQuotes) {
        row.push(cell);
        cell = "";
        continue;
      }
      if ((character === "\n" || character === "\r") && !inQuotes) {
        row.push(cell);
        rows.push(row);
        row = [];
        cell = "";
        if (character === "\r" && input[i + 1] === "\n") {
          i += 1;
        }
        continue;
      }
      cell += character;
    }

    if (cell.length > 0 || row.length > 0) {
      row.push(cell);
      rows.push(row);
    }

    return rows.filter((line) => line.some((value) => String(value || "").trim().length > 0));
  }

  missingRequiredHeaders() {
    const canonical = (this.parsedHeaders || []).map((header) => this.toCanonicalHeader(header));
    const present = new Set(canonical.map((header) => this.normalize(header)));
    return this.requiredHeaders.filter((header) => !present.has(this.normalize(header)));
  }

  normalize(value) {
    // Strip the "required" asterisk (e.g. "Email *") so a downloaded template re-uploads cleanly.
    return String(value || "").trim().toLowerCase().replace(/\*/g, "").trim();
  }

  toCanonicalHeader(value) {
    const normalizedValue = this.normalize(value);
    for (const header of this.headers) {
      const aliases = this.headerAliases[header] || [header];
      if (aliases.some((alias) => this.normalize(alias) === normalizedValue)) {
        return header;
      }
    }
    return String(value || "").trim();
  }

  csvCell(value) {
    const text = String(value == null ? "" : value);
    return `"${text.replace(/"/g, "\"\"")}"`;
  }

  downloadCsv(content, fileName) {
    let url;
    try {
      const blob = new Blob([content], { type: "text/csv;charset=utf-8;" });
      url = URL.createObjectURL(blob);
      // Anchor must be in the DOM and visible for Safari to honour the download.
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = fileName;
      anchor.style.cssText = "position:fixed;top:-100px;left:-100px;opacity:0";
      document.body.appendChild(anchor);
      anchor.click();
      document.body.removeChild(anchor);
    } catch (error) {
      // Last-resort: data URI in a new tab (works on Safari when blob URL fails).
      const dataUri = `data:text/csv;charset=utf-8,${encodeURIComponent(content)}`;
      window.open(dataUri, "_blank");
    } finally {
      if (url) {
        window.setTimeout(() => URL.revokeObjectURL(url), 1500);
      }
    }
  }

  // --------------------------------------------------------------------
  // State reset
  // --------------------------------------------------------------------
  resetStatusState() {
    this.sessionKey = null;
    this.jobStatus = "";
    this.jobProcessed = 0;
    this.jobTotal = 0;
    this.jobErrors = 0;
    this.jobCompleted = false;
    this.isImporting = false;
    this.stalledPolls = 0;
    this.processedSuccess = 0;
    this.totalRecords = 0;
    this.failedRowIndexes = [];
    this.failedRowErrors = {};
    this.unmatchedErrors = [];
  }

  resetFileState() {
    this.file = null;
    this.rows = [];
    this.parsedHeaders = [];
    this.previewVisible = false;
    this.searchTerm = "";
    this.sortField = null;
    this.sortDirection = "asc";
    this.pageSize = 10;
    this.currentPage = 1;
    const fileInput = this.template.querySelector('input[type="file"]');
    if (fileInput) {
      fileInput.value = null;
    }
  }

  scrollPreviewIntoView() {
    window.clearTimeout(this.previewScrollHandle);
    this.previewScrollHandle = window.setTimeout(() => {
      const previewSection = this.template.querySelector("[data-preview-section]");
      if (previewSection) {
        previewSection.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }, 0);
  }

  reduceError(error) {
    if (error && error.body && error.body.message) return error.body.message;
    if (error && error.message) return error.message;
    return "Unknown error";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: variant === "error" ? "sticky" : "dismissable" }));
  }
}