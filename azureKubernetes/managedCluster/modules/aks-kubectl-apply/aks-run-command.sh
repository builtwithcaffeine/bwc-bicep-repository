#!/bin/bash
set -euo pipefail
set +H
export LANG=C.UTF-8

initialDelay="${initialDelay:-0}"
RG="${RG:?missing RG}"
aksName="${aksName:?missing aksName}"
kubeManifest="${kubeManifest:?missing kubeManifest (base64)}"

if [ "$initialDelay" != "0" ]; then
  echo "Waiting on RBAC replication ($initialDelay)s…"
  sleep "$initialDelay"
  az logout || true
  az login --identity
fi

# Safer temp file & cleanup
kubeManifestFile="$(mktemp -t kubemanifest.XXXXXX.yaml)"
trap 'rm -f "$kubeManifestFile"' EXIT

echo "Decoding manifest to $kubeManifestFile…"
# Quote to preserve newlines and non-ASCII
printf %s "$kubeManifest" | base64 -d > "$kubeManifestFile"

echo "Applying manifest to AKS cluster $aksName in $RG…"
result_json="$(
  az aks command invoke \
    -g "$RG" -n "$aksName" \
    --command "kubectl apply -f /work/kubemanifest.yaml" \
    --file "$kubeManifestFile" \
    --target-directory /work \
    -o json
)"

# Inspect the real (remote) exit code and logs
exit_code="$(echo "$result_json" | jq -r '.status.exitCode // .exitCode // empty')"
logs="$(echo "$result_json" | jq -r '.logs // empty')"

[ -n "$logs" ] && { echo "----- kubectl logs -----"; echo "$logs"; echo "------------------------"; }

if [ -z "$exit_code" ] || [ "$exit_code" -ne 0 ]; then
  prov="$(echo "$result_json" | jq -r '.status.provisioningState // .provisioningState // empty')"
  echo "kubectl failed inside AKS run-command (exitCode=${exit_code:-missing}, provisioningState=${prov:-unknown})."
  exit 1
fi

echo "$result_json" > "$AZ_SCRIPTS_OUTPUT_PATH"