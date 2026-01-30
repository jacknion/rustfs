<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Monitoring</a-breadcrumb-item>
            <a-breadcrumb-item>Storage Monitoring</a-breadcrumb-item>
        </template>

        <template #header>
            <div class="header-actions">
                <span class="last-update-text mr-4" v-if="getLastUpdate()">
                    Last Updated: {{ formatDate(getLastUpdate()) }}
                </span>
                <a-button type="primary" @click="fetchData" :loading="loading">
                    <template #icon><ReloadOutlined /></template>
                    Refresh
                </a-button>
            </div>
        </template>
        <a-spin :spinning="loading">
            <!-- Consolidated Summary Section -->
            <a-row :gutter="[16, 16]" class="mb-6">
                <!-- Group 1: Storage Health -->
                <a-col :xs="24" :sm="12" :md="6" :lg="4">
                    <a-card size="small" :bordered="false" class="h-100 summary-card">
                        <a-statistic title="Online Disks" :value="getOnlineDisks()" :value-style="{ color: '#52c41a' }">
                            <template #prefix><CheckCircleOutlined /></template>
                        </a-statistic>
                    </a-card>
                </a-col>
                <a-col :xs="24" :sm="12" :md="6" :lg="4">
                    <a-card size="small" :bordered="false" class="h-100 summary-card">
                        <a-statistic title="Offline Disks" :value="getOfflineDisks()" :value-style="getOfflineDisks() > 0 ? { color: '#ff4d4f' } : { color: '#bfbfbf' }">
                            <template #prefix><CloseCircleOutlined /></template>
                        </a-statistic>
                    </a-card>
                </a-col>

                <!-- Group 2: Capacity -->
                <a-col :xs="24" :sm="12" :md="6" :lg="4">
                    <a-card size="small" :bordered="false" class="h-100 summary-card">
                        <a-statistic title="Total Capacity" :value="formatBytes(getTotalCapacity())">
                            <template #prefix><DatabaseOutlined /></template>
                        </a-statistic>
                    </a-card>
                </a-col>
                <a-col :xs="24" :sm="12" :md="6" :lg="4">
                    <a-card size="small" :bordered="false" class="h-100 summary-card">
                        <a-statistic 
                            title="Used Capacity" 
                            :value="formatBytes(getUsedCapacity())" 
                            :value-style="{ color: getUsedCapacity() / getTotalCapacity() > 0.9 ? '#ff4d4f' : 'inherit' }"
                        >
                            <template #prefix><AreaChartOutlined /></template>
                        </a-statistic>
                    </a-card>
                </a-col>

                <!-- Group 3: Counts -->
                <a-col :xs="24" :sm="12" :md="6" :lg="4">
                    <a-card size="small" :bordered="false" class="h-100 summary-card">
                        <a-statistic title="Total Objects" :value="getObjectsCount()" :value-style="{ color: '#1890ff' }">
                            <template #prefix><FileSearchOutlined /></template>
                        </a-statistic>
                    </a-card>
                </a-col>
                <a-col :xs="24" :sm="12" :md="6" :lg="4">
                    <a-card size="small" :bordered="false" class="h-100 summary-card">
                        <a-statistic title="Buckets Count" :value="getBucketsCount()" :value-style="{ color: '#722ed1' }">
                            <template #prefix><FolderOutlined /></template>
                        </a-statistic>
                    </a-card>
                </a-col>
            </a-row>

            <!-- Detailed Metrics Row -->
            <a-row :gutter="[16, 16]" class="mb-6" v-if="usageInfo">
                <a-col :span="24">
                    <a-card size="small" class="stats-mini-row">
                        <a-space :size="32">
                            <div class="mini-stat-item">
                                <span class="label">Total Versions:</span>
                                <span class="value">{{ getVersionsCount() }}</span>
                            </div>
                            <div class="mini-stat-item">
                                <span class="label">Delete Markers:</span>
                                <span class="value">{{ getDeleteMarkersCount() }}</span>
                            </div>
                        </a-space>
                    </a-card>
                </a-col>
            </a-row>

            <!-- Buckets Usage Table -->
            <a-card title="Bucket Usage Details" class="mb-4" v-if="usageInfo">
                <a-table 
                    :columns="bucketColumns" 
                    :data-source="bucketsList" 
                    row-key="name"
                    size="middle"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'size'">
                            {{ formatBytes(record.size) }}
                        </template>
                        <template v-if="column.key === 'objectsCount'">
                            {{ record.objectsCount || record.objects_count || 0 }}
                        </template>
                        <template v-if="column.key === 'replicatedSize'">
                            {{ formatBytes(record.replicatedSize || record.replicated_size || 0) }}
                        </template>
                    </template>
                </a-table>
            </a-card>

            <a-row :gutter="16">
                <!-- Tier Stats -->
                <a-col :span="10">
                    <a-card title="Tier Statistics" v-if="usageInfo && tierStatsList.length > 0">
                        <a-table 
                            :columns="tierColumns" 
                            :data-source="tierStatsList" 
                            row-key="name"
                            size="small"
                        >
                            <template #bodyCell="{ column, record }">
                                <template v-if="column.key === 'totalSize'">
                                    {{ formatBytes(record.totalSize) }}
                                </template>
                            </template>
                        </a-table>
                    </a-card>
                </a-col>

                <!-- Disk Info Summary -->
                <a-col :span="14">
                    <a-card title="Disk Details" v-if="storageInfo">
                        <a-table 
                            :columns="diskColumns" 
                            :data-source="storageInfo.disks || []" 
                            row-key="uuid"
                            size="small"
                            :scroll="{ x: 800 }"
                        >
                            <template #bodyCell="{ column, record }">
                                <template v-if="column.key === 'state'">
                                    <a-tag :color="record.state === 'ok' ? 'green' : 'red'">
                                        {{ record.state }}
                                    </a-tag>
                                </template>
                                <template v-if="column.key === 'utilization'">
                                    <a-progress 
                                        :percent="getUtilizationPercent(record)" 
                                        :status="getUtilizationPercent(record) > 90 ? 'exception' : 'normal'"
                                        size="small"
                                    />
                                </template>
                                <template v-if="column.key === 'totalSpace'">
                                    {{ formatBytes(record.totalSpace || record.total_space || 0) }}
                                </template>
                            </template>
                        </a-table>
                    </a-card>
                </a-col>
            </a-row>
        </a-spin>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { 
    ReloadOutlined, 
    DatabaseOutlined, 
    FolderOutlined, 
    FileSearchOutlined, 
    CheckCircleOutlined, 
    CloseCircleOutlined,
    AreaChartOutlined,
    LineChartOutlined
} from '@ant-design/icons-vue';
import * as monitoringApi from '@/api/modules/monitoring';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const storageInfo = ref<any>(null);
const usageInfo = ref<any>(null);

