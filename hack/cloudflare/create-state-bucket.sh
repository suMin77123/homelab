#!/usr/bin/env bash
# Create (or verify) the Cloudflare R2 bucket used as the Terraform/OpenTofu
# S3-compatible state backend. Idempotent.
#
# Reads from the loaded .env:
#   AWS_ACCESS_KEY_ID                  (R2 token access key ID)
#   AWS_SECRET_ACCESS_KEY              (R2 token secret)
#   R2_ENDPOINT                        (https://<account-id>.r2.cloudflarestorage.com)
#   STATE_BUCKET                       (optional, defaults to homelab-tfstate)
#
# R2 always uses region "auto" — that's hardcoded below rather than taken
# from env to make the contract unambiguous.

set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?set AWS_ACCESS_KEY_ID in .env (R2 token access key ID)}"
: "${AWS_SECRET_ACCESS_KEY:?set AWS_SECRET_ACCESS_KEY in .env}"
: "${R2_ENDPOINT:?set R2_ENDPOINT in .env, e.g. https://<account-id>.r2.cloudflarestorage.com}"
: "${STATE_BUCKET:=homelab-tfstate}"

if ! command -v aws >/dev/null 2>&1; then
    echo "✗ aws CLI not found — run 'just install' first" >&2
    exit 1
fi

# R2 requires path-style addressing and region "auto". The checksum overrides
# avoid CRC64 upload failures that R2 (and most S3-compat services) reject.
# AWS_PAGER="" turns off the aws CLI v2 default of paging JSON through less —
# head-bucket emits a one-line response we don't care about.
export AWS_DEFAULT_REGION=auto
export AWS_EC2_METADATA_DISABLED=true
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
export AWS_PAGER=""

echo "→ Target: s3://${STATE_BUCKET} @ ${R2_ENDPOINT}"

# 1. Create (or confirm) the bucket
if aws --endpoint-url="${R2_ENDPOINT}" \
        s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1; then
    echo "✓ Bucket exists"
else
    echo "→ Creating bucket..."
    aws --endpoint-url="${R2_ENDPOINT}" \
        s3api create-bucket --bucket "${STATE_BUCKET}"
    echo "✓ Bucket created"
fi

# 2. Write/read/delete sanity test so a silent misconfig surfaces here rather
#    than during 'tofu init' with a confusing error.
probe="_bootstrap-check-$$-$(date +%s).txt"
printf 'ok' | aws --endpoint-url="${R2_ENDPOINT}" \
    s3 cp - "s3://${STATE_BUCKET}/${probe}" \
    --content-type text/plain >/dev/null
aws --endpoint-url="${R2_ENDPOINT}" \
    s3 rm "s3://${STATE_BUCKET}/${probe}" >/dev/null
echo "✓ write/read sanity passed"

cat <<EOF

State bucket ready. Reference it from live/<env>/<csp>/<group>/<proj>/backend.hcl:

    bucket                      = "${STATE_BUCKET}"
    key                         = "<env>/<csp>/<group>/<proj>/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "${R2_ENDPOINT}" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true

EOF
