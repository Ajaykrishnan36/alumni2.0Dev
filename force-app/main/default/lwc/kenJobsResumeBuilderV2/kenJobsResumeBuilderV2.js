import { LightningElement, api, track } from 'lwc';
import getResume from '@salesforce/apex/KenResumeController.getResume';
import saveResumeDraft from '@salesforce/apex/KenResumeController.saveResumeDraft';
import generatePdf from '@salesforce/apex/KenResumeController.generatePdf';

export default class KenJobsResumeBuilderV2 extends LightningElement {
    @api resumeId;          // set => edit mode

    @track step = 1;
    @track template = 'New York';
    @track name = '';
    @track fullName = '';
    @track headline = '';
    @track summary = '';
    @track email = '';
    @track phone = '';
    @track location = '';
    @track experiences = [];
    @track educations = [];
    @track skills = [];
    @track skillInput = '';
    @track errorMsg = '';
    @track saving = false;
    @track generating = false;
    @track done = false;
    @track downloadUrl = '';

    connectedCallback() {
        if (this.resumeId) this._load(this.resumeId);
    }

    _load(id) {
        getResume({ resumeId: id })
            .then(r => {
                this.name = r.name || ''; this.template = r.template || 'New York';
                this.fullName = r.fullName || ''; this.headline = r.headline || ''; this.summary = r.summary || '';
                this.email = r.email || ''; this.phone = r.phone || ''; this.location = r.location || '';
                this.experiences = this._parse(r.experienceJson).map(this._withKey);
                this.educations = this._parse(r.educationJson).map(this._withKey);
                this.skills = this._parse(r.skillsJson);
            })
            .catch(err => { this.errorMsg = (err && err.body && err.body.message) || 'Could not load resume.'; });
    }
    _parse(j) { try { return j ? JSON.parse(j) : []; } catch (e) { return []; } }
    _withKey(o, i) { return { key: 'k' + i + '_' + Date.now(), ...o }; }

    // ---- steps ----
    get isStep1() { return this.step === 1 && !this.done; }
    get isStep2() { return this.step === 2 && !this.done; }
    get isStep3() { return this.step === 3 && !this.done; }
    get step1cls() { return this.step === 1 ? 'on' : ''; }
    get step2cls() { return this.step === 2 ? 'on' : ''; }
    get step3cls() { return this.step === 3 ? 'on' : ''; }
    get nyCls() { return this.template === 'New York' ? 'tpl tpl--on' : 'tpl'; }
    get toCls() { return this.template === 'Toronto' ? 'tpl tpl--on' : 'tpl'; }
    get title() { return this.resumeId ? 'Edit Resume' : 'Build Resume'; }

    handleTemplate(e) { this.template = e.currentTarget.dataset.tpl; }
    handleField(e) { this[e.target.dataset.field] = e.target.value; }

    // ---- experience ----
    addExperience() { this.experiences = [...this.experiences, { key: 'e' + Date.now(), title: '', company: '', dates: '', description: '' }]; }
    handleExp(e) {
        const k = e.currentTarget.dataset.key, f = e.target.dataset.f, v = e.target.value;
        this.experiences = this.experiences.map(x => x.key === k ? { ...x, [f]: v } : x);
    }
    removeExp(e) { const k = e.currentTarget.dataset.key; this.experiences = this.experiences.filter(x => x.key !== k); }

    // ---- education ----
    addEducation() { this.educations = [...this.educations, { key: 'd' + Date.now(), degree: '', institution: '', dates: '' }]; }
    handleEdu(e) {
        const k = e.currentTarget.dataset.key, f = e.target.dataset.f, v = e.target.value;
        this.educations = this.educations.map(x => x.key === k ? { ...x, [f]: v } : x);
    }
    removeEdu(e) { const k = e.currentTarget.dataset.key; this.educations = this.educations.filter(x => x.key !== k); }

    // ---- skills (Set guard) ----
    handleSkillInput(e) { this.skillInput = e.target.value; }
    addSkill() {
        const v = (this.skillInput || '').trim();
        if (!v) return;
        if (this.skills.some(s => s.toLowerCase() === v.toLowerCase())) { this.skillInput = ''; return; }
        this.skills = [...this.skills, v];
        this.skillInput = '';
    }
    handleSkillKey(e) { if (e.key === 'Enter') { e.preventDefault(); this.addSkill(); } }
    removeSkill(e) { const v = e.currentTarget.dataset.skill; this.skills = this.skills.filter(s => s !== v); }

    // ---- nav ----
    next() {
        this.errorMsg = '';
        if (this.step === 2) {
            if (!this.fullName.trim()) { this.errorMsg = 'Please enter your full name.'; return; }
            if (!this.name.trim()) this.name = (this.fullName.trim() + ' Resume');
        }
        if (this.step < 3) this.step += 1;
    }
    back() { this.errorMsg = ''; if (this.step > 1) this.step -= 1; }
    close() { this.dispatchEvent(new CustomEvent('close')); }

    _buildInput() {
        const stripKey = (o) => { const { key, ...rest } = o; return rest; };
        return {
            id: this.resumeId || null,
            name: this.name || (this.fullName ? this.fullName + ' Resume' : 'My Resume'),
            template: this.template,
            fullName: this.fullName, headline: this.headline, summary: this.summary,
            email: this.email, phone: this.phone, location: this.location,
            experienceJson: JSON.stringify(this.experiences.map(stripKey)),
            educationJson: JSON.stringify(this.educations.map(stripKey)),
            skillsJson: JSON.stringify(this.skills),
            isDefault: false
        };
    }

    handleSaveDraft() {
        this.errorMsg = ''; this.saving = true;
        saveResumeDraft({ input: this._buildInput() })
            .then(id => { this.saving = false; this.resumeId = id; this.dispatchEvent(new CustomEvent('saved')); this.dispatchEvent(new CustomEvent('close')); })
            .catch(err => { this.saving = false; this.errorMsg = (err && err.body && err.body.message) || 'Could not save.'; });
    }

    handleGenerate() {
        this.errorMsg = ''; this.generating = true;
        saveResumeDraft({ input: this._buildInput() })
            .then(id => { this.resumeId = id; return generatePdf({ resumeId: id }); })
            .then(url => { this.generating = false; this.downloadUrl = url; this.done = true; this.dispatchEvent(new CustomEvent('saved')); })
            .catch(err => { this.generating = false; this.errorMsg = (err && err.body && err.body.message) || 'Could not generate the PDF.'; });
    }
    handleDone() { this.dispatchEvent(new CustomEvent('close')); }
}