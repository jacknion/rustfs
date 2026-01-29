<template>
    <a-modal 
        v-model:open="visible" 
        :title="`Bucket Settings: ${bucketName}`" 
        width="720px"
        :footer="null"
        @cancel="handleClose"
    >
        <a-spin :spinning="loading">
            <a-tabs v-model:activeKey="activeTab" size="small">
                <!-- Versioning Tab -->
                <a-tab-pane key="versioning" tab="Versioning">
                    <a-descriptions :column="1" bordered size="small">
                        <a-descriptions-item label="Status">
                            <a-tag :color="versioningEnabled ? 'green' : 'default'">
                                {{ versioningStatus }}
                            </a-tag>
                        </a-descriptions-item>
                    </a-descriptions>
                    <div style="margin-top: 16px;">
                        <a-space>
                            <a-button 
                                type="primary" 
                                :disabled="versioningEnabled"
                                @click="enableVersioning"
                                :loading="saving"
                            >
                                Enable Versioning
                            </a-button>
                            <a-button 
                                danger 
                                :disabled="!versioningEnabled"
                                @click="suspendVersioning"
                                :loading="saving"
                            >
                                Suspend Versioning
                            </a-button>
                        </a-space>
                    </div>
                    <a-alert 
                        v-if="versioningEnabled" 
                        type="info" 
                        style="margin-top: 16px;"
                        message="Versioning cannot be disabled once enabled, only suspended."
                        show-icon 
                    />
                </a-tab-pane>

                <!-- Object Locking Tab -->
                <a-tab-pane key="object-lock" tab="Object Lock">
                    <a-descriptions :column="1" bordered size="small">
                        <a-descriptions-item label="Object Lock Enabled">
                            <a-tag :color="objectLockConfig.enabled ? 'green' : 'default'">
                                {{ objectLockConfig.enabled ? 'Yes' : 'No' }}
                            </a-tag>
                        </a-descriptions-item>
                        <template v-if="objectLockConfig.enabled">
                            <a-descriptions-item label="Retention Mode" v-if="objectLockConfig.mode">
                                {{ objectLockConfig.mode }}
                            </a-descriptions-item>
                            <a-descriptions-item label="Retention Period" v-if="objectLockConfig.days || objectLockConfig.years">
                                {{ objectLockConfig.days ? `${objectLockConfig.days} days` : `${objectLockConfig.years} years` }}
                            </a-descriptions-item>
                        </template>
                    </a-descriptions>
                    <a-alert 
                        type="warning" 
                        style="margin-top: 16px;"
                        message="Object Locking can only be enabled during bucket creation."
                        show-icon 
                    />
                </a-tab-pane>

                <!-- Quota Tab -->
                <a-tab-pane key="quota" tab="Quota">
                    <a-form layout="vertical">
                        <a-form-item label="Bucket Quota">
                            <a-input-group compact>
                                <a-input-number 
                                    v-model:value="quotaValue" 
                                    :min="0" 
                                    style="width: 200px;"
                                    placeholder="Enter quota"
                                />
                                <a-select v-model:value="quotaUnit" style="width: 100px;">
                                    <a-select-option value="MB">MB</a-select-option>
                                    <a-select-option value="GB">GB</a-select-option>
                                    <a-select-option value="TB">TB</a-select-option>
                                </a-select>
                            </a-input-group>
                            <div style="color: #888; font-size: 12px; margin-top: 4px;">
                                Set to 0 to disable quota limit
                            </div>
                        </a-form-item>
                        <a-form-item>
                            <a-button type="primary" @click="saveQuota" :loading="saving">
                                Save Quota
                            </a-button>
                        </a-form-item>
                    </a-form>
                </a-tab-pane>

                <!-- Lifecycle Tab -->
                <a-tab-pane key="lifecycle" tab="Lifecycle">
                    <a-table 
                        :columns="lifecycleColumns" 
                        :data-source="lifecycleRules" 
                        :pagination="false"
                        size="small"
                        row-key="id"
                    >
                        <template #bodyCell="{ column, record }">
                            <template v-if="column.key === 'status'">
                                <a-tag :color="record.status === 'Enabled' ? 'green' : 'default'">
                                    {{ record.status }}
                                </a-tag>
                            </template>
                            <template v-if="column.key === 'action'">
                                <a-popconfirm title="Delete this rule?" @confirm="deleteLifecycleRule(record.id)">
                                    <a-button type="link" danger size="small">Delete</a-button>
                                </a-popconfirm>
                            </template>
                        </template>
                        <template #emptyText>
                            <a-empty description="No lifecycle rules configured" />
                        </template>
                    </a-table>
                    <a-divider />
                    <a-form layout="inline" style="margin-top: 12px;">
                        <a-form-item label="Rule ID">
                            <a-input v-model:value="newRule.id" placeholder="rule-1" style="width: 120px;" />
                        </a-form-item>
                        <a-form-item label="Prefix">
                            <a-input v-model:value="newRule.prefix" placeholder="logs/" style="width: 120px;" />
                        </a-form-item>
                        <a-form-item label="Expire Days">
                            <a-input-number v-model:value="newRule.expirationDays" :min="1" style="width: 80px;" />
                        </a-form-item>
                        <a-form-item>
                            <a-button type="primary" @click="addLifecycleRule" :loading="saving">Add Rule</a-button>
                        </a-form-item>
                    </a-form>
                </a-tab-pane>

                <!-- Events/Notifications Tab -->
                <a-tab-pane key="events" tab="Events">
                    <a-table 
                        :columns="eventColumns" 
                        :data-source="notifications" 
                        :pagination="false"
                        size="small"
                        row-key="id"
                    >
                        <template #bodyCell="{ column, record }">
                            <template v-if="column.key === 'events'">
                                <a-tag v-for="evt in record.events" :key="evt" style="margin: 2px;">
                                    {{ evt.replace('s3:', '') }}
                                </a-tag>
                            </template>
                            <template v-if="column.key === 'target'">
                                {{ record.queueArn || record.topicArn || record.lambdaArn || '-' }}
                            </template>
                        </template>
                        <template #emptyText>
                            <a-empty description="No event notifications configured" />
                        </template>
                    </a-table>
                    <a-alert 
                        type="info" 
                        style="margin-top: 16px;"
                        message="Configure event notifications via CLI or API."
                        show-icon 
                    />
                </a-tab-pane>

                <!-- Replication Tab -->
                <a-tab-pane key="replication" tab="Replication">
                    <a-descriptions :column="1" bordered size="small" v-if="replication.role">
                        <a-descriptions-item label="Role ARN">
                            {{ replication.role }}
                        </a-descriptions-item>
                    </a-descriptions>
                    <a-table 
                        :columns="replicationColumns" 
                        :data-source="replication.rules" 
                        :pagination="false"
                        size="small"
                        row-key="id"
                        style="margin-top: 12px;"
                    >
                        <template #bodyCell="{ column, record }">
                            <template v-if="column.key === 'status'">
                                <a-tag :color="record.status === 'Enabled' ? 'green' : 'default'">
                                    {{ record.status }}
                                </a-tag>
                            </template>
                        </template>
                        <template #emptyText>
                            <a-empty description="No replication rules configured" />
                        </template>
                    </a-table>
                    <a-alert 
                        type="info" 
                        style="margin-top: 16px;"
                        message="Configure replication via CLI or API."
                        show-icon 
                    />
                </a-tab-pane>

                <!-- Tags Tab -->
                <a-tab-pane key="tags" tab="Tags">
                    <a-table 
                        :columns="tagColumns" 
                        :data-source="tagList" 
                        :pagination="false"
                        size="small"
                        row-key="key"
                    >
                        <template #bodyCell="{ column, record }">
                            <template v-if="column.key === 'action'">
                                <a-popconfirm title="Delete this tag?" @confirm="deleteTag(record.key)">
                                    <a-button type="link" danger size="small">Delete</a-button>
                                </a-popconfirm>
                            </template>
                        </template>
                        <template #emptyText>
                            <a-empty description="No tags configured" />
                        </template>
                    </a-table>
                    <a-divider />
                    <a-form layout="inline" style="margin-top: 12px;">
                        <a-form-item label="Key">
                            <a-input v-model:value="newTag.key" placeholder="environment" style="width: 150px;" />
                        </a-form-item>
                        <a-form-item label="Value">
                            <a-input v-model:value="newTag.value" placeholder="production" style="width: 150px;" />
                        </a-form-item>
                        <a-form-item>
                            <a-button type="primary" @click="addTag" :loading="saving">Add Tag</a-button>
                        </a-form-item>
                    </a-form>
                </a-tab-pane>
            </a-tabs>
        </a-spin>
    </a-modal>
