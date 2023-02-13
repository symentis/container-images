{ lib, writeShellScriptBin, git }:
writeShellScriptBin "push-images.sh" ''
  PATH=${lib.makeBinPath [ git ]}:$PATH
  set -uo pipefail
  set -o errtrace
  trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR
  IFS=$'\n\t'
  ${builtins.readFile ./lib.sh}
  _explainCmd "Ensuring you are logged in to hub.docker.com" docker login

  if [ ! -z $(git status --porcelain | xargs) ]; then 
    _printError "You have uncomitted changes."
    # exit 1
  fi

  tag="$(date +%Y-%m-%d)_$(git rev-parse HEAD | xargs)"
  echo "Tag for all images will be '$tag'"
  echo

  buildImage "nix-argocd-plugin"

  echo "Uploading all images to hub.docker.symentis..."
  pushMultiarch "symentisgmbh/nix-argocd-plugin" 
''
