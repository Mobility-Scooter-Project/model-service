## Model Service

This service provides independent model deployment for the Mobility Scooter Project. Each model is containerized as an individual Docker image to allow for granular scaling and decoupling from consumer services. 

This architecture replaces heavier alternatives like [Kubeflow](https://www.kubeflow.org/) to maintain a smaller resource footprint. The Kubernetes path now uses an always-on API plus queue-scaled model workers, with [KEDA](https://keda.sh/) handling worker autoscaling.

### Contributing

#### Adding New Models
1. Create a new directory in `src/model/`.
2. Include an `__init__.py` with a *lowercase, non-space separated* class name matching the folder name.
3. Include a `requirements.txt` file for model-specific dependencies.

#### Local Cloud Simulation
The Terraform-based VM substrate for local cloud-style validation lives under [`terraform/`](./terraform/README.md). It models compute, network, storage, cloud-init bootstrapping, and a future OpenStack contract without replacing the existing container-first dev loop.

#### Stage 3 Local K3s Package
The direct-apply Stage 3 package for asynchronous, Redis-backed model serving lives under [`deploy/stage3/`](./deploy/stage3/README.md). It keeps Traefik in front of the cluster, runs one lightweight API deployment per model, scales queue workers with KEDA, stores heavy job results in MinIO, and mounts model caches at `/app/.cache` so local PVCs survive worker scale-down cycles.

#### Scripted Local Cluster Lifecycle
For the current known-good local lab flow, use the cluster scripts under [`scripts/cluster/`](./scripts/cluster):

* `./scripts/cluster/up-local-libvirt.sh`
  * Runs `terraform apply`, waits for cloud-init and k3s, refreshes the local kubeconfig, applies the Stage 3 platform, clears the shared pull-secret reference for public images, and installs the async `yolo` release.
* `./scripts/cluster/status-local-libvirt.sh`
  * Shows the current libvirt, Terraform, and Kubernetes status for the local lab.
* `./scripts/cluster/down-local-libvirt.sh`
  * Uninstalls Stage 3 workloads, runs `terraform destroy`, and cleans up stray libvirt domains/networks/pools that could otherwise block the next recreate.

#### Current Declarative Boundary
- **Declarative substrate**: Terraform manages the local libvirt VM substrate, including networks, volumes, domains, and NoCloud seed ISO creation through `libvirt_cloudinit_disk`.
- **Declarative in-cluster platform**: Kubernetes manifests and the Stage 3 Helm chart define the async API, queue workers, Redis-backed autoscaling, and MinIO-backed result storage.
- **Imperative helper layer**: [`scripts/cluster/`](./scripts/cluster) is a convenience orchestration layer for local sequencing, readiness waits, kubeconfig refresh, and initial Stage 3 installation. It is not the intended long-term control plane.
- **Future direction**: image builds are automated today, while GitOps-style deployment automation remains a future step for Stage 3 rollout.

#### Hosted Infrastructure
Deployment automation is being standardized around the same async runtime used locally.
* **CI**: GitHub Actions automatically builds and pushes a new image for any directory changed under `src/model/`.
* **Current deployment model**: Kubernetes manifests live directly in this repo under `deploy/stage3/` and the chart under `deploy/charts/model-service-stage3/`, but release application is still driven manually through `kubectl`/`helm` or the local bootstrap helper.
* **Planned deployment model**: GitOps-style reconciliation is the intended long-term replacement for the manual Stage 3 apply/Helm workflow.

&nbsp;

![Seal](https://media3.giphy.com/media/v1.Y2lkPTc5MGI3NjExazMyb3ZsanAxaDRzeTduOWU2enRyNmtlYms0Y2tmMWp6NzY0cXMyMyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/mpAJq0BoNZbig/giphy.gif)
