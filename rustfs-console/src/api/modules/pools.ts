import api from '@/api/request';

// Pool types
export interface PoolInfo {
    id: number;
    suspended: boolean;
    decommission?: DecommissionInfo;
    cmdline: string;
    lastUpdate: string;

    // Computed from storage info
    sets: SetInfo[];
}

export interface SetInfo {
    id: number;
    rawUsage: number;
    rawCapacity: number;
    usage: number;
    disksCount: {
        online: number;
        offline: number;
        healing: number;
    };
}

export interface DecommissionInfo {
    startTime: string;
    startSize: number;
    currentSize: number;
    complete: boolean;
    failed: boolean;
    canceled: boolean;
    poolProgress: number;
    currentBucket: string;
    currentObject: string;
    bytesRemaining: number;
    decommissionedBucket?: string;
    failedReason?: string;
}

export interface PoolsListResponse {
    pools: PoolInfo[];
}

// API Functions
export const listPools = () => {
    return api.get<PoolsListResponse>('/pools/list');
};

export const getPoolStatus = (poolId: number) => {
    return api.get('/pools/status', { params: { pool: poolId } });
};

export const decommissionPool = (poolId: number) => {
    return api.post('/pools/decommission', null, { params: { pool: poolId } });
};

export const cancelDecommission = (poolId: number) => {
    return api.post('/pools/cancel', null, { params: { pool: poolId } });
};
