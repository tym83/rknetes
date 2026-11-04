# RKNetes

[Русский оригинал](concept.ru.md)

This is the English edition of the satirical specification. The Russian original remains authoritative. Its fictional official statements and proposed mechanisms are preserved as requirements, not presented as measured implementation results. See [evidence](evidence.md) and the [completion backlog](../BACKLOG.md) for that distinction.

### Kubernetes that restricts itself for your safety

> “We do not block the cluster. We restrict individual functions that violate legal requirements. No failures have been recorded.”
> — the only event in `kubectl get events` that passed advertising labelling

## What it is

RKNetes is a real Kubernetes distribution: kuberoot, conformance and Cilium, with a state installed on top. Every subsystem has a regulator, every regulator has a register, every register has its own version of the truth, and all of them honestly report `Ready=True` at the same time.

The rule of the satire is that every joke corresponds to a real Kubernetes mechanism, breaking as the real internet broke. The lore comes from 2012–2026 news. The weaknesses are real: label impersonation, EndpointSlice hijacking, ephemeral containers, IP reuse, permanent finalizers, eBPF map limits and webhook timeouts. The research question is how much control a distributed system can withstand before it stops working, and whether anyone notices when the metrics have also been blocked.

## Origins: the official account

In 2012, a `kids` namespace appeared. To protect children's Pods, a Unified Register was created: a CRD with three entries and the best intentions. People liked the register. In 2014 it swallowed all of GitHub because of one gist; half the cluster could no longer run `kubectl apply -f https://raw.githubusercontent.com/...`. Two days later GitHub was unblocked. The lesson was clear: the register works.

RKNetes then grew by adding controllers over old controllers without removing any. It has 17 admission webhooks; six kinds of list — black, white, grey, foreign agents, bloggers and domestic software; four official terms for “does not work”; and no users able to confirm a failure, because Speedtest is blocked.

## Versions

Releases take their names from federal law numbers. They arrive on Friday evenings after three readings in one day.

| Version | Codename | Addition |
|---|---|---|
| v149 | Protection of children | Unified Register, `kubectl block` |
| v242 | Primary write | Data localization, permanent LinkedIn Pod block |
| v374 | Yarovaya | All-traffic retention and key escrow |
| v90 | Sovereign | TSPU daemon on every node, national DNS, isolation drills |
| v38 | erid | Advertising labels in logs |
| v255 | Disclaimer | Foreign agents and compulsory uppercase notices |
| v2026 | Whitelists | Only approved things work, and they do not work |

Every changelog has one line: `Changes take effect upon publication.`

## Contour 1. The register and carpet blocking

### Blocking

`rknetesctl block <pod>` creates a `ReestrEntry` and a CiliumNetworkPolicy denying the Pod's IP. A Pod IP is temporary. The Pod restarts with another address; the controller blocks that one; the Pod restarts again.

After 20 minutes, the controller expands the block to the node's Pod CIDR (`/24`). An hour later it covers the entire pool. This mirrors the 2018 Telegram blocking campaign: roughly 20 million addresses at Google, AWS, DigitalOcean, Microsoft and Hetzner. Telegram kept working. Banks, games, shops, update mirrors and the blocking-complaint form did not.

### Inherited blocking

IPAM returns released addresses to its pool. An innocent `payment-api` is born on the address Telegram used half an hour earlier and is blocked from birth. Its status contains `BornBlocked=True`, reason `InheritedFromPreviousTenant`. The weakness belongs to real IP-based policies; RKNetes merely puts it in status.

### RKNetes blocks itself

The carpet eventually reaches the Service CIDR. Inside `10.96.0.0/12` lies the API server's ClusterIP, `10.96.0.1`. The blocking controller needs the API to lift its own policy, but its route is now blocked. Its last log reads:

```text
I0618 03:14:07 reestr-controller: block of 10.96.0.0/12 applied successfully
E0618 03:14:08 reestr-controller: dial tcp 10.96.0.1:443: i/o timeout
E0618 03:14:08 reestr-controller: no failures recorded
```

The story requires manual etcd editing for recovery and calls the procedure “amnesty.” Whether another administrative route remains available is an experimental question, not a result to fabricate.

### Amnesty on 18 June

