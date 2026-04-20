variable "pool_name" {
  description = "Logical name of the node pool."
  type        = string
}

variable "nodes" {
  description = "Per-node compute contract."
  type        = map(any)
}

variable "network_definitions" {
  description = "Logical network definitions keyed by network name."
  type        = map(any)
}

variable "cloud_init" {
  description = "Shared cloud-init contract."
  type        = any
}

variable "gpu" {
  description = "Shared GPU contract."
  type        = any
}
