<script setup lang="ts">
// The project in the middle, what it uses on the left, what it provides on
// the right. Cards are plain markup; the lines are drawn over them from
// where the cards actually landed, so they follow any wrapping or resize.
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { shortPath, type ProvidedAPI, type UsedAPI } from '@/lib/map'

const props = defineProps<{
  project: string
  tenant: string
  path?: string
  used: UsedAPI[]
  /** null when the caller may not read the project's exports. */
  provided: ProvidedAPI[] | null
}>()

const root = ref<HTMLElement>()
const hub = ref<HTMLElement>()
const lines = ref<{ d: string; on: boolean }[]>([])
const size = ref({ w: 0, h: 0 })

function curve(x1: number, y1: number, x2: number, y2: number): string {
  const mid = (x1 + x2) / 2
  return `M${x1} ${y1} C${mid} ${y1} ${mid} ${y2} ${x2} ${y2}`
}

function draw() {
  const box = root.value?.getBoundingClientRect()
  const center = hub.value?.getBoundingClientRect()
  if (!box || !center) return
  size.value = { w: box.width, h: box.height }
  // Stacked on a narrow screen: the columns no longer face each other.
  if (center.left - box.left < 40) {
    lines.value = []
    return
  }
  const cy = center.top + center.height / 2 - box.top
  const out: { d: string; on: boolean }[] = []
  root.value!.querySelectorAll('[data-used]').forEach((el, i) => {
    const r = el.getBoundingClientRect()
    out.push({
      d: curve(r.right - box.left, r.top + r.height / 2 - box.top, center.left - box.left, cy),
      on: props.used[i]?.ready ?? false,
    })
  })
  root.value!.querySelectorAll('[data-provided]').forEach((el, i) => {
    const r = el.getBoundingClientRect()
    out.push({
      d: curve(center.right - box.left, cy, r.left - box.left, r.top + r.height / 2 - box.top),
      on: props.provided?.[i]?.published ?? false,
    })
  })
  lines.value = out
}

let observer: ResizeObserver | undefined
onMounted(() => {
  observer = new ResizeObserver(draw)
  if (root.value) observer.observe(root.value)
  draw()
})
onBeforeUnmount(() => observer?.disconnect())
watch(() => [props.used, props.provided], () => nextTick(draw), { deep: true })
</script>

<template>
  <div ref="root" class="relative grid gap-y-4 sm:grid-cols-[1fr_auto_1fr] sm:gap-x-16 items-center px-4 py-6">
    <svg class="absolute inset-0 pointer-events-none" :width="size.w" :height="size.h" aria-hidden="true">
      <path
        v-for="(l, i) in lines"
        :key="i"
        :d="l.d"
        fill="none"
        :stroke="l.on ? 'var(--color-accent)' : 'var(--color-edge-strong)'"
        :stroke-dasharray="l.on ? '0' : '4 3'"
        stroke-width="1.5"
      />
    </svg>

    <section class="relative space-y-2">
      <div class="k-eyebrow">Uses</div>
      <RouterLink
        v-for="u in used"
        :key="u.binding"
        data-used
        :to="`/p/${u.binding}`"
        class="k-card block px-3 py-2 hover:border-accent/40 transition-colors"
      >
        <div class="flex items-center gap-2">
          <span class="text-xs font-medium">{{ u.name }}</span>
          <span v-if="!u.ready" class="ml-auto text-[10px] text-warning">not ready</span>
        </div>
        <div class="text-[11px] text-faint mt-0.5">
          from <span class="font-mono">{{ shortPath(u.provider) }}</span>
          <template v-if="u.kinds.length"> · {{ u.kinds.join(', ') }}</template>
        </div>
      </RouterLink>
      <div v-if="!used.length" class="k-card px-3 py-2 text-[11px] text-muted">
        Nothing enabled yet.
        <RouterLink to="/catalog" class="text-accent hover:underline">Browse the catalog →</RouterLink>
      </div>
    </section>

    <div ref="hub" class="relative k-card px-4 py-3 border-accent/60 min-w-[160px] text-center">
      <div class="k-eyebrow">Project</div>
      <div class="text-sm font-semibold font-display mt-1">{{ project }}</div>
      <div class="text-[11px] text-faint">in {{ tenant }}</div>
      <div v-if="path" class="font-mono text-[10px] text-faint mt-1">{{ path }}</div>
    </div>

    <section class="relative space-y-2">
      <div class="k-eyebrow">Provides</div>
      <template v-if="provided">
        <RouterLink
          v-for="p in provided"
          :key="p.export"
          data-provided
          to="/publish"
          class="k-card block px-3 py-2 hover:border-accent/40 transition-colors"
        >
          <div class="flex items-center gap-2">
            <span class="text-xs font-medium">{{ p.name }}</span>
            <span class="ml-auto text-[10px]" :class="p.published ? 'text-success' : 'text-faint'">
              {{ p.published ? 'in the catalog' : 'not published' }}
            </span>
          </div>
          <div v-if="p.kinds.length" class="text-[11px] text-faint mt-0.5">{{ p.kinds.join(', ') }}</div>
        </RouterLink>
        <div v-if="!provided.length" class="k-card px-3 py-2 text-[11px] text-muted">
          No APIs defined here.
          <RouterLink to="/publish" class="text-accent hover:underline">Publish one →</RouterLink>
        </div>
      </template>
      <div v-else class="k-card px-3 py-2 text-[11px] text-faint">
        Seeing what this project provides needs admin rights in it.
      </div>
    </section>
  </div>
</template>
