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

A new stand starts with `hack/workshop/up.sh`. It refuses an existing control-plane VM. The script builds Go components, upstream-derived clients/API server, kernel, root filesystem and installation media in the tenant. It installs each guest's blank second disk, selects that disk for boot, joins workers, installs Cilium and deploys the agencies. The primary stand was built incrementally and exercised after upgrade. A second stand proved installation on empty disks using the verified native rootfs, signed package installation and the 21-check demo of that release; B27 is closed.

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

Hydrophone v0.5.0 prefers in-cluster credentials even when a kubeconfig is supplied. The runner removes only `KUBERNETES_SERVICE_HOST` and `KUBERNETES_SERVICE_PORT` for that process. `build-runner.sh` also changes the launcher's parallelism environment variable to `E2E_EXTRA_GINKGO_ARGS=--procs=8`: the v1.37.1 Go runner does not interpret numeric `E2E_PARALLEL`. The runner Pod tolerates the suite’s own NoExecute taints; otherwise a taint test can evict the launcher and destroy its unfinished results. The official conformance image and test binary are unchanged. No conformance tests are excluded by a custom skip expression.

Evidence stays in `/work/evidence/<run>` and is copied to `docs/evidence/`. Private material stays in `/work/kube`, `/work/keys`, `/work/trust` and `/work/tls`; none is served by the builder HTTP server or committed. `/work/out` contains public build outputs only. The original serving certificates expire on 2026-12-04; the2026-11-06 seven-day check passed. The chart preserves existing Secrets and generates 365-day certificates for a new installation. Check actual dates and renew before expiry; keys stay private.

A native upgrade uses `hack/kuberoot.sh build amd64`, then `hack/kuberoot.sh bundle amd64`, followed by `hack/stand/upgrade.sh` inside the builder with the signed bundle URL, SHA256 and the three guest addresses. The script checks the booted slot and a changed node boot ID, then node readiness. Keep the previous boot slot and signing keys for recovery. Add-on binaries are downloaded from immutable private builder snapshots and checked against SHA256. The clean-room installation repeats these steps on separate empty disks; the native inventory records component and overlay revisions separately. The installed release is native11, bundle SHA256 `abaa47aeb81c19a4aa7d28625083f24c2089ee2383c0ec4331a1f543929048dd`, on all three nodes.

`hack/package/build.sh` builds the real `kuberoot-rknetes` package in the builder, pushes charts only to its private OCI registry and signs the index with a private key outside `/work/out`. The package contains all 17 CRDs, controller/admission/MAX/watch-office workloads, the TSPU DaemonSet/BPF object and the immutable runtime-helper references. The runtime image is pinned by digest in `hack/package/runtime-image.ref` rather than read from a node, because a node may know the same digest under a lab-only repository name. Each init container verifies its binary before execution. TLS keys are generated during installation or preserved from existing Secrets, never embedded in the package.

`hack/package/install.sh` adopts only the objects generated by this repository and transfers their management to kubepkg. The original stand runs version 0.1.0 build 7. kubepkg refuses to republish an existing build with different content, so every changed chart takes a new build number; the historical fresh-install proof used build 3, and each generation keeps its own evidence. Initial Helm 4 server-side-apply ownership conflicts were fixed without deleting CRDs or their data. `hack/package/check.sh` validates the signature, package readiness, rollout, the TSPU binary and BPF object, the pinned runtime image and every installed binary hash. The private standalone chart is `/work/out/packages/rknetes-0.1.0-7.tgz`; index and signature are alongside it. No public registry was used.

Cilium runs with `kubeProxyReplacement=false` and `cni.chainingMode=portmap`. The initial upstream HostPort failure passed after enabling this native CNI path. The focused regression selected one test and passed it; suite lifecycle hooks are reported separately and never counted toward 462.

A second stand uses `RK_STAND_PREFIX=rk-clean` and its own `/work/cleanroom/kube` and `/work/cleanroom/tls`. `RK_REUSE_ARTIFACTS=1` requires an explicit `RK_ROOTFS_SHA256`; installation still starts from empty system disks. The measured machines used 3/5/3 GiB because two initial 5 GiB requests could not schedule on the workshop hosts. Only those new VM resources were reduced. `RK_RESUME_UNINSTALLED=1` is restricted to this second stand and verifies every target disk is empty before installation. `nodes.sh` waits for new VMI identities after restarting into installed disks. The original stand cannot be reinstalled by this resume option. The temporary VMs and their disks were removed after their evidence was preserved.

Tests start port-forwards through a bounded supervisor, verify their own listener and terminate/wait the exact child process. Closed upgraded streams can otherwise kill a carrier with broken pipe. The composed recovery uses a temporary NodePort on a private guest address, with client-certificate authentication and verified MAX server name; its cleanup removes the Service. No experiment changes the workshop control plane.

Fresh-image preparation downloads pinned real component programs without querying an existing cluster, builds clean Kine and obtains Go 1.26.0 through the module mirror before assembling rootfs. Fixtures read the current hash-named SBOM extraction. The disposable archive control plane uses the final eo-server executable. All compilation and image work stays in the tenant builder.

`hack/demo.sh <unique-run>` runs 53 top-level checks and the nested archive proof. It finishes node-taint and IPAM phases first, then runs the real 80-minute escalation, 15-minute measurement threshold and 10,001-watch proof alongside independent functional groups. Each group records source hashes, timestamps, logs and exit codes; the parent emits summary.json. It requires the optional experiment commands to match the shipped binaries byte-for-byte. Do not rebuild or reboot while that tour is active. On native11 the tour finishes in about 85 minutes; remove its lab namespaces and test node labels before conformance.
