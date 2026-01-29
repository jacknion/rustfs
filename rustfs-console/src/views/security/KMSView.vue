<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Security</a-breadcrumb-item>
            <a-breadcrumb-item>KMS</a-breadcrumb-item>
        </template>

        <template #header>
            <a-space>
                <a-button type="primary" @click="showCreateModal">Create Key</a-button>
                <a-button type="default" @click="fetchData" :loading="loading">
                    <template #icon><ReloadOutlined /></template>
                    Refresh
                </a-button>
            </a-space>
        </template>

        <a-spin :spinning="loading">
            <!-- KMS Status -->
            <a-card title="KMS Status" class="mb-4">
                <a-row :gutter="16" v-if="status">
                    <a-col :span="6">
                        <a-statistic title="KMS Name" :value="status.name || 'N/A'" />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic title="Default Key ID" :value="status.defaultKeyID || 'N/A'" />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic 
                            title="Endpoints" 
                            :value="status.endpoints?.length || 0" 
                        />
                    </a-col>
                    <a-col :span="6">
                        <a-tag v-if="status.endpoints?.some(e => e.status === 'online')" color="green">Online</a-tag>
                        <a-tag v-else color="red">Offline</a-tag>
                    </a-col>
                </a-row>
                <a-empty v-else description="KMS not configured or unavailable" />
            </a-card>

            <!-- KMS Keys -->
            <a-card title="Encryption Keys">
                <a-table 
                    :columns="keyColumns" 
                    :data-source="keys" 
                    row-key="name"
                    :loading="loading"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'createdAt'">
                            {{ formatDate(record.createdAt) }}
                        </template>
                        <template v-if="column.key === 'actions'">
                            <a-popconfirm 
                                title="Delete this key? This action cannot be undone."
                                @confirm="deleteKey(record.name)"
                            >
                                <a-button type="link" danger size="small">Delete</a-button>
                            </a-popconfirm>
                        </template>
                    </template>
                </a-table>
            </a-card>

            <!-- KMS Metrics -->
            <a-card title="KMS Metrics" class="mt-4" v-if="metrics">
                <a-row :gutter="16">
                    <a-col :span="4">
                        <a-statistic title="Requests OK" :value="metrics.requestOK" :value-style="{ color: '#3f8600' }" />
                    </a-col>
                    <a-col :span="4">
                        <a-statistic title="Requests Error" :value="metrics.requestErr" :value-style="{ color: '#cf1322' }" />
                    </a-col>
                    <a-col :span="4">
                        <a-statistic title="Request Failed" :value="metrics.requestFail" />
                    </a-col>
                    <a-col :span="4">
                        <a-statistic title="Active Requests" :value="metrics.requestActive" />
                    </a-col>
                    <a-col :span="4">
                        <a-statistic title="Uptime" :value="formatUptime(metrics.uptime)" />
                    </a-col>
                    <a-col :span="4">
                        <a-statistic title="Heap Alloc" :value="formatBytes(metrics.heapAlloc)" />
                    </a-col>
                </a-row>
            </a-card>
        </a-spin>

        <!-- Create Key Modal -->
        <a-modal 
            v-model:open="createVisible" 
            title="Create Encryption Key" 
            @ok="handleCreate"
            :confirm-loading="createLoading"
        >
            <a-form layout="vertical">
                <a-form-item label="Key ID" required>
                    <a-input v-model:value="createForm.keyId" placeholder="my-encryption-key" />
                </a-form-item>
            </a-form>
        </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as kmsApi from '@/api/modules/kms';
import type { KMSStatus, KMSKeyInfo, KMSMetrics } from '@/api/modules/kms';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const createVisible = ref(false);
const createLoading = ref(false);
const status = ref<KMSStatus | null>(null);
const keys = ref<KMSKeyInfo[]>([]);
const metrics = ref<KMSMetrics | null>(null);

const createForm = reactive({
    keyId: ''
});

const keyColumns = [
    { title: 'Key Name', dataIndex: 'name', key: 'name' },
    { title: 'Created At', key: 'createdAt' },
    { title: 'Created By', dataIndex: 'createdBy', key: 'createdBy' },
    { title: 'Actions', key: 'actions', width: 100 }
];

const fetchData = async () => {
    loading.value = true;
    try {
        const [statusRes, keysRes, metricsRes] = await Promise.allSettled([
            kmsApi.getKMSStatus(),
            kmsApi.listKMSKeys(),
            kmsApi.getKMSMetrics()
        ]);
        
        if (statusRes.status === 'fulfilled') {
            const data = statusRes.value.data || {};
            status.value = {
                name: data.name || data.Name || '',
                defaultKeyID: data.defaultKeyID || data.DefaultKeyID || '',
                endpoints: (data.endpoints || data.Endpoints || []).map((e: any) => ({
                    endpoint: e.endpoint || e.Endpoint || '',
                    status: (e.status || e.Status || 'offline').toLowerCase(),
                }))
            };
        }
        if (keysRes.status === 'fulfilled') {
            const data = keysRes.value.data || {};
            const keyList = data.keys || data.Keys || [];
            keys.value = keyList.map((k: any) => ({
                name: k.name || k.Name || '',
                createdAt: k.createdAt || k.CreatedAt || k.created_at || '',
                createdBy: k.createdBy || k.CreatedBy || k.created_by || '',
            }));
        }
        if (metricsRes.status === 'fulfilled') {
            const data = metricsRes.value.data || {};
            metrics.value = {
                requestOK: data.requestOK ?? data.RequestOK ?? 0,
                requestErr: data.requestErr ?? data.RequestErr ?? 0,
                requestFail: data.requestFail ?? data.RequestFail ?? 0,
                requestActive: data.requestActive ?? data.RequestActive ?? 0,
                uptime: data.uptime ?? data.Uptime ?? 0,
                heapAlloc: data.heapAlloc ?? data.HeapAlloc ?? 0,
            };
        }
    } catch (error) {
        console.error('Failed to fetch KMS data', error);
    } finally {
        loading.value = false;
    }
};

const showCreateModal = () => {
    createForm.keyId = '';
    createVisible.value = true;
};

const handleCreate = async () => {
    if (!createForm.keyId) {
        message.error('Please enter a key ID');
        return;
    }
    createLoading.value = true;
    try {
        await kmsApi.createKMSKey(createForm.keyId);
        message.success('Key created successfully');
        createVisible.value = false;
        fetchData();
    } catch (error) {
        message.error('Failed to create key');
        console.error(error);
    } finally {
        createLoading.value = false;
    }
};

const deleteKey = async (keyId: string) => {
    try {
        await kmsApi.deleteKMSKey(keyId);
        message.success('Key deleted');
        fetchData();
    } catch (error) {
        message.error('Failed to delete key');
        console.error(error);
    }
};

const formatDate = (dateStr: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
};

const formatUptime = (seconds: number) => {
    if (!seconds) return 'N/A';
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    if (days > 0) return `${days}d ${hours}h`;
    return `${hours}h`;
};

const formatBytes = (bytes: number) => {
    if (!bytes) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

onMounted(() => {
    fetchData();
});
</script>

<style scoped>
.mb-4 { margin-bottom: 16px; }
.mt-4 { margin-top: 16px; }
</style>
