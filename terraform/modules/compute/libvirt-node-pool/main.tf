# This module is the heart of the local lab. It takes expanded nodes from the
# root stack and turns them into actual VMs, one `libvirt_domain` per node.
# References:
# - libvirt domain resource: https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/domain
# - libvirt domain XML: https://libvirt.org/formatdomain.html
# - cloud-init NoCloud: https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
# - cloud-init network v2: https://cloudinit.readthedocs.io/en/latest/topics/network-config-format-v2.html
locals {
  # Build a normalized view of each node's NICs. This is where we decide:
  # - which libvirt network a NIC attaches to
  # - whether the NIC gets a predictable IP
  # - whether Terraform should wait for a DHCP lease
  # - which MAC address should be stable across rebuilds
  node_interfaces = {
    for node_key, node in var.nodes :
    node_key => [
      for network_name in node.networks : {
        network_name = network_name
        address_mode = try(var.network_definitions[network_name].address_mode, "dynamic")
        network_id   = try(var.network_resources[network_name].id, null)
        network_name_actual = try(
          var.network_resources[network_name].name,
          format("%s-%s", var.name_prefix, network_name)
        )
        reservation = try(var.network_definitions[network_name].reservations[node_key], {})

        # Explicit per-node IPs win over network-level reservations. That makes
        # node overrides the final authority for one-off debugging.
        ip = try(node.nic_overrides[network_name].ip, null) != null ? try(node.nic_overrides[network_name].ip, null) : try(var.network_definitions[network_name].reservations[node_key].ip, null)

        # We derive a deterministic MAC when the caller does not supply one.
        # This keeps DHCP reservations stable across destroy/apply cycles.
        mac = coalesce(
          try(node.nic_overrides[network_name].mac, null),
          try(var.network_definitions[network_name].reservations[node_key].mac, null),
          format(
            "52:54:%s:%s:%s:%s",
            substr(md5(format("%s/%s", node_key, network_name)), 0, 2),
            substr(md5(format("%s/%s", node_key, network_name)), 2, 2),
            substr(md5(format("%s/%s", node_key, network_name)), 4, 2),
            substr(md5(format("%s/%s", node_key, network_name)), 6, 2)
          )
        )
        hostname = coalesce(
          try(node.nic_overrides[network_name].hostname, null),
          try(var.network_definitions[network_name].reservations[node_key].hostname, null),
          node.hostname
        )

        # Lease waiting is intentionally conservative:
        # - caller override wins
        # - then network policy
        # - then a safe default of "wait only on external KVM interfaces"
        wait_for_lease = coalesce(
          try(node.nic_overrides[network_name].wait_for_lease, null),
          try(var.network_definitions[network_name].wait_for_lease, null),
          var.domain_type == "kvm" && try(var.network_definitions[network_name].address_mode, "dynamic") != "static" && network_name == "external"
        )
        mtu = try(var.network_resources[network_name].mtu, try(var.network_definitions[network_name].mtu, null))
        dns = try(var.network_resources[network_name].dns, try(var.network_definitions[network_name].dns, []))
        gateway = coalesce(
          try(var.network_resources[network_name].gateway, null),
          try(var.network_definitions[network_name].gateway, null),
          cidrhost(var.network_definitions[network_name].cidr, 1)
        )
        prefix = tonumber(split("/", var.network_definitions[network_name].cidr)[1])
      }
    ]
  }

  # Cloud-init now generates interface definitions for all NICs, not just fully
  # static ones. That gives us deterministic names such as `eth1` for the
  # cluster network and lets us enforce MTU inside the guest.
  generated_network_config = {
    for node_key, interfaces in local.node_interfaces :
    node_key => yamlencode({
      version = 2
      ethernets = {
        for index, iface in interfaces :
        format("eth%d", index) => {
          for key, value in merge(
            {
              match = {
                macaddress = iface.mac
              }
              set-name = format("eth%d", index)
              mtu      = iface.mtu
              dhcp4    = iface.address_mode != "static"
            },
            {
              addresses = iface.address_mode == "static" ? [format("%s/%d", iface.ip, iface.prefix)] : null
              # Only the external network should install the guest's default
              # route. Internal cluster/storage networks are intentionally
              # non-routable from the host and should not compete for egress.
              routes = iface.address_mode == "static" && iface.network_name == "external" && iface.gateway != null ? [
                {
                  to  = "default"
                  via = iface.gateway
                }
              ] : null
              nameservers = iface.address_mode == "static" && iface.network_name == "external" && length(iface.dns) > 0 ? {
                addresses = iface.dns
              } : null
            }
          ) :
          key => value if value != null
        }
      }
    })
  }

  # Each node needs a stable handle to its cluster NIC so k3s binds to the
  # internal network rather than whichever interface appears first at runtime.
  cluster_interface_name = {
    for node_key, interfaces in local.node_interfaces :
    node_key => one([
      for index, iface in interfaces :
      format("eth%d", index) if iface.network_name == var.kubernetes_bootstrap.cluster_network_name
    ])
  }

  # Convert node labels into the flat `key=value` strings that k3s expects.
  # Kubernetes 1.34 rejects kubelet-managed labels in the reserved
  # `node-role.kubernetes.io/*` namespace, so we only inject our custom
  # `model-service.io/*` labels here. If we want the conventional node-role
  # labels later, they need to be applied by the control plane after the node
  # has joined, not by kubelet startup flags.
  node_label_strings = {
    for node_key, node in var.nodes :
    node_key => concat(
      [
        format(
          "model-service.io/node-class=%s",
          var.pool_name == "control_plane" ? "control-plane" : try(node.labels.tier, "cpu")
        )
      ],
      [
        for label_key, label_value in try(node.labels, {}) :
        format("%s=%s", label_key, label_value)
      ]
    )
  }

  # Dedicated control-plane taint keeps local workloads on the workers so Stage
  # 3 autoscaling tests reflect the intended topology more closely.
  node_taint_strings = {
    for node_key, node in var.nodes :
    node_key => var.pool_name == "control_plane" ? [
      "node-role.kubernetes.io/control-plane=true:NoSchedule"
    ] : []
  }

  primary_server_node_key = var.pool_name == "control_plane" && length(keys(var.nodes)) > 0 ? sort(keys(var.nodes))[0] : null

  # Control-plane manifests are rendered once and copied only to the primary
  # server node. k3s will auto-apply anything placed in this directory.
  control_plane_manifests = merge(
    {
      "00-model-service-namespace.yaml" = templatefile("${path.module}/templates/model-service-namespace.yaml.tftpl", {})
    },
    try(var.kubernetes_bootstrap.ghcr.create_pull_secret, false) ? {
      "01-model-service-ghcr-secret.yaml" = templatefile("${path.module}/templates/model-service-pull-secret.yaml.tftpl", {
        secret_name = var.kubernetes_bootstrap.ghcr.secret_name
        dockerconfigjson = base64encode(jsonencode({
          auths = {
            (var.kubernetes_bootstrap.ghcr.registry) = {
              username = var.kubernetes_bootstrap.ghcr.username
              password = var.kubernetes_bootstrap.ghcr.password
              email    = var.kubernetes_bootstrap.ghcr.email
              auth     = base64encode(format("%s:%s", var.kubernetes_bootstrap.ghcr.username, var.kubernetes_bootstrap.ghcr.password))
            }
          }
        }))
      })
    } : {},
    try(var.kubernetes_bootstrap.install_cilium, true) ? {
      "10-cilium.yaml" = templatefile("${path.module}/templates/cilium-helmchart.yaml.tftpl", {
        pod_cidr       = var.kubernetes_bootstrap.pod_cidr
        cilium_mtu     = var.kubernetes_bootstrap.cilium_mtu
        chart_version  = try(var.kubernetes_bootstrap.cilium.chart_version, null)
        hubble_enabled = try(var.kubernetes_bootstrap.cilium.hubble_enabled, false)
      })
    } : {},
    try(var.kubernetes_bootstrap.install_nfd, true) ? {
      "20-node-feature-discovery.yaml" = templatefile("${path.module}/templates/nfd-helmchart.yaml.tftpl", {
        chart_version = try(var.kubernetes_bootstrap.nfd.chart_version, null)
      })
      "21-node-feature-rules.yaml" = templatefile("${path.module}/templates/nfd-nodefeaturerule.yaml.tftpl", {})
    } : {},
    try(var.kubernetes_bootstrap.install_keda, true) ? {
      "30-keda.yaml" = templatefile("${path.module}/templates/keda-helmchart.yaml.tftpl", {
        chart_version = try(var.kubernetes_bootstrap.keda.chart_version, null)
      })
    } : {}
  )

  rendered_preflight_script = {
    for node_key, node in var.nodes :
    node_key => templatefile("${path.module}/templates/preflight.sh.tftpl", {
      data_disk_id    = node.data_disk_id
      data_mount_path = var.kubernetes_bootstrap.data_mount_path
      data_disk_by_id = format("/dev/disk/by-id/virtio-%s", node.data_disk_id)
    })
  }

  rendered_k3s_bootstrap_script = {
    for node_key, node in var.nodes :
    node_key => templatefile("${path.module}/templates/k3s-bootstrap.sh.tftpl", {
      node_name              = node.hostname
      node_role              = var.pool_name == "control_plane" ? "server" : "agent"
      cluster_interface      = local.cluster_interface_name[node_key]
      control_plane_ip       = var.kubernetes_bootstrap.control_plane_endpoint
      cluster_token          = var.kubernetes_bootstrap.cluster_token
      pod_cidr               = var.kubernetes_bootstrap.pod_cidr
      service_cidr           = var.kubernetes_bootstrap.service_cidr
      local_storage_path     = var.kubernetes_bootstrap.data_mount_path
      k3s_channel            = var.kubernetes_bootstrap.k3s_channel
      keep_traefik           = try(var.kubernetes_bootstrap.keep_traefik, true)
      install_metrics_server = try(var.kubernetes_bootstrap.install_metrics_server, true)
      node_labels            = local.node_label_strings[node_key]
      node_taints            = local.node_taint_strings[node_key]
    })
  }

  # Render the cloud-init user-data payload for each node. Callers can either:
  # - inject full raw `user_data`, or
  # - provide a template path and variables.
  rendered_user_data = {
    for node_key, node in var.nodes :
    node_key => coalesce(
      try(node.cloud_init.user_data, null),
      try(var.cloud_init.user_data, null),
      templatefile(
        var.cloud_init.template_path,
        merge(
          try(var.cloud_init.template_vars, {}),
          {
            hostname             = node.hostname
            instance_name        = node.instance_name
            pool_name            = var.pool_name
            labels               = node.labels
            ssh_authorized_keys  = try(var.cloud_init.ssh_authorized_keys, [])
            kubernetes_enabled   = try(var.kubernetes_bootstrap.enabled, false)
            node_role            = var.pool_name == "control_plane" ? "server" : "agent"
            data_mount_path      = var.kubernetes_bootstrap.data_mount_path
            data_disk_id         = node.data_disk_id
            preflight_script     = local.rendered_preflight_script[node_key]
            k3s_bootstrap_script = local.rendered_k3s_bootstrap_script[node_key]
            addon_manifests      = try(var.kubernetes_bootstrap.enabled, false) && node_key == local.primary_server_node_key ? local.control_plane_manifests : {}
          }
        )
      )
    )
  }

  # Render the metadata file that cloud-init's NoCloud datasource expects.
  # `instance-id` is especially important because cloud-init uses it to decide
  # whether a VM is "new" versus a previously initialized instance.
  rendered_meta_data = {
    for node_key, node in var.nodes :
    node_key => yamlencode(merge(
      try(var.cloud_init.meta_data, {}),
      try(node.cloud_init.meta_data, {}),
      {
        "instance-id"    = node.instance_name
        "local-hostname" = node.hostname
      }
    ))
  }

  # Final network config precedence:
  # 1. node-specific override
  # 2. shared stack-level override
  # 3. generated config for all NICs
  rendered_network_config = {
    for node_key, node in var.nodes :
    node_key => try(node.cloud_init.network_config, null) != null ? try(node.cloud_init.network_config, null) : (
      try(var.cloud_init.network_config, null) != null ? try(var.cloud_init.network_config, null) : try(local.generated_network_config[node_key], null)
    )
  }

  # GPU passthrough is attached only to the subset of nodes that asked for it.
  gpu_nodes = {
    for node_key, node in var.nodes :
    node_key => node if try(node.gpu_enabled, false)
  }
}

