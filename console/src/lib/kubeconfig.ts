// A kubeconfig for one project, signed in as whoever downloads it. It
// carries the console's own sign-in token, so it works for as long as that
// sign-in does and no longer; there is nothing else to revoke.

import { stringify } from 'yaml'

export interface KubeconfigInput {
  /** kcp's address, such as https://kcp.example.com:8443. */
  server: string
  /** The project's canonical path, such as root:tenancy:tenants:team-a:apis. */
  path: string
  /** A context name people will recognise, such as team-a/apis. */
  name: string
  user: string
  token: string
  /** PEM for kcp's certificate; empty when the system already trusts it. */
  caPEM?: string
}

export function kubeconfig(k: KubeconfigInput): string {
  const cluster: Record<string, string> = { server: `${k.server.replace(/\/$/, '')}/clusters/${k.path}` }
  if (k.caPEM) cluster['certificate-authority-data'] = btoa(k.caPEM)
  return stringify({
    apiVersion: 'v1',
    kind: 'Config',
    clusters: [{ name: k.name, cluster }],
    users: [{ name: k.user, user: { token: k.token } }],
    contexts: [{ name: k.name, context: { cluster: k.name, user: k.user } }],
    'current-context': k.name,
  })
}

/** fileName is where the download lands: one file per project. */
export function fileName(tenant: string, project: string): string {
  return `${tenant}-${project}.kubeconfig`
}

export interface Snippet {
  title: string
  text: string
}

/**
 * snippets are the first commands worth running against a project, built
 * from what is enabled in it so they work as pasted.
 */
export function snippets(file: string, enabled: { group: string; resource: string }[]): Snippet[] {
  const out: Snippet[] = [
    { title: 'Use the project', text: `export KUBECONFIG=~/Downloads/${file}\nkubectl auth whoami` },
  ]
  const kinds = [...new Map(enabled.map((e) => [`${e.resource}.${e.group}`, e])).values()]
  if (kinds.length) {
    const first = `${kinds[0].resource}.${kinds[0].group}`
    out.push({
      title: 'See what you enabled',
      text: kinds.map((k) => `kubectl get ${k.resource}.${k.group}`).join('\n'),
    })
    out.push({ title: 'Learn the fields of one', text: `kubectl explain ${first} --recursive` })
  } else {
    out.push({ title: 'See what is enabled', text: 'kubectl get apibindings' })
  }
  out.push({ title: 'Everything this project serves', text: 'kubectl api-resources' })
  return out
}
