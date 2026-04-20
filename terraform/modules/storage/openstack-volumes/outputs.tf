# Matches the local storage module conceptually, but keeps values as planned
# placeholders until real OpenStack resources exist.
output "volumes" {
  description = "Planned OpenStack volume contract keyed by logical node name."
  value       = local.planned_volumes
}
