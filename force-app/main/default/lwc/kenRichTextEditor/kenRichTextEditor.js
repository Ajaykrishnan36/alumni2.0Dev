import { LightningElement, api, track } from 'lwc';
import {
    htmlToPlainText,
    replaceElementHtml,
    serializeElementHtml
} from 'c/kenHtmlSanitizer';

/**
 * Lightweight contenteditable rich-text editor with a toolbar covering the
 * formats Salesforce's <lightning-input-rich-text> supports (font, size,
 * bold, italic, underline, strikethrough, text/highlight color,
 * bulleted/numbered lists, indent, alignment, link and clear formatting)
 * — image insertion is intentionally excluded.
 *
 * Drop-in replacement for <lightning-input-rich-text>: pass `value` (HTML string)
 * and listen for the `change` event (`event.detail.value` is the HTML string),
 * so existing onchange handlers keep working unmodified.
 *
 * Optional `max-length` enforces a plain-text character cap (reverts overflow)
 * and shows an "N/max characters" counter.
 */
export default class KenRichTextEditor extends LightningElement {
    @api placeholder = '';
    @api maxLength;
    // Opt-in: this editor is shared by a dozen components, only the ones that
    // can actually store an image (the group post composer) turn these on.
    // allowImages accepts pasted/dropped images; showImageButton additionally
    // puts a picker in the toolbar. They are separate because the composer keeps
    // its picker in the footer next to Create a Poll, but still needs paste.
    @api allowImages = false;
    @api showImageButton = false;
    @api imageBusy = false;
    @api imageAccept = 'image/jpeg,image/png,image/gif,image/webp';

    _value = '';
    @api
    get value() {
        return this._value;
    }
    set value(v) {
        const incoming = v || '';
        this._value = incoming;
        this.currentLength = this._plainLen(incoming);
        if (this.editor && !this._isFocused && serializeElementHtml(this.editor) !== incoming) {
            replaceElementHtml(this.editor, incoming);
            this.lastValidHtml = incoming;
            this.ensureListFormatting();
        }
    }

    editor = null;
    lastValidHtml = '';
    savedRange = null;
    _isFocused = false;

    @track currentLength = 0;
    @track foreColor = '#111827';
    @track backColor = '#fde047';
    @track isBoldActive = false;
    @track isItalicActive = false;
    @track isUnderlineActive = false;
    @track isStrikeActive = false;
    @track isUlActive = false;
    @track isOlActive = false;
    @track isAlignLeftActive = false;
    @track isAlignCenterActive = false;
    @track isAlignRightActive = false;
    @track isAlignJustifyActive = false;
    @track showLinkInput = false;
    @track linkUrl = '';

    get hasCounter() {
        return this.maxLength !== undefined && this.maxLength !== null && this.maxLength !== '';
    }

    get boldClass() {
        return `rte-btn ${this.isBoldActive ? 'active' : ''}`;
    }
    get italicClass() {
        return `rte-btn ${this.isItalicActive ? 'active' : ''}`;
    }
    get underlineClass() {
        return `rte-btn ${this.isUnderlineActive ? 'active' : ''}`;
    }
    get strikeClass() {
        return `rte-btn ${this.isStrikeActive ? 'active' : ''}`;
    }
    get ulClass() {
        return `rte-btn ${this.isUlActive ? 'active' : ''}`;
    }
    get olClass() {
        return `rte-btn ${this.isOlActive ? 'active' : ''}`;
    }
    get alignLeftClass() {
        return `rte-btn ${this.isAlignLeftActive ? 'active' : ''}`;
    }
    get alignCenterClass() {
        return `rte-btn ${this.isAlignCenterActive ? 'active' : ''}`;
    }
    get alignRightClass() {
        return `rte-btn ${this.isAlignRightActive ? 'active' : ''}`;
    }
    get alignJustifyClass() {
        return `rte-btn ${this.isAlignJustifyActive ? 'active' : ''}`;
    }
    get foreBarStyle() {
        return `background:${this.foreColor};`;
    }
    get backBarStyle() {
        return `background:${this.backColor};`;
    }

    renderedCallback() {
        const editor = this.template.querySelector('.rte-area');
        if (!editor) return;

        if (editor !== this.editor) {
            this.editor = editor;
            replaceElementHtml(editor, this._value || '');
            this.lastValidHtml = serializeElementHtml(editor);
            this.currentLength = this._plainLen(this._value);
            this.ensureListFormatting();
            this.updateToolbarStates();
        } else if (!this._isFocused && serializeElementHtml(editor) !== (this._value || '')) {
            replaceElementHtml(editor, this._value || '');
            this.ensureListFormatting();
        }
    }

