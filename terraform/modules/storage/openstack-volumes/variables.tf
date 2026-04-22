variable "name_prefix" {
  description = "Prefix retained for future OpenStack volume naming."
  type        = string
}

# This module is intentionally contract-first: the root stack already validated
# the caller shape, so we keep the child interface broad.
variable "storage" {
  description = "Shared storage contract."
  type        = any
}

variable "nodes" {
  description = "Per-node logical storage requirements."
  type        = map(any)
}
