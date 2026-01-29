import api from '@/api/request';

// Rebalance types
export interface RebalanceStatus {
    id: string;
    started: string;
    pools: RebalancePoolStatus[];
}

export interface RebalancePoolStatus {
    id: number;
    progress: number;
    bucket: string;
    object: string;
    objectsHealed: number;
    bytesHealed: number;
    objectsFailed: number;
    bytesFailed: number;
    elapsed: string;
    eta: string;
}

export interface RebalanceStartResponse {
    id: string;
    started: boolean;
}

// API Functions
export const getRebalanceStatus = () => {
    return api.get<RebalanceStatus>('/rebalance/status');
};

export const startRebalance = () => {
    return api.post<RebalanceStartResponse>('/rebalance/start');
};

export const stopRebalance = () => {
    return api.post('/rebalance/stop');
};
