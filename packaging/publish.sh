#!/usr/bin/env bash
# Sends the manifests in packaging/ (already filled in by update-manifests.sh)
# to a package repository.
#
#   publish.sh winget   pull request to microsoft/winget-pkgs, one per version
#   publish.sh aur      push to the AUR package lumtub-bin
#
# winget needs GH_TOKEN: a classic personal access token of the
# account the pull requests come from (scopes public_repo and workflow, as
# the fork holds those repositories' workflows). aur needs AUR_SSH_KEY: the
# private SSH key registered with the AUR account that owns lumtub-bin.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target=${1:-}

version=$(sed -n 's/^PackageVersion: //p' "$here/winget/Lumtub.Lumtub.yaml")
full=$(python3 -Ic 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$here/scoop/lumtub.json")
if [[ $version == 0.2.29 || $full == *0000000 ]]; then
  echo "The manifests still hold placeholders; run update-manifests.sh first." >&2
  exit 1
fi

# Puts files on a new branch of the token owner's fork of $1 (made when
# missing) and opens a pull request from it. $2 branch, $3 title, $4 body,
# then pairs of <path in the repository> <local file>.
pull_request() {
  local upstream=$1 branch=$2 title=$3 body=$4
  shift 4
  local me fork base default
  me=$(gh api user --jq .login)
  default=${BASE_BRANCH:-$(gh api "repos/$upstream" --jq .default_branch)}
  fork=$(gh api -X POST "repos/$upstream/forks" -f default_branch_only=true --jq .full_name)
  for _ in $(seq 1 30); do
    gh api "repos/$fork" --silent 2>/dev/null && break
    sleep 10
  done
  base=$(gh api "repos/$upstream/git/ref/heads/$default" --jq .object.sha)
  # A fork shares its upstream's objects, so the branch can start at
  # upstream's newest commit without syncing the fork first.
  if gh api "repos/$fork/git/ref/heads/$branch" --silent 2>/dev/null; then
    gh api -X PATCH "repos/$fork/git/refs/heads/$branch" -f sha="$base" -F force=true --silent
  else
    gh api -X POST "repos/$fork/git/refs" -f ref="refs/heads/$branch" -f sha="$base" --silent
  fi
  while (($#)); do
    local path=$1 file=$2
    shift 2
    gh api -X PUT "repos/$fork/contents/$path" -f message="$title" -f branch="$branch" \
      -f content="$(base64 -w0 "$file")" --silent
  done
  gh api -X POST "repos/$upstream/pulls" -f title="$title" -f head="$me:$branch" -f base="$default" \
    -f body="$body" --jq .html_url
}

# Whether $1 has an open pull request titled $2.
open_pull_request() {
  local count
  count=$(gh api -X GET search/issues -f q="repo:$1 is:pr is:open in:title \"$2\"" --jq .total_count)
  ((count > 0))
}

case $target in
  winget)
    repo=microsoft/winget-pkgs
    folder=manifests/l/Lumtub/Lumtub/$version
    if gh api "repos/$repo/contents/$folder" --silent 2>/dev/null; then
      echo "WinGet already has Lumtub $version."
      exit 0
    fi
    if gh api "repos/$repo/contents/manifests/l/Lumtub/Lumtub" --silent 2>/dev/null; then
      title="New version: Lumtub.Lumtub version $version"
    else
      title="New package: Lumtub.Lumtub version $version"
    fi
    if open_pull_request "$repo" "Lumtub.Lumtub version $version"; then
      echo "A pull request for Lumtub $version is already open."
      exit 0
    fi
    body="Lumtub $version: https://github.com/0x696c757a696f/lumtub/releases/tag/v$full

Three manifests (version, default locale, installer) for one package version, schema 1.6.0. The installer is a per-user Inno Setup program (\`Scope: user\`) that WinGet runs silently."
    pull_request "$repo" "lumtub-$version" "$title" "$body" \
      "$folder/Lumtub.Lumtub.yaml" "$here/winget/Lumtub.Lumtub.yaml" \
      "$folder/Lumtub.Lumtub.locale.en-US.yaml" "$here/winget/Lumtub.Lumtub.locale.en-US.yaml" \
      "$folder/Lumtub.Lumtub.installer.yaml" "$here/winget/Lumtub.Lumtub.installer.yaml"
    ;;
  aur)
    : "${AUR_SSH_KEY:?AUR_SSH_KEY is not set}"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    printf '%s\n' "$AUR_SSH_KEY" > "$work/key"
    chmod 600 "$work/key"
    ssh-keyscan aur.archlinux.org > "$work/known_hosts" 2>/dev/null
    export GIT_SSH_COMMAND="ssh -i $work/key -o UserKnownHostsFile=$work/known_hosts -o IdentitiesOnly=yes"
    git clone -q ssh://aur@aur.archlinux.org/lumtub-bin.git "$work/aur"
    cp "$here/aur/PKGBUILD" "$here/aur/.SRCINFO" "$here/aur/lumtub.png" "$here/aur/io.github.lumtub.lumtub.desktop" "$work/aur/"
    cd "$work/aur"
    if [[ -n ${AUR_NAME:-} ]]; then
      sed -i "1s|^# Maintainer: .*|# Maintainer: $AUR_NAME <${AUR_EMAIL:-}>|" PKGBUILD
    fi
    git add PKGBUILD .SRCINFO lumtub.png io.github.lumtub.lumtub.desktop
    if git diff --cached --quiet; then
      echo "The AUR already has lumtub-bin $version."
      exit 0
    fi
    git -c user.name="${AUR_NAME:-Lumtub}" -c user.email="${AUR_EMAIL:-lumtub@users.noreply.github.com}" commit -q -m "lumtub-bin $version"
    git push -q origin HEAD:master
    echo "Pushed lumtub-bin $version to the AUR."
    ;;
  *)
    echo "Usage: $0 winget|aur" >&2
    exit 1
    ;;
esac
