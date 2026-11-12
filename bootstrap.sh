#!/usr/bin/env bash
# Get astra-tools and astra-spec at the commits the tour was written against, and build
# astra-tools' environment. Run it once, inside `nix develop`, with a network connection; the
# tour then works offline.
#
#   ./bootstrap.sh
#
# ASTRA_TOOLS_URL and ASTRA_SPEC_URL say where to clone from (GitHub by default): any URL or
# path git clones, such as your own gitea. Each must hold the commit below. Run again, it
# fetches and checks out again, and keeps what is already there.
set -euo pipefail

ASTRA_TOOLS_COMMIT=a01c66535ca8313baf25a365d163eec3ac12bae5  # v0.1-rebuild: switches in place of when, no container, outputs optional
: "${ASTRA_TOOLS_URL:=https://github.com/LightconeResearch/astra-tools.git}"
: "${ASTRA_SPEC_URL:=https://github.com/LightconeResearch/astra-spec.git}"

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

echo "astra-tools' environment, on $("${UV_PYTHON:-python3}" --version)"
(cd "$repos/astra-tools" && uv sync --quiet --frozen --all-extras \
  --reinstall-package astra-tools --reinstall-package astra-spec)

"$repos/astra-tools/.venv/bin/astra" --version
"$repos/astra-tools/.venv/bin/python" -c 'import rapidfuzz, linkml_runtime' && echo "the extras load"
echo "Ready. Now: source env.sh, and open README.md."
