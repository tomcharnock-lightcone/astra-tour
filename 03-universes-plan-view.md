# 3. Decisions, universes, plan and view

One analysis with three decisions, three universes, four outputs and a switch, and what
astra-tools makes of it: each universe's effective selection, the case the switch takes and the
decisions each universe uses, the planned results with their names, places and commands, the
plan's notes, and the stack as one universe sees it. Nothing is built here: the chapter stops
where a runner starts.

## Setup

```console
$ source env.sh
astra: …/astra-tools/.venv/bin/astra (astra, version 0.2.19.dev…)
work:  …/tour/work
$ sh setup/03.sh
work/03/readings: d2ea15f Estimate the readings' central value three ways
$ cd work/03/readings
```

- `setup/03.sh` removes `work/03` and makes `work/03/readings` again: a git repository with one
  commit (fixed author and date, so the id is `d2ea15f` for you too) holding the analysis, its
  input and three small scripts. Run it again, from the tour's folder, whenever you want the
  starting state back.
- Steps 7 and 8 and some answers use `jq`. If it isn't on your PATH, start with
  `nix shell 'nixpkgs#jq'`, then `source env.sh` in that shell.
- Every step runs in `work/03/readings`. The steps and exercises that edit `astra.yaml` end
  with `git checkout --quiet astra.yaml`.
- Like every chapter, this one cites the published specification, as the README's *Citations*
  says: a rule by its code, anything else by a section, then the term it defines in bold there if
  it defines one, such as Elements *switch* or Results *uses*. Switches aren't in the long
  specification that astra-tools' code cites by `§n`.

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
  plain:
    label: Mean or median
    type: metric
    format: json
    inputs: [clean]
    decisions: [centre]
    recipe:
      command: python3 src/summarise.py --centre={decisions.centre} {inputs.clean} {output}
  trimmed_mean:
    label: Trimmed mean
    type: metric
    format: json
    inputs: [clean]
    decisions: [cut]
    recipe:
      command: python3 src/summarise.py --centre=trimmed --cut={decisions.cut} {inputs.clean} {output}
  summary:
    label: Central value
    switch: centre
    cases: {mean: plain, median: plain, trimmed: trimmed_mean}
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

