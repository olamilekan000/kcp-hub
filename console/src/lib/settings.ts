// Deployment settings. A built image cannot carry them, because the same
// image is installed against different issuers and addresses, so the
// console server writes them into /config.js at startup. In development
// that file is empty and the VITE_* variables apply instead.

export interface Settings {
  kcpServer?: string
  oidcIssuer?: string
  oidcClientId?: string
  oidcScopes?: string
}

declare global {
  interface Window {
    __CONSOLE_CONFIG__?: Settings
  }
}

// Tests import this module outside a browser, where there is no window.
const runtime: Settings = (typeof window === 'undefined' ? undefined : window.__CONSOLE_CONFIG__) ?? {}

export const settings: Required<Settings> = {
  kcpServer: runtime.kcpServer || (import.meta.env.VITE_KCP_SERVER as string) || '',
  oidcIssuer: runtime.oidcIssuer || (import.meta.env.VITE_OIDC_ISSUER as string) || '',
  oidcClientId: runtime.oidcClientId || (import.meta.env.VITE_OIDC_CLIENT_ID as string) || 'kcp',
  oidcScopes: runtime.oidcScopes || (import.meta.env.VITE_OIDC_SCOPES as string) || 'openid email groups',
}
