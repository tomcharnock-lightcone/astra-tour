#!/bin/sh
# Chapter 4, "Building, records and check": (re)creates $TOUR/work/04 from nothing.
#
# - work/04/words: a small analysis in a git repository of its own, one commit, nothing built:
#   an input (a poem), a decision with two options (count words or characters), a universe for
#   each, an output built per universe, one built once that reads both, and a finding.
# - work/04/record.py: writes the records of a result whose recipe was run by hand, through
#   astra-tools' runner helpers (astra.records), which aren't in its stable astra.api.
# - work/04/kept.py: prints what astra-tools' hash cache keeps for a file.
# - work/04/shell.sh: to source in your shell before the chapter's commands: a fixed author,
#   committer and date, and none of your git configuration, so that your commit ids are the
#   chapter's; and jq through nix where there is none on PATH.
#
# It removes work/04 first, and nothing else.
set -eu

: "${TOUR:?source env.sh first, from the tour's folder}"
command -v astra >/dev/null || { echo "setup/04.sh: no astra on PATH: source env.sh" >&2; exit 2; }

W="$TOUR/work/04"
rm -rf "$W"
mkdir -p "$W/words/src" "$W/words/data"

cat > "$W/words/astra.yaml" <<'EOF'
spec_version: "0.1.0"

inputs:
  text:
    label: The poem
    path: data/poem.txt

decisions:
  unit:
    label: What to count
    options:
      words:
        label: Words of at least MIN_LENGTH characters, from src/count.py
      chars:
        label: Characters other than white space

outputs:
  count:
    label: Count
    type: metric
    format: json
    inputs: [text]
    decisions: [unit]
    recipe:
      command: python3 src/count.py {decisions.unit} {inputs.text} {output}
  summary:
    label: Characters per word
    type: table
    format: json
    inputs: [count#words, count#chars]
    recipe:
      command: python3 src/summary.py {inputs} {output}

universes:
  words:
    decisions: {unit: words}
  chars:
    decisions: {unit: chars}

findings:
  short_words:
    label: Short words
    claim: The poem's words are short, under five characters on average.
    evidence:
      - artifact: summary
EOF

cat > "$W/words/data/poem.txt" <<'EOF'
I keep a record of each run,
the commit, the inputs, and the hash;
a line is changed — the count is stale,
until the runner builds again.
EOF

cat > "$W/words/src/count.py" <<'EOF'
"""Count a text's words or characters: python3 count.py UNIT TEXT OUTPUT.

UNIT is `words`, the words of at least MIN_LENGTH characters, or `chars`, the characters other
than white space. OUTPUT gets {"count": N, "unit": UNIT}, as JSON.
"""

import json
import sys

MIN_LENGTH = 1


def main(unit: str, text_path: str, output_path: str) -> None:
    with open(text_path, encoding="utf-8") as stream:
        text = stream.read()
    if unit == "words":
        count = sum(len(word) >= MIN_LENGTH for word in text.split())
    else:
        count = sum(not char.isspace() for char in text)
    with open(output_path, "w", encoding="utf-8") as stream:
        json.dump({"count": count, "unit": unit}, stream, sort_keys=True)
        stream.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
EOF

cat > "$W/words/src/summary.py" <<'EOF'
"""Characters per word, from the two counts: python3 summary.py WORDS CHARS OUTPUT."""

import json
import sys


def main(words_path: str, chars_path: str, output_path: str) -> None:
    counts = {}
    for path in (words_path, chars_path):
        with open(path, encoding="utf-8") as stream:
            found = json.load(stream)
        counts[found["unit"]] = found["count"]
    counts["chars_per_word"] = round(counts["chars"] / counts["words"], 3)
    with open(output_path, "w", encoding="utf-8") as stream:
        json.dump(counts, stream, sort_keys=True)
        stream.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
EOF

cat > "$W/record.py" <<'EOF'
"""Write the records of a result whose recipe you ran by hand: python ../record.py ADDRESS.

Run it in the analysis's folder, right after running the recipe there from a checkout of HEAD
with no change, giving the address of one of the planned results, as `astra plan` lists them.
It writes the result's record at each of its places, naming HEAD as the commit the recipe ran
from: true only if you ran it from HEAD with no change (FALSE_RECORD, §21).
"""

import sys
from pathlib import Path

from astra import api
from astra.records import Runner, new_record, uncommitted_changes, write_record
from astra.sources.git import Repository

address = sys.argv[1]
repo = Repository.discover(Path.cwd())
(result,) = [r for r in api.plan().results if address in [p.address for p in r.places]]
print("changes before:", uncommitted_changes(repo.top))
records = new_record(
    result,
    checkout=repo.top,  # every path of the plan is from the checkout's top
    commit=repo.head(),  # the commit the recipe ran from
    environment="urn:tour:by-hand",
    runner=Runner("tour/record.py", "1"),
)
for place, record in zip(result.places, records, strict=True):
    write_record(repo.top / place.record, record)
    print("wrote", place.record)
print("changes after: ", uncommitted_changes(repo.top))
EOF

cat > "$W/kept.py" <<'EOF'
"""What astra-tools' hash cache keeps for a file: python ../kept.py PATH.

It looks the file up as src/astra/hashing.py does: by its device and inode, a hit only where
the size and modification time kept are the file's. It prints the hash kept and its size, or
says there is no entry for the file as it is now.
"""

import json
import os
import sys

from astra import cache, hashing

stat = os.stat(sys.argv[1])
kept = cache.get(hashing.NAMESPACE, f"{stat.st_dev}:{stat.st_ino}")
entry = None if kept is None else json.loads(kept)
if entry is None or (entry["size"], entry["mtime_ns"]) != (stat.st_size, stat.st_mtime_ns):
    print("no entry for the file as it is now: a check hashes it")
else:
    print(entry["content_hash"], entry["size"], "kept: a check takes it, and doesn't read the file")
EOF

cat > "$W/shell.sh" <<'EOF'
# Chapter 4: source this in your shell before the chapter's commands. Your commits then have a
# fixed author, committer and date, and none of your git configuration (signing, hooks), so
# their ids are the chapter's. It lasts as long as the shell: open a new one afterwards.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Tour GIT_AUTHOR_EMAIL=tour@astra.invalid
export GIT_COMMITTER_NAME=Tour GIT_COMMITTER_EMAIL=tour@astra.invalid
export GIT_AUTHOR_DATE=2026-01-01T12:00:00Z GIT_COMMITTER_DATE=2026-01-01T12:00:00Z
command -v jq >/dev/null || jq() { nix shell 'nixpkgs#jq' --command jq "$@"; }
EOF

cd "$W/words"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Tour GIT_AUTHOR_EMAIL=tour@astra.invalid
export GIT_COMMITTER_NAME=Tour GIT_COMMITTER_EMAIL=tour@astra.invalid
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
git init --quiet --initial-branch main
git add --all
git commit --quiet --message "Count the words and the characters of a poem"
echo "work/04/words: $(git log --oneline)"

version=$(python3 -c 'import platform; print(".".join(platform.python_version_tuple()[:2]))')
if [ "$version" != 3.14 ]; then
  echo "setup/04.sh: python3 is $version, not 3.14: run.py's records name it, so the ids of" \
       "the commits that hold them (step 5 on) differ from the chapter's. For the chapter's" \
       "ids, run ./bootstrap.sh inside nix develop, which builds astra-tools' environment on" \
       "3.14; then source env.sh again and rerun sh setup/04.sh" >&2
fi