</template>

<script setup lang="ts">
import { ref, watch, computed, reactive } from 'vue';
import { message } from 'ant-design-vue';
import * as bucketApi from '@/api/s3/bucket';
import type { LifecycleRule, NotificationConfig, ReplicationRule } from '@/api/s3/bucket';

const props = defineProps<{
    open: boolean;
    bucketName: string;
}>();

const emit = defineEmits<{
    (e: 'update:open', value: boolean): void;
}>();

const visible = computed({
    get: () => props.open,
    set: (val) => emit('update:open', val)
});

const loading = ref(false);
const saving = ref(false);
const activeTab = ref('versioning');

// Versioning
const versioningStatus = ref('Disabled');
const versioningEnabled = computed(() => versioningStatus.value === 'Enabled');

// Object Lock
const objectLockConfig = ref<{ enabled: boolean; mode?: string; days?: number; years?: number }>({ enabled: false });

// Quota
const quotaValue = ref(0);
const quotaUnit = ref('GB');

// Lifecycle
const lifecycleRules = ref<LifecycleRule[]>([]);
const lifecycleColumns = [
    { title: 'ID', dataIndex: 'id', key: 'id' },
    { title: 'Prefix', dataIndex: 'prefix', key: 'prefix' },
    { title: 'Status', key: 'status' },
    { title: 'Expire Days', dataIndex: 'expirationDays', key: 'expirationDays' },
    { title: 'Action', key: 'action', width: 80 }
];
const newRule = reactive({ id: '', prefix: '', expirationDays: 30 });

