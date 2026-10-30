<script setup lang="ts">
// Offering APIs from the selected project. Three things have to be true
// for an API to reach the catalog, and the page is those three, in order:
// the platform admin registered this project as a producer, the project
// allowed the marketplace in, and the API's export is published.
import { computed, onMounted, ref, watch } from 'vue'
import { useSession } from '@/stores/session'
import { ApiError, bindings, canI, offerings, type CatalogOffering } from '@/lib/api'
import {
  PUBLISH_BINDING,
  PUBLISH_CLAIMS,
  acceptAllClaims,
  canonicalPath,
  cardOf,
  consent,
  defineAPI,
  exportName,
  exportsIn,
  isPublished,
  missingClaims,
  pluralOf,
  problems,
  publish,
  withdrawConsent,
  type APIExport,
  type Card,
  type FieldType,
  type NewAPI,
} from '@/lib/publish'
import PageHeader from '@/components/PageHeader.vue'
import Panel from '@/components/Panel.vue'
import StateBlock from '@/components/StateBlock.vue'
import Spinner from '@/components/Spinner.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'

const session = useSession()
const workspace = computed(() => session.workspace)
/** The canonical path, which is what a Producer record names. */
const path = ref('')

const loading = ref(false)
const error = ref('')
const mayPublish = ref(true)
const consentPhase = ref<string | null>(null)
/** What the marketplace asks for now that this project's consent predates. */
const missing = ref<typeof PUBLISH_CLAIMS>([])
const exports = ref<APIExport[]>([])
const listed = ref<CatalogOffering[]>([])

const consented = computed(() => consentPhase.value === 'Bound')
const producerName = computed(() => listed.value[0]?.producer ?? '')
const listedExports = computed(() => new Set(listed.value.map((o) => o.offering)))

async function load() {
  error.value = ''
  if (!workspace.value) return
  loading.value = true
  try {
    mayPublish.value = await canI(workspace.value, { group: 'apis.kcp.io', resource: 'apiexports', verb: 'create' })
    if (!mayPublish.value) return
    path.value = await canonicalPath(workspace.value)
    await refresh()
  } catch (e) {
    error.value = describe(e)
  } finally {
    loading.value = false
  }
}

/** refresh re-reads what this page shows, without the loading state. */
async function refresh() {
  const [b, ex, catalog] = await Promise.all([bindings(workspace.value), exportsIn(workspace.value), offerings()])
  const binding = (b.items ?? []).find((x) => x.metadata.name === PUBLISH_BINDING)
  consentPhase.value = binding?.status?.phase ?? null
  missing.value = binding ? missingClaims(binding.spec?.permissionClaims ?? []) : []
  exports.value = ex
  listed.value = (catalog.items ?? []).filter((o) => o.workspacePath === path.value)
}

function describe(e: unknown): string {
  if (e instanceof ApiError && e.forbidden) return 'Forbidden.'
  if (e instanceof ApiError && e.status === 409) return 'Something with that name already exists in this project.'
  return e instanceof Error ? e.message : String(e)
}

/** settle keeps re-reading for a while, until kcp or the operator has caught up. */
async function settle(done: () => boolean) {
  const ws = workspace.value
  for (let i = 0; i < 20 && ws === workspace.value && !done(); i++) {
    await new Promise((resolve) => setTimeout(resolve, 1000))
    await refresh()
  }
}

const busy = ref('')
const note = ref('')
const noteError = ref(false)

function say(text: string, isError = false) {
  note.value = text
  noteError.value = isError
}

async function run(key: string, act: () => Promise<void>) {
  busy.value = key
  note.value = ''
  try {
    await act()
  } catch (e) {
    say(describe(e), true)
  } finally {
    busy.value = ''
  }
}

const copied = ref(false)
async function copyPath() {
  await navigator.clipboard.writeText(path.value)
  copied.value = true
  setTimeout(() => (copied.value = false), 1500)
}

// ── consent ──────────────────────────────────────────────────────────

/** The change waiting on the confirmation dialog. */
type Ask = { kind: 'withdraw' } | { kind: 'publish' | 'unpublish'; export: APIExport }
const asking = ref<Ask | null>(null)

