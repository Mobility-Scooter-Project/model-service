# Export pool names so other modules know where cloned disks and cloud-init ISOs
# should be stored.
output "image_pool_name" {
  description = "Name of the libvirt pool that stores immutable base images."
  value       = libvirt_pool.images.name
}

output "volume_pool_name" {
  description = "Name of the libvirt pool that stores node-attached boot, data, and cloud-init disks."
  value       = libvirt_pool.volumes.name
}

# Useful when debugging image clone issues or confirming which base image a lab
# was built from.
output "base_image_volume_id" {
  description = "ID of the base image volume cloned for root disks."
  value       = libvirt_volume.base_image.id
}

# Root disks are always present, so this is a straightforward map.
output "root_volume_ids" {
  description = "Per-node root volume IDs."
  value = {
    for node_key, volume in libvirt_volume.root :
    node_key => volume.id
  }
}

# Data disks may come from either destroyable or retained resources, so we merge
# both maps into one uniform output for callers.
output "data_volume_ids" {
  description = "Per-node data volume IDs."
  value = merge(
    {
      for node_key, volume in libvirt_volume.data :
      node_key => volume.id
    },
    {
      for node_key, volume in libvirt_volume.data_retained :
      node_key => volume.id
    }
  )
}

# This output is shaped like an attachment table because that is usually how an
# operator thinks about disks while debugging a VM.
output "volume_attachments" {
  description = "Per-node logical attachment mapping for boot and data disks."
  value = {
    for node_key, node in var.nodes :
    node_key => {
      root_volume_id = libvirt_volume.root[node_key].id
      data_volume_id = try(libvirt_volume.data[node_key].id, libvirt_volume.data_retained[node_key].id)
    }
  }
}
