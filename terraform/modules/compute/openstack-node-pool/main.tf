# Placeholder mapping for a future Nova implementation. This module does not
# create instances yet; it records how we expect compute intent to translate.
locals {
  instances = {
    for node_key, node in var.nodes :
    node_key => {
      id        = null
      name      = node.instance_name
      pool_name = var.pool_name
      status    = "planned"
      fixed_ips = {
        for network_name in node.networks :
        network_name => {
          address_mode = try(var.network_definitions[network_name].address_mode, "dynamic")
          ip           = try(node.nic_overrides[network_name].ip, null) != null ? try(node.nic_overrides[network_name].ip, null) : try(var.network_definitions[network_name].reservations[node_key].ip, null)
        }
      }
      cloud_init = {
        template_path = try(var.cloud_init.template_path, null)
        user_data     = try(var.cloud_init.user_data, null)
      }
      gpu = {
        enabled = try(node.gpu_enabled, false)
        mode    = try(var.gpu.mode, "disabled")
      }
    }
  }
}
