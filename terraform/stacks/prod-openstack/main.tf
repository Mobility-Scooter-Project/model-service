# This stack is intentionally a contract scaffold, not a live OpenStack
# implementation yet. Its job is to prove that the local and production-shaped
# stacks can share the same logical inputs and outputs.
locals {
  # Expand node pools into concrete node names so the placeholder outputs look
  # like the local stack outputs readers already understand.
  nodes = merge(
    {},
    [
      for pool_name, pool in var.node_pools : {
        for index in range(pool.count) :
        format("%s-%02d", replace(pool_name, "_", "-"), index + 1) => {
          node_key      = format("%s-%02d", replace(pool_name, "_", "-"), index + 1)
          hostname      = format("%s-%02d", replace(pool_name, "_", "-"), index + 1)
          instance_name = format("%s-%s-%02d", var.name_prefix, replace(pool_name, "_", "-"), index + 1)
          pool_name     = pool_name
          vcpu          = pool.vcpu
          memory_mb     = pool.memory_mb
          root_disk_gb  = coalesce(try(pool.root_disk_gb, null), try(var.storage.default_root_disk_gb, 30))
          data_disk_gb  = coalesce(try(pool.data_disk_gb, null), try(var.storage.default_data_disk_gb, 80))
          networks      = pool.networks
          labels        = try(pool.labels, {})
          gpu_enabled   = try(pool.gpu_enabled, false)
          nic_overrides = {}
        }
      }
    ]...
  )

  # Regroup nodes by pool because the placeholder compute module, like the real
  # local one, operates one pool at a time.
  pool_nodes = {
    for pool_name, pool in var.node_pools :
    pool_name => {
      for node_key, node in local.nodes :
      node_key => node if node.pool_name == pool_name
    }
    if pool.count > 0
  }
}

# Planned network mapping for a future Neutron implementation.
module "network" {
  source      = "../../modules/network/openstack-fabric"
  name_prefix = var.name_prefix
  networks    = var.networks
}

# Planned storage mapping for a future Cinder implementation.
module "storage" {
  source      = "../../modules/storage/openstack-volumes"
  name_prefix = var.name_prefix
  storage     = var.storage
  nodes = {
    for node_key, node in local.nodes :
    node_key => {
      instance_name = node.instance_name
      root_disk_gb  = node.root_disk_gb
      data_disk_gb  = node.data_disk_gb
    }
  }
}

# Planned compute mapping for a future Nova implementation.
module "compute" {
  for_each            = local.pool_nodes
  source              = "../../modules/compute/openstack-node-pool"
  pool_name           = each.key
  nodes               = each.value
  network_definitions = var.networks
  cloud_init          = var.cloud_init
  gpu                 = var.gpu
}

# Flatten the per-pool placeholder outputs into one map, matching the local
# stack's output shape as closely as possible.
locals {
  instances = merge(
    {},
    [for compute_pool in values(module.compute) : compute_pool.instances]...
  )
}
