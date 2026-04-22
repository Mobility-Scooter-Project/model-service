### 01_ABOUT.MD

This service provides independent model deployment for the Mobility Scooter Project. Each model is containerized as an individual Docker image to allow for granular scaling and decoupling from consumer services. 

This architecture replaces heavier alternatives like [Kubeflow](https://www.kubeflow.org/) to maintain a smaller resource footprint. The current Kubernetes path uses an always-on API, Redis-backed job metadata, MinIO result blobs, and [Keda](https://keda.sh/) for worker autoscaling.
