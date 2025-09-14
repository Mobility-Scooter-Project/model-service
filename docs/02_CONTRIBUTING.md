# Contributing
## Adding New Runtimes
The Dockerfile in the root of this repo builds images based on their runtime (eg pytorch, tensorflow, sklearn, etc). and the specific model. If you need to add a new runtime, add a new stage to the Dockerfile named `{your-env}-builder`. This builder stage is important for caching our image layers, which can save build and download times thanks to layer caching. This stage should install the new dependency group you created for the given runtime.

## Adding New Models
Once a model's runtime exists, all you need to do is create a folder and `__init__.py` in it to createa a new model. This file should contain a *lowercase, non-space separated* class  

## CI/CD
This repo is configured to automatically build new images for every model under `src/lib/model`, likewise with deploying via an ArgoCD ApplicationSet in `deploy`. No modifications should be required to deploy or update a new model after merging into main.
