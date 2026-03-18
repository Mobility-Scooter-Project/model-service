### 02_CONTRIBUTING.md

#### Adding New Models
1. Create a new directory in `src/model/`.
2. Include an `__init__.py` with a *lowercase, non-space separated* class name matching the folder name.
3. Include a `requirements.txt` file for model-specific dependencies.

#### Local Infrastructure
Local development uses a reverse proxy gateway to mimic the production environment.
* **Syncing**: Run `python scripts/generate_local_infra.py` to update `docker-compose.yaml` and `nginx.conf` based on existing model folders.
* **Execution**: Use `docker compose up -d --build` to launch the Nginx gateway and model containers.
* **Access**: Models are accessible via `http://localhost:8000/api/v1/<model_name>/predict`.

#### Hosted Infrastructure
Deployment to the Kubernetes cluster is fully automated.
* **CI/CD**: GitHub Actions automatically builds and pushes a new image for any directory changed under `src/model/`.
* **Deployment**: The ArgoCD ApplicationSet monitors the `src/model/` path and automatically generates a new Kubernetes deployment and ingress for each model.