# Stage 3: Synchronous Scale-to-Zero Serving

This package turns the local K3s lab into a Stage 3 application platform:

- Traefik keeps handling north-south HTTP traffic.
- The KEDA HTTP add-on intercepts requests and scales model Deployments from zero.
- Each model release owns its own `Deployment`, `Service`, `PVC`, `Ingress`, and `HTTPScaledObject`.
- Model caches live on `local-path` PVCs mounted at `/app/.cache` so weights survive pod scale-down.

## What Gets Applied

- `platform/`
  - enables Traefik `ExternalName` backends
  - installs the pinned KEDA HTTP add-on in `keda`
  - creates the shared `model-service` namespace objects:
    - `model-service-runtime` ServiceAccount
    - `keda-http-interceptor` ExternalName alias
    - Traefik `ServersTransport` with a 125s backend timeout budget
- `../charts/model-service-stage3`
  - install one Helm release per model image

## Prerequisites

1. Stage 1 and Stage 2 are already running on the local libvirt/K3s cluster.
2. `/etc/hosts` on your workstation maps `models.local` to the Traefik ingress IP.
3. `kubectl` is pointed at that local cluster.
4. `helm` is installed on your workstation.

## Deployment Order

Run the Stage 3 deployment commands from the repo root:

```bash
cd /home/inferno9/cpp/model-service
```

The order matters:

1. Apply the shared platform layer first. This creates the `model-service`
   namespace, the shared ServiceAccount, the Traefik timeout transport, and the
   namespace-local alias to the KEDA interceptor.
2. Create the registry and app secrets after the namespace exists.
3. Copy the example values into local files and adjust them only if needed.
4. Install one model release at a time with Helm.
5. Verify cold-start routing through Traefik and KEDA.

## Step 1: Check Cluster Access

Confirm that `kubectl` can reach the local Stage 2 cluster before applying anything:

```bash
kubectl config current-context
kubectl get nodes -o wide
```

You should see the local K3s control plane and workers, not the old kind-based environment.

## Step 2: Confirm `models.local`

Make sure your workstation resolves `models.local` to the Traefik ingress IP.

If you already know the right IP, verify the hosts entry:

```bash
grep models.local /etc/hosts
```

If you need to discover Traefik first, this is the most common check on k3s:

```bash
kubectl get svc -n kube-system traefik
```

## Step 3: Apply The Shared Platform Layer

Apply the base Stage 3 components from the repo root:

```bash
kubectl apply -k deploy/stage3/platform
```

Then confirm the shared namespace objects exist:

```bash
kubectl get ns model-service
kubectl get sa -n model-service model-service-runtime
kubectl get svc -n model-service keda-http-interceptor
```

The Traefik change is a k3s `HelmChartConfig`, so give the controller a minute to reconcile before testing ingress.

## Step 4: Create The Namespace Secrets

After `model-service` exists, create the GHCR pull secret.

Example GHCR secret creation:

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --namespace model-service \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GITHUB_TOKEN
```

You can run that from any directory, but keeping the whole flow in the repo root is simpler.

If you plan to deploy WhisperX, also create the diarization token Secret:

```bash
kubectl create secret generic whisperx-env \
  --namespace model-service \
  --from-literal=HF_TOKEN=YOUR_HUGGING_FACE_TOKEN
```

Check that the secrets exist:

```bash
kubectl get secret -n model-service
```

## Step 5: Prepare Local Values Files

Start with `yolo` first, because it only needs the GHCR pull secret and is the
fastest end-to-end validation of the Stage 3 path.

Copy the example values you want to use:

```bash
cp deploy/stage3/values/yolo.values.yaml.example deploy/stage3/values/yolo.values.local.yaml
cp deploy/stage3/values/whisperx.values.yaml.example deploy/stage3/values/whisperx.values.local.yaml
```

If you only want the simplest first deploy, you can stop after copying `yolo.values.local.yaml`.

## Step 6: Install A Model Release

Install `yolo` first:

```bash
helm upgrade --install yolo deploy/charts/model-service-stage3 \
  --namespace model-service \
  -f deploy/stage3/values/yolo.values.local.yaml
```

If you also want WhisperX after that:

```bash
helm upgrade --install whisperx deploy/charts/model-service-stage3 \
  --namespace model-service \
  -f deploy/stage3/values/whisperx.values.local.yaml
```

## Step 7: Verify The Install

Confirm the add-on and model resources are healthy:

```bash
kubectl get pods -n keda
kubectl get pods -n model-service
kubectl get pvc -n model-service
kubectl get ingress -n model-service
kubectl get httpscaledobject -n model-service
kubectl get deploy -n model-service
```

For a fresh install, the model Deployment should usually sit at `0` replicas until the first request arrives.

## Step 8: Test A Cold Request

```bash
curl -H "Host: models.local" \
  -H "Content-Type: application/json" \
  -d '{"input":"https://t4.ftcdn.net/jpg/02/24/86/95/360_F_224869519_aRaeLneqALfPNBzg0xxMZXghtvBXkfIA.jpg"}' \
  http://models.local/api/v1/yolo/predict
```

In a second terminal, watch the scale-up happen:

```bash
kubectl get deploy,pods -n model-service -w
```

The first request should wake the target Deployment from `0` to `1`, and the response path now stays synchronous end to end.

## Step 9: Watch Scale-Down

After the request finishes and the deployment goes idle, KEDA should scale it back down:

```bash
kubectl get deploy -n model-service -w
```

By default, the local examples use a `scaledownPeriod` of `300` seconds, so scale-down is not immediate.
