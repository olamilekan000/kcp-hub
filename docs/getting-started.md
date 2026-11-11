# Getting started

This guide takes you from nothing to a working kcp hub on your laptop. You
will sign in as a test user, create a tenant and a project, enable an API
from the catalog, and publish an API of your own for another team to use.

It takes about 20 minutes, most of it waiting for `make up` the first time.

## 1. Install the tools

You need:

- [Docker](https://docs.docker.com/get-docker/), or another Docker runtime
  such as [Colima](https://github.com/abiosoft/colima). Give it at least
  4 CPUs and 8 GB of memory. With less, kcp does not start.
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- `curl`, `git` and `make`, and `jq` for `make test`

With Colima, start it with enough room:

```sh
colima start --cpu 4 --memory 8
```

Port 8443 on your machine must be free. kcp hub is reached through it.

## 2. Start the platform

```sh
git clone https://github.com/olamilekan000/kcp-hub.git
cd kcp-hub
make up
```

`make up` creates a kind cluster called `kcp-hub` and installs everything in
it: kcp, Dex for signing in, tenancy, the marketplace and the web console.
The first run downloads a lot and takes 10 to 15 minutes. Later runs are
quicker. It is safe to run again at any time.

When it is done, check that everything works:

```sh
make test
```

It ends with `smoke test passed`.

## 3. Trust the local certificate

The console and Dex use certificates from a CA that `make up` created, at
`.hub/ca.crt`. Trust it once, so your browser accepts them. On macOS:

```sh
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain .hub/ca.crt
```

If you would rather not, open `https://dex.kcp.localhost:8443/dex` and accept
the browser's warning, then do the same for
`https://console.kcp.localhost:8443`. Do Dex first: the console calls it from
the page, where the browser cannot show you the warning.

## 4. Sign in

Open `https://console.kcp.localhost:8443` and click **Sign in**. Dex asks for
an email and a password. Use:

- Email: `alice@team-a.example.com`
- Password: `password`

These test users exist, all with the password `password`:

| User | Who they are |
|---|---|
| `admin@platform.example.com` | The platform admin. Registers producers and manages tenants. |
| `alice@team-a.example.com` | A user on team A, in no tenant yet. |
| `bob@team-b.example.com` | A user on team B, in no tenant yet. |
| `mallory@strangers.example.com` | A user who should not see anyone else's work. |

## 5. Create a tenant and a project

Alice is in no tenant yet, so the console opens on the **Welcome** page.

1. Name your tenant, for example `team-a`, and click **Create**. A tenant is
   your team's account. You become its admin.
2. When it is ready, name your first project, for example `apis`, and click
   **Create**. A project is a kcp workspace where your work happens.

The picker at the top of the console now shows `team-a/apis`. You can add more
tenants and projects later from **Tenants**.

## 6. Enable an API from the catalog

1. Open **Catalog**. It lists APIs that other teams publish. One is there
   from the start: **Widgets**, from the example producer `acme`.
2. Click **Enable** on Widgets. This creates a plain kcp `APIBinding` in your
   project.
3. Click **Open**. The page lists what the API serves. Open **Widget**, click
   **New Widget**, fill in the object and click **Apply**.

You just created a Widget in your project, through an API that another team
owns.

## 7. Publish your own API

Now alice offers an API to other teams. This takes three people: alice
publishes, the platform admin puts her project on the catalog, and bob
enables it.

### As alice

1. Open **Publish**. Copy the project path shown under **1 · Registration**,
   such as `root:tenancy:tenants:team-a:apis`. The platform admin needs it.
2. Under **2 · Allow the marketplace**, click **Allow the marketplace**. This
   lets the marketplace see which of your APIs are published, and let others
   enable them. It reads nothing else in your project.
3. Under **3 · Your APIs**, click **New API** and fill in:
   - Kind: `Gadget` (Plural fills itself in)
   - Group: `gadgets.example.com`
   - Fields in spec: `color`, of type `string`

   Click **Create**. The API is created as a draft.
4. Click **Edit card** next to it. Set the display name to `Gadgets`, add a
   line on what it does, and click **Save**. This is what other teams see in
   the catalog.
5. Click **Publish**, and confirm. It shows **published, not listed** until
   the platform admin registers the project.

### As the platform admin

Use a private browser window, so you stay signed in as alice in the other
one.

1. Open `https://console.kcp.localhost:8443` and sign in as
   `admin@platform.example.com`.
2. Open **Admin** and click **Register producer**.
3. Choose **An existing project**. Enter a name, such as `team-a`, and paste
   alice's project path. Click **Register**.

Back as alice, the Gadget API now shows **in the catalog**.

### As bob

1. In the private window, click **Sign out** at the top right, then sign
   in as `bob@team-b.example.com`.
2. Create a tenant and a project for him on the **Welcome** page, such as
   `team-b` and `app`.
3. Open **Catalog**. **Gadgets** is listed. Click **Enable**, then **Open**,
   open **Gadget** and create one.

Bob is now using alice's API in his own project. Neither of them needed the
platform admin for anything except putting alice's project on the catalog.

## 8. Use it from the terminal

Everything in the console works with `kubectl` too. To sign in as alice:

```sh
make login EMAIL=alice@team-a.example.com
export KUBECONFIG=$PWD/.hub/users/alice.kubeconfig
kubectl auth whoami
```

To work in a project, open it in the console and click **Download
kubeconfig** on its **Overview** page. The page also lists commands to try.

## 9. Clean up

```sh
make down
```

This deletes the kind cluster and everything in `.hub/`.

## If something goes wrong

- **`make up` waits for `https://kcp.localhost:8443` and gives up.** kcp
  probably did not start. Run
  `KUBECONFIG=.hub/kind.kubeconfig kubectl -n kcp get pods`. Pods in `Pending`
  mean Docker has too little CPU or memory. Give it more (see step 1),
  run `make down`, then `make up` again. On a slow network, kcp's image can
  take several minutes to download; running `make up` again continues where
  it stopped.
- **`port 8443 is already in use`.** Stop whatever listens on port 8443.
- **The console cannot sign you in.** Your browser does not trust Dex's
  certificate yet. See step 3.
- **The tenancy or marketplace operator shows restarts.** They wait for kcp
  to be set up when the platform starts, and restart until it is. Restarts
  during `make up` are expected.

## Where to go next

- [How it fits together](../README.md#how-it-fits-together) explains what
  runs where.
- To install kcp hub in your own cluster, use the Helm chart in
  [`deploy/chart`](../deploy/chart). Its [`values.yaml`](../deploy/chart/values.yaml)
  lists the settings: the hostname, TLS, your OIDC provider, platform admins,
  and whether users may create their own tenants.
  [`deploy/local/values.yaml`](../deploy/local/values.yaml) is what
  `make up` uses. The cluster needs cert-manager, kcp-operator, etcd and a
  Gateway API gateway with a TLS passthrough listener; `hack/up.sh` shows
  how the local setup installs each of them.
