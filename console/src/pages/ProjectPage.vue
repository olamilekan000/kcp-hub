<script setup lang="ts">
// The selected project at a glance, and how to reach it from a terminal.
// Everything here is read with the user's own token, so a viewer sees
// what a viewer may; the counts that need more are left out rather than
// shown as zero.
import { computed, onMounted, ref, watch } from 'vue'
import { useSession } from '@/stores/session'
import { settings } from '@/lib/settings'
import * as oidc from '@/lib/oidc'
import { canonicalPath, exportsIn, isPublished } from '@/lib/publish'
import { fileName, kubeconfig, snippets } from '@/lib/kubeconfig'
import PageHeader from '@/components/PageHeader.vue'
import Panel from '@/components/Panel.vue'
import StateBlock from '@/components/StateBlock.vue'
import RoleBadge from '@/components/RoleBadge.vue'
import CodeBlock from '@/components/CodeBlock.vue'
import Spinner from '@/components/Spinner.vue'

const session = useSession()
const workspace = computed(() => session.workspace)
const project = computed(() => session.currentProject)

const path = ref('')
const published = ref<number | null>(null)
const loading = ref(false)

async function load() {
  path.value = ''
  published.value = null
  if (!workspace.value) return
  loading.value = true
  const [p, ex] = await Promise.allSettled([canonicalPath(workspace.value), exportsIn(workspace.value)])
  path.value = p.status === 'fulfilled' ? p.value : ''
  published.value = ex.status === 'fulfilled' ? ex.value.filter(isPublished).length : null
  loading.value = false
}

/** One entry per binding, as the sidebar groups them. */
const enabled = computed(() => {
  const byBinding = new Map<string, string[]>()
  for (const e of session.enabled) byBinding.set(e.binding, [...(byBinding.get(e.binding) ?? []), e.resource])
  return [...byBinding].map(([binding, kinds]) => ({
    binding,
    kinds,
    label: binding.split(/[.-]/)[0].replace(/^\w/, (c) => c.toUpperCase()),
  }))
})

const copiedPath = ref(false)
async function copyPath() {
  await navigator.clipboard.writeText(path.value)
  copiedPath.value = true
  setTimeout(() => (copiedPath.value = false), 1500)
}

// ── the terminal ─────────────────────────────────────────────────────

const file = computed(() => fileName(session.tenant, session.project))
const expires = computed(() => {
  const exp = oidc.claims()?.exp
  return exp ? new Date(exp * 1000) : null
})
const canDownload = computed(() => !!settings.kcpServer && !!oidc.token() && !!workspace.value)

