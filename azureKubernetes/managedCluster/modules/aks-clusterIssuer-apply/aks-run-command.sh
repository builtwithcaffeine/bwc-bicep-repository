#!/bin/bash

set -e +H
# -e to exit on error
# +H to prevent history expansion

# Set the script's locale to UTF-8 to ensure proper handling of UTF-8 encoded text
export LANG=C.UTF-8

if [ "$initialDelay" != "0" ]
then
    echo "Waiting on RBAC replication ($initialDelay)"
    sleep $initialDelay

    #Force RBAC refresh
    az logout
    az login --identity
fi

# Define the filename for the Kubernetes manifest
kubeManifestFile="$(dirname "$0")/kubemanifest.yaml"

echo "Creating Kubernetes manifest file..."
echo -n $kubeManifest | base64 -d > $kubeManifestFile

# Replace <managedIdentityClientId> placeholder with the actual $aksManagedId in the manifest file
sed -i "s|managedIdentityClientId|$aksManagedId|g" "$kubeManifestFile"
echo "Kubernetes manifest file created and stored at $kubeManifestFile with the managed ID updated."

echo "Sending command to AKS Cluster $aksName in $RG"
cmdOut=$(az aks command invoke -g $RG -n $aksName  --command "kubectl apply -f $kubeManifestFile" --file $kubeManifestFile -o json)
echo $cmdOut

jsonOutputString=$cmdOut
echo $jsonOutputString > $AZ_SCRIPTS_OUTPUT_PATH
