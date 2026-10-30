// The kubeconfig is pasted into a terminal as-is, so its shape is pinned.

import { describe, expect, it } from 'vitest'
import { parse } from 'yaml'
import { fileName, kubeconfig, snippets } from './kubeconfig'

describe('kubeconfig', () => {
  const base = {
    server: 'https://kcp.example.com:8443/',
    path: 'root:tenancy:tenants:team-a:apis',
    name: 'team-a/apis',
    user: 'alice@team-a.example.com',
    token: 't0ken',
  }

  it('points at the project and signs in with the token', () => {
    const c = parse(kubeconfig(base))
    expect(c['current-context']).toBe('team-a/apis')
    expect(c.clusters[0].cluster).toEqual({
      server: 'https://kcp.example.com:8443/clusters/root:tenancy:tenants:team-a:apis',
    })
    expect(c.users[0]).toEqual({ name: 'alice@team-a.example.com', user: { token: 't0ken' } })
    expect(c.contexts[0].context).toEqual({ cluster: 'team-a/apis', user: 'alice@team-a.example.com' })
  })

  it('carries the CA when there is one', () => {
    const c = parse(kubeconfig({ ...base, caPEM: 'PEM' }))
    expect(atob(c.clusters[0].cluster['certificate-authority-data'])).toBe('PEM')
  })
})

describe('snippets', () => {
  it('lists each enabled kind once, fully qualified', () => {
    const s = snippets(fileName('team-a', 'apis'), [
      { group: 'acme.example', resource: 'widgets' },
      { group: 'acme.example', resource: 'widgets' },
      { group: 'mallory.example', resource: 'gadgets' },
    ])
    expect(s[0].text).toContain('export KUBECONFIG=~/Downloads/team-a-apis.kubeconfig')
    expect(s[1].text).toBe('kubectl get widgets.acme.example\nkubectl get gadgets.mallory.example')
    expect(s[2].text).toBe('kubectl explain widgets.acme.example --recursive')
  })

  it('falls back to bindings when nothing is enabled', () => {
    expect(snippets('x.kubeconfig', []).map((s) => s.text)).toContain('kubectl get apibindings')
  })
})