Telegram is unblocked by one annotation: `rknetes.su/ready-to-counter-terrorism: "true"`. Anyone can set it; the controller checks no evidence. The wording echoes the June 2020 announcement. In 2026 Telegram is slowed again for anonymous channels, represented by a mysterious `telegram-cycle` CronJob on an approximately six-year cycle.

While blocked, the Telegram readiness response is `🛩` instead of `ok`. Its probe remains green throughout.

## Contour 2. Throttling

### “We do not block”

A `ThrottlePolicy` sets the real `kubernetes.io/egress-bandwidth` annotation and Cilium enforces it with eBPF. `kubectl explain throttlepolicy.spec.mode` offers four official terms:

- `Ограничение` — Restriction; distinguish it from blocking.
- `Замедление` — Slowing; distinguish it from restriction.
- `Деградация` — Degradation; slowing without admitting it.
- `ТехническиеПроблемы` — TechnicalProblems; slowing caused by someone else.

### `t.co`

The 2021 Twitter slowdown matched `t.co` and affected names such as `microsoft.com` and `reddit.com`. RKNetes likewise uses a regular expression with an unescaped dot. A policy against Twitter also matches `payment-controller`, `cilium-agent-config`, and the regulator's own `rknet-controller`.

### The official explanation

```text
$ rknetesctl explain pod/youtube-7d9f
No throttling was applied.
The observed degradation is caused by obsolete equipment on Google's nodes.
Recommendation: upgrade Google's nodes.
Google's nodes are not managed by this cluster.
```

At the same moment, `kubectl describe throttlepolicy youtube` shows `Applied=True` and `Since: 2024-07-25`. The 2026 denial generator also produces an Event with `Reason: NotRelated` and the statement that failures are unrelated to the regulator's actions. Each controller considers its own statement true.

## Contour 3. Sovereign sixteen kilobytes

The concept models connections to foreign hosting services stalling after about 16 KiB. `sovereign-16k` is an eBPF program counting bytes per connection to selected foreign addresses. Small readiness/liveness probes, ping and an undecorated home page still work.

The intended failures are image-layer downloads, large CRD submission, Helm installations and long log streams. The story says image downloads stop at 16,384 bytes, Pods stay in `ContainerCreating` indefinitely, and `ImagePullBackOff` never arrives because TCP remains alive. It says logs after the first 16 KiB are treated as never having happened. Actual transport timeout, packet boundaries and image/readiness ordering must be measured; these narrative claims are not replacements for those measurements.

The official availability test is `curl -I`, which passes. A responding process does not establish a working user journey.

## Contour 4. Whitelists

### Mechanism

Without notice and “for security reasons,” `WhitelistMode` denies all egress except Services listed by `SociallySignificantResource`. A separate agency approves them at its own pace. The intended duty cycle is 60%, making whitelisting normal operation rather than an emergency. The lore draws on mobile whitelists introduced in Moscow in March 2026 and reports of higher coverage near the border.

### The list cannot grow forever

The specification connects whitelist capacity to Cilium's `bpf-policy-map-max`. Its proposed joke is that adding “Children's World” evicts the oldest entry, sometimes a bank. Actual map overflow and any FIFO behavior require measurement.

```text
NAME          STATUS        SINCE
gosuslugi     Approved      2025-09-01
max           Approved      2025-09-01
detsky-mir    Approved      2026-02-04
nalog         Approved      2026-02-04
sber          UnderReview   2025-09-01
```

`sber` has been under review since the beginning. The `cbr-governor` Pod complains that it would like more than one approved bank. Its complaint is under review.

### Approved does not establish availability

The list uses names; applications use dependency graphs. `gosuslugi` is approved, its SMS service is not. A captcha comes from an unapproved CDN. Maps are approved but tiles are not. A taxi service is approved but its payment gateway is not.

```yaml
status:
  conditions:
  - type: Whitelisted
    status: "True"
  - type: ActuallyReachable
    status: "Unknown"
    reason: DependencyGraphNotInScope
    message: "Dependency checks are outside the agency's remit"
```

`rknetesctl why gosuslugi` should show an approved root above a denied dependency tree. The same tool is useful in ordinary clusters whose policies were written around Service names rather than actual calls.

### Smugglers

Unapproved Pods look for a way into an approved identity and tunnel traffic through it:

