<script setup lang="ts">
// Loading, empty and error: the three states every screen has.
import Spinner from '@/components/Spinner.vue'

defineProps<{ loading?: boolean; loadingText?: string; error?: string; empty?: boolean; emptyText?: string }>()
</script>

<template>
  <div v-if="loading" class="px-4 py-6 text-xs text-muted flex items-center gap-2" role="status">
    <Spinner />
    {{ loadingText || 'Loading…' }}
  </div>
  <div v-else-if="error" class="p-3">
    <div class="k-note k-note--danger">{{ error }}</div>
  </div>
  <div v-else-if="empty" class="px-4 py-6 text-xs text-muted">{{ emptyText || 'Nothing here.' }}</div>
  <slot v-else />
</template>
