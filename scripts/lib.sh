_printItalic() {
    echo -e "\e[3m$1\e[0m"
}

_printCmd () {
    echo -e "\e[1m\e[32m $\e[0m" "$@"
}

_printError () {
    echo -e "\e[1m\e[31merror:\e[0m " "$@"
}

__explainCmd () {
    local mode="$1"
    shift 1
    _printItalic "$1"
    shift 1
    _printCmd "$@"
    # shellcheck disable=SC2034
    if [ "$mode" == "subshell" ]; then
        OUTPUT=$("$@" | tee /dev/tty)
    else
        "$@"
    fi
    local ret=$?
    echo -e ""
    return $ret
}

# First argument is the explanation of the cmd
# All further arguments are the command that should be executed
#
# Will print:
# <explanation>
# $ <cmd>
# <output>
#
# Will store <output> into global variable OUTPUT
_explainCmd () {
  __explainCmd "subshell" "$@"
}

# Same as _explainCmd except that the command isn't executed in a subshell
# OUTPUT isn't populated with the output
_explainCmdNoSubshell () {
  __explainCmd "" "$@"
}

function loadDockerImage() {
    local imageFolder=$1
    local explainMessage=$2
    local imageId=$(basename $(jq -r .[0].Config < $imageFolder/manifest.json) .json)
    local imageName=$(jq -r .[0].RepoTags[0] < $imageFolder/manifest.json)
    local hasImage=true
    local dockerImageInspectJson=$(docker image inspect $imageName 2>/dev/null) || hasImage=false
    if [ "$hasImage" = true ]; then
        local loadedImageId=$(jq -r .[0].Id <<< "$dockerImageInspectJson")
        if [ "$loadedImageId" = "sha256:$imageId" ]; then
            _printItalic "Docker image '$imageName' already exists with same ID. Not loading again."
            echo
            return
        fi
    fi
    _explainCmdNoSubshell "$explainMessage" docker load -q -i $imageFolder/image.tar.gz
}

function buildImage() {
    local flakePackageName=$1 
    _explainCmdNoSubshell "Building x86_64 '$flakePackageName' image" \
        nix build ".#$flakePackageName-x86_64" --out-link .images/$flakePackageName-x86_64 -L
    loadDockerImage .images/$flakePackageName-x86_64 "Loading x86_64 '$flakePackageName' image" 
    _explainCmdNoSubshell "Building aarch64 '$flakePackageName' image" \
        nix build ".#$flakePackageName-aarch64" --out-link .images/$flakePackageName-aarch64 -L
    loadDockerImage .images/$flakePackageName-aarch64 "Loading aarch64 '$flakePackageName' image" 
}

function pushImage() {
    local localTag=$1
    local remoteTag=$2
    _explainCmdNoSubshell "Tagging $remoteTag" docker tag "$localTag" "$remoteTag"
    _explainCmdNoSubshell "Pushing $remoteTag" docker push "$remoteTag"
}

function pushMultiarch() {
    local name=$1
    local remoteNameAndTag="$name:$tag"
    pushImage "$name:x86_64" "$remoteNameAndTag-amd64"
    pushImage "$name:aarch64" "$remoteNameAndTag-arm64"
    _explainCmdNoSubshell "Creating a new docker manifest for multiarch image capability" docker manifest create \
        "$remoteNameAndTag" \
        --amend "$remoteNameAndTag-amd64" \
        --amend "$remoteNameAndTag-arm64"
    _explainCmdNoSubshell "Pushing manifest" docker manifest push "$remoteNameAndTag"
}
