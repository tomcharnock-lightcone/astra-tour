# Source this before any chapter: `source env.sh` from the tour's folder, inside `nix develop`.
#
# It puts astra-tools' `astra` (and the Python that has astra-tools) first on PATH, and keeps the
# tour's cache and work apart from everything else. ASTRA_TOOLS_VENV picks the astra-tools
# environment; by default, the one bootstrap.sh builds in repos/astra-tools.

TOUR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
export TOUR
: "${ASTRA_TOOLS_VENV:=$TOUR/repos/astra-tools/.venv}"
export PATH="$ASTRA_TOOLS_VENV/bin:$PATH"
export ASTRA_CACHE_DIR="$TOUR/work/cache"
# This folder is a git repository, and the chapters need theirs (under work/) to have none
# above them: git looks for a repository no higher than this folder's children.
export GIT_CEILING_DIRECTORIES="$TOUR"
mkdir -p "$TOUR/work"
echo "astra: $(command -v astra) ($(astra --version 2>/dev/null))"
echo "work:  $TOUR/work"
