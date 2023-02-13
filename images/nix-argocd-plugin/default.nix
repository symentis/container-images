{ dockerTools, buildEnv, nix, bashInteractive, coreutils-full, gnutar, gzip
, gnugrep, which, curl, less, wget, man, cacert, findutils, writeTextFile
, gitMinimal, imageName ? "symentisgmbh/nix-argocd-plugin", imageTag }:
dockerTools.buildImageWithNixDb {
  name = imageName;
  tag = imageTag;

  uid = 999;
  gid = 999;

  copyToRoot = [
    (buildEnv {
      name = "image-root";
      pathsToLink = [ "/bin" "/etc" ];
      paths = [
        # nix-store uses cat program to display results as specified by
        # the image env variable NIX_PAGER.
        nix
        bashInteractive
        coreutils-full
        gnutar
        gzip
        gnugrep
        which
        curl
        less
        wget
        man
        cacert.out
        findutils
        gitMinimal
      ];
    })
    ./files-for-nix-docker-image
  ];

  config = {
    Env = [
      "NIX_PAGER=cat"
      "NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
      # A user is required by nix
      # https://github.com/NixOS/nix/blob/9348f9291e5d9e4ba3c4347ea1b235640f54fd79/src/libutil/util.cc#L478
      "USER=nobody"
    ];
    Cmd = [ "/var/run/argocd/argocd-cmp-server" ];
  };
}
