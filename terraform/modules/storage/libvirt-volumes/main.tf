# This module manages two storage concerns:
# 1. immutable base images used to clone root disks
# 2. mutable per-node disks used for runtime state or model caches
# Reference: https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/pool
locals {
  image_pool_name  = format("%s-images", var.name_prefix)
  volume_pool_name = format("%s-volumes", var.name_prefix)
}

# The image pool stores reusable "golden images". You should rarely delete this
# between runs because downloading cloud images repeatedly is slow.
resource "libvirt_pool" "images" {
  name = local.image_pool_name
  type = "dir"

  # Newer provider versions prefer `target.path` over the older top-level `path`
  # argument, so we use the modern shape to avoid deprecation warnings.
  target {
    path = var.storage.image_store_path
  }
}

# The volume pool stores mutable disks that belong to individual nodes.
resource "libvirt_pool" "volumes" {
  name = local.volume_pool_name
  type = "dir"

  target {
    path = var.storage.volume_store_path
  }
}

# Download or reference the base cloud image once. Root disks clone from this.
resource "libvirt_volume" "base_image" {
  name   = var.storage.base_image_name
  pool   = libvirt_pool.images.name
  source = var.storage.base_image_source
  format = "qcow2"
}

# Create one root disk per node. These are cloned from the base image so each
# VM starts with the same operating system but has its own writable disk.
resource "libvirt_volume" "root" {
  for_each       = var.nodes
  name           = format("%s-root.qcow2", each.value.instance_name)
  pool           = libvirt_pool.volumes.name
  base_volume_id = libvirt_volume.base_image.id
  format         = "qcow2"

  # The provider expects bytes, not GiB, so we convert here.
  size = each.value.root_disk_gb * 1024 * 1024 * 1024
}

# Default behavior: create data disks that Terraform is allowed to destroy.
resource "libvirt_volume" "data" {
  for_each = try(var.storage.retain_on_destroy, false) ? {} : var.nodes
  name     = format("%s-data.qcow2", each.value.instance_name)
  pool     = libvirt_pool.volumes.name
  format   = "qcow2"
  size     = each.value.data_disk_gb * 1024 * 1024 * 1024
}

# Optional retained behavior: keep data disks even if the stack is destroyed.
# This is useful for debugging or preserving large model caches, but it also
# means operators must manually clean up old disks to avoid state drift.
resource "libvirt_volume" "data_retained" {
  for_each = try(var.storage.retain_on_destroy, false) ? var.nodes : {}
  name     = format("%s-data.qcow2", each.value.instance_name)
  pool     = libvirt_pool.volumes.name
  format   = "qcow2"
  size     = each.value.data_disk_gb * 1024 * 1024 * 1024

  lifecycle {
    prevent_destroy = true
  }
}
