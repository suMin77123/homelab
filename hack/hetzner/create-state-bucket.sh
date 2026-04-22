#!/usr/bin/env bash
# Create (or verify) the Hetzner Object Storage bucket used as the
# Terraform/OpenTofu S3 backend. Idempotent.
#
# Reads from the loaded .env:
#   AWS_ACCESS_KEY_ID                  (Hetzner Object Storage key)
#   AWS_SECRET_ACCESS_KEY
#   HETZNER_OBJECT_STORAGE_ENDPOINT    (e.g. https://fsn1.your-objectstorage.com)
#   HETZNER_OBJECT_STORAGE_REGION      (fsn1 / nbg1 / hel1)
#   STATE_BUCKET                       (optional, defaults to homelab-tfstate)

set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?set AWS_ACCESS_KEY_ID in .env (Hetzner Object Storage S3 key)}"
: "${AWS_SECRET_ACCESS_KEY:?set AWS_SECRET_ACCESS_KEY in .env}"
: "${HETZNER_OBJECT_STORAGE_ENDPOINT:?set HETZNER_OBJECT_STORAGE_ENDPOINT in .env}"
: "${HETZNER_OBJECT_STORAGE_REGION:?set HETZNER_OBJECT_STORAGE_REGION in .env}"
: "${STATE_BUCKET:=homelab-tfstate}"

if ! command -v aws >/dev/null 2>&1; then
    echo "✗ aws CLI not found — run 'just install' first" >&2
    exit 1
fi

export AWS_DEFAULT_REGION="${HETZNER_OBJECT_STORAGE_REGION}"
export AWS_EC2_METADATA_DISABLED=true
# aws-cli v2 default adds CRC64 checksums on upload that Hetzner rejects;
# fall back to only-when-required so S3 PUTs succeed.
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

echo "→ Target: s3://${STATE_BUCKET} @ ${HETZNER_OBJECT_STORAGE_ENDPOINT}"

# 1. Create (or confirm) the bucket
if aws --endpoint-url="${HETZNER_OBJECT_STORAGE_ENDPOINT}" \
        s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    echo "✓ Bucket exists"
else
    echo "→ Creating bucket..."
    aws --endpoint-url="${HETZNER_OBJECT_STORAGE_ENDPOINT}" \
        s3api create-bucket --bucket "${STATE_BUCKET}"
    echo "✓ Bucket created"
fi

# 2. Write/read/delete sanity test so a silent misconfig surfaces here
#    rather than during 'tofu init' with a confusing error.
probe="_bootstrap-check-$$-$(date +%s).txt"
printf 'ok' | aws --endpoint-url="${HETZNER_OBJECT_STORAGE_ENDPOINT}" \
    s3 cp - "s3://${STATE_BUCKET}/${probe}" \
    --content-type text/plain >/dev/null
aws --endpoint-url="${HETZNER_OBJECT_STORAGE_ENDPOINT}" \
    s3 rm "s3://${STATE_BUCKET}/${probe}" >/dev/null
echo "✓ write/read sanity passed"

cat <<EOF

State bucket ready. Reference it from live/<env>/<csp>/<group>/<proj>/backend.hcl:

    bucket                      = "${STATE_BUCKET}"
    key                         = "<env>/<csp>/<group>/<proj>/terraform.tfstate"
    region                      = "${HETZNER_OBJECT_STORAGE_REGION}"
    endpoints                   = { s3 = "${HETZNER_OBJECT_STORAGE_ENDPOINT}" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true

EOF
