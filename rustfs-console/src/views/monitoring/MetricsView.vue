<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Monitoring</a-breadcrumb-item>
            <a-breadcrumb-item>Metrics</a-breadcrumb-item>
        </template>

        <template #header>
            <a-space>
                <a-select v-model:value="metricsType" style="width: 150px">
                    <a-select-option value="cluster">Cluster</a-select-option>
                    <a-select-option value="node">Node</a-select-option>
                    <a-select-option value="bucket">Bucket</a-select-option>
                    <a-select-option value="resource">Resource</a-select-option>
                </a-select>
                <a-button type="default" @click="fetchData" :loading="loading">
                    <template #icon><ReloadOutlined /></template>
                    Refresh
                </a-button>
            </a-space>
        </template>

        <a-spin :spinning="loading">
            <a-card title="Prometheus Metrics">
                <a-alert 
                    type="info" 
                    message="Prometheus Format Metrics"
                    description="These metrics can be scraped by Prometheus for monitoring and alerting."
                    show-icon
                    class="mb-4"
                />
                
                <div class="metrics-container">
                    <a-textarea 
                        :value="metricsData" 
                        :rows="25" 
                        readonly 
                        class="metrics-text"
                    />
                </div>

                <div class="mt-4">
                    <a-button @click="copyMetrics" type="primary">
                        Copy to Clipboard
                    </a-button>
                    <a-button @click="downloadMetrics" style="margin-left: 8px">
                        Download
                    </a-button>
                </div>
            </a-card>

            <!-- Parsed Metrics Summary -->
            <a-card title="Metrics Summary" class="mt-4" v-if="parsedMetrics.length > 0">
                <a-table 
                    :columns="summaryColumns" 
                    :data-source="parsedMetrics" 
                    row-key="name"
                    :pagination="{ pageSize: 20 }"
                >
                    <template #bodyCell="{ column, record }">
                        <template v-if="column.key === 'type'">
                            <a-tag :color="getTypeColor(record.type)">{{ record.type }}</a-tag>
                        </template>
                    </template>
                </a-table>
            </a-card>
        </a-spin>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined } from '@ant-design/icons-vue';
import * as monitoringApi from '@/api/modules/monitoring';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const metricsType = ref<'node' | 'cluster' | 'bucket' | 'resource'>('cluster');
const metricsData = ref('');

const summaryColumns = [
    { title: 'Metric Name', dataIndex: 'name', key: 'name' },
    { title: 'Type', key: 'type' },
    { title: 'Help', dataIndex: 'help', key: 'help', ellipsis: true },
];

const parsedMetrics = computed(() => {
    if (!metricsData.value) return [];
    const lines = metricsData.value.split('\n');
    const metrics: { name: string; type: string; help: string }[] = [];
    let currentHelp = '';
    let currentType = '';
    
    for (const line of lines) {
        if (line.startsWith('# HELP ')) {
            const parts = line.substring(7).split(' ');
            currentHelp = parts.slice(1).join(' ');
        } else if (line.startsWith('# TYPE ')) {
            const parts = line.substring(7).split(' ');
            const name = parts[0];
            currentType = parts[1] || 'unknown';
            
            if (!metrics.find(m => m.name === name)) {
                metrics.push({
                    name,
                    type: currentType,
                    help: currentHelp
                });
            }
            currentHelp = '';
        }
    }
    
    return metrics;
});

const fetchData = async () => {
    loading.value = true;
    try {
        const res = await monitoringApi.getMetrics(metricsType.value);
        metricsData.value = res.data;
    } catch (error) {
        message.error('Failed to fetch metrics');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const getTypeColor = (type: string) => {
    const colors: Record<string, string> = {
        counter: 'blue',
        gauge: 'green',
        histogram: 'orange',
        summary: 'purple'
    };
    return colors[type] || 'default';
};

const copyMetrics = async () => {
    try {
        await navigator.clipboard.writeText(metricsData.value);
        message.success('Copied to clipboard');
    } catch {
        message.error('Failed to copy');
    }
};

const downloadMetrics = () => {
    const blob = new Blob([metricsData.value], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `rustfs-metrics-${metricsType.value}-${Date.now()}.txt`;
    a.click();
    URL.revokeObjectURL(url);
};

watch(metricsType, () => {
    fetchData();
});

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
.metrics-container {
    background: #f5f5f5;
    border-radius: 4px;
    padding: 8px;
}
.metrics-text {
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 12px;
}
</style>
