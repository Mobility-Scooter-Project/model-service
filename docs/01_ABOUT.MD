# Model Service
## About
This repo contains all the models deployed to support the Mobility Scooter Project. Each model gets its own docker image and deployment on our cluster, with scaling eventually being handled by Keda.

## Motivation
Originally, we planned to use [Kubeflow](https://www.kubeflow.org/), however its dependency on [Knative](https://knative.dev/docs/) was a deal breaker due to its massive container and RAM footprint. This service is designed to replace Kubeflow Serve, providing a structured way for us to deploy our models independently from any services that may rely on them.