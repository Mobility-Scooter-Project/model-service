# Render the XSLT fragment that appends `<hostdev>` blocks to the generated
# libvirt domain XML. Keeping this logic isolated makes the main compute module
# much easier to read for people who are not yet comfortable with XML/XSLT.
locals {
  xslt = templatefile("${path.module}/templates/hostdev.xslt.tftpl", {
    devices          = var.pci_devices
    data_disk_serial = var.data_disk_serial
  })
}
