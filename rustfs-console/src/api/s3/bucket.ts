import { s3Api } from '@/api/request';

export const listBuckets = async () => {
    const res = await s3Api.get('/', { responseType: 'text' });
    // Parse XML
    const parser = new DOMParser();
    const xmlDoc = parser.parseFromString(res.data, "text/xml");
    const buckets: any[] = [];
    const bucketNodes = xmlDoc.getElementsByTagName("Bucket");
    for (let i = 0; i < bucketNodes.length; i++) {
        const node = bucketNodes.item(i);
        if (!node) continue;
        buckets.push({
            name: node.getElementsByTagName("Name")[0]?.textContent,
            creationDate: node.getElementsByTagName("CreationDate")[0]?.textContent,
        });
    }
    return buckets;
};

export const createBucket = (bucketName: string) => {
    return s3Api.put(`/${bucketName}`);
};

export const deleteBucket = (bucketName: string) => {
    return s3Api.delete(`/${bucketName}`);
};

export const listObjects = async (bucketName: string, prefix = '', delimiter = '/') => {
    const res = await s3Api.get(`/${bucketName}`, {
        params: {
            'list-type': 2,
            prefix,
            delimiter
        },
        responseType: 'text'
    });

    const parser = new DOMParser();
    const xmlDoc = parser.parseFromString(res.data, "text/xml");

    const objects: any[] = [];

    // Handle folders (CommonPrefixes)
    const commonPrefixes = xmlDoc.getElementsByTagName("CommonPrefixes");
    for (let i = 0; i < commonPrefixes.length; i++) {
        const node = commonPrefixes.item(i);
        if (!node) continue;
        const prefixVal = node.getElementsByTagName("Prefix")[0]?.textContent;
        // Skip if prefixVal is exactly the prefix we asked for (can happen in some S3 impls or root)
        if (prefixVal && prefixVal !== prefix) {
            objects.push({
                type: 'folder',
                key: prefixVal,
                name: prefixVal.replace(prefix, '') // Display name relative to current folder
            });
        }
    }

    // Handle files (Contents)
    const contents = xmlDoc.getElementsByTagName("Contents");
    for (let i = 0; i < contents.length; i++) {
        const node = contents.item(i);
        if (!node) continue;
        const key = node.getElementsByTagName("Key")[0]?.textContent;
        // In S3, the "folder" itself might appear as a 0-byte object if explicitly created. 
        // We usually filter it out if it matches the prefix exactly and ends in /
        if (key && key !== prefix) {
            objects.push({
                type: 'file',
                key: key,
                name: key.replace(prefix, ''),
                lastModified: node.getElementsByTagName("LastModified")[0]?.textContent,
                size: parseInt(node.getElementsByTagName("Size")[0]?.textContent || '0'),
                etag: node.getElementsByTagName("ETag")[0]?.textContent
            });
        }
    }

    return objects;
};

export const putObject = (bucketName: string, key: string, data: File) => {
    return s3Api.put(`/${bucketName}/${key}`, data, {
        headers: {
            'Content-Type': data.type || 'application/octet-stream'
        }
    });
};

export const deleteObject = (bucketName: string, key: string) => {
    return s3Api.delete(`/${bucketName}/${key}`);
};

// Start a simple browser download
export const getObjectUrl = (bucketName: string, key: string) => {
    // This returns the full URL. 
    // Since our s3Api proxy is at /s3api, we can construct the browser-facing URL.
    // However, for private objects, we might need a presigned URL. 
    // For this MVP/Admin console, let's assume we are using the proxy which handles Auth via the interceptors if we used axios.
    // But for a download link in <a> tag, the browser sends the request.
    // The browser won't have the SigV4 headers unless we use a Service Worker or download via Blob (Axios).
    // Let's implement download via Axios Blob for now.
    return `/s3api/${bucketName}/${key}`;
};

export const downloadObject = async (bucketName: string, key: string) => {
    const res = await s3Api.get(`/${bucketName}/${key}`, {
        responseType: 'blob'
    });
    const url = window.URL.createObjectURL(new Blob([res.data]));
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', key.split('/').pop() || 'download');
    document.body.appendChild(link);
    link.click();
    link.remove();
};