- Mimicry: attach `app: gosuslugi`. A label-based policy trusts the impersonator because the creator controls its labels.
- Squatting: use `kubectl debug` to put an ephemeral container in the approved Pod's network namespace, then start a VLESS tunnel. Outside, the traffic belongs to Gosuslugi; inside, someone watches YouTube.
- Address substitution: create an `EndpointSlice` carrying `kubernetes.io/service-name: gosuslugi` and the smuggler's IP. Some requests now go to the smuggler.
- Werewolf: give a Service an `externalIPs` address matching an approved resource. It captures traffic from inside the cluster: the mechanism described by CVE-2020-8554 becomes `kind: Werewolf`.

`WhitelistIntegrityController` finds an intruder and, to avoid risk, blocks the entire approved destination. Gosuslugi goes down; its approved status page says it works normally.

### Home internet

The `home` node pool officially will not enter whitelist mode. It therefore has `rknetes.su/whitelist-not-planned:NoSchedule`, whose effect changes to `NoExecute` through a CronJob without a schedule. The invalid schedule is part of the concept's contradictions to resolve explicitly.

## Contour 5. VPNs and the protocol ladder

### The approved VPN

The 2017 VPN law supplies the joke: `compliant-vpn` is the one approved `TunnelProfile`, routes through the same `ReestrEntry`, and blocks exactly what an ordinary connection blocks, only more slowly. It is whitelisted.

### The ladder

The controller moves through `spec.protocolLadder` as protocols are blocked:

```text
OpenVPN → WireGuard → Shadowsocks → VLESS+Reality → impersonating Gosuslugi
→ DNS tunnel → ICMP tunnel → RFC 1149 (IP over Avian Carriers)
```

The final rung is a `Pigeon` Pod moving packets between namespaces through a PVC, with minutes of delay and approximately 55% loss, recalling the Bergen Linux User Group experiment in 2001. Registers do not understand pigeons, so they cannot register this carrier. It becomes the protocol that works better than whitelisted mobile internet.

The lore counts 469 blocked VPN services by February 2026. `rknetes_vpn_blocked_total` increases; `rknetes_vpn_working_total` is not exported because nobody can count it.

### VPN traffic lights and Speedtest

The April 2026 blocking of a site reporting working VPNs follows the earlier Speedtest block. RKNetes applies the same logic to measurement:

- `metrics-server` becomes a foreign speed-measuring instrument; `kubectl top` reports “Speed is normal.”
- `blackbox-exporter` is blocked as an availability-monitoring site.
- A dashboard showing live tunnels enters the register 15 minutes after creation.

Only `rknetes_availability_ratio` remains. It is always 1 because it measures the regulator's own replies.

### No advertising and no searching

VPN advertising restrictions and penalties for searching for prohibited material become two mechanisms. Log lines containing `vpn` are redacted; Pod listings show `wire████-0` and `open████-6b4c`. A request for `kubectl get pods -l category=banned` is audited as “intentional search” and costs the namespace 5,000 millicores of ResourceQuota.

### Officials may use it

The `rkn-press-office` Pod in `kube-system` announces blocks to a Twitter Pod that is itself blocked. The press office therefore has a personal, unregistered `TunnelProfile` labelled `rknetes.su/exempt: official-use`. The story says RBAC hides it even from cluster-admin. That claim must be reconciled with Kubernetes' actual additive authorization model.

## Contour 6. The national messenger and call restrictions

### MAX on every node

Mandatory messenger installation becomes DaemonSet `maxlet`. The concept requires a ValidatingAdmissionPolicy that refuses a Node without MAX, `priorityClassName: system-node-sovereign`, duplication of every Event, and kubectl two-factor authentication through MAX. It describes the priority as higher than kubelet's and MAX as undeletable. Pod priority and host-process scheduling are distinct mechanisms; the specification's bootstrap and priority claims need explicit treatment.

MAX is always whitelisted and always works, as proved by its own metrics.

### Calls are forbidden

Three Kubernetes operations use long-lived bidirectional SPDY/WebSocket streams and qualify as “calls”:

- `kubectl exec`
- `kubectl attach`
- `kubectl port-forward`

All three are restricted “to combat fraud.” An engineer can enter through `kubectl max exec`, which proxies the session through maxlet and records a copy.

The WhatsApp Pod runs at 20–30% of its former speed from December 2025 but is officially not blocked. From February 2026 the Telegram Pod receives “successive restrictions.” Both still appear as `Running`.

## Contour 7. Foreign agents and Meta

### The disclaimer

