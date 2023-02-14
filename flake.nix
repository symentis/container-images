{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    flake-utils.url = "github:numtide/flake-utils";
    kubenix.url = "github:hall/kubenix";
  };
  outputs = { self, nixpkgs, flake-utils, kubenix }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # macOS builder support:
        # - We can use `nixpkgs.legacyPackages.x86_64-darwin.dockerTools` to build a `x86_64-linux` container
        # - We can use `nixpkgs.legacyPackages.aarch64-darwin.dockerTools` to build a `aarch64-linux` container
        systemX86 = builtins.replaceStrings [ "aarch64" ] [ "x86_64" ] system;
        systemAarch64 =
          builtins.replaceStrings [ "x86_64" ] [ "aarch64" ] system;

        # In order to have a quicker change-build-test cycle we store the manifest.json next to the .tar.gz and only load a .tar.gz if it isn't already loaded.
        extractManifestFromImage = image:
          nixpkgs.legacyPackages.${system}.runCommand
          "extract-manifest-from-image-${image.name}" { } ''
            mkdir $out
            ln -s ${image} $out/image.tar.gz
            ${pkgs.gnutar}/bin/tar -xOzf $out/image.tar.gz manifest.json > $out/manifest.json
          '';

        # We use `x86_64-linux.callPackage` here, as most package arguments are packages which end up in the container => Linux
        # We override `dockerTools`, this is only used for the build host => Darwin if possible
        callContainerX86 = directory:
          let
            dockerTools = nixpkgs.legacyPackages.${systemX86}.dockerTools;
            image = nixpkgs.legacyPackages.x86_64-linux.callPackage
              (import directory) {
                inherit dockerTools;
                imageTag = "x86_64";
              };
          in extractManifestFromImage image;
        callContainerAarch64 = directory:
          let
            dockerTools = nixpkgs.legacyPackages.${systemAarch64}.dockerTools;
            image = nixpkgs.legacyPackages.aarch64-linux.callPackage
              (import directory) {
                inherit dockerTools;
                imageTag = "aarch64";
              };
          in extractManifestFromImage image;

        linuxOnlyPackages =
          if system == "x86_64-linux" || system == "aarch64-linux" then {
            nix-argocd-plugin-test =
              nixpkgs.legacyPackages.${system}.callPackage
              (import images/nix-argocd-plugin/test) {
                inherit kubenix;
                testSystem = system;
              };
          } else
            { };
      in {

        packages = {
          nix-argocd-plugin-x86_64 = callContainerX86 images/nix-argocd-plugin;
          nix-argocd-plugin-aarch64 =
            callContainerAarch64 images/nix-argocd-plugin;

          #
          kubenix = {
            nixapp = (kubenix.evalModules.${system} {
              module = { kubenix, ... }: {
                imports = with kubenix.modules; [ k8s helm ];
              };
              kubernetes.resources.pods.example = {
                meta.namespace = "test";
                spec.containers.ex.image = "rancher/mirrored-pause:3.6";
              };
            }).config.kubernetes.result;
          };
        } // linuxOnlyPackages;
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs;
            [
              #
              (callPackage scripts/push-images.nix { })
            ];
        };
      }));
}

