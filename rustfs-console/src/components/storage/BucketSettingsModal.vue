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
                <!-- Access Policy Tab -->
                <a-tab-pane key="access" tab="Access Policy">
                    <a-alert 
                        style="margin-bottom: 16px;"
                        :message="accessLevelDescription"
                        :type="accessLevel === 'private' ? 'success' : accessLevel === 'public' ? 'error' : 'warning'"
                        show-icon 
                    />
                    <a-form layout="vertical">
                        <a-form-item label="Anonymous Access">
                            <a-radio-group v-model:value="accessLevel" button-style="solid" @change="onAccessLevelChange">
                                <a-radio-button value="private">Private</a-radio-button>
                                <a-radio-button value="download">Download</a-radio-button>
                                <a-radio-button value="upload">Upload</a-radio-button>
                                <a-radio-button value="public">Public</a-radio-button>
                                <a-radio-button value="custom">Custom</a-radio-button>
                            </a-radio-group>
                            <div style="color: #888; font-size: 12px; margin-top: 8px;">
                                <div v-if="accessLevel === 'private'">All access requires authentication (AccessKey/SecretKey)</div>
                                <div v-else-if="accessLevel === 'download'">Anyone can download and list objects without authentication</div>
                                <div v-else-if="accessLevel === 'upload'">Anyone can upload objects without authentication</div>
                                <div v-else-if="accessLevel === 'public'">Anyone can upload, download, and delete objects without authentication</div>
                                <div v-else>Custom policy — edit the JSON below</div>
                            </div>
                        </a-form-item>
                        <a-form-item v-if="accessLevel === 'custom'" label="Policy JSON">
                            <a-textarea 
                                v-model:value="policyJson" 
                                :rows="12" 
                                style="font-family: monospace; font-size: 12px;"
                                placeholder='{&#10;  "Version": "2012-10-17",&#10;  "Statement": []&#10;}'
                            />
                        </a-form-item>
                        <a-form-item>
                            <a-space>
                                <a-button type="primary" @click="saveAccessPolicy" :loading="saving">
                                    Save Policy
                                </a-button>
                                <a-popconfirm 
                                    v-if="accessLevel !== 'private'" 
                                    title="Remove all anonymous access?" 
                                    @confirm="removePolicy"
                                >
                                    <a-button danger :loading="saving">Remove Policy</a-button>
                                </a-popconfirm>
                            </a-space>
                        </a-form-item>
                    </a-form>
                </a-tab-pane>

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
            </a-tabs>
        </a-spin>
    </a-modal>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { message } from 'ant-design-vue';
import * as bucketApi from '@/api/s3/bucket';
import type { AccessLevel } from '@/api/s3/bucket';

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
const activeTab = ref('access');

// Access Policy
const accessLevel = ref<AccessLevel>('private');
const policyJson = ref('');
const accessLevelDescription = computed(() => {
    switch (accessLevel.value) {
        case 'private': return 'This bucket is private. All access requires authentication.';
        case 'download': return 'This bucket allows anonymous download and listing.';
        case 'upload': return 'This bucket allows anonymous upload.';
        case 'public': return 'Warning: This bucket is fully public. Anyone can read and write.';
        case 'custom': return 'This bucket has a custom access policy.';
        default: return '';
    }
});

// Versioning
const versioningStatus = ref('Disabled');
const versioningEnabled = computed(() => versioningStatus.value === 'Enabled');

// Quota
const quotaValue = ref(0);
const quotaUnit = ref('GB');

const onAccessLevelChange = () => {
    if (accessLevel.value !== 'custom') {
        policyJson.value = bucketApi.generatePolicy(props.bucketName, accessLevel.value);
    }
};

const saveAccessPolicy = async () => {
    saving.value = true;
    try {
        if (accessLevel.value === 'private') {
            await bucketApi.deleteBucketPolicy(props.bucketName);
            policyJson.value = '';
        } else {
            const policy = accessLevel.value === 'custom' 
                ? policyJson.value 
                : bucketApi.generatePolicy(props.bucketName, accessLevel.value);
            if (!policy) {
                await bucketApi.deleteBucketPolicy(props.bucketName);
            } else {
                await bucketApi.putBucketPolicy(props.bucketName, policy);
            }
            policyJson.value = policy;
        }
        message.success('Access policy updated');
    } catch (e: any) {
        message.error('Failed to update access policy: ' + (e.message || 'Unknown error'));
    } finally {
        saving.value = false;
    }
};

const removePolicy = async () => {
    saving.value = true;
    try {
        await bucketApi.deleteBucketPolicy(props.bucketName);
        accessLevel.value = 'private';
        policyJson.value = '';
        message.success('Access policy removed');
    } catch (e) {
        message.error('Failed to remove access policy');
    } finally {
        saving.value = false;
    }
};

const fetchSettings = async () => {
    if (!props.bucketName) return;
    loading.value = true;
    try {
        const results = await Promise.allSettled([
            bucketApi.getBucketPolicy(props.bucketName),
            bucketApi.getBucketVersioning(props.bucketName),
            bucketApi.getBucketQuota(props.bucketName),
        ]);

        const val = <T>(r: PromiseSettledResult<T>, fallback: T): T =>
            r.status === 'fulfilled' ? r.value : fallback;

        // Access Policy
        const policyRes = val(results[0], '');
        policyJson.value = policyRes;
        accessLevel.value = bucketApi.detectAccessLevel(policyRes);
        
        versioningStatus.value = val(results[1], { status: 'Disabled' }).status;
        
        // Convert bytes to appropriate unit
        const quotaBytes = val(results[2], { quota: 0 }).quota || 0;
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

const handleClose = () => {
    visible.value = false;
};

watch(() => props.open, (newVal) => {
    if (newVal) {
        activeTab.value = 'access';
        fetchSettings();
    }
});
</script>
