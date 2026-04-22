# The output shape matches the local module closely so downstream code can stay
# provider-agnostic for as long as possible.
output "networks" {
  description = "Planned OpenStack network mapping for the shared contract."
  value       = local.networks
}
