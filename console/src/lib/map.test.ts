import { describe, expect, it } from 'vitest'
import type { APIBinding, CatalogOffering } from './api'
import type { APIExport } from './publish'
import { providedAPIs, shortPath, usedAPIs } from './map'

const binding = (name: string, path: string, exportName: string, phase = 'Bound', kinds: string[] = []): APIBinding => ({
  metadata: { name },
  spec: { reference: { export: { path, name: exportName } } },
  status: { phase, boundResources: kinds.map((resource) => ({ resource })) },
})

describe('usedAPIs', () => {
  const offerings = [
    { workspacePath: 'root:tenancy:tenants:platform:apis', export: 'widgets', displayName: 'Widgets' },
  ] as CatalogOffering[]

  it('names what the catalog names, and leaves out the platform machinery', () => {
    const used = usedAPIs(
      [
        binding('tenancy-platform', 'root:tenancy:controllers', 'tenancy-platform'),
        binding('marketplace-publish', 'root:marketplace:controllers', 'marketplace-publish'),
        binding('tenancy-access', '2js17184mqifiadj', 'tenancy-access'),
        binding('widgets-x1', 'root:tenancy:tenants:platform:apis', 'widgets', 'Bound', ['widgets']),
        binding('gadgets-y2', 'root:tenancy:tenants:team-a:apis', 'gadgets', 'Binding'),
      ],
      offerings,
    )
    expect(used).toEqual([
      { binding: 'gadgets-y2', name: 'gadgets', provider: 'root:tenancy:tenants:team-a:apis', kinds: [], ready: false },
      { binding: 'widgets-x1', name: 'Widgets', provider: 'root:tenancy:tenants:platform:apis', kinds: ['widgets'], ready: true },
    ])
  })
})

describe('providedAPIs', () => {
  it('uses the catalog card name and reports whether it is published', () => {
    const exports: APIExport[] = [
      {
        metadata: { name: 'gadgets', annotations: { 'marketplace.kcp.hub/publish': 'true', 'marketplace.kcp.hub/display-name': 'Gadget' } },
        spec: { resources: [{ name: 'gadgets', group: 'gadgets.example.com' }] },
      },
      { metadata: { name: 'drafts' } },
    ]
    expect(providedAPIs(exports)).toEqual([
      { export: 'drafts', name: 'drafts', kinds: [], published: false },
      { export: 'gadgets', name: 'Gadget', kinds: ['gadgets'], published: true },
    ])
  })
})

describe('shortPath', () => {
  it.each([
    ['root:tenancy:tenants:team-a:apis', 'team-a/apis'],
    ['root:shared', 'shared'],
  ])('%s reads as %s', (path, want) => expect(shortPath(path)).toBe(want))
})
