# Each object describes one PCI device on the libvirt host that should be
# passed through to the guest. These values map directly to the `<address ...>`
# elements in libvirt domain XML.
variable "pci_devices" {
  description = "PCI devices to inject into the domain XML using XSLT."
  type = list(object({
    domain   = string
    bus      = string
    slot     = string
    function = string
    managed  = optional(bool, true)
  }))
}

# The local Kubernetes bootstrap uses this serial to create a stable
# `/dev/disk/by-id/...` path for the mutable data disk. We keep the ID short so
# it stays within the typical virtio serial length limits.
variable "data_disk_serial" {
  description = "Stable serial to inject into the second disk device in the domain XML."
  type        = string
}
