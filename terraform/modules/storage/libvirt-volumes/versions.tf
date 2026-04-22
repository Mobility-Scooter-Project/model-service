# Child modules repeat provider source mappings so Terraform does not guess the
# wrong namespace when the root module installs providers.
terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}
