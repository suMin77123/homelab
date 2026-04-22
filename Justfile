# Homelab foundation task runner.
# Loads ENV / CSP / PROJECT and cloud credentials from .env at recipe time.

set dotenv-load := true
set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT := justfile_directory()

default:
    @just --list

# ============================================================
# Setup
# ============================================================

# Install pinned CLI tools via mise + Ansible via pipx + awscli via brew
install:
    mise install
    @if ! command -v ansible >/dev/null 2>&1; then \
        pipx install --include-deps ansible && pipx inject ansible docker; \
    else \
        echo "✓ ansible already installed"; \
    fi
    @if ! command -v aws >/dev/null 2>&1; then \
        brew install awscli; \
    else \
        echo "✓ aws CLI already installed"; \
    fi
    @echo "✓ Tools ready — run 'just envs' next"

# Interactively pick .env.<csp>.<project> and symlink it as .env
envs:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ROOT}}
    mapfile -t files < <(ls -1 .env.*.* 2>/dev/null | grep -v '\.example$' || true)
    if [ "${#files[@]}" -eq 0 ]; then
        echo "No .env.<csp>.<project> files found next to Justfile." >&2
        echo "Copy .env.hetzner.homelab.example → .env.hetzner.homelab, fill in tokens." >&2
        exit 1
    fi
    PS3="Pick env: "
    select target in "${files[@]}"; do
        [ -n "${target:-}" ] && break
    done
    ln -snfv "$target" .env

# Print ENV / CSP / PROJECT from the active .env
ctx:
    @echo "ENV     = ${ENV:-<unset>}"
    @echo "CSP     = ${CSP:-<unset>}"
    @echo "PROJECT = ${PROJECT:-<unset>}"
    @if [ -L .env ]; then readlink .env | xargs -I{} echo ".env    → {}"; else echo ".env    <missing or not a symlink>"; fi

# Create the remote state bucket (one-time, Phase 2)
bootstrap-state:
    @bash {{ROOT}}/hack/${CSP}/create-state-bucket.sh

# ============================================================
# Cloud auth sanity checks
# ============================================================

# Verify Hetzner CLI context
login-hetzner:
    @hcloud context active
    @hcloud server list --output columns=name,status,ipv4 2>/dev/null || echo "(no servers yet)"

# Verify Cloudflare API token is present in env
login-cf:
    @if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then echo "✓ CLOUDFLARE_API_TOKEN set"; else echo "✗ CLOUDFLARE_API_TOKEN missing"; exit 1; fi

# Verify Tailscale is running
login-tailscale:
    @tailscale status --self=false 2>/dev/null | head -5 || echo "Tailscale not connected (run 'tailscale up')"

# ============================================================
# Terraform / OpenTofu core
# ============================================================

# Create empty stacks/ + live/ directories for a new stack
prep group proj:
    @mkdir -p "{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}"
    @mkdir -p "{{ROOT}}/live/${ENV}/${CSP}/{{group}}/{{proj}}"
    @echo "✓ stacks/${ENV}/${CSP}/{{group}}/{{proj}}"
    @echo "✓ live/${ENV}/${CSP}/{{group}}/{{proj}}"

# tofu init with backend config from live/
init group proj:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" init \
        -backend-config="{{ROOT}}/live/${ENV}/${CSP}/{{group}}/{{proj}}/backend.hcl" \
        -reconfigure

# tofu plan with tfvars from live/, saves plan.tfplan
plan group proj:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" plan \
        -var-file="{{ROOT}}/live/${ENV}/${CSP}/{{group}}/{{proj}}/terraform.tfvars" \
        -out="plan.tfplan"

# tofu apply the saved plan.tfplan
apply group proj:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" apply "plan.tfplan"

# tofu destroy (uses tfvars, prompts for confirmation)
destroy group proj:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" destroy \
        -var-file="{{ROOT}}/live/${ENV}/${CSP}/{{group}}/{{proj}}/terraform.tfvars"

# Print stack outputs (pass -raw or a specific name)
output group proj *ARGS:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" output {{ARGS}}

# tofu fmt across stacks + modules
fmt:
    tofu fmt -recursive {{ROOT}}/stacks {{ROOT}}/modules

# tofu validate (requires init first)
validate group proj:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" validate

# ============================================================
# State inspection
# ============================================================

state-list group proj:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" state list

state-show group proj resource:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" state show {{resource}}

state-rm group proj resource:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" state rm {{resource}}

state-mv group proj src dst:
    tofu -chdir="{{ROOT}}/stacks/${ENV}/${CSP}/{{group}}/{{proj}}" state mv {{src}} {{dst}}

# ============================================================
# Ansible
# ============================================================

# Verify Ansible can reach hosts in inventory
ansible-ping:
    cd {{ROOT}}/ansible && ansible -i inventory.yml all -m ping

# Run playbook; optional ROLE arg runs only that role via --tags
deploy *ROLE:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ROOT}}/ansible
    if [ -n "{{ROLE}}" ]; then
        ansible-playbook -i inventory.yml playbook.yml --tags "{{ROLE}}"
    else
        ansible-playbook -i inventory.yml playbook.yml
    fi

# Dry-run equivalent of `deploy`
deploy-check *ROLE:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ROOT}}/ansible
    if [ -n "{{ROLE}}" ]; then
        ansible-playbook -i inventory.yml playbook.yml --check --tags "{{ROLE}}"
    else
        ansible-playbook -i inventory.yml playbook.yml --check
    fi

# ============================================================
# DR / Recovery
# ============================================================

# Destroy the server stack, recreate it, redeploy all services.
# Requires typing the env name to confirm.
recover:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "⚠️  This destroys and recreates ${ENV}/${CSP}. Type '${ENV}' to confirm:"
    read -r confirm
    [ "$confirm" = "${ENV}" ] || { echo "Cancelled."; exit 1; }
    just destroy network server
    just apply network server
    just ansible-ping
    just deploy
