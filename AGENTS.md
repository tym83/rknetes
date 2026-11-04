# RKNetes — brief for the implementing agent

You are building RKNetes end to end: implementation, stand, tests, conformance,
and a registry-application package. Work autonomously. Ask the owner only when a
decision is genuinely theirs; write such questions into `SESSION_LOG.md` under
"Open questions" and keep working on everything else.

## What RKNetes is

A real, conformant Kubernetes distribution satirising Roskomnadzor and Russian
internet regulation. The full concept — twelve "contours" (agencies), every
joke, every command and status message — is in `docs/concept.ru.md` (Russian).
That document is the specification. Read all of it before writing code.

The rule that makes the project work: **every joke is a real Kubernetes
mechanism, and it breaks exactly the way the real internet broke.** IP-based
policies vs pod IP reuse, label-selector spoofing, hand-made EndpointSlices,
ephemeral containers in someone else's pod, CVE-2020-8554 externalIPs,
finalizers that never go away, eBPF map limits, admission webhook timeouts,
SPDY/WebSocket streams (exec/attach/port-forward), watch counts, OCI blob
redirects, Helm `index.yaml` absolute URLs. If a mechanism in the concept does
not actually work on the stand, it is not done.

This series treats such distributions as research into how far Kubernetes
bends (see `~/projects/gachinetes` and `~/projects/yandexnetes` for the tone,
layout and level of rigour expected). Nothing in the concept may end up in the
docs as "not implemented": implement it, or record it in `BACKLOG.md` with the
reason and raise it as an open question.

## Base and layout

- Base distribution: kuberoot (`~/projects/kuberoot`), the same way Gachinetes
  uses it (`~/projects/gachinetes`: `distro/kuberoot`, `cmd/`, `pkg/`,
  `deploy/`, `docs/design.md`). CNI: Cilium. Most components should also
  install as add-ons on any cluster.
- Go for controllers, webhooks and CLIs. API group: `rknetes.su`.
- CLIs: `rknetesctl` (block, why, explain, publication inspect, …) and the
  import-substituted kubectl `hodatay`.
- The "Кормчий" import substitution (contour 8) is literal: a script that
  rebrands an upstream build with `sed`, `hodatay version` vs `-o yaml`,
  `kubectl get стручки`, the Госхран registry/chart proxy that is a 307 to
  Docker Hub and a copy of upstream `index.yaml`. Build it for real.

## Order of work

0. `SESSION_LOG.md` first (see below), then the stand.
1. Skeleton: repo layout, CRDs, `rknetesctl`, build and deploy scripts.
2. Contours one by one, each with an automated e2e test in `hack/e2e/` that
   proves the mechanism on the stand (e.g. a pod born on a blocked IP really
   has `BornBlocked=True`; the carpet block really cuts the controller off
   `10.96.0.1`; a whitelisted Service really goes down when a smuggler adds
   an EndpointSlice; `kubectl exec` really is refused as a "call").
3. The end-to-end demo from the concept ("Сбоев не зафиксировано") as one
   reproducible script.
4. Conformance: upstream Sonobuoy/hydrophone run, **462/462**, with RKNetes
   installed in a profile that keeps the cluster conformant. Record the exact
   numbers and artefacts. The "отечественный conformance" joke is a separate
   document, not a substitute for the real run.
5. Registry package: `docs/registry/` — a template package for an application
   to the Russian Unified Register of Domestic Software (Government Decree
   No. 1236 and the current rules — research official sources and cite them).
   Placeholders for the rights holder; describe the product honestly as a
   modification of Apache-2.0 Kubernetes. Apache-2.0 licence. Do not submit
   anything anywhere.

## Stand

- Workshop cluster: `KUBECONFIG=~/workshop.txt`, context `admin@workshop`.
  Pass `--context admin@workshop` explicitly on every kubectl call.
- Create exactly one Tenant `rknetes` in `tenant-root` (pattern:
  `~/projects/yandexnetes/hack/workshop/tenant.yaml`; quota up to 40 CPU /
  64Gi). Everything else lives inside that tenant (VMs, builders, nested
  clusters).
- Do not modify or delete anything outside the `rknetes` tenant: not the other
  tenants (`workshop01`–`workshop70`, `yanetes`, …), not cluster-wide objects,
  not flux/cozystack components. If you think you need to, stop and write an
  open question.
- Heavy builds run in the cluster, not on this laptop.
- All "censorship" and "smuggling" happens inside the lab between namespaces.
  Nothing may filter, throttle or circumvent real traffic outside the stand.
- Never write credentials or kubeconfigs into git.

## Git

- Local repo `~/projects/rknetes`, branch `feat/skeleton`. Never commit to `main`.
- Small commits after each logical step, Conventional Commits, English.
- Every commit: `git commit -s` and exactly one trailer `Assisted-by: LLM`.
  No other attribution anywhere (no model or tool names in code, docs, commits).
- Do not push, do not create GitHub repositories, do not publish anything.

## Docs

English is primary, every document has a `.ru.md` copy. Code and code comments
in English. Living prose, no hedging, no "we didn't get to this".

## SESSION_LOG.md (mandatory, gitignored)

Create it before the first real action and update it after every meaningful
step (resource created, build deployed, test result, bug + workaround,
decision). Structure:

```
# Session log — rknetes (started YYYY-MM-DD)
## Goal
## Current state      (overwritten: stand names/IPs, contexts, what works, what doesn't)
## Next step          (one concrete action)
## Open questions
## Journal            (append-only, "### HH:MM — what happened")
```

The session can die at any moment; whoever resumes must be able to continue
from this file alone.

## When you stop

Finish with a short report: which contours work (with their e2e tests), the
demo, conformance numbers, the registry package, open questions, next step.
