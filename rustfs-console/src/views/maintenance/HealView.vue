<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Maintenance</a-breadcrumb-item>
            <a-breadcrumb-item>Data Healing</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="default" @click="fetchStatus" :loading="loading">
                <template #icon><ReloadOutlined /></template>
                Refresh
            </a-button>
        </template>

        <a-spin :spinning="loading">
            <!-- Background Heal Status -->
            <a-card title="Background Heal Status" class="mb-4">
                <a-row :gutter="16" v-if="bgStatus">
                    <a-col :span="6">
                        <a-statistic 
                            title="Scanned Items" 
                            :value="bgStatus.scannedItemsCount" 
                        />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic 
                            title="Healed Items" 
                            :value="bgStatus.healedItemsCount"
                            :value-style="{ color: '#52c41a' }"
                        />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic 
                            title="Current Bucket" 
                            :value="bgStatus.currentHealBucket || 'N/A'"
                        />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic 
                            title="Last Activity" 
                            :value="formatDate(bgStatus.lastHealActivity)"
                        />
                    </a-col>
                </a-row>
                <a-empty v-else description="No background heal data available" />
            </a-card>

            <!-- Heal Disks Status -->
            <a-card title="Disk Heal Status" v-if="bgStatus?.healDisks?.length">
                <a-table 
                    :columns="diskColumns" 
                    :data-source="bgStatus.healDisks" 
                    row-key="endpoint"
                    size="small"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'state'">
                            <a-tag :color="record.state === 'ok' ? 'green' : 'orange'">
                                {{ record.state }}
                            </a-tag>
                        </template>
                        <template v-if="column.key === 'bytesHealed'">
                            {{ formatBytes(record.bytesHealed) }}
                        </template>
                        <template v-if="column.key === 'bytesFailed'">
                            {{ formatBytes(record.bytesFailed) }}
                        </template>
                    </template>
                </a-table>
            </a-card>

            <!-- Manual Heal -->
            <a-card title="Manual Heal" class="mt-4">
                <a-form layout="inline">
                    <a-form-item label="Bucket">
                        <a-input v-model:value="healForm.bucket" placeholder="Optional bucket name" style="width: 200px" />
                    </a-form-item>
                    <a-form-item label="Prefix">
                        <a-input v-model:value="healForm.prefix" placeholder="Optional prefix" style="width: 200px" />
                    </a-form-item>
                    <a-form-item>
                        <a-checkbox v-model:checked="healForm.recursive">Recursive</a-checkbox>
                    </a-form-item>
                    <a-form-item>
                        <a-checkbox v-model:checked="healForm.dryRun">Dry Run</a-checkbox>
                    </a-form-item>
                    <a-form-item>
                        <a-button type="primary" @click="startHealOperation" :loading="healLoading">
                            Start Heal
                        </a-button>
                    </a-form-item>
                </a-form>
            </a-card>
        </a-spin>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as healApi from '@/api/modules/heal';
import type { BackgroundHealStatus } from '@/api/modules/heal';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const healLoading = ref(false);
const bgStatus = ref<BackgroundHealStatus | null>(null);

const healForm = reactive({
    bucket: '',
    prefix: '',
    recursive: true,
    dryRun: false
});

const diskColumns = [
    { title: 'Endpoint', dataIndex: 'endpoint', key: 'endpoint' },
    { title: 'State', key: 'state' },
    { title: 'Objects Healed', dataIndex: 'objectsHealed', key: 'objectsHealed' },
    { title: 'Objects Failed', dataIndex: 'objectsFailed', key: 'objectsFailed' },
    { title: 'Bytes Healed', key: 'bytesHealed' },
    { title: 'Bytes Failed', key: 'bytesFailed' },
];

const fetchStatus = async () => {
    loading.value = true;
    try {
        const res = await healApi.getBackgroundHealStatus();
        const data = res.data || {};
        // Normalize data to handle different casing (PascalCase/snake_case)
        bgStatus.value = {
            scannedItemsCount: data.scannedItemsCount || data.ScannedItemsCount || data.scanned_items_count || 0,
            healedItemsCount: data.healedItemsCount || data.HealedItemsCount || data.healed_items_count || 0,
            currentHealBucket: data.currentHealBucket || data.CurrentHealBucket || data.current_heal_bucket || '',
            lastHealActivity: data.lastHealActivity || data.LastHealActivity || data.last_heal_activity || '',
            healDisks: (data.healDisks || data.HealDisks || data.heal_disks || []).map((d: any) => ({
                endpoint: d.endpoint || d.Endpoint || '',
                state: d.state || d.State || 'unknown',
                objectsHealed: d.objectsHealed || d.ObjectsHealed || d.objects_healed || 0,
                objectsFailed: d.objectsFailed || d.ObjectsFailed || d.objects_failed || 0,
                bytesHealed: d.bytesHealed || d.BytesHealed || d.bytes_healed || 0,
                bytesFailed: d.bytesFailed || d.BytesFailed || d.bytes_failed || 0,
            }))
        };
    } catch (error) {
        console.error('Failed to fetch heal status', error);
    } finally {
        loading.value = false;
    }
};

const startHealOperation = async () => {
    healLoading.value = true;
    try {
        await healApi.startHeal({
            bucket: healForm.bucket || undefined,
            prefix: healForm.prefix || undefined,
            recursive: healForm.recursive,
            dryRun: healForm.dryRun
        });
        message.success('Heal operation started');
        fetchStatus();
    } catch (error) {
        message.error('Failed to start heal operation');
        console.error(error);
    } finally {
        healLoading.value = false;
    }
};

const formatDate = (dateStr: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
};

const formatBytes = (bytes: number) => {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

onMounted(() => {
    fetchStatus();
});
</script>

<style scoped>
.mb-4 {
    margin-bottom: 16px;
}
.mt-4 {
    margin-top: 16px;
}
</style>
