#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

log "repo root: ${REPO_ROOT}"
log "terraform dir: ${TF_DIR}"
log "kubeconfig: ${KUBECONFIG_PATH}"

if command -v virsh >/dev/null 2>&1; then
  printf '\n== libvirt domains ==\n'
  virsh list --all | grep "${NAME_PREFIX}" || true
fi

if [[ -f "${TF_DIR}/terraform.tfstate" ]]; then
  printf '\n== terraform outputs ==\n'
  terraform_cmd output || true
fi

if kubectl_cluster_reachable; then
  printf '\n== kubernetes nodes ==\n'
  kubectl_cmd get nodes -o wide

  printf '\n== stage3 workloads ==\n'
  kubectl_cmd get deploy,pods,svc,ingress,scaledobject -n model-service

  printf '\n== platform services ==\n'
  kubectl_cmd get pods,svc,pvc -n model-service

  printf '\n== keda core ==\n'
  kubectl_cmd get pods -n keda
else
  warn "kubectl cannot reach the cluster with ${KUBECONFIG_PATH}"
fi
