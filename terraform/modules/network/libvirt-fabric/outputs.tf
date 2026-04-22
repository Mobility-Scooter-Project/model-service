# Return the same logical structure the caller passed in, but enriched with the
# actual libvirt IDs and names Terraform created. That makes downstream modules
# simpler because they can key everything by the same logical names.
output "networks" {
  description = "Logical network outputs with actual libvirt names and contract metadata."
  value = {
    for network_name, network in var.networks :
    network_name => merge(network, {
      id           = try(libvirt_network.this[network_name].id, null)
      name         = try(libvirt_network.this[network_name].name, format("%s-%s", var.name_prefix, network_name))
      logical_name = network_name
      gateway      = coalesce(try(network.gateway, null), cidrhost(network.cidr, 1))
      enabled      = try(network.enabled, true)
    })
  }
}
