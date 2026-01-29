<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Monitoring</a-breadcrumb-item>
            <a-breadcrumb-item>Storage Info</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="default" @click="fetchData" :loading="loading">
                <template #icon><ReloadOutlined /></template>
                Refresh
            </a-button>
        </template>

        <a-spin :spinning="loading">
            <!-- Backend Summary -->
            <a-card title="Backend Summary" class="mb-4" v-if="storageInfo">
                <a-row :gutter="16">
                    <a-col :span="6">
                        <a-statistic title="Backend Type" :value="getBackendType()" />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic title="Online Disks" :value="getOnlineDisksCount()" :value-style="{ color: '#3f8600' }" />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic title="Offline Disks" :value="getOfflineDisksCount()" :value-style="getOfflineDisksCount() > 0 ? { color: '#cf1322' } : {}" />
                    </a-col>
                    <a-col :span="6">
                        <a-statistic title="Total Disks" :value="storageInfo.disks?.length || 0" />
                    </a-col>
                </a-row>
            </a-card>

            <!-- Disk List -->
            <a-card title="Disk Details">
                <a-table 
                    :columns="columns" 
                    :data-source="storageInfo?.disks || []" 
                    row-key="uuid"
                    :scroll="{ x: 1200 }"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'state'">
                            <a-tag :color="record.state === 'ok' ? 'green' : 'red'">
                                {{ record.state }}
                            </a-tag>
                        </template>
                        <template v-if="column.key === 'healing'">
                            <a-tag :color="record.healing ? 'orange' : 'default'">
                                {{ record.healing ? 'Healing' : 'Normal' }}
                            </a-tag>
                        </template>
                        <template v-if="column.key === 'totalSpace'">
                            {{ formatBytes(record.totalspace || record.totalSpace) }}
                        </template>
                        <template v-if="column.key === 'usedSpace'">
                            {{ formatBytes(record.usedspace || record.usedSpace) }}
                        </template>
                        <template v-if="column.key === 'availableSpace'">
                            {{ formatBytes(record.availspace || record.availableSpace) }}
                        </template>
                        <template v-if="column.key === 'utilization'">
                            <a-progress 
                                :percent="getUtilizationPercent(record)" 
                                :status="getUtilizationPercent(record) > 90 ? 'exception' : 'normal'"
                                size="small"
                            />
                        </template>
                    </template>
                </a-table>
            </a-card>
        </a-spin>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as monitoringApi from '@/api/modules/monitoring';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const storageInfo = ref<any>(null);

const columns = [
    { title: 'Endpoint', dataIndex: 'endpoint', key: 'endpoint', width: 150 },
    { title: 'Drive Path', dataIndex: ['path'], key: 'drivePath', width: 120 },
    { title: 'State', key: 'state', width: 80 },
    { title: 'Healing', key: 'healing', width: 80 },
    { title: 'Total Space', key: 'totalSpace', width: 100 },
    { title: 'Used', key: 'usedSpace', width: 100 },
    { title: 'Available', key: 'availableSpace', width: 100 },
    { title: 'Utilization', key: 'utilization', width: 150 },
    { title: 'Pool', dataIndex: 'poolIndex', key: 'poolIndex', width: 60 },
    { title: 'Set', dataIndex: 'setIndex', key: 'setIndex', width: 60 },
];

const getBackendType = () => {
    const backend = storageInfo.value?.backend;
    if (!backend) return 'N/A';
    // Handle both PascalCase and camelCase
    return backend.BackendType || backend.backendType || 'N/A';
};

const getOnlineDisksCount = () => {
    const backend = storageInfo.value?.backend;
    if (!backend) return 0;
    // OnlineDisks might be a number or an object with disk info
    const online = backend.OnlineDisks || backend.onlineDisks;
    if (typeof online === 'number' && online > 0) return online;
    if (typeof online === 'object' && Object.keys(online).length > 0) {
        return Object.keys(online).length;
    }
    // Fallback: count disks in ok state
    return storageInfo.value?.disks?.filter((d: any) => d.state === 'ok').length || 0;
};

const getOfflineDisksCount = () => {
    const backend = storageInfo.value?.backend;
    if (!backend) return 0;
    const offline = backend.OfflineDisks || backend.offlineDisks;
    if (typeof offline === 'number' && offline > 0) return offline;
    if (typeof offline === 'object' && Object.keys(offline).length > 0) {
        return Object.keys(offline).length;
    }
    // Fallback: count disks not in ok state
    return storageInfo.value?.disks?.filter((d: any) => d.state !== 'ok').length || 0;
};

const getUtilizationPercent = (record: any) => {
    const total = record.totalspace || record.totalSpace || 0;
    const used = record.usedspace || record.usedSpace || 0;
    if (total === 0) return 0;
    return Math.round((used / total) * 100);
};

const fetchData = async () => {
    loading.value = true;
    try {
        const res = await monitoringApi.getStorageInfo();
        storageInfo.value = res.data;
    } catch (error) {
        message.error('Failed to fetch storage info');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const formatBytes = (bytes: number) => {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
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
</style>

