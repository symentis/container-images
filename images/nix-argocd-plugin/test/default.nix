{ nixosTest, kubenix, testSystem }:
nixosTest ({ pkgs, lib, ... }:
  let
    imagesToLoad = [
      "${pkgs.dockerTools.pullImage {
        imageName = "rancher/mirrored-pause";
        finalImageTag = "3.6";
        imageDigest =
          "sha256:c2280d2f5f56cf9c9a01bb64b2db4651e35efd6d62a54dcfc12049fe6449c5e4";
        sha256 = "IbuPXoalV8gKCZGMteRzkeG65o4GCu3G+UX+lVLAo2I=";
      }}"
      "${pkgs.dockerTools.pullImage {
        imageName = "quay.io/argoproj/argocd";
        finalImageTag = "v2.6.1";
        imageDigest =
          "sha256:be13ff4b45ce072fc3bbea7530d96a2a426c830382a7ed38ed30a2cf0266b2a7";
        sha256 = "Puc4LQuxU+Etwq/hKYjXbgPiQ/z+xtXxZPlZxOP1W84=";
      }}"
      "${pkgs.dockerTools.pullImage {
        imageName = "public.ecr.aws/docker/library/redis";
        finalImageTag = "7.0.7-alpine";
        imageDigest =
          "sha256:c471377fed91097d187869cd000f09922b5ea2ce1fa785e58597f5d6c7bb4efd";
        sha256 = "UlQ2+obP1NNRbU5GnAHyz4ng4TmVUd81NKq3F+DTeDw=";
      }}"
      "${pkgs.dockerTools.pullImage {
        imageName = "rancher/mirrored-coredns-coredns";
        finalImageTag = "1.9.1";
        imageDigest =
          "sha256:bde552a948be64907cbff62e8d333addbbff3ea2be3a0738971c32b6956a3057";
        sha256 = "gFn7oIUGtNPsSEzbCKHMgKggjoyO2xmyKH5iyxLy96w=";
      }}"
      # "${pkgs.dockerTools.pullImage {
      #   imageName = "rancher/local-path-provisioner";
      #   finalImageTag = "v0.0.21";
      #   imageDigest =
      #     "sha256:cf7422ac6e9bc9a5cb9ae913bdc8b0f20db8db6f5b77ea5a6446338ea3acd8fc";
      #   sha256 = "UlQ2+obP1NNRbU5GnAHyz4ng4TMVUd81NKq3F+DTeDw=";
      # }}"
    ];
    pluginUnderTest = pkgs.callPackage (import ../.) {
      imageName = "docker.io/symentisgmbh/nix-argocd-plugin";
      imageTag = "latest";
    };
    kubenixRender = moduleArg:
      (kubenix.evalModules.${testSystem} {
        module = { kubenix, ... }: {
          imports = with kubenix.modules; [ k8s helm moduleArg ];
        };
      }).config.kubernetes.result;
  in {
    name = "nix-argocd-plugin";
    nodes.machine = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [ k3s gzip argocd jq ];

      networking.firewall.enable = false;

      # k3s uses enough resources the default vm fails.
      virtualisation.memorySize = 1536;
      virtualisation.diskSize = 4096;

      systemd.services.mock-git = {
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ git python3 ];
        script = ''
          cp -r ${../../..} /tmp/this-flake-git
          cd /tmp/this-flake-git
          git init .
          git add .
          git config user.email "you@example.com"
          git config user.name "Your Name"
          git commit -am "Initial commit"
          git update-server-info
          cd .git
          python -m http.server 8080
        '';
      };

      services.k3s.enable = true;
      services.k3s.role = "server";
      services.k3s.package = pkgs.k3s;
      # Slightly reduce resource usage
      services.k3s.extraFlags = builtins.toString [
        # "--disable"
        # "coredns"
        "--disable"
        "local-storage"
        "--disable"
        "metrics-server"
        "--disable"
        "traefik"
      ];
    };

    testScript = ''
      import time

      start_all()
      machine.wait_for_unit("k3s")
      machine.wait_for_unit("mock-git")

      machine.succeed("k3s kubectl cluster-info")
      machine.succeed("k3s check-config")

      machine.succeed("zcat ${pluginUnderTest} | k3s ctr image import -")
      ${lib.concatMapStringsSep "\n"
      (image: ''machine.succeed("k3s ctr image import ${image}")'')
      imagesToLoad}

      machine.succeed("k3s kubectl -n kube-system wait deployment coredns --for condition=Available=True --timeout=90s")

      machine.succeed("k3s kubectl apply -f ${kubenixRender ./argocd.nix}")
      machine.succeed("k3s kubectl -n argocd wait deployment argocd-repo-server --for condition=Available=True --timeout=90s")
      machine.succeed("k3s kubectl -n argocd wait deployment argocd-server --for condition=Available=True --timeout=90s")

      # adminPass = machine.succeed('k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -').strip()
      # print("Got admin pass '" + adminPass + "'")
      # envVars = "ARGOCD_OPTS='--port-forward --port-forward-namespace argocd' KUBECONFIG=/etc/rancher/k3s/k3s.yaml "
      # machine.succeed(envVars + 'argocd login --core --username admin --password ' + adminPass)

      machine.succeed("k3s kubectl apply -f ${./nixapp-definition.yaml}")

      time.sleep(10.0)
      assert "1" == machine.succeed("k3s kubectl get pods -o json | jq '.items | length'").strip()

      machine.shutdown()
    '';
  })