// Notifications
const notifications = ref<NotificationConfig[]>([]);
const eventColumns = [
    { title: 'ID', dataIndex: 'id', key: 'id' },
    { title: 'Events', key: 'events' },
    { title: 'Target', key: 'target' }
];

// Replication
const replication = ref<{ role: string; rules: ReplicationRule[] }>({ role: '', rules: [] });
const replicationColumns = [
    { title: 'ID', dataIndex: 'id', key: 'id' },
    { title: 'Status', key: 'status' },
    { title: 'Priority', dataIndex: 'priority', key: 'priority' },
    { title: 'Destination', dataIndex: 'destination', key: 'destination' }
];

// Tags
const tags = ref<Record<string, string>>({});
const tagList = computed(() => Object.entries(tags.value).map(([key, value]) => ({ key, value })));
const tagColumns = [
    { title: 'Key', dataIndex: 'key', key: 'key' },
    { title: 'Value', dataIndex: 'value', key: 'value' },
    { title: 'Action', key: 'action', width: 80 }
];
const newTag = reactive({ key: '', value: '' });

const fetchSettings = async () => {
    if (!props.bucketName) return;
    loading.value = true;
    try {
        const [versioningRes, lockRes, quotaRes, tagsRes, lifecycleRes, notifRes, replRes] = await Promise.all([
            bucketApi.getBucketVersioning(props.bucketName),
            bucketApi.getBucketObjectLockConfig(props.bucketName),
            bucketApi.getBucketQuota(props.bucketName),
            bucketApi.getBucketTags(props.bucketName),
            bucketApi.getBucketLifecycle(props.bucketName),
            bucketApi.getBucketNotifications(props.bucketName),
            bucketApi.getBucketReplication(props.bucketName)
        ]);
        
        versioningStatus.value = versioningRes.status;
        objectLockConfig.value = lockRes;
        
        // Convert bytes to appropriate unit
        const quotaBytes = quotaRes.quota || 0;
        if (quotaBytes >= 1024 * 1024 * 1024 * 1024) {
            quotaValue.value = quotaBytes / (1024 * 1024 * 1024 * 1024);
            quotaUnit.value = 'TB';
        } else if (quotaBytes >= 1024 * 1024 * 1024) {
            quotaValue.value = quotaBytes / (1024 * 1024 * 1024);
            quotaUnit.value = 'GB';
        } else {
            quotaValue.value = quotaBytes / (1024 * 1024);
            quotaUnit.value = 'MB';
        }
        
        tags.value = tagsRes;
        lifecycleRules.value = lifecycleRes;
        notifications.value = notifRes;
        replication.value = replRes;
    } catch (e) {
        console.error('Failed to fetch bucket settings:', e);
    } finally {
        loading.value = false;
    }
};

