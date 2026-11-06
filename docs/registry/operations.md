# Installation, development and support record

[Русская версия](operations.ru.md)

The delivery contains the RKNetes source, Apache-2.0 licence, kuberoot distribution overlay, structural CRDs, Go binaries and stand scripts. It is an experimental laboratory distribution. Describe only capabilities backed by the release's test artefacts.

Installation on the workshop stand uses one `rknetes` Tenant, its builder and three nested VMs. The entry point is `hack/workshop/up.sh`; [stand operations](../stand.md) documents its guarded installation and upgrade paths. It prepares pinned tools and runtime artifacts, builds and signs the native image in the tenant, installs only newly created VMs' empty system disks, joins the nodes, installs Cilium and applies the signed add-on package. An existing primary stand is not reinstalled. The nested-cluster marker and lab namespace selectors bound the experiments. Credentials remain outside release archives.

For each delivered release record [SUPPORTED ARCHITECTURES], [CPU/MEMORY/DISK MINIMA], [TESTED PLATFORMS], [INSTALLATION LOG], [E2E LOGS] and [UPSTREAM CONFORMANCE ARTEFACTS]. Do not substitute the number requested in the concept for the actual conformance result.

Source storage: [RIGHTS HOLDER'S REPOSITORY LOCATION, HOSTING JURISDICTION, ACCESS CONTROL, BACKUP AND RESTORE PROCEDURE]. Compilation: [BUILDER LOCATION, STAFF, PINNED TOOLCHAIN, INPUT HASHES, BUILD COMMANDS, OUTPUT HASHES]. The workshop path is development evidence, not a statement about the applicant's production facilities.

Life cycle: changes enter a versioned branch, undergo review, build in an isolated builder, and pass unit and stand tests. Preserve release source, dependency notices, test evidence and recovery instructions. The rights holder completes [SUPPORT CONTACT], [SUPPORT HOURS], [DEFECT RESPONSE TIMES], [END-OF-SUPPORT RULES], [RESPONSIBLE PERSONNEL] and [FINANCING ARRANGEMENTS].

Licence keys: RKNetes has no activation key generator, entitlement server, licence-key delivery system or usage limit in its Apache-2.0 code. Kubernetes client certificates, service-account tokens, image-signing keys and registry credentials are security credentials, not commercial activation keys. If a vendor adds commercial activation, describe and test that separate mechanism before attaching this statement.

Recovery procedures must refer to tested lab state: remove owned network policies, remove deliberate finalizers, remove cooling taints, restore the nested datastore from a snapshot, and verify workload traffic. Keep the workshop control plane out of every recovery command.
