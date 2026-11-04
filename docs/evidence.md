# Measured evidence

[Русская версия](evidence.ru.md)

The native three-node stand completed `demo-native-2` on 2026-11-04: **21 checks passed, zero failed**. Each script's log and exit code is in [the preserved demo archive](evidence/demo-native-2.tar.gz). These results prove the mechanisms named below, not every narrative detail of a contour. [BACKLOG](../BACKLOG.md) identifies the remaining requirements.

| Contour | Automated proof in `hack/e2e/` | Observed behavior |
|---|---|---|
| 1 | `01-reestr.sh`, `01-self-block.sh`, `01-escalation.sh` | Real IP deny, Cilium IPAM reuse, BornBlocked, annotation amnesty; controller's API route times out and is recovered out of band; timed IP, node and pool stages cause measured collateral denial. |
| 2 | `02-throttle.sh` | Unescaped `t.co` matches payment-controller and Cilium reduces measured cross-node throughput. |
| 3 | `03-sovereign-16k.sh` | Exactly 16,384 payload bytes arrive; subsequent reads time out while readiness still responds. |
| 4 | `04-whitelist.sh`, `04-ephemeral.sh`, `04-werewolf.sh`, `04-observe.sh` | Labels allow traffic, manual EndpointSlice and ephemeral-container intrusion trigger whole-destination denial; Service externalIPs captures a lab address; why reads actual Hubble policy-drop verdicts. |
| 5 | `05-pigeon.sh` | 100 valid IPv4/UDP datagrams traverse shared storage under network deny; 47 arrive, 53 are lost, after the full 180-second delay. |
| 6 | `06-calls.sh`, `06-max.sh` | Direct exec is refused; authenticated `kubectl max exec` succeeds and upgraded-stream bytes are archived. |
| 7 | `07-origin.sh` | A domestic reference with the same supplied foreign image digest receives the foreign-agent label in server admission. |
| 8 | `08-import.sh`, `08-goshran.sh` | Unmodified kubectl resolves стручки; native version is v1.37.1/dirty; real HTTP blob redirect and byte-identical Helm index. |
| 9 | `09-escrow-forever.sh` | TLS Secret bytes match escrow exactly; a real deleted Pod remains Terminating behind its finalizer. |
| 10 | `10-drill.sh` | Selected foreign lab traffic stops while the official drill condition reports success. |
| 11 | `11-erid.sh`, `11-blogger.sh` | Unmarked successful Event is rejected; four simultaneous watches exceed a test threshold of three, receive 451, and resume after registration. |
| 12 | `12-cooling.sh` | Actual NoExecute eviction and removal of the taint after captcha completion is recorded. |
| Agencies | `17-agencies.sh` | Delayed validating hooks run concurrently, contradicting the proposed 17-fold sequential delay. |

After all checks, the controller generated the final StatusStatement and it was read from the API. The detached remote run completed and all 21 saved exit-code files were independently checked. The earlier 19-case run is retained in the first evidence archive. Cleanup removed the explicitly labelled lab fixtures and released their IPAM reservations before conformance.

Native bundle: `kuberoot-0.1.0-dev-amd64.tar`, SHA256 `8f8d1dfa09b3356ec9fa9b10a4d05b69384b571bb3d1d7eb85c9dce933ac7ef8`. The bundle is signed; private signing material is excluded. Kubernetes is v1.37.1, upstream commit `f78e722310e50bcaca9276be22276d9e91d91308`, modified tree. Cilium is 1.20.4; the kernel is 6.18.55-kuberoot and containerd 2.4.1.

Conformance run4 completed on 2026-11-04: **462/462 passed, zero failed and zero skipped conformance specs**, runner exit code 0. The official `registry.k8s.io/conformance:v1.37.1` image ran unchanged across eight Ginkgo processes. [The full archive](evidence/conformance-run4.tar.gz) contains JUnit, logs, image IDs, installed component versions and the parsed summary. Its 483 successful XML records include 21 lifecycle hooks; those hooks are excluded from the reported 462. This result applies to native bundle5 and package build2. Run1 failed credential selection before creating resources. Run2 was interrupted to fix numeric parallelism. Run3 was interrupted when the upstream NoExecute test evicted its runner; it also exposed a HostPort failure. Portmap chaining fixed HostPort (the focused upstream regression passed 1/1); the launcher now tolerates suite taints. No official tests were altered or skipped.

The installed `kuberoot-rknetes` 0.1.0 build 2 package is Ready; its [signed artifacts and status](evidence/package.tar.gz) and [native SPDX/provenance inventory](evidence/release-inventory.tar.gz) are retained separately.

The “domestic conformance” document is satire. No certification or registry inclusion is claimed by the measured lab experiments.