const enableVersioning = async () => {
    saving.value = true;
    try {
        await bucketApi.putBucketVersioning(props.bucketName, true);
        versioningStatus.value = 'Enabled';
        message.success('Versioning enabled');
    } catch (e) {
        message.error('Failed to enable versioning');
    } finally {
        saving.value = false;
    }
};

const suspendVersioning = async () => {
    saving.value = true;
    try {
        await bucketApi.putBucketVersioning(props.bucketName, false);
        versioningStatus.value = 'Suspended';
        message.success('Versioning suspended');
    } catch (e) {
        message.error('Failed to suspend versioning');
    } finally {
        saving.value = false;
    }
};

const saveQuota = async () => {
    saving.value = true;
    try {
        let quotaBytes = quotaValue.value;
        if (quotaUnit.value === 'MB') quotaBytes *= 1024 * 1024;
        else if (quotaUnit.value === 'GB') quotaBytes *= 1024 * 1024 * 1024;
        else if (quotaUnit.value === 'TB') quotaBytes *= 1024 * 1024 * 1024 * 1024;
        
        await bucketApi.putBucketQuota(props.bucketName, quotaBytes);
        message.success('Quota updated');
    } catch (e) {
        message.error('Failed to update quota');
    } finally {
        saving.value = false;
    }
};

// Lifecycle actions
const addLifecycleRule = async () => {
    if (!newRule.id) {
        message.warning('Please enter a rule ID');
        return;
    }
    saving.value = true;
    try {
        const updatedRules = [...lifecycleRules.value, {
            id: newRule.id,
            prefix: newRule.prefix,
            status: 'Enabled' as const,
            expirationDays: newRule.expirationDays
        }];
        await bucketApi.putBucketLifecycle(props.bucketName, updatedRules);
        lifecycleRules.value = updatedRules;
        newRule.id = '';
        newRule.prefix = '';
        newRule.expirationDays = 30;
        message.success('Lifecycle rule added');
    } catch (e) {
        message.error('Failed to add lifecycle rule');
    } finally {
        saving.value = false;
    }
};

const deleteLifecycleRule = async (ruleId: string) => {
    saving.value = true;
    try {
        const updatedRules = lifecycleRules.value.filter(r => r.id !== ruleId);
        if (updatedRules.length === 0) {
            await bucketApi.deleteBucketLifecycle(props.bucketName);
        } else {
            await bucketApi.putBucketLifecycle(props.bucketName, updatedRules);
        }
        lifecycleRules.value = updatedRules;
        message.success('Lifecycle rule deleted');
    } catch (e) {
        message.error('Failed to delete lifecycle rule');
    } finally {
        saving.value = false;
    }
};

// Tag actions
const addTag = async () => {
    if (!newTag.key) {
        message.warning('Please enter a tag key');
        return;
    }
    saving.value = true;
    try {
        const updatedTags = { ...tags.value, [newTag.key]: newTag.value };
        await bucketApi.putBucketTags(props.bucketName, updatedTags);
        tags.value = updatedTags;
        newTag.key = '';
        newTag.value = '';
        message.success('Tag added');
    } catch (e) {
        message.error('Failed to add tag');
    } finally {
        saving.value = false;
    }
};

const deleteTag = async (tagKey: string) => {
    saving.value = true;
    try {
        const updatedTags = { ...tags.value };
        delete updatedTags[tagKey];
        if (Object.keys(updatedTags).length === 0) {
            await bucketApi.deleteBucketTags(props.bucketName);
        } else {
            await bucketApi.putBucketTags(props.bucketName, updatedTags);
        }
        tags.value = updatedTags;
        message.success('Tag deleted');
    } catch (e) {
        message.error('Failed to delete tag');
    } finally {
        saving.value = false;
    }
};

const handleClose = () => {
    visible.value = false;
};

watch(() => props.open, (newVal) => {
    if (newVal) {
        activeTab.value = 'versioning';
        fetchSettings();
    }
});
</script>
