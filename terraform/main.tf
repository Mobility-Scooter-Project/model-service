terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0"
    }
  }
}

# Provider credentials should be sourced from environment variables (OS_AUTH_URL, OS_USERNAME, etc.)
provider "openstack" {}

resource "openstack_compute_instance_v2" "k3s_gpu_node" {
  name        = var.instance_name
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = var.key_pair

  network {
    name = var.network_name
  }

  user_data = file("${path.module}/cloud-init.yaml")
}

output "k3s_node_ip" {
  description = "The public IP address of the K3s node"
  value       = openstack_compute_instance_v2.k3s_gpu_node.access_ip_v4
}