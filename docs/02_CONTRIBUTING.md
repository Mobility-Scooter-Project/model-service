# Contributing
## Adding New Models
Once a model's runtime exists, all you need to do is create a folder and `__init__.py` in it to createa a new model. This file should contain a *lowercase, non-space separated* class  

## CI/CD
This repo is configured to automatically build new images for every model under `src/lib/model`, likewise with deploying via an ArgoCD ApplicationSet in `deploy`. No modifications should be required to deploy or update a new model after merging into main.
