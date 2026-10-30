<script setup lang="ts">
// Asks before an action that changes what other people see or removes
// something. The body says what will happen; the page runs the action on
// `confirm` and closes the dialog itself, including on failure, so the
// error it reports is not hidden behind the overlay.
import { useId } from 'vue'
import Modal from './Modal.vue'
import Spinner from './Spinner.vue'

const props = withDefaults(
  defineProps<{
    title: string
    confirmLabel: string
    busyLabel?: string
    busy?: boolean
    tone?: 'danger' | 'primary'
  }>(),
  { busy: false, tone: 'danger', busyLabel: '' },
)

const emit = defineEmits<{ confirm: []; cancel: [] }>()

const titleId = useId()

function cancel() {
  if (!props.busy) emit('cancel')
}
</script>

<template>
  <Modal size="sm" @close="cancel">
    <div class="k-card" :aria-labelledby="titleId">
      <div :id="titleId" class="px-4 py-2.5 border-b border-edge text-[13px] font-medium">{{ title }}</div>
      <div class="px-4 py-3 text-xs text-muted leading-relaxed">
        <slot />
      </div>
      <div class="px-4 py-2.5 border-t border-edge flex gap-2">
        <button
          class="k-btn"
          :class="tone === 'danger' ? 'k-btn--danger' : 'k-btn--primary'"
          :disabled="busy"
          autofocus
          @click="emit('confirm')"
        >
          <Spinner v-if="busy" />
          {{ busy && busyLabel ? busyLabel : confirmLabel }}
        </button>
        <button class="k-btn k-btn--ghost" :disabled="busy" @click="cancel">Cancel</button>
      </div>
    </div>
  </Modal>
</template>
