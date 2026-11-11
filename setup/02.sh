#!/bin/sh
# Chapter 2, "How a file is judged": (re)creates $TOUR/work/02 from nothing.
#
# - work/02/build/noisy-line and work/02/build/line-fit: the tour's examples, built by build.py
#   with their eight-step history and fixed commit ids;
# - work/02/two-names: a three-file analysis whose one result has two names (astra-spec's
#   conformance case 056), in a repository of its own, committed with a fixed identity and date;
# - work/02/judge.py: runs the parse and schema layers on one file, as astra-tools does inside.
#
# The chapter breaks these files one layer at a time, and puts them back with git after each
# step. This script removes work/02 first, and nothing else. It warns when python3 isn't 3.14:
# run.py's records name it by its version, so the commit ids from the first record on would
# differ from the chapter's.
set -eu

: "${TOUR:?source env.sh first, from the tour's folder}"
command -v astra >/dev/null || { echo "setup/02.sh: no astra on PATH: source env.sh" >&2; exit 2; }

rm -rf "$TOUR/work/02"
mkdir -p "$TOUR/work/02"
cp -R "$TOUR/examples/." "$TOUR/work/02/"
rm -rf "$TOUR/work/02/build"
find "$TOUR/work/02" -name __pycache__ -type d -prune -exec rm -rf {} +
cd "$TOUR/work/02"

python build.py

cat > judge.py <<'EOF'
"""Judge one file by the parse and schema layers alone, as astra-tools does inside it.

    python judge.py FILE        an astra.yaml, or a record (a file whose name ends in .json)

It reads the file as src/astra/load.py does, runs the JSON Schema that src/astra/contract.py
picks for it, and prints each error jsonschema gives: where it fails, its absolute keyword
location (the key into rules.json's `errors`), and the code found there. Then it prints
what astra-tools reports for the file, from `Contract.check_analysis` or `check_record`.
"""

import sys
from pathlib import Path

from astra.contract import SUPPORTED, Contract, _version  # _version: contract.py's own helper
from astra.diagnostics import Catalogue, json_pointer
from astra.load import ParseError, load_json, load_yaml

path = Path(sys.argv[1])
record = path.suffix == ".json"
catalogue = Catalogue.load()
contract = Contract.load(catalogue)

try:
    document = load_json(path.read_bytes()) if record else load_yaml(path.read_bytes())
except ParseError as error:
    sys.exit(f"parse    {error.code} at {error.line}:{error.column}: {error.message}")
print("parse    ok: a JSON value")

# The schema the stated version picks, as contract.py picks it (None: missing or malformed).
version = _version(document.value)
if record:
    name = "provenance.open" if version and version[:2] > SUPPORTED else "provenance"
    runs = not (version and version[:2] < SUPPORTED)
else:
    name, runs = "analysis", not (version and version[:2] != SUPPORTED)

if not runs:
    print(f"keyword  none: no schema is run for spec_version {document.value['spec_version']}")
else:
    schema = contract.schemas[name]
    for error in schema.validator.iter_errors(document.value):
        at = schema.pointers[id(error.schema)]
        keyword = f"{schema.uri}#{at}{json_pointer([str(error.validator)])}"
        where = json_pointer(error.absolute_path) or '""'
        print(f"keyword  {where}  {keyword}  {catalogue.errors[keyword]}")

check = contract.check_record if record else contract.check_analysis
for diagnostic in check(document, str(path)):
    at = diagnostic.location
    where = at.pointer or '""'
    place = "" if at.line is None else f" {at.line}:{at.column}"
    key = "" if at.key is None else f" key {at.key}"
    print(f"report   {diagnostic.code} at {where}{place}{key}: {diagnostic.message}")
EOF

# The two-names analysis, committed in a repository of its own, with a fixed identity and date
# and none of the user's git configuration, so that its commit id is the chapter's.
mkdir -p two-names/stage/inner
cat > two-names/astra.yaml <<'EOF'
spec_version: "0.1.0"
analyses:
  stage:
    path: stage
  inner:
    path: stage/inner
outputs:
  result:
    type: metric
    format: json
    inputs: [inner.output1]
    recipe:
      command: python make.py '{inputs.inner.output1}' '{output}'
universes:
  u1:
    decisions: {stage.inner.decision1: a}
  u2:
    decisions: {inner.decision1: b}
EOF
cat > two-names/stage/astra.yaml <<'EOF'
spec_version: "0.1.0"
analyses:
  inner:
    path: inner
outputs:
  result:
    type: metric
    format: json
    recipe:
      command: python make.py '{output}'
EOF
cat > two-names/stage/inner/astra.yaml <<'EOF'
spec_version: "0.1.0"
decisions:
  decision1:
    options:
      a: {}
      b: {}
outputs:
  output1:
    type: metric
    format: json
    decisions: [decision1]
    recipe:
      command: python make.py '{decisions.decision1}' '{output}'
EOF
(
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=Tour GIT_AUTHOR_EMAIL=tour@astra.invalid
  export GIT_COMMITTER_NAME=Tour GIT_COMMITTER_EMAIL=tour@astra.invalid
  export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
  cd two-names
  git init --quiet --initial-branch main
  git add --all
  git commit --quiet --message "One result, reached through two chains of declarations"
  echo "two-names $(git rev-parse --short=12 HEAD) $(git log -1 --format=%s)"
)

version=$(python3 -c 'import platform; print(".".join(platform.python_version_tuple()[:2]))')
if [ "$version" != 3.14 ]; then
  echo "setup/02.sh: python3 is $version, not 3.14: run.py's records name it, so the commit ids" \
       "from the first record on differ from the chapter's (codes, messages and places don't)" >&2
fi
