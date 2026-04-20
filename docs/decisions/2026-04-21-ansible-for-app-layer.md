# 2026-04-21 — Ansible for the service/app layer

## Context

OpenTofu provisions cloud resources (VMs, networks, state buckets, DNS, tunnels). That's the *infrastructure* layer. On top of that a homelab runs services — Docker, Traefik, PostgreSQL, Authentik, monitoring — and those need a *configuration / deployment* layer: something that installs, configures, and updates them idempotently over time.

Three candidates:

## Alternatives

- **A) cloud-init only** — bake service setup into the VM's initial `user_data`. Simple for one-shot provisioning; no extra tool to learn.
- **B) Ansible** — role-per-service, idempotent playbooks, SSH-driven.
- **C) Nix / NixOS** — declarative whole-system config; rebuilds are atomic.

## Decision

**B — Ansible.**

## Reasoning

- **Service churn is the expected operating mode**, not the edge case. A homelab adds Miniflux this week, a music server next, a Vaultwarden after that. cloud-init (A) runs once at VM boot and has no story for "add a service later" — you'd either re-provision or work around it.
- **Ansible's role-per-service model matches how services get added**. Adding a new service is: new role, append to playbook, run. Removing: delete role, run. Idempotence handles re-runs cleanly.
- **A pre-existing step guide** (step-4 through step-6) already designed Ansible roles for common/docker/postgresql/traefik/authentik/prometheus. Reusing that investment is easier than redesigning under a new paradigm.
- **Nix (C) gives stronger guarantees** — atomic rebuilds, reproducible whole-machine state. But it's a significant learning detour and the homelab's "reproducibility" bar is already met by Terraform + Ansible + the recovery test (Phase 9). The Nix step change isn't worth the cost right now.

## Consequences

- Two layers to maintain: `.tf` files and `.yml` files. Mitigated by keeping them under one repo and driving both from `Justfile`.
- The app layer needs its own bootstrap once the VM exists: Ansible inventory wiring, SSH to Tailscale IPs, Python interpreter path on Debian. First Phase-5 pass absorbs this setup cost.
- Terraform outputs (server IP, tunnel token) need to flow into Ansible. Initial plan is env-var + tfvars; Phase 7 replaces those with Infisical data sources.
- If Nix becomes compelling later (for example, if we want NixOS VMs instead of Debian), the migration path is: rewrite roles as Nix modules, swap `debian-12` image for NixOS. No other repo structure changes.

## Scope

Everything under `ansible/`. The Terraform side is untouched by this decision.
