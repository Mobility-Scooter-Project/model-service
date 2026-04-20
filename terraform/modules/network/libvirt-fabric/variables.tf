# Module input used to build stable libvirt object names such as
# `model-service-lab-external`.
variable "name_prefix" {
  description = "Prefix used to derive actual libvirt network names."
  type        = string
}

# The root stack passes a normalized map here rather than many individual
# variables. That keeps the local and future OpenStack contracts aligned.
variable "networks" {
  description = "Normalized network contract keyed by logical network name."
  type        = map(any)
}
