<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Settings</a-breadcrumb-item>
            <a-breadcrumb-item>Replication</a-breadcrumb-item>
        </template>

        <template #header>
            <a-space>
                <a-button type="primary" @click="showAddModal">Add Remote Target</a-button>
                <a-button type="default" @click="fetchTargets" :loading="loading">
                    <template #icon><ReloadOutlined /></template>
                    Refresh
                </a-button>
            </a-space>
        </template>

        <a-spin :spinning="loading">
            <a-alert 
                v-if="targets.length === 0 && !loading"
                type="info" 
                message="No Remote Targets Configured"
                description="Remote targets are used for bucket replication to remote RustFS or S3-compatible storage."
                show-icon
                class="mb-4"
            />

            <!-- Remote Targets Table -->
            <a-card title="Remote Replication Targets" v-if="targets.length > 0">
                <a-table 
                    :columns="columns" 
                    :data-source="targets" 
                    row-key="arn"
                    :scroll="{ x: 1000 }"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'type'">
                            <a-tag :color="record.type === 'replication' ? 'blue' : 'orange'">
                                {{ record.type }}
                            </a-tag>
                        </template>
                        <template v-if="column.key === 'secure'">
                            <a-tag :color="record.secure ? 'green' : 'default'">
                                {{ record.secure ? 'TLS' : 'Plain' }}
                            </a-tag>
                        </template>
                        <template v-if="column.key === 'bandwidth'">
                            {{ record.bandwidth ? formatBandwidth(record.bandwidth) : 'Unlimited' }}
                        </template>
                        <template v-if="column.key === 'actions'">
                            <a-popconfirm 
                                title="Remove this remote target?"
                                @confirm="removeTarget(record.arn)"
                            >
                                <a-button type="link" danger size="small">Remove</a-button>
                            </a-popconfirm>
                        </template>
                    </template>
                </a-table>
            </a-card>
        </a-spin>

        <!-- Add Remote Target Modal -->
        <a-modal 
            v-model:open="addVisible" 
            title="Add Remote Target" 
            @ok="handleAdd"
            :confirm-loading="addLoading"
            width="600px"
        >
            <a-form layout="vertical">
                <a-row :gutter="16">
                    <a-col :span="12">
                        <a-form-item label="Source Bucket" required>
                            <a-input v-model:value="addForm.bucket" placeholder="my-bucket" />
                        </a-form-item>
                    </a-col>
                    <a-col :span="12">
                        <a-form-item label="Target Bucket" required>
                            <a-input v-model:value="addForm.targetBucket" placeholder="target-bucket" />
                        </a-form-item>
                    </a-col>
                </a-row>
                
                <a-form-item label="Remote Endpoint" required>
                    <a-input v-model:value="addForm.endpoint" placeholder="https://remote-server:9000" />
                </a-form-item>
                
                <a-row :gutter="16">
                    <a-col :span="12">
                        <a-form-item label="Access Key" required>
                            <a-input v-model:value="addForm.accessKey" />
                        </a-form-item>
                    </a-col>
                    <a-col :span="12">
                        <a-form-item label="Secret Key" required>
                            <a-input-password v-model:value="addForm.secretKey" />
                        </a-form-item>
                    </a-col>
                </a-row>

                <a-row :gutter="16">
                    <a-col :span="12">
                        <a-form-item label="Region">
                            <a-input v-model:value="addForm.region" placeholder="us-east-1" />
                        </a-form-item>
                    </a-col>
                    <a-col :span="12">
                        <a-form-item label="Bandwidth Limit (bytes/s)">
                            <a-input-number v-model:value="addForm.bandwidth" :min="0" style="width: 100%" placeholder="0 = unlimited" />
                        </a-form-item>
                    </a-col>
                </a-row>

                <a-row :gutter="16">
                    <a-col :span="8">
                        <a-form-item>
                            <a-checkbox v-model:checked="addForm.secure">Use TLS</a-checkbox>
                        </a-form-item>
                    </a-col>
                    <a-col :span="8">
                        <a-form-item>
                            <a-checkbox v-model:checked="addForm.syncMode">Sync Mode</a-checkbox>
                        </a-form-item>
                    </a-col>
                    <a-col :span="8">
                        <a-form-item>
                            <a-checkbox v-model:checked="addForm.disableProxy">Disable Proxy</a-checkbox>
                        </a-form-item>
                    </a-col>
                </a-row>
            </a-form>
        </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as replicationApi from '@/api/modules/replication';
import type { RemoteTarget } from '@/api/modules/replication';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const addVisible = ref(false);
const addLoading = ref(false);
const targets = ref<RemoteTarget[]>([]);

const addForm = reactive({
    bucket: '',
    targetBucket: '',
    endpoint: '',
    accessKey: '',
    secretKey: '',
    region: '',
    bandwidth: 0,
    secure: true,
    syncMode: false,
    disableProxy: false
});

const columns = [
    { title: 'Source Bucket', dataIndex: 'sourceBucket', key: 'sourceBucket' },
    { title: 'Target Bucket', dataIndex: 'targetBucket', key: 'targetBucket' },
    { title: 'Endpoint', dataIndex: 'endpoint', key: 'endpoint' },
    { title: 'Type', key: 'type' },
    { title: 'Secure', key: 'secure' },
    { title: 'Bandwidth', key: 'bandwidth' },
    { title: 'Actions', key: 'actions', width: 100 }
];

const fetchTargets = async () => {
    loading.value = true;
    try {
        const res = await replicationApi.listRemoteTargets();
        targets.value = res.data.targets || [];
    } catch (error) {
        console.error('Failed to fetch remote targets', error);
    } finally {
        loading.value = false;
    }
};

const showAddModal = () => {
    addForm.bucket = '';
    addForm.targetBucket = '';
    addForm.endpoint = '';
    addForm.accessKey = '';
    addForm.secretKey = '';
    addForm.region = '';
    addForm.bandwidth = 0;
    addForm.secure = true;
    addForm.syncMode = false;
    addForm.disableProxy = false;
    addVisible.value = true;
};

const handleAdd = async () => {
    if (!addForm.bucket || !addForm.targetBucket || !addForm.endpoint || !addForm.accessKey || !addForm.secretKey) {
        message.error('Please fill in required fields');
        return;
    }
    addLoading.value = true;
    try {
        await replicationApi.addRemoteTarget({
            bucket: addForm.bucket,
            targetBucket: addForm.targetBucket,
            endpoint: addForm.endpoint,
            accessKey: addForm.accessKey,
            secretKey: addForm.secretKey,
            region: addForm.region || undefined,
            bandwidth: addForm.bandwidth || undefined,
            secure: addForm.secure,
            syncMode: addForm.syncMode,
            disableProxy: addForm.disableProxy
        });
        message.success('Remote target added');
        addVisible.value = false;
        fetchTargets();
    } catch (error) {
        message.error('Failed to add remote target');
        console.error(error);
    } finally {
        addLoading.value = false;
    }
};

const removeTarget = async (arn: string) => {
    try {
        await replicationApi.removeRemoteTarget(arn);
        message.success('Remote target removed');
        fetchTargets();
    } catch (error) {
        message.error('Failed to remove remote target');
        console.error(error);
    }
};

const formatBandwidth = (bytes: number) => {
    if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB/s';
    if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB/s';
    if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB/s';
    return bytes + ' B/s';
};

onMounted(() => {
    fetchTargets();
});
</script>

<style scoped>
.mb-4 { margin-bottom: 16px; }
</style>
