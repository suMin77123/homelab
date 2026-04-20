# ADR-003: Cross-stack references via data sources

## Status
Accepted — 2026-04-21

## Context

Stacks need to reference each other — the `cf-tunnel` stack needs the server's IP; the Ansible inventory needs both; a monitoring stack might need the VPC ID. Two common approaches:

1. **`terraform_remote_state`** — read another stack's state file directly.
2. **Provider data sources** — look up resources by tag or name from the cloud provider's API.

`terraform_remote_state` is the path of least resistance: no extra API calls, types line up with outputs. But it couples every reader to the producer's backend configuration and state file schema. Migrating a backend (e.g., moving from local to S3) or restructuring the state invalidates readers. Worse, if a reader is running with a stale state file version, it can read outdated values and produce divergent plans.

## Decision

**Use provider data sources for cross-stack reads. Do not use `terraform_remote_state`.**

Example — the cf-tunnel stack discovering the Hetzner server:

```hcl
data "hcloud_server" "homelab" {
  name = module.label.id  # resolved via null-label naming convention
}
```

Readers identify the target resource by the predictable name (per [ADR-002](002-naming-convention.md)) or by a label/tag query. The cloud provider API is the source of truth.

Where a data source doesn't exist or is slow, fall back to **passing the value via `tfvars`** — explicit, auditable, and decoupled.

## Consequences

**Positive**
- Stacks can be planned and applied independently. No stack needs to know another's backend.
- Backend migrations (local → S3, one bucket → another) are invisible to readers.
- Data-source lookups validate against actual cloud state — catch drift between two stacks, not between code and stale state.

**Negative**
- Slightly slower plans due to API calls. Usually negligible.
- Requires each cross-stack relationship to have either (a) a data source or (b) a tfvars hop. Sometimes the latter feels like passing values the long way around.
- Some resources (Cloudflare Tunnel tokens, randomly generated secrets) don't have data source equivalents. For these, use Infisical (Phase 7) or an out-of-band share, not `terraform_remote_state`.

**Related**
- [001-directory-layout.md](001-directory-layout.md) — each stack owns its state; readers query the cloud instead.
- [002-naming-convention.md](002-naming-convention.md) — consistent naming is what makes data-source lookups reliable.
