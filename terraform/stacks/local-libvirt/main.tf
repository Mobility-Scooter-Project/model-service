# Configure the provider once at the root so child modules inherit the same
# libvirt connection. Changing `var.libvirt_uri` here changes the whole stack.
provider "libvirt" {
  uri = var.libvirt_uri
}

# `locals` lets us normalize caller input into shapes that are easier for the
# modules below to consume. Think of this block as the stack's "compiler pass".
locals {
  # Fallback cloud-init template used when the caller does not provide one.
  default_cloud_init_template_path = abspath("${path.module}/templates/default-user-data.tftpl")

  # Stage 2 treats the first control-plane node as the stable cluster join
  # target. These locals centralize the naming so later checks and templates do
  # not repeat stringly-typed assumptions.
  cluster_network_name         = try(var.kubernetes_bootstrap.cluster_network_name, "cluster")
  storage_network_name         = try(var.kubernetes_bootstrap.storage_network_name, "storage")
  first_control_plane_node_key = "control-plane-01"

  # Normalize the shared cloud-init contract into a single object so downstream
  # modules do not need to keep checking "did the caller set this?".
  cloud_init_for_modules = {
    template_path       = try(var.cloud_init.template_path, null) != null ? abspath(var.cloud_init.template_path) : local.default_cloud_init_template_path
    template_vars       = try(var.cloud_init.template_vars, {})
    user_data           = try(var.cloud_init.user_data, null)
    ssh_authorized_keys = try(var.cloud_init.ssh_authorized_keys, [])
    meta_data           = try(var.cloud_init.meta_data, {})
    network_config      = try(var.cloud_init.network_config, null)
  }

  # Expand each logical pool into concrete nodes like `workers-cpu-01`.
  # This is where "pool intent" turns into actual VM definitions.
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
          root_disk_gb  = coalesce(try(pool.root_disk_gb, null), var.storage.default_root_disk_gb)
          data_disk_gb  = coalesce(try(pool.data_disk_gb, null), var.storage.default_data_disk_gb)
          networks      = pool.networks
          labels        = try(pool.labels, {})
          gpu_enabled   = try(pool.gpu_enabled, false)
          nic_overrides = try(pool.node_overrides[format("%s-%02d", replace(pool_name, "_", "-"), index + 1)].nics, {})
          cloud_init    = try(pool.node_overrides[format("%s-%02d", replace(pool_name, "_", "-"), index + 1)].cloud_init, null)
          data_disk_id  = format("msd-%s", substr(md5(format("%s-%02d", replace(pool_name, "_", "-"), index + 1)), 0, 16))
        }
      }
    ]...
  )

  # Stable ordering makes the auto-generated compatibility IPs deterministic.
  ordered_node_keys = sort(keys(local.nodes))

  # WSL2 hosts often struggle to deliver libvirt DHCP traffic into the guest.
  # When compatibility mode is enabled, assign explicit guest IPs so cloud-init
  # can configure every NIC without waiting for libvirt DHCP or reservations.
  generated_static_reservations = {
    for network_name, network in var.networks :
    network_name => {
      for index, node_key in local.ordered_node_keys :
      node_key => {
        ip       = cidrhost(network.cidr, index + 10)
        hostname = local.nodes[node_key].hostname
      }
    }
  }

  # Keep the caller-facing network contract intact, but optionally rewrite it
  # into a static-addressing shape that is friendlier to WSL2/libvirt.
  effective_networks = {
    for network_name, network in var.networks :
    network_name => merge(network, {
      address_mode   = var.wsl2_compatibility_mode ? "static" : try(network.address_mode, "dynamic")
      wait_for_lease = var.wsl2_compatibility_mode ? false : try(network.wait_for_lease, null)
      reservations = var.wsl2_compatibility_mode ? merge(
        local.generated_static_reservations[network_name],
        try(network.reservations, {})
      ) : try(network.reservations, {})
    })
  }

  # Group the expanded nodes back by pool so the compute module can iterate
  # cleanly once per pool while still receiving per-node values.
  pool_nodes = {
    for pool_name, pool in var.node_pools :
    pool_name => {
      for node_key, node in local.nodes :
      node_key => node if node.pool_name == pool_name
    }
    if pool.count > 0
  }

  # Collect the addressing decisions we expect the caller to care about. The
  # check block below uses this to verify static IPs are fully specified.
  predictable_bindings = flatten([
    for node_key, node in local.nodes : [
      for network_name in node.networks : {
        node_key     = node_key
        network_name = network_name
        address_mode = try(local.effective_networks[network_name].address_mode, "dynamic")
        desired_ip   = try(node.nic_overrides[network_name].ip, null) != null ? try(node.nic_overrides[network_name].ip, null) : try(local.effective_networks[network_name].reservations[node_key].ip, null)
      }
    ]
  ])

  # GPU checks operate on expanded node names, not just pool names, because the
  # passthrough configuration is per-VM.
  gpu_node_keys = [
    for node_key, node in local.nodes : node_key if node.gpu_enabled
  ]

  first_control_plane_cluster_ip = try(local.nodes[local.first_control_plane_node_key].nic_overrides[local.cluster_network_name].ip, null) != null ? try(local.nodes[local.first_control_plane_node_key].nic_overrides[local.cluster_network_name].ip, null) : try(
    local.effective_networks[local.cluster_network_name].reservations[local.first_control_plane_node_key].ip,
    null
  )

  # Normalize Stage 2 bootstrap defaults in one place so the compute module
  # receives a decision-complete object instead of a partially filled input.
  kubernetes_bootstrap_for_modules = {
    enabled                = try(var.kubernetes_bootstrap.enabled, true)
    distribution           = try(var.kubernetes_bootstrap.distribution, "k3s")
    cluster_token          = coalesce(try(var.kubernetes_bootstrap.cluster_token, null), format("%s-local-cluster-token", var.name_prefix))
    control_plane_endpoint = coalesce(try(var.kubernetes_bootstrap.control_plane_endpoint, null), local.first_control_plane_cluster_ip, "10.42.0.10")
    pod_cidr               = try(var.kubernetes_bootstrap.pod_cidr, "10.244.0.0/16")
    service_cidr           = try(var.kubernetes_bootstrap.service_cidr, "10.96.0.0/12")
    underlay_mtu           = coalesce(try(var.kubernetes_bootstrap.underlay_mtu, null), try(local.effective_networks[local.cluster_network_name].mtu, 1450))
    cilium_mtu             = coalesce(try(var.kubernetes_bootstrap.cilium_mtu, null), coalesce(try(var.kubernetes_bootstrap.underlay_mtu, null), try(local.effective_networks[local.cluster_network_name].mtu, 1450)) - 50)
    data_mount_path        = try(var.kubernetes_bootstrap.data_mount_path, "/var/lib/model-service-local")
    cluster_network_name   = local.cluster_network_name
    storage_network_name   = local.storage_network_name
    k3s_channel            = try(var.kubernetes_bootstrap.k3s_channel, "stable")
    install_cilium         = try(var.kubernetes_bootstrap.install_cilium, true)
    install_nfd            = try(var.kubernetes_bootstrap.install_nfd, true)
    install_keda           = try(var.kubernetes_bootstrap.install_keda, true)
    install_metrics_server = try(var.kubernetes_bootstrap.install_metrics_server, true)
    keep_traefik           = try(var.kubernetes_bootstrap.keep_traefik, true)
    cilium = {
      chart_version  = try(var.kubernetes_bootstrap.cilium.chart_version, null)
      hubble_enabled = try(var.kubernetes_bootstrap.cilium.hubble_enabled, false)
    }
    nfd = {
      chart_version = try(var.kubernetes_bootstrap.nfd.chart_version, null)
    }
    keda = {
      chart_version = try(var.kubernetes_bootstrap.keda.chart_version, null)
    }
    ghcr = {
      create_pull_secret = try(var.kubernetes_bootstrap.ghcr.create_pull_secret, false)
      registry           = try(var.kubernetes_bootstrap.ghcr.registry, "ghcr.io")
      secret_name        = try(var.kubernetes_bootstrap.ghcr.secret_name, "ghcr-pull-secret")
      username           = try(var.kubernetes_bootstrap.ghcr.username, null)
      password           = try(var.kubernetes_bootstrap.ghcr.password, null)
      email              = try(var.kubernetes_bootstrap.ghcr.email, "")
    }
  }
}

