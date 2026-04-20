# Kept aligned with the local network module so callers can reuse the same
# contract across local and future production-shaped stacks.
variable "name_prefix" {
  description = "Prefix retained for future OpenStack resource naming."
  type        = string
}

variable "networks" {
  description = "Shared network contract keyed by logical network name."
  type        = map(any)
}
