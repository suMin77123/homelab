# ADR-002: Naming convention via null-label

## Status
Accepted — 2026-04-21

## Context

Cloud resources accumulate names across many stacks. Without a convention, names drift — `rss-server`, `db-prod`, `homelab_vm_1` — and tagging (for cost attribution, sweeping, ownership) becomes inconsistent. Every `tofu` maintainer then has to re-derive "what do I call this thing?"

## Decision

Use **[`cloudposse/label/null`](https://registry.terraform.io/modules/cloudposse/label/null/)** in every stack via a per-stack `context.tf`.

Stacks produce their identity through:

```hcl
module "label" {
  source  = "cloudposse/label/null"
  version = "~> 0.25"

  namespace   = var.namespace    # e.g., "homelab"
  environment = var.environment  # e.g., "homelab" (this repo has a single env for now)
  stage       = var.stage        # e.g., "network", "storage", "platform"
  name        = var.name         # e.g., "server", "cf-tunnel"

  tags = var.tags                # { owner = "me", managed_by = "opentofu", ... }
}
```

The module outputs:

- `module.label.id` → `{ns}-{env}-{stage}-{name}` (e.g., `homelab-homelab-network-server`)
- `module.label.tags` → merged tag map
- `module.label.tags_as_list_of_maps` → some providers need list form

All resources in the stack reference `module.label.id` as their name and `module.label.tags` as their labels/tags.

All label variables (`namespace`, `environment`, `stage`, `name`, `tags`) live in the stack's `terraform.tfvars` under `live/`. They are never hardcoded in `main.tf`.

## Consequences

**Positive**
- Names and tags stay consistent across stacks without any developer discipline beyond "include context.tf".
- Every resource is attributable to a stack — useful for debugging, cost reports, mass-cleanup.
- Works across cloud providers (Hetzner labels, AWS tags, etc.) since each provider's name/tag mechanism consumes the same module outputs.

**Negative**
- `environment == namespace == "homelab"` feels redundant today. Accepted; leaves room for a future "team" or "project" namespace when needed without restructuring stacks.
- Names can be long in nested stacks. Mitigated: most resources see only the full ID; humans see the path in the repo.

**Related**
- [001-directory-layout.md](001-directory-layout.md) — the stack path and the label IDs align.
