#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd terraform

if kubectl_cluster_reachable; then
  log "uninstalling model releases from the live cluster"
  helm_cmd uninstall whisperx --namespace model-service >/dev/null 2>&1 || true
  helm_cmd uninstall yolo --namespace model-service >/dev/null 2>&1 || true
  kubectl_cmd delete -k "${STAGE3_PLATFORM_DIR}" --ignore-not-found >/dev/null 2>&1 || true
else
  warn "kubectl cannot reach the cluster; skipping Kubernetes cleanup"
fi

log "initializing Terraform in ${TF_DIR}"
terraform_cmd init -input=false >/dev/null

log "destroying local libvirt stack"
terraform_cmd destroy -auto-approve || warn "terraform destroy reported an error; continuing with libvirt cleanup"

cleanup_prefixed_domains
cleanup_prefixed_networks
cleanup_prefixed_pools

cat <<EOF

Cluster teardown complete.

- terraform stack: ${TF_DIR}
- kubeconfig left in place: ${KUBECONFIG_PATH}

If you recreate immediately, the scripts will refresh the kubeconfig and ignore
SSH host-key churn automatically.
EOF