    _emit(html) {
        // Strip caret markers and the LWC synthetic-shadow scoping attributes
        // (lwc-xxxxx="") that execCommand copies onto new nodes \u2014 they are
        // meaningless outside this component and pollute the stored value.
        const clean = (html || '')
            .replace(/\u200B/g, '')
            .replace(/\s+lwc-[a-z0-9]+(="")?/gi, '');
        this._value = clean;
        this.currentLength = this._plainLen(clean);
        this.dispatchEvent(new CustomEvent('change', { detail: { value: clean } }));
    }

    handleInput(event) {
        const html = serializeElementHtml(event.target);
        const max = this.maxLength ? Number(this.maxLength) : 0;
        if (max && this._plainLen(html) > max) {
            replaceElementHtml(event.target, this.lastValidHtml || '');
            this.placeCaretAtEnd(event.target);
            this.updateToolbarStates();
            return;
        }
        this.ensureListFormatting();
        const finalHtml = serializeElementHtml(event.target);
        this.lastValidHtml = finalHtml;
        this._emit(finalHtml);
        this.saveCurrentSelection();
        this.updateToolbarStates();
    }

    handleFocus() {
        this._isFocused = true;
        this.saveCurrentSelection();
        this.updateToolbarStates();
    }

    handleSelection() {
        this.saveCurrentSelection();
        this.updateToolbarStates();
    }

    handleBlur(event) {
        this._isFocused = false;
        const html = serializeElementHtml(event.target);
        this.lastValidHtml = html;
        this._emit(html);
        this.updateToolbarStates();
    }

    preventBlur(event) {
        event.preventDefault();
    }

    saveCurrentSelection() {
        const selection = window.getSelection();
        if (selection && selection.rangeCount > 0) {
            const range = selection.getRangeAt(0);
            if (this.editor && this.editor.contains(range.commonAncestorContainer)) {
                this.savedRange = range.cloneRange();
            }
        }
    }

    restoreSelection() {
        if (!this.editor) return;
        this.editor.focus();
        if (this.savedRange) {
            const selection = window.getSelection();
            if (selection) {
                selection.removeAllRanges();
                selection.addRange(this.savedRange);
            }
        }
    }

    afterCommand() {
        if (!this.editor) return;
        this.ensureListFormatting();
        this.lastValidHtml = serializeElementHtml(this.editor);
        this._emit(this.lastValidHtml);
        this.updateToolbarStates();
    }

    executeCommand(command) {
        if (!this.editor) return;
        this.restoreSelection();

        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) {
            const range = document.createRange();
            range.selectNodeContents(this.editor);
            range.collapse(false);
            if (selection) {
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }

        const wasOn = this._isToggleableFormat(command) && this._queryState(command);
        document.execCommand(command, false, null);

        // Turning a format OFF at a collapsed caret inside styled text is
        // unreliable in contenteditable — when the browser ignored the toggle,
        // physically move the caret out of the styled node so newly typed text
        // stops inheriting the adjacent formatting.
        if (wasOn && this._isToggleableFormat(command)) {
            const sel = window.getSelection();
            if (sel && sel.rangeCount > 0 && sel.isCollapsed && this._queryState(command)) {
                this._escapeFormat(command, sel);
            }
        }

        this.afterCommand();
    }

    _isToggleableFormat(command) {
        return command === 'bold' || command === 'italic'
            || command === 'underline' || command === 'strikeThrough';
    }

    _queryState(command) {
        try {
            return document.queryCommandState(command);
        } catch (e) {
            return false;
        }
    }

    _escapeFormat(command, selection) {
        const TAGS = {
            bold: ['B', 'STRONG'],
            italic: ['I', 'EM'],
            underline: ['U'],
            strikeThrough: ['S', 'STRIKE', 'DEL']
        };
        const tags = TAGS[command];
        if (!tags) return;
        let node = selection.getRangeAt(0).startContainer;
        let target = null;
        while (node && node !== this.editor) {
            if (node.nodeType === 1 && tags.includes(node.tagName)) target = node;
            node = node.parentNode;
        }
        if (!target || !target.parentNode) return;
        const marker = document.createTextNode('\u200B');
        target.parentNode.insertBefore(marker, target.nextSibling);
        const range = document.createRange();
        range.setStart(marker, 1);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
    }

    handleBold(event) {
        event.preventDefault();
        this.executeCommand('bold');
    }

    handleItalic(event) {
        event.preventDefault();
        this.executeCommand('italic');
    }

    handleUnderline(event) {
        event.preventDefault();
        this.executeCommand('underline');
    }

    handleStrike(event) {
        event.preventDefault();
        this.executeCommand('strikeThrough');
    }

