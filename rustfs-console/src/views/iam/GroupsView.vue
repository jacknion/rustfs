<template>
    <PageContainer>
        <template #breadcrumb>
            <a-breadcrumb-item>IAM</a-breadcrumb-item>
            <a-breadcrumb-item>Groups</a-breadcrumb-item>
        </template>

        <template #header>
            <a-button type="primary" @click="showCreateModal">Create Group</a-button>
        </template>

        <a-list bordered :data-source="groups" :loading="loading">
            <template #header>
                <div v-if="groups.length === 0 && !loading" style="text-align: center; color: #999; padding: 20px;">
                    No data
                </div>
            </template>
            <template #renderItem="{ item }">
                <a-list-item>
                    <a-list-item-meta :title="item" description="Group">
                        <template #avatar>
                            <a-avatar style="background-color: #87d068">G</a-avatar>
                        </template>
                    </a-list-item-meta>
                    <template #actions>
                        <a-button type="link" @click="viewGroup(item)">Details</a-button>
                        <a-button type="link" @click="toggleStatus(item, 'enabled')">Enable</a-button>
                        <a-popconfirm
                            title="Disable this group?"
                            @confirm="toggleStatus(item, 'disabled')"
                        >
                            <a-button type="link" danger>Disable</a-button>
                        </a-popconfirm>
                    </template>
                </a-list-item>
            </template>
        </a-list>
    
        <!-- Group Details Drawer -->
        <a-drawer
            v-model:open="drawerVisible"
            title="Group Details"
            placement="right"
            width="400"
        >
            <div v-if="currentGroup">
                <p><strong>Name:</strong> {{ currentGroup.name }}</p>
                <p><strong>Status:</strong> {{ currentGroup.status }}</p>
                <p><strong>Policy:</strong> {{ currentGroup.policy }}</p>
                <p><strong>Members:</strong></p>
                <ul>
                    <li v-for="member in currentGroup.members" :key="member">{{ member }}</li>
                </ul>
                <a-empty v-if="!currentGroup.members || currentGroup.members.length === 0" description="No members" />
            </div>
        </a-drawer>

        <!-- Create Group Modal -->
        <a-modal 
            v-model:open="createVisible" 
            title="Create Group" 
            @ok="handleCreate"
            :confirm-loading="createLoading"
        >
            <a-form layout="vertical">
                <a-form-item label="Group Name" required>
                    <a-input v-model:value="form.groupName" placeholder="Enter group name" />
                </a-form-item>
                <a-form-item label="Initial Members" required>
                    <a-select
                        v-model:value="form.members"
                        mode="multiple"
                        placeholder="Select users to add"
                        :options="userOptions"
                        style="width: 100%"
                    />
                </a-form-item>
                <a-alert 
                    type="info" 
                    message="Groups are created by adding members. At least one member is required."
                    show-icon 
                    style="margin-top: 8px"
                />
            </a-form>
        </a-modal>
    </PageContainer>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { message } from 'ant-design-vue';
import * as groupApi from '@/api/modules/groups';
import * as userApi from '@/api/modules/users';
import type { GroupDesc } from '@/types/iam';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const groups = ref<string[]>([]);
const drawerVisible = ref(false);
const currentGroup = ref<GroupDesc | null>(null);

// Create modal state
const createVisible = ref(false);
const createLoading = ref(false);
const userOptions = ref<{label: string; value: string}[]>([]);
const form = ref({
    groupName: '',
    members: [] as string[]
});

const fetchGroups = async () => {
    loading.value = true;
    try {
        const res = await groupApi.getGroups();
        groups.value = res.data || [];
    } catch (error) {
        message.error('Failed to fetch groups');
    } finally {
        loading.value = false;
    }
};

const fetchUsers = async () => {
    try {
        const res = await userApi.getUsers();
        const usersMap = res.data || {};
        userOptions.value = Object.keys(usersMap).map(key => ({
            label: key,
            value: key
        }));
    } catch (error) {
        console.error('Failed to fetch users for selection');
    }
};

const viewGroup = async (groupName: string) => {
    try {
        const res = await groupApi.getGroupInfo(groupName);
        currentGroup.value = res.data;
        drawerVisible.value = true;
    } catch (error) {
        message.error('Failed to load group details');
    }
};

const toggleStatus = async (groupName: string, status: 'enabled' | 'disabled') => {
    try {
        await groupApi.setGroupStatus(groupName, status);
        message.success(`Group ${status}`);
        fetchGroups();
    } catch (error) {
        message.error('Failed to update group status');
    }
};

const showCreateModal = async () => {
    form.value = { groupName: '', members: [] };
    await fetchUsers();
    createVisible.value = true;
};

const handleCreate = async () => {
    if (!form.value.groupName.trim()) {
        message.error('Group name is required');
        return;
    }
    if (form.value.members.length === 0) {
        message.error('At least one member is required');
        return;
    }
    
    createLoading.value = true;
    try {
        await groupApi.updateGroupMembers({
            group: form.value.groupName,
            members: form.value.members,
            isRemove: false
        });
        message.success('Group created successfully');
        createVisible.value = false;
        fetchGroups();
    } catch (error) {
        message.error('Failed to create group');
    } finally {
        createLoading.value = false;
    }
};

onMounted(() => {
    fetchGroups();
});
</script>

