# 2026-04-21 — Integrate prior step-0~7 plan into a layered IaC structure

## Context

Before adopting a foundation-style Terraform structure, a detailed step-0 through step-7 guide already existed at `.context/attachments/`. It covered Hetzner VM provisioning, Cloudflare Tunnel, Tailscale, Ansible for Docker + services (PostgreSQL/Traefik/Authentik/Prometheus/…), and a recovery test. The directory shape there was a flat `terraform/<csp>/` + `ansible/` split with local tfstate.

Then a more structured reference Terraform foundation pattern (2-layer `stacks/code` + `live/data`, per-CSP modules, null-label naming, data-source cross-stack refs, Justfile-driven ops) caught our attention. The question: what do we do with the prior guide?

## Alternatives

- **A) Replace**: adopt the new structure wholesale, discard the step guide.
- **B) Parallel**: keep the step guide's flat structure as-is; treat the new structure only as future reference.
- **C) Integrate**: re-home the step guide's content (Terraform resource definitions, Ansible roles, Cloudflare Tunnel pattern, network split, recovery test) under the new `stacks/ live/ modules/` layout.

## Decision

**C — Integrate.**

## Reasoning

- The step guide embodies non-trivial design work — specific SKU picks, Ansible role conventions, Cloudflare Tunnel ingress patterns, a recovery drill. Discarding it (A) wastes that work.
- The new structural pattern provides *discipline* (code/data separation, path-to-tool mapping, extensibility) but not *workload choices*. The two layers are orthogonal, so they compose rather than conflict.
- (B) leaves the repo structurally weaker and gives up the extensibility benefit of the new pattern.
- Concretely, things like Cloudflare Tunnel and the Ansible role split *should* live somewhere — putting them inside `stacks/homelab/hetzner/network/cf-tunnel/` and `ansible/roles/<service>/` makes each piece addressable and evolvable.

## Consequences

- Plan Phase count grew from 3 to 10 to accommodate the richer scope.
- `ansible/` becomes a first-class top-level tree, not a peer-of-module afterthought.
- A dedicated ADR (004) documents the Cloudflare Tunnel + Tailscale network split.
- The recovery test becomes its own phase (9), promoting DR from "nice to have" to "gate before we call Phase 1–8 done".

## Scope

Entire repo shape. Every later decision (where does a stack live, how do services get secrets, how do we re-deploy) inherits from this choice.
