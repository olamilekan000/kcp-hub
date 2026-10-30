// What the producer form writes is what consumers will bind, so the shape
// of the schema and export it produces is pinned down here.

import { describe, expect, it } from 'vitest'
import {
  PUBLISH_CLAIMS,
  exportFor,
  isPublished,
  missingClaims,
  pluralOf,
  problems,
  schemaFor,
  type APIExport,
  type NewAPI,
} from './publish'

const gadget: NewAPI = {
  group: 'gadgets.example.com',
  version: 'v1alpha1',
  kind: 'Gadget',
  plural: 'gadgets',
  scope: 'Cluster',
  fields: [
    { name: 'size', type: 'string' },
    { name: 'count', type: 'integer' },
  ],
}

describe('pluralOf', () => {
  it.each([
    ['Widget', 'widgets'],
    ['Box', 'boxes'],
    ['Policy', 'policies'],
    ['Key', 'keys'],
    ['', ''],
  ])('%s becomes %s', (kind, plural) => {
    expect(pluralOf(kind)).toBe(plural)
  })
})

describe('problems', () => {
  it('accepts a sound definition', () => {
    expect(problems(gadget)).toEqual([])
  })

  it('names each thing that is wrong', () => {
    const found = problems({
      ...gadget,
      group: 'gadgets',
      version: '1',
      kind: 'gadget',
      plural: 'Gadgets',
      fields: [
        { name: 'size', type: 'string' },
        { name: 'size', type: 'integer' },
        { name: '2nd', type: 'string' },
      ],
    })
    expect(found).toHaveLength(6)
  })
})

describe('schemaFor', () => {
  it('names the schema version.plural.group and puts the fields in spec', () => {
    const s = schemaFor(gadget) as {
      metadata: { name: string }
      spec: { scope: string; names: Record<string, string>; versions: { schema: { properties: { spec: unknown } } }[] }
    }
    expect(s.metadata.name).toBe('v1alpha1.gadgets.gadgets.example.com')
    expect(s.spec.scope).toBe('Cluster')
    expect(s.spec.names).toEqual({ kind: 'Gadget', listKind: 'GadgetList', plural: 'gadgets', singular: 'gadget' })
    expect(s.spec.versions[0].schema.properties.spec).toEqual({
      type: 'object',
      properties: { size: { type: 'string' }, count: { type: 'integer' } },
    })
  })
})

describe('exportFor', () => {
  it('serves the schema and is not published', () => {
    const e = exportFor(gadget) as { metadata: { name: string; annotations?: unknown }; spec: { resources: unknown[] } }
    expect(e.metadata.name).toBe('gadgets.gadgets.example.com')
    expect(e.metadata.annotations).toBeUndefined()
    expect(e.spec.resources).toEqual([
      { name: 'gadgets', group: 'gadgets.example.com', schema: 'v1alpha1.gadgets.gadgets.example.com', storage: { crd: {} } },
    ])
  })
})

describe('isPublished', () => {
  it('takes only "true" as published', () => {
    const e = (v?: string): APIExport => ({
      metadata: { name: 'x', annotations: v === undefined ? {} : { 'marketplace.kcp.hub/publish': v } },
    })
    expect(isPublished(e('true'))).toBe(true)
    expect(isPublished(e('yes'))).toBe(false)
    expect(isPublished(e())).toBe(false)
  })
})

describe('missingClaims', () => {
  const accepted = (resources: string[], state = 'Accepted') =>
    PUBLISH_CLAIMS.filter((c) => resources.includes(c.resource)).map((c) => ({ group: c.group, resource: c.resource, state }))

  it('is empty once every claim is accepted', () => {
    expect(missingClaims(accepted(PUBLISH_CLAIMS.map((c) => c.resource)))).toEqual([])
  })

  it('names what a binding made before the export claimed more lacks', () => {
    const old = PUBLISH_CLAIMS.map((c) => c.resource).filter((r) => r !== 'apiresourceschemas')
    expect(missingClaims(accepted(old)).map((c) => c.resource)).toEqual(['apiresourceschemas'])
  })

  it('counts a rejected claim as missing', () => {
    expect(missingClaims(accepted(PUBLISH_CLAIMS.map((c) => c.resource), 'Rejected'))).toHaveLength(PUBLISH_CLAIMS.length)
  })
})
