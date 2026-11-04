# Stand and reproduction

[Русская версия](stand.ru.md)

The workshop context is always `admin@workshop`, using `~/workshop.txt`. The only outer resources owned by this project are Tenant `tenant-root/rknetes` and its `tenant-rknetes` namespace. Its quota is 40 CPU / 64 GiB. The builder has a 60 GiB persistent volume; each of three nested VMs has 4 CPU / 8 GiB. No external VM address is requested.

| Resource | Address / identity |
|---|---|
| Builder | `tenant-rknetes/builder`, `10.244.8.11` |
| Control plane | `rk-cp`, `10.244.8.31`, node `kuberoot-eb636b` |
| Worker 1 | `rk-worker1`, `10.244.8.29`, node `kuberoot-00d000` |
| Worker 2 | `rk-worker2`, `10.244.8.28`, node `kuberoot-531721` |
| Nested Pod / Service ranges | `10.42.0.0/16` / `10.96.0.0/12` |
| Nested kubeconfig | `/work/kube/rknetes.conf` inside builder |
| Node API kubeconfig | `/work/kube/node.conf` inside builder |

Addresses are observations, not permanent assignments. `hack/workshop/up.sh` discovers them when provisioning. The nested Pod range must not overlap the outer Pod range. The outer DNS address overlaps the nested Service range, so the guest OS explicitly uses external recursive DNS for ordinary image downloads. No real external traffic is filtered.

A new stand starts with `hack/workshop/up.sh`. It refuses an existing control-plane VM. The script builds Go components, upstream-derived clients/API server, kernel, root filesystem and installation media in the tenant. It installs each guest's blank second disk, selects that disk for boot, joins workers, installs Cilium and deploys the agencies. The existing stand was built incrementally and exercised after upgrade; a clean-room rerun of the entire provisioning script is tracked in B27.

On an existing stand, these commands run from the repository:

```bash
hack/dev/build.sh
hack/workshop/kc.sh get nodes
bash -c 'source hack/workshop/common.sh; builder bash /work/src/rknetes/hack/demo.sh demo-unique-name'
```

The demo refuses pre-existing test namespaces. To remove disposable fixtures, pass their explicit names to `hack/e2e/cleanup.sh` inside the builder. The script verifies the lab marker, checks that IPAM reservations were released, stops lab reconciliation, removes only the deliberate `forever` finalizer and deletes those namespaces. It preserves node-local packet/session files. This cleanup never runs against the outer workshop context's namespace resources.

Before conformance, clean the lab namespaces and verify node readiness. Start a detached run so a laptop connection reset does not terminate collection:

```bash
bash -c 'source hack/workshop/common.sh; builder sh -c "nohup bash /work/src/rknetes/hack/conformance/run.sh unique-name </dev/null >/work/conformance-driver.log 2>&1 &"'
```

Hydrophone v0.5.0 prefers in-cluster credentials even when a kubeconfig is supplied. The runner removes only `KUBERNETES_SERVICE_HOST` and `KUBERNETES_SERVICE_PORT` for that process. `build-runner.sh` also changes the launcher's parallelism environment variable to `E2E_EXTRA_GINKGO_ARGS=--procs=8`: the v1.37.1 Go runner does not interpret numeric `E2E_PARALLEL`. The official conformance image and test binary are unchanged. No conformance tests are excluded by a custom skip expression.

Evidence stays in `/work/evidence/<run>` and is copied to `docs/evidence/`. Private material stays in `/work/kube`, `/work/keys`, `/work/trust` and `/work/tls`; none is served by the builder HTTP server or committed. `/work/out` contains public build outputs only. The temporary serving certificates last 30 days; renew them before their expiry.

A native upgrade uses `hack/kuberoot.sh build amd64`, then `hack/kuberoot.sh bundle amd64`, followed by `hack/stand/upgrade.sh` inside the builder with the signed bundle URL, SHA256 and the three guest addresses. The script checks the booted slot, then node readiness. Keep the previous boot slot and signing keys for recovery. Add-on binaries are currently downloaded from the private builder; B27/B29 cover immutable packaging and release provenance.
