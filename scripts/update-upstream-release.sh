#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update-upstream-release.sh [--dry-run] [--upstream-repo owner/name]

Update PKGBUILD and .SRCINFO to match the latest upstream release tag.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

dry_run=false
upstream_repo="${UPSTREAM_REPO:-alajmo/mani}"
pkgbuild_path="PKGBUILD"
srcinfo_path=".SRCINFO"

while (($# > 0)); do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --upstream-repo)
      upstream_repo="${2:?missing value for --upstream-repo}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

require_command curl
require_command git
require_command jq
require_command makepkg
require_command sed

current_pkgver="$(sed -n "s/^pkgver=//p" "$pkgbuild_path" | head -n 1)"
current_pkgrel="$(sed -n "s/^pkgrel=//p" "$pkgbuild_path" | head -n 1)"
current_commit="$(sed -n "s/^_commit='\([^']*\)'/\1/p" "$pkgbuild_path" | head -n 1)"

if [[ -z "$current_pkgver" || -z "$current_pkgrel" || -z "$current_commit" ]]; then
  echo "Failed to parse current package metadata from $pkgbuild_path" >&2
  exit 1
fi

if [[ ! "$current_pkgrel" =~ ^[0-9]+$ ]]; then
  echo "pkgrel must be numeric: $current_pkgrel" >&2
  exit 1
fi

api_headers=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  api_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

latest_tag=""
if release_json="$(curl --fail --silent --show-error "${api_headers[@]}" "https://api.github.com/repos/${upstream_repo}/releases/latest" 2>/dev/null)"; then
  latest_tag="$(jq -r '.tag_name // empty' <<<"$release_json")"
fi

if [[ -z "$latest_tag" ]]; then
  tags_json="$(curl --fail --silent --show-error "${api_headers[@]}" "https://api.github.com/repos/${upstream_repo}/tags?per_page=1")"
  latest_tag="$(jq -r '.[0].name // empty' <<<"$tags_json")"
fi

if [[ -z "$latest_tag" ]]; then
  echo "Could not determine the latest upstream tag for ${upstream_repo}" >&2
  exit 1
fi

tag_refs="$(git ls-remote --tags "https://github.com/${upstream_repo}.git" "refs/tags/${latest_tag}" "refs/tags/${latest_tag}^{}")"
latest_commit="$(awk '
  $2 ~ /\^\{\}$/ { dereferenced = $1 }
  $2 !~ /\^\{\}$/ { direct = $1 }
  END {
    if (dereferenced != "") {
      print dereferenced
    } else {
      print direct
    }
  }
' <<<"$tag_refs")"

if [[ -z "$latest_commit" ]]; then
  echo "Could not resolve commit for upstream tag ${latest_tag}" >&2
  exit 1
fi

latest_pkgver="${latest_tag#v}"
next_pkgrel="$current_pkgrel"

if [[ "$latest_pkgver" != "$current_pkgver" ]]; then
  next_pkgrel=1
elif [[ "$latest_commit" != "$current_commit" ]]; then
  next_pkgrel=$((current_pkgrel + 1))
fi

if [[ "$latest_pkgver" == "$current_pkgver" && "$latest_commit" == "$current_commit" ]]; then
  echo "No update needed: ${current_pkgver} (${current_commit}) is already current."
  exit 0
fi

echo "Current version: ${current_pkgver}-${current_pkgrel} @ ${current_commit}"
echo "Latest version:  ${latest_pkgver}-${next_pkgrel} @ ${latest_commit}"

if [[ "$dry_run" == true ]]; then
  exit 0
fi

tmp_pkgbuild="$(mktemp)"
trap 'rm -f "$tmp_pkgbuild"' EXIT

sed \
  -e "s/^pkgver=.*/pkgver=${latest_pkgver}/" \
  -e "s/^pkgrel=.*/pkgrel=${next_pkgrel}/" \
  -e "s/^_commit='[^']*'/_commit='${latest_commit}'/" \
  "$pkgbuild_path" > "$tmp_pkgbuild"
mv "$tmp_pkgbuild" "$pkgbuild_path"

makepkg --printsrcinfo > "$srcinfo_path"

echo "Updated ${pkgbuild_path} and ${srcinfo_path}."
