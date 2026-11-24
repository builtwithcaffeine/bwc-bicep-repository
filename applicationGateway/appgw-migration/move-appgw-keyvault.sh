#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Fill these in, or provide them as environment variables. Vaults must be in Azure public cloud.
SUBSCRIPTION_ID="ecba0e28-5657-4e2b-a5f5-9c3873893d3b"
RESOURCE_GROUP="rg-x-bwc-agw-shared-dev-weu"
GATEWAY_NAME="agw-bwc-shared-dev-weu-01"
OLD_KEY_VAULT="kv-bwc-kvacme-dev-weu"
NEW_KEY_VAULT="kv-bwc-acmebot-prod-weu"
NEW_MI_RESOURCE_ID="/subscriptions/ecba0e28-5657-4e2b-a5f5-9c3873893d3b/resourceGroups/rg-x-bwc-agw-shared-dev-weu/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-agw-bwc-shared-dev-weu-01"

# Set true only after reviewing any version-pinned certificates in the preview.
ALLOW_VERSION_UNPIN="${ALLOW_VERSION_UNPIN:-false}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$HOME/appgw-migration}"

section() {
    CURRENT_STEP="$1"
    printf '\n--- %s ---\n' "$CURRENT_STEP"
}
fail() {
    printf '\n[ERROR] %s\nStage: %s\n' "$*" "${CURRENT_STEP:-Configuration}" >&2
    if [[ -n "${RUN_DIR:-}" ]]; then
        printf 'Evidence directory: %s\n' "$RUN_DIR" >&2
    fi
    if [[ "${CHANGES_SUBMITTED:-false}" == true ]]; then
        printf 'A gateway update was attempted. Inspect its state before retrying; no automatic rollback was attempted.\n' >&2
    else
        printf 'No gateway changes submitted.\n' >&2
    fi
    exit 1
}
trap 'status=$?; fail "Command failed (exit $status) at line $LINENO. See the command error above."' ERR

printf '%s\n' 'Application Gateway Migration Script' 'ToolKit 1.0'

