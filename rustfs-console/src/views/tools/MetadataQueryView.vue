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
        </template>

        <!-- Query Form -->
        <a-card title="Query Parameters" class="mb-4">
            <a-form layout="vertical">
                <a-row :gutter="16">
                    <a-col :span="16">
                        <a-form-item label="Query Expression" required>
                            <a-input 
                                v-model:value="queryForm.query" 
                                placeholder='e.g., SELECT * FROM s3object WHERE size > 1000'
                            />
                            <template #extra>
                                <a-typography-text type="secondary">
                                    Use SQL-like syntax to query object metadata
                                </a-typography-text>
                            </template>
                        </a-form-item>
                    </a-col>
                    <a-col :span="8">
                        <a-form-item label="Bucket">
                            <a-input 
                                v-model:value="queryForm.bucket" 
                                placeholder="Optional bucket filter"
                            />
                        </a-form-item>
                    </a-col>
                </a-row>
                <a-row :gutter="16">
                    <a-col :span="8">
                        <a-form-item label="Max Results">
                            <a-input-number 
                                v-model:value="queryForm.maxResults" 
                                :min="1" 
                                :max="1000" 
                                style="width: 100%"
                            />
                        </a-form-item>
                    </a-col>
                    <a-col :span="8">
                        <a-form-item>
                            <a-checkbox v-model:checked="queryForm.recursive">
                                Recursive Search
                            </a-checkbox>
                        </a-form-item>
                    </a-col>
                </a-row>
            </a-form>
        </a-card>

        <!-- Results -->
        <a-card title="Query Results">
            <a-table 
                :columns="columns" 
                :data-source="results" 
                row-key="key"
                :loading="loading"
                :scroll="{ x: 1200 }"
                :pagination="{ pageSize: 20 }"
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
            width="600px"
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
            <a-descriptions :column="1" bordered size="small" v-if="selectedObject?.userMetadata">
                <a-descriptions-item 
                    v-for="(value, key) in selectedObject.userMetadata" 
                    :key="key" 
                    :label="key"
                >
                    {{ value }}
                </a-descriptions-item>
            </a-descriptions>

            <a-divider v-if="selectedObject?.tags && Object.keys(selectedObject.tags).length > 0">
                Object Tags
            </a-divider>
            <a-space wrap v-if="selectedObject?.tags">
                <a-tag v-for="(value, key) in selectedObject.tags" :key="key">
                    {{ key }}={{ value }}
                </a-tag>
            </a-space>
        </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue';
import { message } from 'ant-design-vue';
import { SearchOutlined } from '@ant-design/icons-vue';
import * as metadataApi from '@/api/modules/metadata';
import type { ObjectMetadata } from '@/api/modules/metadata';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const detailsVisible = ref(false);
const results = ref<ObjectMetadata[]>([]);
const selectedObject = ref<ObjectMetadata | null>(null);
const nextMarker = ref<string | undefined>(undefined);

const queryForm = reactive({
    query: '',
    bucket: '',
    recursive: true,
    maxResults: 100
});

const columns = [
    { title: 'Bucket', dataIndex: 'bucket', key: 'bucket', width: 150 },
    { title: 'Key', dataIndex: 'key', key: 'key', ellipsis: true },
    { title: 'Size', key: 'size', width: 100 },
    { title: 'Content Type', dataIndex: 'contentType', key: 'contentType', width: 150 },
    { title: 'Last Modified', key: 'lastModified', width: 180 },
    { title: 'Metadata', key: 'userMetadata', width: 100 },
    { title: 'Actions', key: 'actions', width: 80 }
];

const executeQuery = async () => {
    if (!queryForm.query) {
        message.warning('Please enter a query expression');
        return;
    }
    loading.value = true;
    nextMarker.value = undefined;
    try {
        const res = await metadataApi.queryMetadata({
            query: queryForm.query,
            bucket: queryForm.bucket || undefined,
            recursive: queryForm.recursive,
            maxResults: queryForm.maxResults
        });
        results.value = res.data.objects || [];
        nextMarker.value = res.data.isTruncated ? res.data.nextMarker : undefined;
    } catch (error) {
        message.error('Query failed');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const loadMore = async () => {
    if (!nextMarker.value) return;
    loading.value = true;
    try {
        const res = await metadataApi.queryMetadata({
            query: queryForm.query,
            bucket: queryForm.bucket || undefined,
            recursive: queryForm.recursive,
            maxResults: queryForm.maxResults,
            marker: nextMarker.value
        });
        results.value = [...results.value, ...(res.data.objects || [])];
        nextMarker.value = res.data.isTruncated ? res.data.nextMarker : undefined;
    } catch (error) {
        message.error('Failed to load more results');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const viewDetails = (obj: ObjectMetadata) => {
    selectedObject.value = obj;
    detailsVisible.value = true;
};

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
</style>
