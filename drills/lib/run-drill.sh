#!/usr/bin/env bash
# Submits a Workflow from a WorkflowTemplate (drills/templates/), waits for it, and
# prints the emitted drill record plus a human-readable RTO/RPO/verdict summary.
# No `argo` CLI dependency — kubectl create + poll + logs, same tools as everything
# else in this repo's operational path.
set -euo pipefail

SCENARIO="${SCENARIO:?usage: SCENARIO=<name> run-drill.sh}"
NAMESPACE="argo-workflows"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

WF_NAME="$(kubectl -n "$NAMESPACE" create -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: ${SCENARIO}-
spec:
  workflowTemplateRef:
    name: ${SCENARIO}
  arguments:
    parameters:
      - name: git-sha
        value: "${GIT_SHA}"
EOF
)"

echo "submitted workflow: $WF_NAME"

while true; do
  PHASE="$(kubectl -n "$NAMESPACE" get workflow "$WF_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$PHASE" in
    Succeeded|Failed|Error) break ;;
  esac
  sleep 5
done

echo "--- workflow $PHASE ---"
LOGS="$(kubectl -n "$NAMESPACE" logs -l "workflows.argoproj.io/workflow=$WF_NAME" --tail=-1 2>&1)"
echo "$LOGS"

if [ "$PHASE" != "Succeeded" ]; then
  echo "drill did not succeed (workflow phase: $PHASE)" >&2
  exit 1
fi

RAW_RECORD="$(echo "$LOGS" | grep '^{"drill_id"' | tail -1)"

echo
echo "=== drill record (as emitted) ==="
echo "$RAW_RECORD" | python3 -m json.tool

# Phase 11 (Incident response, build-spec §6.5/§6.4/§6.8): classify, compute both regulatory
# clocks, re-validate the enriched record through emit.py's own schema check, then open a real
# GitHub Issue. Host-side, not inside the workflow pod -- keeps the workflow template's own job
# (inject/detect/recover/verify) separate from response concerns, and lets emit.py's existing
# validation logic actually get exercised for the first time outside its own design intent.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENRICHED_RECORD="$(echo "$RAW_RECORD" | python3 "$LIB_DIR/enrich.py")"

echo
echo "=== enriched drill record (classification + regulatory clocks) ==="
echo "$ENRICHED_RECORD" | python3 -m json.tool

echo
echo "=== opening incident issue ==="
GITHUB_TOKEN_TMP="$(mktemp)"
trap 'shred -u "$GITHUB_TOKEN_TMP" 2>/dev/null || rm -f "$GITHUB_TOKEN_TMP"' EXIT
REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
sops --decrypt "$REPO_ROOT/drills/secrets/github-token.enc.yaml" > "$GITHUB_TOKEN_TMP"
GITHUB_TOKEN="$(awk '/^github_token:/ {print $2}' "$GITHUB_TOKEN_TMP")"
rm -f "$GITHUB_TOKEN_TMP"

ISSUE_RESULT="$(echo "$ENRICHED_RECORD" | GITHUB_TOKEN="$GITHUB_TOKEN" python3 "$LIB_DIR/open-incident.py")"
echo "$ISSUE_RESULT" | python3 -m json.tool

echo
echo "=== summary ==="
echo "$LOGS" | grep '^RESULT_'