const askBusy = computed(() => {
  const a = asking.value
  if (!a) return false
  return a.kind === 'withdraw' ? busy.value === 'consent' : busy.value === a.export.metadata.name
})

async function confirmAsk() {
  const a = asking.value
  if (!a) return
  if (a.kind === 'withdraw') await withdraw()
  else await setPublished(a.export, a.kind === 'publish')
  asking.value = null
}

function allow() {
  return run('consent', async () => {
    await consent(workspace.value)
    await refresh()
    await settle(() => consented.value)
    say('The marketplace may now see this project\'s published APIs.')
  })
}

function acceptMissing() {
  return run('consent', async () => {
    await acceptAllClaims(workspace.value)
    await refresh()
    say('Accepted. The marketplace has everything it asks for.')
  })
}

function withdraw() {
  return run('consent', async () => {
    await withdrawConsent(workspace.value)
    await settle(() => consentPhase.value === null)
    say('Withdrawn. Published APIs leave the catalog, and nobody new can enable them.')
  })
}

// ── your APIs ────────────────────────────────────────────────────────

const editing = ref('')
const card = ref<Card>({ displayName: '', description: '', docsURL: '' })

function edit(e: APIExport) {
  editing.value = e.metadata.name
  card.value = cardOf(e)
}

function setPublished(e: APIExport, published: boolean, withCard: Card = cardOf(e)) {
  const name = e.metadata.name
  return run(name, async () => {
    await publish(workspace.value, name, published, withCard)
    editing.value = ''
    await refresh()
    if (published && producerName.value) {
      await settle(() => listedExports.value.has(name))
    } else if (!published) {
      await settle(() => !listedExports.value.has(name))
    }
    say(published ? `Published ${name}.` : `Unpublished ${name}. Existing bindings keep working; nobody new can enable it.`)
  })
}

function saveCard(e: APIExport) {
  return setPublished(e, isPublished(e), card.value)
}

function kindsOf(e: APIExport): string {
  return (e.spec?.resources ?? []).map((r) => r.name).join(', ') || 'none'
}

// ── a new API ────────────────────────────────────────────────────────

const showNew = ref(false)
const pluralTouched = ref(false)
const draft = ref<NewAPI>(blank())

function blank(): NewAPI {
  return { group: '', version: 'v1alpha1', kind: '', plural: '', scope: 'Cluster', fields: [{ name: '', type: 'string' }] }
}

watch(
  () => draft.value.kind,
  (kind) => {
    if (!pluralTouched.value) draft.value.plural = pluralOf(kind)
  },
)

const FIELD_TYPES: FieldType[] = ['string', 'integer', 'number', 'boolean']

const cleaned = computed<NewAPI>(() => ({
  ...draft.value,
  group: draft.value.group.trim(),
  kind: draft.value.kind.trim(),
  plural: draft.value.plural.trim(),
  fields: draft.value.fields.filter((f) => f.name.trim()).map((f) => ({ ...f, name: f.name.trim() })),
}))
const draftProblems = computed(() => problems(cleaned.value))
const started = computed(() => !!(draft.value.group || draft.value.kind))

function createAPI() {
  const api = cleaned.value
  if (draftProblems.value.length) return
  return run('new', async () => {
    await defineAPI(workspace.value, api)
    showNew.value = false
    draft.value = blank()
    pluralTouched.value = false
    await refresh()
    say(`Created ${exportName(api)}. It is not in the catalog until you publish it.`)
  })
}

onMounted(async () => {
  if (!session.tenants.length) await session.load()
  await load()
})
watch(workspace, load)
</script>

