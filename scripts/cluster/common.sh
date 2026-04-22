#!/usr/bin/env bash

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${COMMON_DIR}/../.." && pwd)"

TF_DIR="${TF_DIR:-${REPO_ROOT}/terraform/stacks/local-libvirt}"
TFVARS_PATH="${TFVARS_PATH:-${TF_DIR}/terraform.tfvars}"
STAGE3_PLATFORM_DIR="${STAGE3_PLATFORM_DIR:-${REPO_ROOT}/deploy/stage3/platform}"
STAGE3_CHART_DIR="${STAGE3_CHART_DIR:-${REPO_ROOT}/deploy/charts/model-service-stage3}"

KUBECONFIG_PATH="${KUBECONFIG_PATH:-${HOME}/.kube/model-service-lab.yaml}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/model-service-lab}"
NAME_PREFIX="${NAME_PREFIX:-model-service-lab}"

DEFAULT_CONTROL_PLANE_IP="${DEFAULT_CONTROL_PLANE_IP:-192.168.124.10}"
DEFAULT_WORKER_IP="${DEFAULT_WORKER_IP:-192.168.124.11}"

read_tfvars_string() {
  local key="$1"
  local fallback="$2"

  if [[ -f "${TFVARS_PATH}" ]]; then
    local value
    value="$(sed -nE "s/^${key}[[:space:]]*=[[:space:]]*\"([^\"]+)\"/\1/p" "${TFVARS_PATH}" | head -n1)"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi

  printf '%s\n' "${fallback}"
}

NAME_PREFIX="$(read_tfvars_string "name_prefix" "${NAME_PREFIX}")"

log() {
  printf '[cluster] %s\n' "$*"
}

warn() {
  printf '[cluster] warning: %s\n' "$*" >&2
}

die() {
  printf '[cluster] error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "missing required command: ${cmd}"
  done
}

