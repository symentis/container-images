{ kubenix, ... }: {
  kubernetes.resources.namespaces.argocd = { };
  kubernetes.resources.configMaps.nix-plugin-config = {
    metadata.namespace = "argocd";
  };
  kubernetes.helm.releases.argocd = {
    namespace = "argocd";
    chart = kubenix.lib.helm.fetch {
      chart = "argo-cd";
      repo = "https://argoproj.github.io/argo-helm";
      version = "5.20.3";
      sha256 = "eNXsg7POGn/kTztbY7XjS+nz9pkflxHfI8dcrcEZbW8=";
    };
    values = {
      dex.enabled = false;
      applicationSet.enabled = false;
      repoServer.extraContainers = [{
        # https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/
        name = "nix";
        # Entrypoint should be Argo CD lightweight CMP server i.e. argocd-cmp-server
        command = [ "/var/run/argocd/argocd-cmp-server" ];
        image = "symentisgmbh/nix-argocd-plugin:latest";
        # Only for this test. don't include this in your config
        imagePullPolicy = "Never";
        securityContext = {
          runAsNonRoot = true;
          runAsUser = 999;
        };
        volumeMounts = [
          {
            mountPath = "/var/run/argocd";
            name = "var-files";
          }
          {
            mountPath = "/home/argocd/cmp-server/plugins";
            name = "plugins";
          }
          # Optional: This could be used to change something in plugin.yaml without needing to rebuild the image.
          #   {
          #     mountPath = "/home/argocd/cmp-server/config/plugin.yaml";
          #     subPath = "plugin.yaml";
          #     name = "nix-plugin-config";
          #   }
          {
            mountPath = "/tmp";
            name = "cmp-tmp";
          }
        ];
      }];

      repoServer.volumes = [
        # Optional: This could be used to change something in plugin.yaml without needing to rebuild the image.
        # {
        #   name = "nix-plugin-config";
        #   configMap.name = "nix-plugin-config";
        # }
        {
          name = "cmp-tmp";
          emptyDir = { };
        }
      ];
    };
  };
}
