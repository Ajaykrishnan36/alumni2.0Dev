/* eslint-disable camelcase,max-statements, prefer-destructuring, sort-vars, no-magic-numbers, one-var, max-lines,  sort-imports*/


import { LightningElement, api, track, wire } from 'lwc';

import getQuestionnaireWithQuestions from '@salesforce/apex/KenQuestionnaireControllerClass.getQuestionnaireWithQuestions';
import saveQuestionnaireWithRelatedRecord from '@salesforce/apex/KenQuestionnaireControllerClass.saveQuestionnaireWithQuestions';
import saveQuestionnaireWithQuestions from '@salesforce/apex/KenQuestionnaireControllerClass.saveQuestionnaireWithQuestions2';

import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';


const FIELDS = ['Id', 'Ken_Service_Offering__c.Target_Audience__c'],
      INDEX_OFFSET = 1,
      NAV_REFRESH_DELAY_MS = 100,
      ZERO = 0;



// eslint-disable-next-line new-cap
export default class KenQuestionnaireEditForm extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    questionnaireId;
    @track placeholder = '';

    @track questionnaire = { description: '', targetAudience: '', title: '' };

    @track selectedValues = '';

    @track parentOptions = [
        { checked: false, label: 'Alumni', show: true, value: 'Alumni' },
        { checked: false, label: 'Student', show: true, value: 'Student' },
        { checked: false, label: 'All', show: true, value: 'All' }
    ];

    @track questions = [];
    @track groupedQuestions = [];
    @track wiredRecordData;

    questionTypeOptions = [
        { label: 'Short Answer', value: 'Short Answer' },
        { label: 'Rating', value: 'Rating' },
        { label: 'Multiple Choice', value: 'Multiple Choice' },
        { label: 'Dropdown', value: 'Dropdown' },
        { label: 'Comment', value: 'Comment' },
        { label: 'Yes/No', value: 'Yes/No' },
        { label: 'File Upload', value: 'File Upload' },
        { label: 'Linear Scale', value: 'Linear Scale' },
        { label: 'Date', value: 'Date' },
        { label: 'Time', value: 'Time' }
    ];

    // Mapping options shown only for Date/Time type questions
    gatePassMappingOptions = [
        { label: '(None)', value: '' },
        { label: 'Exit Date → Exit_Time__c', value: 'Exit_Date' },
        { label: 'Exit Time → Exit_Time__c', value: 'Exit_Time' },
        { label: 'Entry Date → Entry_Time__c', value: 'Entry_Date' },
        { label: 'Entry Time → Entry_Time__c', value: 'Entry_Time' }
    ];

    showSpinner = false;

    @wire(getRecord, { fields: FIELDS, recordId: '$recordId' })
    wiredRecord(value) {
        this.wiredRecordData = value;
        const { data, error } = value;
        if (data) {
            this.objectApiName = data.apiName;
            if (this.objectApiName === 'Ken_Questionnaire__c') {
                this.fetchQuestionnaireWithQuestions();
            } else if (this.objectApiName === 'Ken_Service_Offering__c') {
                const offeringTargetAudience = data.fields && data.fields.Target_Audience__c
                    ? data.fields.Target_Audience__c.value
                    : '';
                if (offeringTargetAudience) {
                    this.questionnaire = { ...this.questionnaire, targetAudience: offeringTargetAudience };
                }
            }
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error retrieving object info: ', error);
        }
    }

    /* eslint-disable max-lines-per-function, max-statements */
    fetchQuestionnaireWithQuestions() {
        this.showSpinner = true;
        getQuestionnaireWithQuestions({ questionnaireId: this.recordId })
            .then(data => {
                if (data) {
                    this.questionnaire = {
                        description: data.Descripation__c,
                        targetAudience: data.Target_Audience__c,
                        title: data.Section_Name__c
                    };

                    this.placeholder = data.Target_Audience__c;
                    const targetAudience2 = data.Target_Audience__c.split(';');
                    this.parentOptions.forEach(option => {
                        if (targetAudience2.includes(option.value)) {
                            option.checked = true;
                        } else {
                            option.checked = false;
                        }
                    });
                    if (data && data.Ken_Questionnaire_Parameters__r) {
                        this.questions = data.Ken_Questionnaire_Parameters__r.map((question, index) => ({
                            Id: question.Id,
                            id: index + INDEX_OFFSET,
                            isMCQ:
                                question.Question_Type__c === 'Multiple Choice' ||
                                question.Question_Type__c === 'Dropdown',
                            isRequired: question.Is_Required__c,
                            label: question.Question_Label__c,
                            options: question.MCQ_Options__c,
                            section: question.Section_Name__c,
                            sectionHeader: question.Section_Header__c,
                            type: question.Question_Type__c,
                            gatePassMapping: question.Gate_Pass_Mapping__c || '',
                            showGatePassMapping: question.Question_Type__c === 'Date' || question.Question_Type__c === 'Time'
                        }));

                        if (this.questions.length > ZERO) {
                            this.groupQuestionsBySection(this.questions);
                            this.updateSectionHeaderDisabledStatus(null);
                        }
                    }
                } else {
                    this.questions = [];
                    this.groupedQuestions = [];
                }
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            })
            .finally(() => {
                this.showSpinner = false;
            });
    }
    /* eslint-enable max-lines-per-function, max-statements */

    handleInputChange(event) {
        const field = event.target.dataset.id;
        this.questionnaire[field] = event.target.value;
    }

    handleSelection(event) {
        this.selectedValues = event.detail;

        this.questionnaire.targetAudience = this.selectedValues;
    }

    handleSectionNameChange(event) {
        const section = this.groupedQuestions.find(
            (sec) => sec.sectionId === event.target.dataset.sectionid
        );

        if (section) {
            section.sectionName = event.target.value;
            this.groupedQuestions = [...this.groupedQuestions];
        }
    }

    /* eslint-disable max-statements */
    handleQuestionChange(event) {
        const fieldName = event.target.dataset.name,
            questionId = event.target.dataset.questionid,
            section = this.groupedQuestions.find(
                (sec) => sec.sectionId === event.target.dataset.sectionid
            ),
            sectionId = event.target.dataset.sectionid;

        if (!section) {
            return;
        }

        const questionIndex = section.questions.findIndex(
            (qq) => qq.id === Number(questionId)
        );

        const NOT_FOUND = -1;

        if (questionIndex === NOT_FOUND) {

            return;
        }

        const { type, checked, value: inputValue } = event.target;

        let value = inputValue;

        if (type === 'checkbox') {
            value = checked;
        }

        if (fieldName === 'sectionHeader') {
            section.questions[questionIndex][fieldName] = value;
            this.updateSectionHeaderDisabledStatus(sectionId);
        } else {
            section.questions[questionIndex][fieldName] = value;
        }

        section.questions = [...section.questions];

        if (fieldName === 'type' && (value === 'Multiple Choice' || value === 'Dropdown')) {
            section.questions[questionIndex].isMCQ = true;
        } else if (fieldName === 'type' && value !== 'Multiple Choice' && value !== 'Dropdown') {
            section.questions[questionIndex].isMCQ = false;
            section.questions[questionIndex].options = '';
        }

        // Show Gate Pass Mapping only for Date/Time type questions
        if (fieldName === 'type') {
            section.questions[questionIndex].showGatePassMapping =
                (value === 'Date' || value === 'Time');
            if (value !== 'Date' && value !== 'Time') {
                section.questions[questionIndex].gatePassMapping = '';
            }
        }
    }
    /* eslint-enable max-statements */

    addQuestion(event) {
        const section = this.groupedQuestions.find(
            (sec) => sec.sectionId === event.target.dataset.sectionid
        );

        if (section) {
            const headerExists = section.questions.some((qq) => qq.sectionHeader === true);

            section.questions.push({
                id: section.questions.length + INDEX_OFFSET,
                isHeaderDisabled: headerExists,
                isMCQ: false,
                isRequired: false,
                label: '',
                options: '',
                section: section.sectionName,
                sectionHeader: false,
                type: ''
            });

            section.questions = [...section.questions];
        }
    }

    addSection() {
        const newSection = {
            questions: [],
            sectionId: `section-${Date.now()}`,
            sectionName: ''
        };
        this.groupedQuestions = [...this.groupedQuestions, newSection];
    }

    removeQuestion(event) {
        const { questionid: questionId, sectionid: sectionId } = event.target.dataset,
            section = this.groupedQuestions.find((sec) => sec.sectionId === sectionId);
        if (section) {
            const removed = section.questions.find((qq) => qq.id === Number(questionId)),
                wasHeader = removed && removed.sectionHeader;
            section.questions = section.questions.filter((qq) => qq.id !== Number(questionId));
            if (wasHeader) {
                this.updateSectionHeaderDisabledStatus(sectionId);
            }
            section.questions = [...section.questions];
        }
    }

    removeSection(event) {
        const sectionId = event.target.dataset.sectionid;
        this.groupedQuestions = this.groupedQuestions.filter((sec) => sec.sectionId !== sectionId);
        this.groupedQuestions = [...this.groupedQuestions];
    }

    // eslint-disable-next-line max-statements
    validateForm() {
        if (!this.questionnaire.title || !this.questionnaire.description || !this.questionnaire.targetAudience) {
            this.showToast('Error', 'All questionnaire fields must be filled.', 'error');
            return false;
        }

        if (!this.groupedQuestions || this.groupedQuestions.length === ZERO) {
            this.showToast('Error', 'You must add at least one question.', 'error');
            return false;
        }

        for (let idx = ZERO; idx < this.groupedQuestions.length; idx += INDEX_OFFSET) {
            if (!this.groupedQuestions[idx].sectionName.trim()) {
                this.showToast('Error', 'Each section must have a name.', 'error');
                return false;
            }

            if (this.groupedQuestions[idx].questions.length === ZERO) {
                this.showToast('Error', 'Each section must have at least one question.', 'error');
                return false;
            }

            for (let jdx = ZERO; jdx < this.groupedQuestions[idx].questions.length; jdx += INDEX_OFFSET) {
                const question = this.groupedQuestions[idx].questions[jdx];
                if (!question.label || !question.type) {
                    this.showToast('Error', 'All question fields must be filled.', 'error');
                    return false;
                }
                if (question.isMCQ && !question.options) {
                    this.showToast('Error', 'MCQ or Dropdown questions must have options.', 'error');
                    return false;
                }
            }
        }

        return true;
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
        message,
        title,
        variant
});

        this.dispatchEvent(event);
    }

    resetForm() {
        this.questionnaire = {
            description: '',
            targetAudience: '',
            title: ''
        };
        this.groupedQuestions = [];
    }

    /* eslint-disable max-lines-per-function, max-statements */
    saveQuestionnaire() {
        if (!this.validateForm()) {
            return;
        }

        this.showSpinner = true;
        const isRelatedObject =
            this.objectApiName === 'Ken_Service_Offering__c' ||
            this.objectApiName === 'Ken_Event_Master__c' ||
            this.objectApiName === 'Ken_Schedule_Sessions__c' ||
            this.objectApiName === 'Ken_Survey__c';

        if (isRelatedObject) {
            this.questionnaireId = null;
        } else {
            this.questionnaireId = this.recordId;
        }

        const questionnaireRecord = {
                Descripation__c: this.questionnaire.description,
                Id: this.questionnaireId,
                Section_Name__c: this.questionnaire.title,
                Target_Audience__c: this.questionnaire.targetAudience
            },
            questionsRecords = this.groupedQuestions.flatMap((sec) =>
                sec.questions.map((qq) => ({
                    Id: qq.Id,
                    Is_Required__c: qq.isRequired,
                    MCQ_Options__c: qq.options,
                    Question_Label__c: qq.label,
                    Question_Type__c: qq.type,
                    Gate_Pass_Mapping__c: qq.gatePassMapping || null,
                    Section_Header__c: qq.sectionHeader,
                    Section_Name__c: sec.sectionName
                }))
            );

        if (isRelatedObject) {
            saveQuestionnaireWithRelatedRecord({
                questionnaire: questionnaireRecord,
                questions: questionsRecords,
                relatedObjectType: this.objectApiName,
                relatedRecordId: this.recordId
            })
                .then(() => {
                    this.showToast('Success', 'Questionnaire updated successfully.', 'success');

                    this[NavigationMixin.Navigate]({
                        attributes: { apiName: 'Home' },
                        type: 'standard__navItemPage'
                    });

                    setTimeout(() => {
                        this[NavigationMixin.Navigate]({
                            attributes: {
                                actionName: 'view',
                                objectApiName: this.objectApiName,
                                recordId: this.recordId
                            },
                            type: 'standard__recordPage'
                        });
                    }, NAV_REFRESH_DELAY_MS);
                    window.location.reload();
                    this.resetForm();
                })
                .catch(error => {
                    this.showToast('Error', error.body.message, 'error');
                })
                .finally(() => {
                    this.showSpinner = false;
                });
        } else {
            saveQuestionnaireWithQuestions({ questionnaire: questionnaireRecord, questions: questionsRecords })
                .then((result) => {
                    this.showToast('Success', 'Questionnaire updated successfully.', 'success');

                    this[NavigationMixin.Navigate]({
                        attributes: {
                            actionName: 'view',
                            objectApiName: 'Ken_Questionnaire__c',
                            recordId: result
                        },
                        type: 'standard__recordPage'
                    });

                    this.resetForm();
                })
                .catch(error => {
                    this.showToast('Error', error.body.message, 'error');
                })
                .finally(() => {
                    this.showSpinner = false;
                });
        }
    }
    /* eslint-enable max-lines-per-function, max-statements */

    handleCancel() {
        if (this.recordId) {
            this[NavigationMixin.Navigate]({
                attributes: {
                    actionName: 'view',
                    objectApiName: this.objectApiName,
                    recordId: this.recordId
                },
                type: 'standard__recordPage'
            });
        } else {
            this[NavigationMixin.Navigate]({
                attributes: {
                    actionName: 'home',
                    objectApiName: this.objectApiName
                },
                type: 'standard__objectPage'
            });
        }
    }

    updateSectionHeaderDisabledStatus(sectionId) {
        if (sectionId) {
            const sectionsToUpdate = [this.groupedQuestions.find((sec) => sec.sectionId === sectionId)];

            sectionsToUpdate
                .filter((section) => section)
                .forEach((section) => {
                    const headerExists = section.questions.some((qq) => qq.sectionHeader === true);
                    section.questions.forEach((question) => {
                        question.isHeaderDisabled = headerExists && !question.sectionHeader;
                    });
                });
        } else {
            const sectionsToUpdate = this.groupedQuestions;

            sectionsToUpdate
                .filter((section) => section)
                .forEach((section) => {
                    const headerExists = section.questions.some((qq) => qq.sectionHeader === true);
                    section.questions.forEach((question) => {
                        question.isHeaderDisabled = headerExists && !question.sectionHeader;
                    });
                });
        }
    }

    groupQuestionsBySection(questions) {
        const grouped = questions.reduce((acc, question) => {
            if (!acc[question.section]) {
                acc[question.section] = {
                    questions: [],
                    sectionName: question.section
                };
            }
            acc[question.section].questions.push(question);
            return acc;
        }, {});

        let sectionIndex = INDEX_OFFSET;
        this.groupedQuestions = Object.values(grouped).map(section => {
            section.sectionId = `section-${sectionIndex}`;

            section.questions = section.questions.map(
                (question, questionIndex) => ({ ...question, id: questionIndex + INDEX_OFFSET })
            );

            sectionIndex += INDEX_OFFSET;
            return section;
        });
    }
}