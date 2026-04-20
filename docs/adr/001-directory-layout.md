# ADR-001: Directory layout

## Status
Accepted — 2026-04-21

## Context

The repo needs to grow across two axes: multiple environments (currently just `homelab`, potentially `staging`, `prod`) and multiple cloud providers (starting with Hetzner, extensible to AWS and beyond). It also spans two tooling layers: OpenTofu for cloud resources and Ansible for service deployment.

A flat `terraform/<csp>/` layout (one dir per provider) works for one cloud + one env but gets cramped once the matrix grows. Without a clear convention, tfvars values creep into module code and environments diverge silently.

## Decision

Use a **two-layer split**, mirrored by path:

```
stacks/<env>/<csp>/<group>/<proj>/   # Terraform code (main.tf, provider.tf, context.tf…)
live/<env>/<csp>/<group>/<proj>/     # Terraform data (terraform.tfvars, backend.hcl)
```

- **`stacks/`** holds the immutable module composition per deployment unit. No literal values, only variable wiring.
- **`live/`** holds the environment-specific values and backend wiring. tfvars is gitignored initially (may contain secrets before Phase 7); backend.hcl is committed.
- **`<env>`** (e.g., `homelab`) isolates full environments.
- **`<csp>`** (e.g., `hetzner`, `aws`) pins the cloud provider.
- **`<group>`** (e.g., `network`, `storage`, `platform`) clusters related stacks.
- **`<proj>`** (e.g., `server`, `cf-tunnel`) is the leaf — one `tofu` workspace.

Alongside, two peer trees:

- **`modules/<csp>/`** — reusable per-cloud primitives (e.g., `modules/hetzner/server/`). `modules/aws/` is kept as an empty placeholder so future expansion has an anchor.
- **`modules/shared/`** — cross-cloud modules (e.g., `infisical-identity`).
- **`ansible/roles/`** — service-deployment layer. Terraform output (server IPs, Tailscale IPs) flows into Ansible inventory.

## Consequences

**Positive**
- Tooling maps paths mechanically. `just apply <group> <proj>` resolves `stacks/$ENV/$CSP/<group>/<proj>/` and `live/$ENV/$CSP/<group>/<proj>/` with zero per-stack config.
- Adding an env or a CSP is a copy-paste shape, not a redesign.
- Code/data separation prevents accidental secret leakage and makes diffs readable: "new feature" PRs touch `stacks/` only; "new environment" PRs touch `live/` only.

**Negative**
- Two trees to navigate instead of one. Mitigated by the mirrored structure.
- Some duplication between live and stacks paths. Offset by the mechanical tool mapping.

**Related**
- Naming: [002-naming-convention.md](002-naming-convention.md)
- Cross-stack refs: [003-cross-stack-references.md](003-cross-stack-references.md)
- tfvars gitignore rationale: README + future decision log when switching to Infisical data sources