# Static interfaces must have explicit addresses. This check is intentionally
# local to the compute module because this is where static IPs become actual NIC
# configuration, not just abstract policy.
check "predictable_addresses" {
  assert {
    condition = alltrue(flatten([
      for interfaces in values(local.node_interfaces) : [
        for iface in interfaces :
        iface.address_mode != "static" || iface.ip != null
      ]
    ]))
    error_message = "static interfaces require an explicit IP from reservations or node_overrides."
  }
}

# GPU passthrough without PCI devices would silently create a misleading VM, so
# fail fast before we get near libvirt's XML layer.
check "gpu_passthrough_inputs" {
  assert {
    condition = try(var.gpu.mode, "disabled") != "manual_host_passthrough" || alltrue([
      for node_key in keys(local.gpu_nodes) :
      length(lookup(try(var.gpu.pci_devices, {}), node_key, [])) > 0
    ])
    error_message = "GPU-enabled nodes require at least one PCI device entry when gpu.mode is manual_host_passthrough."
  }
}

# This helper module renders the XSLT used to append `<hostdev>` blocks and the
# stable data-disk serial to the generated libvirt domain XML.
module "hostdev" {
  for_each = var.nodes
  source   = "../libvirt-hostdev"

  pci_devices      = lookup(try(var.gpu.pci_devices, {}), each.key, [])
  data_disk_serial = each.value.data_disk_id
}

