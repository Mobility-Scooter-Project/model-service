# Same naming concept as the local stack, but for future OpenStack resources.
variable "name_prefix" {
  description = "Prefix applied to future OpenStack resources."
  type        = string
  default     = "model-service"
}

# These variables intentionally mirror the local stack's input shape. That is
# the key design choice that allows us to validate the architecture locally
# before building provider-specific OpenStack resources.
variable "networks" {
  description = "Shared network contract keyed by logical network name."
  type        = map(any)
}

variable "node_pools" {
  description = "Shared node pool contract keyed by pool name."
  type        = map(any)
}

variable "cloud_init" {
  description = "Shared cloud-init contract."
  type        = any
  default     = {}
}

variable "storage" {
  description = "Shared storage contract."
  type        = any
}

variable "kubernetes_bootstrap" {
  description = "Shared Stage 2 Kubernetes bootstrap contract."
  type        = any
  default     = {}
}

variable "gpu" {
  description = "Shared GPU contract."
  type        = any
  default     = {}
}
