# Rights and component evidence

[Русская версия](rights-and-components.ru.md)

Attach the contracts or authorship records for the original RKNetes changes. Provide a file-level change inventory against the pinned upstream revisions. A repository rename, translated interface, image tag, cache location or source mirror is not proof of original authorship or a transfer of upstream exclusive rights.

| Component | Origin / licence | Evidence |
|---|---|---|
| RKNetes controllers and CLI | This repository / Apache-2.0 | Release commit, source archive, LICENSE, original-change inventory |
| Kubernetes | kubernetes/kubernetes / Apache-2.0 | Pinned source tag, original notices, patch, executable checksums |
| kuberoot | kuberoot-dev/kuberoot | Pinned revision, original licence and notices, distribution overlay |
| Cilium and eBPF components | cilium/cilium and this repository | Version, individual code licences, chart and image digests |
| Linux | kernel.org / GPL-2.0-only with applicable exceptions | Exact source, configuration and correspondence to shipped kernel |
| containerd, runc, CoreDNS, etcd, Helm and Go modules | Upstream projects | Versioned inventory and original licence files |
| Test images and Helm chart dependencies | Per upstream artifact | Registry, digest, redirect chain, chart archive hashes |

Generate the actual dependency inventory from the build: `go list -m -json all`, module checksums, kernel source/configuration, node binary hashes, Cilium chart version and Pod imageIDs. Include transitive runtime dependencies and source-delivery obligations for bundled copyleft components. Preserve Apache copyright notices, licence texts and applicable NOTICE content; the rebranding script must never replace them. Consult the [Apache-2.0 licence text](https://www.apache.org/licenses/LICENSE-2.0) for redistribution conditions.

The rights holder completes [PAYMENTS REGISTER], [OWNERSHIP CHAIN], [DEVELOPMENT CONTRACTS] and [LICENCE INVENTORY REVIEW]. No evidence of these private facts is inferred from the source repository.

The final [native inventory](../evidence/inventory-final.tar.gz) records 4,201 instances and 1,351 distinct name/version/type tuples. Its [licence supplement](../evidence/licences-final.tar.gz) covers all 1,026 scanner omissions: 754 tuples, 397 distinct evidence texts, 526 module-archive h1 checks. Original licences remain separate: notably Grafana carries AGPL, Linux has GPL obligations, and Go's telemetry lockfile contributes npm references without claiming an installed JavaScript runtime. Generated Parca SDKs omit a root licence file; the supplement retains exact schema notices and generator licences with this boundary explicit. The scanner is not a legal clearance.

All compared native/builder binaries match. [Repeat-build evidence](../evidence/repeat-build.tar.gz) covers every RKNetes command from separate source directories. [Kine evidence](../evidence/kine-provenance.tar.gz) replaces the earlier dirty binary with exact upstream 35f4319798cf3543e49f86c775a1f8c5c23b1e80, a clean source tree and two identical builds. Rootfs timestamps and every imported upstream executable are outside that repeat-build claim. The Kubernetes patch, pinned base, Go module inventory, kernel configuration and artifact hashes are included. The older native6 inventories remain historical evidence.
