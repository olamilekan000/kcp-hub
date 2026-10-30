<script setup lang="ts">
// One catalog entry in full: what the catalog says about it, the API it
// adds (each resource and its schema, as the producer defined them), and
// the entry itself, raw.
import { computed, ref } from 'vue'
import { stringify } from 'yaml'
import type { CatalogOffering, OfferingResource, OpenAPISchema } from '@/lib/api'
import { example, fields } from '@/lib/schema'
import Modal from './Modal.vue'
import CodeBlock from './CodeBlock.vue'

const props = defineProps<{ offering: CatalogOffering; title: string }>()
const emit = defineEmits<{ close: [] }>()

type Tab = 'overview' | 'api' | 'raw'
const tab = ref<Tab>('overview')
const tabs: { id: Tab; label: string }[] = [
  { id: 'overview', label: 'Overview' },
  { id: 'api', label: 'API' },
  { id: 'raw', label: 'Raw' },
]

// The server leaves out empty fields and list items carry no type, so the
// entry is shown in its full shape: every field, unset ones empty.
const raw = computed(() => {
  const o = props.offering
  return stringify({
    apiVersion: 'marketplace.platform.kcp.io/v1alpha1',
    kind: 'CatalogOffering',
    metadata: o.metadata,
    producer: o.producer,
    offering: o.offering,
    displayName: o.displayName ?? '',
    description: o.description ?? '',
    export: o.export ?? '',
    workspacePath: o.workspacePath ?? '',
    revision: o.revision ?? '',
    ready: o.ready,
    docsURL: o.docsURL ?? '',
    claims: o.claims ?? [],
    instructions: o.instructions ?? {},
    resources: o.resources ?? [],
  })
})
const resources = computed(() => props.offering.resources ?? [])

function groupOf(r: OfferingResource): string {
  return r.group || 'core'
}

type Version = NonNullable<OfferingResource['versions']>[number]

function fieldsOf(v: Version) {
  return fields(v.schema as OpenAPISchema | undefined)
}

function exampleOf(r: OfferingResource, v: Version): string {
  const gv = r.group ? `${r.group}/${v.name}` : v.name
  return stringify(example(gv, r.kind || r.resource, r.scope, v.schema as OpenAPISchema | undefined))
}
</script>

