variable "instance_name" {
  description = "Name of the K3s cluster node"
  type        = string
  default     = "model-service-cluster"
}

variable "image_name" {
  description = "OS Image to use for the node"
  type        = string
  default     = "Ubuntu 22.04"
}

variable "flavor_name" {
  description = "Compute flavor (must include GPU allocation)"
  type        = string
}

variable "key_pair" {
  description = "SSH keypair name registered in OpenStack"
  type        = string
}

variable "network_name" {
  description = "Name of the network to attach the instance to"
  type        = string
}