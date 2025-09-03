#!/bin/bash
set -e +H  # -e to exit on error, +H to disable history expansion
export LANG=C.UTF-8

# Input parameters with safety checks
initialDelay="${initialDelay:-0}"
RG="${RG:?missing RG}"
aksName="${aksName:?missing aksName}"
helmAppValues="${helmAppValues:?missing helmAppValues (base64)}"
helmRepo="${helmRepo:?missing helmRepo}"
helmRepoURL="${helmRepoURL:?missing helmRepoURL}"
helmAppName="${helmAppName:?missing helmAppName}"
helmApp="${helmApp:?missing helmApp}"
helmAppParams="${helmAppParams:-}"  # optional

# Wait for RBAC replication if needed
if [ "$initialDelay" != "0" ]; then
    echo "Waiting on RBAC replication ($initialDelay)s…"
    sleep "$initialDelay"
    az logout || true
    az login --identity
fi

# Fixed Helm values file in the same folder as the script
helmValuesFileName="$(dirname "$0")/helmvalues.yaml"

echo "Decoding Helm values to $helmValuesFileName..."
printf %s "$helmAppValues" | base64 -d > "$helmValuesFileName"
echo "Helm values file created and stored at $helmValuesFileName"

echo "Running Helm commands on AKS cluster '$aksName' in resource group '$RG'..."
result_json="$(
    az aks command invoke \
        -g "$RG" -n "$aksName" \
        --file "$helmValuesFileName" \
        --command "helm repo add ${helmRepo} ${helmRepoURL} && \
                   helm repo update && \
                   helm upgrade --install ${helmAppName} ${helmApp} ${helmAppParams} -f $helmValuesFileName" \
        -o json
)"

# Parse remote exit code and logs
exit_code="$(echo "$result_json" | jq -r '.status.exitCode // .exitCode // empty')"
logs="$(echo "$result_json" | jq -r '.logs // empty')"

# Output remote logs to console (portal logging)
if [ -n "$logs" ]; then
    echo "----- remote logs -----"
    echo "$logs"
    echo "------------------------"
fi

# Check for failure
if [ -z "$exit_code" ] || [ "$exit_code" -ne 0 ]; then
    prov="$(echo "$result_json" | jq -r '.status.provisioningState // .provisioningState // empty')"
    echo "Helm failed inside AKS run-command (exitCode=${exit_code:-missing}, provisioningState=${prov:-unknown})."
    exit 1
fi

# Save result to Bicep output
echo "$result_json" > "$AZ_SCRIPTS_OUTPUT_PATH"

echo "Helm deployment completed successfully!"