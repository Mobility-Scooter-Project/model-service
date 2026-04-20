## Model Service

This service provides independent model deployment for the Mobility Scooter Project. Each model is containerized as an individual Docker image to allow for granular scaling and decoupling from consumer services. 

This architecture replaces heavier alternatives like [Kubeflow](https://www.kubeflow.org/) to maintain a smaller resource footprint. Scaling in cluster will eventually be handled by [Keda](https://keda.sh/).

### Contributing

#### Adding New Models
1. Create a new directory in `src/model/`.
2. Include an `__init__.py` with a *lowercase, non-space separated* class name matching the folder name.
3. Include a `requirements.txt` file for model-specific dependencies.

#### Local Infrastructure
Local development uses a reverse proxy gateway to mimic the production environment.
* **Syncing**: Run `python scripts/generate_local_infra.py` to update `docker-compose.yaml` and `nginx.conf` based on existing model folders.
* **Execution**: Use `docker compose up -d --build` to launch the Nginx gateway and model containers.
* **Access**: Models are accessible via `http://localhost:8000/api/v1/<model_name>/predict`.

#### Local Cloud Simulation
The Terraform-based VM substrate for local cloud-style validation lives under [`terraform/`](./terraform/README.md). It models compute, network, storage, cloud-init bootstrapping, and a future OpenStack contract without replacing the existing container-first dev loop.

#### Stage 3 Local K3s Package
The direct-apply Stage 3 package for synchronous, KEDA HTTP-backed model serving lives under [`deploy/stage3/`](./deploy/stage3/README.md). It keeps Traefik in front of the cluster, routes requests through the KEDA interceptor, and mounts model caches at `/app/.cache` so local PVCs survive scale-to-zero cycles.

#### Hosted Infrastructure
Deployment to the Kubernetes cluster is fully automated.
* **CI/CD**: GitHub Actions automatically builds and pushes a new image for any directory changed under `src/model/`.
* **Deployment**: The ArgoCD ApplicationSet monitors the `src/model/` path and automatically generates a new Kubernetes deployment and ingress for each model.

&nbsp;

![Seal](https://media3.giphy.com/media/v1.Y2lkPTc5MGI3NjExazMyb3ZsanAxaDRzeTduOWU2enRyNmtlYms0Y2tmMWp6NzY0cXMyMyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/mpAJq0BoNZbig/giphy.gif)
