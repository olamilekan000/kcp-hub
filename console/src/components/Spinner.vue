<script setup lang="ts">
// Something is on its way. Drawn in currentColor, so it takes the colour
// of the text or button it sits in. Always next to words that say what is
// happening, which is what a screen reader announces.
withDefaults(defineProps<{ size?: number }>(), { size: 14 })
</script>

<template>
  <svg
    class="shrink-0 motion-safe:animate-spin"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    aria-hidden="true"
  >
    <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="3" opacity="0.2" />
    <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
  </svg>
</template>
