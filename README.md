# homelab

Cloud-based self-hosted infrastructure. Learning, reproducibility, data ownership, low cost.

## Architecture

Two-layer IaC:

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Infrastructure | OpenTofu | Cloud resources — VMs, networking, state storage, DNS, tunnels |
| Services | Ansible | Service deployment — Docker, Traefik, SSO, apps |

Access paths:

- **Public** — Cloudflare Tunnel → Traefik → subdomain-routed containers (no inbound ports on host)
- **Management** — Tailscale VPN → SSH / internal dashboards

Secrets: Infisical (cloud-auth machine identities read at apply time).

## Repo layout

```
docs/adr/           # Architecture Decision Records — "why we designed it this way"
docs/decisions/     # Decision logs — "why we made this specific choice"
stacks/<env>/<csp>/<group>/<proj>/   # Terraform code (provider, main, variables, context)
live/<env>/<csp>/<group>/<proj>/     # Terraform data (tfvars, backend.hcl)
modules/<csp>/      # Reusable Terraform primitives per cloud
ansible/roles/      # One role per service
hack/<csp>/         # One-time bootstrap scripts (state bucket creation, etc.)
```

State lives in Hetzner Object Storage (S3-compatible), one bucket per project with per-stack key prefix.

## Prerequisites

**Host machine**
- macOS with Homebrew
- `mise` + `just` (`brew install mise just`)
- SSH key (`ssh-keygen -t ed25519 -f ~/.ssh/homelab`)

**Hetzner Cloud**
- Account + payment method on file
- API token (Console → Security → API Tokens, Read & Write)

**Hetzner Object Storage** (state backend)
- Object Storage enabled: Console → Object Storage → create a project in your chosen region (`fsn1` recommended to match server location)
- S3-protocol credentials generated in that project. Note: these are *separate* from the Cloud API token above

**Later phases**
- Cloudflare account + domain + API token (Phase 4)
- Tailscale account + reusable auth key (Phase 4)
- Infisical workspace + machine identity (Phase 7)

## Quick start

```bash
# 1. Install pinned tool versions
just install

# 2. Select environment (creates .env symlink)
just envs

# 3. Verify context
just ctx

# 4. Cloud auth sanity check
just login-hetzner

# 5. Bootstrap remote state bucket (first time only, creates + smoke-tests it)
just bootstrap-state

# 6. Deploy a stack (example)
just prep network server
just init network server
just plan network server
just apply network server
```

## Commands

| Group | Command | Purpose |
|-------|---------|---------|
| Setup | `just install` / `just envs` / `just ctx` | Tool install, env switch, context |
| Auth | `just login-hetzner` / `just login-cf` / `just login-tailscale` | Cloud auth checks |
| Terraform | `just prep/init/plan/apply/destroy/output GROUP PROJ` | Core lifecycle |
| State | `just state-list/show/rm/mv` | State introspection |
| Ansible | `just ansible-ping` / `just deploy [ROLE]` / `just deploy-check` | Service deployment |
| DR | `just recover` | Destroy → recreate → redeploy |

Run `just` with no args to list all recipes.

## Design references

- Directory layout rationale: [docs/adr/001-directory-layout.md](docs/adr/001-directory-layout.md)
- Naming convention: [docs/adr/002-naming-convention.md](docs/adr/002-naming-convention.md)
- Cross-stack references: [docs/adr/003-cross-stack-references.md](docs/adr/003-cross-stack-references.md)
- Network architecture: [docs/adr/004-network-architecture.md](docs/adr/004-network-architecture.md)
