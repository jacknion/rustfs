<template>
  <div class="page-root">
    <a-breadcrumb v-if="$slots.breadcrumb" class="breadcrumb">
      <slot name="breadcrumb" />
    </a-breadcrumb>

    <div class="container" :style="containerStyle">
      <div v-if="$slots.header" class="header">
        <slot name="header" />
      </div>
      <slot />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(
  defineProps<{
    minHeight?: number | string;
    padding?: number;
    background?: string;
  }>(),
  {
    minHeight: '360px',
    padding: 24,
    background: '#fff',
  }
);

const containerStyle = computed(() => {
  const minHeight = typeof props.minHeight === 'number' ? `${props.minHeight}px` : props.minHeight;
  return {
    padding: `${props.padding}px`,
    background: props.background,
    minHeight,
  } as const;
});
</script>

<style scoped>
.page-root {
  width: 100%;
}

.breadcrumb {
  margin-bottom: 12px;
}

.container {
  border-radius: 8px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}

.header {
  margin-bottom: 16px;
}
</style>
