# RKNetes

[Русская версия](README.ru.md)

RKNetes is a Kubernetes distribution built on kuberoot and Cilium. Its lab agencies turn the Russian internet-regulation satire in [the concept](docs/concept.ru.md) into measurable Kubernetes failure modes. The implementation uses real packets, admission requests, object watches, finalizers and node taints.

The native build runs `eo-server`, `gosplan` and `uchastkovy`. An unchanged upstream client accepts `kubectl get стручки`; `hodatay` provides branded text while retaining upstream structured versions. The source remains a modification of Kubernetes, with its authorship and licences preserved.

The stand uses one workshop Tenant, `tenant-root/rknetes`, containing a builder and three kuberoot VMs. Compilation runs in that builder. Censorship experiments act only on explicitly labelled lab namespaces inside the nested cluster. The workshop control plane and other tenants are outside the experiment.

Start with [stand operations](docs/stand.md), [design](docs/design.md), [measured evidence](docs/evidence.md) and the [specification acceptance record](BACKLOG.md). The [registry application templates](docs/registry/README.md) describe the product's actual origins and leave rights-holder facts blank. Nothing has been submitted or published.

```bash
# From this checkout. Refuses to reinstall an existing stand.
hack/workshop/up.sh

# Every outer and nested kubectl invocation selects admin@workshop explicitly.
hack/workshop/kc.sh get nodes
hack/workshop/kc.sh get стручки -n rknet-system

# Build and verify the Go components in the tenant builder.
hack/dev/build.sh
```

The reproducible lab tour is `hack/demo.sh`, executed inside the builder. It requires fresh lab namespaces and records each assertion separately. Upstream conformance uses `hack/conformance/run.sh`; the satirical [domestic conformance report](docs/domestic-conformance.md) is a different document. The exact upstream result belongs in the evidence report, never in a constant or a fabricated dashboard.

RKNetes code is Apache-2.0. Bundled Kubernetes, Linux, Cilium and other components retain their respective licences. `SESSION_LOG.md` is an ignored operational handover; credentials and signing keys stay outside the repository.

The release is the native11 image, installed on all three nodes, with the signed package `kuberoot-rknetes` 0.1.0 build 7. On that build `hack/demo.sh` passes all **53 checks** of the complete tour and upstream conformance passes **462/462**. The [evidence report](docs/evidence.md) binds both results to the bundle hash and archives; [experiments](docs/experiments.md) describe each mechanism, and every item in [BACKLOG](BACKLOG.md) is closed.