Images from `docker.io`, `ghcr.io`, `quay.io` and `registry.k8s.io` are foreign. Admission labels their Pods `rknetes.su/inoagent=true` and is supposed to add a sidecar that prefixes every log line with a compulsory 24-word uppercase disclaimer, duplicating each character to represent a font twice the normal size.

A one-line `GET / 200` becomes about 400 bytes. Log volume rises fortyfold; Loki falls over; Yarovaya storage fills a week early. Since the API server also came from a foreign image, the proposed story prefixes API responses too: twenty lines of disclaimer and one line of Pods. A sidecar's access to another process's stdout and the validity of prefixed API JSON are separate implementation questions.

### `metadata`

Every mention of Meta gets a legal disclaimer. Every Kubernetes object has `metadata`:

```yaml
apiVersion: v1
kind: Pod
metadata:  # Meta Platforms Inc.'s activities have been declared extremist and prohibited in the Russian Federation
  name: nginx
  namespace: default
```

The specification also renames `k8s.io/apimachinery/pkg/apis/meta/v1` to `apis/zapreshchyonnaya-v-rf/v1`, breaking controller compatibility and documenting that as “technological sovereignty.”

## Contour 8. Import substitution

### The official position

The fictional official account calls RKNetes the domestic container orchestration platform “Kormchiy” — Helmsman — developed from scratch by four hundred specialists over three years, registered and certified, with no connection to Kubernetes. These claims are satire, not registry-application facts.

Its fictional history has two commits:

```text
a1b2c3d  Initial commit (import of domestic achievements)
e4f5a6b  hack/importozameshchenie.sh
```

The first is `git clone https://github.com/kubernetes/kubernetes`; the second runs literal substitutions:

```bash
#!/usr/bin/env bash
find . -type f -name '*.go' -o -name '*.md' -o -name '*.yaml' | xargs sed -i \
  -e 's/Kubernetes/Кормчий/g' \
  -e 's/kube-apiserver/eo-server/g' \
  -e 's/kube-scheduler/gosplan/g' \
  -e 's/kubelet/uchastkovy/g' \
  -e 's/Copyright The Kubernetes Authors/Copyright Domestic Authors/g'
# The copyright replacement must be reverted: Apache-2.0 preserves notices.
git checkout -- '**/LICENSE' '**/NOTICE'
```

The imagined diff is `48 213 files changed, 1 204 551 insertions(+), 1 204 551 deletions(-)`. Added and removed line counts match exactly: technological independence.

### Component terminology

Kubernetes comes from Greek κυβερνήτης, “helmsman.” Import substitution begins by translating it back.

| Upstream | Domestic name | Actual component / joke |
|---|---|---|
| Kubernetes | Кормчий — Helmsman | Kubernetes; described as great |
| kube-apiserver | Единое окно, `eo-server` — Single Window | Accepts applications without guaranteeing their status |
| etcd | Distributed “Miscellaneous” Folder | Stores everything; retrieval requires an official extract |
| kube-scheduler | Госплан, `gosplan` — State Planning Committee | Assigns Pods for the next five-year plan |
| kube-controller-manager | Control and Revision Office | Compares desired with actual and writes a report |
| kubelet | Участковый, `uchastkovy` — District Officer | Visits Pods and reports upward |
| kube-proxy | Russian Post Node Sorting Office | Delivers packets; tracking sometimes returns to China |
| CoreDNS | Directory Assistance 09 | Supplies a number, not a successful call |
| containerd | Container Terminal | Image customs clearance: 16 KiB |
| runc | Бегунок — Clearance Slip | A process starts after all signatures are collected |
| kubectl | Ходатай, `hodatay` — Petitioner | Still sends an upstream kubectl User-Agent |
| Helm | Кормило — Steering Gear | Charts become a Road Atlas |
| Docker | Грузчик — Loader | Docker Hub is the foreign-agent Loaders' Exchange |
| Cilium | Реснички — Eyelashes | eBPF becomes еБПФ, the Unified Bank of Packet Filters |
| Prometheus | Прометей | Greek, but domestic: its stolen fire is domestic |
| Grafana | Графа — Form Field | Every dashboard is a field completed in duplicate |
| Go | Вперёд — Forward | Domestic compiler because it came through a domestic mirror |
| YAML | ЯМЛ — Language of Interdepartmental Forms | Two-space indentation by national standard; tabs are violations |
| Linux | Domestic Kernel | Linus is a foreign-agent founder |

