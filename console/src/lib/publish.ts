// The producer's side of the marketplace. All of it happens in the
// producer's own project, as plain kcp objects the project's admin may
// already write:
//
//   - consent is an APIBinding to marketplace-publish, which lets the
//     marketplace read the project's exports and grant consumers `bind`
//     on the published ones;
//   - an API is an APIResourceSchema and the APIExport that serves it;
//   - publishing is an annotation on that export, and the card the catalog
//     shows is three more.
//
// The one thing a producer cannot do here is register: a Producer record
// naming this project lives in the catalog, which only the platform admin
// may write.

import {
  acceptedClaims,
  createBinding,
  createObject,
  deleteBinding,
  getObject,
  list,
  patchObject,
  type OfferingClaim,
} from './api'

/** Where marketplace-publish lives; `marketplace-vw init` puts it there. */
export const PUBLISH_EXPORT = { path: 'root:marketplace:controllers', name: 'marketplace-publish' }

/** The consent binding's name in the producer's project. */
export const PUBLISH_BINDING = 'marketplace-publish'

/**
 * What marketplace-publish claims, as its APIExport declares them. A user
 * cannot read that export, so the console carries the list; a binding
 * that accepted fewer would bind and then leave the marketplace blind.
 */
export const PUBLISH_CLAIMS: (OfferingClaim & { why: string })[] = [
  { group: 'apis.kcp.io', resource: 'apiexports', verbs: ['get', 'list', 'watch'], why: 'see which of your APIs are published' },
  { group: 'apis.kcp.io', resource: 'apiexportendpointslices', verbs: ['get', 'list', 'watch'], why: 'follow where published APIs are served' },
  { group: 'apis.kcp.io', resource: 'apiresourceschemas', verbs: ['get', 'list', 'watch'], why: "show consumers an API's schema before they enable it" },
  { group: 'core.kcp.io', resource: 'logicalclusters', verbs: ['get', 'list', 'watch'], why: 'match this project to your producer registration' },
  { group: '', resource: 'configmaps', verbs: ['get', 'list', 'watch'], why: 'read the usage instructions you attach to an API' },
  { group: 'rbac.authorization.k8s.io', resource: 'clusterroles', verbs: ['get', 'list', 'watch', 'create', 'update', 'delete'], why: 'grant consumers permission to enable a published API, and revoke it' },
  { group: 'rbac.authorization.k8s.io', resource: 'clusterrolebindings', verbs: ['get', 'list', 'watch', 'create', 'update', 'delete'], why: 'grant consumers permission to enable a published API, and revoke it' },
]

export const ANNOTATION = {
  publish: 'marketplace.kcp.hub/publish',
  displayName: 'marketplace.kcp.hub/display-name',
  description: 'marketplace.kcp.hub/description',
  docsURL: 'marketplace.kcp.hub/docs-url',
} as const

/**
 * canonicalPath is the workspace's path, such as root:team-a:apis, which
 * is what a Producer record names. The console addresses workspaces by
 * cluster name, so the path comes from the workspace's LogicalCluster.
 */
export async function canonicalPath(cluster: string): Promise<string> {
  const lc = (await getObject(cluster, 'core.kcp.io/v1alpha1', 'logicalclusters', 'cluster')) as {
    metadata?: { annotations?: Record<string, string> }
  }
  return lc.metadata?.annotations?.['kcp.io/path'] ?? ''
}

export function consent(cluster: string): Promise<unknown> {
  return createBinding(cluster, PUBLISH_BINDING, PUBLISH_EXPORT.path, PUBLISH_EXPORT.name, PUBLISH_CLAIMS)
}

/**
 * The claims marketplace-publish makes that a binding has not accepted. A
 * binding made before the export claimed more keeps what it accepted, so
 * the marketplace sees less of the project until its admin accepts the rest.
 */
export function missingClaims(accepted: { group?: string; resource: string; state?: string }[]) {
  const has = new Set(accepted.filter((c) => c.state === 'Accepted').map((c) => `${c.group ?? ''}/${c.resource}`))
  return PUBLISH_CLAIMS.filter((c) => !has.has(`${c.group ?? ''}/${c.resource}`))
}

export function acceptAllClaims(cluster: string): Promise<unknown> {
  return patchObject(cluster, 'apis.kcp.io/v1alpha2', 'apibindings', PUBLISH_BINDING, {
    spec: { permissionClaims: acceptedClaims(PUBLISH_CLAIMS) },
  })
}

export function withdrawConsent(cluster: string): Promise<unknown> {
  return deleteBinding(cluster, PUBLISH_BINDING)
}

export interface APIExport {
  metadata: { name: string; annotations?: Record<string, string> }
  spec?: { resources?: { name: string; group?: string; schema?: string }[] }
}

export async function exportsIn(cluster: string): Promise<APIExport[]> {
  const body = await list(cluster, 'apis.kcp.io/v1alpha2', 'apiexports')
  return (body.items ?? []) as unknown as APIExport[]
}

