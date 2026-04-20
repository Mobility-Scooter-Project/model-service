# Used to derive the pool names that hold images and mutable node disks.
variable "name_prefix" {
  description = "Prefix used for pool names."
  type        = string
}

# Kept intentionally broad (`any`) because the root stack already validates the
# public contract. This module only cares about the fields it actually uses.
variable "storage" {
  description = "Storage configuration shared by the local libvirt stack."
  type        = any
}

# Map of expanded nodes from the root stack, keyed by logical node name.
variable "nodes" {
  description = "Per-node disk sizing and instance naming information."
  type        = map(any)
}