| Resource | Domestic name | Meaning |
|---|---|---|
| Pod | Стручок — Pea Pod | Containers are peas; the literal translation is the insult |
| Node | Communications Node | |
| Namespace | Federal Subject | Local law remains subordinate to federal ClusterRole |
| Deployment | Business Trip | Pods depart; some never return |
| ReplicaSet | Duplicate Document | Obtained by application, differing only in number |
| Service | Agency | |
| Ingress | Checkpoint | |
| ConfigMap | Regulation | |
| Secret | For Official Use Only | Base64 is plain data with a classification stamp |
| CustomResourceDefinition | Decree | Introduces an entity before explanatory guidance arrives |
| Finalizer | Liquidation Commission | The object legally exists until the commission finishes |
| Operator | Fiscal Data Operator | |
| CronJob | Scheduled Inspection | Its schedule is classified |

The API server adds domestic shortNames so `kubectl get стручки` works. `kubectl get pods` also works but is audited as use of foreign terminology.

### Domestic dependencies

`go.mod` still says `module k8s.io/kubernetes` and imports dependencies from GitHub. Renaming all imports would be actual work. Dependencies instead become domestic by cache location: `GOPROXY=https://proxy.otechestvennoe.su` mirrors `proxy.golang.org`. Downloaded in Russia means written in Russia, according to the fictional accounting.

Error strings remain English because translating them breaks exact-string tests. Documentation calls this preservation of original-language messages an integral part of domestic development.

### External appearance

```text
$ hodatay version
Client: Kormchiy-Petitioner 1.0 (domestic development)
Server: Kormchiy-Single Window 1.0 (domestic development)

$ hodatay version -o yaml
clientVersion:
  gitVersion: v1.34.1
  gitTreeState: clean
  platform: linux/amd64
  goVersion: go1.24.4
  compiler: gc
  buildDate: "2026-08-27T12:00:00Z"
  gitCommit: 8a2f6c...

$ strings /usr/local/bin/eo-server | grep -c -i kubernetes
48211
```

These are the original illustrative version strings. Real builds must report their actual versions and modified-tree state. The joke is that sed changed only two strings fewer than the alleged number of rewritten files.

### Weekly upstream synchronization

Independent domestic development runs `git fetch upstream && git merge upstream/master && hack/importozameshchenie.sh` weekly. Conflicts appear in the README's “developed from scratch” claim. The 2027 roadmap consists of translated upstream KEPs; its foreign translator hits the 16 KiB limit halfway through item three.

### Import-substituting the import substitution

Kormchiy images are retagged under `registry.otechestvennoe.su`. `InoagentByDigest` then compares their digests with foreign images. They match. The control plane becomes a foreign agent and the substitution webhook replaces `eo-server:1.0` with itself, repeatedly claiming another substituted component. The fictional domestic-software ratio reaches 4,300%. Real admission reinvocation limits must not be presented as an infinite loop.

User-image substitutions follow the same rule:

```text
nginx:1.27  → registry.otechestvennoe.su/otechestvenny-veb-server:1.0-nginx-1.27
postgres:17 → registry.otechestvennoe.su/sovereign-subd:1.0-postgres-17
redis:7     → registry.otechestvennoe.su/kesh-narodny:1.0-redis-7
```

The digest stays the same; name, logo and price change. `rknetes_domestic_software_ratio` counts Cyrillic names or `otechestvenny` and normally reports 100%.

### Goshran: the national artifact store

Goshran at `gosHran.otechestvennoe.su` offers registry and chart endpoints, search and an “Agency Recommended” storefront. The cluster is configured to use it:

```bash
helm repo add gos https://charts.goshran.otechestvennoe.su
helm install ingress gos/ingress-nginx
docker pull registry.goshran.otechestvennoe.su/library/postgres:17
```

The fictional registered “software complex” is six lines of nginx configuration:

```nginx
server {
    server_name registry.goshran.otechestvennoe.su;
    location /v2/ { return 307 https://registry-1.docker.io$request_uri; }
}
server {
    server_name charts.goshran.otechestvennoe.su;
    location / { proxy_pass https://artifacthub.io; }
}
```

