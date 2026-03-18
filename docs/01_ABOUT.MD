### 01_ABOUT.MD

This service provides independent model deployment for the Mobility Scooter Project. Each model is containerized as an individual Docker image to allow for granular scaling and decoupling from consumer services. 

This architecture replaces heavier alternatives like [Kubeflow](https://www.kubeflow.org/) to maintain a smaller resource footprint. Scaling in cluster will eventually be handled by [Keda](https://keda.sh/).


![About Seal](https://c.tenor.com/SdLIKYn92AIAAAAC/seal-cute.gif)