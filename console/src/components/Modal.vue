<script setup lang="ts">
// A dialog over the page. The content brings its own card, so a form that
// also renders inline (ObjectEditor) looks the same in both places.
//
// `dismissable` decides whether a click on the backdrop closes it. A form
// with typed input sets it false: a stray click should not throw work away.
// Escape always closes, since it is never pressed by accident.
import { onBeforeUnmount, onMounted } from 'vue'

const props = withDefaults(defineProps<{ size?: 'sm' | 'md' | 'lg'; dismissable?: boolean }>(), {
  size: 'md',
  dismissable: true,
})

const emit = defineEmits<{ close: [] }>()

const width = { sm: 'max-w-sm', md: 'max-w-xl', lg: 'max-w-3xl' }

function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') emit('close')
}

let overflow = ''
onMounted(() => {
  window.addEventListener('keydown', onKey)
  overflow = document.body.style.overflow
  document.body.style.overflow = 'hidden'
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKey)
  document.body.style.overflow = overflow
})
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-start sm:items-center justify-center bg-black/30 px-4 py-8 overflow-auto"
      @click.self="props.dismissable && emit('close')"
    >
      <div class="w-full max-h-full" :class="width[size]" role="dialog" aria-modal="true">
        <slot />
      </div>
    </div>
  </Teleport>
</template>
