# ADR-004: Network architecture — Cloudflare Tunnel + Tailscale

## Status
Accepted — 2026-04-21

## Context

The homelab exposes some services publicly (Grafana dashboards, an RSS reader, a password vault) and keeps others private (SSH, DB direct access, Traefik dashboard). Two common choices:

1. **Open inbound ports** on the VM and put a reverse proxy (Caddy/Traefik/Nginx) with TLS + ACME in front. Public services get public hostnames; private ones get firewall rules.
2. **Tunnel + VPN** — a tunnel handles public ingress (no inbound ports), a VPN handles private access.

Option 1 is simpler in one dimension (no extra services) but harder in others: the VM has a public surface, ACME has edge cases (firewall, rate limits), and private endpoints need careful firewall rules that can drift.

## Decision

Split by purpose:

**Public ingress — Cloudflare Tunnel**
- `cloudflared` on the VM establishes an outbound connection to Cloudflare's edge.
- DNS: `*.<domain>` CNAMEs to the tunnel (wildcard, proxied).
- Ingress rule: tunnel → `http://localhost:80` → Traefik.
- Traefik does subdomain routing to Docker containers via the shared `traefik-public` network.
- Host firewall: 22 SSH (narrowed to Tailscale later), 80/443 open initially to allow manual debugging; closed after Cloudflare Tunnel is healthy.

**Management access — Tailscale**
- VM joins a Tailscale tailnet (SaaS initially; self-hosted Headscale considered later).
- Admin uses Tailscale IPs for SSH, Traefik dashboard, direct DB access, service-internal UIs.
- Tailscale ACLs restrict which nodes can reach which services.

```
Public user
  → Cloudflare CDN (DDoS, TLS)
  → Cloudflare Tunnel (outbound-only, no inbound VM ports)
  → Traefik :80
  → subdomain-routed container

Admin (me)
  → Tailscale VPN
  → VM: SSH :22, Traefik dashboard, DB ports, internal UIs
```

## Consequences

**Positive**
- VM has **zero required inbound ports** once Cloudflare Tunnel is healthy. Attack surface for public services is Cloudflare's, not the VM's.
- No ACME machinery on the VM — Cloudflare terminates TLS at the edge.
- Admin access does not rely on opening SSH to the internet; credential leaks have a smaller blast radius.
- Separation of concern is explicit: public ≠ admin. Mistakenly exposing an admin UI publicly requires accidentally adding a Cloudflare Tunnel ingress rule AND a Traefik label, not just forgetting a firewall rule.

**Negative**
- Two external dependencies (Cloudflare + Tailscale) instead of one reverse proxy.
- Cloudflare outage affects public services (acceptable — article-scale homelab, not SLA-backed).
- Tailscale SaaS has a free-tier device limit and a 3rd-party trust surface. Mitigated by planned migration to self-hosted Headscale.

**Related**
- [001-directory-layout.md](001-directory-layout.md) — `network/server` and `network/cf-tunnel` are separate stacks for a reason.
- Future ADR: Tailscale → Headscale migration, when it happens.
