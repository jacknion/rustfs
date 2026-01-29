<template>
    <div class="json-node" :style="{ marginLeft: depth > 0 ? '20px' : '0' }">
        <template v-if="isObject || isArray">
            <span class="json-toggle" @click="toggleNode">
                {{ isNodeExpanded ? '▼' : '▶' }}
            </span>
            <span class="json-bracket">{{ isArray ? '[' : '{' }}</span>
            <span v-if="!isNodeExpanded" class="json-collapsed">
                {{ isArray ? `${dataLength} items` : `${dataLength} keys` }}
            </span>
            <span v-if="!isNodeExpanded" class="json-bracket">{{ isArray ? ']' : '}' }}</span>
            
            <template v-if="isNodeExpanded">
                <div class="json-children">
                    <div v-for="(value, key) in data" :key="key" class="json-entry">
                        <span v-if="!isArray" class="json-key">"{{ key }}"</span>
                        <span v-if="!isArray" class="json-colon">: </span>
                        <JsonNode :data="value" :expanded="expanded" :depth="depth + 1" />
                        <span v-if="!isLastKey(key)" class="json-comma">,</span>
                    </div>
                </div>
                <span class="json-bracket">{{ isArray ? ']' : '}' }}</span>
            </template>
        </template>
        
        <template v-else>
            <span :class="valueClass">{{ formattedValue }}</span>
        </template>
    </div>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue';

const props = defineProps<{
    data: any;
    expanded: boolean;
    depth: number;
}>();

const isNodeExpanded = ref(true);

watch(() => props.expanded, (newVal) => {
    isNodeExpanded.value = newVal;
}, { immediate: true });

const toggleNode = () => {
    isNodeExpanded.value = !isNodeExpanded.value;
};

const isObject = computed(() => 
    typeof props.data === 'object' && props.data !== null && !Array.isArray(props.data)
);

const isArray = computed(() => Array.isArray(props.data));

const dataLength = computed(() => 
    isArray.value ? props.data.length : Object.keys(props.data).length
);

const valueClass = computed(() => {
    const type = typeof props.data;
    if (props.data === null) return 'json-null';
    if (type === 'string') return 'json-string';
    if (type === 'number') return 'json-number';
    if (type === 'boolean') return 'json-boolean';
    return 'json-value';
});

const formattedValue = computed(() => {
    if (props.data === null) return 'null';
    if (typeof props.data === 'string') return `"${props.data}"`;
    return String(props.data);
});

const isLastKey = (key: string | number) => {
    if (isArray.value) {
        return Number(key) === props.data.length - 1;
    }
    const keys = Object.keys(props.data);
    return keys.indexOf(String(key)) === keys.length - 1;
};
</script>

<style scoped>
.json-node {
    line-height: 1.6;
}

.json-toggle {
    cursor: pointer;
    user-select: none;
    color: #808080;
    margin-right: 4px;
    display: inline-block;
    width: 12px;
}

.json-toggle:hover {
    color: #fff;
}

.json-bracket {
    color: #d4d4d4;
}

.json-collapsed {
    color: #6a9955;
    font-style: italic;
    margin: 0 4px;
}

.json-key {
    color: #9cdcfe;
}

.json-colon {
    color: #d4d4d4;
}

.json-comma {
    color: #d4d4d4;
}

.json-string {
    color: #ce9178;
}

.json-number {
    color: #b5cea8;
}

.json-boolean {
    color: #569cd6;
}

.json-null {
    color: #569cd6;
}

.json-children {
    /* Children are already indented via marginLeft */
}

.json-entry {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
}
</style>
