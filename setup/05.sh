#!/bin/sh
# Chapter 5: (re)create $TOUR/work/05 from nothing. It copies the examples there and runs
# build.py, which makes two git repositories, build/noisy-line and build/line-fit, with the
# eight-step history of examples/README.md, and fixes its own commit ids (a fixed author and
# fixed dates, the user's git configuration left out). It removes work/05 first, and nothing
# else. It warns when python3 isn't 3.14, since run.py's records name it, and so the ids differ.
set -eu

if [ -z "${TOUR:-}" ]; then
  echo "setup/05.sh: source env.sh first" >&2
  exit 2
fi
command -v astra >/dev/null || { echo "setup/05.sh: no astra on PATH: source env.sh" >&2; exit 2; }

rm -rf "$TOUR/work/05"
mkdir -p "$TOUR/work/05"
cp -R "$TOUR/examples/." "$TOUR/work/05/"
rm -rf "$TOUR/work/05/build"

cd "$TOUR/work/05"
# build.py gives each git and run.py process it starts its own environment (examples/build.py:47-60):
# the cache work/05/build/cache, a fixed identity and dates, no git configuration of the
# user's, and git's url.<build/>.insteadOf for the examples' URLs. So the build leaves the
# tour's cache, work/cache, alone, and makes no work/05/cache.
python build.py
# The chapter's astra commands read the examples' URLs from work/build, through env.sh's
# url.<copy>.insteadOf: make it this chapter's copy.
ln -sfn 05/build "$TOUR/work/build"

version=$(python3 -c 'import platform; print(".".join(platform.python_version_tuple()[:2]))')
if [ "$version" != 3.14 ]; then
  echo "setup/05.sh: python3 is $version, not 3.14: run.py's records name it, so every commit" \
       "id from \"Build the points\" on differs from the chapter's, the commit line-fit declares" \
       "among them. For the chapter's ids, run ./bootstrap.sh, which builds astra-tools'" \
       "environment on Python 3.14; then source env.sh again and rerun sh setup/05.sh" >&2
fi
