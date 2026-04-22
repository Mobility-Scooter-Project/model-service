# This module does not create real resources yet. Instead, it returns the shape
# we expect a later Neutron-backed implementation to produce.
locals {
  networks = {
    for network_name, network in var.networks :
    network_name => merge(network, {
      id           = null
      logical_name = network_name
      name         = format("%s-%s", var.name_prefix, network_name)
      provider     = "openstack"
      status       = "planned"
      gateway      = coalesce(try(network.gateway, null), cidrhost(network.cidr, 1))
    })
  }
}
