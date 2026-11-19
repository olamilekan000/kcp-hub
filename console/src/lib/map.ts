// What a project is connected to, as the project map draws it: the APIs
// it uses on one side, the APIs it provides on the other.
//
// Built only from what the project's own members can read — its bindings,
// its exports, and the catalog. Who uses what this project provides lives
// in other projects, so the map does not claim to know it.

import { isPlatformGroup, type APIBinding, type CatalogOffering } from './api'
import { cardOf, isPublished, PUBLISH_EXPORT, type APIExport } from './publish'

/** Where the platform's own exports live; binding to them is machinery, not use. */
const platformExportPaths = new Set(['root:tenancy:controllers', PUBLISH_EXPORT.path])

export interface UsedAPI {
  binding: string
  name: string
  /** The workspace path of the project serving it. */
  provider: string
  kinds: string[]
  ready: boolean
}

export interface ProvidedAPI {
  export: string
  name: string
  kinds: string[]
  published: boolean
}

export function usedAPIs(bindings: APIBinding[], offerings: CatalogOffering[]): UsedAPI[] {
  const out: UsedAPI[] = []
  for (const b of bindings) {
    const ref = b.spec?.reference?.export
    if (!ref?.path || !ref.name || platformExportPaths.has(ref.path)) continue
    const kinds = (b.status?.boundResources ?? []).filter((r) => !isPlatformGroup(r.group ?? '')).map((r) => r.resource)
    const ready = b.status?.phase === 'Bound'
    // A bound binding that adds no resources carries only permissions, such
    // as tenancy-access, which a project's type binds by cluster name.
    if (ready && !kinds.length) continue
    const offering = offerings.find((o) => o.workspacePath === ref.path && o.export === ref.name)
    out.push({ binding: b.metadata.name, name: offering?.displayName || ref.name, provider: ref.path, kinds, ready })
  }
  return out.sort((a, b) => a.name.localeCompare(b.name))
}

export function providedAPIs(exports: APIExport[]): ProvidedAPI[] {
  return exports
    .map((e) => ({
      export: e.metadata.name,
      name: cardOf(e).displayName || e.metadata.name,
      kinds: (e.spec?.resources ?? []).map((r) => r.name),
      published: isPublished(e),
    }))
    .sort((a, b) => a.name.localeCompare(b.name))
}

/**
 * shortPath drops the tiers every project path shares, so root:tenancy:
 * tenants:platform:apis reads as platform/apis.
 */
export function shortPath(path: string): string {
  const parts = path.split(':')
  const at = parts.indexOf('tenants')
  return (at >= 0 ? parts.slice(at + 1) : parts.slice(1)).join('/') || path
}
