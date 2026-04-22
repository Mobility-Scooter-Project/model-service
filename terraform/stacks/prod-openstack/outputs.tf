# Output shapes intentionally mirror the local stack, but values stay "planned"
# or `null` until a real OpenStack provider implementation is added.
output "networks" {
  description = "Planned OpenStack network mapping for the shared contract."
  value       = module.network.networks
}

output "volumes" {
  description = "Planned OpenStack storage mapping for the shared contract."
  value       = module.storage.volumes
}

output "instances" {
  description = "Planned OpenStack compute mapping for the shared contract."
  value       = local.instances
}
