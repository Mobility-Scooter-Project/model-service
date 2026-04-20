# The caller only needs the rendered XSLT string, not the intermediate device
# list, so that is the only output this helper module returns.
output "xslt" {
  description = "Rendered XSLT used to append PCI host devices to a libvirt domain."
  value       = local.xslt
}
