# Stage 3: Async API + Queue Workers

This package turns the local K3s lab into an async model-serving platform:

- Traefik handles north-south HTTP traffic.
- Each model release owns:
  - one always-on API `Deployment`
  - one queue worker `Deployment`
  - one KEDA `ScaledObject` that scales workers from Redis queue depth
  - one model-cache PVC mounted at `/app/.cache` on workers
- Redis stores only small job metadata.
- MinIO stores heavy result JSON blobs, which clients fetch by pre-signed URL.

## What Gets Applied

- `platform/`
  - `model-service` namespace and shared ServiceAccount
  - shared Redis deployment/service/PVC
  - shared MinIO deployment/service/PVC
  - shared runtime config and secrets for Redis and object storage
- `../charts/model-service-stage3`
  - install one async model release per image

## Prerequisites

1. Stage 1 and Stage 2 are already running on the local libvirt/K3s cluster.
2. `kubectl` points at that cluster.
3. `helm` is installed locally.
4. Your workstation can reach the local Traefik ingress IP.

## Scripted Shortcut

The fastest path to the current known-good local state is:

```bash
./scripts/cluster/up-local-libvirt.sh
```

That script:

- applies the local-libvirt Terraform stack
- refreshes kubeconfig from the control plane
- applies the async Stage 3 platform
- installs the `yolo` async release

For inspection and teardown:

```bash
./scripts/cluster/status-local-libvirt.sh
./scripts/cluster/down-local-libvirt.sh
```

## Manual Flow

From the repo root:

```bash
cd /home/inferno9/cpp/model-service
```

1. Apply the shared platform:

```bash
kubectl apply -k deploy/stage3/platform
```

2. Create pull/app secrets as needed:

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --namespace model-service \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GITHUB_TOKEN
```

```bash
kubectl create secret generic whisperx-env \
  --namespace model-service \
  --from-literal=HF_TOKEN=YOUR_HUGGING_FACE_TOKEN
```

3. Install a model release:

```bash
helm upgrade --install yolo deploy/charts/model-service-stage3 \
  --namespace model-service \
  -f deploy/stage3/values/yolo.values.local.yaml
```

```bash
helm upgrade --install whisperx deploy/charts/model-service-stage3 \
  --namespace model-service \
  -f deploy/stage3/values/whisperx.values.local.yaml
```

## Verify

```bash
kubectl get deploy,pods,svc,ingress,scaledobject -n model-service
kubectl get pods -n keda
kubectl get pods,svc,pvc -n model-service
```

Expected shape:

- API deployments stay at `1` replica.
- Worker deployments sit at `0` replicas until a job is queued.
- Redis and MinIO stay available in the `model-service` namespace.

## Test A Job

Use the HTTP examples under `http/yolo/` or `http/whisperx/`.

Yolo example:

```bash
curl -H "Host: models.local" \
  -H "Content-Type: application/json" \
  -d '{"get_url":"https://t4.ftcdn.net/jpg/02/24/86/95/360_F_224869519_aRaeLneqALfPNBzg0xxMZXghtvBXkfIA.jpg"}' \
  http://10.42.0.10/api/v1/yolo/jobs
```

Then poll the returned `status_url` until the response contains:

- `"status": "succeeded"`
- `"result_get_url": "..."` for direct MinIO download

While the job is running, watch worker scale-up:

```bash
kubectl get deploy,pods -n model-service -w
```
