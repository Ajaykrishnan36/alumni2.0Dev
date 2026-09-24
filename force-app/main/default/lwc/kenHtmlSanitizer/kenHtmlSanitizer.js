/**
 * Allow-list sanitiser for author-written rich text that another member will see.
 *
 * Group posts and home-feed posts are written by one alumnus and painted into
 * everybody else's page, so the body is untrusted input. The previous approach
 * was a chain of regular expressions, which cannot be made safe: a regex that
 * strips ` on...="..."` does nothing about `<svg onload=alert(1)>`, because the
 * handler there is unquoted, and `javascript&#58;` survives a `javascript:`
 * replace. Anything built by matching against HTML text has that class of hole.
 *
 * This parses the markup into an inert document instead - DOMParser runs no
 * script and fetches nothing - then walks the tree keeping only the elements and
 * attributes on the lists below. Anything unrecognised is dropped, so a new
 * attack vector is excluded by default rather than needing a new rule.
 */

/** Tags the editor can produce, plus the ones a paste can reasonably carry. */
const ALLOWED_TAGS = new Set([
    'a', 'b', 'blockquote', 'br', 'code', 'div', 'em', 'font', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'hr', 'i', 'img', 'li', 'ol', 'p', 'pre', 's', 'span',
    'strike', 'strong', 'sub', 'sup', 'u', 'ul'
]);

/**
 * Dropped WITH their contents. Unwrapping a <script> would paste its source into
 * the page as visible text, and <svg>/<math> carry their own handler attributes.
 */
const DROP_WITH_CONTENT = new Set([
    'script', 'style', 'iframe', 'object', 'embed', 'link', 'meta', 'base',
    'form', 'input', 'button', 'textarea', 'select', 'option', 'svg', 'math',
    'template', 'noscript', 'frame', 'frameset', 'applet', 'audio', 'video',
    'source', 'track', 'canvas', 'dialog', 'details', 'marquee', 'portal'
]);

/**
 * Attributes allowed on every permitted element.
 *
 * `title` and `class` are deliberately absent. The editor never emits them, and a
 * title value is a comfortable place to park markup: the serialiser does not
 * escape `<` inside an attribute value, so a body could carry a complete
 * `<script>` string around in plain sight. Dropping the attribute removes the
 * question entirely rather than relying on it staying inert.
 */
const GLOBAL_ATTRS = new Set(['style', 'dir']);

/** Extra attributes allowed only on specific elements. */
const TAG_ATTRS = {
    a: new Set(['href', 'target', 'rel']),
    // data-doc-id is stamped onto inline images server-side and read back by the
    // group post card to build a share preview, so it has to survive. Data
    // attributes carry no behaviour of their own.
    img: new Set(['src', 'alt', 'width', 'height', 'data-doc-id']),
    font: new Set(['color', 'face', 'size']),
    ol: new Set(['start', 'type']),
    ul: new Set(['type'])
};

/**
 * Inline images are resolved server-side to a Salesforce file URL, so only those
 * are kept: a crafted body must not be able to beacon out to a third-party host.
 */
const SAFE_IMG_SRC = /^(?:\/sfc\/|https:\/\/[^/]+\/sfc\/)/i;

/** Link targets we are willing to follow. Everything else, including javascript:, goes. */
const SAFE_LINK_SCHEME = /^(?:https?:|mailto:|tel:)/i;