// ===== Bucket Settings APIs =====

// Versioning
export const getBucketVersioning = async (bucketName: string): Promise<{ status: string }> => {
    const res = await s3Api.get(`/${bucketName}?versioning`, { responseType: 'text' });
    const parser = new DOMParser();
    const xmlDoc = parser.parseFromString(res.data, "text/xml");
    const status = xmlDoc.getElementsByTagName("Status")[0]?.textContent || 'Disabled';
    return { status };
};

export const putBucketVersioning = async (bucketName: string, enabled: boolean) => {
    const status = enabled ? 'Enabled' : 'Suspended';
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <Status>${status}</Status>
</VersioningConfiguration>`;
    return s3Api.put(`/${bucketName}?versioning`, xml, {
        headers: { 'Content-Type': 'application/xml' }
    });
};

// Object Lock Configuration
export const getBucketObjectLockConfig = async (bucketName: string): Promise<{ enabled: boolean; mode?: string; days?: number; years?: number }> => {
    try {
        const res = await s3Api.get(`/${bucketName}?object-lock`, { responseType: 'text' });
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(res.data, "text/xml");
        const objectLockEnabled = xmlDoc.getElementsByTagName("ObjectLockEnabled")[0]?.textContent === 'Enabled';
        const mode = xmlDoc.getElementsByTagName("Mode")[0]?.textContent;
        const days = xmlDoc.getElementsByTagName("Days")[0]?.textContent;
        const years = xmlDoc.getElementsByTagName("Years")[0]?.textContent;
        return {
            enabled: objectLockEnabled,
            mode: mode || undefined,
            days: days ? parseInt(days) : undefined,
            years: years ? parseInt(years) : undefined
        };
    } catch (e: any) {
        // Object lock not configured returns 404
        if (e.response?.status === 404 || e.response?.status === 501) {
            return { enabled: false };
        }
        throw e;
    }
};

// Bucket Quota (Admin API)
import api from '@/api/request';

export const getBucketQuota = async (bucketName: string): Promise<{ quota: number }> => {
    try {
        const res = await api.get(`/buckets/${bucketName}/quota`);
        return res.data || { quota: 0 };
    } catch (e: any) {
        if (e.response?.status === 404) {
            return { quota: 0 };
        }
        throw e;
    }
};

export const putBucketQuota = async (bucketName: string, quota: number) => {
    return api.put(`/buckets/${bucketName}/quota`, { quota });
};

// Bucket Tags
export const getBucketTags = async (bucketName: string): Promise<Record<string, string>> => {
    try {
        const res = await s3Api.get(`/${bucketName}?tagging`, { responseType: 'text' });
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(res.data, "text/xml");
        const tags: Record<string, string> = {};
        const tagNodes = xmlDoc.getElementsByTagName("Tag");
        for (let i = 0; i < tagNodes.length; i++) {
            const node = tagNodes.item(i);
            if (!node) continue;
            const key = node.getElementsByTagName("Key")[0]?.textContent;
            const value = node.getElementsByTagName("Value")[0]?.textContent;
            if (key) tags[key] = value || '';
        }
        return tags;
    } catch (e: any) {
        if (e.response?.status === 404) {
            return {};
        }
        throw e;
    }
};

export const putBucketTags = async (bucketName: string, tags: Record<string, string>) => {
    const tagEntries = Object.entries(tags).map(([key, value]) =>
        `<Tag><Key>${key}</Key><Value>${value}</Value></Tag>`
    ).join('');
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<Tagging xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <TagSet>${tagEntries}</TagSet>
</Tagging>`;
    return s3Api.put(`/${bucketName}?tagging`, xml, {
        headers: { 'Content-Type': 'application/xml' }
    });
};

export const deleteBucketTags = async (bucketName: string) => {
    return s3Api.delete(`/${bucketName}?tagging`);
};