export function isPublished(e: APIExport): boolean {
  return e.metadata.annotations?.[ANNOTATION.publish] === 'true'
}

/** The catalog card, as the export's annotations hold it. */
export interface Card {
  displayName: string
  description: string
  docsURL: string
}

export function cardOf(e: APIExport): Card {
  const a = e.metadata.annotations ?? {}
  return {
    displayName: a[ANNOTATION.displayName] ?? '',
    description: a[ANNOTATION.description] ?? '',
    docsURL: a[ANNOTATION.docsURL] ?? '',
  }
}

/**
 * publish sets or clears the publish annotation and writes the card with
 * it. An empty card field removes its annotation, so the catalog falls
 * back to the export's name rather than showing an empty one.
 */
export function publish(cluster: string, name: string, published: boolean, card: Card): Promise<unknown> {
  const value = (s: string) => s.trim() || null
  return patchObject(cluster, 'apis.kcp.io/v1alpha2', 'apiexports', name, {
    metadata: {
      annotations: {
        [ANNOTATION.publish]: published ? 'true' : null,
        [ANNOTATION.displayName]: value(card.displayName),
        [ANNOTATION.description]: value(card.description),
        [ANNOTATION.docsURL]: value(card.docsURL),
      },
    },
  })
}

// ── defining an API ──────────────────────────────────────────────────

export type FieldType = 'string' | 'integer' | 'number' | 'boolean'

export interface NewAPI {
  group: string
  version: string
  kind: string
  plural: string
  scope: 'Cluster' | 'Namespaced'
  /** The fields of the object's spec. */
  fields: { name: string; type: FieldType }[]
}

/** The plural a kind usually takes; a suggestion the form lets you change. */
export function pluralOf(kind: string): string {
  const k = kind.trim().toLowerCase()
  if (!k) return ''
  if (/(s|x|z|ch|sh)$/.test(k)) return `${k}es`
  if (/[^aeiou]y$/.test(k)) return `${k.slice(0, -1)}ies`
  return `${k}s`
}

const DNS_SUBDOMAIN = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+$/
const DNS_LABEL = /^[a-z]([-a-z0-9]*[a-z0-9])?$/
const VERSION = /^v[0-9]+((alpha|beta)[0-9]+)?$/
const KIND = /^[A-Z][A-Za-z0-9]*$/
const FIELD = /^[a-zA-Z][a-zA-Z0-9]*$/

/** problems lists what is wrong with a definition, in the form's words. */
export function problems(api: NewAPI): string[] {
  const out: string[] = []
  if (!DNS_SUBDOMAIN.test(api.group)) out.push('The group must be a domain you own, such as widgets.example.com.')
  if (!VERSION.test(api.version)) out.push('The version looks like v1, v1beta1 or v1alpha1.')
  if (!KIND.test(api.kind)) out.push('The kind starts with a capital letter and has only letters and digits, such as Widget.')
  if (!DNS_LABEL.test(api.plural)) out.push('The plural is lowercase letters, digits and hyphens, such as widgets.')
  const names = api.fields.map((f) => f.name)
  if (names.some((n) => !FIELD.test(n))) out.push('Field names start with a letter and have only letters and digits.')
  if (new Set(names).size !== names.length) out.push('Two fields have the same name.')
  return out
}

export function schemaName(api: NewAPI): string {
  return `${api.version}.${api.plural}.${api.group}`
}

export function exportName(api: NewAPI): string {
  return `${api.plural}.${api.group}`
}

export function schemaFor(api: NewAPI): Record<string, unknown> {
  const properties = Object.fromEntries(api.fields.map((f) => [f.name, { type: f.type }]))
  return {
    apiVersion: 'apis.kcp.io/v1alpha1',
    kind: 'APIResourceSchema',
    metadata: { name: schemaName(api) },
    spec: {
      group: api.group,
      names: {
        kind: api.kind,
        listKind: `${api.kind}List`,
        plural: api.plural,
        singular: api.kind.toLowerCase(),
      },
      scope: api.scope,
      versions: [
        {
          name: api.version,
          served: true,
          storage: true,
          schema: {
            type: 'object',
            properties: {
              apiVersion: { type: 'string' },
              kind: { type: 'string' },
              metadata: { type: 'object' },
              spec: { type: 'object', properties },
            },
          },
        },
      ],
    },
  }
}

/** exportFor serves the schema. It is not published until the producer says so. */
export function exportFor(api: NewAPI): Record<string, unknown> {
  return {
    apiVersion: 'apis.kcp.io/v1alpha2',
    kind: 'APIExport',
    metadata: { name: exportName(api) },
    spec: {
      resources: [{ name: api.plural, group: api.group, schema: schemaName(api), storage: { crd: {} } }],
    },
  }
}

export async function defineAPI(cluster: string, api: NewAPI): Promise<void> {
  await createObject(cluster, 'apis.kcp.io/v1alpha1', 'apiresourceschemas', schemaFor(api))
  await createObject(cluster, 'apis.kcp.io/v1alpha2', 'apiexports', exportFor(api))
}
