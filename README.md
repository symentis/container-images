# symentis-container-images

This repo contains all our public container images.

## Images

All images are tagged using this format: `<build_date>_<revision>`

 - `symentisgmbh/nix-argocd-plugin`
   This can be run as a sidecar of ArgoCD to allow using Nix to build Kubernetes manifests.
   
## Building

Run `push-images.sh`. This script will build all images push them to `hub.docker.com`.