// ===== Lifecycle Rules =====
export interface LifecycleRule {
    id: string;
    prefix: string;
    status: 'Enabled' | 'Disabled';
    expirationDays?: number;
    noncurrentExpirationDays?: number;
    transitionDays?: number;
    transitionStorageClass?: string;
}

export const getBucketLifecycle = async (bucketName: string): Promise<LifecycleRule[]> => {
    try {
        const res = await s3Api.get(`/${bucketName}?lifecycle`, { responseType: 'text' });
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(res.data, "text/xml");
        const rules: LifecycleRule[] = [];
        const ruleNodes = xmlDoc.getElementsByTagName("Rule");
        for (let i = 0; i < ruleNodes.length; i++) {
            const node = ruleNodes.item(i);
            if (!node) continue;
            const id = node.getElementsByTagName("ID")[0]?.textContent || '';
            const prefix = node.getElementsByTagName("Prefix")[0]?.textContent || '';
            const status = node.getElementsByTagName("Status")[0]?.textContent as 'Enabled' | 'Disabled' || 'Disabled';
            const expirationDays = node.getElementsByTagName("Days")[0]?.textContent;
            const noncurrentDays = node.querySelector("NoncurrentVersionExpiration > NoncurrentDays")?.textContent;
            rules.push({
                id,
                prefix,
                status,
                expirationDays: expirationDays ? parseInt(expirationDays) : undefined,
                noncurrentExpirationDays: noncurrentDays ? parseInt(noncurrentDays) : undefined
            });
        }
        return rules;
    } catch (e: any) {
        if (e.response?.status === 404) {
            return [];
        }
        throw e;
    }
};

