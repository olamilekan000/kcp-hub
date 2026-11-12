# deploy

Manifests and charts that install kcp hub, both for the local kind setup
and for an existing cluster.

- [`chart/`](chart) is the Helm chart for kcp hub itself. See
  [Installing in your cluster](../docs/install.md).
- [`local/`](local) is what `make up` adds around it on kind: the cluster,
  cert-manager's local CA, the gateway, etcd, kcp-operator, Dex, the
  example producer, and the chart's settings in `values.yaml`.
