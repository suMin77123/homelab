# 2026-04-22 — Cloudflare R2 as Terraform state backend

## Context

Phase 2 started with Hetzner Object Storage as the state backend (matching the "state storage lives in the same cloud as the infra it tracks" principle from the reference IaC pattern we're borrowing from). During operator prep, the pricing became concrete: Hetzner Object Storage has a base fee of **€6.49/month** per project regardless of usage.

The homelab's monthly infra budget anchor is ~€3.49 (one Hetzner CX22). A state backend costing almost **2× the infra it tracks** is a shape-mismatch no sane cost model tolerates, and the reference repo never faced this trade-off because state cost was a rounding error against their actual spend.

So: keep the *principle* (remote backend, backend as independent resource, backend co-located with operator's vendor stack), drop the specific vendor choice.

## Alternatives

- **A) Hetzner Object Storage** — original Phase 2 direction. Matches reference repo's "same-cloud state storage" pattern exactly. €6.49/mo base.
- **B) Cloudflare R2** — S3-compatible, 10 GB storage + 1 M Class-A ops/month free tier, no egress fees. Cloudflare is already a vendor in the stack (Phase 4 adds CF Tunnel + DNS) — not a new vendor, just a new usage.
- **C) Local state** (`terraform.tfstate` on laptop) — simplest and free but breaks the "remote backend" principle; the source-of-truth lives on one machine with no durability or multi-device story.
- **D) AWS S3 free tier** — 5 GB for 12 months, then paid. Adds a vendor we otherwise don't touch before Phase 10.

## Decision

**(B) Cloudflare R2.**

## Reasoning

- **Reference-principle fit.** "Remote backend, independent resource, operator's vendor stack." R2 checks all three. A is the only one that matches on *literal cloud*, but "literal cloud" wasn't the principle — it was "don't pay cross-vendor overhead", and B avoids that overhead the same way A would.
- **Cost shape.** Free at homelab scale (well under 10 GB + 1 M ops/month). Over any reasonable time horizon the expected R2 spend is €0. Hetzner Object Storage is €78/year minimum even if we never write a byte.
- **Vendor count doesn't grow.** Cloudflare is already planned for DNS + Tunnel in Phase 4. Using it for R2 is a new *usage* of an existing relationship, not a new vendor to configure, monitor, or pay.
- **API surface is the same.** R2 is S3-compatible. `backend "s3"` with `use_path_style = true`, a custom endpoint, and `region = "auto"` — same shape we already had for Hetzner. Terraform code barely changes.
- **(C) gives up too much.** Losing remote backend would undo one of the few real "this is operated infrastructure, not a local script collection" disciplines the repo has. Not worth it for €6.49.
- **(D) has a 12-month clock** — would need a second migration later. Not worth the re-do.

## Consequences

- Bootstrap script moves from `hack/hetzner/create-state-bucket.sh` to `hack/cloudflare/create-state-bucket.sh`. The previous location reflected "state backend is a Hetzner thing"; the new location reflects "state backend is a Cloudflare thing". This also groups it with the future CF Tunnel bootstrap under `hack/cloudflare/`.
- `just bootstrap-state` gets a hardcoded path to `hack/cloudflare/` instead of interpolating `${CSP}` — **state backend is decoupled from infra CSP** and that's a property worth making visible in the recipe.
- `.env.hetzner.homelab`: `HETZNER_OBJECT_STORAGE_{ENDPOINT,REGION}` go away, replaced by `R2_ENDPOINT` + `AWS_REGION=auto`. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` stay (both providers use AWS-style creds).
- `backend.hcl` snippets for stacks: `region = "auto"`, endpoint points at `<account-id>.r2.cloudflarestorage.com`. `use_path_style = true` required for R2. Otherwise identical to the Hetzner Object Storage shape.
- **Not Hetzner-specific and not R2-specific moving forward:** the `backend "s3" {}` declaration in each stack's `backend.tf`. Backend migrations (R2 → somewhere else, if ever needed) are a `live/.../backend.hcl` edit + `tofu init -migrate-state`, no stack code changes.

## Scope

- Phase 2 deliverables (bootstrap script, env template, README, `just` recipe).
- Future `backend.hcl` authoring in every `live/.../` stack directory.
- No change to `stacks/.../backend.tf` — it's already the vendor-agnostic `backend "s3" {}` empty block.
