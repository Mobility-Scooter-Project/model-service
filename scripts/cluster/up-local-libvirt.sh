#!/usr/bin/env bash

# thank you chat

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd terraform kubectl helm ssh sed

log "initializing Terraform in ${TF_DIR}"
terraform_cmd init -input=false >/dev/null

log "applying local libvirt stack"
terraform_cmd apply -auto-approve

CONTROL_PLANE_IP="$(control_plane_ip)"
CONTROL_PLANE_CLUSTER_IP="$(control_plane_cluster_ip)"
WORKER_IP="$(worker_ip)"

log "waiting for SSH on control plane ${CONTROL_PLANE_IP}"
wait_for_ssh "${CONTROL_PLANE_IP}" "control-plane-01"
log "waiting for SSH on worker ${WORKER_IP}"
wait_for_ssh "${WORKER_IP}" "workers-cpu-01"

wait_for_cloud_init "${CONTROL_PLANE_IP}" "control-plane-01"
wait_for_cloud_init "${WORKER_IP}" "workers-cpu-01"

log "verifying k3s services"
ssh_vm "${CONTROL_PLANE_IP}" "sudo systemctl is-active k3s >/dev/null"
ssh_vm "${WORKER_IP}" "sudo systemctl is-active k3s-agent >/dev/null"

log "refreshing kubeconfig at ${KUBECONFIG_PATH}"
refresh_kubeconfig "${CONTROL_PLANE_IP}" "${CONTROL_PLANE_CLUSTER_IP}"

wait_for_nodes_ready

log "applying Stage 3 platform"
kubectl_cmd apply -k "${STAGE3_PLATFORM_DIR}"
wait_for_stage3_platform

configure_runtime_secrets
configure_optional_whisperx_secret

YOLO_VALUES_FILE="${YOLO_VALUES_FILE:-$(best_yolo_values_file)}"
log "installing yolo Helm release with ${YOLO_VALUES_FILE}"
helm_cmd upgrade --install yolo "${STAGE3_CHART_DIR}" \
  --namespace model-service \
  -f "${YOLO_VALUES_FILE}"
kubectl_cmd rollout status deployment/yolo -n model-service --timeout=10m

log "final cluster summary"
kubectl_cmd get nodes -o wide
kubectl_cmd get pods -n model-service
kubectl_cmd get deploy,svc,ingress,scaledobject -n model-service

cat <<EOF

Cluster is ready.

- kubeconfig: ${KUBECONFIG_PATH}
- control plane: ${CONTROL_PLANE_IP}
- worker: ${WORKER_IP}
- yolo job file: ${REPO_ROOT}/http/yolo/predict.http

The yolo API deployment should stay at 1 replica, while the yolo worker
deployment should sit at 0 replicas until the first job arrives.
If you want private image pulls instead of public-image mode, rerun with
GHCR_USERNAME and GHCR_PASSWORD set in the environment.
EOF