export const putBucketLifecycle = async (bucketName: string, rules: LifecycleRule[]) => {
    const rulesXml = rules.map(rule => {
        let ruleContent = `<ID>${rule.id}</ID>`;
        ruleContent += `<Filter><Prefix>${rule.prefix}</Prefix></Filter>`;
        ruleContent += `<Status>${rule.status}</Status>`;
        if (rule.expirationDays) {
            ruleContent += `<Expiration><Days>${rule.expirationDays}</Days></Expiration>`;
        }
        if (rule.noncurrentExpirationDays) {
            ruleContent += `<NoncurrentVersionExpiration><NoncurrentDays>${rule.noncurrentExpirationDays}</NoncurrentDays></NoncurrentVersionExpiration>`;
        }
        return `<Rule>${ruleContent}</Rule>`;
    }).join('');

    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<LifecycleConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
${rulesXml}
</LifecycleConfiguration>`;
    return s3Api.put(`/${bucketName}?lifecycle`, xml, {
        headers: { 'Content-Type': 'application/xml' }
    });
};

export const deleteBucketLifecycle = async (bucketName: string) => {
    return s3Api.delete(`/${bucketName}?lifecycle`);
};

// ===== Bucket Notifications =====
export interface NotificationConfig {
    id: string;
    events: string[];
    queueArn?: string;
    topicArn?: string;
    lambdaArn?: string;
    prefix?: string;
    suffix?: string;
}

export const getBucketNotifications = async (bucketName: string): Promise<NotificationConfig[]> => {
    try {
        const res = await s3Api.get(`/${bucketName}?notification`, { responseType: 'text' });
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(res.data, "text/xml");
        const configs: NotificationConfig[] = [];

        // Queue configurations
        const queueNodes = xmlDoc.getElementsByTagName("QueueConfiguration");
        for (let i = 0; i < queueNodes.length; i++) {
            const node = queueNodes.item(i);
            if (!node) continue;
            const id = node.getElementsByTagName("Id")[0]?.textContent || `queue-${i}`;
            const queueArn = node.getElementsByTagName("Queue")[0]?.textContent;
            const events: string[] = [];
            const eventNodes = node.getElementsByTagName("Event");
            for (let j = 0; j < eventNodes.length; j++) {
                events.push(eventNodes[j]?.textContent || '');
            }
            configs.push({ id, events, queueArn });
        }

        // Topic configurations
        const topicNodes = xmlDoc.getElementsByTagName("TopicConfiguration");
        for (let i = 0; i < topicNodes.length; i++) {
            const node = topicNodes.item(i);
            if (!node) continue;
            const id = node.getElementsByTagName("Id")[0]?.textContent || `topic-${i}`;
            const topicArn = node.getElementsByTagName("Topic")[0]?.textContent;
            const events: string[] = [];
            const eventNodes = node.getElementsByTagName("Event");
            for (let j = 0; j < eventNodes.length; j++) {
                events.push(eventNodes[j]?.textContent || '');
            }
            configs.push({ id, events, topicArn });
        }

        return configs;
    } catch (e: any) {
        if (e.response?.status === 404) {
            return [];
        }
        throw e;
    }
};

// ===== Bucket Replication =====
export interface ReplicationRule {
    id: string;
    status: 'Enabled' | 'Disabled';
    priority?: number;
    prefix?: string;
    destination: string;
}

export const getBucketReplication = async (bucketName: string): Promise<{ role: string; rules: ReplicationRule[] }> => {
    try {
        const res = await s3Api.get(`/${bucketName}?replication`, { responseType: 'text' });
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(res.data, "text/xml");
        const role = xmlDoc.getElementsByTagName("Role")[0]?.textContent || '';
        const rules: ReplicationRule[] = [];
        const ruleNodes = xmlDoc.getElementsByTagName("Rule");
        for (let i = 0; i < ruleNodes.length; i++) {
            const node = ruleNodes.item(i);
            if (!node) continue;
            rules.push({
                id: node.getElementsByTagName("ID")[0]?.textContent || '',
                status: (node.getElementsByTagName("Status")[0]?.textContent as 'Enabled' | 'Disabled') || 'Disabled',
                priority: parseInt(node.getElementsByTagName("Priority")[0]?.textContent || '0'),
                prefix: node.getElementsByTagName("Prefix")[0]?.textContent || '',
                destination: node.getElementsByTagName("Bucket")[0]?.textContent || ''
            });
        }
        return { role, rules };
    } catch (e: any) {
        if (e.response?.status === 404) {
            return { role: '', rules: [] };
        }
        throw e;
    }
};

// ===== Bucket Usage Statistics =====
export const getBucketUsage = async (bucketName: string): Promise<{ objectCount: number; size: number }> => {
    try {
        // First try to get from admin API
        const res = await api.get(`/buckets/${bucketName}/usage`);
        if (res.data && (res.data.objectCount > 0 || res.data.size > 0)) {
            return res.data;
        }
    } catch {
        // Admin API not available, fall through to S3 calculation
    }

    // Fallback: calculate by listing all objects (may be slow for large buckets)
    try {
        let objectCount = 0;
        let totalSize = 0;
        let continuationToken: string | undefined;

        // Limit iterations to prevent hanging on very large buckets
        const maxIterations = 10; // 10 * 1000 = max 10,000 objects
        let iteration = 0;

        do {
            const params: Record<string, any> = { 'list-type': 2, 'max-keys': 1000 };
            if (continuationToken) {
                params['continuation-token'] = continuationToken;
            }

            const res = await s3Api.get(`/${bucketName}`, {
                responseType: 'text',
                params
            });

            const parser = new DOMParser();
            const xmlDoc = parser.parseFromString(res.data, "text/xml");

            // Count objects and sum sizes
            const contents = xmlDoc.getElementsByTagName("Contents");
            for (let i = 0; i < contents.length; i++) {
                const node = contents.item(i);
                if (!node) continue;
                const sizeStr = node.getElementsByTagName("Size")[0]?.textContent;
                if (sizeStr) {
                    totalSize += parseInt(sizeStr);
                }
                objectCount++;
            }

            // Check for more pages
            const isTruncated = xmlDoc.getElementsByTagName("IsTruncated")[0]?.textContent === 'true';
            continuationToken = isTruncated
                ? xmlDoc.getElementsByTagName("NextContinuationToken")[0]?.textContent || undefined
                : undefined;

            iteration++;
        } while (continuationToken && iteration < maxIterations);

        return { objectCount, size: totalSize };
    } catch {
        return { objectCount: 0, size: 0 };
    }
};