ssh_opts=(
  -i "${SSH_KEY_PATH}"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

ssh_vm() {
  local host="$1"
  shift
  ssh "${ssh_opts[@]}" "${SSH_USER}@${host}" "$@"
}

kubectl_cmd() {
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl "$@"
}

helm_cmd() {
  KUBECONFIG="${KUBECONFIG_PATH}" helm "$@"
}

terraform_cmd() {
  terraform -chdir="${TF_DIR}" "$@"
}

kubectl_cluster_reachable() {
  [[ -f "${KUBECONFIG_PATH}" ]] && kubectl_cmd version --request-timeout=10s >/dev/null 2>&1
}

terraform_output_instance_ip() {
  local instance_name="$1"
  local network_name="$2"
  local fallback="$3"

  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "${fallback}"
    return 0
  fi

  TF_DIR_FOR_PY="${TF_DIR}" python3 - "${instance_name}" "${network_name}" "${fallback}" <<'PY'
import json
import os
import subprocess
import sys

instance_name = sys.argv[1]
network_name = sys.argv[2]
fallback = sys.argv[3]
tf_dir = os.environ["TF_DIR_FOR_PY"]

try:
    raw = subprocess.check_output(
        ["terraform", f"-chdir={tf_dir}", "output", "-json", "instances"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    instances = json.loads(raw)
    print(instances[instance_name]["network_interfaces"][network_name]["desired_ip"])
except Exception:
    print(fallback)
PY
}

control_plane_ip() {
  terraform_output_instance_ip "control-plane-01" "external" "${CONTROL_PLANE_IP:-${DEFAULT_CONTROL_PLANE_IP}}"
}

control_plane_cluster_ip() {
  terraform_output_instance_ip "control-plane-01" "cluster" "10.42.0.10"
}

worker_ip() {
  terraform_output_instance_ip "workers-cpu-01" "external" "${WORKER_IP:-${DEFAULT_WORKER_IP}}"
}

wait_for_ssh() {
  local host="$1"
  local label="$2"
  local max_attempts="${3:-120}"
  local attempt=1

  until ssh_vm "${host}" "true" >/dev/null 2>&1; do
    if (( attempt >= max_attempts )); then
      die "timed out waiting for SSH on ${label} (${host})"
    fi
    sleep 5
    attempt=$((attempt + 1))
  done
}

wait_for_cloud_init() {
  local host="$1"
  local label="$2"
  log "waiting for cloud-init on ${label}"
  ssh_vm "${host}" "cloud-init status --wait >/dev/null"
}

refresh_kubeconfig() {
  local ssh_host="$1"
  local server_endpoint="$2"

  mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
  ssh_vm "${ssh_host}" "sudo cat /etc/rancher/k3s/k3s.yaml" \
    | sed "s/127.0.0.1/${server_endpoint}/" \
    > "${KUBECONFIG_PATH}"
  chmod 600 "${KUBECONFIG_PATH}"
}

wait_for_nodes_ready() {
  log "waiting for Kubernetes nodes to become Ready"
  kubectl_cmd wait --for=condition=Ready node --all --timeout=15m
}

wait_for_deployment() {
  local namespace="$1"
  local name="$2"
  local timeout_seconds="${3:-600}"
  local elapsed=0

  while ! kubectl_cmd get deployment "${name}" -n "${namespace}" >/dev/null 2>&1; do
    if (( elapsed >= timeout_seconds )); then
      die "timed out waiting for deployment/${name} to appear in namespace ${namespace}"
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

wait_for_stage3_platform() {
  log "waiting for Traefik, Redis, MinIO, and KEDA core"
  wait_for_deployment kube-system traefik 900
  kubectl_cmd rollout status deployment/traefik -n kube-system --timeout=10m
  kubectl_cmd rollout status deployment/keda-operator -n keda --timeout=10m
  kubectl_cmd rollout status deployment/redis -n model-service --timeout=10m
  kubectl_cmd rollout status deployment/minio -n model-service --timeout=10m
}

best_yolo_values_file() {
  local local_file="${REPO_ROOT}/deploy/stage3/values/yolo.values.local.yaml"
  local example_file="${REPO_ROOT}/deploy/stage3/values/yolo.values.yaml.example"

  if [[ -f "${local_file}" ]]; then
    printf '%s\n' "${local_file}"
  else
    printf '%s\n' "${example_file}"
  fi
}

configure_runtime_secrets() {
  if [[ -n "${GHCR_USERNAME:-}" && -n "${GHCR_PASSWORD:-}" ]]; then
    log "creating GHCR pull secret in model-service namespace"
    kubectl_cmd create secret docker-registry ghcr-pull-secret \
      --namespace model-service \
      --docker-server=ghcr.io \
      --docker-username="${GHCR_USERNAME}" \
      --docker-password="${GHCR_PASSWORD}" \
      --dry-run=client \
      -o yaml \
      | kubectl_cmd apply -f -
    return 0
  fi

  log "public image mode: clearing imagePullSecrets on model-service-runtime"
  kubectl_cmd patch serviceaccount model-service-runtime \
    -n model-service \
    --type=merge \
    -p '{"imagePullSecrets":[]}'
}

configure_optional_whisperx_secret() {
  if [[ -z "${HF_TOKEN:-}" ]]; then
    return 0
  fi

  log "creating whisperx-env secret in model-service namespace"
  kubectl_cmd create secret generic whisperx-env \
    --namespace model-service \
    --from-literal="HF_TOKEN=${HF_TOKEN}" \
    --dry-run=client \
    -o yaml \
    | kubectl_cmd apply -f -
}

cleanup_prefixed_domains() {
  command -v virsh >/dev/null 2>&1 || return 0

  local domains
  domains="$(virsh list --all --name | grep "^${NAME_PREFIX}-" || true)"
  [[ -n "${domains}" ]] || return 0

  log "cleaning up leftover libvirt domains for ${NAME_PREFIX}"
  while IFS= read -r domain; do
    [[ -n "${domain}" ]] || continue
    if virsh domstate "${domain}" 2>/dev/null | grep -qv "shut off"; then
      virsh destroy "${domain}" >/dev/null 2>&1 || true
    fi
    virsh undefine --nvram "${domain}" >/dev/null 2>&1 || virsh undefine "${domain}" >/dev/null 2>&1 || true
  done <<< "${domains}"
}

cleanup_prefixed_networks() {
  command -v virsh >/dev/null 2>&1 || return 0

  local networks
  networks="$(virsh net-list --all --name | grep "^${NAME_PREFIX}-" || true)"
  [[ -n "${networks}" ]] || return 0

  log "cleaning up leftover libvirt networks for ${NAME_PREFIX}"
  while IFS= read -r network; do
    [[ -n "${network}" ]] || continue
    virsh net-destroy "${network}" >/dev/null 2>&1 || true
    virsh net-undefine "${network}" >/dev/null 2>&1 || true
  done <<< "${networks}"
}

cleanup_prefixed_pools() {
  command -v virsh >/dev/null 2>&1 || return 0

  local pools
  pools="$(virsh pool-list --all --name | grep "^${NAME_PREFIX}-" || true)"
  [[ -n "${pools}" ]] || return 0

  log "cleaning up leftover libvirt pools for ${NAME_PREFIX}"
  while IFS= read -r pool; do
    [[ -n "${pool}" ]] || continue
    virsh pool-destroy "${pool}" >/dev/null 2>&1 || true
    virsh pool-undefine "${pool}" >/dev/null 2>&1 || true
  done <<< "${pools}"
}
