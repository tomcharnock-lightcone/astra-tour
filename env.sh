# Source this before any chapter: `source env.sh` from the tour's folder, in bash or zsh.
#
# It puts astra-tools' `astra` (and the Python that has astra-tools) first on PATH, and keeps the
# tour's cache and work apart from everything else. ASTRA_TOOLS_VENV picks the astra-tools
# environment; by default, the one bootstrap.sh builds in repos/astra-tools.
#
# The chapters' analyses declare one another by URLs that stand for their repositories, under
# https://astra-examples.invalid/ and https://astra-tour.invalid/, which no network serves. git,
# which astra-tools runs to fetch, reads them from the copies under work/ instead: the setting
# `url.<copy>.insteadOf`, given here through git's environment (git 2.31 or later). work/build
# is the examples' copy of the chapter set up last; chapter 1's upstream is in work/01.

TOUR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
export TOUR
: "${ASTRA_TOOLS_VENV:=$TOUR/repos/astra-tools/.venv}"
export PATH="$ASTRA_TOOLS_VENV/bin:$PATH"
export ASTRA_CACHE_DIR="$TOUR/work/cache"
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0="url.file://$TOUR/work/build/.insteadOf"
export GIT_CONFIG_VALUE_0=https://astra-examples.invalid/
export GIT_CONFIG_KEY_1="url.file://$TOUR/work/01/.insteadOf"
export GIT_CONFIG_VALUE_1=https://astra-tour.invalid/
# This folder is a git repository, and the chapters need theirs (under work/) to have none
# above them: git looks for a repository no higher than this folder's children.
export GIT_CEILING_DIRECTORIES="$TOUR"
mkdir -p "$TOUR/work"
echo "astra: $(command -v astra) ($(astra --version 2>/dev/null))"
echo "work:  $TOUR/work"