# Create a NoCloud seed ISO for each node.
# `libvirt_cloudinit_disk` packages:
# - user-data
# - meta-data
# - optional network-config
#
# This resource shells out to an ISO tool such as `mkisofs`, which is why the
# host needs `genisoimage` installed on Ubuntu.
resource "libvirt_cloudinit_disk" "this" {
  for_each = var.nodes

  name           = format("%s-seed.iso", each.value.instance_name)
  pool           = var.cloud_init_pool_name
  user_data      = local.rendered_user_data[each.key]
  meta_data      = local.rendered_meta_data[each.key]
  network_config = local.rendered_network_config[each.key]
}

# Create one VM per expanded node.
resource "libvirt_domain" "this" {
  for_each = var.nodes
  name     = each.value.instance_name

  # `type` is the hypervisor mode:
  # - `kvm` = fast, hardware accelerated
  # - `qemu` = slower, software emulated fallback
  type   = var.domain_type
  memory = each.value.memory_mb
  vcpu   = each.value.vcpu

  # Expose a modern CPU model to the guest so native ML wheels do not inherit
  # libvirt's very old qemu64 defaults. `host-passthrough` is reserved for KVM.
  cpu {
    mode = var.cpu_mode
  }

  # `autostart` means libvirt will try to boot the VM on host restart.
  autostart = true

  # `qemu_agent` allows libvirt to ask the guest for details such as IPs when
  # the guest agent is installed in the image.
  qemu_agent = true
  running    = true

  # Attaching the seed ISO is what makes first-boot cloud-init run.
  cloudinit = libvirt_cloudinit_disk.this[each.key].id

  # Attach one NIC per logical network. Important fields:
  # - `wait_for_lease`: whether Terraform waits for libvirt to see a guest IP
  # - `addresses`: hint predictable IPs to the provider when known
  dynamic "network_interface" {
    for_each = local.node_interfaces[each.key]
    content {
      network_id     = network_interface.value.network_id
      network_name   = network_interface.value.network_name_actual
      hostname       = network_interface.value.hostname
      mac            = network_interface.value.mac
      wait_for_lease = network_interface.value.wait_for_lease
      addresses      = network_interface.value.ip == null ? [] : [network_interface.value.ip]
    }
  }

  # First disk is the cloned OS/root disk.
  disk {
    volume_id = var.root_volume_ids[each.key]
  }

  # Second disk is for mutable workload or cache data.
  disk {
    volume_id = var.data_volume_ids[each.key]
  }

  # Serial and virtio consoles make boot/debugging easier when the guest has no
  # network yet. They are especially useful in local VM labs.
  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  # SPICE gives a graphical console path when SSH is not ready yet.
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  # The `xml` block applies XSLT to the provider-generated domain XML so we can
  # inject features the provider does not expose as simple first-class
  # arguments, such as GPU host devices and stable disk serials.
  dynamic "xml" {
    for_each = [module.hostdev[each.key].xslt]
    content {
      xslt = xml.value
    }
  }
}