const bucketColumns = [
    { title: 'Bucket Name', dataIndex: 'name', key: 'name' },
    { title: 'Size', key: 'size', align: 'right' as const },
    { title: 'Objects', key: 'objectsCount', align: 'right' as const },
    { title: 'Replicated', key: 'replicatedSize', align: 'right' as const },
];

const tierColumns = [
    { title: 'Tier', dataIndex: 'name', key: 'name' },
    { title: 'Size', key: 'totalSize', align: 'right' as const },
    { title: 'Objects', dataIndex: 'numObjects', key: 'numObjects', align: 'right' as const },
];

const diskColumns = [
    { title: 'Drive Path', dataIndex: 'drivePath', key: 'drivePath', width: 250 },
    { title: 'State', key: 'state', width: 100, align: 'center' as const },
    { title: 'Total', key: 'totalSpace', width: 120, align: 'right' as const },
    { title: 'Utilization', key: 'utilization', width: 200 },
    { title: 'Pool', dataIndex: 'poolIndex', key: 'poolIndex', width: 80, align: 'center' as const },
];

// Calculation Helpers
const getTotalCapacity = () => {
    if (!storageInfo.value?.disks) return 0;
    return storageInfo.value.disks.reduce((acc: number, disk: any) => 
        acc + (disk.totalSpace || disk.total_space || 0), 0);
};