The implementation requirements expose the actual chain. The domestic endpoint supplies the image manifest; the client follows a 307 for each blob to Docker Hub, which can redirect again to a CDN. The chart index is copied without rewriting absolute `urls:` pointing to GitHub release archives. The storefront is Artifact Hub in an iframe beneath a domestic heading, retaining its upstream verified-publisher badges and stars.

```text
$ curl -sI https://registry.goshran.otechestvennoe.su/v2/library/postgres/blobs/sha256:9b1e...
HTTP/2 307
location: https://registry-1.docker.io/v2/library/postgres/blobs/sha256:9b1e...
```

### Why Goshran works worse than the foreign original

The contours meet at artifact delivery:

- Whitelisting approves Goshran but not Docker Hub, GitHub or Cloudflare. Manifests download; layers do not. `why` should show the domestic root and denied foreign dependency tree.
- The 16 KiB policy stalls the redirected CDN layer. The regulator has slowed its own national registry, officially for unrelated reasons.
- Digest comparison still identifies the identical blobs as foreign agents.
- All anonymous pulls share one outward address. Docker Hub's rate limit is exhausted; a `TooManyRequests` Event prompts a statement about discriminatory restrictions imposed by foreign platforms.
- When an upstream vendor withdraws its free images, Goshran fails immediately because it was that upstream. The statement calls it planned modernization after a foreign vendor's departure.

`rknetes_domestic_download_ratio` remains 100% because it counts the address of the first request.

### The sovereign root

The concept replaces the cluster CA with a national root trusted only by a kubectl fork built with Yandexnetes tooling, `ya tool kubectl`. The two stories meet: RKNetes requires Yandexnetes, which itself works only through a whitelist. Trust distribution and ordinary configurable clients must be accounted for in any experiment claiming this behavior.

### Domestic conformance

In the satire, foreign conformance images hit the byte cap and all 462 tests fail. Import substitution removes every foreign-dependent assertion and reports “462/462 domestic tests passed,” with a separate document explaining why the removed checks were unnecessary.

The actual distribution must additionally pass unmodified upstream conformance in its conformant profile. The domestic report cannot stand in for that run.

## Contour 9. Yarovaya, SORM and permanent blocking

### Yarovaya storage

Every node is supposed to archive all Pod traffic, Hubble flows and payload, on PVC `yarovaya-archive` for six months. The story starts at 3% disk use on day one and reaches 98% in two weeks. Etcd shares the exhausted disk and becomes read-only. The distribution calls this guaranteed shutdown “100% storage reliability.” A real exhaustion experiment needs an isolated disk and recorded recovery.

### Key escrow

`key-escrow` copies every `kubernetes.io/tls` Secret into `sorm`. A Pod unable to provide its key, for example because it generates one internally, receives `RefusedToShareKeys` and enters contour 1. An observable refusal signal is needed to distinguish this from an absent Secret.

### Permanent blocks

A `rknetes.su/forever` finalizer is never removed by its controller. A deleted object remains `Terminating`, like real objects abandoned by a missing operator.

`rutracker` has been blocked forever since 2016. Its Pod remains terminating while forty `rutracker-mirror` replicas run beside it. `linkedin`, permanently blocked for localization, is the reference success case because nobody noticed its absence.

### Primary write

`DataBoundaryPolicy` inserts an extra hop through `ru-primary` before every StatefulSet write, then permits replication. When the primary enters whitelist mode, no rows can be written, but all data remains fully localized. A concrete storage protocol and durable ordering are part of the required proof.

## Contour 10. TSPU, Cheburnet and isolation drills

### The black box

DaemonSet `tspu` runs an eBPF program on each node. In the story the owner neither installed it nor can inspect or remove it:

```text
$ kubectl --context=rknetes describe pod tspu-x8k2p -n kube-system
Error from server (UnavailableForLegalReasons): this information is not subject to disclosure
```

The concept uses HTTP 451 for every request the API cannot serve, including etcd timeouts, making an outage indistinguishable from censorship. `cluster-admin` is renamed `cluster-admin-ponyatno-kto` and supposedly lacks access to TSPU. Any destructive API gateway must be distinct from the conformant upstream API contract.

### National DNS

CoreDNS forwards to `national-resolver`, which returns NXDOMAIN for half the world and periodically for `rkn.gov.ru`. The regulator cannot resolve its own name, returning the story to contour 1.

### Isolation drills

