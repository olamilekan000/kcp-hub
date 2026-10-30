<script setup lang="ts">
// The catalog, and enabling from it. Enabling is a plain APIBinding the
// browser creates with the user's own token — there is no marketplace
// API to call and nothing privileged in the path, so a refusal here is
// kcp's answer about this person, shown as it came.
import { computed, onMounted, ref, watch } from 'vue'
import { useSession } from '@/stores/session'
import {
  offerings,
  createBinding,
  deleteBinding,
  bindings,
  ApiError,
  type APIBinding,
  type CatalogOffering,
} from '@/lib/api'
import PageHeader from '@/components/PageHeader.vue'
import Panel from '@/components/Panel.vue'
import StateBlock from '@/components/StateBlock.vue'
import Spinner from '@/components/Spinner.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import OfferingDetails from '@/components/OfferingDetails.vue'

const session = useSession()

const items = ref<CatalogOffering[]>([])
const loading = ref(false)
const error = ref('')
const busy = ref('')
const note = ref('')
const noteError = ref(false)

const workspace = computed(() => session.workspace)

// What this project has already bound. Without it every entry offered an
// Enable button, including the ones already enabled — the catalog is global
// but being enabled is a fact about one project, so the two have to be read
// together.
const bound = ref<APIBinding[]>([])

async function load() {
  loading.value = true
  error.value = ''
  try {
    const body = await offerings()
    items.value = body.items ?? []
    bound.value = workspace.value ? (await bindings(workspace.value)).items ?? [] : []
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e)
  } finally {
    loading.value = false
  }
}

/**
 * bindingFor finds the binding that enabled an offering, matching on BOTH
 * the export name and the workspace it lives in.
 *
 * Requiring both is deliberate. A binding written by hand may reference its
 * export by cluster id rather than by path, so this can miss one and offer
 * Enable for something already enabled — and that is the safe direction:
 * the create returns 409 and says so. Matching on the name alone would do
 * the opposite, calling an offering enabled because some other producer
 * exports the same name, and leaving no way to enable it.
 */
function bindingFor(offer: CatalogOffering): APIBinding | undefined {
  return bound.value.find((b) => {
    const exported = b.spec?.reference?.export
    return exported?.name === offer.export && exported?.path === offer.workspacePath
  })
}

type State = 'enabled' | 'pending' | 'available'

function stateOf(offer: CatalogOffering): State {
  const binding = bindingFor(offer)
  if (!binding) return 'available'
  return binding.status?.phase === 'Bound' ? 'enabled' : 'pending'
}

// kcp binds a new APIBinding, and finishes deleting one, a moment after the
// request returns, so the first read usually finds it in between. Keep
// reading the bindings, and only them, for a while so the entry settles
// without a reload.
async function until(settled: () => boolean) {
  const ws = workspace.value
  for (let i = 0; i < 20 && ws && ws === workspace.value && !settled(); i++) {
    await new Promise((resolve) => setTimeout(resolve, 1000))
    bound.value = (await bindings(ws)).items ?? []
  }
}

async function enable(offer: CatalogOffering) {
  if (!workspace.value || !offer.export || !offer.workspacePath) return
  busy.value = offer.metadata.name
  note.value = ''
  try {
    await createBinding(workspace.value, offer.offering, offer.workspacePath, offer.export, offer.claims ?? [])
    noteError.value = false
    note.value = `Enabled ${titleOf(offer)} in ${session.tenant}/${session.project}.`
    enabledNow.value = offer.offering
    // Re-read, so the entry stops offering to do it again.
    await load()
    await until(() => stateOf(offer) !== 'pending')
  } catch (e) {
    noteError.value = true
    note.value =
      e instanceof ApiError && e.forbidden
        ? `Forbidden in ${session.tenant}/${session.project}: you may not create APIBindings, or the offering is unpublished.`
        : e instanceof ApiError && e.status === 409
          ? `${titleOf(offer)} is already enabled.`
          : e instanceof Error
            ? e.message
            : String(e)
  } finally {
    busy.value = ''
  }
}

// Disabling is deleting the binding, so it asks first: the API stops being
// served, and anything in the workspace that was using it stops working
// until it is enabled again.
const confirming = ref<CatalogOffering | null>(null)

/** The entry open in the details dialog. */
const details = ref<CatalogOffering | null>(null)

// The binding just created, so the success note can point at the page
// that answers "now what" — which for a service-shaped producer is the
// whole point of enabling it.
const enabledNow = ref('')

async function disable(offer: CatalogOffering) {
  const binding = bindingFor(offer)
  if (!binding || !workspace.value) return
  busy.value = offer.metadata.name
  note.value = ''
  try {
    await deleteBinding(workspace.value, binding.metadata.name)
    noteError.value = false
    note.value = `Disabled ${titleOf(offer)} in ${session.tenant}/${session.project}.`
    confirming.value = null
    await load()
    await until(() => !bindingFor(offer))
  } catch (e) {
    confirming.value = null
    noteError.value = true
    note.value =
      e instanceof ApiError && e.forbidden
        ? `Forbidden in ${session.tenant}/${session.project}: you may not delete APIBindings there.`
        : e instanceof Error
          ? e.message
          : String(e)
  } finally {
    busy.value = ''
  }
}

/**
 * The card's name: the producer's display name, or the export's first
 * word, as the sidebar shows it. The marketplace fills an unset display
 * name with the export's name, so that counts as unset.
 */
