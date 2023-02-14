## `symentisgmbh/nix-argocd-plugin`

This image can be used to use Nix flakes to generate Kubernetes manifests for use in ArgoCD.

The main reason this image exists is that `/nix` has to be writable by uid=999, the user which ArgoCD uses to execute the plugin.