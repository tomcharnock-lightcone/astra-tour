#!/bin/sh
# Chapter 3: decisions, universes, plan and view.
#
# (Re)creates $TOUR/work/03/readings from nothing: one analysis, `readings`, in a git repository
# of its own, with one commit. Removes $TOUR/work/03 first, and nothing else.
set -eu

TOUR="${TOUR:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="$TOUR/work/03"
rm -rf "$WORK"
mkdir -p "$WORK/readings/data" "$WORK/readings/src"
cd "$WORK/readings"

cat > astra.yaml <<'EOF'
spec_version: "0.1.0"

inputs:
  readings:
    label: Sensor readings
    description: One reading per line; a loose connector adds a few spikes.
    path: data/readings.csv

decisions:
  spikes:
    label: Spikes
    rationale: The spikes are faults, not signal. Dropping them is the obvious fix, but a robust estimator copes without it.
    options:
      keep: {}
      drop:
        description: Drop every reading more than five median absolute deviations from the median.
  centre:
    label: Central value
    rationale: The mean follows the spikes; the median and a trimmed mean don't.
    options:
      mean:
        requires: [spikes.drop]
      median: {}
      trimmed: {}
      mode:
        excluded: The readings are continuous, so a mode would need them binned first.
  cut:
    label: How much the trimmed mean cuts from each end
    when: [centre.trimmed]
    options:
      p10: {}
      p25: {}

outputs:
  clean:
    label: Readings, with or without their spikes
    type: data
    format: csv
    inputs: [readings]
    decisions: [spikes]
    recipe:
      command: python3 src/clean.py --spikes={decisions.spikes} {inputs.readings} {output}
  summary:
    label: Central value
    type: metric
    format: json
    inputs: [clean]
    decisions: [centre, cut]
    recipe:
      command: python3 src/summarise.py --centre={decisions.centre} --cut={decisions.cut} {inputs.clean} {output}
  comparison:
    label: The three central values side by side
    type: table
    format: csv
    inputs: [summary#mean, summary#trimmed, summary#median]
    recipe:
      command: python3 src/compare.py --format='{{:.2f}}' {inputs} {output}

universes:
  mean:
    label: Mean, spikes dropped
    decisions: {spikes: drop, centre: mean}
  trimmed:
    label: Trimmed mean, spikes kept
    decisions: {spikes: keep, centre: trimmed, cut: p10}
  median:
    label: Median, spikes kept
    derived_from: trimmed
    decisions: {centre: median}
EOF

cat > data/readings.csv <<'EOF'
reading
20.1
19.8
20.4
19.9
20.0
20.3
19.7
35.2
20.2
19.6
20.5
20.1
41.0
19.9
20.2
20.0
19.8
38.6
20.3
20.1
EOF

cat > src/clean.py <<'EOF'
"""Keep or drop the spikes: clean.py --spikes=keep|drop READINGS OUT"""

import argparse
import statistics

parser = argparse.ArgumentParser()
parser.add_argument("--spikes", choices=["keep", "drop"], required=True)
parser.add_argument("readings")
parser.add_argument("out")
args = parser.parse_args()

with open(args.readings) as file:
    values = [float(line) for line in file.read().split()[1:]]
if args.spikes == "drop":
    median = statistics.median(values)
    mad = statistics.median(abs(value - median) for value in values)
    values = [value for value in values if abs(value - median) <= 5 * mad]
with open(args.out, "w") as file:
    file.write("reading\n" + "".join(f"{value}\n" for value in values))
EOF

cat > src/summarise.py <<'EOF'
"""The central value: summarise.py --centre=mean|median|trimmed --cut=[p10|p25] CLEAN OUT"""

import argparse
import json
import statistics

parser = argparse.ArgumentParser()
parser.add_argument("--centre", choices=["mean", "median", "trimmed"], required=True)
parser.add_argument("--cut", choices=["", "p10", "p25"], default="")
parser.add_argument("clean")
parser.add_argument("out")
args = parser.parse_args()

with open(args.clean) as file:
    values = sorted(float(line) for line in file.read().split()[1:])
if args.centre == "mean":
    value = statistics.fmean(values)
elif args.centre == "median":
    value = statistics.median(values)
else:
    k = len(values) * {"p10": 10, "p25": 25}[args.cut] // 100
    value = statistics.fmean(values[k : len(values) - k])
summary = {"centre": args.centre, "cut": args.cut or None, "n": len(values), "value": value}
with open(args.out, "w") as file:
    file.write(json.dumps(summary) + "\n")
EOF

cat > src/compare.py <<'EOF'
"""The central values side by side: compare.py --format=SPEC SUMMARY... OUT"""

import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("--format", required=True)
parser.add_argument("summaries", nargs="+")
parser.add_argument("out")
args = parser.parse_args()

rows = ["centre,cut,value"]
for path in args.summaries:
    with open(path) as file:
        summary = json.load(file)
    rows.append(f"{summary['centre']},{summary['cut'] or ''},{args.format.format(summary['value'])}")
with open(args.out, "w") as file:
    file.write("\n".join(rows) + "\n")
EOF

# A fixed identity and date, and none of the user's git config, so the commit id is the same
# every time.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Tour" GIT_AUTHOR_EMAIL="tour@astra.invalid"
export GIT_COMMITTER_NAME="Tour" GIT_COMMITTER_EMAIL="tour@astra.invalid"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
git init --quiet --initial-branch=main
git add --all
git commit --quiet --message "Estimate the readings' central value three ways"

echo "work/03/readings: $(git log --oneline)"
