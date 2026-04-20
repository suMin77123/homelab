# 2026-04-21 — Two-layer `stacks/` + `live/` structure over flat `terraform/<csp>/`

## Context

The prior plan had `terraform/hetzner/`, `terraform/cloudflare/`, `terraform/aws/` — a flat per-provider layout. It works for today (one env, few clouds) but has limits:

- Environment dimension has no home. Adding a `staging` means new top-level dirs or per-file switches.
- Code and values live side-by-side. Secrets in tfvars are one misconfigured `.gitignore` away from being committed.
- Automation has to hard-code per-stack paths.

Three shapes considered:

## Alternatives

- **A) Keep flat `terraform/<csp>/`** — one dir per provider, values alongside code.
- **B) Two-layer `stacks/<env>/<csp>/<group>/<proj>/` (code) mirrored by `live/<env>/<csp>/<group>/<proj>/` (data)** — code/data split, paths carry env + csp.
- **C) CSP-level folder, flat below** (e.g., `terraform/hetzner/<group>/<proj>/`) — introduces grouping but not env or code/data separation.

## Decision

**B — Two-layer `stacks/` + `live/`.**

## Reasoning

- **Path-derived automation**: `just <verb> <group> <proj>` resolves `stacks/$ENV/$CSP/<group>/<proj>/` and `live/$ENV/$CSP/<group>/<proj>/` purely from `.env`. No per-stack Justfile entries, no maintenance cost as stacks multiply.
- **Code/data separation is load-bearing** for this repo: tfvars are gitignored until Phase 7 (secrets concern); backend.hcl is committed; both live under `live/`. Keeping them in the same tree as `.tf` would make gitignore patterns brittle.
- **Env is a first-class axis**. Even though today `<env>` is only `homelab`, the path guarantees that adding `staging` later is a directory copy, not a refactor.
- (A) is fine for single-env repos but bakes in assumptions that wouldn't survive the first "let me spin up a test env" moment.
- (C) addresses grouping but not code/data and not env — it's a half-measure. If we're restructuring anyway, the full two-layer shape costs the same and gets more of the benefit.

## Consequences

- Every stack's `backend.tf` is **empty** (`terraform { backend "s3" {} }`). The real config lives in `live/.../backend.hcl` and is injected at `tofu init` via `-backend-config=…`. This is what makes the per-stack-key-prefix state bucket pattern work.
- Every stack imports a shared `context.tf` + `cloudposse/label/null` (see [ADR-002](../adr/002-naming-convention.md)). Naming derives from the four label vars set in tfvars.
- Cross-stack data flow uses provider data sources, not `terraform_remote_state` (see [ADR-003](../adr/003-cross-stack-references.md)). Stacks can be independently moved or re-backed.
- Migrating a single stack (e.g., `stacks/homelab/hetzner/network/server/` → `stacks/homelab/aws/network/server/`) is a copy + provider swap; no change to the surrounding pattern.

## Scope

Root repo layout. All future stacks inherit this shape.
