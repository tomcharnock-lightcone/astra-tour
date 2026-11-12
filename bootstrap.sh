#!/usr/bin/env bash
# Get astra-tools and astra-spec at the commits the tour was written against, and build
# astra-tools' environment. Run it once, with a network connection; the tour then works
# offline. It needs git 2.31 or later and uv.
#
#   ./bootstrap.sh
#
# ASTRA_TOOLS_URL and ASTRA_SPEC_URL say where to clone from (GitHub by default): any URL or
# path git clones, such as your own gitea. Each must hold the commit below. Run again, it
# fetches and checks out again, and keeps what is already there.
#
# UV_PYTHON picks the Python the environment is built on: 3.14 by default, a CPython 3.14 that
# uv finds or else downloads (`nix develop` sets it to the flake's). The examples' records name
# its version, so the chapters' commit ids hold only on 3.14.
set -euo pipefail

ASTRA_TOOLS_COMMIT=d14bf162aff99ebe939d947fed6c532fe4b4ea05  # v0.1-rebuild: switches, no container, outputs optional, the spec in its LinkML layout
: "${ASTRA_TOOLS_URL:=https://github.com/LightconeResearch/astra-tools.git}"
: "${ASTRA_SPEC_URL:=https://github.com/LightconeResearch/astra-spec.git}"

: "${UV_PYTHON:=3.14}"
export UV_PYTHON

if ! command -v uv >/dev/null; then
  echo "bootstrap.sh: uv isn't on PATH: install it (https://docs.astral.sh/uv/)" >&2
  exit 2
fi
# git takes settings from its environment (GIT_CONFIG_COUNT), as env.sh gives them, since 2.31.
version="$(git --version | sed -n 's/^git version \([0-9]*\.[0-9]*\).*/\1/p')"
IFS=. read -r major minor <<<"$version"
if (( major < 2 || (major == 2 && minor < 31) )); then
  echo "bootstrap.sh: $(git --version) is older than 2.31, which the tour needs" >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repos="$here/repos"
mkdir -p "$repos"

get() { # get <folder> <url>: clone, or fetch where already cloned
  if [[ -d "$repos/$1/.git" ]]; then
    git -C "$repos/$1" fetch --quiet origin
  else
    git clone --quiet --no-checkout "$2" "$repos/$1"
  fi
}

echo "astra-tools from $ASTRA_TOOLS_URL"
get astra-tools "$ASTRA_TOOLS_URL"
git -C "$repos/astra-tools" -c advice.detachedHead=false checkout --quiet --detach "$ASTRA_TOOLS_COMMIT"

pin="$(tr -d '[:space:]' < "$repos/astra-tools/astra-spec.pin")"
echo "astra-spec from $ASTRA_SPEC_URL, at astra-tools' pin $pin"
get astra-spec "$ASTRA_SPEC_URL"
# astra-tools installs astra-spec, editable, from ../astra-spec-pinned: a worktree at the pin.
if [[ -e "$repos/astra-spec-pinned" ]]; then
  git -C "$repos/astra-spec-pinned" -c advice.detachedHead=false checkout --quiet --detach "$pin"
else
  git -C "$repos/astra-spec" worktree add --quiet --detach ../astra-spec-pinned "$pin"
fi

echo "astra-tools' environment, on Python $UV_PYTHON"
(cd "$repos/astra-tools" && uv sync --quiet --frozen --all-extras \
  --reinstall-package astra-tools --reinstall-package astra-spec)

"$repos/astra-tools/.venv/bin/python" --version
"$repos/astra-tools/.venv/bin/astra" --version
"$repos/astra-tools/.venv/bin/python" -c 'import rapidfuzz, linkml_runtime' && echo "the extras load"
echo "Ready. Now: source env.sh, and open README.md."
