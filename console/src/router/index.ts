import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import * as oidc from '@/lib/oidc'

const routes: RouteRecordRaw[] = [
  // The root is the overview, which is also the wizard for somebody with
  // no project yet.
  { path: '/', redirect: '/overview' },
  { path: '/login', name: 'login', component: () => import('@/pages/LoginPage.vue'), meta: { public: true } },
  { path: '/callback', name: 'callback', component: () => import('@/pages/CallbackPage.vue'), meta: { public: true } },
  { path: '/profile', name: 'profile', component: () => import('@/pages/ProfilePage.vue') },
  // First run used to be a page of its own; the overview shows it now.
  { path: '/welcome', redirect: '/overview' },
  { path: '/tenants', name: 'tenants', component: () => import('@/pages/TenantsPage.vue') },
  // A tenant is managed rather than entered, so it gets a page of its own
  // instead of becoming a selectable context.
  { path: '/tenants/:name', name: 'tenant', component: () => import('@/pages/TenantPage.vue') },
  {
    path: '/tenants/:name/access',
    name: 'tenant-access',
    component: () => import('@/pages/TenantAccessPage.vue'),
  },
  // Projects had a page of its own until the tenant page took over both
  // halves of it — listing what is inside a tenant, and adding one. Kept
  // as a redirect so older links still land somewhere sensible.
  { path: '/projects', redirect: '/tenants' },
  { path: '/overview', name: 'overview', component: () => import('@/pages/ProjectPage.vue') },
  { path: '/project', redirect: '/overview' },
  { path: '/catalog', name: 'catalog', component: () => import('@/pages/CatalogPage.vue') },
  { path: '/api', name: 'api', component: () => import('@/pages/ApiViewerPage.vue') },
  // The producer's side: offering this project's own APIs in the catalog.
  { path: '/publish', name: 'publish', component: () => import('@/pages/PublishPage.vue') },
  // One enabled producer in the selected project: what it is, how to use
  // it, and what it serves. The sidebar lands here.
  { path: '/p/:binding', name: 'producer', component: () => import('@/pages/ProducerPage.vue') },
  // One enabled offering's resources: /r/<group>/<resource>, with the
  // group left empty for core types.
  { path: '/r/:group/:resource', name: 'resource', component: () => import('@/pages/ResourcePage.vue') },
  { path: '/admin', name: 'admin', component: () => import('@/pages/AdminPage.vue') },
  { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/pages/NotFoundPage.vue'), meta: { public: true } },
]

export const router = createRouter({ history: createWebHistory(), routes })

// One guard, one rule: everything but the login pages needs a token.
// Losing it mid-session sends you back to login with where you were, so
// you land back there after signing in.
router.beforeEach((to) => {
  if (to.meta.public) return true
  if (oidc.token()) return true
  return { name: 'login', query: { returnTo: to.fullPath } }
})
