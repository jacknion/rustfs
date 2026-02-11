<template>
  <PageContainer>
    <template #breadcrumb>
      <a-breadcrumb-item>IAM</a-breadcrumb-item>
      <a-breadcrumb-item>Users</a-breadcrumb-item>
    </template>

    <template #header>
      <a-button type="primary" @click="showAddModal">
        <template #icon><plus-outlined /></template>
        Create User
      </a-button>
    </template>

      <a-alert
        v-if="!loading && users.length === 0"
        type="info"
        show-icon
        style="margin-bottom: 12px"
        message="No IAM users yet"
        description="This list only shows IAM users created in RustFS. The root/admin credentials you use to log in (e.g. rustfsadmin) are not listed here. Click 'Create User' to add one."
      />

      <a-table :columns="columns" :data-source="users" :loading="loading" row-key="accessKey">
        <template #bodyCell="{ column, record }">
          <template v-if="column.key === 'status'">
            <a-tag :color="record.status === 'enabled' ? 'green' : 'red'">
              {{ record.status.toUpperCase() }}
            </a-tag>
          </template>
          <template v-if="column.key === 'action'">
            <a-space>
              <a-button type="link" size="small" @click="toggleStatus(record)">
                {{ record.status === 'enabled' ? 'Disable' : 'Enable' }}
              </a-button>
              <a-popconfirm
                title="Are you sure delete this user?"
                @confirm="handleDelete(record)"
              >
                <a-button type="link" danger size="small">Delete</a-button>
              </a-popconfirm>
            </a-space>
          </template>
        </template>
      </a-table>

      <a-modal
        v-model:open="visible"
        title="Create User"
        @ok="handleCreate"
        :confirmLoading="creating"
      >
        <a-form layout="vertical">
          <a-form-item label="Access Key" required>
            <a-input v-model:value="form.accessKey" />
          </a-form-item>
          <a-form-item label="Secret Key" required>
            <a-input-password v-model:value="form.secretKey" />
          </a-form-item>
          <a-form-item label="Policy">
             <a-select v-model:value="form.policy" style="width: 100%" placeholder="Select Policy" allowClear>
                <a-select-option v-for="p in policies" :key="p" :value="p">{{ p }}</a-select-option>
             </a-select>
          </a-form-item>
        </a-form>
      </a-modal>
  </PageContainer>
</template>

<script setup lang="ts">
import { ref, onMounted, reactive } from 'vue';
import { PlusOutlined } from '@ant-design/icons-vue';
import { message } from 'ant-design-vue';
import * as userApi from '@/api/modules/users';
import * as policyApi from '@/api/modules/policies';
import type { UserInfo } from '@/types/iam';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const users = ref<UserInfo[]>([]);
const visible = ref(false);
const creating = ref(false);
const policies = ref<string[]>([]);

const form = reactive({
  accessKey: '',
  secretKey: '',
  policy: undefined as string | undefined,
});

const columns = [
  { title: 'Access Key', dataIndex: 'accessKey', key: 'accessKey' },
  { title: 'Status', dataIndex: 'status', key: 'status' },
  { title: 'Policy', dataIndex: 'policyName', key: 'policyName' },
  { title: 'Action', key: 'action' },
];

const fetchUsers = async () => {
  loading.value = true;
  try {
    const res = await userApi.getUsers();
    // API returns Map<AccessKey, UserInfo>
    // We need to inject AccessKey into UserInfo for the table
    const data = res.data as Record<string, UserInfo>;
    users.value = Object.entries(data).map(([key, info]) => ({
      ...(info as UserInfo),
      accessKey: key,
    }));
  } catch (error) {
    message.error('Failed to fetch users');
  } finally {
    loading.value = false;
  }
};

const fetchPolicies = async () => {
  try {
    const res = await policyApi.getPolicies();
    policies.value = Object.keys(res.data);
  } catch (error) {
    // optional
  }
}

// Generate random alphanumeric string
const generateRandomString = (length: number): string => {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const array = new Uint8Array(length);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => chars[byte % chars.length]).join('');
};

const showAddModal = () => {
  // Auto-generate access key (20 chars) and secret key (40 chars)
  form.accessKey = generateRandomString(20);
  form.secretKey = generateRandomString(40);
  form.policy = undefined;
  fetchPolicies();
  visible.value = true;
};

const handleCreate = async () => {
  if (!form.accessKey || !form.secretKey) {
    message.error('Please fill in required fields');
    return;
  }
  
  creating.value = true;
  try {
    await userApi.addUser(form.accessKey, {
      secretKey: form.secretKey,
      status: 'enabled',
      policy: form.policy,
    });
    message.success('User created successfully');
    visible.value = false;
    fetchUsers();
  } catch (error) {
    message.error('Failed to create user');
  } finally {
    creating.value = false;
  }
};

const toggleStatus = async (user: UserInfo) => {
  if (!user.accessKey) return;
  const newStatus = user.status === 'enabled' ? 'disabled' : 'enabled';
  try {
    await userApi.setUserStatus(user.accessKey, newStatus);
    message.success(`User ${newStatus}`);
    fetchUsers();
  } catch (error) {
    message.error('Failed to update status');
  }
};

const handleDelete = async (user: UserInfo) => {
  if (!user.accessKey) return;
  try {
    await userApi.deleteUser(user.accessKey);
    message.success('User deleted');
    fetchUsers();
  } catch (error) {
    message.error('Failed to delete user');
  }
};

onMounted(() => {
  fetchUsers();
});
</script>
