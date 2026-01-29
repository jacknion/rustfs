<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Maintenance</a-breadcrumb-item>
            <a-breadcrumb-item>Tier Management</a-breadcrumb-item>
        </template>

        <template #header>
            <a-space>
                <a-button type="primary" @click="showAddModal">Add Tier</a-button>
                <a-button type="default" @click="fetchData" :loading="loading">
                    <template #icon><ReloadOutlined /></template>
                    Refresh
                </a-button>
            </a-space>
        </template>

        <a-spin :spinning="loading">
            <a-alert 
                v-if="tiers.length === 0 && !loading"
                type="info" 
                message="No tiers configured"
                description="Tiers allow you to transition objects to remote storage for cost optimization."
                show-icon
                class="mb-4"
            />

            <a-row :gutter="[16, 16]">
                <a-col :span="8" v-for="tier in tiers" :key="tier.name">
                    <a-card :title="tier.name" size="small">
                        <template #extra>
                            <a-tag :color="tier.status === 'online' ? 'green' : 'red'">
                                {{ tier.status }}
                            </a-tag>
                        </template>
                        
                        <a-descriptions :column="1" size="small">
                            <a-descriptions-item label="Type">
                                <a-tag>{{ tier.type.toUpperCase() }}</a-tag>
                            </a-descriptions-item>
                            <a-descriptions-item label="Endpoint">
                                {{ tier.endpoint || 'Default' }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Bucket">
                                {{ tier.bucket }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Prefix" v-if="tier.prefix">
                                {{ tier.prefix }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Region" v-if="tier.region">
                                {{ tier.region }}
                            </a-descriptions-item>
                        </a-descriptions>

                        <!-- Stats for this tier -->
                        <div v-if="tierStats[tier.name]" class="mt-2">
                            <a-divider style="margin: 8px 0" />
                            <a-row :gutter="8">
                                <a-col :span="12">
                                    <a-statistic 
                                        title="Objects" 
                                        :value="tierStats[tier.name].numObjects" 
                                        size="small"
                                    />
                                </a-col>
                                <a-col :span="12">
                                    <a-statistic 
                                        title="Size" 
                                        :value="formatBytes(tierStats[tier.name].totalSize)" 
                                        size="small"
                                    />
                                </a-col>
                            </a-row>
                        </div>

                        <template #actions>
                            <a-tooltip title="Verify Connection">
                                <CheckCircleOutlined @click="verifyTierConnection(tier.name)" />
                            </a-tooltip>
                            <a-popconfirm title="Remove this tier?" @confirm="removeTierItem(tier.name)">
                                <DeleteOutlined style="color: #ff4d4f" />
                            </a-popconfirm>
                        </template>
                    </a-card>
                </a-col>
            </a-row>
        </a-spin>

        <!-- Add Tier Modal -->
        <a-modal 
            v-model:open="addVisible" 
            title="Add Tier" 
            @ok="handleAdd"
            :confirm-loading="addLoading"
            width="600px"
        >
            <a-form layout="vertical">
                <a-row :gutter="16">
                    <a-col :span="12">
                        <a-form-item label="Tier Name" required>
                            <a-input v-model:value="addForm.name" placeholder="e.g., GLACIER" />
                        </a-form-item>
                    </a-col>
                    <a-col :span="12">
                        <a-form-item label="Type" required>
                            <a-select v-model:value="addForm.type">
                                <a-select-option value="s3">Amazon S3</a-select-option>
                                <a-select-option value="minio">MinIO</a-select-option>
                                <a-select-option value="azure">Azure Blob</a-select-option>
                                <a-select-option value="gcs">Google Cloud</a-select-option>
                            </a-select>
                        </a-form-item>
                    </a-col>
                </a-row>
                
                <a-form-item label="Endpoint" required>
                    <a-input v-model:value="addForm.endpoint" placeholder="https://s3.amazonaws.com" />
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
                        <a-form-item label="Bucket" required>
                            <a-input v-model:value="addForm.bucket" />
                        </a-form-item>
                    </a-col>
                    <a-col :span="12">
                        <a-form-item label="Prefix">
                            <a-input v-model:value="addForm.prefix" placeholder="Optional" />
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
                        <a-form-item label="Storage Class">
                            <a-input v-model:value="addForm.storageClass" placeholder="GLACIER" />
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
import { ReloadOutlined, CheckCircleOutlined, DeleteOutlined } from '@ant-design/icons-vue';
import * as tierApi from '@/api/modules/tier';
import type { TierInfo, TierStats } from '@/api/modules/tier';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const addVisible = ref(false);
const addLoading = ref(false);
const tiers = ref<TierInfo[]>([]);
const tierStats = ref<Record<string, TierStats>>({});

const addForm = reactive({
    name: '',
    type: 's3' as 's3' | 'azure' | 'gcs' | 'minio',
    endpoint: '',
    accessKey: '',
    secretKey: '',
    bucket: '',
    prefix: '',
    region: '',
    storageClass: ''
});

const fetchData = async () => {
    loading.value = true;
    try {
        const [tiersRes, statsRes] = await Promise.all([
            tierApi.listTiers(),
            tierApi.getTierStats()
        ]);
        tiers.value = tiersRes.data.tiers || [];
        tierStats.value = statsRes.data.stats || {};
    } catch (error) {
        console.error('Failed to fetch tiers', error);
    } finally {
        loading.value = false;
    }
};

const showAddModal = () => {
    addForm.name = '';
    addForm.type = 's3';
    addForm.endpoint = '';
    addForm.accessKey = '';
    addForm.secretKey = '';
    addForm.bucket = '';
    addForm.prefix = '';
    addForm.region = '';
    addForm.storageClass = '';
    addVisible.value = true;
};

const handleAdd = async () => {
    if (!addForm.name || !addForm.endpoint || !addForm.accessKey || !addForm.secretKey || !addForm.bucket) {
        message.error('Please fill in required fields');
        return;
    }
    addLoading.value = true;
    try {
        await tierApi.addTier({
            name: addForm.name,
            type: addForm.type,
            endpoint: addForm.endpoint,
            accessKey: addForm.accessKey,
            secretKey: addForm.secretKey,
            bucket: addForm.bucket,
            prefix: addForm.prefix || undefined,
            region: addForm.region || undefined,
            storageClass: addForm.storageClass || undefined
        });
        message.success('Tier added successfully');
        addVisible.value = false;
        fetchData();
    } catch (error) {
        message.error('Failed to add tier');
        console.error(error);
    } finally {
        addLoading.value = false;
    }
};

const verifyTierConnection = async (name: string) => {
    try {
        await tierApi.verifyTier(name);
        message.success(`Tier "${name}" connection verified`);
    } catch (error) {
        message.error(`Failed to verify tier "${name}"`);
        console.error(error);
    }
};

const removeTierItem = async (name: string) => {
    try {
        await tierApi.removeTier(name);
        message.success('Tier removed');
        fetchData();
    } catch (error) {
        message.error('Failed to remove tier');
        console.error(error);
    }
};

const formatBytes = (bytes: number) => {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

onMounted(() => {
    fetchData();
});
</script>

<style scoped>
.mb-4 {
    margin-bottom: 16px;
}
.mt-2 {
    margin-top: 8px;
}
</style>
