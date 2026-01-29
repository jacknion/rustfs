<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Storage</a-breadcrumb-item>
            <a-breadcrumb-item>Pools</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="default" @click="fetchPools" :loading="loading">
                <template #icon><ReloadOutlined /></template>
                Refresh
            </a-button>
        </template>

        <a-spin :spinning="loading">
            <a-alert 
                v-if="pools.length === 0 && !loading"
                type="info" 
                message="No storage pools found"
                description="Storage pools are automatically created when you configure erasure coding."
                show-icon
            />

            <a-row :gutter="[16, 16]">
                <a-col :span="24" v-for="pool in pools" :key="pool.id">
                    <a-card :title="'Pool ' + pool.id">
                        <template #extra>
                            <a-space>
                                <a-tag :color="pool.suspended ? 'orange' : 'green'">
                                    {{ pool.suspended ? 'Suspended' : 'Active' }}
                                </a-tag>
                                <a-tag v-if="pool.decommission" color="red">
                                    Decommissioning
                                </a-tag>
                            </a-space>
                        </template>

                        <a-descriptions :column="{ xs: 1, sm: 2, md: 3 }" size="small">
                            <a-descriptions-item label="Pool ID">{{ pool.id }}</a-descriptions-item>
                            <a-descriptions-item label="Status">
                                {{ pool.suspended ? 'Suspended' : 'Active' }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Last Update">
                                {{ formatDate(pool.lastUpdate) }}
                            </a-descriptions-item>
                        </a-descriptions>

                        <!-- Decommission Progress -->
                        <div v-if="pool.decommission" class="mt-4">
                            <a-divider>Decommission Progress</a-divider>
                            <a-progress 
                                :percent="pool.decommission.poolProgress" 
                                :status="pool.decommission.failed ? 'exception' : pool.decommission.complete ? 'success' : 'active'"
                            />
                            <a-descriptions :column="2" size="small" class="mt-2">
                                <a-descriptions-item label="Started">
                                    {{ formatDate(pool.decommission.startTime) }}
                                </a-descriptions-item>
                                <a-descriptions-item label="Bytes Remaining">
                                    {{ formatBytes(pool.decommission.bytesRemaining) }}
                                </a-descriptions-item>
                                <a-descriptions-item label="Current Bucket">
                                    {{ pool.decommission.currentBucket || 'N/A' }}
                                </a-descriptions-item>
                                <a-descriptions-item label="Status">
                                    <a-tag v-if="pool.decommission.complete" color="green">Complete</a-tag>
                                    <a-tag v-else-if="pool.decommission.failed" color="red">Failed</a-tag>
                                    <a-tag v-else-if="pool.decommission.canceled" color="orange">Canceled</a-tag>
                                    <a-tag v-else color="blue">In Progress</a-tag>
                                </a-descriptions-item>
                            </a-descriptions>
                        </div>

                        <!-- Actions -->
                        <div class="mt-4">
                            <a-space>
                                <a-popconfirm 
                                    v-if="!pool.decommission"
                                    title="This will start decommissioning the pool. Continue?"
                                    @confirm="startDecommission(pool.id)"
                                >
                                    <a-button type="primary" danger :loading="actionLoading[pool.id]">
                                        Decommission
                                    </a-button>
                                </a-popconfirm>
                                <a-popconfirm 
                                    v-if="pool.decommission && !pool.decommission.complete && !pool.decommission.canceled"
                                    title="Cancel decommission operation?"
                                    @confirm="cancelPoolDecommission(pool.id)"
                                >
                                    <a-button :loading="actionLoading[pool.id]">
                                        Cancel Decommission
                                    </a-button>
                                </a-popconfirm>
                            </a-space>
                        </div>
                    </a-card>
                </a-col>
            </a-row>
        </a-spin>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, onMounted, reactive } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as poolsApi from '@/api/modules/pools';
import type { PoolInfo } from '@/api/modules/pools';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const pools = ref<PoolInfo[]>([]);
const actionLoading = reactive<Record<number, boolean>>({});

const fetchPools = async () => {
    loading.value = true;
    try {
        const res = await poolsApi.listPools();
        const poolList = res.data.pools || res.data.Pools || [];
        pools.value = poolList.map((p: any) => ({
            id: p.id || p.ID || p.poolID || 0,
            suspended: p.suspended !== undefined ? p.suspended : (p.Suspended !== undefined ? p.Suspended : false),
            lastUpdate: p.lastUpdate || p.LastUpdate || p.last_update || '',
            decommission: (p.decommission || p.Decommission) ? {
                poolProgress: p.decommission?.poolProgress ?? p.Decommission?.PoolProgress ?? 0,
                failed: p.decommission?.failed ?? p.Decommission?.Failed ?? false,
                complete: p.decommission?.complete ?? p.Decommission?.Complete ?? false,
                canceled: p.decommission?.canceled ?? p.Decommission?.Canceled ?? false,
                startTime: p.decommission?.startTime ?? p.Decommission?.StartTime ?? '',
                bytesRemaining: p.decommission?.bytesRemaining ?? p.Decommission?.BytesRemaining ?? 0,
                currentBucket: p.decommission?.currentBucket ?? p.Decommission?.CurrentBucket ?? '',
            } : null
        }));
    } catch (error) {
        message.error('Failed to fetch pools');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const startDecommission = async (poolId: number) => {
    actionLoading[poolId] = true;
    try {
        await poolsApi.decommissionPool(poolId);
        message.success('Decommission started');
        fetchPools();
    } catch (error) {
        message.error('Failed to start decommission');
        console.error(error);
    } finally {
        actionLoading[poolId] = false;
    }
};

const cancelPoolDecommission = async (poolId: number) => {
    actionLoading[poolId] = true;
    try {
        await poolsApi.cancelDecommission(poolId);
        message.success('Decommission canceled');
        fetchPools();
    } catch (error) {
        message.error('Failed to cancel decommission');
        console.error(error);
    } finally {
        actionLoading[poolId] = false;
    }
};

const formatDate = (dateStr: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
};

const formatBytes = (bytes: number) => {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

onMounted(() => {
    fetchPools();
});
</script>

<style scoped>
.mt-2 {
    margin-top: 8px;
}
.mt-4 {
    margin-top: 16px;
}
</style>
