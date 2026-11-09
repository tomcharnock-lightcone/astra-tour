# 3. Decisions, universes, plan and view

One analysis with three decisions, three universes and three outputs, and what astra-tools makes
of it: each universe's effective selection, the planned results with their names, places and
commands, the plan's notes, and the stack as one universe sees it. Nothing is built here: the
chapter stops where a runner starts.

## Setup

```console
$ source env.sh
astra: …/astra-tools/.venv/bin/astra (astra, version 0.2.19.dev…)
work:  …/tour/work
$ sh setup/03.sh
work/03/readings: c33540d Estimate the readings' central value three ways
$ cd work/03/readings
```

- `setup/03.sh` removes `work/03` and makes `work/03/readings` again: a git repository with one
  commit (fixed author and date, so the id is `c33540d` for you too) holding the analysis, its
  input and three small scripts. Run it again, from the tour's folder, whenever you want the
  starting state back.
- Steps 7 and 8 and some answers use `jq`. If it isn't on your PATH, start with
  `nix shell 'nixpkgs#jq'`, then `source env.sh` in that shell.
- Every step runs in `work/03/readings`. The steps and exercises that edit `astra.yaml` end
  with `git checkout --quiet astra.yaml`.

## 1. The analysis

Everything below is a function of this one file and git.

```console
$ cat astra.yaml
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
$ git ls-files
astra.yaml
data/readings.csv
src/clean.py
src/compare.py
src/summarise.py
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
```

What to notice:

