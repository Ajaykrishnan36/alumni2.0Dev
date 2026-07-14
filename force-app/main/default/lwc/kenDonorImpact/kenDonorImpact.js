import { LightningElement } from 'lwc';

export default class KenDonorImpact extends LightningElement {
    stats = [
        { id: 1, number: '2,000+', label: 'Students receiving alumni-backed support' },
        { id: 2, number: '15+', label: 'Major facilities improved with alumni contributions' },
        { id: 3, number: '120+', label: 'Clubs and events enabled by alumni' },
        { id: 4, number: '50+', label: 'Research initiatives boosted by alumni funding' }
    ];
}