- Three decisions ([Elements](https://astra-spec.org/0.1/specification/#elements) *decision*):
  `spikes`; `centre`, whose `mean` `requires` `spikes.drop` and whose `mode` is `excluded`; and
  `cut`. None is conditional: whether a universe uses `cut` follows from what is planned there
  (step 3).
- `summary` is a **switch** (Elements *switch*): `switch` names a decision, `centre`, and
  `cases` maps options of it to references. It has no `type`, `format`, `inputs`, `decisions` or
  recipe, and no result of its own. In each universe it **takes** the case of the option
  `centre` selects there, and reading it reads what that case names: `plain` for `mean` and for
  `median` (options may share a case), `trimmed_mean` for `trimmed`. `mode` needs no case: it is
  excluded, so never selected.
- `clean`, `plain` and `trimmed_mean` list `decisions`, so each is built per universe.
  `comparison` lists none and reads `summary` only pinned, so it is built once, like line-fit's
  `comparison` (Elements *built per universe*). A switch is neither.
- Only `trimmed_mean` lists `cut`, and `summary` reads it only where `centre` selects `trimmed`.
  So only a universe that selects `trimmed` uses `cut`, and `plain`'s command, which has no
  `--cut`, never needs one.
- The universes are inline in the file, none of them an import. `median` derives from
  `trimmed` and writes one key.
- The commands use every placeholder form: `{inputs.<entry>}`, `{decisions.<entry>}`,
  `{inputs}`, `{output}`, and `{{ }}` for literal braces
  ([Elements](https://astra-spec.org/0.1/specification/#elements) *placeholders*,
  `UNDECLARED_TEMPLATE_REF`).

Under the hood:

- How `astra validate` works is chapter 2's subject. The rules the exercises break are in
  `src/astra/rules/universes.py`: `_unused` (:73; `UNUSED_DECISION` at :106,
  `INACTIVE_DECISION` at :117) and `_selected` (:180; `excluded` at :198, `requires` at :204,
  `incompatible_with` at :213); in `src/astra/rules/driving.py:121` (`_missing`,
  `MISSING_DECISION`); in `src/astra/rules/pins.py:33` (`_not_built`, `PIN_NOT_BUILT`); and in
  `src/astra/rules/recipes.py:37` (`_problems`, `UNDECLARED_TEMPLATE_REF`), which skips a switch
  (:26), as it has no recipe.
- The selection rules (`MISSING_REQUIRED_OPTION`, `INCOMPATIBLE_OPTIONS`,
  `EXCLUDED_OPTION_SELECTED`) judge effective selections, not universes as written:
  `src/astra/rules/universes.py:63` loops over `context.selections`, which is step 2's
  function. The two constraints are judged only for a decision in play, one the universe uses
  (:66, :202; Results *in play*). `UNUSED_DECISION` and `INACTIVE_DECISION` judge each
  universe's own keys as written (`own_keys`, :83), and `UNKNOWN_DERIVED_FROM` and
  `DERIVED_FROM_CYCLE` its `derived_from` as written (:55-59).
  `UNDECLARED_TEMPLATE_REF` reads only the command and its output's own `inputs` and `decisions`.
- A switch's fields are the schema's to police, in chapter 2's schema layer: an entry of
  `outputs` with `switch` or `cases` has both, and no `type`, `format`, `inputs`, `decisions` or
  `recipe`, or it breaks `INVALID_SWITCH`.

## 2. The universes and their effective selections

A universe's selection is what a reader of the file has to work out by hand once `derived_from`
is used (Elements *effective selection*: it inherits another universe's selection, replacing what
it sets). `astra universe` shows it.

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
  cut: p10  (from trimmed)
  centre: median
$ astra universe show nope
Usage: astra universe show [OPTIONS] UNIVERSE [PATH]
Try 'astra universe show --help' for help.

Error: Invalid value for UNIVERSE: the analysis has no universe `nope`: its universes are mean, trimmed, median
$ echo $?
2
```

A universe's own keys are judged against what it uses; inherited ones aren't. Give `mean` a key
for `cut`:

```console
$ perl -pi -e 's/\{spikes: drop, centre: mean\}/{spikes: drop, centre: mean, cut: p25}/' astra.yaml
$ astra validate
astra.yaml
  73:45 warning INACTIVE_DECISION `mean` sets `cut`, which it doesn't use: it is used only where a switch takes another case, or in a universe that inherits the key. Set it only in the universes that use it
astra.yaml: valid, 0 error(s), 1 warning(s)
$ git checkout --quiet astra.yaml
```

What to notice:

- `list` is the file's order, with `derived from` and the label. An import would show
  `imports <analysis>.<universe>`.
- `show median` gives the inherited keys first, then its own. `(from trimmed)` names the
  universe whose own `decisions` wrote the key. In a longer chain it is still the writer, not
  the parent (Try 1).
- `cut: p10`, which `trimmed` selects, stays in `median`: the effective selection is the
  inherited one with the universe's own keys written over it, and nothing is dropped. `median`
  doesn't use `cut`, since `summary` takes `plain` there (step 3), and that breaks nothing: an
  inherited key is never judged against what the universe uses.
- A universe's own key for a decision it uses on no branch, whatever case each switch takes,
  breaks `UNUSED_DECISION`, a `MUST` (Try 2). A key for one it uses on some branch, but not with
  the options it selects, breaks `INACTIVE_DECISION`, a `SHOULD`: a warning, and the file stays
  valid (Results *uses on some branch*). `mean` uses `cut` on some branch: `comparison` reads
  `summary#mean`, and one of `summary`'s cases is `trimmed_mean`, which lists `cut`. The
  warning is at the key (73:45), `cut` in `{spikes: drop, centre: mean, cut: p25}`.
- `astra universe` prints text only; there is no `--json` (design §4.12). It doesn't validate:
  it needs only a root file that is a valid document in a repository, so it shows a selection
  even when the analysis breaks a `MUST` (Try 1 and 2). It exits 1 where the universe has no
  effective selection (a `derived_from` that names nothing or loops, design §4.13 case 7), and
  2 for an id that isn't a universe of the root.

Under the hood:

- `src/astra/cli/universe.py:47` resolves the id with `plan.root_universe`
  (`src/astra/plan.py:331`), which refuses an unknown id or an import; click turns that into a
  usage error, exit 2 (`src/astra/cli/universe.py:49`).
- `src/astra/cli/universe.py:50` computes `universes.selections(stack)`: the selection of every
  universe of every analysis in the stack, not only the one asked for.
- `src/astra/universes.py:116` `effective_selection` is recursive and memoised in `found`;
  `deriving` (:120) is the loop guard. Step 1 is :132-133: no `derived_from`, the own keys.
- `src/astra/universes.py:145` `_derive` is step 2: it keeps each inherited key that no own key
  replaces (:149), by `_one_key` (:153): the same key, or two spellings of one decision. There is
  no step 3: the long specification's third step, which dropped an inherited key for a decision
  a condition switched off, left the specification with conditions.
- `_unused` (`src/astra/rules/universes.py:73`) judges each own key: on a branch where its
  analysis's `Run.branches` (`src/astra/universes.py:764`) holds its decision in the universe, or
  in a universe that inherits the key without setting it (:87-96); used where `Context.used`
  holds it (:108).
- The `(from …)` suffix is `entry.owner.id`, at `src/astra/cli/text/universe.py:40`.

## 3. The effective selection from the inside

The same computation through the Python API, with what the CLI doesn't print: what each
universe inherited, the decisions it uses, those it uses on some branch, and the case `summary`
takes in it.

```console
$ python - <<'EOF'
from astra import api
from astra.diagnostics import Catalogue
from astra.rules.context import Context

stack = api.bind().stack
context = Context(stack, Catalogue.load())
run = context.runs[stack.root]
summary = stack.element("summary", "switch")
for universe, selection in context.selections.items():
    taken = context.meaning.taken(summary, universe)
    print(universe.id)
    print("  inherited", [f"{e.key}: {e.option}" for e in selection.inherited])
    print("  entries  ", [f"{e.key}: {e.option} ({e.owner.id})" for e in selection.entries])
    print("  uses     ", sorted(d.id for d in run.used[universe]))
    print("  branches ", sorted(d.id for d in run.branches[universe]))
    print("  summary  ", f"takes {taken.case.written}, for {taken.option}")
EOF
mean
  inherited []
  entries   ['spikes: drop (mean)', 'centre: mean (mean)']
  uses      ['centre', 'spikes']
  branches  ['centre', 'cut', 'spikes']
  summary   takes plain, for mean
trimmed
  inherited []
  entries   ['spikes: keep (trimmed)', 'centre: trimmed (trimmed)', 'cut: p10 (trimmed)']
  uses      ['centre', 'cut', 'spikes']
  branches  ['centre', 'cut', 'spikes']
  summary   takes trimmed_mean, for trimmed
median
  inherited ['spikes: keep', 'centre: trimmed', 'cut: p10']
  entries   ['spikes: keep (trimmed)', 'cut: p10 (trimmed)', 'centre: median (median)']
  uses      ['centre', 'spikes']
  branches  ['centre', 'cut', 'spikes']
  summary   takes plain, for median
```

What to notice:

- `median.inherited` is `trimmed`'s whole effective selection, and its `entries` keep
  `cut: p10`, with `trimmed` as its owner.
- Each entry is a `Resolution`: the key as written, the option, and `owner`, the universe whose
  own `decisions` hold it. It is the same object the rules report from, which is why a rule
  broken through inheritance can name the universe that wrote the key (Try 2).
- `uses` is Results *uses*: the decisions that results planned in the universe list, and those
  that switches reached there switch on. `summary` is reached in every universe, through
  `comparison`'s pins, so each uses `centre`; only `trimmed` plans `trimmed_mean`, so only it
  uses `cut`.
- `branches` is Results *uses on some branch*: the same, with every case of every switch
  followed, whatever it takes. `cut` is in every universe's, which is why `mean`'s key in step 2
  was a warning, not an error.
- `taken` is what `summary` takes: the option `centre` selects there, and the case keyed by it,
  itself a `Resolution` (`written` is the reference as written in `cases`).
- `api.bind()` reads and binds without running the validator rules, as `astra universe` does.
  `Context` (`astra.rules.context`) is what every validator rule is a function of (design §4.4),
  each part computed once; the plan and the view build one too.

Under the hood:

- `Selection` is `src/astra/universes.py:50`: `universe`, `entries`, `inherited`, and `own()`,
  `options()`. A selection says what is selected, not what matters: that is the run's.
- `Context` (`src/astra/rules/context.py:22`) holds each as a `cached_property`: `selections`
  (:51), `meaning` (:87), and `runs` (:95), one `Run` for each analysis of the stack, with itself
  driving.
- `Meaning.taken` (`src/astra/universes.py:601`, `_take` :612): a `Taken` whose `case` is `None`
  where the option selected has no case, or `None` where what the switch takes is undetermined,
  as where its decision is unset (design §4.13 case 6).
- `run` (`src/astra/universes.py:773`) reaches from the planning roots (`_roots`, :926),
  following every entry of an output's `inputs` (:859-865) and only the case each switch takes
  (:849-858); it plans a root where it is built, and what a planned result reads (:876-881).
  `used` (:884-892) is what results planned there list (`_listed`, :954) and what switches
  reached there switch on (`_switched_on`, :963). `branches` comes from `_branches` (:997),
  which follows every case of every switch (:1055-1056), a pinned read counting for its pin's
  universe.

## 4. The plan, as text

The planned results ([Results](https://astra-spec.org/0.1/specification/#results) *plans*),
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
plain#mean
  record    .astra/records/mean/plain.json
  bytes     results/mean/plain.json
  run in    .
  command   python3 src/summarise.py --centre=mean results/mean/clean.csv results/mean/plain.json
trimmed_mean#trimmed
  record    .astra/records/trimmed/trimmed_mean.json
  bytes     results/trimmed/trimmed_mean.json
  run in    .
  command   python3 src/summarise.py --centre=trimmed --cut=p10 results/trimmed/clean.csv results/trimmed/trimmed_mean.json
plain#median
  record    .astra/records/median/plain.json
  bytes     results/median/plain.json
  run in    .
  command   python3 src/summarise.py --centre=median results/median/clean.csv results/median/plain.json
comparison
  record    .astra/records/comparison.json
  bytes     results/comparison.csv
  run in    .
  command   python3 src/compare.py --format='{:.2f}' results/mean/plain.json results/trimmed/trimmed_mean.json results/median/plain.json results/comparison.csv
7 planned result(s), and notes, none of them a breach (--notes lists them):
  1 computation(s) repeated across universes, in 2 result(s)
```

What to notice:

- Seven results: `clean` in each universe; `plain` in `mean` and `median`, and `trimmed_mean` in
  `trimmed`, where `summary` takes them; and `comparison` once. Each heading is a result's
  address: its name, then `#` and the universe for a result built in one.
- `summary` has no heading: a switch has no result, name or place. Nor are `plain` and
  `trimmed_mean` planned for themselves: a case names each, so each is planned only where
  something planned reads it (Results *plans*). The planning roots are `clean`, in each universe,
  and `comparison`, once, which reads `summary` in each universe and, through the case it takes
  there, `plain#mean`, `trimmed_mean#trimmed` and `plain#median`. `trimmed_mean` would be built
  in `mean` too, but nothing there reads it.
- Places (Results *place*, *default place*): the record at `.astra/records/{universe}/{name}.json`
  and the bytes at their default place, `results/{universe}/{name}.{format}`; for `comparison`,
  built once, neither has a `{universe}`. Paths are from the top of the repository, which is
  the analysis's folder here.
- `run in .` is the analysis's folder (Elements *recipe*). A result of an analysis from a commit
  has `read through its record at <commit>` instead, and no command (chapter 5's step 4 shows
  one).
- Each result comes after what it reads. The plan takes the results in the order it reaches
  them, `clean` in each universe, then `comparison`, and puts each after what it reads: here,
  `comparison`'s three, in the order of its `inputs`, before `comparison`. Step 6 shows another
  order.
- `--cut` appears once, with a value. Only `trimmed_mean` lists `cut`, and a universe that plans
  it uses `cut`, so sets it (`MISSING_DECISION` otherwise): `{decisions.<entry>}` always has an
  option to give.
- In `comparison`, `{inputs}` is the three pinned paths in the order of `inputs`: each
  `summary#<universe>` gives the bytes of the case `summary` takes in that universe. And
  `'{{:.2f}}'` became `'{:.2f}'`. Nothing is quoted for the shell: Elements *placeholders* says
  verbatim.
- The exit code is 0. With a `MUST` broken, `astra plan` prints the validation report instead and
  exits 1 (Try 1 to 3): there is no plan of an invalid analysis. The exit codes are astra-tools'
  own (design §4.12; chapter 1, step 3). For `universe show` and `view`, an unknown universe is
  a usage error, exit 2.

Under the hood:

- `src/astra/cli/plan.py:40` calls `api.plan`, which validates first: `src/astra/api.py:180`
  raises `InvalidAnalysisError`, and `src/astra/cli/plan.py:41-43` prints its report and exits 1.
- `src/astra/plan.py:186` `plan()` builds a rules `Context` (:204), the root's run (:208,
  `universes.run`, step 3) and `universes.building` (:209), which gives the planned results.
- Per universe or once is `src/astra/universes.py:385` `per_universe`: outputs other than a
  switch that list `decisions` (:391-396), then, until nothing grows, outputs with an unpinned
  entry naming a switch or one of those (:397-409). Every entry of `comparison` has a pin, so it
  stays out.
- `_roots` (`src/astra/universes.py:926`): the root's outputs other than switches that no case
  of its own names, and its switches that nothing of its own reads or names (:939-943). `plain`
  and `trimmed_mean` are named by `summary`'s cases, and `comparison` reads `summary`.
- `src/astra/universes.py:1085` `building`: the root's universes, and each other universe its run
  reads in (:1094-1096); a result for each output the run plans (:1098-1102).
- `read_in` (`src/astra/universes.py:506`) gives the universe an entry or a case reads in: the
  reader's own for an unpinned one, the pin's for a pinned one (:519), none for an input or an
  output built once (:517-518). `Meaning.through` (:696) follows a switch, and a switch its case
  names, to the case each takes there (:703-716).
- `places` (`src/astra/universes.py:488`) writes the address (:498), the record (:499) and the
  bytes (:500).
- `src/astra/plan.py:230` `visit` puts each result after the results it reads; `_reads` (:361)
  and `_result` (:398) fill in what each entry reads and the rest of the result.
- The text renders each command at `src/astra/cli/text/plan.py:39`:
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
note astra.yaml:41:16 the command names `../tools/clean.py`, outside its analysis's folder: a recipe should run only code tracked in its analysis's folder, outside every folder below it that holds an analysis of its own, or that its output's inputs give it (`CODE_OUTSIDE_ANALYSIS`, §21)
7 planned result(s), and notes, none of them a breach:
  1 computation(s) repeated across universes, in 2 result(s)
  1 command(s) name a path outside their analysis (CODE_OUTSIDE_ANALYSIS)
$ git checkout --quiet astra.yaml
```

What to notice:

- Notes are astra-tools' own (design §4.6), not the spec's: none has a code, none changes an exit
  code, and `astra validate` shows none of them (a result with two names also breaks the
  `SHOULD` `RESULT_IN_TWO_PLACES`, which `validate` reports in its own right). The kinds are
  `fallback_pin`, `two_names`, `unplanned`, `not_built`, `same_computation` and
  `outside_folder`. This chapter meets four (`unplanned` and `not_built` in Try 4); the other
  two need declared analyses.
- `clean#trimmed` and `clean#median` have the same command, read the same file and select the
  same option of the one decision `clean` lists, `spikes: keep`. The universes differ only in
  `centre`, which `clean` doesn't list. A runner may build one and place the bytes at both.
- `plain#mean` and `plain#median` aren't one computation: `centre` differs, and so do the
  `clean` results they read.
- `not_built` is the plan's report of a missing case: an output reached in a universe where a
  switch on the way has no case for the option selected there isn't built there. That breaks no
  rule (Elements *switch*), so the plan says where, and which switch and option (Try 4).
- `outside_folder` names `CODE_OUTSIDE_ANALYSIS`, a runner rule
  ([Rules](https://astra-spec.org/0.1/specification/#rules)) that no validator checks; the note
  is astra-tools reading the command as text. It has a location (41:16, the command's value); the
  notes about results (`same_computation`, `two_names`) have none.
- The text counts and lists only notes about what this root builds (`built`); the JSON lists all
  of them (step 7).

Under the hood:

- `src/astra/plan.py:437` `_notes` yields the kinds in a fixed order (:453-460).
- `_same_computations` (`src/astra/plan.py:571`): a computation is the output, what it reads and
  the options selected (:589). A read of another planned result counts as that result's
  computation (:583-588), so two `plain` results that read one `clean` computation and select
  the same options are one computation too (Try 1).
- `_not_built` (`src/astra/plan.py:546`): for each output the root's run reaches in a universe,
  `Meaning.cause` (`src/astra/universes.py:672`) gives the first switch on the way with no case
  there; one note for each output, switch and option, with the universes (:551-557).
- `_outside_folder` (`src/astra/plan.py:608`): `_paths` (:663) takes each word of the command
  outside its placeholders, which it masks (:667), and skips absolute paths; `_climbs` (:675)
  counts `..` against the folders before them; `below` (:620) looks for an `astra.yaml` in each
  folder on the way to a path that stays inside.
- `src/astra/cli/text/plan.py:40` keeps the `built` notes; :41-48 list them under `--notes`;
  :53-68 count them by kind.

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
try:
    api.plan(outputs=["summary"])
except api.RequestError as error:
    print(error)
EOF
python3 src/compare.py --format='{{:.2f}}' {inputs} {output}
python3 src/compare.py --format='{:.2f}' results/mean/plain.json results/trimmed/trimmed_mean.json results/median/plain.json results/comparison.csv
python3 src/compare.py --format='{:.2f}' /srv/run/results/mean/plain.json /srv/run/results/trimmed/trimmed_mean.json /srv/run/results/median/plain.json /srv/run/results/comparison.csv
['clean#median', 'plain#median']
['clean#mean', 'plain#mean', 'clean#trimmed', 'trimmed_mean#trimmed', 'clean#median', 'plain#median', 'comparison']
`summary` is a switch, which has no result of its own: ask for the output a case names
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
  from that one seed: each `clean` right before the result that reads it. "Each after what it
  reads" is the only promise about order.
- `outputs` names outputs to build, and a switch is none: asking for `summary` is a usage error,
  `RequestError`. Ask for `plain` or `trimmed_mean` instead.

Under the hood:

- `src/astra/plan.py:711` `render_command`: `depth` and `top` (:732-733) find the checkout's top
  from `cwd` and the result's `workdir`, since every path in the plan is from that top; `path`
  (:736) makes each relative to `cwd` or absolute.
- `_TEMPLATE` (`src/astra/plan.py:706`) reads `{{`, `}}` and `{…}` from the left, as
  `UNDECLARED_TEMPLATE_REF` says. `fill` (:747): a brace pair (:749-750), `{output}` as the
  first name's bytes (:751-752), `{inputs}` joined by spaces (:753-754), `{inputs.<entry>}`
  (:755-757), and `{decisions.<entry>}` as `result.decisions[entry]` (:758), which a valid stack
  always fills.
- `where` (:740-743): an entry read at a commit renders as `<commit>:<path>` unless `got=` gives
  where the runner put its bytes.
- The validator scans braces with a regex of its own, `src/astra/rules/recipes.py:33`, which
  also matches a stray `{` or `}`. `render_command` assumes a command that passed it.
- The filters: `src/astra/plan.py:211` `chosen`; with `universes` alone, a result is kept where
  `result.universe in wanted` (:213), which `None`, built once, never is. `root_output` (:347)
  refuses a switch (:351-355).

## 7. The plan as JSON: astra-plan/1

This is what lightcone-cli and agents read. The shape is astra-tools' own, shared with
astra-typescript and pinned by astra-tools' tests until its JSON Schema exists (design §4.11).

```console
$ astra plan --json | jq -c 'keys'
["notes","results","root","shape"]
$ astra plan --json | jq '.results[3]'
{
  "names": [
    "plain"
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
    "id": "plain"
  },
  "universe": "mean",
  "places": [
    {
      "name": "plain",
      "address": "plain#mean",
      "record": ".astra/records/mean/plain.json",
      "bytes": "results/mean/plain.json"
    }
  ],
  "inputs": [
    {
      "entry": "clean",
      "path": "results/mean/clean.csv",
      "commit": null,
      "result": 0,
      "via": []
    }
  ],
  "decisions": {
    "centre": "mean"
  },
  "command": "python3 src/summarise.py --centre={decisions.centre} {inputs.clean} {output}",
  "workdir": "",
  "read_only": false,
  "run_at": null,
  "resources": null
}
$ astra plan --json | jq -c '.results[] | [.places[0].address, .universe, [.inputs[].result], .decisions]'
["clean#mean","mean",[null],{"spikes":"drop"}]
["clean#trimmed","trimmed",[null],{"spikes":"keep"}]
["clean#median","median",[null],{"spikes":"keep"}]
["plain#mean","mean",[0],{"centre":"mean"}]
["trimmed_mean#trimmed","trimmed",[1],{"cut":"p10"}]
["plain#median","median",[2],{"centre":"median"}]
["comparison",null,[3,4,5],{}]
$ astra plan --json | jq -c '.results[-1].inputs[]'
{"entry":"summary#mean","path":"results/mean/plain.json","commit":null,"result":3,"via":["plain"]}
{"entry":"summary#trimmed","path":"results/trimmed/trimmed_mean.json","commit":null,"result":4,"via":["trimmed_mean"]}
{"entry":"summary#median","path":"results/median/plain.json","commit":null,"result":5,"via":["plain"]}
$ astra plan --json | jq -c '.notes[]'
{"kind":"same_computation","message":"`clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each","location":null,"results":[1,2],"built":true,"universes":[],"switch":null,"option":null}
```

What to notice:

- `owner` and `output.analysis` are identities: the folder from the top (`""` is the top) and
  the commit, `null` for the working tree. `universe` is a bare id, `null` for a result built
  once.
- `inputs` has one entry per entry of the output's `inputs`, as written: `path` from the top,
  `commit` where it is read at one, and `result`, the index of the planned result it reads, or
  `null` for an input's file. An index always points earlier: `comparison` reads 3, 4 and 5.
- A read through a switch keeps its entry as written, `summary#mean`, and gives the path and the
  index of what the case it takes names; `via` lists each case taken on the way, as written, and
  is `[]` for an entry that names no switch.
- `decisions` gives each entry of the output's `decisions` the option selected in its universe:
  never `null` in a valid analysis, which sets every decision it uses.
- `command` is the template. A consumer renders it with `render_command`, or must fill the
  placeholders itself (Elements *placeholders*).
- `read_only` and `run_at` matter only for analyses from a commit; `resources` only where a
  recipe asks for them.
- A note gives its results by index, its location as a whole `Location` or `null`, `built`, and,
  for a `not_built` note, the `universes`, the `switch` and the `option`; the other kinds leave
  those empty.
- On an analysis that breaks a `MUST`, `astra plan --json` prints an
  `astra-validation-report/1` instead, and exits 1 (chapter 1's step 3, and Try 1 here). A
  consumer checks `shape`.

Under the hood:

- `src/astra/plan.py:124` `Plan.to_json`; the index of each result by its output and universe
  (:127), each read as `{entry, path, commit, result, via}` (:129-138), each note (:145-160).
- `via` is each step's case as written (`_result`, `src/astra/plan.py:403`), from
  `Meaning.through` (`src/astra/universes.py:696`); `Read.entry` stays the entry as written.
- `Result.decisions` is `selected` (`src/astra/plan.py:692`, called at :428): each entry of the
  output's `decisions` as written, with `min(selection.options(...), default=None)` (:700).

## 8. One universe: astra view

The stack as one universe sees it: what UIs read (design §4.6).

```console
$ astra view median
universe median
astra.yaml  built
  spikes       keep
  centre       median
  cut          p10  (unused)
  clean        clean#median  results/median/clean.csv
  plain        plain#median  results/median/plain.json
  trimmed_mean no planned result
  summary      takes plain
  comparison   comparison  results/comparison.csv
$ astra view median --json | jq -c 'keys, (.analyses[0] | keys)'
["analyses","root","shape","universe"]
["built","commit","decisions","fields","file","folder","outputs"]
$ astra view median --json | jq -c '.analyses[0] | .decisions, .outputs.summary, .outputs.trimmed_mean, .outputs.comparison'
{"spikes":{"used":true,"selected":"keep"},"centre":{"used":true,"selected":"median"},"cut":{"used":false,"selected":"p10"}}
{"built":true,"takes":"plain","result":null}
{"built":true,"takes":null,"result":null}
{"built":true,"takes":null,"result":{"names":["comparison"],"owner":{"folder":"","commit":null},"universe":null,"places":[{"name":"comparison","address":"comparison","record":".astra/records/comparison.json","bytes":"results/comparison.csv"}]}}
$ astra view median --json | jq -c '.analyses[0].fields.universes.median'
{"label":"Median, spikes kept","derived_from":"trimmed","decisions":{"centre":"median"}}
```

What to notice:

- One block per analysis of the stack, the root first; here the root is the whole stack. `built`
  says whether the analysis is built in the universe: the root always is, a declared analysis
  where the universe drives it (Elements *drives*).
- `cut` is selected but not used in `median`: `p10  (unused)` is `used: false, selected: "p10"`.
  The view keeps the effective selection whole and says which keys matter. A decision neither
  selected nor used shows `unused`, and one used with nothing selected `no option selected`.
- `summary` shows the case it takes there, as written (`takes`), and no result, as a switch has
  none. A switch that takes no case shows `takes nothing`, and one whose case is undetermined
  `undetermined` (Try 4).
- `trimmed_mean` has `built: true`, as what it reads, `clean`, is built in `median` (Results
  *built*), but no planned result: nothing planned reads it there. An output that isn't built,
  as one that reads a switch without a pin where the switch takes nothing, shows `not built`.
- `comparison` appears with its one result in every universe's view.
- `decisions` holds the effective selection; `fields` holds the document as written, so
  `fields.universes.median` still says `derived_from: trimmed` and one key. A UI gets both
  without a YAML reader of its own.
- The view has no commands, inputs or notes: it isn't a plan. `astra view nope` fails as
  `astra universe show nope` does, with the same error line and exit 2.

Under the hood:

- `src/astra/cli/view.py:30` calls `api.view`, which validates first like `api.plan`
  (`src/astra/api.py:113`), then `src/astra/view.py:101` `view`.
- `src/astra/view.py:105` resolves the universe with `root_universe`; :106 takes its selection
  from the same `Context` as the rules; :108 takes the analyses built in it from
  `context.building.universes`; :109-111 take the root's run, and the decisions it uses there
  and those whose use is undetermined.
- `src/astra/view.py:118`: the selected option is `min(selection.options(decision))`, one option
  in a valid stack; :119 makes `used` true, `null` where it turns on an undetermined switch, or
  false. :125 looks a switch, or an output built per universe, up in the universe, any other
  output once; :126-129 take a switch's case from `Meaning.taken`; :132 takes `built` from
  `Meaning.built`.
- The JSON is `src/astra/view.py:62`; `fields` is `member.document.value` (:80).
- The text's words for a decision, a switch and an output: `src/astra/cli/text/view.py:33`,
  :42 and :50.

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
  cut: p10  (from trimmed)
  centre: median
$ astra plan | tail -n 2
7 planned result(s), and notes, none of them a breach (--notes lists them):
  1 computation(s) repeated across universes, in 3 result(s)
$ perl -pi -e 's/decisions: \{centre: median\}/decisions: {centre: mean}/' astra.yaml
$ astra plan --notes | sed -n '/^note/,$p'
note `clean#mean`, `clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
note `plain#mean`, `plain#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
7 planned result(s), and notes, none of them a breach:
  2 computation(s) repeated across universes, in 5 result(s)
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/decisions: \{centre: median\}/decisions: {centre: mean}/' astra.yaml
$ astra plan
astra.yaml
  80:17 error MISSING_REQUIRED_OPTION `median` selects `centre: mean`, which requires `spikes.drop`, and it isn't selected
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ echo $?
1
$ astra plan --json | jq -r .shape
astra-validation-report/1
$ astra universe show median
median  derived from trimmed
  spikes: keep  (from trimmed)
  cut: p10  (from trimmed)
  centre: mean
$ git checkout --quiet astra.yaml
```

- `trimmed` now inherits `spikes: drop` from `mean`, and `median` inherits it from `trimmed`.
  `(from mean)` names the universe that wrote the key, two steps up the chain, not the parent;
  `cut: p10` comes from `trimmed`, which writes it.
- All three `clean` results select `spikes: drop`: one computation in three results.
- With `centre: mean`, `summary` takes `plain` in `median` as in `mean`, and `plain#median` has
  the same command and options as `plain#mean`; its `clean` read is the same computation as
  `plain#mean`'s, so the two are one computation too (`src/astra/plan.py:583-588`). Two notes,
  five results.
- From the clean file, `median` inherits `spikes: keep`, and `mean` requires `spikes.drop`.
  `centre` is in play in `median`, which uses it. The breach is reported at `median`'s own key
  `centre` (80:17): the option that carries the constraint is the one the universe sets itself.
  `astra plan` exits 1 with the report, and `astra plan --json` prints the report's JSON,
  `astra-validation-report/1`, not a plan: a consumer checks `shape`. `astra universe show`
  still prints the selection.

</details>

**2. Add an option that excludes another, and select both.** Give `centre` an option
`winsorised` that is `incompatible_with` `spikes.drop`, and a universe that derives from `mean`
and selects it:

```console
$ perl -pi -e 's/^      trimmed: \{\}\n/$&      winsorised:\n        incompatible_with: [spikes.drop]\n/' astra.yaml
$ printf '  winsorised:\n    derived_from: mean\n    decisions: {centre: winsorised}\n' >> astra.yaml
```

Which code, and at which line and column? Then have `comparison` read `summary#winsorised` as
well: what now? Last, from a clean file, put the constraint on the other side, on `spikes.drop`,
with `incompatible_with: [centre.winsorised]`, and add the same universe and the same read:
where is the breach reported?

<details><summary>Answer</summary>

```console
$ astra plan
astra.yaml
  85:17 error UNUSED_DECISION `winsorised` sets `centre`, which no branch of this analysis uses in `winsorised`: nothing it can plan there, whatever case each switch takes, lists or switches on it, nor in a universe that inherits the key. Remove the key
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ astra universe show winsorised
winsorised  derived from mean
  spikes: drop  (from mean)
  centre: winsorised
$ perl -pi -e 's/summary#median\]/summary#median, summary#winsorised]/' astra.yaml
$ astra plan
astra.yaml
  68:61 error PIN_NOT_BUILT `summary#winsorised` pins `summary` to `winsorised`, where it isn't built: `summary` has no case in `winsorised` for `winsorised`, the option its decision selects there. Pin a universe where it is built
  85:17 error INCOMPATIBLE_OPTIONS `winsorised` selects `centre: winsorised`, which is incompatible with `spikes.drop`, selected too
astra.yaml: invalid, 2 error(s), 0 warning(s)
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/^      trimmed: \{\}\n/$&      winsorised: {}\n/; s/^        description: Drop every.*\n/$&        incompatible_with: [centre.winsorised]\n/' astra.yaml
$ printf '  winsorised:\n    derived_from: mean\n    decisions: {centre: winsorised}\n' >> astra.yaml
$ perl -pi -e 's/summary#median\]/summary#median, summary#winsorised]/' astra.yaml
$ astra validate
astra.yaml
  68:61 error PIN_NOT_BUILT `summary#winsorised` pins `summary` to `winsorised`, where it isn't built: `summary` has no case in `winsorised` for `winsorised`, the option its decision selects there. Pin a universe where it is built
  84:19 error INCOMPATIBLE_OPTIONS `winsorised` inherits `spikes: drop` from `mean`, which is incompatible with `centre.winsorised`, selected too
astra.yaml: invalid, 2 error(s), 0 warning(s)
$ astra validate --json | jq -c '.diagnostics[] | {code, at: .location.pointer, key: .location.key, related: [.related[] | [.pointer, .key, .line, .column]]}'
{"code":"PIN_NOT_BUILT","at":"/outputs/comparison/inputs/3","key":null,"related":[]}
{"code":"INCOMPATIBLE_OPTIONS","at":"/universes/winsorised/derived_from","key":null,"related":[["/universes/mean/decisions","spikes",75,17],["/decisions/spikes/options/drop/incompatible_with/0",null,17,29]]}
$ git checkout --quiet astra.yaml
```

- In `winsorised`, the plan reaches only `clean`: `comparison` is built once, and reads
  `summary` pinned to the other three universes. Nothing reached there lists `centre` or
  switches on it, on any branch, so `winsorised`'s own key breaks `UNUSED_DECISION` (85:17,
  `centre` in `{centre: winsorised}`). The constraint isn't judged: `centre` isn't in play in
  `winsorised`, and a constraint never makes a decision used.
- Read as `summary#winsorised`, `summary` is reached in `winsorised`, so `winsorised` uses
  `centre`, and the constraint is judged: `INCOMPATIBLE_OPTIONS`. And `summary` has no case for
  `winsorised`, so it isn't built there. A missing case breaks no rule, but a pin to where
  nothing is built does: `PIN_NOT_BUILT`, at the entry (68:61), naming the switch and the
  option.
- The rule is checked for each selected option against its own constraints
  (`src/astra/rules/universes.py:213`), so it is reported once, on the option that carries
  `incompatible_with`, though the pair is symmetric in meaning.
- First, that option is `centre: winsorised`, which the universe sets itself: reported at its key
  (85:17).
- Second, it is the inherited `spikes: drop`: reported at the universe's `derived_from` (84:19),
  with the key `spikes` where `mean` writes it (75:17) as a related place, and the constraint
  (17:29) as another. The JSON is filtered to the pointer, key, line and column of each. Where a
  rule broken through inheritance is reported is astra-tools' own choice (design §3), made in
  `_at`, `src/astra/rules/universes.py:230`. The text shows only the main place; the JSON has the
  related ones.
- `astra universe show` still answers on the invalid file; `astra plan` doesn't.

</details>

**3. Make a placeholder name nothing.** In `trimmed_mean`'s command, the one with `--cut=`, write
`{inputs.cleaned}` for `{inputs.clean}` (`plain`'s command reads `{inputs.clean}` too):

```console
$ perl -pi -e 's/\{inputs\.clean\}/{inputs.cleaned}/ if /--cut=/' astra.yaml
```

What does `astra plan` do? Then, from a clean file, add `--spikes={decisions.spikes}` to the same
command: `spikes` is a decision of the analysis, so is that a placeholder of `trimmed_mean`? Last,
write `{{inputs.clean}}` for `{inputs.clean}` there: valid? What does the plan's command say?

<details><summary>Answer</summary>

```console
$ astra plan
astra.yaml
  57:16 error UNDECLARED_TEMPLATE_REF `{inputs.cleaned}` isn't a placeholder of this output: it takes `{inputs}`, `{output}`, and `{inputs.<entry>}` and `{decisions.<entry>}` for an entry of its `inputs` or `decisions` as written; `{{` and `}}` are literal braces
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/--cut=\{decisions\.cut\}/$& --spikes={decisions.spikes}/' astra.yaml
$ astra validate
astra.yaml
  57:16 error UNDECLARED_TEMPLATE_REF `{decisions.spikes}` isn't a placeholder of this output: it takes `{inputs}`, `{output}`, and `{inputs.<entry>}` and `{decisions.<entry>}` for an entry of its `inputs` or `decisions` as written; `{{` and `}}` are literal braces
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/\{inputs\.clean\}/{{inputs.clean}}/ if /--cut=/' astra.yaml
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra plan | grep summarise
  command   python3 src/summarise.py --centre=mean results/mean/clean.csv results/mean/plain.json
  command   python3 src/summarise.py --centre=trimmed --cut=p10 {inputs.clean} results/trimmed/trimmed_mean.json
  command   python3 src/summarise.py --centre=median results/median/clean.csv results/median/plain.json
$ git checkout --quiet astra.yaml
```

- A placeholder is checked against the output's own `inputs` and `decisions`, as written
  (`_gives`, `src/astra/rules/recipes.py:57`), not against the analysis's elements. `spikes`
  reaches `trimmed_mean` only through `clean`, and an output's `decisions` lists the decisions it
  is made with directly ([Elements](https://astra-spec.org/0.1/specification/#elements)
  *output*), so `trimmed_mean` doesn't list it and has no `{decisions.spikes}`. Listing it would
  change no result.
- The error is at the command's value (57:16), not at the placeholder; the message names it.
- `{{inputs.clean}}` is a literal `{inputs.clean}`: valid, and the recipe gets the text instead
  of the path to `clean`'s bytes. No rule says a command uses every entry of its `inputs`, so
  the plan is valid and the recipe would fail when run. `plain`'s commands are unchanged.

</details>

**4. Build an output only where an option no universe selects is selected.** Add an output
`quartiles`, and a switch `quartiles_at_p25` that takes it only where `cut` selects `p25`:

```console
$ perl -pi -e 's|^universes:|  quartiles:\n    type: table\n    format: json\n    inputs: [clean]\n    recipe:\n      command: python3 src/quartiles.py {inputs.clean} {output}\n  quartiles_at_p25:\n    switch: cut\n    cases: {p25: quartiles}\n\nuniverses:|' astra.yaml
```

Is the analysis valid? Then put `quartiles_at_p25` behind a switch on `centre`, as the case for
`trimmed`: valid now? What does the plan say about `quartiles`, and what does `astra view` show
for the two switches in `mean` and in `trimmed`? Then give `quartiles_at_p25` its case for `p10`
instead: how many results? Last, add an output `report` that reads the outer switch: where is it
built, and what do the notes say?

<details><summary>Answer</summary>

```console
$ astra validate
astra.yaml
  83:16 error MISSING_DECISION `mean` selects nothing for `cut`, which it uses
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ perl -pi -e 's|^    cases: \{p25: quartiles\}\n|$&  quartiles_if_trimmed:\n    switch: centre\n    cases: {trimmed: quartiles_at_p25}\n|' astra.yaml
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra plan --notes | sed -n '/^note/,$p'
note astra.yaml:71:5 `quartiles` has no planned result: only a case of `quartiles_at_p25` names it, so it is planned only where something planned reads it, and nothing does, so a check of the root never covers it
note `clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
7 planned result(s), and notes, none of them a breach:
  1 output(s) have no planned result
  1 computation(s) repeated across universes, in 2 result(s)
$ astra view mean | grep quartiles
  quartiles    no planned result
  quartiles_at_p25 undetermined
  quartiles_if_trimmed takes nothing
$ astra view trimmed | grep quartiles
  quartiles    no planned result
  quartiles_at_p25 takes nothing
  quartiles_if_trimmed takes quartiles_at_p25
$ perl -pi -e 's/cases: \{p25: quartiles\}/cases: {p10: quartiles}/' astra.yaml
$ astra plan | grep '^quartiles'
quartiles#trimmed
$ astra plan | tail -n 2
8 planned result(s), and notes, none of them a breach (--notes lists them):
  1 computation(s) repeated across universes, in 2 result(s)
$ perl -pi -e 's|^universes:|  report:\n    type: report\n    format: md\n    inputs: [quartiles_if_trimmed]\n    recipe:\n      command: python3 src/report.py {inputs} {output}\n\nuniverses:|' astra.yaml
$ astra plan | grep -e '^report' -e '^quartiles'
quartiles#trimmed
report#trimmed
$ astra plan --notes | sed -n '/^note/,$p'
note astra.yaml:84:5 `report` isn't built in `mean`: `quartiles_if_trimmed` has no case there for `mean`, the option its decision selects
note astra.yaml:84:5 `report` isn't built in `median`: `quartiles_if_trimmed` has no case there for `median`, the option its decision selects
note `clean#trimmed`, `clean#median` are one computation, with the same command, inputs and selected options: a runner can build one and place its bytes at each
9 planned result(s), and notes, none of them a breach:
  2 output(s) aren't built in some universe, where a switch has no case
  1 computation(s) repeated across universes, in 2 result(s)
$ git checkout --quiet astra.yaml
```

- Nothing of the analysis reads `quartiles_at_p25` or names it in a case, so it is a planning
  root, reached in every universe. A switch reached in a universe uses the decision it switches
  on, whatever case it takes, or none (Results *uses*). So `mean` uses `cut` and must set it:
  `MISSING_DECISION`, at `mean`'s `decisions` (83:16). `trimmed` sets `cut`, and `median`
  inherits it.
- Behind `quartiles_if_trimmed`, `quartiles_at_p25` is reached only through the case
  `quartiles_if_trimmed` takes, in `trimmed`: only the case a switch takes is followed. So only
  `trimmed` uses `cut`, and it sets it. The switch on the decision that decides whether the other
  matters is the outer one, the short specification's convention for nesting.
- `quartiles` has no planned result: a case names it, so it is planned only where something
  planned reads it, and in `trimmed`, which selects `p10`, `quartiles_at_p25` takes nothing.
  The `unplanned` note says so (`_unplanned`, `src/astra/plan.py:502`). Its location, 71:5, is
  where the output's value starts, `type:`, one line below `quartiles:`. No `not_built` note:
  that kind is about an output reached where it isn't built, and nothing reaches `quartiles`.
- The view shows each switch in each universe, reached or not. In `trimmed`,
  `quartiles_at_p25` takes nothing. In `mean`, `cut` is unset, so what it would take is
  undetermined (design §4.13 case 6); nothing reaches it there, so nothing uses `cut` there and
  no rule is broken. `quartiles` reads only `clean`, so it is built in every universe, and
  planned in none.
- With its case for `p10`, `quartiles_at_p25` takes `quartiles` in `trimmed`: eight results,
  `quartiles#trimmed` the eighth, and the `unplanned` note is gone.
- `report` reads `quartiles_if_trimmed` without a pin, so it is built per universe, and as a
  planning root it is reached in each. In `mean` and `median`, `quartiles_if_trimmed` has no
  case for the option `centre` selects, so `report` isn't built there: nine results. A missing
  case breaks no rule; the plan's `not_built` notes say where, and which switch and option
  (`_not_built`, `src/astra/plan.py:546`), at `report` (84:5), one for each option.
- `src/quartiles.py` and `src/report.py` don't exist. Nothing notices before a run: the plan
  reads a command only for its placeholders and, for `outside_folder`, for paths that leave the
  folder or pass through a folder holding an `astra.yaml`; it never looks for the file a path
  names.

</details>

## What you now know

- `astra universe show` is the effective selection, `universes.effective_selection` and
  `_derive`, computed for every universe at once, text only and without validating. An
  inherited selection is kept whole, and `(from …)` names the universe that wrote a key.
- A switch takes, in each universe, the case of the option its decision selects, and reading it
  reads that case. A universe uses the decisions its planned results list and the switches
  reached in it switch on. Only its own keys are judged against that: `UNUSED_DECISION` for a
  decision it uses on no branch, `INACTIVE_DECISION` for one it uses only on another branch.
- The plan is `universes.run` (what the root reaches from its planning roots, following only the
  case each switch takes, planned where it is built) and `universes.building`, put in reading
  order by `plan.visit`. An output a case names is planned only where something planned reads
  it. Names, addresses and places come from `universes.places`, and there is no plan of an
  invalid analysis.
- `render_command` fills the placeholders (Elements *placeholders*) verbatim, relative to the
  folder the recipe runs in or absolute. `astra-plan/1` carries the template, read indices, the
  cases each read goes through (`via`), and an option for every decision a result lists.
- The notes are astra-tools' own, never diagnostics. `same_computation` follows computations
  through what results read, and `not_built` says where a missing case leaves an output unbuilt,
  and why.
- `astra view` is the effective selection, which decisions the universe uses, the case each
  switch takes, and the planned results of one universe, beside the document as written.
- A constraint is checked on the option that carries it, for a decision in play. Broken through
  an inherited key, it is reported at the universe's `derived_from`, with the key where it is
  written as a related place (design §3).
