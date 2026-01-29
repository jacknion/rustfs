import api from '@/api/request';

// KMS types
export interface KMSStatus {
    name: string;
    defaultKeyID: string;
    endpoints: KMSEndpoint[];
}

export interface KMSEndpoint {
    url: string;
    status: 'online' | 'offline';
    version?: string;
}

export interface KMSKeyInfo {
    name: string;
    createdAt: string;
    createdBy: string;
}

export interface KMSKeyListResponse {
    keys: KMSKeyInfo[];
    continuationToken?: string;
}

export interface KMSMetrics {
    requestOK: number;
    requestErr: number;
    requestFail: number;
    requestActive: number;
    auditEvents: number;
    errorEvents: number;
    latencyHistogram: Record<string, number>;
    uptime: number;
    cpus: number;
    usableCPUs: number;
    threads: number;
    heapAlloc: number;
    heapObjects: number;
    stackAlloc: number;
}

export interface CreateKeyRequest {
    keyId: string;
}

// API Functions
export const getKMSStatus = () => {
    return api.get<KMSStatus>('/kms/status');
};

export const getKMSMetrics = () => {
    return api.get<KMSMetrics>('/kms/metrics');
};

export const listKMSKeys = (pattern?: string) => {
    return api.get<KMSKeyListResponse>('/kms/keys', { params: { pattern } });
};

export const createKMSKey = (keyId: string) => {
    return api.post('/kms/key/create', { keyId });
};

export const importKMSKey = (keyId: string, bytes: string) => {
    return api.post('/kms/key/import', { keyId, bytes });
};

export const deleteKMSKey = (keyId: string) => {
    return api.delete('/kms/key/delete', { params: { keyId } });
};

export const getKMSAPIs = () => {
    return api.get('/kms/apis');
};

export const getKMSVersion = () => {
    return api.get('/kms/version');
};