# This check catches typos such as `["externl", "cluster"]` before Terraform
# reaches the provider. Reference: https://developer.hashicorp.com/terraform/language/checks
check "pool_network_references" {
  assert {
    condition = alltrue(flatten([
      for pool in values(var.node_pools) : [
        for network_name in pool.networks :
        contains(keys(var.networks), network_name)
      ]
    ]))
    error_message = "Every node pool must reference networks that exist in var.networks."
  }
}

# Static addressing is the only mode that truly requires an explicit IP at
# plan-time. DHCP reservation can still work without Terraform embedding the IP
# into guest network config.
check "predictable_addressing_inputs" {
  assert {
    condition = alltrue([
      for binding in local.predictable_bindings :
      binding.address_mode != "static" || binding.desired_ip != null
    ])
    error_message = "Networks using static addressing must provide an IP through reservations or node_overrides."
  }
}

# GPU pools only make sense when the local-only passthrough mode is enabled.
check "gpu_mode_consistency" {
  assert {
    condition     = length(local.gpu_node_keys) == 0 || var.gpu.mode == "manual_host_passthrough"
    error_message = "Any node pool with gpu_enabled=true requires gpu.mode=manual_host_passthrough."
  }
}

# If passthrough is enabled, every GPU node must have at least one PCI device.
# Without this, libvirt would create a VM that looks like a GPU node in naming
# only, which is worse than failing early.
check "gpu_pci_devices_present" {
  assert {
    condition = var.gpu.mode != "manual_host_passthrough" || alltrue([
      for node_key in local.gpu_node_keys :
      length(lookup(try(var.gpu.pci_devices, {}), node_key, [])) > 0
    ])
    error_message = "Every GPU-enabled node must provide at least one host PCI device in gpu.pci_devices."
  }
}

