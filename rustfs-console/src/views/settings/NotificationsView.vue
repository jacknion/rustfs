<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Settings</a-breadcrumb-item>
            <a-breadcrumb-item>Notifications</a-breadcrumb-item>
        </template>

        <template #header>
            <a-space>
                <a-button type="primary" @click="showAddModal">Add Target</a-button>
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
                message="No Notification Targets Configured"
                description="Notification targets allow you to receive event notifications when objects are created, deleted, or modified in your buckets."
                show-icon
                class="mb-4"
            />

            <!-- Notification Targets Grid -->
            <a-row :gutter="[16, 16]" v-if="targets.length > 0">
                <a-col :xs="24" :sm="12" :lg="8" v-for="target in targets" :key="target.arn">
                    <a-card size="small">
                        <template #title>
                            <a-space>
                                <a-tag :color="getTypeColor(target.type)">{{ target.type.toUpperCase() }}</a-tag>
                                <span>{{ target.id }}</span>
                            </a-space>
                        </template>
                        <template #extra>
                            <a-tag :color="target.status === 'online' ? 'green' : 'red'">
                                {{ target.status }}
                            </a-tag>
                        </template>

                        <a-descriptions :column="1" size="small">
                            <a-descriptions-item label="ARN">
                                <a-typography-text copyable :content="target.arn">
                                    {{ truncateArn(target.arn) }}
                                </a-typography-text>
                            </a-descriptions-item>
                        </a-descriptions>

                        <template #actions>
                            <a-tooltip title="Test Connection">
                                <ThunderboltOutlined @click="testTarget(target.arn)" />
                            </a-tooltip>
                            <a-popconfirm 
                                title="Remove this notification target?"
                                @confirm="removeTarget(target.arn)"
                            >
                                <DeleteOutlined style="color: #ff4d4f" />
                            </a-popconfirm>
                        </template>
                    </a-card>
                </a-col>
            </a-row>
        </a-spin>

        <!-- Add Target Modal -->
        <a-modal 
            v-model:open="addVisible" 
            title="Add Notification Target" 
            @ok="handleAdd"
            :confirm-loading="addLoading"
            width="500px"
        >
            <a-form layout="vertical">
                <a-form-item label="Target Type" required>
                    <a-select v-model:value="addForm.type" placeholder="Select target type">
                        <a-select-option value="webhook">Webhook</a-select-option>
                        <a-select-option value="kafka">Kafka</a-select-option>
                        <a-select-option value="amqp">AMQP (RabbitMQ)</a-select-option>
                        <a-select-option value="mqtt">MQTT</a-select-option>
                        <a-select-option value="nats">NATS</a-select-option>
                        <a-select-option value="redis">Redis</a-select-option>
                        <a-select-option value="elasticsearch">Elasticsearch</a-select-option>
                        <a-select-option value="postgresql">PostgreSQL</a-select-option>
                        <a-select-option value="mysql">MySQL</a-select-option>
                    </a-select>
                </a-form-item>

                <a-form-item label="Target ID">
                    <a-input v-model:value="addForm.id" placeholder="my-notification-target" />
                </a-form-item>

                <!-- Webhook Config -->
                <template v-if="addForm.type === 'webhook'">
                    <a-form-item label="Endpoint URL" required>
                        <a-input v-model:value="addForm.config.endpoint" placeholder="https://example.com/webhook" />
                    </a-form-item>
                    <a-form-item label="Auth Token">
                        <a-input-password v-model:value="addForm.config.authToken" placeholder="Optional auth token" />
                    </a-form-item>
                </template>

                <!-- Kafka Config -->
                <template v-if="addForm.type === 'kafka'">
                    <a-form-item label="Brokers" required>
                        <a-input v-model:value="addForm.config.brokers" placeholder="broker1:9092,broker2:9092" />
                    </a-form-item>
                    <a-form-item label="Topic" required>
                        <a-input v-model:value="addForm.config.topic" placeholder="minio-events" />
                    </a-form-item>
                </template>

                <!-- Generic Config -->
                <template v-if="!['webhook', 'kafka'].includes(addForm.type)">
                    <a-form-item label="Endpoint/Host" required>
                        <a-input v-model:value="addForm.config.endpoint" placeholder="host:port" />
                    </a-form-item>
                </template>
            </a-form>
        </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import { ReloadOutlined, DeleteOutlined, ThunderboltOutlined } from '@ant-design/icons-vue';
import * as notificationsApi from '@/api/modules/notifications';
import type { NotificationTarget, TargetType } from '@/api/modules/notifications';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const addVisible = ref(false);
const addLoading = ref(false);
const targets = ref<NotificationTarget[]>([]);

const addForm = reactive<{
    type: TargetType;
    id: string;
    config: Record<string, any>;
}>({
    type: 'webhook',
    id: '',
    config: {}
});

const fetchTargets = async () => {
    loading.value = true;
    try {
        const res = await notificationsApi.listNotificationTargets();
        const t = res.data.targets || res.data.Targets || [];
        targets.value = t.map((target: any) => ({
            id: target.id || target.ID || '',
            type: (target.type || target.Type || '').toLowerCase(),
            status: (target.status || target.Status || 'offline').toLowerCase(),
            arn: target.arn || target.Arn || target.ARN || '',
        }));
    } catch (error) {
        console.error('Failed to fetch notification targets', error);
    } finally {
        loading.value = false;
    }
};

const showAddModal = () => {
    addForm.type = 'webhook';
    addForm.id = '';
    addForm.config = {};
    addVisible.value = true;
};

const handleAdd = async () => {
    if (!addForm.type) {
        message.error('Please select a target type');
        return;
    }
    addLoading.value = true;
    try {
        await notificationsApi.addNotificationTarget({
            type: addForm.type,
            id: addForm.id || undefined,
            config: addForm.config
        });
        message.success('Notification target added');
        addVisible.value = false;
        fetchTargets();
    } catch (error) {
        message.error('Failed to add notification target');
        console.error(error);
    } finally {
        addLoading.value = false;
    }
};

const removeTarget = async (arn: string) => {
    try {
        await notificationsApi.removeNotificationTarget(arn);
        message.success('Target removed');
        fetchTargets();
    } catch (error) {
        message.error('Failed to remove target');
        console.error(error);
    }
};

const testTarget = async (arn: string) => {
    try {
        await notificationsApi.testNotificationTarget(arn);
        message.success('Test notification sent');
    } catch (error) {
        message.error('Failed to test target');
        console.error(error);
    }
};

const getTypeColor = (type: TargetType) => {
    const colors: Record<TargetType, string> = {
        webhook: 'blue',
        kafka: 'purple',
        amqp: 'orange',
        mqtt: 'cyan',
        nats: 'green',
        nsq: 'lime',
        elasticsearch: 'gold',
        redis: 'red',
        mysql: 'geekblue',
        postgresql: 'volcano'
    };
    return colors[type] || 'default';
};

const truncateArn = (arn: string) => {
    if (arn.length > 40) return arn.substring(0, 40) + '...';
    return arn;
};

onMounted(() => {
    fetchTargets();
});
</script>

<style scoped>
.mb-4 { margin-bottom: 16px; }
</style>
