import getPortalConfigsApex from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';

let cachedPromise;

const getPortalConfigs = () => {
    if (!cachedPromise) {
        cachedPromise = getPortalConfigsApex().catch((error) => {
            cachedPromise = undefined;
            throw error;
        });
    }
    return cachedPromise;
};

export { getPortalConfigs };