# Stage 2 relies on the control plane's cluster-network IP being stable. This
# check turns a future "workers can’t join the API server" symptom into an
# immediate Terraform error with the exact missing input.
check "bootstrap_control_plane_endpoint" {
  assert {
    condition     = !local.kubernetes_bootstrap_for_modules.enabled || local.first_control_plane_cluster_ip != null
    error_message = "kubernetes_bootstrap requires a reserved or explicit cluster IP for control-plane-01 on the cluster network."
  }
}

# The single local control plane and the worker join target must agree on the
# same address, otherwise workers would join one endpoint while the API server
# advertises another.
check "bootstrap_endpoint_matches_control_plane_ip" {
  assert {
    condition     = !local.kubernetes_bootstrap_for_modules.enabled || local.kubernetes_bootstrap_for_modules.control_plane_endpoint == local.first_control_plane_cluster_ip
    error_message = "kubernetes_bootstrap.control_plane_endpoint must match the control-plane node's cluster-network IP."
  }
}

# Overlay MTU must stay below the guest NIC MTU or pod traffic will fragment.
check "bootstrap_mtu_relationship" {
  assert {
    condition     = !local.kubernetes_bootstrap_for_modules.enabled || local.kubernetes_bootstrap_for_modules.cilium_mtu < local.kubernetes_bootstrap_for_modules.underlay_mtu
    error_message = "kubernetes_bootstrap.cilium_mtu must be lower than kubernetes_bootstrap.underlay_mtu."
  }
}

# If the caller asks Terraform to create a GHCR pull secret, both username and
# password must be supplied. Without them the cluster would boot but later image
# pulls would fail in a less obvious way.
check "ghcr_secret_inputs" {
  assert {
    condition = !local.kubernetes_bootstrap_for_modules.enabled || !local.kubernetes_bootstrap_for_modules.ghcr.create_pull_secret || (
      local.kubernetes_bootstrap_for_modules.ghcr.username != null &&
      local.kubernetes_bootstrap_for_modules.ghcr.password != null
    )
    error_message = "kubernetes_bootstrap.ghcr.create_pull_secret=true requires both ghcr.username and ghcr.password."
  }
}

# Kubernetes bootstrap expects every node to have the internal cluster network
# attached. Failing here is much easier to understand than a later k3s join
# failure or a template error while resolving the cluster NIC name.
check "bootstrap_cluster_network_attached" {
  assert {
    condition = !local.kubernetes_bootstrap_for_modules.enabled || alltrue([
      for node in values(local.nodes) :
      contains(node.networks, local.kubernetes_bootstrap_for_modules.cluster_network_name)
    ])
    error_message = "kubernetes_bootstrap requires every node to attach the cluster network."
  }
}

# Network module:
# creates the libvirt layer-2/layer-3 networks that the VMs will attach to.
module "network" {
  source      = "../../modules/network/libvirt-fabric"
  name_prefix = var.name_prefix
  networks    = local.effective_networks
}

# Storage module:
# creates the image pool, cloned root disks, and per-node data disks. This is
# intentionally separate from compute so volumes can be reasoned about on their
# own and later mapped more cleanly to Cinder concepts.
module "storage" {
  source      = "../../modules/storage/libvirt-volumes"
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

# Compute module:
# creates the actual VMs for each pool and wires them to the networks, disks,
# cloud-init, and optional GPU passthrough configuration.
module "compute" {
  for_each             = local.pool_nodes
  source               = "../../modules/compute/libvirt-node-pool"
  name_prefix          = var.name_prefix
  pool_name            = each.key
  domain_type          = var.domain_type
  nodes                = each.value
  cloud_init           = local.cloud_init_for_modules
  cloud_init_pool_name = module.storage.volume_pool_name
  network_definitions  = local.effective_networks
  network_resources    = module.network.networks
  root_volume_ids      = module.storage.root_volume_ids
  data_volume_ids      = module.storage.data_volume_ids
  kubernetes_bootstrap = local.kubernetes_bootstrap_for_modules
  gpu                  = var.gpu
}

# Flatten per-pool module outputs into a single `instances` object that is easy
# to inspect from `terraform output instances`.
locals {
  instances = merge(
    {},
    [for compute_pool in values(module.compute) : compute_pool.instances]...
  )
}