<template>
  <Modal size="lg" @close="emit('close')">
    <div class="k-card">
      <div class="px-4 py-2.5 border-b border-edge flex items-center gap-3">
        <div class="min-w-0">
          <div class="text-[13px] font-medium truncate">{{ title }}</div>
          <div class="text-[11px] text-faint truncate">by {{ offering.producer }}</div>
        </div>
        <div class="ml-auto flex gap-1">
          <button
            v-for="t in tabs"
            :key="t.id"
            class="k-btn !px-2.5 !py-1"
            :class="tab === t.id ? 'k-btn--primary' : 'k-btn--ghost'"
            @click="tab = t.id"
          >
            {{ t.label }}
          </button>
        </div>
      </div>

      <div class="px-4 py-3.5 max-h-[65vh] overflow-auto text-xs text-muted leading-relaxed">
        <div v-if="tab === 'overview'" class="space-y-4">
          <p>{{ offering.description || 'No description.' }}</p>
          <dl class="grid grid-cols-[8rem_1fr] gap-x-3 gap-y-1.5">
            <dt class="text-faint">Producer</dt>
            <dd class="text-ink">{{ offering.producer }}</dd>
            <dt class="text-faint">Adds</dt>
            <dd class="text-ink">
              <template v-if="resources.length">
                <span v-for="(r, i) in resources" :key="r.resource">
                  {{ i ? ', ' : '' }}{{ r.kind || r.resource }}
                </span>
              </template>
              <span v-else class="text-faint">Unknown</span>
            </dd>
            <dt class="text-faint">Export</dt>
            <dd class="font-mono text-[11px] text-ink">{{ offering.export }}</dd>
            <dt class="text-faint">Published from</dt>
            <dd class="font-mono text-[11px] text-ink break-all">{{ offering.workspacePath }}</dd>
            <dt class="text-faint">Status</dt>
            <dd class="text-ink">{{ offering.ready ? 'Available' : 'Not available yet' }}</dd>
            <template v-if="offering.docsURL">
              <dt class="text-faint">Docs</dt>
              <dd>
                <a :href="offering.docsURL" target="_blank" rel="noreferrer" class="text-accent hover:underline break-all">
                  {{ offering.docsURL }}
                </a>
              </dd>
            </template>
          </dl>

          <div class="space-y-1.5">
            <div class="k-eyebrow">Access it needs in your project</div>
            <p v-if="!offering.claims?.length">None. It only adds its own API.</p>
            <table v-else class="k-table">
              <thead>
                <tr><th>Resource</th><th>Group</th><th>Verbs</th><th>Scope</th></tr>
              </thead>
              <tbody>
                <tr v-for="(c, i) in offering.claims" :key="i">
                  <td class="font-medium">{{ c.resource }}</td>
                  <td class="font-mono text-[11px]">{{ c.group || 'core' }}</td>
                  <td class="font-mono text-[11px]">{{ (c.verbs ?? []).join(', ') || 'all' }}</td>
                  <td class="font-mono text-[11px]">
                    {{ c.matchLabels ? Object.entries(c.matchLabels).map(([k, v]) => `${k}=${v}`).join(', ') : 'everything' }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div v-else-if="tab === 'api'" class="space-y-5">
          <p v-if="!resources.length">The catalog does not know what this API serves.</p>
          <section v-for="r in resources" :key="r.resource" class="space-y-2">
            <div class="flex items-baseline gap-2 flex-wrap">
              <span class="text-[13px] font-medium text-ink">{{ r.kind || r.resource }}</span>
              <span class="font-mono text-[11px]">{{ r.resource }}.{{ groupOf(r) }}</span>
              <span v-if="r.scope" class="k-badge">{{ r.scope }}</span>
              <span v-for="v in r.versions ?? []" :key="v.name" class="k-badge">
                {{ v.name }}{{ v.storage ? ' · storage' : '' }}{{ v.served ? '' : ' · not served' }}
              </span>
            </div>
            <p v-if="!r.versions?.length" class="k-note k-note--info">
              The producer has not let the marketplace read this schema yet.
            </p>
            <div v-for="v in r.versions ?? []" :key="v.name" class="space-y-3">
              <div class="space-y-1.5">
                <div class="k-eyebrow">Fields{{ (r.versions?.length ?? 0) > 1 ? ` · ${v.name}` : '' }}</div>
                <p v-if="!fieldsOf(v).length">None: objects of this kind carry only a name and metadata.</p>
                <table v-else class="k-table">
                  <thead>
                    <tr><th>Field</th><th>Type</th><th>Description</th></tr>
                  </thead>
                  <tbody>
                    <tr v-for="f in fieldsOf(v)" :key="f.path">
                      <td class="font-mono text-[11px] text-ink whitespace-nowrap">
                        {{ f.path }}<span v-if="f.required" class="text-danger" title="required">*</span>
                      </td>
                      <td class="font-mono text-[11px]">{{ f.type }}</td>
                      <td>{{ f.description || '—' }}</td>
                    </tr>
                  </tbody>
                </table>
                <p v-if="fieldsOf(v).some((f) => f.required)" class="text-[11px] text-faint">
                  <span class="text-danger">*</span> required
                </p>
              </div>
              <CodeBlock :title="`Example ${r.kind || r.resource}`" :text="exampleOf(r, v)" />
              <details class="group">
                <summary class="cursor-pointer text-[11px] text-accent hover:underline select-none">
                  OpenAPI schema
                </summary>
                <div class="pt-2">
                  <CodeBlock :title="`${r.kind || r.resource} ${v.name}`" :text="stringify(v.schema ?? {})" />
                </div>
              </details>
            </div>
          </section>
        </div>

        <CodeBlock v-else title="The catalog entry" :text="raw" />
      </div>

      <div class="px-4 py-2.5 border-t border-edge">
        <button class="k-btn k-btn--ghost" @click="emit('close')">Close</button>
      </div>
    </div>
  </Modal>
</template>
