<template>
    <div class="json-viewer">
        <div class="json-toolbar">
            <a-button size="small" @click="toggleExpand">
                {{ allExpanded ? 'Collapse All' : 'Expand All' }}
            </a-button>
            <a-button size="small" @click="copyToClipboard">
                <template #icon><CopyOutlined /></template>
                Copy
            </a-button>
        </div>
        <div class="json-content">
            <JsonNode :data="data" :expanded="allExpanded" :depth="0" />
        </div>
    </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { message } from 'ant-design-vue';
import { CopyOutlined } from '@ant-design/icons-vue';
import JsonNode from './JsonNode.vue';

const props = defineProps<{
    data: any;
}>();

const allExpanded = ref(true);

const toggleExpand = () => {
    allExpanded.value = !allExpanded.value;
};

const copyToClipboard = async () => {
    try {
        await navigator.clipboard.writeText(JSON.stringify(props.data, null, 2));
        message.success('Copied to clipboard');
    } catch (err) {
        message.error('Failed to copy');
    }
};
</script>

<style scoped>
.json-viewer {
    background: #1e1e1e;
    border-radius: 8px;
    overflow: hidden;
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 13px;
}

.json-toolbar {
    display: flex;
    gap: 8px;
    padding: 8px 12px;
    background: #2d2d2d;
    border-bottom: 1px solid #404040;
}

.json-content {
    padding: 12px 16px;
    max-height: 400px;
    overflow: auto;
}
</style>
