# `name_prefix` gives every resource a predictable name. Change this when you
# want multiple local labs to coexist on one host without naming collisions.
variable "name_prefix" {
  description = "Prefix applied to libvirt resources so multiple local labs can coexist."
  type        = string
  default     = "model-service"
}

# `libvirt_uri` selects which libvirt daemon Terraform talks to.
# - `qemu:///system` is the usual system-wide daemon.
# - `qemu:///session` is useful on laptops where the user session owns the VMs.
variable "libvirt_uri" {
  description = "Libvirt connection URI."
  type        = string
  default     = "qemu:///system"
}

# `domain_type` chooses the hypervisor mode:
# - `kvm` uses hardware acceleration and is much faster.
# - `qemu` uses software emulation and is slower, but works on hosts without KVM.
variable "domain_type" {
  description = "Domain type used by libvirt for VM creation."
  type        = string
  default     = "kvm"
}

# WSL2 struggles with libvirt tap/DHCP behavior, especially when the guests run
# under software-emulated `qemu` instead of hardware-accelerated KVM. Enabling
# this switch forces deterministic static guest IPs on every lab network so the
# VMs no longer depend on libvirt DHCP at boot.
variable "wsl2_compatibility_mode" {
  description = "Force deterministic static guest IPs for WSL2-style hosts where libvirt DHCP is unreliable."
  type        = bool
  default     = false
}

# `networks` defines the three logical networks this lab cares about:
# - `external`: north/south traffic such as SSH or ingress.
# - `cluster`: east/west traffic for Kubernetes node-to-node communication.
# - `storage`: a separate path for storage or future CSI experiments.
#
# Important knobs for future readers:
# - `mtu`: lower this if you later add an overlay CNI and see fragmentation.
# - `wait_for_lease`: when true, Terraform waits for libvirt to observe DHCP.
#   That is convenient on fast KVM boots, but often unreliable on slow `qemu`.
# - `address_mode`: `dynamic`, `dhcp_reserved`, or `static`.
#   `static` expects cloud-init network config to own the address.
variable "networks" {
  description = "Shared network contract for the local cloud-simulation lab."
  type = map(object({
    enabled        = optional(bool, true)
    mode           = optional(string, "none")
    domain         = optional(string)
    cidr           = string
    gateway        = optional(string)
    dhcp_range     = object({ start = string, end = string })
    dns            = optional(list(string), [])
    mtu            = number
    wait_for_lease = optional(bool)
    address_mode   = optional(string, "dynamic")
    reservations = optional(map(object({
      ip       = string
      mac      = optional(string)
      hostname = optional(string)
    })), {})
  }))

  default = {
    # `external` behaves like the VM lab's "public" network. We use NAT here
    # because it works on most laptops without requiring a bridged host NIC.
    external = {
      enabled        = true
      mode           = "nat"
      domain         = "external.local"
      cidr           = "192.168.124.0/24"
      gateway        = "192.168.124.1"
      dhcp_range     = { start = "192.168.124.50", end = "192.168.124.200" }
      dns            = ["1.1.1.1", "8.8.8.8"]
      mtu            = 1450
      wait_for_lease = true
      address_mode   = "dynamic"
      reservations   = {}
    }

    # `cluster` is the internal network that a future Kubernetes control plane
    # and workers will use to talk to each other. The default reservation keeps
    # the first control-plane node on a stable address for join commands.
    cluster = {
      enabled        = true
      mode           = "none"
      domain         = "cluster.local"
      cidr           = "10.42.0.0/24"
      gateway        = "10.42.0.1"
      dhcp_range     = { start = "10.42.0.100", end = "10.42.0.200" }
      dns            = ["10.42.0.1"]
      mtu            = 1450
      wait_for_lease = false
      address_mode   = "dhcp_reserved"
      reservations = {
        control-plane-01 = {
          ip       = "10.42.0.10"
          hostname = "control-plane-01"
        }
      }
    }

    # `storage` is intentionally separate from `cluster` even though nothing in
    # Stage 1 consumes it yet. Keeping it separate now lets us model the same
    # separation we would likely keep in OpenStack later.
    storage = {
      enabled        = true
      mode           = "none"
      domain         = "storage.local"
      cidr           = "10.43.0.0/24"
      gateway        = "10.43.0.1"
      dhcp_range     = { start = "10.43.0.100", end = "10.43.0.200" }
      dns            = []
      mtu            = 1450
      wait_for_lease = false
      address_mode   = "dynamic"
      reservations   = {}
    }
  }

  # This validation fails early if a caller invents a new address mode. The
  # goal is to turn a vague provider error into a Terraform-native one.
  validation {
    condition = alltrue([
      for network in values(var.networks) :
      contains(["dynamic", "dhcp_reserved", "static"], try(network.address_mode, "dynamic"))
    ])
    error_message = "networks[*].address_mode must be one of dynamic, dhcp_reserved, or static."
  }
}

