import { describe, expect, it } from 'vitest'
import { example, fields } from './schema'

const gadget = {
  type: 'object',
  properties: {
    apiVersion: { type: 'string' },
    kind: { type: 'string' },
    metadata: { type: 'object' },
    spec: {
      type: 'object',
      required: ['size'],
      properties: {
        size: { type: 'string', description: 'How big.' },
        color: { type: 'string', enum: ['red', 'blue'] },
        ports: { type: 'array', items: { type: 'object', properties: { port: { type: 'integer' } } } },
      },
    },
  },
}

describe('fields', () => {
  it('lists the API’s own fields, not the ones every object has', () => {
    expect(fields(gadget)).toEqual([
      { path: 'spec', type: 'object', required: false, description: undefined },
      { path: 'spec.size', type: 'string', required: true, description: 'How big.' },
      { path: 'spec.color', type: 'string: red | blue', required: false, description: undefined },
      { path: 'spec.ports', type: 'array of object', required: false, description: undefined },
      { path: 'spec.ports[].port', type: 'integer', required: false, description: undefined },
    ])
  })

  it('is empty without a schema', () => {
    expect(fields(undefined)).toEqual([])
  })
})

describe('example', () => {
  it('fills every field, and a namespace only for namespaced kinds', () => {
    expect(example('gadgets.example/v1', 'Gadget', 'Namespaced', gadget)).toEqual({
      apiVersion: 'gadgets.example/v1',
      kind: 'Gadget',
      metadata: { name: 'example', namespace: 'default' },
      spec: { size: '', color: 'red', ports: [{ port: 0 }] },
    })
    expect(example('gadgets.example/v1', 'Gadget', 'Cluster', gadget).metadata).toEqual({ name: 'example' })
  })
})
