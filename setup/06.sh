#!/bin/sh
# Chapter 6, "astra-tools from Python, and a map of the code": (re)creates $TOUR/work/06.
#
# It copies the tour's examples into work/06 and runs build.py there, which makes the two
# example repositories, noisy-line and line-fit, under work/06/build with their eight-step
# history and fixed commit ids. Then it writes work/06/plugin: a package that registers an
# environment scheme and a stand-in through astra-tools' entry points, installed nowhere, found
# only where PYTHONPATH names its folder. It removes work/06 first, and nothing else. It warns
# when python3 isn't 3.14: run.py's records name it by its version, so the ids differ.
set -eu

: "${TOUR:?source env.sh first, from the tour's folder}"
command -v astra >/dev/null || { echo "setup/06.sh: no astra on PATH: source env.sh" >&2; exit 2; }

rm -rf "$TOUR/work/06"
mkdir -p "$TOUR/work/06"
cp -R "$TOUR/examples/." "$TOUR/work/06/"
rm -rf "$TOUR/work/06/build"
find "$TOUR/work/06" -name __pycache__ -type d -prune -exec rm -rf {} +

cd "$TOUR/work/06"
python build.py
# The chapter's astra commands read the examples' URLs from work/build, through env.sh's
# url.<copy>.insteadOf: make it this chapter's copy.
ln -sfn 06/build "$TOUR/work/build"

mkdir -p plugin/tour_plugin-0.1.dist-info

cat > plugin/tour_plugin-0.1.dist-info/METADATA <<'EOF'
Metadata-Version: 2.1
Name: tour-plugin
Version: 0.1
EOF

cat > plugin/tour_plugin-0.1.dist-info/entry_points.txt <<'EOF'
[astra.environments]
tour-python = tour_plugin:ENVIRONMENT

[astra.standins]
tour-pointer = tour_plugin:STANDIN
EOF

cat > plugin/tour_plugin.py <<'EOF'
"""A plug-in for astra-tools: an environment scheme and a stand-in."""

from dataclasses import dataclass


@dataclass(frozen=True)
class ExamplesPython:
    """The environments run.py records: urn:astra-examples:<implementation>-<version>."""

    name: str = "tour-python"

    def recognises(self, iri):
        return iri.startswith("urn:astra-examples:")

    def holds(self, iri):
        return f"python3 {iri.rpartition('-')[2]}, its standard library only"

    def recreatable(self, iri):
        return False


@dataclass(frozen=True)
class TourPointer:
    """A file at the path whose two lines are `tour-pointer` and `sha256:<digest> <size>`."""

    name: str = "tour pointer"

    def place(self, path):
        return path

    def recognises(self, reader, path):
        return self.gives(reader, path) is not None

    def gives(self, reader, path):
        entry = reader.stat(path)
        if entry is None or entry.kind != "file":
            return None
        lines = reader.read(path).decode("utf-8", "replace").split("\n")
        if len(lines) != 3 or lines[0] != "tour-pointer" or lines[2] != "":
            return None
        digest, _, size = lines[1].partition(" ")
        return (digest, int(size)) if size.isdigit() else None


ENVIRONMENT = ExamplesPython()
STANDIN = TourPointer()
EOF

version=$(python3 -c 'import platform; print(".".join(platform.python_version_tuple()[:2]))')
if [ "$version" != 3.14 ]; then
  echo "setup/06.sh: python3 is $version, not 3.14: run.py's records name it, so every commit" \
       "id from \"Build the points\" on differs from the chapter's, and so do the cpython-3.14" \
       "lines. For the chapter's ids, run ./bootstrap.sh, which builds astra-tools'" \
       "environment on Python 3.14; then source env.sh again and rerun sh setup/06.sh" >&2
fi
