# Output shape stays similar to the local compute module so downstream tooling
# can grow toward OpenStack incrementally instead of all at once.
output "instances" {
  description = "Planned OpenStack instances for this node pool."
  value       = local.instances
}
