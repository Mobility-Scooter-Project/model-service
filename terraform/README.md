# Terraform Local Cloud Simulation

This directory introduces a staged Terraform layout for moving the model service from local container-first workflows toward a local cloud-like VM substrate.

## What Exists Today
- `stacks/local-libvirt`: executable local KVM/libvirt stack for compute, network, storage, and cloud-init bootstrapping.
- `stacks/prod-openstack`: contract-complete placeholder stack that preserves the same input/output shapes for a later OpenStack implementation.
- `modules/network/*`: network modules for local libvirt and future OpenStack parity.
- `modules/storage/*`: boot/data volume modules for local libvirt and future OpenStack parity.
- `modules/compute/*`: VM pool modules, including an experimental libvirt GPU passthrough XSLT path.

## Stage 2 Bootstrap
- The local stack now bootstraps a single-control-plane `k3s` cluster directly from cloud-init.
- Workers join the control plane at the fixed `cluster` network endpoint configured in `kubernetes_bootstrap.control_plane_endpoint`.
- The default pod and service CIDRs are `10.244.0.0/16` and `10.96.0.0/12` so they do not overlap the libvirt underlay networks `10.42.0.0/24` and `10.43.0.0/24`.
- The stack disables k3s flannel and installs Cilium through the k3s manifests directory with an explicit overlay MTU.
- The mutable qcow2 data disk now receives a stable libvirt disk serial so the guest can safely discover it under `/dev/disk/by-id/...` before formatting it for node-local storage.
- Stage 2 also prepares the cluster for Stage 3 by installing Node Feature Discovery, KEDA core, and the `model-service` namespace contract for GHCR-backed workloads.
- The Stage 3 application package now lives under [`deploy/stage3/`](/home/inferno9/cpp/model-service/deploy/stage3/README.md). It adds the KEDA HTTP add-on, Traefik-to-interceptor routing, and a per-model Helm chart for synchronous scale-to-zero serving.

## Important Notes
- The local stack intentionally pins `dmacvicar/libvirt` to `0.8.2`. That legacy provider line is still the safer choice for deterministic address handling while the newer `0.9.x` rewrite continues catching up on DHCP reservation workflows.
- GPU passthrough is exposed as an experimental, manual-prepared lane. Terraform does not configure host IOMMU, VFIO binding, or laptop-specific PCI isolation prerequisites.
- KEDA HTTP add-on is intentionally not installed yet. Stage 3 ingress must route through the KEDA HTTP interceptor service instead of pointing ingress directly at model services.
- The OpenStack stack is interface scaffolding only in this stage. It exists to lock the contract now, not to provision a real cloud yet.
- `terraform validate` succeeds for `stacks/local-libvirt`, but `terraform plan` still depends on a live libvirt socket at the configured URI. If your host does not expose `/var/run/libvirt/libvirt-sock`, switch to `qemu:///session` or start the system libvirt daemon before planning.
- `terraform apply` for `stacks/local-libvirt` also requires a local ISO authoring tool for `libvirt_cloudinit_disk`. On Ubuntu, install `genisoimage` so the `mkisofs` binary is available on `PATH`.
- `terraform apply` for `stacks/local-libvirt` also requires `xsltproc` on the host because the stack uses an XSLT hook to inject the stable data-disk serial and optional PCI passthrough XML into each libvirt domain definition.
- If `terraform apply` fails with `does not support virt type 'kvm'`, your host likely lacks KVM acceleration. Set `domain_type = "qemu"` in `stacks/local-libvirt/terraform.tfvars` to use software emulation instead.
- `cpu_mode` now defaults to `host-model`, which is compatible with both `kvm` and `qemu`. Reserve `cpu_mode = "host-passthrough"` for `kvm` hosts that need the maximum host CPU feature set for local ML workloads.
- When using `domain_type = "qemu"`, guest boot is much slower and libvirt IP lease polling is unreliable. The local stack therefore defaults to lease waiting only on the external network for `kvm`, while internal `cluster` and `storage` networks default to `wait_for_lease = false`.
- When running the lab from WSL2, enable `wsl2_compatibility_mode = true` in `stacks/local-libvirt/terraform.tfvars`. That forces deterministic static guest IPs on `external`, `cluster`, and `storage`, which is much more reliable than libvirt DHCP on WSL2-based hosts.

## WSL2 Notes

WSL2 is a supported "best effort" local target, but it needs a more opinionated setup than a normal Linux host:

- Use `domain_type = "qemu"` because WSL2 does not expose KVM acceleration in the same way as a real Linux host.
- Use `wsl2_compatibility_mode = true` so the guests boot with static IPs instead of depending on libvirt DHCP.
- Expect slower first boot and slower `terraform apply` runs because software emulation is much slower than KVM.

Recommended local `terraform.tfvars` additions on WSL2:

```hcl
domain_type             = "qemu"
wsl2_compatibility_mode = true
# cpu_mode stays on the default "host-model" here; do not set host-passthrough.
```

When compatibility mode is enabled, the stack auto-assigns deterministic guest IPs:

- `control-plane-01`
  - `external`: `192.168.124.10`
  - `cluster`: `10.42.0.10`
  - `storage`: `10.43.0.10`
- `workers-cpu-01`
  - `external`: `192.168.124.11`
  - `cluster`: `10.42.0.11`
  - `storage`: `10.43.0.11`
- `workers-cpu-02`
  - `external`: `192.168.124.12`
  - `cluster`: `10.42.0.12`
  - `storage`: `10.43.0.12`

If you switch an existing lab from DHCP-style networking to WSL2 compatibility mode, do a full recreate so the guests pick up the new cloud-init network config:

```bash
cd /home/inferno9/cpp/model-service/terraform/stacks/local-libvirt
terraform destroy
terraform apply
```

## Libvirt Permissions

Terraform talks to the libvirt daemon through `/var/run/libvirt/libvirt-sock`. If you see:

```text
failed to connect: dial unix /var/run/libvirt/libvirt-sock: connect: permission denied
```

your user does not currently have access to the system libvirt socket.

Preferred fix:

```bash
sudo usermod -aG libvirt "$USER"
newgrp libvirt
```

Then verify:

```bash
id
ls -l /var/run/libvirt/libvirt-sock
```

You want your shell to show membership in the `libvirt` group before retrying `terraform plan`, `terraform apply`, or `terraform destroy`.

Avoid `sudo terraform ...` unless you are truly blocked, because it can leave behind root-owned files in `.terraform/` and make later runs from your normal user more annoying.

## Start Here
- Example inputs: [stacks/local-libvirt/terraform.tfvars.example](/home/inferno9/cpp/model-service/terraform/stacks/local-libvirt/terraform.tfvars.example)
- Local entrypoint: [stacks/local-libvirt/main.tf](/home/inferno9/cpp/model-service/terraform/stacks/local-libvirt/main.tf)