    handleUnorderedList(event) {
        event.preventDefault();
        this.executeCommand('insertUnorderedList');
    }

    handleOrderedList(event) {
        event.preventDefault();
        this.executeCommand('insertOrderedList');
    }

    handleIndent(event) {
        event.preventDefault();
        this.executeCommand('indent');
    }

    handleOutdent(event) {
        event.preventDefault();
        this.executeCommand('outdent');
    }

    handleAlignLeft(event) {
        event.preventDefault();
        this.executeCommand('justifyLeft');
    }

    handleAlignCenter(event) {
        event.preventDefault();
        this.executeCommand('justifyCenter');
    }

    handleAlignRight(event) {
        event.preventDefault();
        this.executeCommand('justifyRight');
    }

    handleAlignJustify(event) {
        event.preventDefault();
        this.executeCommand('justifyFull');
    }

    handleClearFormat(event) {
        event.preventDefault();
        this.restoreSelection();
        document.execCommand('removeFormat', false, null);
        document.execCommand('unlink', false, null);
        this.afterCommand();
    }

    handleForeColor(event) {
        const color = event.target.value;
        this.foreColor = color;
        this.restoreSelection();
        document.execCommand('styleWithCSS', false, true);
        document.execCommand('foreColor', false, color);
        document.execCommand('styleWithCSS', false, false);
        this.afterCommand();
    }

    handleBackColor(event) {
        const color = event.target.value;
        this.backColor = color;
        this.restoreSelection();
        document.execCommand('styleWithCSS', false, true);
        if (!document.execCommand('hiliteColor', false, color)) {
            document.execCommand('backColor', false, color);
        }
        document.execCommand('styleWithCSS', false, false);
        this.afterCommand();
    }

    handleFontName(event) {
        const font = event.target.value;
        event.target.selectedIndex = 0;
        if (!font) return;
        this.restoreSelection();
        document.execCommand('styleWithCSS', false, true);
        document.execCommand('fontName', false, font);
        document.execCommand('styleWithCSS', false, false);
        this.afterCommand();
    }

    handleFontSize(event) {
        const size = event.target.value;
        event.target.selectedIndex = 0;
        if (!size) return;
        this.restoreSelection();
        document.execCommand('fontSize', false, size);
        this.afterCommand();
    }

    handleLink(event) {
        event.preventDefault();
        this.saveCurrentSelection();
        this.linkUrl = 'https://';
        this.showLinkInput = true;
        requestAnimationFrame(() => {
            const input = this.template.querySelector('.rte-link-input');
            if (input) {
                input.focus();
                input.select();
            }
        });
    }

    handleLinkUrlChange(event) {
        this.linkUrl = event.target.value || '';
    }

    handleLinkKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleLinkInsert();
        } else if (event.key === 'Escape') {
            this.handleLinkCancel();
        }
    }

    handleLinkCancel() {
        this.showLinkInput = false;
        this.linkUrl = '';
    }

    handleLinkInsert() {
        const url = (this.linkUrl || '').trim();
        this.showLinkInput = false;
        this.linkUrl = '';
        if (!url || url === 'https://') return;

        this.restoreSelection();
        const selection = window.getSelection();
        const collapsed = !selection || selection.rangeCount === 0 || selection.isCollapsed;
        if (collapsed) {
            const safe = url.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
            document.execCommand('insertHTML', false,
                `<a href="${safe}" target="_blank" rel="noopener noreferrer">${safe}</a>`);
        } else {
            document.execCommand('createLink', false, url);
        }
        this.editor.querySelectorAll('a').forEach(anchor => {
            anchor.setAttribute('target', '_blank');
            anchor.setAttribute('rel', 'noopener noreferrer');
        });
        this.afterCommand();
    }

    // --- Images ----------------------------------------------------------
    //
    // The editor only knows how to place an <img> at the caret; uploading the
    // file and deciding what the src should eventually be is the owner's job,
    // so the picked files go out as an event and the owner calls insertImage().

    handleClickImage() {
        this.saveCurrentSelection();
        const input = this.template.querySelector('input.rte-image-input');
        if (input) input.click();
    }

    // A pasted or dragged image arrives as a local data: URL that only this
    // browser can resolve. Left alone it previews perfectly and then vanishes on
    // save, so it is intercepted and routed through the same upload as the
    // toolbar button. Without allowImages the paste is dropped rather than
    // silently stored as an unusable data: URL.
    handlePaste(event) {
        const files = this.imageFilesFrom(event.clipboardData);
        if (files.length === 0) return;
        event.preventDefault();
        if (!this.allowImages) return;
        this.dispatchEvent(new CustomEvent('imageselect', { detail: { files } }));
    }

    allowDrop(event) {
        if (this.imageFilesFrom(event.dataTransfer).length > 0) event.preventDefault();
    }

    handleDrop(event) {
        const files = this.imageFilesFrom(event.dataTransfer);
        if (files.length === 0) return;
        event.preventDefault();
        if (!this.allowImages) return;
        this.dispatchEvent(new CustomEvent('imageselect', { detail: { files } }));
    }

    imageFilesFrom(transfer) {
        if (!transfer) return [];
        const out = [];
        // Screenshots come through items[] with no entry in files[], so both are
        // checked and de-duplicated by name+size.
        for (const item of Array.from(transfer.items || [])) {
            if (item.kind === 'file' && (item.type || '').startsWith('image/')) {
                const file = item.getAsFile();
                if (file) out.push(file);
            }
        }
        for (const file of Array.from(transfer.files || [])) {
            if ((file.type || '').startsWith('image/') &&
                !out.some(f => f.name === file.name && f.size === file.size)) {
                out.push(file);
            }
        }
        return out;
    }

    handleImageFiles(event) {
        const files = Array.from(event.target.files || []);
        event.target.value = '';
        if (files.length === 0) return;
        this.dispatchEvent(new CustomEvent('imageselect', { detail: { files } }));
    }

    @api
    insertImage(url, alt) {
        if (!url || !this.editor) return;
        const safeUrl = String(url)
            .replace(/&/g, '&amp;').replace(/"/g, '&quot;')
            .replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const safeAlt = String(alt || '')
            .replace(/&/g, '&amp;').replace(/"/g, '&quot;')
            .replace(/</g, '&lt;').replace(/>/g, '&gt;');
        this.editor.focus();
        this.restoreSelection();
        // A trailing paragraph keeps the caret below the image so the author can
        // carry on typing a caption instead of landing inside the image node.
        document.execCommand('insertHTML', false,
            `<img src="${safeUrl}" alt="${safeAlt}" /><p><br/></p>`);
        this.afterCommand();
    }

    /**
     * Hand every <img> in the editor to `resolver(src)` and return the resulting
     * HTML. Whatever the resolver returns becomes the new src; returning a falsy
     * value removes the image entirely.
     *
     * This reads src off the live DOM rather than matching strings in serialized
     * markup. Serialization re-encodes characters (& becomes &amp;) and may
     * reorder attributes, so string matching against the URL the upload returned
     * silently missed - which is exactly how an uploaded image ended up being
     * dropped from the saved post.
     */
    @api
    resolveImages(resolver) {
        if (!this.editor || typeof resolver !== 'function') return this.value;
        const clone = this.editor.cloneNode(true);
        clone.querySelectorAll('img').forEach(img => {
            const replacement = resolver(img.getAttribute('src'));
            if (replacement) img.setAttribute('src', replacement);
            else img.remove();
        });
        return serializeElementHtml(clone);
    }

    handleAiClick() {
        this.dispatchEvent(new CustomEvent('aiassist'));
    }

    updateToolbarStates() {
        try {
            this.isBoldActive = document.queryCommandState('bold');
            this.isItalicActive = document.queryCommandState('italic');
            this.isUnderlineActive = document.queryCommandState('underline');
            this.isStrikeActive = document.queryCommandState('strikeThrough');
            this.isAlignLeftActive = document.queryCommandState('justifyLeft');
            this.isAlignCenterActive = document.queryCommandState('justifyCenter');
            this.isAlignRightActive = document.queryCommandState('justifyRight');
            this.isAlignJustifyActive = document.queryCommandState('justifyFull');

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
            // queryCommandState can throw in some embedded contexts
        }
    }

    ensureListFormatting() {
        if (!this.editor) return;
        // list-style is set inline because SLDS / site resets strip list
        // markers inside contenteditable — without this the numbers/bullets
        // are invisible while typing even though the saved HTML renders fine.
        this.editor.querySelectorAll('ul, ol').forEach(list => {
            if (!list.style.marginLeft) {
                list.style.marginLeft = '1.5rem';
                list.style.marginTop = '0.5rem';
                list.style.marginBottom = '0.5rem';
            }
            list.style.listStyleType = list.tagName === 'OL' ? 'decimal' : 'disc';
            list.style.listStylePosition = 'outside';
            list.style.paddingLeft = '0.5rem';
        });
        this.editor.querySelectorAll('li').forEach(li => {
            if (!li.style.marginBottom) {
                li.style.marginBottom = '0.25rem';
            }
            li.style.display = 'list-item';
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
        return htmlToPlainText(html).length;
    }
}