<template>
  <div>
    <PageHeader title="Publish" subtitle="Offer APIs from this project in the catalog, for other teams to enable.">
      <template #actions>
        <span v-if="session.project" class="k-badge k-badge--muted">{{ session.tenant }}/{{ session.project }}</span>
      </template>
    </PageHeader>

    <div v-if="!workspace && (session.loading || session.error)" class="k-card">
      <StateBlock :loading="session.loading" :error="session.error" />
    </div>
    <div v-else-if="!workspace" class="k-card px-4 py-6 text-xs text-muted space-y-2">
      <template v-if="!session.projects.length">
        <p>You publish from a project, and you are not in one yet.</p>
        <RouterLink to="/welcome" class="text-accent hover:underline">Create a tenant and a project →</RouterLink>
      </template>
      <p v-else>Pick a project at the top to publish from it.</p>
    </div>

    <div v-else-if="loading" class="k-card"><StateBlock loading /></div>
    <div v-else-if="error" class="k-card"><StateBlock :error="error" /></div>

    <div v-else-if="!mayPublish" class="k-card px-4 py-6 text-xs text-muted">
      Publishing needs admin rights in {{ session.tenant }}/{{ session.project }}, and you do not have them.
    </div>

    <div v-else class="space-y-4">
      <div v-if="note" class="k-note" :class="noteError ? 'k-note--danger' : 'k-note--success'">{{ note }}</div>

      <Panel>
        <template #header>
          <span>1 · Registration</span>
          <span v-if="producerName" class="ml-auto k-badge k-badge--success">
            <span class="k-badge__dot" />
            producer {{ producerName }}
          </span>
        </template>
        <div class="px-4 py-3.5 space-y-3 text-xs text-muted leading-relaxed">
          <p v-if="producerName">
            This project is registered as the producer <span class="font-medium text-ink">{{ producerName }}</span>,
            and its published APIs are in the catalog.
          </p>
          <p v-else>
            Only the platform admin can put a project on the catalog. They register it as a producer on the Admin
            page, choosing <span class="text-ink">an existing project</span> and this path. Registration shows here
            once one of your APIs is published and listed.
          </p>
          <div class="flex items-center gap-2">
            <code class="font-mono text-[11px] text-ink bg-overlay px-2 py-1 rounded-[3px] truncate">{{ path }}</code>
            <button class="k-btn k-btn--ghost !px-2.5 !py-1" @click="copyPath">{{ copied ? 'Copied' : 'Copy' }}</button>
          </div>
        </div>
      </Panel>

      <Panel>
        <template #header>
          <span>2 · Allow the marketplace</span>
          <span v-if="consented" class="ml-auto k-badge k-badge--success"><span class="k-badge__dot" /> allowed</span>
          <span v-else-if="consentPhase" class="ml-auto k-badge k-badge--warning">{{ consentPhase }}</span>
        </template>
        <div class="px-4 py-3.5 space-y-3 text-xs text-muted leading-relaxed">
          <p>
            The marketplace has no access to your project until you allow it. Allowing creates the binding
            <code class="font-mono text-[11px]">{{ PUBLISH_BINDING }}</code> here, which lets it:
          </p>
          <ul class="list-disc pl-5 space-y-1 marker:text-faint">
            <li v-for="c in PUBLISH_CLAIMS.filter((c, i, all) => all.findIndex((x) => x.why === c.why) === i)" :key="c.resource">
              <span class="text-ink">{{ c.why }}</span>
            </li>
          </ul>
          <p class="k-note k-note--info">
            It reads nothing else, and writes only the grants that let consumers enable what you publish.
            Withdrawing deletes the binding, which takes every published API off the catalog.
          </p>

          <div v-if="!consentPhase" class="pt-1">
            <button class="k-btn k-btn--primary" :disabled="busy === 'consent'" @click="allow">
              <Spinner v-if="busy === 'consent'" />
              {{ busy === 'consent' ? 'Allowing…' : 'Allow the marketplace' }}
            </button>
          </div>
          <template v-else>
            <div v-if="missing.length" class="k-note k-note--warning space-y-2">
              <p>
                The marketplace now asks for more than this project allowed. Until you accept, it cannot:
              </p>
              <ul class="list-disc pl-5 space-y-0.5">
                <li v-for="c in missing" :key="c.resource">{{ c.why }}</li>
              </ul>
              <button class="k-btn k-btn--primary" :disabled="busy === 'consent'" @click="acceptMissing">
                <Spinner v-if="busy === 'consent'" />
                {{ busy === 'consent' ? 'Accepting…' : 'Accept' }}
              </button>
            </div>
            <div class="pt-1">
              <button class="k-btn k-btn--ghost" :disabled="busy === 'consent'" @click="asking = { kind: 'withdraw' }">
                Withdraw
              </button>
            </div>
          </template>
        </div>
      </Panel>

      <Panel>
        <template #header>
          <span>3 · Your APIs</span>
          <button v-if="!showNew" class="ml-auto k-btn k-btn--primary !px-2.5 !py-1" @click="showNew = true">New API</button>
        </template>

        <div v-if="showNew" class="px-4 py-3.5 border-b border-edge space-y-3">
          <div class="grid gap-2 sm:grid-cols-2">
            <label class="space-y-1">
              <span class="k-eyebrow">Kind</span>
              <input v-model="draft.kind" class="k-input" placeholder="Gadget" autofocus />
            </label>
            <label class="space-y-1">
              <span class="k-eyebrow">Plural</span>
              <input v-model="draft.plural" class="k-input" placeholder="gadgets" @input="pluralTouched = true" />
            </label>
            <label class="space-y-1">
              <span class="k-eyebrow">Group</span>
              <input v-model="draft.group" class="k-input" placeholder="gadgets.example.com" />
            </label>
            <div class="grid grid-cols-2 gap-2">
              <label class="space-y-1">
                <span class="k-eyebrow">Version</span>
                <input v-model="draft.version" class="k-input" placeholder="v1alpha1" />
              </label>
              <label class="space-y-1">
                <span class="k-eyebrow">Scope</span>
                <select v-model="draft.scope" class="k-input">
                  <option value="Cluster">Cluster</option>
                  <option value="Namespaced">Namespaced</option>
                </select>
              </label>
            </div>
          </div>

          <div class="space-y-1.5">
            <span class="k-eyebrow">Fields in spec</span>
            <div v-for="(f, i) in draft.fields" :key="i" class="flex gap-2">
              <input v-model="f.name" class="k-input flex-1 min-w-0" placeholder="field name, e.g. size" />
              <select v-model="f.type" class="k-input !w-32">
                <option v-for="t in FIELD_TYPES" :key="t" :value="t">{{ t }}</option>
              </select>
              <button class="k-btn k-btn--ghost !px-2" title="Remove field" @click="draft.fields.splice(i, 1)">Remove</button>
            </div>
            <button class="k-btn k-btn--ghost !px-2.5 !py-1" @click="draft.fields.push({ name: '', type: 'string' })">
              Add field
            </button>
          </div>

          <ul v-if="started && draftProblems.length" class="text-[11px] text-danger space-y-0.5">
            <li v-for="p in draftProblems" :key="p">{{ p }}</li>
          </ul>
          <p v-else-if="started" class="text-[11px] text-faint">
            Creates the export <code class="font-mono">{{ exportName(cleaned) }}</code>, unpublished.
          </p>

          <div class="flex gap-2">
            <button class="k-btn k-btn--primary" :disabled="busy === 'new' || !!draftProblems.length" @click="createAPI">
              <Spinner v-if="busy === 'new'" />
              {{ busy === 'new' ? 'Creating…' : 'Create' }}
            </button>
            <button class="k-btn k-btn--ghost" @click="showNew = false">Cancel</button>
          </div>
          <p class="text-[11px] text-faint leading-relaxed">
            This defines the API. Whatever should act on the objects consumers create, such as a controller, is
            yours to run. For anything the form does not cover, create the APIResourceSchema and APIExport with
            kubectl; they show up here either way.
          </p>
        </div>

        <StateBlock :empty="!exports.length" empty-text="No APIs in this project yet.">
          <table class="k-table">
            <thead>
              <tr><th>API</th><th>Kinds</th><th>Status</th><th /></tr>
            </thead>
            <tbody>
              <template v-for="e in exports" :key="e.metadata.name">
                <tr>
                  <td>
                    <div class="font-medium">{{ cardOf(e).displayName || e.metadata.name }}</div>
                    <div v-if="cardOf(e).displayName" class="font-mono text-[10px] text-faint">{{ e.metadata.name }}</div>
                  </td>
                  <td class="text-muted font-mono text-[11px]">{{ kindsOf(e) }}</td>
                  <td>
                    <span v-if="listedExports.has(e.metadata.name)" class="k-badge k-badge--success">
                      <span class="k-badge__dot" /> in the catalog
                    </span>
                    <span
                      v-else-if="isPublished(e)"
                      class="k-badge k-badge--warning"
                      :title="consented ? 'Waiting for the platform admin to register this project' : 'Allow the marketplace first'"
                    >
                      published, not listed
                    </span>
                    <span v-else class="k-badge k-badge--muted">draft</span>
                  </td>
                  <td class="text-right whitespace-nowrap">
                    <button class="k-btn k-btn--ghost !px-2" :disabled="!!busy" @click="edit(e)">Edit card</button>
                    <button
                      v-if="isPublished(e)"
                      class="k-btn k-btn--ghost !px-2"
                      :disabled="!!busy"
                      @click="asking = { kind: 'unpublish', export: e }"
                    >
                      <Spinner v-if="busy === e.metadata.name" :size="12" />
                      Unpublish
                    </button>
                    <button
                      v-else
                      class="k-btn k-btn--primary !px-2"
                      :disabled="!!busy || !consented"
                      :title="consented ? '' : 'Allow the marketplace first'"
                      @click="asking = { kind: 'publish', export: e }"
                    >
                      <Spinner v-if="busy === e.metadata.name" :size="12" />
                      Publish
                    </button>
                  </td>
                </tr>
                <tr v-if="editing === e.metadata.name">
                  <td colspan="4" class="!bg-overlay/40">
                    <div class="py-2 space-y-2">
                      <input v-model="card.displayName" class="k-input" placeholder="display name, e.g. Gadgets" />
                      <input v-model="card.description" class="k-input" placeholder="one line on what it does" />
                      <input v-model="card.docsURL" class="k-input" placeholder="documentation URL (optional)" />
                      <div class="flex gap-2">
                        <button class="k-btn k-btn--primary" :disabled="!!busy" @click="saveCard(e)">
                          <Spinner v-if="busy === e.metadata.name" />
                          {{ busy === e.metadata.name ? 'Saving…' : 'Save' }}
                        </button>
                        <button class="k-btn k-btn--ghost" @click="editing = ''">Cancel</button>
                      </div>
                    </div>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </StateBlock>
        <p v-if="exports.length && !consented" class="px-4 py-2.5 border-t border-edge text-[11px] text-faint">
          Publishing is available once the marketplace is allowed in step 2.
        </p>
      </Panel>
    </div>

    <ConfirmDialog
      v-if="asking?.kind === 'withdraw'"
      title="Withdraw the marketplace's access?"
      confirm-label="Withdraw"
      busy-label="Withdrawing…"
      :busy="askBusy"
      @confirm="confirmAsk"
      @cancel="asking = null"
    >
      This deletes the <code class="font-mono">{{ PUBLISH_BINDING }}</code> binding in
      {{ session.tenant }}/{{ session.project }}. Every published API leaves the catalog and nobody new can
      enable them. Projects that already enabled one keep it. Allowing again brings them back.
    </ConfirmDialog>
    <ConfirmDialog
      v-else-if="asking?.kind === 'publish'"
      :title="`Publish ${asking.export.metadata.name}?`"
      confirm-label="Publish"
      busy-label="Publishing…"
      tone="primary"
      :busy="askBusy"
      @confirm="confirmAsk"
      @cancel="asking = null"
    >
      Anyone who can see the catalog will see it, and any project admin can enable it. Check its card first:
      it shows as <span class="text-ink">{{ cardOf(asking.export).displayName || asking.export.metadata.name }}</span>.
    </ConfirmDialog>
    <ConfirmDialog
      v-else-if="asking?.kind === 'unpublish'"
      :title="`Unpublish ${asking.export.metadata.name}?`"
      confirm-label="Unpublish"
      busy-label="Unpublishing…"
      :busy="askBusy"
      @confirm="confirmAsk"
      @cancel="asking = null"
    >
      It leaves the catalog and nobody new can enable it. Projects that already enabled it keep it.
    </ConfirmDialog>
  </div>
</template>
