# Placeholder mapping for a future Cinder implementation. The main purpose is
# to preserve naming, sizing, and retain/destroy intent in the output contract.
locals {
  planned_volumes = {
    for node_key, node in var.nodes :
    node_key => {
      root = {
        id      = null
        name    = format("%s-root", node.instance_name)
        size_gb = node.root_disk_gb
        source  = var.storage.base_image_name
        status  = "planned"
      }
      data = {
        id      = null
        name    = format("%s-data", node.instance_name)
        size_gb = node.data_disk_gb
        retain  = try(var.storage.retain_on_destroy, false)
        status  = "planned"
      }
    }
  }
}
