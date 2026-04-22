### 02_CONTRIBUTING.md

#### Adding New Models
1. Create a new directory in `src/model/`.
2. Include an `__init__.py` with a *lowercase, non-space separated* class name matching the folder name.
3. Include a `requirements.txt` file for model-specific dependencies.

#### Local Infrastructure
Local development now targets the shared local-libvirt + k3s environment and the async Stage 3 package under `deploy/stage3/`.
* **Bootstrap**: Use `./scripts/cluster/up-local-libvirt.sh` to recreate the local lab. Treat it as a convenience helper for local sequencing, not the long-term deployment control plane.
* **Execution**: Submit jobs to `http://models.local/api/v1/<model_name>/jobs`.
* **Inspection**: Use `./scripts/cluster/status-local-libvirt.sh` and the HTTP examples under `http/`.

#### Hosted Infrastructure
Deployment automation is being consolidated around the repo-owned Stage 3 chart and manifests.
* **CI**: GitHub Actions automatically builds and pushes a new image for any directory changed under `src/model/`.
* **Deployment Today**: Runtime manifests live under `deploy/stage3/` and `deploy/charts/model-service-stage3/`, but rollout is still applied manually with `kubectl`/`helm` or the local helper.
* **Deployment Target**: GitOps-style reconciliation should eventually replace the current manual Stage 3 apply/Helm workflow.
