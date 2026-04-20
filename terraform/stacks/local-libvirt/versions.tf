# This root stack uses Terraform 1.5+ because the configuration relies on
# `check` blocks in main.tf to document and validate design assumptions.
# Reference: https://developer.hashicorp.com/terraform/language/checks
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # We intentionally pin to the 0.8.x libvirt provider line because it is the
    # most stable match for this repo's current network and cloud-init workflow.
    # Newer provider lines changed behavior and docs shape substantially.
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.2"
    }
  }
}