MODE="${1:---preview}"
[[ $# -le 1 && ( "$MODE" == "--preview" || "$MODE" == "--apply" ) ]] ||
    fail "Usage: bash ${0##*/} [--preview|--apply]"
section 'Script Variables'
printf '%-24s %s\n' \
    'Subscription ID:' "$SUBSCRIPTION_ID" \
    'Resource group:' "$RESOURCE_GROUP" \
    'Gateway name:' "$GATEWAY_NAME" \
    'Old Key Vault:' "$OLD_KEY_VAULT" \
    'New Key Vault:' "$NEW_KEY_VAULT" \
    'New MI resource ID:' "$NEW_MI_RESOURCE_ID" \
    'Allow version unpin:' "$ALLOW_VERSION_UNPIN" \
    'Mode:' "$MODE" \
    'Output root:' "$OUTPUT_ROOT"
printf 'Started (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
section 'Checking Script Configuration'
for tool in az jq; do
    command -v "$tool" >/dev/null || fail "Required tool missing: $tool"
done
for parameter in SUBSCRIPTION_ID RESOURCE_GROUP GATEWAY_NAME OLD_KEY_VAULT NEW_KEY_VAULT NEW_MI_RESOURCE_ID; do
    [[ -n "${!parameter}" ]] || fail "Set $parameter at the top of the script."
done
[[ "$ALLOW_VERSION_UNPIN" == true || "$ALLOW_VERSION_UNPIN" == false ]] ||
    fail "ALLOW_VERSION_UNPIN must be true or false."
OLD_KEY_VAULT="${OLD_KEY_VAULT,,}"
NEW_KEY_VAULT="${NEW_KEY_VAULT,,}"
for vault in "$OLD_KEY_VAULT" "$NEW_KEY_VAULT"; do
    [[ "$vault" =~ ^[a-z][a-z0-9-]{1,22}[a-z0-9]$ && "$vault" != *--* ]] ||
        fail "Use a Key Vault name, not a URL or resource ID: $vault"
done
[[ "$OLD_KEY_VAULT" != "$NEW_KEY_VAULT" ]] || fail "Old and new vault names must differ."
[[ "${NEW_MI_RESOURCE_ID,,}" =~ ^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft.managedidentity/userassignedidentities/[^/]+$ ]] ||
    fail "NEW_MI_RESOURCE_ID must be the full user-assigned managed identity resource ID."

mkdir -p "$OUTPUT_ROOT"
RUN_DIR="$(mktemp -d "$OUTPUT_ROOT/${GATEWAY_NAME}-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
printf 'Mode: %s\nEvidence directory: %s\n' "$MODE" "$RUN_DIR"
gateway_args=(--subscription "$SUBSCRIPTION_ID" --resource-group "$RESOURCE_GROUP" --name "$GATEWAY_NAME")

section 'Reading Application Gateway'
printf 'Reading configuration for %s (read-only)...\n' "$GATEWAY_NAME"
az network application-gateway show "${gateway_args[@]}" --only-show-errors --output json > "$RUN_DIR/before.json"
jq -e '.provisioningState == "Succeeded" and (.etag | type == "string" and length > 0)' \
    "$RUN_DIR/before.json" >/dev/null || fail "Gateway is not Succeeded or has no ETag."
jq -e '((.listeners // []) | length) == 0 and ((.routingRules // []) | length) == 0' \
    "$RUN_DIR/before.json" >/dev/null || fail "TCP/TLS listeners or L4 routing rules require a separate migration review."
identity_type="$(jq -r '.identity.type // "None" | ascii_downcase' "$RUN_DIR/before.json")"
[[ "$identity_type" == userassigned || "$identity_type" == none ]] ||
    fail "Unexpected identity type '$identity_type'; refusing to remove a system-assigned identity."
printf '[OK] Gateway provisioning state: Succeeded\nETag: %s\n' "$(jq -r '.etag' "$RUN_DIR/before.json")"

section 'Current Certs'
jq -r '
    . as $gateway |
    "Total certificate objects: \((.sslCertificates // []) | length)",
    "Key Vault references: \([.sslCertificates[]? | select((.keyVaultSecretId // "") != "")] | length)",
    "Uploaded certificates: \([.sslCertificates[]? | select((.keyVaultSecretId // "") == "")] | length)",
    (.sslCertificates[]? | . as $certificate |
        "\nCertificate: \(.name)",
        "  Type: \(if (.keyVaultSecretId // "") != "" then "Key Vault" else "Uploaded (unchanged)" end)",
        "  Current secret URI: \(.keyVaultSecretId // "Not applicable")",
        "  Attached listeners: \([$gateway.httpListeners[]? |
            select((.sslCertificate.id // "" | split("/")[-1]) == $certificate.name) | .name] |
            if length == 0 then "None" else join(", ") end)")
    ' "$RUN_DIR/before.json"

section 'Managed Identity'
printf 'Current gateway identity:\n'
jq '.identity' "$RUN_DIR/before.json"
printf 'Resolving replacement identity: %s\n' "$NEW_MI_RESOURCE_ID"

az identity show --ids "$NEW_MI_RESOURCE_ID" --only-show-errors --output json > "$RUN_DIR/new-identity.json"
NEW_MI_RESOURCE_ID="$(jq -er '.id' "$RUN_DIR/new-identity.json")"
jq -e '.principalId != null and .tenantId != null' "$RUN_DIR/new-identity.json" >/dev/null ||
    fail "Replacement identity has no principal or tenant."
printf '[OK] Replacement identity found.\nPrincipal: %s\nTenant: %s\n' \
    "$(jq -r '.principalId' "$RUN_DIR/new-identity.json")" \
    "$(jq -r '.tenantId' "$RUN_DIR/new-identity.json")"

# Resolve the destination in the gateway subscription; never read or write the source vault.
section 'Destination Key Vault'
printf 'Resolving %s in subscription %s...\n' "$NEW_KEY_VAULT" "$SUBSCRIPTION_ID"
az keyvault show --subscription "$SUBSCRIPTION_ID" --name "$NEW_KEY_VAULT" \
    --only-show-errors --output json > "$RUN_DIR/new-vault.json"
jq -e --slurpfile mi "$RUN_DIR/new-identity.json" \
    '(.properties.tenantId | ascii_downcase) == ($mi[0].tenantId | ascii_downcase)' \
    "$RUN_DIR/new-vault.json" >/dev/null || fail "Destination vault and replacement identity belong to different tenants."
[[ "$(jq -r '.properties.vaultUri | ascii_downcase' "$RUN_DIR/new-vault.json")" == "https://$NEW_KEY_VAULT.vault.azure.net/" ]] ||
    fail "Unexpected destination vault URI."
printf '[OK] Destination vault URI and identity tenant match.\n'

section 'Proposed Certificate Mappings'
jq --arg old "$OLD_KEY_VAULT" --arg new "$NEW_KEY_VAULT" '
    [(.sslCertificates // [] | to_entries[]) |
        select((.value.keyVaultSecretId // "") != "") |
        . as $entry |
        (.value.keyVaultSecretId | (try capture(
            "^https://(?<vault>[a-zA-Z0-9-]+)\\.vault\\.azure\\.net/secrets/(?<secret>[a-zA-Z0-9-]+)(/(?<version>[a-fA-F0-9]{32}))?$"
        ) catch null) // null) as $uri |
        {
            index: $entry.key, name: $entry.value.name,
            oldUri: $entry.value.keyVaultSecretId,
            secret: ($uri.secret // null),
            pinned: (($uri.version // "") != ""),
            supported: ($uri != null and (($uri.vault | ascii_downcase) == $old or ($uri.vault | ascii_downcase) == $new)),
            change: ($uri != null and ($uri.vault | ascii_downcase) == $old),
            newUri: (if $uri != null and ($uri.vault | ascii_downcase) == $old
                then "https://" + $new + ".vault.azure.net/secrets/" + $uri.secret
                else $entry.value.keyVaultSecretId end)
        }
    ]' "$RUN_DIR/before.json" > "$RUN_DIR/plan.json"

printf 'Uploaded certificates are unchanged. Destination secret names must match the source names.\n'
jq -r '.[] |
    "\nCertificate: \(.name)",
    "  Current URI: \(.oldUri)",
    "  Target URI:  \(.newUri)",
    "  Action: \(if .change then "Move reference to new vault" else "Keep existing destination reference" end)",
    "  Version-pinned: \(.pinned)"' \
    "$RUN_DIR/plan.json"
jq -e 'length > 0 and all(.[]; .supported)' "$RUN_DIR/plan.json" >/dev/null ||
    fail "No Key Vault references found, or a reference uses an unexpected vault/URI. Review plan.json."
if jq -e 'any(.[]; .change and .pinned)' "$RUN_DIR/plan.json" >/dev/null; then
    [[ "$ALLOW_VERSION_UNPIN" == true ]] ||
        fail "Moving pinned versions requires review and ALLOW_VERSION_UNPIN=true. See plan.json."
fi

# List returns metadata only, unlike secret show, which retrieves the PFX secret value.
section 'Destination Secret Validation'
printf 'Listing secret metadata, including certificate-managed secrets, from %s using YOUR login (no secret values retrieved)...\n' "$NEW_KEY_VAULT"
az keyvault secret list --vault-name "$NEW_KEY_VAULT" --subscription "$SUBSCRIPTION_ID" \
    --include-managed true --only-show-errors --output json > "$RUN_DIR/destination-secret-metadata.json"
printf 'Destination secret metadata records returned: %s\n' \
    "$(jq 'length' "$RUN_DIR/destination-secret-metadata.json")"
jq --slurpfile metadata "$RUN_DIR/destination-secret-metadata.json" '
    def epoch:
        if type == "number" then .
        elif type == "string" then sub("\\+00:00$"; "Z") | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
        else error("Unrecognized secret timestamp format") end;
    . as $plan |
    [$plan[] | . as $mapping |
        [$metadata[0][] | select((.id | split("/")[-1] | ascii_downcase) == ($mapping.secret | ascii_downcase))] as $found |
        if ($found | length) != 1 then {certificate: .name, error: "Destination secret missing or ambiguous"}
        else $found[0] as $secret |
            if $secret.attributes.enabled != true then {certificate: .name, error: "Destination secret disabled"}
            elif ($secret.contentType // "" | ascii_downcase) != "application/x-pkcs12" then
                {certificate: .name, error: "Destination secret is not marked application/x-pkcs12"}
            elif ($secret.attributes.notBefore != null and ($secret.attributes.notBefore | epoch) > now) then
                {certificate: .name, error: "Destination secret is not yet valid"}
            elif ($secret.attributes.expires != null and ($secret.attributes.expires | epoch) <= now) then
                {certificate: .name, error: "Destination secret expired"}
            elif .pinned and (.change | not) then
                {certificate: .name, error: "Already-targeted pinned version needs version-specific review"}
            else empty end
        end |
        . + {secret: $mapping.secret, targetUri: $mapping.newUri}
    ]' "$RUN_DIR/plan.json" > "$RUN_DIR/validation-errors.json"
jq -r --slurpfile errors "$RUN_DIR/validation-errors.json" '
    .[] | . as $mapping |
    [$errors[0][] | select(.certificate == $mapping.name)] as $failures |
    if ($failures | length) == 0 then
        "[OK] \(.name): destination secret enabled, PFX content type and time restrictions checked."
    else
        $failures[] |
        "[FAIL] \(.certificate): \(.error)",
        "  Expected secret name: \(.secret)",
        "  Expected target URI:  \(.targetUri)"
    end' "$RUN_DIR/plan.json"
if [[ "$(jq 'length' "$RUN_DIR/validation-errors.json")" != 0 ]]; then
    printf '\nValidation failures: %s\nDetails: %s/validation-errors.json\n' \
        "$(jq 'length' "$RUN_DIR/validation-errors.json")" "$RUN_DIR"
    printf '%s\n' \
        'Resolve the failures above before rerunning.' \
        'For a missing secret, confirm the destination vault and copy/import the certificate under the expected name.' \
        'This migration script only changes gateway references; it does not copy certificates between vaults.'
    fail "Destination metadata validation failed. No gateway changes submitted."
fi
printf '[OK] All %s gateway Key Vault references passed destination metadata checks.\n' \
    "$(jq 'length' "$RUN_DIR/plan.json")"

section 'Migration Summary'
jq -n --arg id "$NEW_MI_RESOURCE_ID" \
    '{type:"UserAssigned",userAssignedIdentities:{($id):{}}}' > "$RUN_DIR/planned-identity.json"
set_args=("identity=$(jq -c . "$RUN_DIR/planned-identity.json")")
jq -r '.[] | select(.change) | [.index, .newUri] | @tsv' \
    "$RUN_DIR/plan.json" > "$RUN_DIR/uri-updates.tsv"
while IFS=$'\t' read -r index uri; do
    set_args+=("sslCertificates[$index].keyVaultSecretId=$uri")
done < "$RUN_DIR/uri-updates.tsv"
printf '%s\n' "${set_args[@]}" > "$RUN_DIR/planned-set-arguments.txt"

printf 'Replacement identity: %s\nPrincipal: %s\n' "$NEW_MI_RESOURCE_ID" \
    "$(jq -r '.principalId' "$RUN_DIR/new-identity.json")"
printf 'Certificate references to update: %s\n' "$(jq '[.[] | select(.change)] | length' "$RUN_DIR/plan.json")"
printf '%s\n' \
    'Metadata checks use YOUR login, not the gateway MI.' \
    'Before applying, confirm the new MI has secret GET access and the gateway can reach the new vault.' \
    'Confirm the destination contains valid, exportable PFX certificates with the intended SANs.' \
    'Freeze other gateway edits during this operation; the CLI update has no atomic ETag precondition.' \
    'The saved configuration is a rollback reference, not a self-contained certificate/private-key backup.'

if [[ "$MODE" == "--preview" ]]; then
    section 'Preview Complete'
    printf '\nPREVIEW ONLY: no Azure writes. Review the evidence, then rerun with --apply.\n'
    exit 0
fi

section 'Apply Confirmation and Concurrency Check'
read -r -p "After confirming the prerequisites above, type '$GATEWAY_NAME' to apply: " confirmation
[[ "$confirmation" == "$GATEWAY_NAME" ]] || fail "Confirmation did not match; no changes submitted."
az network application-gateway show "${gateway_args[@]}" --only-show-errors --output json > "$RUN_DIR/pre-apply.json"
[[ "$(jq -r '.etag' "$RUN_DIR/before.json")" == "$(jq -r '.etag' "$RUN_DIR/pre-apply.json")" ]] ||
    fail "Gateway changed during preparation. Rerun and review a fresh preview."

# Generic update submits the replacement identity and every URI change in one gateway PUT.
section 'Applying Combined Gateway Update'
printf '\nSubmitting ONE combined gateway update. This is not a zero-downtime guarantee.\n'
CHANGES_SUBMITTED=true
if ! az network application-gateway update "${gateway_args[@]}" --set "${set_args[@]}" \
    --only-show-errors --output none; then
    fail "Gateway update failed or its outcome is unknown. Inspect provisioning state and saved evidence before retrying; no automatic rollback."
fi
section 'Post-update Verification'
az network application-gateway show "${gateway_args[@]}" --only-show-errors --output json > "$RUN_DIR/after.json"
jq -e --slurpfile before "$RUN_DIR/before.json" --slurpfile plan "$RUN_DIR/plan.json" \
    --arg mi "$NEW_MI_RESOURCE_ID" '
    . as $after |
    .provisioningState == "Succeeded" and
    (.identity.type | ascii_downcase) == "userassigned" and
    ([.identity.userAssignedIdentities | keys[] | ascii_downcase] == [$mi | ascii_downcase]) and
    ((.httpListeners // []) | map({name, sslCertificate}) | sort_by(.name)) ==
        (($before[0].httpListeners // []) | map({name, sslCertificate}) | sort_by(.name)) and
    ((.sslCertificates // []) | map(.name) | sort) == (($before[0].sslCertificates // []) | map(.name) | sort) and
    all($plan[0][]; . as $mapping |
        any($after.sslCertificates[]; .name == $mapping.name and .keyVaultSecretId == $mapping.newUri))
    ' "$RUN_DIR/after.json" >/dev/null ||
    fail "Post-update verification failed. Inspect after.json and gateway health; no automatic rollback."
printf '\nConfiguration verified: replacement MI and certificate URIs match; listener certificate bindings are unchanged.\n'
printf 'Next: check Resource Health, backend health, served TLS certificates and Key Vault retrieval diagnostics.\nEvidence: %s\n' "$RUN_DIR"
