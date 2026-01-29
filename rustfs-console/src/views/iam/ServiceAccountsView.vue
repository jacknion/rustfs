<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>IAM</a-breadcrumb-item>
            <a-breadcrumb-item>Service Accounts</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="primary" @click="showCreateModal">Create Service Account</a-button>
        </template>

      <a-table :columns="columns" :data-source="accounts" :loading="loading" row-key="accessKey">
         <template #bodyCell="{ column, record }">
             <template v-if="column.key === 'status'">
                 <a-tag :color="record.accountStatus === 'on' ? 'green' : 'red'">
                     {{ record.accountStatus === 'on' ? 'Active' : 'Inactive' }}
                 </a-tag>
             </template>
             <template v-if="column.key === 'expiration'">
                 {{ record.expiration ? new Date(record.expiration).toLocaleString() : 'Never' }}
             </template>
             <template v-if="column.key === 'action'">
                 <a-button type="link" @click="viewDetails(record.accessKey)">View</a-button>
                 <a-popconfirm title="Delete?" @confirm="handleDelete(record.accessKey)">
                     <a-button type="link" danger>Delete</a-button>
                 </a-popconfirm>
             </template>
         </template>
      </a-table>

      <!-- Details Drawer -->
      <a-drawer
          v-model:open="detailsVisible"
          title="Service Account Details"
          placement="right"
          width="450"
      >
          <a-spin :spinning="detailsLoading">
              <div v-if="currentAccount">
                  <a-descriptions :column="1" bordered size="small">
                      <a-descriptions-item label="Access Key">
                          <code>{{ currentAccount.accessKey }}</code>
                      </a-descriptions-item>
                      <a-descriptions-item label="Parent User">
                          {{ currentAccount.parentUser }}
                      </a-descriptions-item>
                      <a-descriptions-item label="Status">
                          <a-tag :color="currentAccount.accountStatus === 'on' ? 'green' : 'red'">
                              {{ currentAccount.accountStatus === 'on' ? 'Active' : 'Inactive' }}
                          </a-tag>
                      </a-descriptions-item>
                      <a-descriptions-item label="Name">
                          {{ currentAccount.name || '-' }}
                      </a-descriptions-item>
                      <a-descriptions-item label="Description">
                          {{ currentAccount.description || '-' }}
                      </a-descriptions-item>
                      <a-descriptions-item label="Expiration">
                          {{ currentAccount.expiration ? new Date(currentAccount.expiration).toLocaleString() : 'Never' }}
                      </a-descriptions-item>
                      <a-descriptions-item label="Implied Policy">
                          {{ currentAccount.impliedPolicy ? 'Yes' : 'No' }}
                      </a-descriptions-item>
                  </a-descriptions>
                  
                  <div style="margin-top: 16px;">
                      <a-button 
                          v-if="currentAccount.accountStatus === 'on'"
                          type="default"
                          danger
                          @click="updateStatus('off')"
                          :loading="updateLoading"
                      >
                          Disable Account
                      </a-button>
                      <a-button 
                          v-else
                          type="primary"
                          @click="updateStatus('on')"
                          :loading="updateLoading"
                      >
                          Enable Account
                      </a-button>
                  </div>
              </div>
          </a-spin>
      </a-drawer>

      <!-- Create Modal -->
      <a-modal v-model:open="visible" title="Create Service Account" @ok="handleCreate" width="600px">
        <a-form layout="vertical">
            <a-form-item label="Target User">
                <a-input v-model:value="form.targetUser" placeholder="Leave empty for current user" />
            </a-form-item>
            <a-form-item label="Name" required>
                <a-input v-model:value="form.name" />
            </a-form-item>
            <a-form-item label="Description">
                <a-textarea v-model:value="form.description" />
            </a-form-item>
            <a-row :gutter="16">
                <a-col :span="12">
                    <a-form-item label="Access Key" required>
                        <a-input v-model:value="form.accessKey" />
                        <a-button type="link" size="small" @click="generateKeys">Generate</a-button>
                    </a-form-item>
                </a-col>
                <a-col :span="12">
                    <a-form-item label="Secret Key" required>
                        <a-input v-model:value="form.secretKey" />
                    </a-form-item>
                </a-col>
            </a-row>
             <a-form-item label="Policy">
                 <a-textarea v-model:value="form.policy" placeholder="Optional JSON policy" :rows="4" />
             </a-form-item>
        </a-form>
      </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, onMounted, reactive } from 'vue';
