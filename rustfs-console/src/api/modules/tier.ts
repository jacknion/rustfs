import api from '@/api/request';

// Tier types
export interface TierInfo {
    name: string;
    type: 's3' | 'azure' | 'gcs' | 'minio';
    endpoint: string;
    bucket: string;
    prefix: string;
    region: string;
    storageClass: string;
    status: 'online' | 'offline';
}

export interface TierStats {
    tierName: string;
    totalSize: number;
    numObjects: number;
    numVersions: number;
    dailyStats?: DailyTierStats[];
}

export interface DailyTierStats {
    date: string;
    tieredSize: number;
    tieredObjects: number;
}

export interface AddTierRequest {
    type: 's3' | 'azure' | 'gcs' | 'minio';
    name: string;
    endpoint: string;
    accessKey: string;
    secretKey: string;
    bucket: string;
    prefix?: string;
    region?: string;
    storageClass?: string;
}

export interface TierListResponse {
    tiers: TierInfo[];
}

export interface TierStatsResponse {
    stats: Record<string, TierStats>;
}

// API Functions
export const listTiers = () => {
    return api.get<TierListResponse>('/tier');
};

export const getTierStats = () => {
    return api.get<TierStatsResponse>('/tier-stats');
};

export const addTier = (data: AddTierRequest) => {
    return api.post('/tier', data);
};

export const editTier = (name: string, data: Partial<AddTierRequest>) => {
    return api.put('/tier', { ...data, name });
};

export const removeTier = (name: string) => {
    return api.delete('/tier', { params: { tier: name } });
};

export const verifyTier = (name: string) => {
    return api.get('/tier/verify', { params: { tier: name } });
};