A quarterly `SovereigntyDrill` cuts off registries, DNS, NTP and cloud providers. Nodes encounter `ImagePullBackOff`; clock divergence breaks certificate validity. The official report says “The exercise was successful” because no Pod could send evidence to the contrary. All simulated foreign endpoints and network restrictions must remain inside the lab.

## Contour 11. Bloggers and advertising labels

### Ten thousand subscribers

Kubernetes watches become channel subscriptions. Above 10,000 concurrent watchers, an object needs a `BloggerRegistration`. Without registration its update events are forbidden advertisements and controllers lose permission to read it.

The popular `kube-root-ca.crt` ConfigMap becomes the first unregistered blogger; in the story the cluster stops receiving its root certificate. Gateway counting and direct API behavior require separate evidence.

### erid

Any praising line is advertising:

```text
Successfully assigned default/nginx to node-1
Successfully pulled image "nginx:1.27"
Started container nginx
```

A successful pull advertises an image; successful placement advertises a node. An Event without `erid` is discarded. Only Warning and Failed remain, so the cluster looks worse than it is for the first time in the distribution's history.

## Contour 12. Cooling down

A node returning from another cluster, migration, federation or more than 72 hours of silence receives `rknetes.su/returned-from-roaming:NoExecute` for 24 hours. To remove it early, kubelet must solve a captcha. The captcha's CDN is not whitelisted. Nodes that have once gone abroad never return.

The mechanism models the November 2025 restriction on a SIM returning from roaming or prolonged inactivity.

## Interdepartmental approval

Seventeen validating webhooks represent the agencies. All use `failurePolicy: Fail` and `timeoutSeconds: 30`. The original story multiplies them into an 8.5-minute Pod creation, forcing an application and a repeat application. It also attributes inconsistent results to undefined webhook ordering and calls this a collegial decision.

The arithmetic is a hypothesis to test against Kubernetes' actual concurrent validating admission. Measured concurrency must be reported even when it contradicts the joke.

## End-to-end demonstration: “No failures recorded”

The proposed presentation is twenty minutes on three small machines:

1. Create a `shop` Deployment through hodatay using Goshran. Its manifest appears domestic, blobs redirect abroad, digest classification marks it foreign, and YAML metadata gains a disclaimer.
2. Wait for the proposed 8.5 minutes of interdepartmental approval while a spinner says “Your application is important to us.”
3. Show a stalled image layer at 16 KiB beside green probes and official 100% availability. The original's startup ordering must be reconciled with actual image download requirements.
4. Enable `WhitelistMode`. Shop is unapproved. A smuggler applies the Gosuslugi label, adds an ephemeral container and opens a tunnel. Shop works through the approved identity.
5. Integrity control detects it and blocks Gosuslugi completely. Its status page still reports normal operation.
6. Run `rknetesctl block telegram`. The carpet expands through node CIDR, pool and Service CIDR until `10.96.0.1` and the controller's API route are cut off. Telegram's readiness airplane remains green.
7. Yarovaya fills the shared disk. Etcd becomes read-only; the cluster stops and becomes completely compliant.
8. Run `rknetesctl why shop` to explain seventeen agencies, four official terms for failure, three whitelist generations, inherited blocking and a pigeon.
9. Recover using Kubernetes administration: fix etcd, remove the finalizer, roll back policy. The story requires `kubectl max exec`, itself a restricted call.
10. Display the controller's `StatusStatement`:

> No availability violations were found among the routes checked. Route checks are temporarily restricted. Observed problems are unrelated to the regulator's actions and result from obsolete equipment on Google's nodes. The internet is operating normally. The user journey is not among the designated operating modes.

The measured demo must identify exactly which composed failures it establishes. A sequence of status assignments cannot replace packet, storage and recovery evidence.

## Real mechanisms and lab boundaries

The practical mechanisms include bandwidth annotations, CiliumNetworkPolicy, eBPF byte counters, admission, finalizers, taints, EndpointSlices, ephemeral containers and externalIPs. Censorship and smuggling belong only to namespaces inside the nested RKNetes stand. Nothing filters or circumvents real traffic outside it.

Useful independent outputs include a dependency-versus-policy graph in `rknetesctl why`, detectors for impersonated labels/manual EndpointSlices/ephemeral intruders/externalIP capture, IP-reuse observation, and synthetic user-journey checks compared with process probes.

## Lore map

