#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [create|destroy|help]"
  echo "Env: RESOURCE_GROUP=cf-rdp-vm-tfstate-rg LOCATION=eastus CONTAINER_NAME=tfstate STORAGE_ACCOUNT=<auto>"
}

cmd="${1:-create}"
if [[ "${cmd}" == "help" || "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
  usage
  exit 0
fi

RESOURCE_GROUP="${RESOURCE_GROUP:-cf-rdp-vm-tfstate-rg}"
LOCATION="${LOCATION:-eastus}"
CONTAINER_NAME="${CONTAINER_NAME:-tfstate}"

case "${cmd}" in
  create)
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
      STORAGE_ACCOUNT="cfrdpvmtfstate$(openssl rand -hex 4)"
    fi
    SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
    USER_OBJECT_ID="$(az ad signed-in-user show --query id -o tsv)"
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"

    az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}"

    az storage account create --name "${STORAGE_ACCOUNT}" \
      --resource-group "${RESOURCE_GROUP}" --location "${LOCATION}" \
      --sku Standard_LRS --kind StorageV2

    az role assignment create --assignee "${USER_OBJECT_ID}" \
      --role "Storage Blob Data Contributor" --scope "${SCOPE}"

    az storage container create --name "${CONTAINER_NAME}" \
      --account-name "${STORAGE_ACCOUNT}" --auth-mode login
    ;;
  destroy|delete|cleanup)
    if [[ "$(az group exists --name "${RESOURCE_GROUP}")" == "true" ]]; then
      az group delete --name "${RESOURCE_GROUP}" --yes
    fi
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage
    exit 1
    ;;
esac