function titleOf(offer: CatalogOffering): string {
  const named = offer.displayName && offer.displayName !== offer.export ? offer.displayName : ''
  return named || offer.offering.split(/[.-]/)[0].replace(/^\w/, (c) => c.toUpperCase())
}

/** What an offering asks to reach in your project, as resource names. */
function asksFor(offer: CatalogOffering): string {
  return [...new Set((offer.claims ?? []).map((c) => c.resource))].join(', ')
}

/** Where to go once it is enabled: the page for the binding it made. */
function openLink(offer: CatalogOffering): string {
  return `/p/${bindingFor(offer)?.metadata.name ?? offer.offering}`
}

onMounted(load)
// Being enabled is a fact about one project, so switching re-reads it.
watch(workspace, load)
</script>

<template>
  <div>
    <PageHeader
      title="Catalog"
      subtitle="APIs published by other teams. Enable one to use it in your project."
    >
      <template #actions>
        <span v-if="session.project" class="k-badge k-badge--muted">
          {{ session.tenant }}/{{ session.project }}
        </span>
      </template>
    </PageHeader>

    <div v-if="note" class="k-note mb-4 flex items-center gap-3" :class="noteError ? 'k-note--danger' : 'k-note--success'">
      <span>{{ note }}</span>
      <RouterLink v-if="!noteError && enabledNow" :to="`/p/${enabledNow}`" class="ml-auto shrink-0 underline">
        How to use it →
      </RouterLink>
    </div>

    <div v-if="!workspace && items.length" class="k-note k-note--info mb-4">
      Pick a project at the top to enable APIs in it.
    </div>

    <StateBlock :loading="loading" :error="error">
      <div v-if="!items.length" class="k-card p-5 max-w-2xl text-xs text-muted leading-relaxed space-y-3">
        <div class="text-[13px] font-semibold text-ink">Nothing has been published yet</div>
        <p>
          APIs show up here when a team publishes one. Any project can publish: open
          <span class="text-ink">Publish</span> in the sidebar of a project you admin, define an API, and ask a
          platform admin to register that project as a producer.
        </p>
        <RouterLink v-if="workspace" to="/publish" class="k-btn k-btn--ghost">Publish from this project</RouterLink>
      </div>
      <div v-else class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <div v-for="o in items" :key="o.metadata.name" class="k-card p-4 flex flex-col gap-2">
          <div class="flex items-start gap-2">
            <div class="min-w-0" :title="`${o.export} from ${o.workspacePath}`">
              <button class="block max-w-full text-left text-[13px] font-semibold truncate hover:text-accent" @click="details = o">
                {{ titleOf(o) }}
              </button>
              <div class="text-[11px] text-faint truncate">by {{ o.producer }}</div>
            </div>
            <span v-if="stateOf(o) === 'enabled'" class="ml-auto k-badge k-badge--success shrink-0">
              <span class="k-badge__dot" />
              Enabled
            </span>
            <span
              v-else-if="stateOf(o) === 'pending'"
              class="ml-auto k-badge k-badge--muted shrink-0"
              title="kcp is still setting the API up in your project"
            >
              <Spinner :size="10" />
              Enabling…
            </span>
            <span v-else-if="!o.ready" class="ml-auto k-badge k-badge--warning shrink-0" title="The producer is not ready yet">
              Unavailable
            </span>
          </div>

          <p class="text-xs text-muted leading-relaxed line-clamp-3">
            {{ o.description || 'No description.' }}
          </p>

          <p v-if="asksFor(o)" class="text-[11px] text-faint">
            Needs access to <span class="text-muted">{{ asksFor(o) }}</span> in your project.
          </p>

          <div class="mt-auto pt-2.5 border-t border-edge flex items-center gap-3">
            <button class="text-[11px] text-accent hover:underline" @click="details = o">Details</button>
            <a
              v-if="o.docsURL"
              :href="o.docsURL"
              target="_blank"
              rel="noreferrer"
              class="text-[11px] text-accent hover:underline"
            >Docs ↗</a>
            <template v-if="stateOf(o) === 'enabled'">
              <button
                class="ml-auto k-btn k-btn--ghost !px-2.5 !py-1"
                :disabled="busy === o.metadata.name"
                @click="confirming = o"
              >
                Disable
              </button>
              <RouterLink :to="openLink(o)" class="k-btn k-btn--primary !px-2.5 !py-1">Open</RouterLink>
            </template>
            <button
              v-else-if="stateOf(o) === 'available'"
              class="ml-auto k-btn k-btn--primary !px-2.5 !py-1"
              :disabled="!o.ready || !workspace || busy === o.metadata.name"
              :title="workspace ? '' : 'Pick a project first'"
              @click="enable(o)"
            >
              <Spinner v-if="busy === o.metadata.name" :size="12" />
              {{ busy === o.metadata.name ? 'Enabling…' : 'Enable' }}
            </button>
          </div>
        </div>
      </div>
    </StateBlock>

    <OfferingDetails
      v-if="details"
      :offering="details"
      :title="titleOf(details)"
      @close="details = null"
    />

    <ConfirmDialog
      v-if="confirming"
      :title="`Disable ${titleOf(confirming)}?`"
      confirm-label="Disable"
      busy-label="Disabling…"
      :busy="busy === confirming.metadata.name"
      @confirm="disable(confirming)"
      @cancel="confirming = null"
    >
      It stops being available in {{ session.tenant }}/{{ session.project }}, and anything using it there
      stops working. Objects you created with it are kept, and enabling it again brings them back.
    </ConfirmDialog>
  </div>
</template>
