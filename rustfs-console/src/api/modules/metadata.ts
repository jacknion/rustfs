import api from '@/api/request';

// Metadata Query Types
export interface MetadataQueryRequest {
    bucket?: string;
    prefix?: string;
    storageClass?: string;
    encryption?: string;
    ownerId?: string;
    minSize?: number;
    maxSize?: number;
    modifiedAfter?: string;
    modifiedBefore?: string;
    includeDeleted?: boolean;
    limit?: number;
    offset?: number;
    tags?: Record<string, string>;
}

export interface ObjectMetadata {
    bucket: string;
    object_key: string;
    size_bytes: number;
    last_modified: string;
    etag: string;
    content_type: string;
    storage_class: string;
    owner_id?: string;
    user_metadata?: Record<string, string>;
    tags?: Record<string, string>;
    version_id?: string;
    is_deleted?: boolean;
}

export interface MetadataQueryResponse {
    objects: ObjectMetadata[];
    metadata: {
        total_count: number;
        returned_count: number;
        offset: number;
        limit: number;
        query_time_ms: number;
    };
}

// API Functions

/**
 * Query S3 object metadata using GET request with query parameters
 * Backend endpoint: GET /rustfs/admin/v3/s3/metadata/query
 */
export const queryMetadata = (params: MetadataQueryRequest) => {
    // Build query string from params, converting to snake_case for backend
    const queryParams: Record<string, string> = {};

    if (params.bucket) queryParams.bucket = params.bucket;
    if (params.prefix) queryParams.prefix = params.prefix;
    if (params.storageClass) queryParams.storage_class = params.storageClass;
    if (params.encryption) queryParams.encryption = params.encryption;
    if (params.ownerId) queryParams.owner_id = params.ownerId;
    if (params.minSize !== undefined) queryParams.min_size = String(params.minSize);
    if (params.maxSize !== undefined) queryParams.max_size = String(params.maxSize);
    if (params.modifiedAfter) queryParams.modified_after = params.modifiedAfter;
    if (params.modifiedBefore) queryParams.modified_before = params.modifiedBefore;
    if (params.includeDeleted !== undefined) queryParams.include_deleted = String(params.includeDeleted);
    if (params.limit !== undefined) queryParams.limit = String(params.limit);
    if (params.offset !== undefined) queryParams.offset = String(params.offset);
    if (params.tags) queryParams.tags = JSON.stringify(params.tags);

    return api.get<MetadataQueryResponse>('/s3/metadata/query', { params: queryParams });
};

/**
 * Query S3 object metadata by tags using POST request with JSON body
 * Backend endpoint: POST /rustfs/admin/v3/s3/metadata/query-by-tags
 */
export interface QueryByTagsRequest {
    tags?: Record<string, string>;
    tagsFuzzy?: Record<string, string>;
    limit?: number;
    bucket?: string;
    prefix?: string;
    includeDeleted?: boolean;
}

export const queryMetadataByTags = (params: QueryByTagsRequest) => {
    return api.post<MetadataQueryResponse>('/s3/metadata/query-by-tags', params);
};

/**
 * Get metadata for a specific object
 */
export const getObjectMetadata = (bucket: string, key: string, versionId?: string) => {
    return api.get<ObjectMetadata>('/s3/metadata/object', {
        params: { bucket, key, versionId }
    });
};