- Three decisions ([§8](https://astra-spec.org/0.1/specification/#8-decisions-and-options)):
  `spikes`; `centre`, whose `mean` `requires` `spikes.drop` and whose `mode` is `excluded`; and
  `cut`, conditional on `centre.trimmed` ([§9](https://astra-spec.org/0.1/specification/#9-conditions)).
- `clean` and `summary` list `decisions`, so each is built per universe. `summary` would be
  anyway, since it reads `clean` without a pin. `comparison` lists none and reads `summary` only
  pinned, so it is built once, like line-fit's `comparison`
  ([§13](https://astra-spec.org/0.1/specification/#13-pins-and-outputs-built-per-universe-or-once)).
- The universes are inline in the file, none of them an import. `median` derives from
  `trimmed` and writes one key.
- The commands use every placeholder form: `{inputs.<entry>}`, `{decisions.<entry>}`,
  `{inputs}`, `{output}`, and `{{ }}` for literal braces
  ([§11](https://astra-spec.org/0.1/specification/#11-recipes)). `--cut={decisions.cut}` has its
  `=` on purpose; step 4 shows why.

Under the hood:

- How `astra validate` works is chapter 2's subject. The rules the exercises break are in
  `src/astra/rules/universes.py:103` (`_selected`: `excluded` at :115, `requires` at :119,
  `incompatible_with` at :124, `INACTIVE_DECISION` at :129) and
  `src/astra/rules/recipes.py:34` (`_problems`, `UNDECLARED_TEMPLATE_REF`).
- The selection rules of §12 (`MISSING_REQUIRED_OPTION`, `INCOMPATIBLE_OPTIONS`,
  `EXCLUDED_OPTION_SELECTED`, `INACTIVE_DECISION`) judge effective selections, not universes as
  written: `src/astra/rules/universes.py:46` loops over `context.selections`, which is step 2's
  function. The other two, `UNKNOWN_DERIVED_FROM` and `DERIVED_FROM_CYCLE`, judge `derived_from`
  as written (:40-44).
  `UNDECLARED_TEMPLATE_REF` reads only the command and its output's own `inputs` and `decisions`.

## 2. The universes and their effective selections

A universe's selection is what a reader of the file has to work out by hand once `derived_from`
is used ([§12](https://astra-spec.org/0.1/specification/#12-universes), *The effective
selection*). `astra universe` shows it.

```console
$ astra universe list
mean  Mean, spikes dropped
trimmed  Trimmed mean, spikes kept
median  derived from trimmed  Median, spikes kept
$ astra universe show mean
mean
  spikes: drop
  centre: mean
$ astra universe show trimmed
trimmed
  spikes: keep
  centre: trimmed
  cut: p10
$ astra universe show median
median  derived from trimmed
  spikes: keep  (from trimmed)
  centre: median
$ astra universe show nope
Usage: astra universe show [OPTIONS] UNIVERSE [PATH]
Try 'astra universe show --help' for help.

Error: Invalid value for UNIVERSE: the analysis has no universe `nope`: its universes are mean, trimmed, median
$ echo $?
2
```

What to notice:

- `list` is the file's order, with `derived from` and the label. An import would show
  `imports <analysis>.<universe>`.
- `show median` gives the inherited keys first, then its own. `(from trimmed)` names the
  universe whose own `decisions` wrote the key. In a longer chain it is still the writer, not
  the parent (Try 1).
- `cut: p10`, which `trimmed` selects, is gone from `median`: `centre: median` switches `cut` off,
  and step 3 of the effective selection drops the inherited key. Nothing in the output says a
  key was dropped; step 3 below shows it.
- `astra universe` prints text only; there is no `--json` (design §4.12). It doesn't validate:
  it needs only a root file that is a valid document in a repository, so it shows a selection
  even when the analysis breaks a `MUST` (Try 1 and 2). It exits 1 where the universe has no
  effective selection (a `derived_from` that names nothing or loops, design §4.13 case 7), and
  2 for an id that isn't a universe of the root.

Under the hood:

- `src/astra/cli/universe.py:47` resolves the id with `plan.root_universe`
  (`src/astra/plan.py:233`), which refuses an unknown id or an import; click turns that into a
  usage error, exit 2 (`src/astra/cli/universe.py:49`).
- `src/astra/cli/universe.py:50` computes `universes.selections(stack, universes.written(stack))`:
  the selection of every universe of every analysis in the stack, not only the one asked for.
- `src/astra/universes.py:119` `effective_selection` is recursive and memoised in `found`;
  `deriving` (:141) is the loop guard. Step 1 is :136: no `derived_from`, the own keys.
- `src/astra/universes.py:149` `_derive` holds steps 2 and 3. Step 2 (:159) drops each
  inherited key that an own key replaces, by `_one_key` (:168): the same key, or two spellings
  of one decision. Step 3 (:160-163) computes activity on what is left plus the own keys, and
  drops an inherited key whose decision is inactive (`False`; an undetermined `None` is kept,
  design §4.13 case 6).
- Step 3 runs once, not until nothing changes: `# OPEN(O2)` at :160 (design §5). It matters only
  when dropping one key switches off another decision whose key was inherited too.
- The `(from …)` suffix is `entry.owner.id`, at `src/astra/cli/text/universe.py:40`.

## 3. The effective selection from the inside

The same computation through the Python API, with what the CLI doesn't print: what each
universe inherited, and what is active in it.

```console
$ python - <<'EOF'
from astra import api, universes

stack = api.bind().stack
found = universes.selections(stack, universes.written(stack))
for universe, selection in found.items():
    print(universe.id)
    print("  inherited", [f"{e.key}: {e.option}" for e in selection.inherited])
    print("  entries  ", [f"{e.key}: {e.option} ({e.owner.id})" for e in selection.entries])
    print("  active   ", [e.id for e, active in selection.activity.items() if active])
EOF
mean
  inherited []
  entries   ['spikes: drop (mean)', 'centre: mean (mean)']
  active    ['spikes', 'centre', 'clean', 'summary', 'comparison']
trimmed
  inherited []
  entries   ['spikes: keep (trimmed)', 'centre: trimmed (trimmed)', 'cut: p10 (trimmed)']
  active    ['spikes', 'centre', 'cut', 'clean', 'summary', 'comparison']
median
  inherited ['spikes: keep', 'centre: trimmed', 'cut: p10']
  entries   ['spikes: keep (trimmed)', 'centre: median (median)']
  active    ['spikes', 'centre', 'clean', 'summary', 'comparison']
```

What to notice:

- `median.inherited` is `trimmed`'s whole effective selection, `cut: p10` included; its
  `entries` lack `cut`, and `cut` isn't active in it. That is step 3.
- Each entry is a `Resolution`: the key as written, the option, and `owner`, the universe whose
  own `decisions` hold it. It is the same object the rules report from, which is why a rule
  broken through inheritance can name the universe that wrote the key (Try 2).
- `activity` covers outputs as well as decisions: an output's `when` is judged on the same
  selection. Here every output is active everywhere, since none has a `when`.
- `api.bind()` reads and binds without running the validator rules, as `astra universe` does.

Under the hood:

- `Selection` is `src/astra/universes.py:41`: `entries`, `inherited`, `activity`, and
  `own()`, `options()`, `active()`.
- `_activity` (`src/astra/universes.py:193`) judges each `when` with `holds` (:216). A
  condition on a decision with nothing selected is undetermined (`None`) unless that decision is
  itself inactive, in which case `d.o` is false and `~d.o` true: `# OPEN(O16)` at :222 (Try 4).
- `None` and `False` part ways later: `_derive` drops only `False`, and the plan plans a result
  only where its output's activity is `True` (`src/astra/universes.py:583`).

## 4. The plan, as text

The planned results ([§18](https://astra-spec.org/0.1/specification/#18-results-and-where-they-go)),
each with its places and the command that makes it.

```console
$ astra plan
clean#mean
  record    .astra/records/mean/clean.json
  bytes     results/mean/clean.csv
  run in    .
  command   python3 src/clean.py --spikes=drop data/readings.csv results/mean/clean.csv
clean#trimmed
  record    .astra/records/trimmed/clean.json
  bytes     results/trimmed/clean.csv
  run in    .
  command   python3 src/clean.py --spikes=keep data/readings.csv results/trimmed/clean.csv
clean#median
  record    .astra/records/median/clean.json
  bytes     results/median/clean.csv
  run in    .
  command   python3 src/clean.py --spikes=keep data/readings.csv results/median/clean.csv
summary#mean
  record    .astra/records/mean/summary.json
  bytes     results/mean/summary.json
  run in    .
  command   python3 src/summarise.py --centre=mean --cut= results/mean/clean.csv results/mean/summary.json
summary#trimmed
  record    .astra/records/trimmed/summary.json
  bytes     results/trimmed/summary.json
  run in    .
  command   python3 src/summarise.py --centre=trimmed --cut=p10 results/trimmed/clean.csv results/trimmed/summary.json
summary#median
  record    .astra/records/median/summary.json
  bytes     results/median/summary.json
  run in    .
  command   python3 src/summarise.py --centre=median --cut= results/median/clean.csv results/median/summary.json
comparison
  record    .astra/records/comparison.json
  bytes     results/comparison.csv
  run in    .
  command   python3 src/compare.py --format='{:.2f}' results/mean/summary.json results/trimmed/summary.json results/median/summary.json results/comparison.csv
7 planned result(s), and notes, none of them a breach (--notes lists them):
  1 computation(s) repeated across universes, in 2 result(s)
```

What to notice:

- Seven results: two outputs built per universe in three universes, and `comparison` once. Each
  heading is a result's address: its name, then `#` and the universe for a result built in one.
- Places (§18 *Where records and bytes go*): the record at `.astra/records/{universe}/{name}.json`
  and the bytes at their default place, `results/{universe}/{name}.{format}`; for `comparison`,
  built once, neither has a `{universe}`. Paths are from the top of the repository, which is
  the analysis's folder here.
- `run in .` is the analysis's folder (§11). A result of an analysis from a commit has
  `read through its record at <commit>` instead, and no command (chapter 5's step 4 shows one).
- Each result comes after what it reads. Here that is also the file's order: outputs in order,
  each across the universes in order. Step 6 shows an order where it isn't.
- `--cut=` in `mean` and `median`: `cut` is inactive there, and astra-tools renders
  `{decisions.cut}` as the empty string, its reading of an open question (`OPEN(O30)`, design
  §5). Written `--cut {decisions.cut}`, the shell would get `--cut results/mean/clean.csv …`
  and the script would read the path as the value of `--cut`.
- In `comparison`, `{inputs}` is the three pinned paths in the order of `inputs`, and
  `'{{:.2f}}'` became `'{:.2f}'`. Nothing is quoted for the shell: §11 says verbatim.
- The exit code is 0. With a `MUST` broken, `astra plan` prints the validation report instead and
  exits 1 (Try 1 to 3): there is no plan of an invalid analysis. The exit codes are astra-tools'
  own (design §4.12; chapter 1, step 3). For `universe show` and `view`, an unknown universe is
  a usage error, exit 2.

Under the hood:

- `src/astra/cli/plan.py:39` calls `api.plan`, which validates first: `src/astra/api.py:180`
  raises `InvalidAnalysisError`, and `src/astra/cli/plan.py:40-42` prints its report and exits 1.
- `src/astra/plan.py:162` `plan()` builds a rules `Context` (:179) and asks
  `universes.building` for the planned results (:183).
- Per universe or once is `src/astra/universes.py:388` `per_universe`: outputs that list
  `decisions` or have a `when` (:397), then, until nothing grows, outputs with an unpinned entry
  naming one of those (:399-407). Every entry of `comparison` has a pin, so it stays out.
- `src/astra/universes.py:536` `building`: the root's universes are built (:607-608); each root
  output gets one result, or one per universe (:612-614); then whatever a planned result reads
  is planned in its turn (:620-624). The inner `plan` returns early where the output isn't active
  in the universe (:583).
- `read_in` (`src/astra/universes.py:501`) gives the universe an entry reads in: the result's
  own for an unpinned entry, the pin's for a pinned one (:514), none for an output built once
  (:512-513).
- `places` (`src/astra/universes.py:484`) writes the address (:493), the record (:494) and the
  bytes (:495).
- `src/astra/plan.py:205` `visit` puts each result after the results it reads; `_reads` (:258)
  and `_result` (:293) fill in what each entry reads and the rest of the result.
- The text renders each command at `src/astra/cli/text/plan.py:41`:
  `render_command(result, folder)`, with `folder` the result's `workdir`, or `.`.

## 5. The notes

The plan points out what an author may want to tidy. None of it is a breach.

```console
$ astra plan --notes | sed -n '/^note/,$p'
note `clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
7 planned result(s), and notes, none of them a breach:
  1 computation(s) repeated across universes, in 2 result(s)
```

A command that runs code from outside the analysis's folder gets a note of another kind:

```console
$ perl -pi -e 's{python3 src/clean.py}{python3 ../tools/clean.py}' astra.yaml
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra plan --notes | sed -n '/^note/,$p'
note `clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
note astra.yaml:42:16 the command names `../tools/clean.py`, outside its analysis's folder: a recipe should run only code tracked in its analysis's folder, outside every folder below it that holds an analysis of its own, or that its output's inputs give it (`CODE_OUTSIDE_ANALYSIS`, §21)
7 planned result(s), and notes, none of them a breach:
  1 computation(s) repeated across universes, in 2 result(s)
  1 command(s) name a path outside their analysis (CODE_OUTSIDE_ANALYSIS)
$ git checkout --quiet astra.yaml
```

What to notice:

- Notes are astra-tools' own (design §4.6), not the spec's: none has a code, none changes an exit
  code, and `astra validate` shows none of them (a result with two names also breaks the
  `SHOULD` `RESULT_IN_TWO_PLACES`, which `validate` reports in its own right). The kinds are
  `fallback_pin`, `two_names`, `unplanned`, `same_computation` and `outside_folder`. This chapter
  meets three (`unplanned` in Try 4); the other two need declared analyses.
- `clean#trimmed` and `clean#median` have the same command, read the same file and select the
  same option of the one decision `clean` lists, `spikes: keep`. The universes differ only in
  `centre`, which `clean` doesn't list. A runner may build one and place the bytes at both.
- `summary#trimmed` and `summary#median` aren't one computation: `centre` and `cut` differ.
- `outside_folder` names `CODE_OUTSIDE_ANALYSIS`, a runner rule of
  [§21](https://astra-spec.org/0.1/specification/#21-runners) that no validator checks; the note
  is astra-tools reading the command as text. It has a location (42:16, the command's value); the
  notes about results (`same_computation`, `two_names`) have none.
- The text counts and lists only notes about what this root builds (`built`); the JSON lists all
  of them (step 7).

Under the hood:

- `src/astra/plan.py:330` `_notes` yields the kinds in a fixed order (:343-347).
- `_same_computations` (`src/astra/plan.py:419`): a computation is the output, what it reads and
  the options selected (:437). A read of another planned result counts as that result's
  computation (:431-436), so two `summary` results that read one `clean` computation and select
  the same options are one computation too (Try 1).
- `_outside_folder` (`src/astra/plan.py:456`): `_paths` (:509) takes each word of the command
  outside its placeholders, which it masks (:513), and skips absolute paths; `_climbs` (:521)
  counts `..` against the folders before them; `below` (:468) looks for an `astra.yaml` in each
  folder on the way to a path that stays inside.
- `src/astra/cli/text/plan.py:42` keeps the `built` notes; :43-50 list them under `--notes`;
  :58-70 count them by kind.

## 6. The plan from Python: filters and render_command

`astra plan` takes no filters, and the JSON holds commands unrendered. Both are the API's
(design §4.6).

```console
$ python - <<'EOF'
from astra import api
from astra.plan import render_command

comparison = api.plan().results[-1]
print(comparison.command)
print(render_command(comparison, "."))
print(render_command(comparison, "/srv/run", absolute=True))
print([r.places[0].address for r in api.plan(universes=["median"]).results])
print([r.places[0].address for r in api.plan(outputs=["comparison"]).results])
EOF
python3 src/compare.py --format='{{:.2f}}' {inputs} {output}
python3 src/compare.py --format='{:.2f}' results/mean/summary.json results/trimmed/summary.json results/median/summary.json results/comparison.csv
python3 src/compare.py --format='{:.2f}' /srv/run/results/mean/summary.json /srv/run/results/trimmed/summary.json /srv/run/results/median/summary.json /srv/run/results/comparison.csv
['clean#median', 'summary#median']
['clean#mean', 'summary#mean', 'clean#trimmed', 'summary#trimmed', 'clean#median', 'summary#median', 'comparison']
```

What to notice:

- `Result.command` is the template as written. Filling it is the consumer's job, through
  `render_command`; `astra plan` does it for its text.
- `cwd` is the folder the recipe runs in, inside the checkout it runs in. Paths come out relative
  to it, or absolute with `absolute=True`, as a runner working in a checkout of its own wants.
  `/srv/run` is only a name here: nothing is read there.
- `universes=["median"]` keeps the results built in `median` and what they read. `comparison`
  is built once, not in `median`, so it is left out.
- `outputs=["comparison"]` plans `comparison` and what it reads, and the order is depth-first
  from that one seed: each `clean` right before its `summary`. "Each after what it reads" is the
  only promise about order.

Under the hood:

- `src/astra/plan.py:558` `render_command`: `depth` and `top` (:579-580) find the checkout's top
  from `cwd` and the result's `workdir`, since every path in the plan is from that top; `path`
  (:583) makes each relative to `cwd` or absolute.
- `_TEMPLATE` (`src/astra/plan.py:553`) reads `{{`, `}}` and `{…}` from the left, as §11 says.
  `fill` (:594): a brace pair (:596-597), `{output}` as the first name's bytes (:598-599),
  `{inputs}` joined by spaces (:600-601), `{inputs.<entry>}` (:602-604), and
  `{decisions.<entry>}` as `result.decisions[entry] or ""` (:605, `OPEN(O30)`).
- `where` (:587-590): an entry read at a commit renders as `<commit>:<path>` unless `got=` gives
  where the runner put its bytes.
- The validator scans braces with a regex of its own, `src/astra/rules/recipes.py:30`, which
  also matches a stray `{` or `}`. `render_command` assumes a command that passed it.
- The filters: `src/astra/plan.py:188` `chosen`; with `universes` alone, a result is kept where
  `result.universe in wanted` (:190), which `None`, built once, never is.

## 7. The plan as JSON: astra-plan/1

This is what lightcone-cli and agents read. The shape is astra-tools' own, shared with
astra-typescript and pinned by astra-tools' tests until its JSON Schema exists (design §4.11).

```console
$ astra plan --json | jq -c 'keys'
["notes","results","root","shape"]
$ astra plan --json | jq '.results[3]'
{
  "names": [
    "summary"
  ],
  "owner": {
    "folder": "",
    "commit": null
  },
  "output": {
    "analysis": {
      "folder": "",
      "commit": null
    },
    "kind": "output",
    "id": "summary"
  },
  "universe": "mean",
  "places": [
    {
      "name": "summary",
      "address": "summary#mean",
      "record": ".astra/records/mean/summary.json",
      "bytes": "results/mean/summary.json"
    }
  ],
  "inputs": [
    {
      "entry": "clean",
      "path": "results/mean/clean.csv",
      "commit": null,
      "result": 0
    }
  ],
  "decisions": {
    "centre": "mean",
    "cut": null
  },
  "command": "python3 src/summarise.py --centre={decisions.centre} --cut={decisions.cut} {inputs.clean} {output}",
  "workdir": "",
  "read_only": false,
  "run_at": null,
  "resources": null,
  "container": null
}
$ astra plan --json | jq -c '.results[] | [.places[0].address, .universe, [.inputs[].result], .decisions]'
["clean#mean","mean",[null],{"spikes":"drop"}]
["clean#trimmed","trimmed",[null],{"spikes":"keep"}]
["clean#median","median",[null],{"spikes":"keep"}]
["summary#mean","mean",[0],{"centre":"mean","cut":null}]
["summary#trimmed","trimmed",[1],{"centre":"trimmed","cut":"p10"}]
["summary#median","median",[2],{"centre":"median","cut":null}]
["comparison",null,[3,4,5],{}]
$ astra plan --json | jq -c '.notes[]'
{"kind":"same_computation","message":"`clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each","location":null,"results":[1,2],"built":true}
```

What to notice:

- `owner` and `output.analysis` are identities: the folder from the top (`""` is the top) and
  the commit, `null` for the working tree. `universe` is a bare id, `null` for a result built
  once.
- `inputs` has one entry per entry of the output's `inputs`, as written: `path` from the top,
  `commit` where it is read at one, and `result`, the index of the planned result it reads, or
  `null` for an input's file. An index always points earlier: `comparison` reads 3, 4 and 5.
- `decisions` has `"cut": null` where the CLI rendered an empty string: the same `OPEN(O30)`
  reading in its JSON form.
- `command` is the template. A consumer renders it with `render_command`, or must implement §11
  itself.
- `read_only` and `run_at` matter only for analyses from a commit; `resources` and `container`
  only where a recipe or its analysis asks for them.
- A note gives its results by index, its location as a whole `Location` or `null`, and `built`.
- On an analysis that breaks a `MUST`, `astra plan --json` prints an
  `astra-validation-report/1` instead, and exits 1 (chapter 1's step 3, and Try 1 here). A
  consumer checks `shape`.

Under the hood:

- `src/astra/plan.py:113` `Plan.to_json`; the index of each result by its output and universe
  (:116), each read as `{entry, path, commit, result}` (:118-121), each note (:128-135).
- `Result.decisions` is `selected` (`src/astra/plan.py:538`, called at :320): each entry of the
  output's `decisions` as written, with `min(selection.options(...), default=None)` (:547), so
  `None` for a decision with no option selected; `# OPEN(O30)` at :543. Design §5 keeps O30 in
  two places, here and in `render_command` (:605, step 6).

## 8. One universe: astra view

The stack as one universe sees it: what UIs read (design §4.6).

```console
$ astra view median
universe median
astra.yaml  built
  spikes       keep
  centre       median
  cut          inactive
  clean        clean#median  results/median/clean.csv
  summary      summary#median  results/median/summary.json
  comparison   comparison  results/comparison.csv
$ astra view median --json | jq -c 'keys, (.analyses[0] | keys)'
["analyses","root","shape","universe"]
["built","commit","decisions","fields","file","folder","outputs"]
$ astra view median --json | jq -c '.analyses[0] | .decisions, .outputs.summary, .outputs.comparison'
{"spikes":{"active":true,"selected":"keep"},"centre":{"active":true,"selected":"median"},"cut":{"active":false,"selected":null}}
{"active":true,"result":{"names":["summary"],"owner":{"folder":"","commit":null},"universe":"median","places":[{"name":"summary","address":"summary#median","record":".astra/records/median/summary.json","bytes":"results/median/summary.json"}]}}
{"active":true,"result":{"names":["comparison"],"owner":{"folder":"","commit":null},"universe":null,"places":[{"name":"comparison","address":"comparison","record":".astra/records/comparison.json","bytes":"results/comparison.csv"}]}}
$ astra view median --json | jq -c '.analyses[0].fields.universes.median'
{"label":"Median, spikes kept","derived_from":"trimmed","decisions":{"centre":"median"}}
```

What to notice:

- One block per analysis of the stack, the root first; here the root is the whole stack. `built`
  says whether the analysis is built in the universe: the root always is, a declared analysis
  where the universe drives it (§16).
- `cut` shown `inactive` is `active: false, selected: null`. A decision that is active but has
  nothing selected would show `no option selected`, and an output with no result `inactive` or
  `no planned result`.
- `comparison` appears with its one result in every universe's view.
- `decisions` holds the effective selection; `fields` holds the document as written, so
  `fields.universes.median` still says `derived_from: trimmed` and one key. A UI gets both
  without a YAML reader of its own.
- The view has no commands, inputs or notes: it isn't a plan. `astra view nope` fails as
  `astra universe show nope` does, with the same error line and exit 2.

Under the hood:

- `src/astra/cli/view.py:29` calls `api.view`, which validates first like `api.plan`
  (`src/astra/api.py:112`), then `src/astra/view.py:96` `view`.
- `src/astra/view.py:100` resolves the universe with `root_universe`; :101 takes its selection
  from the same `Context` as the rules; :103 takes the analyses built in it from
  `context.building.universes`.
- `src/astra/view.py:109`: the selected option is `min(selection.options(decision))`, one option
  in a valid stack. :114-115 find an output's result under `(output, universe)` if it is built
  per universe, else `(output, None)`.
- The JSON is `src/astra/view.py:57`; `fields` is `member.document.value` (:75).
- The text's words for a decision and an output: `src/astra/cli/text/view.py:25-27` and
  :33-35.

## Try

Predict first, then run. Each answer was run in this order from a fresh setup, and ends with
`git checkout --quiet astra.yaml`.

**1. Change a universe's selection.** Derive `trimmed` from `mean`, so that it inherits
`spikes: drop` instead of keeping the spikes:

```console
$ perl -pi -e 's/    decisions: \{spikes: keep, centre: trimmed, cut: p10\}/    derived_from: mean\n    decisions: {centre: trimmed, cut: p10}/' astra.yaml
```

What does `astra universe show median` print now, and what do the plan's notes count? Then make
`median` select `centre: mean` as well: what do the notes count? Last, from a clean file, make
only that second change: what happens?

<details><summary>Answer</summary>

```console
$ astra universe show median
median  derived from trimmed
  spikes: drop  (from mean)
  centre: median
$ astra plan | tail -n 2
7 planned result(s), and notes, none of them a breach (--notes lists them):
  1 computation(s) repeated across universes, in 3 result(s)
$ perl -pi -e 's/decisions: \{centre: median\}/decisions: {centre: mean}/' astra.yaml
$ astra plan --notes | sed -n '/^note/,$p'
note `clean#mean`, `clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
note `summary#mean`, `summary#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
7 planned result(s), and notes, none of them a breach:
  2 computation(s) repeated across universes, in 5 result(s)
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/decisions: \{centre: median\}/decisions: {centre: mean}/' astra.yaml
$ astra plan
astra.yaml
  69:17 error MISSING_REQUIRED_OPTION `median` selects `centre: mean`, which requires `spikes.drop`, and it isn't selected
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ echo $?
1
$ astra plan --json | jq -r .shape
astra-validation-report/1
$ astra universe show median
median  derived from trimmed
  spikes: keep  (from trimmed)
  centre: mean
$ git checkout --quiet astra.yaml
```

- `trimmed` now inherits `spikes: drop` from `mean`, and `median` inherits it from `trimmed`.
  `(from mean)` names the universe that wrote the key, two steps up the chain, not the parent.
- All three `clean` results select `spikes: drop`: one computation in three results.
- With `centre: mean`, `summary#median` has the same command and options as `summary#mean`, and
  its `clean` read is the same computation as `summary#mean`'s, so the two are one computation
  too (`src/astra/plan.py:431-436`). Two notes, five results.
- From the clean file, `median` inherits `spikes: keep`, and `mean` requires `spikes.drop`. The
  breach is reported at `median`'s own key `centre` (69:17): the option that carries the
  constraint is the one the universe sets itself. `astra plan` exits 1 with the report, and
  `astra plan --json` prints the report's JSON, `astra-validation-report/1`, not a plan: a
  consumer checks `shape`. `astra universe show` still prints the selection.

</details>

**2. Add an option that excludes another, and select both.** Give `centre` an option
`winsorised` that is `incompatible_with` `spikes.drop`, and a universe that derives from `mean`
and selects it:

```console
$ perl -pi -e 's/^      trimmed: \{\}\n/$&      winsorised:\n        incompatible_with: [spikes.drop]\n/' astra.yaml
$ printf '  winsorised:\n    derived_from: mean\n    decisions: {centre: winsorised}\n' >> astra.yaml
```

Which code, and at which line and column? Then put the constraint on the other side, on
`spikes.drop`, with `incompatible_with: [centre.winsorised]`: where is it reported now?

<details><summary>Answer</summary>

```console
$ astra plan
astra.yaml
  74:17 error INCOMPATIBLE_OPTIONS `winsorised` selects `centre: winsorised`, which is incompatible with `spikes.drop`, selected too
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ astra universe show winsorised
winsorised  derived from mean
  spikes: drop  (from mean)
  centre: winsorised
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/^      trimmed: \{\}\n/$&      winsorised: {}\n/; s/^        description: Drop every.*\n/$&        incompatible_with: [centre.winsorised]\n/' astra.yaml
$ printf '  winsorised:\n    derived_from: mean\n    decisions: {centre: winsorised}\n' >> astra.yaml
$ astra validate
astra.yaml
  73:19 error INCOMPATIBLE_OPTIONS `winsorised` inherits `spikes: drop` from `mean`, which is incompatible with `centre.winsorised`, selected too
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ astra validate --json | jq -c '.diagnostics[] | {code, at: .location.pointer, key: .location.key, related: [.related[] | [.pointer, .key, .line, .column]]}'
{"code":"INCOMPATIBLE_OPTIONS","at":"/universes/winsorised/derived_from","key":null,"related":[["/universes/mean/decisions","spikes",64,17],["/decisions/spikes/options/drop/incompatible_with/0",null,17,29]]}
$ git checkout --quiet astra.yaml
```

- The rule is checked for each selected option against its own constraints
  (`src/astra/rules/universes.py:124`), so it is reported once, on the option that carries
  `incompatible_with`, though §8 makes the pair symmetric in meaning.
- First, that option is `centre: winsorised`, which the universe sets itself: reported at its key
  (74:17, `centre` in `{centre: winsorised}`).
- Second, it is the inherited `spikes: drop`: reported at the universe's `derived_from` (73:19),
  with the key `spikes` where `mean` writes it (64:17) as a related place, and the constraint
  (17:29) as another. The JSON is filtered to the pointer, key, line and column of each. Where a
  rule broken through inheritance is reported is astra-tools' own choice (design §3), made in
  `_at`, `src/astra/rules/universes.py:143`. The text shows only the main place; the JSON has the
  related ones.
- `astra universe show` still answers on the invalid file; `astra plan` doesn't.

</details>

**3. Make a placeholder name nothing.** In `summary`'s command, write `{inputs.cleaned}` for
`{inputs.clean}`:

```console
$ perl -pi -e 's/\{inputs\.clean\}/{inputs.cleaned}/' astra.yaml
```

What does `astra plan` do? Then, from a clean file, add `--spikes={decisions.spikes}` to the same
command: `spikes` is a decision of the analysis, so is that a placeholder of `summary`? Last,
write `{{inputs.clean}}` for `{inputs.clean}`: valid? What does the plan's command say?

<details><summary>Answer</summary>

```console
$ astra plan
astra.yaml
  50:16 error UNDECLARED_TEMPLATE_REF `{inputs.cleaned}` isn't a placeholder of this output: it takes `{inputs}`, `{output}`, and `{inputs.<entry>}` and `{decisions.<entry>}` for an entry of its `inputs` or `decisions` as written; `{{` and `}}` are literal braces
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/--cut=\{decisions\.cut\}/$& --spikes={decisions.spikes}/' astra.yaml
$ astra validate
astra.yaml
  50:16 error UNDECLARED_TEMPLATE_REF `{decisions.spikes}` isn't a placeholder of this output: it takes `{inputs}`, `{output}`, and `{inputs.<entry>}` and `{decisions.<entry>}` for an entry of its `inputs` or `decisions` as written; `{{` and `}}` are literal braces
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/ \{inputs\.clean\} / {{inputs.clean}} /' astra.yaml
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra plan | grep summarise
  command   python3 src/summarise.py --centre=mean --cut= {inputs.clean} results/mean/summary.json
  command   python3 src/summarise.py --centre=trimmed --cut=p10 {inputs.clean} results/trimmed/summary.json
  command   python3 src/summarise.py --centre=median --cut= {inputs.clean} results/median/summary.json
$ git checkout --quiet astra.yaml
```

- A placeholder is checked against the output's own `inputs` and `decisions`, as written
  (`_gives`, `src/astra/rules/recipes.py:53`), not against the analysis's elements. `spikes`
  reaches `summary` only through `clean`, and an output's `decisions` lists the decisions it is
  made with directly ([§10](https://astra-spec.org/0.1/specification/#10-outputs)), so
  `summary` doesn't list it and has no `{decisions.spikes}`. Listing it would change no result
  ([§13](https://astra-spec.org/0.1/specification/#13-pins-and-outputs-built-per-universe-or-once)).
- The error is at the command's value (50:16), not at the placeholder; the message names it.
- `{{inputs.clean}}` is a literal `{inputs.clean}`: valid, and the recipe gets the text instead
  of the path to `clean`'s bytes. No rule says a command uses every entry of its `inputs`, so
  the plan is valid and the recipe would fail when run.

</details>

**4. Switch an output on with an option no universe selects.** Add an output `quartiles` that is
active only where `cut.p25` is selected:

```console
$ perl -pi -e 's|^universes:|  quartiles:\n    type: table\n    format: json\n    inputs: [clean]\n    when: [cut.p25]\n    recipe:\n      command: python3 src/quartiles.py {inputs.clean} {output}\n\nuniverses:|' astra.yaml
```

What does the plan say about it, and what does `astra view mean` show for it? `cut` is inactive
in `mean`: which of design §5's open readings decides that line? Then make the condition
`~cut.p25`: how many results, and what do the notes count?

<details><summary>Answer</summary>

```console
$ astra plan --notes | sed -n '/^note/,$p'
note astra.yaml:60:5 `quartiles` has no planned result: it is active in none of the root's universes, so a check of the root never covers it
note `clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
7 planned result(s), and notes, none of them a breach:
  1 output(s) have no planned result
  1 computation(s) repeated across universes, in 2 result(s)
$ astra view mean | grep quartiles
  quartiles    inactive
$ perl -pi -e 's/when: \[cut\.p25\]/when: ["~cut.p25"]/' astra.yaml
$ astra plan | grep '^quartiles'
quartiles#mean
quartiles#trimmed
quartiles#median
$ astra plan | tail -n 2
10 planned result(s), and notes, none of them a breach (--notes lists them):
  2 computation(s) repeated across universes, in 4 result(s)
$ git checkout --quiet astra.yaml
```

- `unplanned` is a note, not a rule: an output active in none of the root's universes is valid,
  and a check never covers it (`_unplanned`, `src/astra/plan.py:390`). Its location, 60:5, is
  where the output's value starts, `type:`, one line below `quartiles:`.
- In `mean`, `cut` has nothing selected and is inactive. `OPEN(O16)` reads `cut.p25` as false
  there, so `quartiles` is `inactive`. Read the other way, its activity would be undetermined
  (design §4.13 case 6), and the view would say `no planned result`.
- With `~cut.p25`, the same reading makes it true in `mean` and `median`, and `p10` makes it true
  in `trimmed`: three results. `quartiles` lists no decisions and reads `clean`, so
  `quartiles#trimmed` and `quartiles#median` are one computation, because their `clean` reads are.
- `src/quartiles.py` doesn't exist. Nothing notices before a run: the plan reads a command only
  for its placeholders and, for `outside_folder`, for paths that leave the folder or pass
  through a folder holding an `astra.yaml`; it never looks for the file a path names.

</details>

## What you now know

- `astra universe show` is §12's three steps in `universes.effective_selection` and `_derive`,
  computed for every universe at once, text only and without validating. Step 3 runs once
  (`OPEN(O2)`), and `(from …)` names the universe that wrote a key.
- The plan is `universes.building` (what is built in which universe, from `per_universe` and
  `read_in`) put in reading order by `plan.visit`. Names, addresses and places come from
  `universes.places`, and there is no plan of an invalid analysis.
- `render_command` fills §11's placeholders verbatim, relative to the folder the recipe runs in or
  absolute. `astra-plan/1` carries the template, read indices and `null` for an inactive decision
  (`OPEN(O30)`, the empty string in a command).
- The notes are astra-tools' own, never diagnostics. `same_computation` follows computations
  through what results read.
- `astra view` is the effective selection, activity and planned results of one universe, beside
  the document as written.
- A constraint is checked on the option that carries it. Broken through an inherited key, it is
  reported at the universe's `derived_from`, with the key where it is written as a related place
  (design §3).
