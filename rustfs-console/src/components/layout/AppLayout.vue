<template>
  <a-layout class="app-layout">
    <a-layout-sider v-model:collapsed="collapsed" collapsible class="app-sider">
      <div class="logo">RustFS</div>
      <a-menu v-model:selectedKeys="selectedKeys" theme="dark" mode="inline" @click="handleMenuClick">
        <a-menu-item key="dashboard">
          <pie-chart-outlined />
          <span>Dashboard</span>
        </a-menu-item>
        
        <a-sub-menu key="iam">
            <template #title>
                <span>
                    <team-outlined />
                    <span>Identity</span>
                </span>
            </template>
            <a-menu-item key="users">Users</a-menu-item>
            <a-menu-item key="groups">Groups</a-menu-item>
            <a-menu-item key="policies">Policies</a-menu-item>
            <a-menu-item key="service-accounts">Service Accounts</a-menu-item>
        </a-sub-menu>

        <a-sub-menu key="storage">
            <template #title>
                <span>
                    <hdd-outlined />
                    <span>Storage</span>
                </span>
            </template>
            <a-menu-item key="buckets">Buckets</a-menu-item>
            <a-menu-item key="pools">Pools</a-menu-item>
        </a-sub-menu>

        <a-sub-menu key="monitoring">
            <template #title>
                <span>
                    <bar-chart-outlined />
                    <span>Monitoring</span>
                </span>
            </template>
            <a-menu-item key="storage-monitoring">Storage Monitoring</a-menu-item>
            <a-menu-item key="metrics">Metrics</a-menu-item>
        </a-sub-menu>

        <a-sub-menu key="maintenance">
            <template #title>
                <span>
                    <tool-outlined />
                    <span>Maintenance</span>
                </span>
            </template>
            <a-menu-item key="heal">Data Healing</a-menu-item>
            <a-menu-item key="tier">Tiers</a-menu-item>
            <a-menu-item key="rebalance">Rebalance</a-menu-item>
        </a-sub-menu>

        <a-sub-menu key="security">
            <template #title>
                <span>
                    <lock-outlined />
                    <span>Security</span>
                </span>
            </template>
            <a-menu-item key="kms">KMS</a-menu-item>
        </a-sub-menu>

        <a-sub-menu key="settings">
            <template #title>
                <span>
                    <setting-outlined />
                    <span>Settings</span>
                </span>
            </template>
            <a-menu-item key="replication">Replication</a-menu-item>
            <a-menu-item key="notifications">Notifications</a-menu-item>
        </a-sub-menu>

        <a-sub-menu key="tools">
            <template #title>
                <span>
                    <code-outlined />
                    <span>Tools</span>
                </span>
            </template>
            <a-menu-item key="metadata-query">Metadata Query</a-menu-item>
        </a-sub-menu>

        <a-menu-item key="logout" @click="handleLogout">
          <logout-outlined />
          <span>Logout</span>
        </a-menu-item>
      </a-menu>
    </a-layout-sider>
    <a-layout class="app-main">
      <a-layout-header class="app-header">
        <div class="app-header-right">
          <a-button type="text" @click="handleLogout">Logout</a-button>
        </div>
      </a-layout-header>
      <a-layout-content class="app-content">
        <router-view />
      </a-layout-content>
      <a-layout-footer class="app-footer">RustFS Console ©2025 Created by RustFS Team</a-layout-footer>
    </a-layout>
  </a-layout>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue';
import { PieChartOutlined, HddOutlined, LogoutOutlined, TeamOutlined, BarChartOutlined, ToolOutlined, LockOutlined, SettingOutlined, CodeOutlined } from '@ant-design/icons-vue';
import { useAuthStore } from '@/stores/auth';
import { useRouter, useRoute } from 'vue-router';

const collapsed = ref(false);
const selectedKeys = ref<string[]>(['dashboard']); // default
const authStore = useAuthStore();
const router = useRouter();
const route = useRoute();

const handleLogout = () => {
  authStore.logout();
  router.push('/login');
};

const handleMenuClick = (e: any) => {
    if (e.key === 'logout') return;
    if (e.key === 'dashboard') router.push('/');
    else if (e.key === 'users') router.push('/iam/users');
    else if (e.key === 'groups') router.push('/iam/groups');
    else if (e.key === 'policies') router.push('/iam/policies');
    else if (e.key === 'service-accounts') router.push('/iam/service-accounts');
    else if (e.key === 'buckets') router.push('/storage/buckets');
    else if (e.key === 'pools') router.push('/storage/pools');
    else if (e.key === 'storage-monitoring') router.push('/monitoring/usage');
    else if (e.key === 'metrics') router.push('/monitoring/metrics');
    else if (e.key === 'heal') router.push('/maintenance/heal');
    else if (e.key === 'tier') router.push('/maintenance/tier');
    else if (e.key === 'rebalance') router.push('/maintenance/rebalance');
    else if (e.key === 'kms') router.push('/security/kms');
    else if (e.key === 'replication') router.push('/settings/replication');
    else if (e.key === 'notifications') router.push('/settings/notifications');
    else if (e.key === 'metadata-query') router.push('/tools/metadata-query');
};

// Sync menu with route
watch(
    () => route.path,
    (path) => {
        if (path === '/') selectedKeys.value = ['dashboard'];
        else if (path.includes('/iam/users')) selectedKeys.value = ['users'];
        else if (path.includes('/iam/groups')) selectedKeys.value = ['groups'];
        else if (path.includes('/iam/policies')) selectedKeys.value = ['policies'];
        else if (path.includes('/iam/service-accounts')) selectedKeys.value = ['service-accounts'];
        else if (path.includes('/storage/buckets')) selectedKeys.value = ['buckets'];
        else if (path.includes('/storage/pools')) selectedKeys.value = ['pools'];
        else if (path.includes('/monitoring/usage')) selectedKeys.value = ['storage-monitoring'];
        else if (path.includes('/monitoring/storage')) selectedKeys.value = ['storage-monitoring'];
        else if (path.includes('/monitoring/metrics')) selectedKeys.value = ['metrics'];
        else if (path.includes('/maintenance/heal')) selectedKeys.value = ['heal'];
        else if (path.includes('/maintenance/tier')) selectedKeys.value = ['tier'];
        else if (path.includes('/maintenance/rebalance')) selectedKeys.value = ['rebalance'];
        else if (path.includes('/security/kms')) selectedKeys.value = ['kms'];
        else if (path.includes('/settings/replication')) selectedKeys.value = ['replication'];
        else if (path.includes('/settings/notifications')) selectedKeys.value = ['notifications'];
        else if (path.includes('/tools/metadata-query')) selectedKeys.value = ['metadata-query'];
    },
    { immediate: true }
);

</script>

<style scoped>
.app-layout {
  min-height: 100%;
}

.app-main {
  min-width: 0;
}

.app-header {
  background: #fff;
  padding: 0 16px;
  height: 48px;
  line-height: 48px;
  border-bottom: 1px solid rgba(5, 5, 5, 0.06);
}

.app-header-right {
  display: flex;
  justify-content: flex-end;
}

.app-content {
  padding: 16px;
  overflow: auto;
}

.app-footer {
  text-align: center;
  padding: 12px 16px;
  color: rgba(0, 0, 0, 0.45);
  background: transparent;
}

.logo {
  height: 32px;
  margin: 16px;
  background: rgba(255, 255, 255, 0.3);
  color: white;
  text-align: center;
  line-height: 32px;
  font-weight: bold;
}
</style>