import { message } from 'ant-design-vue';
import * as saApi from '@/api/modules/service-accounts';
import type { ServiceAccountInfo } from '@/types/iam';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const accounts = ref<ServiceAccountInfo[]>([]);
const visible = ref(false);

// Details drawer state
const detailsVisible = ref(false);
const detailsLoading = ref(false);
const updateLoading = ref(false);
const currentAccount = ref<ServiceAccountInfo | null>(null);

const form = reactive({
    targetUser: '',
    name: '',
    description: '',
    accessKey: '',
    secretKey: '',
    policy: ''
});

const columns = [
    { title: 'Access Key', dataIndex: 'accessKey', key: 'accessKey' },
    { title: 'Parent User', dataIndex: 'parentUser', key: 'parentUser' },
    { title: 'Status', dataIndex: 'accountStatus', key: 'status' },
    { title: 'Name', dataIndex: 'name', key: 'name' },
    { title: 'Expiration', dataIndex: 'expiration', key: 'expiration' },
    { title: 'Action', key: 'action' }
];

const fetchAccounts = async () => {
    loading.value = true;
    try {
        const res = await saApi.getServiceAccounts();
        accounts.value = res.data.accounts || [];
    } catch (error) {
        message.error('Failed to fetch service accounts');
    } finally {
        loading.value = false;
    }
};

const viewDetails = async (accessKey: string) => {
    detailsVisible.value = true;
    detailsLoading.value = true;
    try {
        const res = await saApi.getServiceAccountInfo(accessKey);
        currentAccount.value = res.data;
    } catch (error) {
        message.error('Failed to fetch service account details');
    } finally {
        detailsLoading.value = false;
    }
};

const updateStatus = async (newStatus: 'on' | 'off') => {
    if (!currentAccount.value) return;
    updateLoading.value = true;
    try {
        await saApi.updateServiceAccount(currentAccount.value.accessKey, {
            newStatus
        });
        message.success(`Service account ${newStatus === 'on' ? 'enabled' : 'disabled'}`);
        currentAccount.value.accountStatus = newStatus;
        fetchAccounts();
    } catch (error) {
        message.error('Failed to update service account');
    } finally {
        updateLoading.value = false;
    }
};

const handleDelete = async (accessKey: string) => {
    try {
        await saApi.deleteServiceAccount(accessKey);
        message.success('Service account deleted');
        fetchAccounts();
    } catch (error) {
        message.error('Failed to delete service account');
    }
};

const showCreateModal = () => {
    form.targetUser = '';
    form.name = '';
    form.description = '';
    form.policy = '';
    generateKeys();
    visible.value = true;
};

const generateKeys = () => {
    // Simple random generation for demo
    form.accessKey = 'SA' + Math.random().toString(36).substring(2, 10).toUpperCase();
    form.secretKey = Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
};

const handleCreate = async () => {
    if (!form.accessKey || !form.secretKey || !form.name) {
        message.error('Access Key, Secret Key and Name are required');
        return;
    }
    try {
        await saApi.addServiceAccount({
            accessKey: form.accessKey,
            secretKey: form.secretKey,
            name: form.name,
            description: form.description,
            targetUser: form.targetUser || undefined,
            policy: form.policy || undefined
        });
        message.success('Service account created');
        visible.value = false;
        fetchAccounts();
    } catch (error) {
        message.error('Failed to create service account');
    }
};

onMounted(() => {
    fetchAccounts();
});
</script>

