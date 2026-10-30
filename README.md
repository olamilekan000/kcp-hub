# kcp hub

> [!WARNING]
> This is an experimental repository. Anything in it can change at any time

kcp hub is the quickest way to get a real platform running on
[kcp](https://github.com/kcp-dev/kcp). Start it on your laptop or install it
in your cluster, and your teams can sign in, get their own workspaces and
share APIs with each other. From there, shape it into the platform you need.

kcp hub runs from this repository. It puts together pre-built components from
[contrib-virtual-workspaces](https://github.com/kcp-dev/contrib-virtual-workspaces)
into one platform. The web console lives here, in [console/](console/).

## What it gives you

- **Tenancy.** Tenants, projects and memberships, turned into real kcp
  workspaces and RBAC. Users can see what they belong to, and tenant admins
  can create projects and grant access themselves, without a cluster admin.
  Optionally, users can create their own tenant without waiting for an admin.
- **A marketplace.** Producers publish their APIs to a shared catalog. Other
  teams find them there and enable them in their projects with a plain kcp
  `APIBinding`.
- **Login.** Any OIDC provider. [Dex](https://dexidp.io) is used for local
  development.
- **A console and a CLI.** A web UI and `kubectl hub`, a
  [krew](https://krew.sigs.k8s.io) plugin, for logging in, choosing a project,
  browsing the catalog and enabling APIs.
- **Platform admins.** Named users or groups manage tenants and producers
  through a narrow role, not cluster-admin.

## Principles

- **Small.** kcp plus a few components. Every dependency has to earn its place.
- **Bring your own.** Organisations already run an identity provider, GitOps,
  databases and policy tooling. kcp hub doesn't ship its own; it works
  alongside what you already run.
- **Least privilege.** Once installed, components act through scoped kcp
  APIExports, never as cluster admins.
- **Plain kcp underneath.** Workspaces, APIExports and APIBindings are the
  real objects. Nothing hides them, so standard kcp tooling keeps working.
- **Easy to run.** One command for a full local environment, and the aim is
  an equally simple install in your own cluster.

## Terminology

| Term | Meaning |
|---|---|
| Workspace | kcp's unit of isolation: an API server of its own, with its own APIs, objects and RBAC. Workspaces nest, like directories. |
| APIExport | How a workspace offers an API to other workspaces. |
| APIBinding | How a workspace takes up an API that another workspace exports. |
| Virtual workspace | An API that kcp serves under `/services/...` without storing anything itself. It answers each user based on what they are allowed to see. |
| Operator | A controller that turns records, such as a Tenant, into real workspaces and permissions. |
| Front-proxy | kcp's single entry point. It checks who the caller is and routes the request to the right workspace or virtual workspace. |
| Tenant | An account, such as a team or a company, that holds projects and decides who may reach them. |
| Project | A workspace where a team does its work. Every project belongs to a tenant. |
| Membership | A grant of a role (`view`, `edit` or `admin`) on a tenant or a project, to a user or a group. |
| Platform admin | The person who runs kcp hub. They manage tenants and producers through a narrow role, not as a kcp admin. |
| Self-service | Letting any signed-in user request a tenant of their own, without waiting for a platform admin. |
| Producer | A team that publishes APIs to the catalog, from a workspace of its own. |
| Catalog | The list of published APIs that users can browse and enable. Each entry is called an offering. |

## How it fits together

![kcp hub architecture](docs/architecture.png)

Each feature is a kcp **virtual workspace** with an **operator**. The virtual
workspace answers questions on the user's behalf ("which projects am I in?",
"what can I enable?"); the operator turns records into real workspaces and
permissions.

### Tenancy

![Tenancy](docs/tenancy.svg)

A platform admin records a Tenant in the store. The operator gives it a
workspace, and every Project in it becomes a workspace of its own with the
team's RBAC. Tenant admins never write to their tenant workspace directly:
they ask the virtual workspace, which checks they are allowed and makes the
change for them. Members work straight in their project workspaces with
`kubectl`.

### Marketplace

![Marketplace](docs/marketplace.svg)

A platform admin registers a producer in the catalog, and the operator
creates the producer's workspace. The producer publishes by annotating their
own `APIExport`, and the operator grants others permission to bind it.
Consumers browse the catalog through the virtual workspace, then enable an
API by creating an `APIBinding` in their own workspace. That binding is plain
kcp: the marketplace never writes into consumer workspaces.

## Running it locally

`make up` creates a kind cluster with kcp at `https://kcp.localhost:8443`
and Dex, the sign-in provider, at `https://dex.kcp.localhost:8443/dex`.
Tenancy and the marketplace are served by kcp at
`https://kcp.localhost:8443/services/tenancy` and
`https://kcp.localhost:8443/services/marketplace`, and the console at
`https://console.kcp.localhost:8443`. `make down` deletes it all again. It
needs docker, kind, kubectl, helm, curl and git.

The console's and Dex's certificates come from a local CA, written to
`.hub/ca.crt`. Trust it once so the browser accepts both. On macOS:

```sh
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain .hub/ca.crt
```

Otherwise, open Dex's address and accept the warning before signing in to
the console. The console calls Dex from the page, where the browser cannot
ask.

Dex has these test users, all with the password `password`:

- `admin@platform.example.com`, the platform admin, who can create tenants
  and register producers
- `alice@team-a.example.com`, `bob@team-b.example.com` and
  `mallory@strangers.example.com`, who start out in no tenant

Self-service is on, so any signed-in user can request a tenant of their
own and then projects in it. The catalog starts with one example API,
Widgets from the producer `acme`, which anyone can enable in their project.
To work as one of them:

```sh
make login EMAIL=alice@team-a.example.com
export KUBECONFIG=$PWD/.hub/users/alice.kubeconfig
kubectl auth whoami
```