const getUsedCapacity = () => {
    if (!storageInfo.value?.disks) return 0;
    return storageInfo.value.disks.reduce((acc: number, disk: any) => 
        acc + (disk.usedSpace || disk.used_space || 0), 0);
};

const getOnlineDisks = () => {
    if (!storageInfo.value?.disks) return 0;
    return storageInfo.value.disks.filter((d: any) => d.state === 'ok').length;
};

const getOfflineDisks = () => {
    if (!storageInfo.value?.disks) return 0;
    return storageInfo.value.disks.filter((d: any) => d.state !== 'ok').length;
};

const getObjectsCount = () => usageInfo.value?.objectsCount || usageInfo.value?.objects_total_count || 0;
const getVersionsCount = () => usageInfo.value?.versionsCount || usageInfo.value?.versions_total_count || 0;
const getDeleteMarkersCount = () => usageInfo.value?.deleteMarkersCount || usageInfo.value?.delete_markers_total_count || 0;
const getBucketsCount = () => usageInfo.value?.bucketsCount || usageInfo.value?.buckets_count || 0;
const getLastUpdate = () => usageInfo.value?.lastUpdate || usageInfo.value?.last_update || '';

const getUtilizationPercent = (record: any) => {
    const total = record.totalSpace || record.total_space || 0;
    const used = record.usedSpace || record.used_space || 0;
    return total === 0 ? 0 : Math.round((used / total) * 100);
};

const bucketsList = computed(() => {
    const info = usageInfo.value?.bucketsUsageInfo || usageInfo.value?.buckets_usage_info || usageInfo.value?.buckets_usage;
    if (!info) return [];
    return Object.entries(info).map(([name, data]: [string, any]) => ({ name, ...data }));
});

const tierStatsList = computed(() => {
    const stats = usageInfo.value?.tierStats || usageInfo.value?.tier_stats;
    if (!stats) return [];
    return Object.entries(stats).map(([name, info]: [string, any]) => ({
        name,
        ...info,
        totalSize: info.totalSize || info.total_size || 0,
        numObjects: info.numObjects || info.num_objects || 0,
    }));
});

const fetchData = async () => {
    loading.value = true;
    try {
        const [sRes, uRes] = await Promise.all([
            monitoringApi.getStorageInfo(),
            monitoringApi.getDataUsageInfo()
        ]);
        storageInfo.value = sRes.data;
        usageInfo.value = uRes.data;
    } catch (error) {
        message.error('Failed to fetch monitoring data');
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

const formatDate = (date: any) => {
    if (!date) return 'N/A';
    // Handle both ISO string and Go-style NullTime object
    const dateStr = typeof date === 'string' ? date : date.Time;
    if (!dateStr || dateStr === '0001-01-01T00:00:00Z') return 'Never';
    return new Date(dateStr).toLocaleString();
};

onMounted(fetchData);
</script>

<style scoped>
.mb-4 { margin-bottom: 16px; }
.mb-6 { margin-bottom: 24px; }
.mr-4 { margin-right: 16px; }
.h-100 { height: 100%; }

.header-actions {
    display: flex;
    align-items: center;
}

.last-update-text {
    color: var(--text-color-secondary, #8c8c8c);
    font-size: 13px;
}

.summary-card {
    transition: all 0.3s;
    border-radius: 8px;
    box-shadow: 0 1px 2px rgba(0,0,0,0.03);
}

.summary-card:hover {
    box-shadow: 0 4px 12px rgba(0,0,0,0.08);
}

.stats-mini-row {
    background: var(--component-background, #f5f5f5);
    border: none;
    border-radius: 6px;
}

.mini-stat-item {
    display: inline-flex;
    align-items: center;
}

.mini-stat-item .label {
    color: var(--text-color-secondary, #8c8c8c);
    margin-right: 8px;
    font-size: 13px;
}

.mini-stat-item .value {
    font-weight: 500;
    font-size: 14px;
}

:deep(.ant-statistic-title) {
    font-size: 13px;
    margin-bottom: 8px;
}

:deep(.ant-statistic-content) {
    font-size: 20px;
    font-weight: 600;
}

:deep(.ant-table-thead > tr > th) {
    background-color: var(--table-header-bg, #fafafa);
}
</style>