# `node_pools` models the Kubernetes-style idea of node classes:
# control planes, CPU workers, and optional GPU workers. Each pool expands into
# one or more VM instances in main.tf.
#
# Important knobs:
# - `count`: how many VMs exist in this pool.
# - `root_disk_gb` / `data_disk_gb`: boot disk vs attached workload/cache disk.
# - `node_overrides`: per-node escape hatch for fixed MAC/IPs or custom
#   cloud-init without changing the shared pool defaults.
variable "node_pools" {
  description = "Shared node-pool contract for control-plane, CPU worker, and optional GPU worker pools."
  type = map(object({
    count        = number
    vcpu         = number
    memory_mb    = number
    root_disk_gb = optional(number)
    data_disk_gb = optional(number)
    networks     = list(string)
    labels       = optional(map(string), {})
    gpu_enabled  = optional(bool, false)
    node_overrides = optional(map(object({
      nics = optional(map(object({
        mac            = optional(string)
        ip             = optional(string)
        wait_for_lease = optional(bool)
        hostname       = optional(string)
      })), {})
      cloud_init = optional(object({
        user_data      = optional(string)
        meta_data      = optional(map(string), {})
        network_config = optional(string)
      }))
    })), {})
  }))

  default = {
    # Small default control plane: enough to bootstrap a local cluster without
    # consuming too much laptop memory.
    control_plane = {
      count        = 1
      vcpu         = 2
      memory_mb    = 4096
      root_disk_gb = 30
      data_disk_gb = 80
      networks     = ["external", "cluster", "storage"]
      labels = {
        role = "control-plane"
      }
    }

    # CPU workers are the default place to run the model service locally. They
    # represent the "normal" worker shape we expect most clusters to have.
    workers_cpu = {
      count        = 1
      vcpu         = 4
      memory_mb    = 8192
      root_disk_gb = 40
      data_disk_gb = 100
      networks     = ["external", "cluster", "storage"]
      labels = {
        role = "worker"
        tier = "cpu"
      }
    }

    # GPU workers are disabled by default because local PCI passthrough is
    # highly host-specific. Enabling this pool alone is not enough; the caller
    # must also set `gpu.mode = "manual_host_passthrough"` and provide devices.
    workers_gpu = {
      count        = 0
      vcpu         = 8
      memory_mb    = 16384
      root_disk_gb = 60
      data_disk_gb = 200
      networks     = ["external", "cluster", "storage"]
      gpu_enabled  = true
      labels = {
        role = "worker"
        tier = "gpu"
      }
    }
  }
}

# `cloud_init` is the bootstrap contract shared by local libvirt and the future
# OpenStack stack. We keep it provider-agnostic so later work can swap the
# transport (ISO vs user_data API field) without changing the caller contract.
# References:
# - NoCloud datasource: https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
variable "cloud_init" {
  description = "Provider-agnostic cloud-init contract shared between local libvirt and later OpenStack stacks."
  type = object({
    template_path       = optional(string)
    template_vars       = optional(map(string), {})
    user_data           = optional(string)
    ssh_authorized_keys = optional(list(string), [])
    meta_data           = optional(map(string), {})
    network_config      = optional(string)
  })
  default = {}

  # The caller must choose one of:
  # - `template_path`: render a file with variables
  # - `user_data`: pass an already rendered cloud-config payload
  validation {
    condition = !(
      try(var.cloud_init.template_path, null) != null &&
      try(var.cloud_init.user_data, null) != null
    )
    error_message = "Set cloud_init.template_path or cloud_init.user_data, not both."
  }
}

