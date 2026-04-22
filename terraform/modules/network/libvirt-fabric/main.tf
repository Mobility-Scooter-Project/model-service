# This module turns the logical network contract into actual libvirt networks.
# References:
# - libvirt network XML: https://libvirt.org/formatnetwork.html
locals {
  # Filter out disabled networks and fill in any caller-omitted gateway with
  # the first host address in the subnet. That mirrors a common "gateway is .1"
  # convention and keeps input files shorter.
  enabled_networks = {
    for network_name, network in var.networks :
    network_name => merge(network, {
      actual_name = format("%s-%s", var.name_prefix, network_name)
      gateway     = coalesce(try(network.gateway, null), cidrhost(network.cidr, 1))
    })
    if try(network.enabled, true)
  }
}

# Create one libvirt network per enabled logical network. In Kubernetes terms,
# think of these as the L2/L3 segments that your nodes will attach to before a
# CNI creates pod networking inside the guest.
resource "libvirt_network" "this" {
  for_each = local.enabled_networks
  name     = each.value.actual_name
  mode     = try(each.value.mode, "none")
  domain   = try(each.value.domain, null)

  # `addresses` defines the subnet libvirt will manage for this network.
  # Changing the CIDR here recreates the network and can invalidate leases.
  addresses = [each.value.cidr]
  autostart = true
  mtu       = each.value.mtu

  # We only omit DHCP when the caller chooses fully static addressing.
  # `dynamic` and `dhcp_reserved` both still rely on libvirt's DHCP service.
  dynamic "dhcp" {
    for_each = try(each.value.address_mode, "dynamic") == "static" ? [] : [1]
    content {
      enabled = true
    }
  }
}