function download() {
  const token = oidc.token()
  if (!token) return
  const text = kubeconfig({
    server: settings.kcpServer,
    // The path reads better, but the cluster name always resolves.
    path: path.value || workspace.value.replace(/^\/clusters\//, ''),
    name: `${session.tenant}/${session.project}`,
    user: session.username,
    token,
    caPEM: settings.kcpCA,
  })
  const url = URL.createObjectURL(new Blob([text], { type: 'application/yaml' }))
  const a = document.createElement('a')
  a.href = url
  a.download = file.value
  a.click()
  URL.revokeObjectURL(url)
}

const commands = computed(() => snippets(file.value, session.enabled))

onMounted(async () => {
  if (!session.tenants.length) await session.load()
  await load()
})
watch(workspace, load)
</script>

<template>
  <div>
    <PageHeader
      :title="project?.displayName || session.project || 'Project'"
      :subtitle="session.tenant ? `A project in ${session.tenant}` : ''"
    />

    <div v-if="!workspace && (session.loading || session.error)" class="k-card">
      <StateBlock :loading="session.loading" :error="session.error" />
    </div>
    <div v-else-if="!workspace" class="k-card px-4 py-6 text-xs text-muted space-y-2">
      <template v-if="!session.projects.length">
        <p>You are not in a project yet.</p>
        <RouterLink to="/welcome" class="text-accent hover:underline">Create a tenant and a project →</RouterLink>
      </template>
      <p v-else>Pick a project at the top.</p>
    </div>

    <div v-else class="space-y-4">
      <div class="grid gap-3 sm:grid-cols-3">
        <RouterLink to="/catalog" class="k-card p-4 hover:border-accent/40 transition-colors">
          <div class="k-eyebrow">Enabled APIs</div>
          <div class="mt-1.5 text-2xl font-semibold font-display">
            <span v-if="session.enabledLoaded">{{ enabled.length }}</span>
            <Spinner v-else :size="16" />
          </div>
          <div class="text-[11px] text-faint mt-0.5">from the catalog</div>
        </RouterLink>
        <RouterLink to="/publish" class="k-card p-4 hover:border-accent/40 transition-colors">
          <div class="k-eyebrow">Published APIs</div>
          <div class="mt-1.5 text-2xl font-semibold font-display">
            <Spinner v-if="loading" :size="16" />
            <span v-else-if="published !== null">{{ published }}</span>
            <span v-else class="text-faint" title="Needs admin rights in this project">–</span>
          </div>
          <div class="text-[11px] text-faint mt-0.5">shared with other teams</div>
        </RouterLink>
        <RouterLink :to="`/tenants/${session.tenant}/access`" class="k-card p-4 hover:border-accent/40 transition-colors">
          <div class="k-eyebrow">Your access</div>
          <div class="mt-2"><RoleBadge :roles="project?.roles ?? []" /></div>
          <div class="text-[11px] text-faint mt-1.5">who else has access →</div>
        </RouterLink>
      </div>

      <Panel>
        <template #header>Enabled here</template>
        <StateBlock v-if="!session.enabledLoaded" loading />
        <div v-else-if="!enabled.length" class="px-4 py-4 text-xs text-muted">
          Nothing yet. <RouterLink to="/catalog" class="text-accent hover:underline">Browse the catalog →</RouterLink>
        </div>
        <ul v-else class="divide-y divide-edge">
          <li v-for="e in enabled" :key="e.binding">
            <RouterLink :to="`/p/${e.binding}`" class="px-4 py-2.5 flex items-center gap-3 hover:bg-overlay/40">
              <span class="text-xs font-medium">{{ e.label }}</span>
              <span class="font-mono text-[10px] text-faint">{{ e.binding }}</span>
              <span class="ml-auto text-[11px] text-muted">{{ e.kinds.join(', ') }}</span>
            </RouterLink>
          </li>
        </ul>
      </Panel>

      <Panel>
        <template #header>Use it from your terminal</template>
        <div class="px-4 py-3.5 space-y-4 text-xs text-muted leading-relaxed">
          <p>
            Everything you do here, you can also do with <code class="font-mono text-ink">kubectl</code>. Download a
            kubeconfig for this project, then try the commands below.
          </p>
          <div class="flex flex-wrap items-center gap-3">
            <button class="k-btn k-btn--primary" :disabled="!canDownload" @click="download">
              Download kubeconfig
            </button>
            <span class="text-[11px] text-faint">
              Signs you in as <span class="text-muted">{{ session.username }}</span>{{
                expires ? ` until ${expires.toLocaleString()}` : ''
              }}. Download it again after that.
            </span>
          </div>
          <p v-if="!settings.kcpServer" class="k-note k-note--danger">
            The console was not told kcp's address, so it cannot write a kubeconfig.
          </p>
          <div class="space-y-3">
            <CodeBlock v-for="c in commands" :key="c.title" :title="c.title" :text="c.text" />
          </div>
          <div v-if="path" class="flex items-center gap-2 pt-1 text-[11px] text-faint">
            <span>Project path</span>
            <code class="font-mono text-muted bg-overlay px-2 py-0.5 rounded-[3px] truncate">{{ path }}</code>
            <button class="k-btn k-btn--ghost !px-2 !py-0.5 text-[10px]" @click="copyPath">
              {{ copiedPath ? 'Copied' : 'Copy' }}
            </button>
          </div>
        </div>
      </Panel>
    </div>
  </div>
</template>
