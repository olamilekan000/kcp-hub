// Reading an offered resource's schema the way a consumer needs it: which
// fields they would write, and what an object looks like. The schema is
// the APIResourceSchema's, verbatim, as the catalog carries it.

import { emptyFor, type OpenAPISchema } from './api'

/** Every object has these; they say nothing about the API. */
const STANDARD = new Set(['apiVersion', 'kind', 'metadata'])

export interface Field {
  /** Dotted path from the object's root, such as spec.size or spec.ports[]. */
  path: string
  type: string
  required: boolean
  description?: string
}

/** fields lists the schema's own fields, depth first, parents before children. */
export function fields(schema: OpenAPISchema | undefined): Field[] {
  const out: Field[] = []
  const walk = (s: OpenAPISchema, prefix: string, isRoot: boolean) => {
    const required = new Set(s.required ?? [])
    for (const [name, def] of Object.entries(s.properties ?? {})) {
      if (isRoot && STANDARD.has(name)) continue
      const path = prefix ? `${prefix}.${name}` : name
      out.push({ path, type: typeOf(def), required: required.has(name), description: def.description })
      if (def.properties) walk(def, path, false)
      else if (def.items?.properties) walk(def.items, `${path}[]`, false)
    }
  }
  if (schema) walk(schema, '', true)
  return out
}

function typeOf(s: OpenAPISchema): string {
  if (s.type === 'array') return `array of ${s.items ? typeOf(s.items) : 'anything'}`
  if (s.enum?.length) return `${s.type ?? 'string'}: ${s.enum.map(String).join(' | ')}`
  if (s.format) return `${s.type ?? 'string'} (${s.format})`
  return s.type ?? 'any'
}

/** example is an object of this kind with every field filled in empty. */
export function example(
  groupVersion: string,
  kind: string,
  scope: string | undefined,
  schema: OpenAPISchema | undefined,
): Record<string, unknown> {
  const metadata: Record<string, string> = { name: 'example' }
  if (scope === 'Namespaced') metadata.namespace = 'default'
  const obj: Record<string, unknown> = { apiVersion: groupVersion, kind, metadata }
  for (const [name, def] of Object.entries(schema?.properties ?? {})) {
    if (!STANDARD.has(name)) obj[name] = fill(def)
  }
  return obj
}

function fill(s: OpenAPISchema): unknown {
  if (s.default !== undefined) return s.default
  if (s.enum?.length) return s.enum[0]
  if (s.properties) {
    return Object.fromEntries(Object.entries(s.properties).map(([k, v]) => [k, fill(v)]))
  }
  if (s.type === 'array' && s.items) return [fill(s.items)]
  return emptyFor(s)
}
