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

echo
echo "=== drill record ==="
echo "$LOGS" | grep '^{"drill_id"' | tail -1 | python3 -m json.tool 2>/dev/null || echo "$LOGS" | grep '^{"drill_id"'
echo
echo "=== summary ==="
echo "$LOGS" | grep '^RESULT_'
