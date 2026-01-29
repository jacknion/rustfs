<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>IAM</a-breadcrumb-item>
            <a-breadcrumb-item>Policies</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="primary" @click="showCreateModal">Create Policy</a-button>
        </template>

        <a-list bordered :data-source="policyList" :loading="loading">
             <template #renderItem="{ item }">
                <a-list-item>
                    <a-list-item-meta :title="item.name">
                        <template #description>
                            Version: {{ item.policy.Version }}
                        </template>
                    </a-list-item-meta>
                    <template #actions>
                        <a-button type="link" @click="viewPolicy(item.policy)">View JSON</a-button>
                         <a-popconfirm
                            title="Delete this policy?"
                            @confirm="handleDelete(item.name)"
                          >
                            <a-button type="link" danger>Delete</a-button>
                          </a-popconfirm>
                    </template>
                </a-list-item>
            </template>
        </a-list>

    <a-modal v-model:open="jsonVisible" title="Policy Document" :footer="null" width="700px">
        <JsonViewer :data="currentPolicyJson" />
    </a-modal>

    <a-modal v-model:open="createVisible" title="Create Policy" @ok="handleCreate" width="600px">
        <a-form layout="vertical">
            <a-form-item label="Policy Name" required>
                <a-input v-model:value="createForm.name" />
            </a-form-item>
            <a-form-item label="Policy JSON" required help="Enter valid JSON policy">
                 <a-textarea v-model:value="createForm.json" :rows="10" />
            </a-form-item>
        </a-form>
    </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, onMounted, reactive } from 'vue';
import { message } from 'ant-design-vue';
import * as policyApi from '@/api/modules/policies';
import type { Policy } from '@/types/iam';
import PageContainer from '@/components/layout/PageContainer.vue';
import JsonViewer from '@/components/common/JsonViewer.vue';

const loading = ref(false);
const policyList = ref<{name: string, policy: Policy}[]>([]);
const jsonVisible = ref(false);
const currentPolicyJson = ref<any>({});

const createVisible = ref(false);
const createForm = reactive({
    name: '',
    json: `{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::*"]
    }
  ]
}`
});

const fetchPolicies = async () => {
    loading.value = true;
    try {
        const res = await policyApi.getPolicies();
        policyList.value = Object.entries(res.data).map(([name, policy]) => ({
            name,
            policy
        }));
    } catch (error) {
        message.error('Failed to fetch policies');
    } finally {
        loading.value = false;
    }
};

const viewPolicy = (policy: Policy) => {
    currentPolicyJson.value = policy;
    jsonVisible.value = true;
};

const handleDelete = async (name: string) => {
    try {
        await policyApi.removePolicy(name);
        message.success('Policy removed');
        fetchPolicies();
    } catch (error) {
         message.error('Failed to remove policy');
    }
};

const showCreateModal = () => {
    createForm.name = '';
    createVisible.value = true;
};

const handleCreate = async () => {
    try {
        const policyObj = JSON.parse(createForm.json);
        await policyApi.addPolicy(createForm.name, policyObj);
        message.success('Policy created');
        createVisible.value = false;
        fetchPolicies();
    } catch (error) {
        message.error('Invalid JSON or Create Failed');
    }
};

onMounted(() => {
    fetchPolicies();
});
</script>
