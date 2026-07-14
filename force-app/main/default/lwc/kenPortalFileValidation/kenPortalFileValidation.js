export const PORTAL_FILE_MAX_BYTES = 5 * 1024 * 1024;
export const PORTAL_FILE_ACCEPT = '.pdf,.png,.jpg,.jpeg,.doc,.docx';
export const PORTAL_FILE_TYPE_LABEL = 'PDF, PNG, JPG, DOC, or DOCX';
export const PORTAL_FILE_SIZE_ERROR = 'File size must not exceed 5 MB.';
export const PORTAL_FILE_TYPE_ERROR = `Only ${PORTAL_FILE_TYPE_LABEL} files are allowed.`;

const ALLOWED_MIME_TYPES = new Set([
    'application/pdf',
    'image/png',
    'image/jpeg',
    'image/jpg',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]);

const ALLOWED_EXTENSIONS = new Set(['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx']);

function getFileExtension(fileName) {
    const parts = String(fileName || '').trim().toLowerCase().split('.');
    return parts.length > 1 ? parts.pop() : '';
}

export function validatePortalUploadFile(file) {
    if (!file) {
        return { valid: true, error: '' };
    }

    if (file.size > PORTAL_FILE_MAX_BYTES) {
        return { valid: false, error: PORTAL_FILE_SIZE_ERROR };
    }

    const mime = String(file.type || '').toLowerCase();
    const extension = getFileExtension(file.name);
    const mimeAllowed = mime && ALLOWED_MIME_TYPES.has(mime);
    const extensionAllowed = ALLOWED_EXTENSIONS.has(extension);

    if (mimeAllowed || extensionAllowed) {
        return { valid: true, error: '' };
    }

    return { valid: false, error: PORTAL_FILE_TYPE_ERROR };
}