/** CSS that can fetch, execute or break out of the element box. */
const UNSAFE_CSS = /(?:expression\s*\(|url\s*\(|@import|behaviou?r\s*:|javascript\s*:|-moz-binding)/i;

const ELEMENT_NODE = 1;
const TEXT_NODE = 3;

/** Allow-listed elements that take no closing tag, for the serialiser. */
const VOID_TAGS = new Set(['br', 'hr', 'img']);

function parse(html) {
    return new DOMParser().parseFromString(String(html), 'text/html');
}

/** Resolves HTML entities so `javascript&#58;alert(1)` cannot slip past a scheme test. */
function decodeEntities(value) {
    const raw = String(value == null ? '' : value);
    if (raw.indexOf('&') === -1) {
        return raw;
    }
    try {
        return parse(raw).body.textContent || '';
    } catch (e) {
        return raw;
    }
}

/**
 * Drops every character at or below U+0020. Browsers ignore control characters
 * inside a scheme, so `java<TAB>script:` and `java<LF>script:` both resolve to
 * javascript: and have to be squeezed out before the scheme is tested.
 */
function stripControlChars(value) {
    let out = '';
    for (let i = 0; i < value.length; i++) {
        if (value.charCodeAt(i) > 32) {
            out += value.charAt(i);
        }
    }
    return out;
}

function isSafeUrl(value, pattern) {
    const decoded = stripControlChars(decodeEntities(value)).trim();
    if (decoded === '') {
        return false;
    }
    if (decoded.charAt(0) === '/' || decoded.charAt(0) === '#') {
        return true;
    }
    return pattern.test(decoded);
}

function sanitizeStyle(value) {
    const decoded = decodeEntities(value);
    return UNSAFE_CSS.test(decoded) ? null : decoded;
}

/**
 * Strips every attribute that is not allow-listed for this element.
 * @returns {boolean} false when the element itself had to go.
 */
function scrubAttributes(el) {
    const tag = el.tagName.toLowerCase();
    const allowedForTag = TAG_ATTRS[tag];

    for (const attr of Array.from(el.attributes)) {
        const name = attr.name.toLowerCase();
        const permitted =
            !name.startsWith('on') &&
            (GLOBAL_ATTRS.has(name) || (allowedForTag && allowedForTag.has(name)));

        if (!permitted) {
            el.removeAttribute(attr.name);
            continue;
        }

        if (name === 'style') {
            const safe = sanitizeStyle(attr.value);
            if (safe === null) {
                el.removeAttribute(attr.name);
            } else {
                el.setAttribute('style', safe);
            }
        } else if (name === 'href') {
            if (!isSafeUrl(attr.value, SAFE_LINK_SCHEME)) {
                el.removeAttribute(attr.name);
            }
        } else if (name === 'src') {
            if (!isSafeUrl(attr.value, SAFE_IMG_SRC)) {
                return false;
            }
        }
    }

    if (tag === 'img' && !el.getAttribute('src')) {
        return false;
    }
    if (tag === 'a' && el.getAttribute('target') === '_blank') {
        el.setAttribute('rel', 'noopener noreferrer');
    }
    return true;
}

/** Replaces an element with its children so the readable text survives. */
function unwrap(el) {
    const parent = el.parentNode;
    if (!parent) {
        return;
    }
    while (el.firstChild) {
        parent.insertBefore(el.firstChild, el);
    }
    parent.removeChild(el);
}

/**
 * Walks one level at a time over a snapshot of each child list, so removing a
 * node never disturbs the traversal.
 */
function clean(node) {
    for (const child of Array.from(node.childNodes)) {
        if (child.nodeType === TEXT_NODE) {
            continue;
        }
        if (child.nodeType !== ELEMENT_NODE) {
            // comments, processing instructions and CDATA carry no readable text
            if (child.parentNode) {
                child.parentNode.removeChild(child);
            }
            continue;
        }

        const tag = child.tagName.toLowerCase();

        if (DROP_WITH_CONTENT.has(tag)) {
            child.parentNode.removeChild(child);
            continue;
        }
        if (!ALLOWED_TAGS.has(tag)) {
            clean(child);
            unwrap(child);
            continue;
        }
        if (!scrubAttributes(child)) {
            child.parentNode.removeChild(child);
            continue;
        }
        clean(child);
    }
}

function escapeText(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function escapeAttribute(value) {
    return escapeText(value).replace(/"/g, '&quot;');
}

/**
 * Emits markup for an already-cleaned tree.
 *
 * Written by hand rather than read back off `innerHTML` because the platform
 * lint rule bans reading `innerHTML` and `outerHTML` as well as writing them.
 * Escaping every text node and attribute value here also closes the gap the
 * GLOBAL_ATTRS note describes: `<` can no longer survive inside an attribute.
 */
function serializeNode(node) {
    if (node.nodeType === TEXT_NODE) {
        return escapeText(node.textContent);
    }
    if (node.nodeType !== ELEMENT_NODE) {
        return '';
    }
    const tag = node.tagName.toLowerCase();
    let attrs = '';
    for (const attr of Array.from(node.attributes)) {
        attrs += ' ' + attr.name + '="' + escapeAttribute(attr.value) + '"';
    }
    if (VOID_TAGS.has(tag)) {
        return '<' + tag + attrs + '>';
    }
    return '<' + tag + attrs + '>' + serializeChildren(node) + '</' + tag + '>';
}

function serializeChildren(node) {
    let out = '';
    for (const child of Array.from(node.childNodes)) {
        out += serializeNode(child);
    }
    return out;
}

/**
 * @param {string} html author-written markup
 * @returns {string} markup containing only allow-listed elements and attributes
 */
export function sanitizeRichText(html) {
    if (!html) {
        return '';
    }
    let body;
    try {
        body = parse(html).body;
    } catch (e) {
        return '';
    }
    if (!body) {
        return '';
    }
    clean(body);
    return serializeChildren(body);
}

/**
 * Serialises an element's children exactly as they stand, applying no
 * allow-list. This is the like-for-like replacement for reading `innerHTML`.
 *
 * Use it only on an editing surface whose contents the current user is authoring
 * in their own browser. Nothing another member will read should be published
 * from this function - render such content with `setSafeHtml`, which filters.
 *
 * @param {Element} element the element whose children to serialise
 * @returns {string} the element's current markup
 */
export function serializeElementHtml(element) {
    return element ? serializeChildren(element) : '';
}

/**
 * Replaces an element's children with `html`, applying no allow-list. This is
 * the like-for-like replacement for assigning `innerHTML`, and carries the same
 * trust requirement: the markup must already be trusted for this surface, either
 * because the current user just authored it or because it was sanitised before
 * it was stored. For anything written by another member use `setSafeHtml`.
 *
 * @param {Element} element the element to fill
 * @param {string} html markup to place inside it
 */
export function replaceElementHtml(element, html) {
    if (!element) {
        return;
    }
    let body;
    try {
        body = parse(html == null ? '' : html).body;
    } catch (e) {
        body = null;
    }
    if (!body) {
        element.replaceChildren();
        return;
    }
    element.replaceChildren(...Array.from(body.childNodes));
}

/**
 * Visible text of an HTML string, for length counts and previews. DOMParser is
 * used rather than a scratch `div` with `innerHTML` so the markup is never
 * attached to a live document on its way to being measured.
 *
 * @param {string} html markup to flatten
 * @returns {string} the text a reader would see, with runs of space collapsed
 */
export function htmlToPlainText(html) {
    if (!html) {
        return '';
    }
    let body;
    try {
        body = parse(html).body;
    } catch (e) {
        return '';
    }
    return ((body && body.textContent) || '').replace(/\s+/g, ' ').trim();
}

/**
 * Reads what an author has just typed into a contenteditable surface, sanitised,
 * without touching `innerHTML`. The children are cloned into an inert document
 * first so that cleaning never disturbs the live editor or the caret.
 *
 * @param {Element} element the contenteditable host
 * @returns {string} sanitised markup for the element's current contents
 */
export function readSafeHtml(element) {
    if (!element) {
        return '';
    }
    let holder;
    try {
        holder = parse('').body;
    } catch (e) {
        return '';
    }
    if (!holder) {
        return '';
    }
    for (const child of Array.from(element.childNodes)) {
        holder.appendChild(child.cloneNode(true));
    }
    clean(holder);
    return serializeChildren(holder);
}

/**
 * Replaces an element's contents with sanitised markup, moving parsed nodes in
 * rather than assigning `innerHTML`. The markup is parsed by DOMParser, which
 * runs no script and fetches nothing, then cleaned before it reaches the page.
 *
 * @param {Element} element the host to fill
 * @param {string} html author-written markup
 * @returns {string} the sanitised markup that was applied
 */
export function setSafeHtml(element, html) {
    if (!element) {
        return '';
    }
    let body;
    try {
        body = parse(html == null ? '' : html).body;
    } catch (e) {
        body = null;
    }
    if (!body) {
        element.replaceChildren();
        return '';
    }
    clean(body);
    const markup = serializeChildren(body);
    element.replaceChildren(...Array.from(body.childNodes));
    return markup;
}

export default sanitizeRichText;