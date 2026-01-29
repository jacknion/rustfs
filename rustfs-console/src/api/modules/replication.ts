import api from '@/api/request';

// Replication types
export interface RemoteTarget {
    arn: string;
    sourceBucket: string;
    endpoint: string;
    targetBucket: string;
    secure: boolean;
    path: string;
    type: 'replication' | 'ilm';
    credentials?: {
        accessKey: string;
        secretKey?: string;
    };
    bandwidth?: number;
    healthCheckDuration?: string;
    region?: string;
    replicationSync?: boolean;
    storageClass?: string;
    disableProxy?: boolean;
    resetBeforeDate?: string;
    resetID?: string;
}

export interface RemoteTargetListResponse {
    targets: RemoteTarget[];
}

export interface AddRemoteTargetRequest {
    bucket: string;
    endpoint: string;
    accessKey: string;
    secretKey: string;
    targetBucket: string;
    secure?: boolean;
    region?: string;
    bandwidth?: number;
    healthCheckDuration?: string;
    disableProxy?: boolean;
    syncMode?: boolean;
    storageClass?: string;
}

export interface AddRemoteTargetResponse {
    arn: string;
}

// Bucket Replication Rule
export interface ReplicationRule {
    id: string;
    status: 'Enabled' | 'Disabled';
    priority: number;
    deleteMarkerReplication: { status: 'Enabled' | 'Disabled' };
    deleteReplication: { status: 'Enabled' | 'Disabled' };
    destination: {
        bucket: string;
        storageClass?: string;
    };
    filter?: {
        prefix?: string;
        tags?: Record<string, string>;
    };
    sourceSelectionCriteria?: {
        replicaModifications?: { status: 'Enabled' | 'Disabled' };
    };
    existingObjectReplication?: { status: 'Enabled' | 'Disabled' };
}

export interface BucketReplicationConfig {
    role: string;
    rules: ReplicationRule[];
}

// API Functions
export const listRemoteTargets = (bucket?: string) => {
    return api.get<RemoteTargetListResponse>('/list-remote-targets', {
        params: bucket ? { bucket } : undefined
    });
};

export const addRemoteTarget = (data: AddRemoteTargetRequest) => {
    return api.post<AddRemoteTargetResponse>('/set-remote-target', data);
};

export const removeRemoteTarget = (arn: string) => {
    return api.delete('/remove-remote-target', { params: { arn } });
};

export const getBucketReplication = (bucket: string) => {
    return api.get<BucketReplicationConfig>('/get-bucket-replication', { params: { bucket } });
};

export const setBucketReplication = (bucket: string, config: BucketReplicationConfig) => {
    return api.put('/set-bucket-replication', { bucket, ...config });
};

export const deleteBucketReplication = (bucket: string) => {
    return api.delete('/delete-bucket-replication', { params: { bucket } });
};
