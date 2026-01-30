<template>
  <PageContainer>
    <template #breadcrumb>
      <a-breadcrumb-item>Admin</a-breadcrumb-item>
      <a-breadcrumb-item>Dashboard</a-breadcrumb-item>
    </template>

    <template #header>
      <div style="display: flex; align-items: center; justify-content: space-between; gap: 12px">
        <h2 style="margin: 0">Server Info</h2>
        <a-button @click="fetchInfo" :loading="loading">Refresh</a-button>
      </div>
    </template>

    <a-spin v-if="loading" />

    <template v-else>
      <a-row :gutter="16">
        <a-col :xs="24" :sm="12" :md="8">
          <a-card size="small">
            <a-statistic title="Version" :value="formattedVersion">
              <template #formatter>
                <a-tooltip :title="version">
                  <span>{{ formattedVersion }}</span>
                </a-tooltip>
              </template>
            </a-statistic>
          </a-card>
        </a-col>
        <a-col :xs="24" :sm="12" :md="8">
          <a-card size="small">
            <a-statistic title="Uptime" :value="uptime" />
          </a-card>
        </a-col>
        <a-col :xs="24" :sm="12" :md="8">
          <a-card size="small">
            <div style="display: flex; justify-content: space-between; align-items: center">
              <span style="color: rgba(0,0,0,0.45)">Status</span>
              <a-badge status="processing" text="Running" />
            </div>
          </a-card>
        </a-col>
      </a-row>

      <div style="height: 16px" />

      <a-descriptions title="Summary" bordered :column="2">
        <a-descriptions-item label="Mode">{{ mode }}</a-descriptions-item>
        <a-descriptions-item label="Servers">{{ servers }}</a-descriptions-item>
        <a-descriptions-item label="Buckets">{{ buckets }}</a-descriptions-item>
        <a-descriptions-item label="Objects">{{ objects }}</a-descriptions-item>
      </a-descriptions>

      <div style="height: 16px" />

      <a-collapse>
        <a-collapse-panel key="raw" header="Raw /info response (JSON)">
          <pre class="json-block">{{ rawInfoText }}</pre>
        </a-collapse-panel>
      </a-collapse>
    </template>
  </PageContainer>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import api from '@/api/request';
import PageContainer from '@/components/layout/PageContainer.vue';

const loading = ref(false);
const rawInfo = ref<any>(null);

const pick = (obj: any, keys: string[]) => {
  if (!obj) return undefined;
  for (const key of keys) {
    if (obj[key] !== undefined && obj[key] !== null) return obj[key];
  }
  return undefined;
};

const formatScalar = (value: unknown) => {
  if (value === undefined || value === null || value === '') return '-';
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return String(value);
  return '-';
};

const formatCountLike = (value: unknown) => {
  if (value === undefined || value === null) return '-';
  if (typeof value === 'number') return String(value);
  if (Array.isArray(value)) return String(value.length);
  if (typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    const count = pick(obj, ['count', 'total', 'num', 'number', 'items', 'objects', 'buckets']);
    if (typeof count === 'number') return String(count);
  }
  return '-';
};

const formatUptime = (seconds: unknown) => {
  if (typeof seconds !== 'number') return '-';
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h ${minutes}m`;
  return `${hours}h ${minutes}m`;
};

const version = computed(() => {
  // Try root
  let v = pick(rawInfo.value, ['version', 'Version', 'serverVersion']);
  if (v) return formatScalar(v);
  // Try servers[0]
  if (rawInfo.value?.servers?.[0]) {
    v = pick(rawInfo.value.servers[0], ['version', 'Version']);
    if (v) return formatScalar(v);
  }
  return '-';
});

const formattedVersion = computed(() => {
  const v = version.value;
  if (!v || v === '-') return '-';
  
  // Format: 2026-01-30T09:33:15+08:00@2e8644b9
  // Target: 2026-01-30 09:33 (2e8644b)
  const match = v.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}):\d{2}.*?@([a-f0-9]+)$/);
  if (match) {
    const [_, date, time, hash] = match;
    const shortHash = hash.substring(0, 7);
    return `${date} ${time} (${shortHash})`;
  }
  return v;
});

const uptime = computed(() => {
  // Try root
  let u = pick(rawInfo.value, ['uptime', 'Uptime', 'serverUptime']);
  if (u !== undefined) return formatUptime(u);
  // Try servers[0]
  if (rawInfo.value?.servers?.[0]) {
    u = pick(rawInfo.value.servers[0], ['uptime', 'Uptime']);
    if (u !== undefined) return formatUptime(u);
  }
  return '-';
});

const mode = computed(() => formatScalar(pick(rawInfo.value, ['mode', 'Mode'])));
const servers = computed(() => formatCountLike(pick(rawInfo.value, ['servers', 'Servers'])));
const buckets = computed(() => formatCountLike(pick(rawInfo.value, ['buckets', 'Buckets'])));
const objects = computed(() => formatCountLike(pick(rawInfo.value, ['objects', 'Objects'])));

const rawInfoText = computed(() => {
  if (!rawInfo.value) return '';
  try {
    return JSON.stringify(rawInfo.value, null, 2);
  } catch {
    return String(rawInfo.value);
  }
});

const fetchInfo = async () => {
  try {
    loading.value = true;
    const res = await api.get('/info');
    rawInfo.value = res.data;
  } catch (error) {
    console.error(error);
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  fetchInfo();
});
</script>

<style scoped>
.json-block {
  margin: 0;
  padding: 12px;
  background: #0b1020;
  color: #e5e7eb;
  border-radius: 8px;
  overflow: auto;
  font-size: 12px;
  line-height: 1.5;
}
</style>
