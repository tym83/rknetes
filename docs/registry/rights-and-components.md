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

A measured [native bundle6 inventory and provenance archive](../evidence/inventory-native6.tar.gz) is attached. The SPDX scan found 2,793 package instances representing 482 distinct name/version/type tuples. Local module-cache and vendor licence lookup populated most entries; 389 instances still lack a detected licence. The scanner output is evidence for review, not a declaration that all obligations have been cleared. The archive includes the upstream Kubernetes patch, Go module inventory, kernel configuration and artifact hashes. All compared native/builder binaries match for this bundle. [Signed package build3 evidence](../evidence/package-build3.tar.gz) includes the public verification key, index, signature, chart and Ready status without private material. The optional research extensions have a separate source/build inventory and do not change the identity of the validated native bundle.
