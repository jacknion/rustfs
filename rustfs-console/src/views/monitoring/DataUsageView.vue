<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Monitoring</a-breadcrumb-item>
            <a-breadcrumb-item>Data Usage</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="default" @click="fetchData" :loading="loading">
                <template #icon><ReloadOutlined /></template>
                Refresh
            </a-button>
        </template>

        <a-spin :spinning="loading">
            <!-- Summary Cards -->
            <a-row :gutter="16" class="mb-4" v-if="usageInfo">
                <a-col :span="6">
                    <a-card>
                        <a-statistic 
                            title="Total Objects" 
                            :value="getObjectsCount()" 
                            :value-style="{ color: '#1890ff' }"
                        />
                    </a-card>
                </a-col>
                <a-col :span="6">
                    <a-card>
                        <a-statistic 
                            title="Total Size" 
                            :value="formatBytes(getTotalSize())"
                        />
                    </a-card>
                </a-col>
                <a-col :span="6">
                    <a-card>
                        <a-statistic 
                            title="Buckets Count" 
                            :value="getBucketsCount()"
                            :value-style="{ color: '#52c41a' }"
                        />
                    </a-card>
                </a-col>
                <a-col :span="6">
                    <a-card>
                        <a-statistic 
                            title="Last Update" 
                            :value="formatDate(getLastUpdate())"
                        />
                    </a-card>
                </a-col>
            </a-row>

            <!-- Buckets Usage Table -->
            <a-card title="Bucket Usage Details" v-if="usageInfo">
                <a-table 
                    :columns="columns" 
                    :data-source="bucketsList" 
                    row-key="name"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'size'">
                            {{ formatBytes(record.size) }}
                        </template>
                        <template v-if="column.key === 'replicatedSize'">
                            {{ formatBytes(record.replicatedSize) }}
                        </template>
                        <template v-if="column.key === 'replicaSize'">
                            {{ formatBytes(record.replicaSize) }}
                        </template>
                    </template>
                </a-table>
            </a-card>

            <!-- Tier Stats -->
            <a-card title="Tier Statistics" class="mt-4" v-if="usageInfo && tierStatsList.length > 0">
                <a-table 
                    :columns="tierColumns" 
                    :data-source="tierStatsList" 
                    row-key="name"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'totalSize'">
                            {{ formatBytes(record.totalSize) }}
                        </template>
                    </template>
                </a-table>
            </a-card>
        </a-spin>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as monitoringApi from '@/api/modules/monitoring';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const usageInfo = ref<any>(null);

const columns = [
    { title: 'Bucket Name', dataIndex: 'name', key: 'name' },
    { title: 'Size', key: 'size' },
    { title: 'Objects Count', dataIndex: 'objectsCount', key: 'objectsCount' },
    { title: 'Replicated Size', key: 'replicatedSize' },
    { title: 'Replica Size', key: 'replicaSize' },
];

const tierColumns = [
    { title: 'Tier Name', dataIndex: 'name', key: 'name' },
    { title: 'Total Size', key: 'totalSize' },
    { title: 'Objects', dataIndex: 'numObjects', key: 'numObjects' },
    { title: 'Versions', dataIndex: 'numVersions', key: 'numVersions' },
];

// Helper to safely get properties supporting multiple casing conventions
const getObjectsCount = () => {
    if (!usageInfo.value) return 0;
    return usageInfo.value.objectsCount || usageInfo.value.objects_total_count || 0;
};

const getTotalSize = () => {
    if (!usageInfo.value) return 0;
    return usageInfo.value.objectsTotalSize || usageInfo.value.total_used_capacity || 0;
};

const getBucketsCount = () => {
    if (!usageInfo.value) return 0;
    return usageInfo.value.bucketsCount || usageInfo.value.buckets_count || 0;
};

const getLastUpdate = () => {
    if (!usageInfo.value) return '';
    if (usageInfo.value.lastUpdate) return usageInfo.value.lastUpdate;
    if (usageInfo.value.last_update) {
        // Check for Go-style NullTime/Time struct
        if (usageInfo.value.last_update.Valid === false) return '';
        return usageInfo.value.last_update.Time;
    }
    return '';
};

const bucketsList = computed(() => {
    const bucketsInfo = usageInfo.value?.bucketsUsageInfo || usageInfo.value?.buckets_usage_info;
    if (!bucketsInfo) return [];
    return Object.entries(bucketsInfo).map(([name, info]: [string, any]) => ({
        name,
        ...info
    }));
});

const tierStatsList = computed(() => {
    const stats = usageInfo.value?.tierStats || usageInfo.value?.tier_stats;
    if (!stats) return [];
    return Object.entries(stats).map(([name, info]: [string, any]) => ({
        name,
        ...info
    }));
});

const fetchData = async () => {
    loading.value = true;
    try {
        const res = await monitoringApi.getDataUsageInfo();
        usageInfo.value = res.data;
    } catch (error) {
        message.error('Failed to fetch data usage info');
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

const formatDate = (dateStr: string) => {
    if (!dateStr) return 'N/A';
    return new Date(dateStr).toLocaleString();
};

onMounted(() => {
    fetchData();
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
