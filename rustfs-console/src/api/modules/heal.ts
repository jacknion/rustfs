import api from '@/api/request';

// Heal types
export interface HealStatus {
    summary: HealSummary;
    startTime: string;
    settings: HealSettings;
    currentBucket: string;
    currentItem: string;
    itemsHealed: number;
    itemsFailed: number;
    bytesHealed: number;
    bytesFailed: number;
    lastHealActivity: string;
}

export interface HealSummary {
    healthy: number;
    healed: number;
    failed: number;
    pending: number;
}

export interface HealSettings {
    dryRun: boolean;
    remove: boolean;
    recursive: boolean;
    sleepMs: number;
}

export interface BackgroundHealStatus {
    healDisks: HealDiskStatus[];
    lastHealActivity: string;
    scannedItemsCount: number;
    healedItemsCount: number;
    currentHealBucket: string;
}

export interface HealDiskStatus {
    endpoint: string;
    state: string;
    objectsHealed: number;
    objectsFailed: number;
    bytesHealed: number;
    bytesFailed: number;
}

export interface HealStartRequest {
    bucket?: string;
    prefix?: string;
    recursive?: boolean;
    dryRun?: boolean;
    remove?: boolean;
    scanMode?: 'normal' | 'deep';
}

// API Functions
export const getBackgroundHealStatus = () => {
    return api.get<BackgroundHealStatus>('/background-heal/status');
};

export const startHeal = (params: HealStartRequest) => {
    return api.post<HealStatus>('/heal/start', params);
};

export const getHealStatus = () => {
    return api.get<HealStatus>('/heal/status');
};

export const stopHeal = () => {
    return api.post('/heal/stop');
};
