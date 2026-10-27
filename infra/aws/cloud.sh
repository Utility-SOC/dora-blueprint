#!/usr/bin/env bash
# Up/down driver for the ephemeral EKS lab (infra/aws/cluster) -- what `make cloud-up` /
# `make cloud-down` and .github/workflows/cloud-lab.yaml both call, so a laptop run and a CI run
# are the same code path.
#
#   cloud.sh up      create or update lab $LAB_NAME, due for teardown in $TTL_HOURS
#   cloud.sh down    destroy lab $LAB_NAME
#   cloud.sh reap    destroy every lab in this account+region whose expires-at tag has passed
#
# Persistent-stack values (state bucket, backups bucket, KMS key) come from the environment when
# set (CI: repository variables), otherwise from infra/aws/persistent's local state. One state
# file per lab name, so several labs -- e.g. one per trainee -- can coexist.
set -euo pipefail

ACTION="${1:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="${TF:-tofu}"
LAB_NAME="${LAB_NAME:-dora-lab}"
TTL_HOURS="${TTL_HOURS:-4}"
NAME_PREFIX="${NAME_PREFIX:-dora-blueprint}"

persistent() {  # <output name>
  "$TF" -chdir="$HERE/persistent" output -raw "$1"
}
STATE_BUCKET="${STATE_BUCKET:-$(persistent state_bucket)}"
BACKUPS_BUCKET="${BACKUPS_BUCKET:-$(persistent backups_bucket)}"
KMS_KEY_ARN="${KMS_KEY_ARN:-$(persistent kms_key_arn)}"
AWS_REGION="${AWS_REGION:-$(persistent region)}"
export STATE_BUCKET BACKUPS_BUCKET KMS_KEY_ARN AWS_REGION

# admin CIDRs / principals arrive as comma-separated lists; Terraform wants HCL lists.
hcl_list() { python3 -c 'import json, sys; print(json.dumps([x.strip() for x in sys.argv[1].split(",") if x.strip()]))' "${1:-}"; }

init() {  # <lab name>
  "$TF" -chdir="$HERE/cluster" init -input=false -reconfigure \
    -backend-config="bucket=$STATE_BUCKET" \
    -backend-config="key=cluster/$1.tfstate" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="encrypt=true" \
    -backend-config="use_lockfile=true" >/dev/null
}

tf_vars() {  # <lab name> <expires_at>
  export TF_VAR_name="$1" TF_VAR_expires_at="$2" TF_VAR_region="$AWS_REGION" \
    TF_VAR_name_prefix="$NAME_PREFIX" TF_VAR_backups_bucket="$BACKUPS_BUCKET" \
    TF_VAR_kms_key_arn="$KMS_KEY_ARN" \
    TF_VAR_admin_cidrs="$(hcl_list "${ADMIN_CIDRS:-}")" \
    TF_VAR_admin_principal_arns="$(hcl_list "${ADMIN_PRINCIPAL_ARNS:-}")"
}

case "$ACTION" in
  up)
    [ -n "${ADMIN_CIDRS:-}" ] || { echo "ADMIN_CIDRS is required (e.g. ADMIN_CIDRS=203.0.113.4/32) -- the CIDRs allowed to reach the Kubernetes API" >&2; exit 1; }
    EXPIRES_AT="$(python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=float(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$TTL_HOURS")"
    init "$LAB_NAME"
    tf_vars "$LAB_NAME" "$EXPIRES_AT"
    "$TF" -chdir="$HERE/cluster" apply -input=false ${AUTO_APPROVE:+-auto-approve}
    eval "$("$TF" -chdir="$HERE/cluster" output -raw kubeconfig_command)"
    echo "lab $LAB_NAME is up until $EXPIRES_AT -- 'make cloud-down LAB_NAME=$LAB_NAME' when done"
    ;;
  down)
    init "$LAB_NAME"
    # Destroy doesn't care about these values, but every variable without a default still
    # has to be set; expires_at gets a placeholder that passes validation.
    tf_vars "$LAB_NAME" "1970-01-01T00:00:00Z"
    TF_VAR_admin_cidrs='["127.0.0.1/32"]' "$TF" -chdir="$HERE/cluster" destroy -input=false ${AUTO_APPROVE:+-auto-approve}
    ;;
  reap)
    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for CLUSTER in $(aws eks list-clusters --query 'clusters[]' --output text); do
      TAGS="$(aws eks describe-cluster --name "$CLUSTER" --query 'cluster.tags' --output json)"
      PROJECT="$(echo "$TAGS" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("project", ""))')"
      EXPIRY="$(echo "$TAGS" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("expires-at", ""))')"
      [ "$PROJECT" = "$NAME_PREFIX" ] || continue
      # Same fixed-width UTC format on both sides, so string comparison is time comparison.
      if [ -n "$EXPIRY" ] && [[ "$EXPIRY" < "$NOW" ]]; then
        echo "reaping $CLUSTER (expired $EXPIRY)"
        LAB_NAME="$CLUSTER" AUTO_APPROVE=1 bash "$0" down
      else
        echo "keeping $CLUSTER (expires ${EXPIRY:-never -- no expires-at tag, not created by this script})"
      fi
    done
    ;;
  *)
    echo "usage: $0 up|down|reap   (env: LAB_NAME, TTL_HOURS, ADMIN_CIDRS, ADMIN_PRINCIPAL_ARNS, TF)" >&2
    exit 1
    ;;
esac
