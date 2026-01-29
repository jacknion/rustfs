<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>Storage</a-breadcrumb-item>
            <a-breadcrumb-item><router-link to="/storage/buckets">Buckets</router-link></a-breadcrumb-item>
            <a-breadcrumb-item>{{ bucketName }}</a-breadcrumb-item>
            <a-breadcrumb-item v-for="(crumb, index) in breadcrumbs" :key="index">
                <a @click.prevent="navigateToPrefix(crumb.prefix)">{{ crumb.name }}</a>
            </a-breadcrumb-item>
        </template>

        <template #header>
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <h3 style="margin: 0">Browser: /{{ currentPrefix }}</h3>
                <a-upload :customRequest="handleUpload" :showUploadList="false">
                    <a-button type="primary">Upload File</a-button>
                </a-upload>
            </div>
        </template>

        <a-table :columns="columns" :data-source="objects" :loading="loading" row-key="key">
             <template #bodyCell="{ column, record }">
                 <template v-if="column.key === 'name'">
                     <a v-if="record.type === 'folder'" @click.prevent="enterFolder(record.key)">
                        📁 {{ record.name }}
                     </a>
                     <span v-else>
                        📄 {{ record.name }}
                     </span>
                 </template>
                 <template v-if="column.key === 'size'">
                     <span v-if="record.type === 'file'">{{ formatBytes(record.size) }}</span>
                     <span v-else>-</span>
                 </template>
                 <template v-if="column.key === 'lastModified'">
                     <span v-if="record.type === 'file'">{{ new Date(record.lastModified).toLocaleString() }}</span>
                     <span v-else>-</span>
                 </template>
                 <template v-if="column.key === 'action'">
                      <template v-if="record.type === 'file'">
                        <a-button type="link" @click="download(record.key)">Download</a-button>
                        <a-popconfirm title="Delete object?" @confirm="deleteObj(record.key)">
                            <a-button type="link" danger>Delete</a-button>
                        </a-popconfirm>
                      </template>
                 </template>
             </template>
        </a-table>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { message } from 'ant-design-vue';
import * as bucketApi from '@/api/s3/bucket';
import PageContainer from '@/components/layout/PageContainer.vue';

const route = useRoute();
const router = useRouter();
const bucketName = computed(() => route.params.name as string);
const currentPrefix = computed(() => (route.query.prefix as string) || '');
const loading = ref(false);
const objects = ref<any[]>([]);

const columns = [
    { title: 'Name', dataIndex: 'name', key: 'name' },
    { title: 'Size', dataIndex: 'size', key: 'size' },
    { title: 'Last Modified', dataIndex: 'lastModified', key: 'lastModified' },
    { title: 'Action', key: 'action' }
];

const breadcrumbs = computed(() => {
    const parts = currentPrefix.value.split('/').filter(p => p);
    let accum = '';
    return parts.map(p => {
        accum += p + '/';
        return { name: p, prefix: accum };
    });
});

const loadObjects = async () => {
    loading.value = true;
    try {
        objects.value = await bucketApi.listObjects(bucketName.value, currentPrefix.value);
    } catch (e) {
        message.error('Failed to load objects');
    } finally {
        loading.value = false;
    }
};

const navigateToPrefix = (prefix: string) => {
    router.push({ query: { ...route.query, prefix } });
};

const enterFolder = (key: string) => {
    navigateToPrefix(key);
};

const handleUpload = async (options: any) => {
    const { file, onSuccess, onError } = options;
    const key = currentPrefix.value + file.name;
    try {
        await bucketApi.putObject(bucketName.value, key, file);
        message.success('Uploaded ' + file.name);
        onSuccess(file);
        loadObjects();
    } catch (e) {
        message.error('Upload failed');
        onError(e);
    }
};

const deleteObj = async (key: string) => {
    try {
        await bucketApi.deleteObject(bucketName.value, key);
        message.success('Deleted object');
        loadObjects();
    } catch (e) {
        message.error('Delete failed');
    }
};

const download = async (key: string) => {
    try {
        await bucketApi.downloadObject(bucketName.value, key);
    } catch (e) {
        message.error('Download failed');
    }
};

const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

watch(() => [bucketName.value, currentPrefix.value], () => {
    if (bucketName.value) {
        loadObjects();
    }
}, { immediate: true });

</script>
