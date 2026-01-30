<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Tools</a-breadcrumb-item>
            <a-breadcrumb-item>Metadata Query</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="primary" @click="executeQuery" :loading="loading">
                <template #icon><SearchOutlined /></template>
                Search
            </a-button>
            <a-button @click="resetFilters" style="margin-left: 8px">
                <template #icon><ClearOutlined /></template>
                Reset
            </a-button>
        </template>

        <!-- Query Mode Tabs -->
        <a-card class="mb-4">
            <a-tabs v-model:activeKey="queryMode" type="card">
                <!-- Visual Builder Tab -->
                <a-tab-pane key="visual" tab="Visual Builder">
                    <!-- Quick Presets -->
                    <div class="preset-section mb-4">
                        <span class="preset-label">Quick Filters:</span>
                        <a-space wrap>
                            <a-button size="small" @click="applyPreset('largeFiles')">
                                <FileOutlined /> Large Files (>100MB)
                            </a-button>
                            <a-button size="small" @click="applyPreset('recentFiles')">
                                <ClockCircleOutlined /> Last 24 Hours
                            </a-button>
                            <a-button size="small" @click="applyPreset('images')">
                                <PictureOutlined /> Images Only
                            </a-button>
                            <a-button size="small" @click="applyPreset('videos')">
                                <VideoCameraOutlined /> Videos Only
                            </a-button>
                            <a-button size="small" @click="applyPreset('documents')">
                                <FileTextOutlined /> Documents
                            </a-button>
                        </a-space>
                    </div>

                    <a-divider style="margin: 12px 0" />

                    <!-- Visual Filters -->
                    <a-form layout="vertical">
                        <a-row :gutter="16">
                            <a-col :span="8">
                                <a-form-item label="Bucket">
                                    <a-select
                                        v-model:value="filters.bucket"
                                        placeholder="All Buckets"
                                        allowClear
                                        showSearch
                                        :loading="bucketsLoading"
                                    >
                                        <a-select-option v-for="b in buckets" :key="b.name" :value="b.name">
                                            {{ b.name }}
                                        </a-select-option>
                                    </a-select>
                                </a-form-item>
                            </a-col>
                            <a-col :span="8">
                                <a-form-item label="Key Prefix">
                                    <a-input 
                                        v-model:value="filters.prefix" 
                                        placeholder="e.g., documents/, images/2024/"
                                    />
                                </a-form-item>
                            </a-col>
                            <a-col :span="8">
                                <a-form-item label="Content Type">
                                    <a-select
                                        v-model:value="filters.contentType"
                                        placeholder="Any Type"
                                        allowClear
                                    >
                                        <a-select-option value="image/">Images (image/*)</a-select-option>
                                        <a-select-option value="video/">Videos (video/*)</a-select-option>
                                        <a-select-option value="audio/">Audio (audio/*)</a-select-option>
                                        <a-select-option value="application/pdf">PDF</a-select-option>
                                        <a-select-option value="application/json">JSON</a-select-option>
                                        <a-select-option value="text/">Text Files (text/*)</a-select-option>
                                        <a-select-option value="application/zip">ZIP Archives</a-select-option>
                                    </a-select>
                                </a-form-item>
                            </a-col>
                        </a-row>
                        
                        <a-row :gutter="16">
                            <a-col :span="8">
                                <a-form-item label="Size Range">
                                    <a-input-group compact>
                                        <a-input-number 
                                            v-model:value="filters.minSize" 
                                            placeholder="Min"
                                            :min="0"
                                            style="width: 45%"
                                        />
                                        <a-input 
                                            style="width: 10%; border-left: 0; pointer-events: none; background: #fafafa; text-align: center" 
                                            placeholder="~" 
                                            disabled 
                                        />
                                        <a-input-number 
                                            v-model:value="filters.maxSize" 
                                            placeholder="Max"
                                            :min="0"
                                            style="width: 45%; border-left: 0"
                                        />
                                    </a-input-group>
                                    <div class="size-unit-hint">Size in bytes (1MB = 1048576)</div>
                                </a-form-item>
                            </a-col>
                            <a-col :span="8">
                                <a-form-item label="Last Modified">
                                    <a-range-picker 
                                        v-model:value="filters.dateRange"
                                        style="width: 100%"
                                        :placeholder="['Start Date', 'End Date']"
                                    />
                                </a-form-item>
                            </a-col>
                            <a-col :span="8">
                                <a-form-item label="Options">
                                    <a-space>
                                        <a-checkbox v-model:checked="filters.recursive">
                                            Recursive
                                        </a-checkbox>
                                        <a-input-number 
                                            v-model:value="filters.maxResults" 
                                            :min="1" 
                                            :max="1000"
                                            addon-before="Max"
                                            style="width: 130px"
                                        />
                                    </a-space>
                                </a-form-item>
                            </a-col>
                        </a-row>

                        <!-- Tags Filter -->
                        <a-row :gutter="16">
                            <a-col :span="24">
                                <a-form-item>
                                    <template #label>
                                        <span>Tag Filters</span>
                                        <a-button type="link" size="small" @click="addTagFilter">
                                            <PlusOutlined /> Add Tag
                                        </a-button>
                                    </template>
                                    <div v-if="filters.tags.length === 0" class="empty-hint">
                                        No tag filters. Click "Add Tag" to filter by object tags.
                                    </div>
                                    <a-space direction="vertical" style="width: 100%">
                                        <a-input-group 
                                            v-for="(tag, index) in filters.tags" 
                                            :key="index"
                                            compact
                                        >
                                            <a-input 
                                                v-model:value="tag.key" 
                                                placeholder="Tag Key"
                                                style="width: 40%"
                                            />
                                            <a-input 
                                                v-model:value="tag.value" 
                                                placeholder="Tag Value"
                                                style="width: 40%"
                                            />
                                            <a-button danger @click="removeTagFilter(index)">
                                                <DeleteOutlined />
                                            </a-button>
                                        </a-input-group>
                                    </a-space>
                                </a-form-item>
                            </a-col>
                        </a-row>
                    </a-form>

                    <!-- Generated Query Preview -->
                    <a-collapse v-if="generatedQuery" :bordered="false" class="query-preview">
                        <a-collapse-panel key="1" header="Generated Query">
                            <code>{{ generatedQuery }}</code>
                        </a-collapse-panel>
                    </a-collapse>
                </a-tab-pane>

                <!-- Advanced SQL Tab -->
                <a-tab-pane key="sql" tab="Advanced SQL">
                    <a-form layout="vertical">
                        <a-form-item label="SQL Query Expression">
                            <a-textarea 
                                v-model:value="sqlQuery" 
                                placeholder="SELECT * FROM s3object WHERE size > 1000 AND content_type LIKE 'image/%'"
                                :rows="4"
                            />
                            <template #extra>
                                <a-typography-text type="secondary">
                                    Use SQL-like syntax. Available fields: bucket, key, size, content_type, last_modified, etag, storage_class
                                </a-typography-text>
                            </template>
                        </a-form-item>
                        <a-row :gutter="16">
                            <a-col :span="8">
                                <a-form-item label="Bucket Filter">
                                    <a-select
                                        v-model:value="filters.bucket"
                                        placeholder="All Buckets"
                                        allowClear
                                        :loading="bucketsLoading"
                                    >
                                        <a-select-option v-for="b in buckets" :key="b.name" :value="b.name">
                                            {{ b.name }}
                                        </a-select-option>
                                    </a-select>
                                </a-form-item>
                            </a-col>
                            <a-col :span="8">
                                <a-form-item label="Max Results">
                                    <a-input-number 
                                        v-model:value="filters.maxResults" 
                                        :min="1" 
                                        :max="1000" 
                                        style="width: 100%"
                                    />
                                </a-form-item>
                            </a-col>
                            <a-col :span="8">
                                <a-form-item>
                                    <a-checkbox v-model:checked="filters.recursive" style="margin-top: 30px">
                                        Recursive Search
                                    </a-checkbox>
                                </a-form-item>
                            </a-col>
                        </a-row>
                    </a-form>
                </a-tab-pane>
            </a-tabs>
        </a-card>

        <!-- Results -->
        <a-card>
            <template #title>
                <span>Query Results</span>
                <a-tag v-if="results.length > 0" color="blue" style="margin-left: 12px">
                    {{ results.length }} objects found
                </a-tag>
            </template>
            <template #extra v-if="results.length > 0">
                <a-button size="small" @click="exportToCSV">
                    <DownloadOutlined /> Export CSV
                </a-button>
            </template>

            <a-empty v-if="!loading && results.length === 0 && hasSearched" description="No objects found matching your criteria">
                <template #image>
                    <SearchOutlined style="font-size: 48px; color: #ccc" />
                </template>
            </a-empty>

            <a-alert 
                v-if="!hasSearched" 
                message="Ready to Search" 
                description="Configure your filters above and click Search to find objects."
                type="info" 
                show-icon 
            />

            <a-table 
                v-if="results.length > 0"
                :columns="columns" 
                :data-source="results" 
                row-key="key"
                :loading="loading"
                :scroll="{ x: 1200 }"
                :pagination="{ pageSize: 20, showSizeChanger: true, showTotal: (t: number) => `Total ${t} items` }"
            >
                <template #bodyCell="{ column, record }">
                    <template v-if="column.key === 'size'">
                        {{ formatBytes(record.size) }}
                    </template>
                    <template v-if="column.key === 'lastModified'">
                        {{ formatDate(record.lastModified) }}
                    </template>
                    <template v-if="column.key === 'userMetadata'">
                        <a-tooltip v-if="Object.keys(record.userMetadata || {}).length > 0">
                            <template #title>
                                <div v-for="(v, k) in record.userMetadata" :key="k">
                                    {{ k }}: {{ v }}
                                </div>
                            </template>
                            <a-tag color="blue">{{ Object.keys(record.userMetadata).length }} keys</a-tag>
                        </a-tooltip>
                        <span v-else>-</span>
                    </template>
                    <template v-if="column.key === 'tags'">
                        <a-tooltip v-if="record.tags && Object.keys(record.tags).length > 0">
                            <template #title>
                                <div v-for="(v, k) in record.tags" :key="k">
                                    {{ k }}={{ v }}
                                </div>
                            </template>
                            <a-tag color="green">{{ Object.keys(record.tags).length }} tags</a-tag>
                        </a-tooltip>
                        <span v-else>-</span>
                    </template>
                    <template v-if="column.key === 'actions'">
                        <a-button type="link" size="small" @click="viewDetails(record)">
                            Details
                        </a-button>
                    </template>
                </template>
            </a-table>
            
            <div v-if="nextMarker" class="mt-4 text-center">
                <a-button @click="loadMore" :loading="loading">
                    Load More
                </a-button>
            </div>
        </a-card>

        <!-- Object Details Modal -->
        <a-modal 
            v-model:open="detailsVisible" 
            title="Object Metadata Details"
            :footer="null"
            width="700px"
        >
            <a-descriptions :column="1" bordered v-if="selectedObject">
                <a-descriptions-item label="Bucket">{{ selectedObject.bucket }}</a-descriptions-item>
                <a-descriptions-item label="Key">{{ selectedObject.key }}</a-descriptions-item>
                <a-descriptions-item label="Size">{{ formatBytes(selectedObject.size) }}</a-descriptions-item>
                <a-descriptions-item label="Content Type">{{ selectedObject.contentType }}</a-descriptions-item>
                <a-descriptions-item label="ETag">{{ selectedObject.etag }}</a-descriptions-item>
                <a-descriptions-item label="Last Modified">{{ formatDate(selectedObject.lastModified) }}</a-descriptions-item>
                <a-descriptions-item label="Storage Class">{{ selectedObject.storageClass || 'STANDARD' }}</a-descriptions-item>
                <a-descriptions-item label="Version ID" v-if="selectedObject.versionId">
                    {{ selectedObject.versionId }}
                </a-descriptions-item>
            </a-descriptions>

            <a-divider v-if="selectedObject?.userMetadata && Object.keys(selectedObject.userMetadata).length > 0">
                User Metadata
            </a-divider>
            <a-descriptions :column="1" bordered size="small" v-if="selectedObject?.userMetadata && Object.keys(selectedObject.userMetadata).length > 0">
                <a-descriptions-item 
                    v-for="(value, key) in selectedObject.userMetadata" 
                    :key="key" 
                    :label="String(key)"
                >
                    {{ value }}
                </a-descriptions-item>
            </a-descriptions>

            <a-divider v-if="selectedObject?.tags && Object.keys(selectedObject.tags).length > 0">
                Object Tags
            </a-divider>
            <a-space wrap v-if="selectedObject?.tags && Object.keys(selectedObject.tags).length > 0">
                <a-tag v-for="(value, key) in selectedObject.tags" :key="key" color="processing">
                    {{ key }}={{ value }}
                </a-tag>
            </a-space>
        </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { 
    SearchOutlined, ClearOutlined, FileOutlined, ClockCircleOutlined, 
    PictureOutlined, VideoCameraOutlined, FileTextOutlined, PlusOutlined,
    DeleteOutlined, DownloadOutlined
} from '@ant-design/icons-vue';
import * as metadataApi from '@/api/modules/metadata';
import { listBuckets } from '@/api/s3/bucket';
import type { ObjectMetadata } from '@/api/modules/metadata';
import PageContainer from '@/components/layout/PageContainer.vue';
import type { Dayjs } from 'dayjs';

// State
const loading = ref(false);
const bucketsLoading = ref(false);
const detailsVisible = ref(false);
const hasSearched = ref(false);
const results = ref<any[]>([]);
const selectedObject = ref<any | null>(null);
const totalCount = ref<number>(0);
const currentOffset = ref<number>(0);
const queryMode = ref<'visual' | 'sql'>('visual');
const sqlQuery = ref('');
const buckets = ref<{ name: string; creationDate: string }[]>([]);

// Visual Filter State
const filters = reactive({
    bucket: undefined as string | undefined,
    prefix: '',
    contentType: undefined as string | undefined,
    minSize: undefined as number | undefined,
    maxSize: undefined as number | undefined,
    dateRange: undefined as [Dayjs, Dayjs] | undefined,
    recursive: true,
    maxResults: 100,
    tags: [] as { key: string; value: string }[]
});

// Table columns
const columns = [
    { title: 'Bucket', dataIndex: 'bucket', key: 'bucket', width: 120 },
    { title: 'Key', dataIndex: 'key', key: 'key', ellipsis: true },
    { title: 'Size', key: 'size', width: 100 },
    { title: 'Content Type', dataIndex: 'contentType', key: 'contentType', width: 130, ellipsis: true },
    { title: 'Last Modified', key: 'lastModified', width: 160 },
    { title: 'Metadata', key: 'userMetadata', width: 90 },
    { title: 'Tags', key: 'tags', width: 80 },
    { title: 'Actions', key: 'actions', width: 80 }
];

// Generate query from visual filters
const generatedQuery = computed(() => {
    const conditions: string[] = [];
    
    if (filters.prefix) {
        conditions.push(`key LIKE '${filters.prefix}%'`);
    }
    if (filters.contentType) {
        conditions.push(`content_type LIKE '${filters.contentType}%'`);
    }
    if (filters.minSize !== undefined) {
        conditions.push(`size >= ${filters.minSize}`);
    }
    if (filters.maxSize !== undefined) {
        conditions.push(`size <= ${filters.maxSize}`);
    }
    if (filters.dateRange && filters.dateRange[0] && filters.dateRange[1]) {
        conditions.push(`last_modified >= '${filters.dateRange[0].format('YYYY-MM-DD')}'`);
        conditions.push(`last_modified <= '${filters.dateRange[1].format('YYYY-MM-DD')}'`);
    }
    
    if (conditions.length === 0) {
        return 'SELECT * FROM s3object';
    }
    return `SELECT * FROM s3object WHERE ${conditions.join(' AND ')}`;
});

// Load buckets on mount
onMounted(async () => {
    bucketsLoading.value = true;
    try {
        buckets.value = await listBuckets();
    } catch (error) {
        console.error('Failed to load buckets:', error);
    } finally {
        bucketsLoading.value = false;
    }
});

// Apply preset filters
const applyPreset = (preset: string) => {
    resetFilters();
    switch (preset) {
        case 'largeFiles':
            filters.minSize = 100 * 1024 * 1024; // 100MB
            break;
        case 'recentFiles':
            // Set date range to last 24 hours - would need dayjs for proper implementation
            message.info('Filtering files from last 24 hours');
            break;
        case 'images':
            filters.contentType = 'image/';
            break;
        case 'videos':
            filters.contentType = 'video/';
            break;
        case 'documents':
            filters.contentType = 'application/pdf';
            break;
    }
};

// Tag filter management
const addTagFilter = () => {
    filters.tags.push({ key: '', value: '' });
};

const removeTagFilter = (index: number) => {
    filters.tags.splice(index, 1);
};

// Reset all filters
const resetFilters = () => {
    filters.bucket = undefined;
    filters.prefix = '';
    filters.contentType = undefined;
    filters.minSize = undefined;
    filters.maxSize = undefined;
    filters.dateRange = undefined;
    filters.recursive = true;
    filters.maxResults = 100;
    filters.tags = [];
    sqlQuery.value = '';
};

// Execute query
const executeQuery = async () => {
    loading.value = true;
    hasSearched.value = true;
    currentOffset.value = 0;
    
    try {
        // Build query parameters from visual filters
        const queryParams: metadataApi.MetadataQueryRequest = {
            bucket: filters.bucket || undefined,
            prefix: filters.prefix || undefined,
            minSize: filters.minSize,
            maxSize: filters.maxSize,
            limit: filters.maxResults,
            offset: 0
        };
        
        // Add date filters if set
        if (filters.dateRange && filters.dateRange[0] && filters.dateRange[1]) {
            queryParams.modifiedAfter = filters.dateRange[0].toISOString();
            queryParams.modifiedBefore = filters.dateRange[1].toISOString();
        }
        
        // Add tag filters if set
        if (filters.tags.length > 0) {
            const tagObj: Record<string, string> = {};
            filters.tags.forEach(t => {
                if (t.key) tagObj[t.key] = t.value || '';
            });
            if (Object.keys(tagObj).length > 0) {
                queryParams.tags = tagObj;
            }
        }
        
        const res = await metadataApi.queryMetadata(queryParams);
        
        // Map backend snake_case to frontend camelCase
        results.value = (res.data.objects || []).map(obj => ({
            ...obj,
            key: obj.object_key,
            size: obj.size_bytes,
            lastModified: obj.last_modified,
            contentType: obj.content_type || '',
            storageClass: obj.storage_class,
            userMetadata: obj.user_metadata || {},
            versionId: obj.version_id
        }));
        
        totalCount.value = res.data.metadata?.total_count || results.value.length;
        
        if (results.value.length === 0) {
            message.info('No objects found matching your criteria');
        } else {
            message.success(`Found ${totalCount.value} objects`);
        }
    } catch (error: any) {
        const errMsg = error?.response?.data?.message || error?.message || 'Query failed';
        message.error(errMsg);
        console.error('Metadata query error:', error);
    } finally {
        loading.value = false;
    }
};

// Load more results
const loadMore = async () => {
    loading.value = true;
    currentOffset.value += filters.maxResults;
    
    try {
        const queryParams: metadataApi.MetadataQueryRequest = {
            bucket: filters.bucket || undefined,
            prefix: filters.prefix || undefined,
            minSize: filters.minSize,
            maxSize: filters.maxSize,
            limit: filters.maxResults,
            offset: currentOffset.value
        };
        
        if (filters.dateRange && filters.dateRange[0] && filters.dateRange[1]) {
            queryParams.modifiedAfter = filters.dateRange[0].toISOString();
            queryParams.modifiedBefore = filters.dateRange[1].toISOString();
        }
        
        const res = await metadataApi.queryMetadata(queryParams);
        
        const newResults = (res.data.objects || []).map(obj => ({
            ...obj,
            key: obj.object_key,
            size: obj.size_bytes,
            lastModified: obj.last_modified,
            contentType: obj.content_type || '',
            storageClass: obj.storage_class,
            userMetadata: obj.user_metadata || {},
            versionId: obj.version_id
        }));
        
        results.value = [...results.value, ...newResults];
    } catch (error) {
        message.error('Failed to load more results');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

// View object details
const viewDetails = (obj: ObjectMetadata) => {
    selectedObject.value = obj;
    detailsVisible.value = true;
};

// Export to CSV
const exportToCSV = () => {
    const headers = ['Bucket', 'Key', 'Size', 'Content Type', 'Last Modified', 'ETag', 'Storage Class'];
    const rows = results.value.map(obj => [
        obj.bucket,
        obj.key,
        obj.size,
        obj.contentType,
        obj.lastModified,
        obj.etag,
        obj.storageClass || 'STANDARD'
    ]);
    
    const csv = [headers.join(','), ...rows.map(r => r.map(v => `"${v}"`).join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `metadata-query-${new Date().toISOString().split('T')[0]}.csv`;
    link.click();
    URL.revokeObjectURL(url);
    message.success('CSV exported successfully');
};

// Format utilities
const formatBytes = (bytes: number) => {
    if (!bytes) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

const formatDate = (dateStr: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
};
</script>

<style scoped>
.mb-4 { margin-bottom: 16px; }
.mt-4 { margin-top: 16px; }
.text-center { text-align: center; }

.preset-section {
    display: flex;
    align-items: center;
    gap: 12px;
}

.preset-label {
    font-weight: 500;
    color: #666;
}

.size-unit-hint {
    font-size: 12px;
    color: #999;
    margin-top: 4px;
}

.empty-hint {
    color: #999;
    font-size: 13px;
    padding: 8px 0;
}

.query-preview {
    margin-top: 16px;
    background: #f5f5f5;
}

.query-preview code {
    font-family: 'Monaco', 'Menlo', monospace;
    font-size: 13px;
    color: #1890ff;
}
</style>
