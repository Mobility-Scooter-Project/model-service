# Surface the full network contract after module normalization. This is useful
# when operators want to confirm the actual libvirt network names Terraform
# created versus the logical names used in the input file.
output "networks" {
  description = "Normalized network outputs for the local libvirt fabric."
  value       = module.network.networks
}

# Expose storage outputs separately because attached disks are often the first
# thing people inspect when a VM lab behaves differently from expectations.
output "storage" {
  description = "Storage pool and attachment contract for the local libvirt lab."
  value = {
    image_pool_name      = module.storage.image_pool_name
    volume_pool_name     = module.storage.volume_pool_name
    base_image_volume_id = module.storage.base_image_volume_id
    root_volume_ids      = module.storage.root_volume_ids
    data_volume_ids      = module.storage.data_volume_ids
    volume_attachments   = module.storage.volume_attachments
  }
}

# `instances` is the most operator-friendly output in this stack. It summarizes
# which VMs exist, how Terraform thinks they are wired, and which cloud-init ISO
# and disks belong to each one.
output "instances" {
  description = "Per-node instance outputs, including rendered cloud-init artifacts and desired IP contracts."
  value       = local.instances
}
