import api from '@/api/request';

// Storage Info
export interface StorageInfo {
    disks: DiskInfo[];
    backend: {
        backendType: string;
        onlineDisks: number;
        offlineDisks: number;
        standardSCData: number;
        standardSCParity: number;
        rrSCData: number;
        rrSCParity: number;
    };
}

export interface DiskInfo {
    endpoint: string;
    rootDisk: boolean;
    drivePath: string;
    healing: boolean;
    scanning: any;
    state: string;
    uuid: string;
    major: number;
    minor: number;
    model: string;
    totalSpace: number;
    usedSpace: number;
    availableSpace: number;
    readThroughput: number;
    writeThroughput: number;
    readLatency: number;
    writeLatency: number;
    utilization: number;
    poolIndex: number;
    setIndex: number;
    diskIndex: number;
}

// Data Usage
export interface DataUsageInfo {
    lastUpdate: string;
    objectsCount: number;
    objectsTotalSize: number;
    objectsReplicationInfo: any;
    bucketsCount: number;
    bucketsUsageInfo: Record<string, BucketUsageInfo>;
    bucketsSizes: Record<string, number>;
    tierStats: Record<string, TierStats>;
}

export interface BucketUsageInfo {
    size: number;
    objectsCount: number;
    objectsSizesHistogram: Record<string, number>;
    objectsVersionsHistogram: Record<string, number>;
    replicatedSize: number;
    replicatedSizePending: number;
    replicatedSizeFailed: number;
    replicaSize: number;
    replicationInfo: any;
}

export interface TierStats {
    totalSize: number;
    numVersions: number;
    numObjects: number;
}

// API Functions
export const getStorageInfo = () => {
    return api.get<StorageInfo>('/storageinfo');
};

export const getDataUsageInfo = () => {
    return api.get<DataUsageInfo>('/datausageinfo');
};

export const getMetrics = (type: 'node' | 'cluster' | 'bucket' | 'resource' = 'cluster') => {
    return api.get<string>('/metrics', {
        params: { type },
        headers: { 'Accept': 'text/plain' }
    });
};
