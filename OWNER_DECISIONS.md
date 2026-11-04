# Owner decisions

## 2026-11-04 — concept vs measured Kubernetes semantics

Keep the joke everywhere. Do not rewrite the concept to drop a mechanism;
implement each one through an honest, working replacement and describe the
replacement in the design docs as part of the joke (the limit Kubernetes puts
on the regulator is itself funny). Measured behaviour goes into evidence.

| Item | Decision |
|---|---|
| B02 Telegram cycle | Annual CronJob with a year guard (fires only every sixth year); readiness `🛩` tied to real registry state. |
| B06 Whitelist eviction | Measure what Cilium really does when the policy map overflows and record it. Model the "Детский мир evicts the bank" eviction with an admission queue on top, sized from the measured limit. Never fake kernel eviction in status. |
| B12 Invisible official tunnel | Separate filtering API gateway (aggregated API or proxy) through which the "public" sees TunnelProfiles; the official one is hidden there. The real API stays observable — that is the punchline. |
| B13 MAX on every node | Node enrollment via kuberoot JoinTicket requiring MAX enrollment; define and test fail-open/fail-closed. Second factor for kubectl through the MAX gateway. Replace the priority claim with what is actually enforceable. |
| B14 Inoagent banner | Log/presentation proxy (or cooperative process wrapper) that adds the 24-word banner doubled; measure byte amplification and storage effect, put the numbers in evidence. API output gets the banner only through the presentation path, never by corrupting JSON. |
| B15 `metav1` rename, infinite substitution | Separate deliberately incompatible "sovereign build" that renames the package and shows what breaks. The substitution loop: show that admission reinvocation is bounded (one reinvocation) — the loop is stopped by Kubernetes law; the report still counts every pass as "a substituted component". |
| B21 First-write hop | Concrete Postgres adapter: ordered durable primary write on the "domestic" node, then replication; prove the blocked-primary failure. |
| B22 TSPU and 451 | Explicit opt-in destructive gateway profile returning 451 for everything; prove admin-visible failure and recovery. Default profile stays conformant. |
| B23 National DNS, drills | Lab resolver, controlled clocks (faketime/NTP fixture) and registry fixtures, inside the tenant only; bounded certificate-expiry experiment. |

## 2026-11-04 — registry package

Rights holder stays as placeholders: the package is a template any Russian
company can fill in. If official sources keep timing out, cite secondary
sources with dates and mark the primary text to be verified before filing.
