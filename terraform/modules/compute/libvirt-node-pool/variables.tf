# Shared prefix from the root stack, used only for naming fallbacks.
variable "name_prefix" {
  description = "Resource prefix carried through from the root stack."
  type        = string
}

# Human-readable pool name such as `control_plane` or `workers_cpu`.
variable "pool_name" {
  description = "Logical name of the node pool being provisioned."
  type        = string
}

# Hypervisor mode selected by the caller. See the root variable docs for how
# `kvm` and `qemu` differ in speed and host requirements.
variable "domain_type" {
  description = "Libvirt domain type."
  type        = string
}

# Expanded node map from the root stack. Each key is a concrete node such as
# `workers-cpu-02`.
variable "nodes" {
  description = "Per-node compute, network, and cloud-init overrides."
  type        = map(any)
}

# Provider-agnostic cloud-init contract. This module renders it into a NoCloud
# ISO because libvirt expects local disk-style bootstrap data.
variable "cloud_init" {
  description = "Provider-agnostic cloud-init contract."
  type        = any
}

# Pool name where generated cloud-init seed ISOs are stored.
variable "cloud_init_pool_name" {
  description = "Libvirt storage pool that will store generated cloud-init ISOs."
  type        = string
}

# Logical network contract and realized network objects are passed separately:
# - definitions: policy and desired behavior
# - resources: actual libvirt IDs/names created by the network module
variable "network_definitions" {
  description = "Logical network definitions keyed by network name."
  type        = map(any)
}

variable "network_resources" {
  description = "Provisioned network resources keyed by logical network name."
  type        = map(any)
}

# Root and data disk IDs are created in the storage module and attached here.
variable "root_volume_ids" {
  description = "Root volume IDs keyed by logical node name."
  type        = map(string)
}

variable "data_volume_ids" {
  description = "Data volume IDs keyed by logical node name."
  type        = map(string)
}

# Stage 2 bootstrap contract for the local Kubernetes lab. This stays separate
# from the generic `cloud_init` object because it models intent, not transport.
variable "kubernetes_bootstrap" {
  description = "Stage 2 Kubernetes bootstrap contract."
  type        = any
}

# Local-only passthrough extension. This is intentionally loose because the
# caller-side validation already happened in the root stack.
variable "gpu" {
  description = "Local-only GPU extension for experimental PCI passthrough."
  type        = any
}
