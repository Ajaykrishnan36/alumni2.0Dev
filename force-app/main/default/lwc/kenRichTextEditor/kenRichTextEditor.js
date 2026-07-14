import { LightningElement, api, track } from 'lwc';

/**
 * Lightweight contenteditable rich-text editor with a Bold / Italic /
 * Bulleted-list / Numbered-list toolbar and a "Continue writing with AI" affordance.
 *
 * Drop-in replacement for <lightning-input-rich-text>: pass `value` (HTML string)
 * and listen for the `change` event (`event.detail.value` is the HTML string),
 * so existing onchange handlers keep working unmodified.
 *
 * Optional `max-length` enforces a plain-text character cap (reverts overflow,
 * same as the old inline editors) and shows an "N/max characters" counter.
 */
export default class KenRichTextEditor extends LightningElement {
    @api placeholder = '';
    @api maxLength;

    _value = '';
    @api
    get value() {
        return this._value;
    }
    set value(v) {
        const incoming = v || '';
        this._value = incoming;
        this.currentLength = this._plainLen(incoming);
        // Sync the live editor immediately when the value is set programmatically
        // (e.g. edit pre-fill / async data load). We cannot rely on renderedCallback
        // for this: `value` is not read in the template, so LWC will not re-render
        // when it changes — which previously left the editor blank on edit.
        if (this.editor && !this._isFocused && this.editor.innerHTML !== incoming) {
            this.editor.innerHTML = incoming;
            this.lastValidHtml = incoming;
            this.ensureListFormatting();
        }
    }

    editor = null;
    lastValidHtml = '';
    _isFocused = false;

    @track currentLength = 0;
    @track isBoldActive = false;
    @track isItalicActive = false;
    @track isUlActive = false;
    @track isOlActive = false;

    get hasCounter() {
        return this.maxLength !== undefined && this.maxLength !== null && this.maxLength !== '';
    }

    get boldClass() {
        return `rte-btn ${this.isBoldActive ? 'active' : ''}`;
    }
    get italicClass() {
        return `rte-btn ${this.isItalicActive ? 'active' : ''}`;
    }
    get ulClass() {
        return `rte-btn ${this.isUlActive ? 'active' : ''}`;
    }
    get olClass() {
        return `rte-btn ${this.isOlActive ? 'active' : ''}`;
    }

    renderedCallback() {
        const editor = this.template.querySelector('.rte-area');
        if (!editor) return;

        if (editor !== this.editor) {
            // First time we see this editor node — seed it with the value.
            this.editor = editor;
            editor.innerHTML = this._value || '';
            this.lastValidHtml = editor.innerHTML;
            this.currentLength = this._plainLen(this._value);
            this.ensureListFormatting();
            this.updateToolbarStates();
        } else if (editor.innerHTML !== (this._value || '')) {
            // Value changed externally (e.g. session restore / clear) — resync.
            editor.innerHTML = this._value || '';
            this.ensureListFormatting();
        }
    }

    _emit(html) {
        this._value = html;
        this.currentLength = this._plainLen(html);
        this.dispatchEvent(new CustomEvent('change', { detail: { value: html } }));
    }

    handleInput(event) {
        const html = event.target.innerHTML || '';
        const max = this.maxLength ? Number(this.maxLength) : 0;
        if (max && this._plainLen(html) > max) {
            // Over the cap — revert to the last accepted content.
            event.target.innerHTML = this.lastValidHtml || '';
            this.placeCaretAtEnd(event.target);
        } else {
            this.lastValidHtml = html;
            this._emit(html);
        }
        this.ensureListFormatting();
        this.updateToolbarStates();
    }

    handleFocus() {
        this._isFocused = true;
        this.updateToolbarStates();
    }

    handleSelection() {
        this.updateToolbarStates();
    }

    handleBlur(event) {
        this._isFocused = false;
        const html = event.target.innerHTML || '';
        this.lastValidHtml = html;
        this._emit(html);
        this.updateToolbarStates();
    }

    executeCommand(command) {
        if (!this.editor) return;
        this.editor.focus();

        if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
            const selection = window.getSelection();
            if (selection && (selection.rangeCount === 0 || selection.isCollapsed)) {
                const range = document.createRange();
                const textNode = this.editor.childNodes[0] || this.editor;
                range.setStart(textNode, 0);
                range.setEnd(textNode, textNode.textContent ? textNode.textContent.length : 0);
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }

        document.execCommand(command, false, null);
        this.lastValidHtml = this.editor.innerHTML || '';
        this._emit(this.editor.innerHTML || '');
        this.ensureListFormatting();
        this.updateToolbarStates();
    }

    handleBold(event) {
        event.preventDefault();
        this.executeCommand('bold');
    }

    handleItalic(event) {
        event.preventDefault();
        this.executeCommand('italic');
    }

    handleUnorderedList(event) {
        event.preventDefault();
        this.executeCommand('insertUnorderedList');
    }

    handleOrderedList(event) {
        event.preventDefault();
        this.executeCommand('insertOrderedList');
    }

    handleAiClick() {
        // Hook for future AI assist; emitted so a parent can opt in.
        this.dispatchEvent(new CustomEvent('aiassist'));
    }

    updateToolbarStates() {
        try {
            this.isBoldActive = document.queryCommandState('bold');
            this.isItalicActive = document.queryCommandState('italic');

            let isInUl = false;
            let isInOl = false;
            const selection = window.getSelection();
            if (selection && selection.rangeCount > 0) {
                let container = selection.getRangeAt(0).commonAncestorContainer;
                while (container && container !== this.editor) {
                    if (container.nodeType === 1) {
                        const tag = container.tagName.toUpperCase();
                        if (tag === 'UL') {
                            isInUl = true;
                            break;
                        }
                        if (tag === 'OL') {
                            isInOl = true;
                            break;
                        }
                        if (tag === 'LI') {
                            const parent = container.parentElement;
                            if (parent) {
                                const pt = parent.tagName.toUpperCase();
                                if (pt === 'UL') isInUl = true;
                                if (pt === 'OL') isInOl = true;
                            }
                            break;
                        }
                    }
                    container = container.parentElement || container.parentNode;
                }
            }
            this.isUlActive = isInUl;
            this.isOlActive = isInOl;
        } catch (e) {
            // ignore — queryCommandState can throw in some embedded contexts
        }
    }

    ensureListFormatting() {
        if (!this.editor) return;
        this.editor.querySelectorAll('ul, ol').forEach(list => {
            if (!list.style.marginLeft) {
                list.style.marginLeft = '1.5rem';
                list.style.marginTop = '0.5rem';
                list.style.marginBottom = '0.5rem';
            }
        });
        this.editor.querySelectorAll('li').forEach(li => {
            if (!li.style.marginBottom) {
                li.style.marginBottom = '0.25rem';
            }
        });
    }

    placeCaretAtEnd(element) {
        if (!element) return;
        const range = document.createRange();
        range.selectNodeContents(element);
        range.collapse(false);
        const selection = window.getSelection();
        if (!selection) return;
        selection.removeAllRanges();
        selection.addRange(range);
    }

    _plainLen(html) {
        const helper = document.createElement('div');
        helper.innerHTML = html || '';
        const text = (helper.textContent || '').replace(/\s+/g, ' ').trim();
        return text.length;
    }
}