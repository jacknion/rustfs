<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Storage</a-breadcrumb-item>
            <a-breadcrumb-item>Buckets</a-breadcrumb-item>
        </template>

        <template #header>
            <a-space>
                <a-input-search
                    v-model:value="searchText"
                    placeholder="Search buckets..."
                    style="width: 250px;"
                    allow-clear
                />
                <a-button type="primary" @click="showCreate">Create Bucket</a-button>
            </a-space>
        </template>

        <a-table :columns="columns" :data-source="filteredBuckets" :loading="loading" row-key="name">
             <template #bodyCell="{ column, record }">
                 <template v-if="column.key === 'creationDate'">
                     {{ new Date(record.creationDate).toLocaleString() }}
                 </template>
                 <template v-if="column.key === 'objectCount'">
                     <a-spin v-if="record.usageLoading" size="small" />
                     <span v-else>{{ record.objectCount ?? '-' }}</span>
                 </template>
                 <template v-if="column.key === 'size'">
                     <a-spin v-if="record.usageLoading" size="small" />
                     <span v-else>{{ formatSize(record.size) }}</span>
                 </template>
                 <template v-if="column.key === 'action'">
                      <a-space>
                          <router-link :to="{ name: 'ObjectBrowser', params: { name: record.name } }">
                              <a-button type="link" size="small">Browse</a-button>
                          </router-link>
                          <a-button type="link" size="small" @click="openSettings(record.name)">Settings</a-button>
                          <a-popconfirm title="Delete bucket?" @confirm="handleDelete(record.name)">
                              <a-button type="link" danger size="small">Delete</a-button>
                          </a-popconfirm>
                      </a-space>
                 </template>
             </template>
        </a-table>

        <a-modal v-model:open="visible" title="Create Bucket" @ok="handleCreate">
            <a-form layout="vertical">
                <a-form-item label="Bucket Name" required>
                    <a-input v-model:value="newBucketName" />
                </a-form-item>
            </a-form>
        </a-modal>

        <BucketSettingsModal 
            v-model:open="settingsVisible" 
            :bucket-name="selectedBucket" 
        />
  </PageContainer>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import * as bucketApi from '@/api/s3/bucket';
import PageContainer from '@/components/layout/PageContainer.vue';
import BucketSettingsModal from '@/components/storage/BucketSettingsModal.vue';

interface BucketItem {
    name: string;
    creationDate: string;
    objectCount?: number;
    size?: number;
    usageLoading?: boolean;
}

const loading = ref(false);
const buckets = ref<BucketItem[]>([]);
const visible = ref(false);
const newBucketName = ref('');
const searchText = ref('');

// Settings modal
const settingsVisible = ref(false);
const selectedBucket = ref('');

const columns = [
    { title: 'Name', dataIndex: 'name', key: 'name' },
    { title: 'Objects', key: 'objectCount', width: 100 },
    { title: 'Size', key: 'size', width: 100 },
    { title: 'Creation Date', dataIndex: 'creationDate', key: 'creationDate' },
    { title: 'Action', key: 'action', width: 220 }
];

const filteredBuckets = computed(() => {
    if (!searchText.value) return buckets.value;
    const search = searchText.value.toLowerCase();
    return buckets.value.filter(b => b.name.toLowerCase().includes(search));
});

const formatSize = (bytes?: number) => {
    if (bytes === undefined || bytes === 0) return '-';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};

const fetchBuckets = async () => {
    loading.value = true;
    try {
        const list = await bucketApi.listBuckets();
        buckets.value = list.map(b => ({ ...b, usageLoading: true }));
        
        // Fetch usage for each bucket in background
        for (const bucket of buckets.value) {
            fetchBucketUsage(bucket);
        }
    } catch (error) {
        message.error('Failed to fetch buckets');
    } finally {
        loading.value = false;
    }
};

const fetchBucketUsage = async (bucket: BucketItem) => {
    try {
        const usage = await bucketApi.getBucketUsage(bucket.name);
        bucket.objectCount = usage.objectCount;
        bucket.size = usage.size;
    } catch (e) {
        bucket.objectCount = 0;
        bucket.size = 0;
    } finally {
        bucket.usageLoading = false;
    }
};

const handleDelete = async (name: string) => {
    try {
        await bucketApi.deleteBucket(name);
        message.success('Bucket deleted');
        fetchBuckets();
    } catch (e) {
        message.error('Delete failed');
    }
};

const showCreate = () => {
    newBucketName.value = '';
    visible.value = true;
};

const handleCreate = async () => {
    if (!newBucketName.value) return;
    try {
        await bucketApi.createBucket(newBucketName.value);
        message.success('Bucket created');
        visible.value = false;
        fetchBuckets();
    } catch (e) {
        message.error('Create failed');
    }
};

const openSettings = (name: string) => {
    selectedBucket.value = name;
    settingsVisible.value = true;
};

onMounted(() => {
    fetchBuckets();
});
</script>

