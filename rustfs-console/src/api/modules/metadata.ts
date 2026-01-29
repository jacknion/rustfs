import api from '@/api/request';

// Metadata Query Types
export interface MetadataQueryRequest {
    query: string;
    bucket?: string;
    recursive?: boolean;
    maxResults?: number;
    marker?: string;
}

export interface ObjectMetadata {
    key: string;
    bucket: string;
    size: number;
    lastModified: string;
    etag: string;
    contentType: string;
    userMetadata: Record<string, string>;
    tags?: Record<string, string>;
    storageClass?: string;
    versionId?: string;
}

export interface MetadataQueryResponse {
    objects: ObjectMetadata[];
    nextMarker?: string;
    isTruncated: boolean;
}

// API Functions
export const queryMetadata = (params: MetadataQueryRequest) => {
    return api.post<MetadataQueryResponse>('/s3/metadata/query', params);
};

export const getObjectMetadata = (bucket: string, key: string, versionId?: string) => {
    return api.get<ObjectMetadata>('/s3/metadata/object', {
        params: { bucket, key, versionId }
    });
};
