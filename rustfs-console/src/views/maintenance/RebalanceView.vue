<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Maintenance</a-breadcrumb-item>
            <a-breadcrumb-item>Rebalance</a-breadcrumb-item>
        </template>

        <template #header>
            <a-space>
                <a-button 
                    v-if="!status || !isRunning" 
                    type="primary" 
                    @click="startRebalanceOp"
                    :loading="actionLoading"
                >
                    Start Rebalance
                </a-button>
                <a-button 
                    v-else
                    type="primary" 
                    danger
                    @click="stopRebalanceOp"
                    :loading="actionLoading"
                >
                    Stop Rebalance
                </a-button>
                <a-button type="default" @click="fetchStatus" :loading="loading">
                    <template #icon><ReloadOutlined /></template>
                    Refresh
                </a-button>
            </a-space>
        </template>

        <a-spin :spinning="loading">
            <a-alert 
                v-if="!status && !loading"
                type="info" 
                message="No Rebalance in Progress"
                description="Rebalance distributes data evenly across all storage pools. Start a rebalance operation to optimize data placement."
                show-icon
                class="mb-4"
            />

            <!-- Rebalance Status -->
            <a-card v-if="status" title="Rebalance Status" class="mb-4">
                <a-descriptions :column="3">
                    <a-descriptions-item label="Rebalance ID">{{ status.id }}</a-descriptions-item>
                    <a-descriptions-item label="Started">{{ formatDate(status.started) }}</a-descriptions-item>
                    <a-descriptions-item label="Status">
                        <a-tag :color="isRunning ? 'blue' : 'green'">
                            {{ isRunning ? 'Running' : 'Complete' }}
                        </a-tag>
                    </a-descriptions-item>
                </a-descriptions>
            </a-card>

            <!-- Pool Progress -->
            <a-card v-if="status?.pools?.length" title="Pool Progress">
                <a-collapse>
                    <a-collapse-panel v-for="pool in status.pools" :key="pool.id" :header="'Pool ' + pool.id">
                        <template #extra>
                            <a-progress :percent="pool.progress" :size="100" />
                        </template>
                        
                        <a-descriptions :column="2" size="small">
                            <a-descriptions-item label="Current Bucket">
                                {{ pool.bucket || 'N/A' }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Current Object">
                                {{ pool.object || 'N/A' }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Objects Healed">
                                {{ pool.objectsHealed }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Bytes Healed">
                                {{ formatBytes(pool.bytesHealed) }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Objects Failed">
                                <span :style="pool.objectsFailed > 0 ? { color: '#cf1322' } : {}">
                                    {{ pool.objectsFailed }}
                                </span>
                            </a-descriptions-item>
                            <a-descriptions-item label="Bytes Failed">
                                {{ formatBytes(pool.bytesFailed) }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Elapsed">
                                {{ pool.elapsed || 'N/A' }}
                            </a-descriptions-item>
                            <a-descriptions-item label="ETA">
                                {{ pool.eta || 'N/A' }}
                            </a-descriptions-item>
                        </a-descriptions>
                    </a-collapse-panel>
                </a-collapse>
            </a-card>
        </a-spin>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as rebalanceApi from '@/api/modules/rebalance';
import type { RebalanceStatus } from '@/api/modules/rebalance';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const actionLoading = ref(false);
const status = ref<RebalanceStatus | null>(null);

const isRunning = computed(() => {
    if (!status.value?.pools) return false;
    return status.value.pools.some(p => p.progress < 100);
});

const fetchStatus = async () => {
    loading.value = true;
    try {
        const res = await rebalanceApi.getRebalanceStatus();
        const data = res.data || {};
        status.value = {
            id: data.id || data.ID || '',
            started: data.started || data.Started || '',
            pools: (data.pools || data.Pools || []).map((p: any) => ({
                id: p.id || p.ID || 0,
                progress: p.progress || p.Progress || 0,
                bucket: p.bucket || p.Bucket || '',
                object: p.object || p.Object || '',
                objectsHealed: p.objectsHealed || p.ObjectsHealed || p.objects_healed || 0,
                bytesHealed: p.bytesHealed || p.BytesHealed || p.bytes_healed || 0,
                objectsFailed: p.objectsFailed || p.ObjectsFailed || p.objects_failed || 0,
                bytesFailed: p.bytesFailed || p.BytesFailed || p.bytes_failed || 0,
                elapsed: p.elapsed || p.Elapsed || '',
                eta: p.eta || p.ETA || ''
            }))
        };
    } catch (error: any) {
        if (error?.response?.status !== 404) {
            console.error('Failed to fetch rebalance status', error);
        }
        status.value = null;
    } finally {
        loading.value = false;
    }
};

const startRebalanceOp = async () => {
    actionLoading.value = true;
    try {
        await rebalanceApi.startRebalance();
        message.success('Rebalance started');
        fetchStatus();
    } catch (error) {
        message.error('Failed to start rebalance');
        console.error(error);
    } finally {
        actionLoading.value = false;
    }
};

const stopRebalanceOp = async () => {
    actionLoading.value = true;
    try {
        await rebalanceApi.stopRebalance();
        message.success('Rebalance stopped');
        fetchStatus();
    } catch (error) {
        message.error('Failed to stop rebalance');
        console.error(error);
    } finally {
        actionLoading.value = false;
    }
};

const formatDate = (dateStr: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
};

const formatBytes = (bytes: number) => {
    if (!bytes) return '0 B';
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
.mb-4 { margin-bottom: 16px; }
</style>