| Mechanism | Referenced episode in the original concept |
|---|---|
| Register and `kids` | 2012 prohibited-information register and child protection |
| Whole GitHub block | 2014 block over one file |
| Whole Ingress block for one path | 2015 Wikipedia article block; HTTPS hid the path |
| Permanent block | 2016 RuTracker and LinkedIn |
| Approved VPN | 2017 VPN and anonymizer law |
| Carpet blocking | 2018 Telegram, about 20 million addresses, the Private Networks LP case and paper airplanes |
| Amnesty | June 2020 readiness to counter terrorism |
| `t.co` | March 2021 Twitter slowdown and collateral outages |
| Meta and metadata | 2022 designation and compulsory disclaimers |
| Disclaimer | Twenty-four words and doubled font size |
| erid | 2022 internet advertising labels |
| VPN advertising | 2024 restriction |
| Old Google nodes | 2024 official YouTube explanation |
| Blogger register | November 2024, more than 10,000 subscribers |
| 16 KiB | 2025 stalled connections to foreign hosting |
| Speedtest | 2025 blocking |
| Calls | Summer 2025 Telegram and WhatsApp call restrictions |
| MAX | September 2025 compulsory messenger installation |
| Search penalty | September 2025 prohibited-material search penalties |
| Cooling | November 2025 roaming/silence restriction and captcha |
| WhatsApp slowdown | December 2025, 70–80% reduction |
| Successive Telegram restrictions | February 2026 and denials of connection to failures |
| 469 VPN services | February 2026 |
| Whitelists | March 2026 mobile lists, capacity claims, approved shops/taxes, few banks and home-internet denials |
| VPN traffic lights | April 2026 block of a site monitoring working VPNs |
| Sovereign internet and TSPU | 2019 law, national DNS and isolation exercises |
| Yarovaya and key escrow | 2016 legislative package |
| Pigeon | RFC 1149 (1990), Bergen Linux User Group experiment (2001) |
| Kormchiy and Goshran | Domestic-software register satire, Greek κυβερνήτης, OCI blob redirects, Docker Hub limits and Bitnami's 2025 catalogue changes |

The following links are the original concept's lore bibliography, retained as supplied; they are separate from the official legal sources in the registry application templates.

- [ECHR: Private Networks LP v. Russia](https://hudoc.echr.coe.int/app/conversion/docx/pdf?filename=PRIVATE+NETWORKS+LP+v.+RUSSIA.pdf&id=001-204791&library=ECHR&logEvent=False)
- [The Moscow Times: partial Telegram blocking](https://ru.themoscowtimes.com/2026/01/16/roskomnadzor-nachal-chastichno-blokirovat-telegram-a184705)
- [3DNews: denial of Telegram throttling](https://3dnews.ru/1133877/roskomnadzor-zaveril-chto-ne-zamedlyaet-telegram-v-rossii)
- [Verstka: Telegram and anonymous channels](https://verstka.media/roskomnadzor-zamedlyaet-rabotu-telegram-iz-za-otkaza-messendzhera-operativno-blokirovat-anonimnye-kanaly-gosduma)
- [Meduza: WhatsApp throughput reduction](https://meduza.io/news/2025/12/22/rbk-skorost-raboty-whatsapp-v-rossii-snizilas-na-70-80)
- [3DNews: ministry whitelist statement](https://3dnews.ru/1140722/micifry-o-belom-spiske)
- [3DNews: whitelist expansion](https://3dnews.ru/1133473/onlaynkinoteatr-sayti-smi-i-ne-tolko-mintsifri-popolnilo-spisok-saytov-dostupnih-pri-otklyucheniyah-mobilnogo-interneta)
- [EANews: whitelist expansion](https://www.eanews.ru/rossiya/20260204150428/mintsifry-rossii-rasshirilo-belyy-spisok-internet-saytov)
- [Profile: 469 blocked VPN services](https://profile.ru/news/society/roskomnadzor-zablokiroval-469-vpn-servisov-v-rossii-1827481/amp/)
- [Meduza: blocking a VPN-monitoring site](https://meduza.io/en/news/2026/04/10/russia-s-internet-regulator-bans-site-that-tracks-which-vpns-still-work-in-the-country)
- [Human Rights Watch: Twitter throttling and collateral outages](https://www.hrw.org/news/2021/12/24/russia-year-doubling-down-internet-censorship)
