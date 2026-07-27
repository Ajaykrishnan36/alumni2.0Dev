import getModuleVisibilityApex from '@salesforce/apex/KenModuleVisibilityController.getModuleVisibility';

let cachedPromise;

/**
 * Shared, memoized accessor for the per-module show/hide flags so the setting
 * is fetched once per page rather than once per component.
 */
const getModuleVisibility = () => {
    if (!cachedPromise) {
        cachedPromise = getModuleVisibilityApex().catch((error) => {
            cachedPromise = undefined;
            throw error;
        });
    }
    return cachedPromise;
};

export { getModuleVisibility };