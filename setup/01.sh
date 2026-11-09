#!/bin/sh
# Chapter 1's starting state, made from nothing: $TOUR/work/01/ with
#
#   upstream/   a git repository holding a tiny analysis, in two commits with fixed ids:
#               the first misnames a field (`recipie`), the second fixes it. Step 8 declares
#               it by a file:// URL, so that astra-tools fetches it into the cache.
#   loaded.py   runs one astra command in-process and lists the modules it imported (step 5).
#
# The analysis of steps 1 to 4, first/, is made by `astra init` in step 1, not here.
# Run it from anywhere after `source env.sh`. It removes $TOUR/work/01 first, and nothing else.
set -eu

: "${TOUR:?run 'source env.sh' from the tour folder first}"
W="$TOUR/work/01"
rm -rf "$W"
mkdir -p "$W/upstream/src"

# Fixed commit ids: a fixed identity and fixed dates, and none of the user's git configuration.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Tour GIT_AUTHOR_EMAIL=tour@astra.invalid
export GIT_COMMITTER_NAME=Tour GIT_COMMITTER_EMAIL=tour@astra.invalid

commit() { # commit <date> <message>: everything in upstream/, at that date
  git -C "$W/upstream" add --all
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$W/upstream" commit --quiet -m "$2"
}

git init --quiet --initial-branch=main "$W/upstream"

cat > "$W/upstream/words.txt" <<'EOF'
alpha beta gamma
delta epsilon
EOF

cat > "$W/upstream/src/count.py" <<'EOF'
import json, sys

words, output = sys.argv[1], sys.argv[2]
with open(words, encoding="utf-8") as stream:
    count = len(stream.read().split())
with open(output, "w", encoding="utf-8") as stream:
    json.dump({"words": count}, stream)
EOF

cat > "$W/upstream/astra.yaml" <<'EOF'
spec_version: "0.1.0"
inputs:
  words:
    path: words.txt
outputs:
  count:
    type: metric
    format: json
    inputs: [words]
    recipie:
      command: python3 src/count.py {inputs.words} {output}
EOF
commit 2026-01-01T00:00:00Z "Count the words"

sed 's/recipie:/recipe:/' "$W/upstream/astra.yaml" > "$W/upstream/astra.yaml.new"
mv "$W/upstream/astra.yaml.new" "$W/upstream/astra.yaml"
commit 2026-01-01T01:00:00Z "Spell recipe right"

cat > "$W/loaded.py" <<'EOF'
"""python loaded.py ARGS...: run `astra ARGS...` in this process, its output thrown away, then
list what it imported: astra-tools' modules, and the libraries astra-tools depends on."""

import contextlib
import io
import sys

from astra.cli import main

LIBRARIES = {"click", "jsonschema", "rich", "ruamel", "linkml_runtime", "pypdf", "rapidfuzz"}

with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
    try:
        main(sys.argv[1:], prog_name="astra")
    except SystemExit as stop:
        code = stop.code
own = sorted(name.removeprefix("astra.") for name in sys.modules if name.startswith("astra."))
libraries = sorted({name.split(".")[0] for name in sys.modules} & LIBRARIES)
print("exit code:", code)
print(f"astra ({len(own)}):", " ".join(own))
print("libraries:", " ".join(libraries))
EOF

echo "work/01 is ready: $W"
git --no-pager -C "$W/upstream" log --format='  upstream %h %s'
