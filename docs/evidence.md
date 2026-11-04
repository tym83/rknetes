# Measured evidence

[Русская версия](evidence.ru.md)

The native three-node stand completed `demo-native-3` on 2026-11-04: **21 checks passed, zero failed**. Each script's log and exit code is in [the preserved demo archive](evidence/demo-native-3.tar.gz). These results prove the mechanisms named below, not every narrative detail of a contour. [BACKLOG](../BACKLOG.md) identifies the remaining requirements.

| Contour | Automated proof in `hack/e2e/` | Observed behavior |
|---|---|---|
| 1 | `01-reestr.sh`, `01-self-block.sh`, `01-escalation.sh` | Real IP deny, Cilium IPAM reuse, BornBlocked, annotation amnesty; controller's API route times out and is recovered out of band; timed IP, node and pool stages cause measured collateral denial. |
| 2 | `02-throttle.sh` | Unescaped `t.co` matches payment-controller and Cilium reduces measured cross-node throughput. |
| 3 | `03-sovereign-16k.sh` | Exactly 16,384 payload bytes arrive; subsequent reads time out while readiness still responds. |
| 4 | `04-whitelist.sh`, `04-ephemeral.sh`, `04-werewolf.sh`, `04-observe.sh` | Labels allow traffic, manual EndpointSlice and ephemeral-container intrusion trigger whole-destination denial; Service externalIPs captures a lab address; why reads actual Hubble policy-drop verdicts. |
| 5 | `05-pigeon.sh` | 100 valid IPv4/UDP datagrams traverse shared storage under network deny; 54 arrive, 46 are lost, after the full 180-second delay. |
| 6 | `06-calls.sh`, `06-max.sh` | Direct exec is refused; authenticated `kubectl max exec` succeeds and upgraded-stream bytes are archived. |
| 7 | `07-origin.sh` | A domestic reference with the same supplied foreign image digest receives the foreign-agent label in server admission. |
| 8 | `08-import.sh`, `08-goshran.sh` | Unmodified kubectl resolves стручки; native version is v1.37.1/dirty; real HTTP blob redirect and byte-identical Helm index. |
| 9 | `09-escrow-forever.sh` | TLS Secret bytes match escrow exactly; a real deleted Pod remains Terminating behind its finalizer. |
| 10 | `10-drill.sh` | Selected foreign lab traffic stops while the official drill condition reports success. |
| 11 | `11-erid.sh`, `11-blogger.sh` | Unmarked successful Event is rejected; four simultaneous watches exceed a test threshold of three, receive 451, and resume after registration. |
| 12 | `12-cooling.sh` | Actual NoExecute eviction and removal of the taint after captcha completion is recorded. |
| Agencies | `17-agencies.sh`, `17-agency-timeout.sh` | Delayed validating hooks run concurrently. The separate deadline test measures a real fail-closed timeout after 31 seconds and a successful ordinary retry. |

After all checks, the controller generated the final StatusStatement and it was read from the API. The detached remote run completed and all 21 saved exit-code files were independently checked. The earlier 19-case run is retained in the first evidence archive. Cleanup removed the explicitly labelled lab fixtures and released their IPAM reservations before conformance.

Native bundle: `kuberoot-0.1.0-dev-amd64.tar`, SHA256 `8c8c49636437e770e106072c5693258c87afe8220df8ce632ff41c489ea2f19a`. The bundle is signed; private signing material is excluded. Kubernetes is v1.37.1, upstream commit `f78e722310e50bcaca9276be22276d9e91d91308`, modified tree. Cilium is 1.20.4; the kernel is 6.18.55-kuberoot and containerd 2.4.1.

Conformance run5 completed on 2026-11-04: **462/462 passed, zero failed and zero skipped conformance specs**, runner exit code 0. The unchanged official test binary uses the pinned image `registry.k8s.io/conformance:v1.37.1@sha256:c48b0c496e600718f50fa0cc19a49f3c4e27cc83894da84ccccc539539884c3b`. [The full archive](evidence/conformance-run5.tar.gz) contains JUnit, logs, exact image, component versions and parsed counts. Of 483 successful XML records, 21 are lifecycle hooks and are excluded from 462. The selection omits 2,744 non-Conformance specs; no additional skip expression is used. This result applies to native bundle6 and package build3. The earlier complete run4 also passed 462/462 and is retained separately. Run1 failed credential selection before creating resources. Run2 was interrupted to fix numeric parallelism. Run3 was interrupted when the upstream NoExecute test evicted its runner; it also exposed a HostPort failure. Portmap chaining fixed HostPort (the focused upstream regression passed 1/1); the launcher now tolerates suite taints. No Conformance tests were altered or skipped.

The installed `kuberoot-rknetes` 0.1.0 build 3 package is Ready; its [signed artifacts and status](evidence/package-build3.tar.gz) and [native SPDX/provenance inventory](evidence/inventory-native6.tar.gz) are retained separately.

The “domestic conformance” document is satire. No certification or registry inclusion is claimed by the measured lab experiments.

[Additional experiments](experiments.md) prove the six-year cycle, filtering gateway, 54.5-fold presentation expansion, bounded reinvocation and PostgreSQL first-write ordering. A separate `11-blogger-scale` run proved 10,000 real watches, HTTP 451 on watch 10,001 and recovery after registration; gateway resources were restored afterward. These results do not waive the independent requirements in BACKLOG.

[Clean-room evidence](evidence/cleanroom.tar.gz) preserves the full provisioning transcript, signed package readiness and the repeated 21/21 demo on three new VMs. The first run exposed port-forward cleanup errors and is also retained. [Load-test and build evidence](evidence/scale-and-build.tar.gz) records the default 10,000-watch threshold with a temporary 2 CPU / 2Gi gateway limit and restoration of its original resources.

[Final validation](evidence/final-validation.tar.gz) proves the real 20/80-minute escalation schedule, collateral denial and amnesty; an actual 31-second admission timeout followed by a successful retry; final node/package readiness and absence of active lab namespaces. Temporary clean-room VMs were removed after evidence preservation.

Continuation after native6 closes specific TSPU (`03-byte-policy`), graph (`04-dependency-graph`), TLS disclosure (`09-key-refusal`) and whitelist (`04-capacity`, `04-schedule`) requirements; archives are linked in [experiments](experiments.md). `03-boundaries` returned exit0 before workshop access failed; its archive still needs copying from the stand. New `05-pigeon-interface` and `08-artifact-chain` are prepared and statically checked, but have not run. These changes do not automatically inherit native6 conformance.
