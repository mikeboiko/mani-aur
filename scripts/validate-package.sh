#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: validate-package.sh [--build]

Validate PKGBUILD and .SRCINFO. Use --build to perform a full package build.
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

build_package=false

while (($# > 0)); do
  case "$1" in
    --build)
      build_package=true
      shift
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

require_command diff
require_command makepkg
require_command namcap
require_command sed

generated_srcinfo="$(mktemp)"
built_package=""

cleanup() {
  rm -f "$generated_srcinfo"
}

trap cleanup EXIT

makepkg --printsrcinfo > "$generated_srcinfo"
diff -u .SRCINFO "$generated_srcinfo"

makepkg --verifysource --nocolor
makepkg --packagelist --nobuild --nodeps --noconfirm --nocolor >/dev/null
namcap PKGBUILD

if [[ "$build_package" == true ]]; then
  built_package="$(makepkg --packagelist --nocolor | head -n 1)"
  makepkg --cleanbuild --force --nodeps --noconfirm --nocolor
  namcap "$built_package"
fi
