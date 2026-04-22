# Return an operator-friendly summary of what this pool created. This avoids
# making readers inspect raw libvirt state to answer basic questions like:
# - which VM belongs to which pool?
# - which MAC did Terraform assign?
# - which disk IDs belong to the VM?
output "instances" {
  description = "Per-node VM outputs for this node pool."
  value = {
    for node_key, node in var.nodes :
    node_key => {
      id        = libvirt_domain.this[node_key].id
      name      = libvirt_domain.this[node_key].name
      pool_name = var.pool_name
      labels    = node.labels
      cloud_init = {
        id   = libvirt_cloudinit_disk.this[node_key].id
        name = libvirt_cloudinit_disk.this[node_key].name
      }
      network_interfaces = {
        for index, iface in local.node_interfaces[node_key] :
        iface.network_name => {
          address_mode       = iface.address_mode
          mac                = iface.mac
          desired_ip         = iface.ip
          reported_addresses = try(libvirt_domain.this[node_key].network_interface[index].addresses, [])
        }
      }
      volumes = {
        root_volume_id = var.root_volume_ids[node_key]
        data_volume_id = var.data_volume_ids[node_key]
      }
      bootstrap = {
        enabled            = try(var.kubernetes_bootstrap.enabled, false)
        role               = var.pool_name == "control_plane" ? "server" : "agent"
        data_disk_id       = node.data_disk_id
        cluster_interface  = try(local.cluster_interface_name[node_key], null)
        control_plane_node = var.pool_name == "control_plane"
      }
    }
  }
}
