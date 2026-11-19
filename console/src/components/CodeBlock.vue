<script setup lang="ts">
// A command or file to copy, with the button that copies it.
import { ref } from 'vue'
import YamlEditor from '@/components/YamlEditor.vue'

const props = defineProps<{ text: string; title?: string; lang?: string }>()

const copied = ref(false)

async function copy() {
  await navigator.clipboard.writeText(props.text)
  copied.value = true
  setTimeout(() => (copied.value = false), 1500)
}
</script>

<template>
  <div class="space-y-1">
    <div class="flex items-center gap-2">
      <span v-if="title" class="text-[11px] text-muted">{{ title }}</span>
      <button class="ml-auto k-btn k-btn--ghost !px-2 !py-0.5 text-[10px]" @click="copy">
        {{ copied ? 'Copied' : 'Copy' }}
      </button>
    </div>
    <div v-if="lang === 'yaml'" class="border border-edge rounded-[4px] overflow-hidden">
      <YamlEditor :model-value="text" readonly />
    </div>
    <pre v-else class="font-mono text-[11px] leading-relaxed bg-overlay border border-edge rounded-[4px] px-3 py-2.5 overflow-auto whitespace-pre">{{ text }}</pre>
  </div>
</template>