# `storage` separates immutable base image storage from per-node mutable disks.
# That mirrors the mental model of "golden image + attached volumes" we expect
# to carry forward into Cinder later.
variable "storage" {
  description = "Shared storage contract for image and per-node attached disk handling."
  type = object({
    image_store_path     = string
    volume_store_path    = string
    base_image_name      = string
    base_image_source    = string
    retain_on_destroy    = optional(bool, false)
    default_root_disk_gb = optional(number, 30)
    default_data_disk_gb = optional(number, 80)
  })

  default = {
    image_store_path     = "/var/lib/libvirt/images/model-service/base"
    volume_store_path    = "/var/lib/libvirt/images/model-service/volumes"
    base_image_name      = "jammy-server-cloudimg-amd64.img"
    base_image_source    = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    retain_on_destroy    = false
    default_root_disk_gb = 30
    default_data_disk_gb = 80
  }
}

# `kubernetes_bootstrap` turns the Stage 1 VM substrate into a Stage 2 local
# Kubernetes lab. We keep the object provider-agnostic so the same logical
# intent can later be mapped to OpenStack without redesigning the caller API.
#
# Important knobs:
# - `control_plane_endpoint`: the stable join target that agents will use.
# - `pod_cidr` / `service_cidr`: must not overlap the libvirt underlay ranges.
# - `underlay_mtu` / `cilium_mtu`: the overlay MTU must stay below the guest
#   network MTU or pod traffic will fragment.
# - `ghcr`: optional image-pull secret contract for GitHub Packages.
variable "kubernetes_bootstrap" {
  description = "Stage 2 Kubernetes bootstrap contract for the local libvirt lab."
  type = object({
    enabled                = optional(bool, true)
    distribution           = optional(string, "k3s")
    cluster_token          = optional(string)
    control_plane_endpoint = optional(string)
    pod_cidr               = optional(string, "10.244.0.0/16")
    service_cidr           = optional(string, "10.96.0.0/12")
    underlay_mtu           = optional(number)
    cilium_mtu             = optional(number)
    data_mount_path        = optional(string, "/var/lib/model-service-local")
    cluster_network_name   = optional(string, "cluster")
    storage_network_name   = optional(string, "storage")
    k3s_channel            = optional(string, "stable")
    install_cilium         = optional(bool, true)
    install_nfd            = optional(bool, true)
    install_keda           = optional(bool, true)
    install_metrics_server = optional(bool, true)
    keep_traefik           = optional(bool, true)
    cilium = optional(object({
      chart_version  = optional(string)
      hubble_enabled = optional(bool, false)
    }), {})
    nfd = optional(object({
      chart_version = optional(string)
    }), {})
    keda = optional(object({
      chart_version = optional(string)
    }), {})
    ghcr = optional(object({
      create_pull_secret = optional(bool, false)
      registry           = optional(string, "ghcr.io")
      secret_name        = optional(string, "ghcr-pull-secret")
      username           = optional(string)
      password           = optional(string)
      email              = optional(string, "")
    }), {})
  })
  default = {}

  validation {
    condition     = contains(["k3s"], try(var.kubernetes_bootstrap.distribution, "k3s"))
    error_message = "kubernetes_bootstrap.distribution currently supports only k3s in the local libvirt stack."
  }
}

# `gpu` is intentionally local-only. It exposes the host PCI details needed by
# the libvirt/XSLT passthrough path, but it is not meant to be a portable
# contract across providers.
variable "gpu" {
  description = "Local-only GPU extension. PCI devices are keyed by logical node name."
  type = object({
    mode = optional(string, "disabled")
    pci_devices = optional(map(list(object({
      domain   = string
      bus      = string
      slot     = string
      function = string
      managed  = optional(bool, true)
    }))), {})
  })
  default = {}

  # We only support two states in Stage 1:
  # - `disabled`: safest default
  # - `manual_host_passthrough`: caller accepts host-side prep outside Terraform
  validation {
    condition     = contains(["disabled", "manual_host_passthrough"], try(var.gpu.mode, "disabled"))
    error_message = "gpu.mode must be disabled or manual_host_passthrough."
  }
}
