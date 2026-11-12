# 6. astra-tools from Python, and a map of the code

The validator, plan, view and checker through `astra.api`, in one Python session over line-fit.
Then the JSON shapes, a diagnostic traced to the line that reports it, the extension points, the
code's constraints and open questions, and the tests. Chapter 1's step 7 has the layer table.

## Setup

```console
$ source env.sh
astra: …/astra-tools/.venv/bin/astra (astra, version 0.2.19.dev…)
work:  …/tour/work
$ ASTRA_TOOLS=$(python -c 'import astra.api as a, pathlib; print(pathlib.Path(a.__file__).parents[2])')
$ sh setup/06.sh
1. noisy-line is built and committed
  noisy-line c94c7b063ef9 Generate noisy points around a line
  noisy-line 2c5197a98df7 Build the points
2. line-fit declares noisy-line at that commit, and is built and committed
  line-fit 81d441927eea Fit noisy-line's points by least squares and by the Huber loss
  line-fit b137cfed5275 Build the fits and their comparison
3. noisy-line draws twice as many points, and is built again
  noisy-line 228881854072 Draw 60 points
  noisy-line 18cfe9d5695d Build the points again
4. line-fit declares noisy-line's new commit, and is built again
  line-fit d2076b7db726 Read noisy-line's 60 points
  line-fit 7631b7b9da97 Build the fits and their comparison again
5. the Huber option's setting changes, and what it changes is built again
  line-fit eb6f8b9be6a6 Huber: turn linear from 1.0 robust standard deviations
  line-fit 1fd25e98b790 Build the Huber fit and the comparison again
6. the Huber option's setting changes back, and what it changes is built again
  line-fit 03c7a9dd58fe Huber: back to 1.345 robust standard deviations, the usual choice
  line-fit 7b0f45b9aee1 Build the Huber fit and the comparison at 1.345
7. noisy-line pushes twice as many points above the line, and is built again
  noisy-line 3732bd7f8be4 Push 6 points above the line, not 3
  noisy-line 2dcf20f515e3 Build the points with 6 outliers
8. line-fit declares noisy-line's newest commit, and is built again
  line-fit f9662d2fec04 Read noisy-line's points with 6 outliers
  line-fit c232c1ae172e Build the fits and their comparison with 6 outliers
$ cd work/06/build/line-fit
```

- `ASTRA_TOOLS` is the astra-tools checkout whose `src/astra` the `python` on PATH imports
  (`repos/astra-tools`, which `bootstrap.sh` made): the folder that holds `src/astra/api.py`.
  Steps 7, 9 and 10 grep it and run its tests, read only.
- The whole chapter assumes that checkout at `bf5650f` (the head of its `v0.1-rebuild`), its
  venv built with astra-spec installed from `../astra-spec-pinned` at the commit in its
  `astra-spec.pin` (`31a1a8b`, the short specification with switches), as its CLAUDE.md's
  *Development* says and `bootstrap.sh` does.
- The ids hold only where `python3 --version` prints 3.14 after `source env.sh`: run.py's
  records name the `python3` on PATH (`urn:astra-examples:cpython-3.14`). On another version,
  every id from noisy-line's `Build the points` on differs (the setup warns), and so do the
  `cpython-3.14` lines of steps 5 and 8 and of Try 5. The README's *Before you start* says how
  to get 3.14.
- line-fit's ids differ from the examples README's: line-fit names noisy-line by a `file://`
  URL, here under `work/06`. So they match the chapter's only with the tour at this path,
  `/home/r/Projects/LightconeResearch/astra-tour`, which `…/tour` stands for in the output.
- The setup also writes `work/06/plugin`, used in step 8.
- Steps 1 to 5 are one Python session. If you leave it, start again from step 1's imports.

## 1. The public surface

`astra.api` is the one import path that stays stable (design §2). Start with what it exports.

```console
$ python -q
>>> from astra import api
>>> api.__all__
['Bound', 'CheckReport', 'History', 'InvalidAnalysisError', 'NoAnalysisError', 'NotInHistoryError', 'Plan', 'RequestError', 'UniverseView', 'ValidationReport', 'bind', 'check', 'history', 'init', 'papers', 'plan', 'quotes', 'validate', 'view']
>>> import astra
>>> astra.__file__ is None, len(astra.__path__)
(True, 3)
>>> import inspect
>>> for name in ("validate", "bind", "plan", "view", "check", "history", "init"):
...     print(name, inspect.signature(getattr(api, name)))
...
validate (path: 'str | os.PathLike[str] | None' = None, *, offline: 'bool' = False) -> 'ValidationReport'
bind (path: 'str | os.PathLike[str] | None' = None) -> 'Bound'
plan (path: 'str | os.PathLike[str] | None' = None, *, universes: 'Iterable[str] | None' = None, outputs: 'Iterable[str] | None' = None) -> 'Plan'
view (universe: 'str', path: 'str | os.PathLike[str] | None' = None) -> 'UniverseView'
check (path: 'str | os.PathLike[str] | None' = None, *, at: 'str | None' = None, universes: 'Iterable[str] | None' = None, outputs: 'Iterable[str] | None' = None) -> 'CheckReport'
history (path: 'str | os.PathLike[str] | None' = None) -> 'History'
init (path: 'str | os.PathLike[str] | None' = None) -> 'tuple[Path, bool]'
```

What to notice:

- Seven functions, and `papers` and `quotes` with the `[evidence]` extra. None runs a recipe:
  a runner's helpers (`new_record`, `uncommitted_changes`, `land`) are in `astra.records`,
  outside `api`.
- Each takes the analysis's folder, the current one by default. Nothing is searched for: this
  session runs in line-fit's folder, so `api.validate()` is line-fit.
- `view` takes the universe first. The filters are keyword-only. `universes` and `outputs`
  exist only here: `astra plan` takes no filters (design §4.6), and `astra check` has only
  `--at`, which is `at` (`src/astra/cli/check.py:15`), and `--json` (`:21`).
- The exceptions are part of the surface: `NoAnalysisError` (no `astra.yaml` there),
  `InvalidAnalysisError` (a `MUST` broken, so no plan, view or history), `RequestError` (a
  universe, output or revision that isn't there), `NotInHistoryError`. `GitError` and
  `CacheError` aren't re-exported: they are in `astra.sources.git` and `astra.cache`.
- `astra` has no `__file__`: it is a namespace package of three portions, astra-tools'
  `src/astra`, astra-spec's `src/astra` (which holds `astra.schema`), and
  `site-packages/astra/docs/llms.txt`, which astra-spec's wheel installs and `astra guide` prints.

Under the hood:

- `_root` (`src/astra/api.py:245`) turns the folder into a reader and a root: one
  `Repository.discover` (`git rev-parse --show-toplevel`), then a `WorktreeReader` on the
  repository's top, with the folder as a path from there. A folder with no `astra.yaml` file, or
  a symlink in its place, is `NoAnalysisError` (`src/astra/api.py:261`).
- `_read` (`src/astra/api.py:186`) puts a `CommitReader` in place of the working tree for `at=`,
  then calls `validate.validated` (`src/astra/api.py:201`), which gives the report and the stack
  together. So every function but `bind` and `init` validates the whole stack first. `plan`,
  `view` and `history` go through `_valid`, which raises `InvalidAnalysisError` on an invalid
  report (`src/astra/api.py:181`).
- The types print as strings: `api.py`, like every module but two docstring-only
  `__init__.py`, has `from __future__ import annotations`.
- `astra guide` reads `files("astra") / "docs" / "llms.txt"` (`src/astra/cli/guide.py:16`).
  `tests/test_layout.py:12` checks that `src/astra/__init__.py` and `src/astra/schema/` don't
  exist: either would hide astra-spec's portion.

## 2. validate and bind: the report and the stack

The validator's report, then the `Stack` it judged, which every later layer is a function of.

```console
>>> report = api.validate()
>>> report
ValidationReport(root='astra.yaml', diagnostics=(), unchecked=())
>>> report.valid
True
>>> bound = api.bind()
>>> stack = bound.stack
>>> stack.root
Identity(folder='', commit=None)
>>> for identity, member in stack.analyses.items():
...     print(f"{identity!s:52} {member.file}  {member.url}")
...
.                                                    astra.yaml  None
. at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206        astra.yaml  file://…/tour/work/06/build/noisy-line
>>> for r in stack.resolutions:
...     print(f"{r.field:9} {r.written:13} {r.element}")
...
inputs    noisy.points  Element(analysis=Identity(folder='', commit='2dcf20f515e3eecf7e2126c182c54dd5f0f8f206'), kind='output', id='points')
decisions method        Element(analysis=Identity(folder='', commit=None), kind='decision', id='method')
inputs    fit#ols       Element(analysis=Identity(folder='', commit=None), kind='output', id='fit')
inputs    fit#huber     Element(analysis=Identity(folder='', commit=None), kind='output', id='fit')
selection method        Element(analysis=Identity(folder='', commit=None), kind='decision', id='method')
selection method        Element(analysis=Identity(folder='', commit=None), kind='decision', id='method')
artifact  comparison    Element(analysis=Identity(folder='', commit=None), kind='output', id='comparison')
inputs    config        Element(analysis=Identity(folder='', commit='2dcf20f515e3eecf7e2126c182c54dd5f0f8f206'), kind='input', id='config')
```

What to notice:

- `ValidationReport` is a frozen dataclass: `root`, `diagnostics`, `unchecked`. `valid` is a
  property: no diagnostic at level `error`. `unchecked` is empty: every validator code of
  rules.json has its check.
- An analysis is known by its `Identity`, a folder and a commit
  ([Elements](https://astra-spec.org/0.1/specification/#elements) *identity*).
  noisy-line, read at its commit, is `. at 2dcf20f…`, its `astra.yaml` being at its
  repository's top. The URL it came from is on its `Member`, not in its identity.
- `stack.resolutions` is every address of every valid file, resolved once, at binding. `field`
  says where it is written (`selection` is a key of a universe's `decisions`, `artifact` an
  evidence's), `element` what it names. noisy-line's own `config` is there too: the stack is the
  whole stack.
- `api.bind()` gives the stack with the parse and schema diagnostics only, and
  `UNSUPPORTED_SPEC_VERSION`, which the contract reports beside them. The validator rules are
  `validate`'s: step 7 shows the difference.

Under the hood:

- `validate.validated` (`src/astra/validate.py:75`): `Catalogue.load()` reads rules.json
  (`:81`), `bind` reads every file and follows every declaration (`:82`), and `rules.check` runs
  the rule modules on a `Context` of the stack (`:94`). Duplicates go through `dict.fromkeys`
  (`:97`), then the diagnostics are sorted, the working tree's files first (`:98`).
- `bind` (`src/astra/stack.py:242`) reads each analysis once by its identity. A remote commit
  comes from the cache's `remotes`: one bare repository per URL, fetched with
  `--filter=blob:none` and kept by a ref (`src/astra/sources/remote.py`, design §4.3; chapter 5
  follows it). On a fresh cache, the first call of this session is the one that fetches
  noisy-line.
- `Identity` is at `src/astra/stack.py:49`, `Member` at `:93`, `Resolution` at `:156`, `Stack`
  at `:185`, each a frozen dataclass. Rules, plan, view and check never re-resolve what a file
  writes: they read `element`. `Stack.element` (`src/astra/stack.py:201`) resolves an address
  afterwards in two places only: one a caller asks for (`plan.root_output`, for `outputs=`,
  `src/astra/plan.py:351`), and a place's name at a record's commit (`src/astra/check.py:365`).

## 3. plan: the planned results and their commands

What a runner gets: each result after what it reads, with its places, reads and template.

```console
>>> plan = api.plan()
>>> len(plan.results), plan.notes
(4, ())
>>> for result in plan.results:
...     reads = [(read.entry, read.commit and read.commit[:7]) for read in result.inputs]
...     print(result.places[0].address, result.read_only, result.decisions, reads)
...
points True {} [('config', '2dcf20f')]
fit#ols False {'method': 'ols'} [('noisy.points', '2dcf20f')]
fit#huber False {'method': 'huber'} [('noisy.points', '2dcf20f')]
comparison False {} [('fit#ols', None), ('fit#huber', None)]
>>> fit = plan.results[1]
>>> fit.places
(Place(name='fit', address='fit#ols', record='.astra/records/ols/fit.json', bytes='results/ols/fit.json'),)
>>> from astra.plan import render_command
>>> render_command(fit, ".")
'python3 src/fit.py ols 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206:results/points.csv results/ols/fit.json'
>>> render_command(fit, ".", got={"noisy.points": "/tmp/points.csv"}, absolute=True)
'python3 src/fit.py ols /tmp/points.csv …/tour/work/06/build/line-fit/results/ols/fit.json'
>>> [r.places[0].address for r in api.plan(universes=["huber"]).results]
['points', 'fit#huber']
>>> [r.places[0].address for r in api.plan(outputs=["comparison"]).results]
['points', 'fit#ols', 'fit#huber', 'comparison']
>>> try:
...     api.plan(universes=["robust"])
... except api.RequestError as error:
...     print(error)
...
the analysis has no universe `robust`: its universes are ols, huber
```

What to notice:

- `points` comes first, though line-fit never builds it: `read_only` is True, since it belongs
  to noisy-line at the declared commit, read through its record there.
- Each `Read` holds the entry as written, a path and the commit it is read at: `noisy.points`
  reads `results/points.csv` at 2dcf20f, not in line-fit's checkout.
- `decisions` maps each entry of the output's `decisions` to the option its universe selects.
- `command` is the template. `render_command` fills it as the specification says
  ([Elements](https://astra-spec.org/0.1/specification/#elements) *placeholders*), with no shell
  quoting. An entry read at a commit is written `<commit>:<path>` unless `got=` says where the
  runner put its bytes. Paths are relative to `cwd`, the folder the recipe runs in, or absolute.
- `universes=["huber"]` keeps what is built in `huber` and what it reads: `comparison`, built
  once, goes. `outputs=["comparison"]` asks for an output and pulls in what it reads.
- `notes` is empty here. The notes (`fallback_pin`, `two_names`, `unplanned`, `not_built`,
  `same_computation`, `outside_folder`) are astra-tools' own (design §4.6): no code, never an
  error, never an exit code.

Under the hood:

- `plan.plan` (`src/astra/plan.py:187`) gets the planned results from `universes.building`
  (`:210`), given what the root reaches from its own outputs (`_run`, `:209`); `visit` (`:231`)
  then makes each one after what it reads, depth first, and leaves out any whose planning isn't
  determined, which happens only on an invalid stack, for `check`.
- `Result` (`:77`) and `Read` (`:62`) are frozen dataclasses: the API hands out objects, and
  only `to_json` makes dicts.
- `render_command` (`:711`): `{output}` is the first name's default place (`:752`), the
  `<commit>:<path>` form is at `:743`, and `{decisions.<entry>}` at `:758`: the option selected,
  which a valid stack always has for a decision a planned result lists (`MISSING_DECISION`).
- An unknown universe is a `RequestError` from `root_universe` (`:331`).

## 4. view: one universe

The stack as it is in one universe, the bundle a UI asks for.

```console
>>> view = api.view("huber")
>>> for analysis in view.analyses:
...     print(analysis.member.identity, "built" if analysis.built else "not built")
...     for id_, decision in analysis.decisions.items():
...         print("  decision", id_, decision)
...     for id_, output in analysis.outputs.items():
...         print("  output", id_, output.built, output.takes, [place.address for place in output.places])
...
. built
  decision method DecisionView(used=True, selected='huber')
  output fit True None ['fit#huber']
  output comparison True None ['comparison']
. at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 built
  output points True None ['points']
```

What to notice:

- Every analysis of the stack, the root first, with `built` (built in this universe: the root,
  or an analysis the universe drives,
  [Elements](https://astra-spec.org/0.1/specification/#elements) *drives*), each decision's
  `used` (whether the universe uses it, with the root driving:
  [Results](https://astra-spec.org/0.1/specification/#results) *uses*) and `selected`, and each
  output's `built` (Results *built*), `takes` (for a switch, the case it takes here: Elements
  *switch*) and its result's places here.
- `fit` gives `fit#huber`, and `comparison` its one result. Nothing is a switch here, so
  `takes` is `None` throughout, every decision is used and every output built. `None` for
  `used` or `built` would mean undetermined, as for a switch whose decision a universe that
  doesn't reach it leaves unset (design §4.13 case 6).
- `to_json()` adds each file's `fields`, as written (step 6).

Under the hood:

- `view.view` (`src/astra/view.py:101`) takes the universe's effective selection from
  `Context.selections` (`:106`), each decision's option as `min(selection.options(decision))`
  (`:118`) and its use from the root's run (`:119`), what each switch takes from
  `context.meaning` (`:129`), and each output's result from `context.building.planned` (`:130`).
  It reads no analysis file, since binding has read them all; only `rules.json`, through
  `Catalogue.load` (`:104`; chapter 1's step 7 lists the meaning layer's IO).
- Only a valid stack has a view: `api.view` goes through `_valid` (`src/astra/api.py:113`).

## 5. check: the statuses, and the stale results in ten lines

The checker's report is a tree: results, their places, each place's statuses and reasons, then
the evidence.

```console
>>> report = api.check()
>>> report.ok, report.at, len(report.results), len(report.evidence), report.errors
(True, 'worktree', 4, 1, ())
>>> status = report.results[1].statuses[0]
>>> status.place.address, status.record_status, status.bytes_status, status.committed, status.environment
('fit#ols', 'unchanged', 'present', True, ())
>>> status.record.commit, status.record.environment
('f9662d2fec04291fbcc9bbb0ad679126d1b3ecd4', 'urn:astra-examples:cpython-3.14')
>>> status.record.inputs
(RecordedInput(entry='noisy.points', content_hash='sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47', size=1117),)
>>> from pathlib import Path
>>> yaml = Path("astra.yaml")
>>> original = yaml.read_text()
>>> _ = yaml.write_text(original.replace("{method: huber}", "{method: ols}"))
>>> def stale(report):
...     for checked in report.results:
...         for status in checked.statuses:
...             if status.record_status != "unchanged":
...                 yield status.place.address, [reason.message for reason in status.reasons]
...     for evidence in report.evidence:
...         if evidence.record_status != "unchanged":
...             yield evidence.artifact, [reason.message for reason in evidence.reasons]
...
>>> for address, why in stale(api.check()):
...     print(address, why)
...
fit#huber ['`method` selects `ols` in `huber`, where it selected `huber` at f9662d2fec04']
comparison ['`fit#huber`, which it reads, is stale']
comparison ['`comparison` cites `comparison`, whose record is stale']
>>> narrowed = api.check(universes=["ols"])
>>> [c.result.places[0].address for c in narrowed.results], narrowed.ok
(['fit#ols'], False)
>>> _ = yaml.write_text(original)
>>> api.check().ok
True
>>> old = api.check(at="HEAD~1")
>>> old.at
'f9662d2fec04291fbcc9bbb0ad679126d1b3ecd4'
>>> list(stale(old))
[('fit#ols', ['`points`, which it reads through `noisy.points`, was made again since, with other bytes than it read']), ('fit#huber', ['`points`, which it reads through `noisy.points`, was made again since, with other bytes than it read']), ('comparison', ['`fit#ols`, which it reads, is stale', '`fit#huber`, which it reads, is stale']), ('comparison', ['`comparison` cites `comparison`, whose record is stale'])]
>>> [version.commit[:7] for version in api.history().timeline("fit#huber")]
['c232c1a', '7b0f45b', '1fd25e9', '7631b7b', 'b137cfe']
```

What to notice:

- `report.ok` is `astra check`'s verdict: valid, and every place and every evidence `unchanged`.
  Absent bytes don't fail it.
- A `Status` per place: `record_status`, `bytes_status`, `committed` (HEAD has the record at its
  place, byte for byte), `reasons`, the parsed `record`, and `environment`, empty: no scheme is
  registered yet (step 8).
- The record's commit is f9662d2, the commit its recipe ran from, one before c232c1a, the commit
  that holds the record.
- The stale listing walks two collections: each place of each result, then the evidence. A
  `STALE_RESULT` message says what changed since the record's commit (12 characters of it); a
  result that reads a stale one is stale; the finding that cites it gets `STALE_EVIDENCE`
  ([Results](https://astra-spec.org/0.1/specification/#results) *made from*, *Evidence*).
- `universes=["ols"]` keeps only `fit#ols`, which is unchanged, yet `ok` is False: the filters
  narrow the results reported, never the evidence, and the finding cites the stale
  `comparison` (`src/astra/check.py:242`; design §4.7).
- `at="HEAD~1"` checks the analysis as it was at that commit, its records and bytes too.
  `report.at` is then the full commit, not `"worktree"`.
- `api.history()` gives a `History` whose queries read git on demand. `timeline` lists the
  commits that changed `fit#huber`'s record, newest first: five builds.

Under the hood:

- `api.check` (`src/astra/api.py:116`) validates, keeps the errors (`:135`) and calls
  `check.check` (`:139`), even on an invalid stack (step 7).
- `check.check` (`src/astra/check.py:190`) plans the whole stack (`:209`), then gives each place
  its statuses in `_Checker.place` (`:291`): `read_record` (`:301`), then `_then` (`:324`),
  which binds the stack as it was at the record's commit through a `CommitReader` (`:391`), once
  per repository, commit and folder (`:360`).
- `_changes` (`:423`) writes each `STALE_RESULT` message (the selection's at `:460`), and
  `place` attaches the code to them (`:333`). Bytes are hashed by `hashing.digest` (`:529`),
  kept in the cache's `hashes` by device and inode with size and modification time
  (`src/astra/hashing.py:47`), so an unchanged file costs a `stat`.
- `CheckReport.ok` is at `src/astra/check.py:139`; evidence statuses come from
  `_Checker.evidence` (`:558`).

## 6. The four JSON shapes

What agents and astra-typescript read: `to_json()` of each result, and `--json` of each command.

```console
>>> import json
>>> for made in (api.validate(), api.plan(), api.view("ols"), api.check()):
...     document = made.to_json()
...     print(document["shape"], list(document))
...
astra-validation-report/1 ['shape', 'root', 'valid', 'diagnostics', 'unchecked']
astra-plan/1 ['shape', 'root', 'results', 'notes']
astra-universe-view/1 ['shape', 'root', 'universe', 'analyses']
astra-check-report/1 ['shape', 'root', 'at', 'results', 'evidence', 'errors']
>>> place = api.check().to_json()["results"][2]["places"][0]
>>> print(json.dumps(place))
{"name": "fit", "address": "fit#huber", "record": ".astra/records/huber/fit.json", "bytes": "results/huber/fit.json", "record_status": "unchanged", "bytes_status": "present", "committed": true, "reasons": [], "environment": []}
>>> print(json.dumps(api.plan().to_json()["results"][3]["inputs"]))
[{"entry": "fit#ols", "path": "results/ols/fit.json", "commit": null, "result": 1, "via": []}, {"entry": "fit#huber", "path": "results/huber/fit.json", "commit": null, "result": 2, "via": []}]
>>> exit()
$ astra check --json | python -c 'import json, sys; from astra import api; print(json.load(sys.stdin) == api.check().to_json())'
True
$ astra view robust; echo "exit $?"
Usage: astra view [OPTIONS] UNIVERSE [PATH]
Try 'astra view --help' for help.

Error: Invalid value for UNIVERSE: the analysis has no universe `robust`: its universes are ols, huber
exit 2
```

What to notice:

- Four shapes, each named and versioned in its `shape` key. They are astra-tools' own, shared
  with astra-typescript (design §4.11), not the specification's. No JSON Schema of them exists
  yet: astra-spec's `conformance/` has a schema only for its cases' `expected.json`. Their form
  is what `to_json` gives, pinned by astra-tools' tests.
- In `astra-plan/1`, an input's `result` is the index of the result it reads (`1`, `2`), so the
  plan is a graph by index. `via` lists, as written, each case taken on the way to it where the
  entry reads a switch: empty here, where nothing is one (Try 1 makes one).
  `astra-check-report/1` repeats `names`, `owner`, `output` and `universe` for each result
  instead, and puts each place's statuses beside its place's fields.
- `astra check --json` prints the same dict as `api.check().to_json()`.
- The exit codes are the CLI's, not the API's: the API raises `RequestError`, and the command
  makes it a usage error, exit 2.

Under the hood:

- Each `to_json` is a hand-written dict over `dataclasses.asdict` of the small pieces (a place,
  an identity, a reason, a location): `ValidationReport.to_json` (`src/astra/validate.py:43`),
  `Diagnostic.to_json`, which is `asdict(self)` (`src/astra/diagnostics.py:44`),
  `Plan.to_json` (`src/astra/plan.py:125`, with the index at `:128`), `UniverseView.to_json`
  (`src/astra/view.py:62`; `fields` is `member.document.value`, `:80`) and
  `CheckReport.to_json` (`src/astra/check.py:147`).
- `write_json` prints `json.dumps(document, indent=2, ensure_ascii=False)`
  (`src/astra/cli/__init__.py:129`). `cli/view.py` maps `RequestError` to `click.BadParameter`
  (`src/astra/cli/view.py:35`). `FAILED = 1` and `USAGE = 2` are at
  `src/astra/cli/__init__.py:50`; the module's docstring lists which command exits how.

## 7. An invalid analysis, and a diagnostic traced to its code

Break one selection, see what each function does with it, then follow the diagnostic from its
message to the line that reports it.

```console
$ perl -pi -e 's/\{method: huber\}/{method: hubr}/' astra.yaml
$ astra validate; echo "exit $?"
astra.yaml
  44:25 error UNKNOWN_OPTION `method` has no option `hubr`: its options are `ols`, `huber`
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit 1
$ astra plan --json > ../plan.json; echo "exit $?"
exit 1
$ python -c 'import json; d = json.load(open("../plan.json")); print(d["shape"]); print(json.dumps(d["diagnostics"][0]))'
astra-validation-report/1
{"code": "UNKNOWN_OPTION", "level": "error", "message": "`method` has no option `hubr`: its options are `ols`, `huber`", "location": {"file": "astra.yaml", "pointer": "/universes/huber/decisions/method", "line": 44, "column": 25, "key": null, "commit": null, "url": null}, "related": []}
$ python -q
>>> from astra import api
>>> api.bind().diagnostics
()
>>> try:
...     api.plan()
... except api.InvalidAnalysisError as error:
...     print(error)
...     print([d.code for d in error.report.diagnostics])
...
astra.yaml breaks a MUST: `astra validate` says where
['UNKNOWN_OPTION']
>>> broken = api.check()
>>> broken.ok, [d.code for d in broken.errors]
(False, ['UNKNOWN_OPTION'])
>>> [(c.result.places[0].address, c.statuses[0].record_status) for c in broken.results]
[('points', 'unchanged'), ('fit#ols', 'unchanged'), ('fit#huber', 'stale'), ('comparison', 'stale')]
>>> from astra.diagnostics import Catalogue, OWN
>>> catalogue = Catalogue.load()
>>> catalogue.rule("UNKNOWN_OPTION")
Rule(code='UNKNOWN_OPTION', layer='validator', level='MUST', statement="Each option an option reference, selection or key of `cases` names is one of its decision's", source=None, status=None)
>>> catalogue.level("UNKNOWN_OPTION"), catalogue.level("COMMIT_NOT_ANCESTOR")
('error', 'warning')
>>> list(OWN)
['UNSUPPORTED_SPEC_VERSION', 'REMOTE_UNREACHABLE', 'COMMIT_NOT_ANCESTOR']
>>> catalogue.version, len(catalogue.rules), len(catalogue.errors)
('ASTRA rule catalogue, schema version dev', 64, 296)
>>> exit()
$ astra rules UNKNOWN_OPTION
UNKNOWN_OPTION
validator, MUST
Each option an option reference, selection or key of `cases` names is one of its decision's
$ git checkout --quiet astra.yaml
$ cd "$ASTRA_TOOLS"
$ git grep -n '"UNKNOWN_OPTION"' -- src/astra
src/astra/rules/decisions.py:19:CODES = frozenset({"UNKNOWN_OPTION"})
src/astra/rules/decisions.py:49:        yield context.diagnostic("UNKNOWN_OPTION", message, location)
$ git grep -n 'has no option' -- src/astra
src/astra/rules/decisions.py:43:                f"`{owner.id}` switches on `{decision.address}`, which has no option `{option}` "
src/astra/rules/decisions.py:47:            message = f"`{resolution.address}` has no option `{option}`: its options are {listed}"
$ git grep -n '"STALE_RESULT"' -- src/astra
src/astra/check.py:66:        "STALE_RESULT",
src/astra/check.py:327:                    reasons.append(self.reason("STALE_RESULT", then, at))
src/astra/check.py:333:                    reasons.extend(self.reason("STALE_RESULT", change, at) for change in changes)
$ git grep -n 'where it selected' -- src/astra
src/astra/check.py:673:                f"`{step.universe.id}`, where it selected `{before.option}` at {commit}"
$ git grep -n 'selects {' -- src/astra
src/astra/check.py:460:                    f"`{written}` selects {_option(option)} in `{result.universe.id}`, where it "
$ cd "$TOUR/work/06/build/line-fit"
```

What to notice:

- `astra plan --json` on an invalid analysis prints an `astra-validation-report/1`, not a plan,
  and exits 1. A consumer of `--json` branches on `shape`. `astra view` does the same.
- `api.bind()` reports nothing: `UNKNOWN_OPTION` is a validator rule, and binding reports only
  the parse and schema rules, and `UNSUPPORTED_SPEC_VERSION` (`src/astra/contract.py:95`).
- `api.plan()` raises `InvalidAnalysisError`, which holds the validation report. `api.check()`
  doesn't raise: it holds the errors, and gives statuses only to the results whose planning is
  determined (design §4.13 case 12, astra-tools' policy of when a rule isn't checked). Here
  that is all four: no switch is on `method`, so `hubr` leaves every result's planning
  determined, and `fit#huber` gets statuses: stale, as `hubr` isn't the `huber` its record's
  commit selected. A switch on `method` would be undetermined in `huber`, where the option
  selected names nothing (case 6), and case 12 would then withhold statuses from what reads it
  there (Try 1). `astra check` would exit 1 on the errors even with every status unchanged
  (`CheckReport.ok`).
- The trace: the message gives the code; `Catalogue.rule` gives rules.json's row (layer, level,
  statement), with no section, since the short specification's rules.json gives none
  (`source=None`); the code in quotes, `'"UNKNOWN_OPTION"'`, finds the module's `CODES` and the
  line that reports it, and the module's docstring names its section of the long
  specification, *Decisions and options*. A validator code lives in `rules/<module>.py`, one
  module per section of the long specification (design §4.4), but for
  `NOT_IN_REPOSITORY`, in `validate.py` (`src/astra/validate.py:92`). `contract.py` holds
  `UNSUPPORTED_SPEC_VERSION` and `INVALID_RECORD`, which `check.py` also attaches.
- No rule module states a level: `Catalogue.level` makes a `MUST` an error and a `SHOULD` a
  warning. astra-tools' three own codes are in `OWN`, with `source='astra-tools'`; `astra
  rules` lists them apart.
- A check code is attached in one place (`check.py:327`, `:333`) and its messages written in
  another. The message of step 5, "`method` selects `ols` in `huber`, where it selected
  `huber`", spans an f-string's line break, so `where it selected` finds only another message,
  the one for a switch whose decision selects another option than at the record's commit
  (`check.py:673`); grep a shorter fixed part.
- The catalogue says `schema version dev`: the tour's astra-spec is a development build, not a
  release.

Under the hood:

- `Catalogue.load` (`src/astra/diagnostics.py:105`) reads rules.json from the installed
  `astra.schema`, at every call. `find` (`:122`) falls back on `OWN` (`:60`); `level` is at
  `:139`. `errors` maps each JSON Schema keyword location to its code, for the schema layer
  ([Schema files](https://astra-spec.org/0.1/specification/#schema-files)).
- `rules.MODULES` lists the rule modules (`src/astra/rules/__init__.py:37`) and `rules.CODES`
  unions their `CODES` (`:51`); `validate.unchecked` (`src/astra/validate.py:62`) gives every
  validator code of rules.json that no module declares.
- In `rules/decisions.py`: `CODES` (`src/astra/rules/decisions.py:19`), the message (`:47`; a
  key of a switch's `cases` gets its own, `:42-45`) and `context.diagnostic` (`:49`), which
  takes the level from the catalogue (`src/astra/rules/context.py:30`).
- `astra plan` writes the validation report on `InvalidAnalysisError`
  (`src/astra/cli/plan.py:41`), and `astra view` too (`src/astra/cli/view.py:31`).

## 8. Extension points: environments and stand-ins

Two entry-point groups let another package, lightcone-cli say, add an environment scheme or a
stand-in without astra-tools knowing it (design §4.10). `work/06/plugin` is such a package,
installed nowhere: `PYTHONPATH` makes it visible.

```console
$ cat ../../plugin/tour_plugin-0.1.dist-info/entry_points.txt
[astra.environments]
tour-python = tour_plugin:ENVIRONMENT

[astra.standins]
tour-pointer = tour_plugin:STANDIN
$ PYTHONPATH=$TOUR/work/06/plugin astra check
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
  tour-python: urn:astra-examples:cpython-3.14 can't be recreated
    python3 3.14, its standard library only
.astra/records/ols/fit.json  fit#ols  unchanged  present
  tour-python: urn:astra-examples:cpython-3.14 can't be recreated
    python3 3.14, its standard library only
.astra/records/huber/fit.json  fit#huber  unchanged  present
  tour-python: urn:astra-examples:cpython-3.14 can't be recreated
    python3 3.14, its standard library only
.astra/records/comparison.json  comparison  unchanged  present
  tour-python: urn:astra-examples:cpython-3.14 can't be recreated
    python3 3.14, its standard library only
astra.yaml
  53:19 unchanged `comparison`
astra.yaml: 4 place(s) of planned results, 4 unchanged, 0 stale, 0 missing; 0 absent
$ PYTHONPATH=$TOUR/work/06/plugin astra check --json | python -c 'import json, sys; print(json.load(sys.stdin)["results"][1]["places"][0]["environment"])'
[{'scheme': 'tour-python', 'holds': 'python3 3.14, its standard library only', 'recreatable': False}]
$ PYTHONPATH=$TOUR/work/06/plugin python -c 'from astra.sources import standins; print([s.name for s in standins.registered()])'
['Git LFS', 'git-annex', 'DVC', 'tour pointer']
$ cd ../noisy-line
$ rm config.json
$ astra validate
astra.yaml
  7:11 error MISSING_INPUT_FILE `config.json` names no file, and no stand-in of Git LFS, git-annex, DVC
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ PYTHONPATH=$TOUR/work/06/plugin astra validate
astra.yaml
  7:11 error MISSING_INPUT_FILE `config.json` names no file, and no stand-in of Git LFS, git-annex, DVC, tour pointer
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout --quiet config.json
$ cd ../line-fit
```

Read `work/06/plugin/tour_plugin.py` beside this: 46 lines, two frozen dataclasses and an
instance of each.

What to notice:

- An environment scheme answers, for an IRI it recognises, what the environment holds and
  whether it can be recreated. The answer is a fact beside the statuses: it changes no status,
  no verdict, no exit code. With no scheme registered, `environment` is `[]`: astra-tools has no
  built-in scheme.
- A stand-in says where the tool keeps the stand-in, which is what git tracks for the path
  (`place`, `src/astra/sources/standins.py:40`), whether something there stands in for the
  path, and the hash and size it gives. The built-ins come first; a plug-in
  only adds.
- The entry point names an object, `tour_plugin:ENVIRONMENT`, not a class: astra-tools uses what
  `load()` returns as it is.
- lightcone-cli would plug in the same way, with a table in its `pyproject.toml`:
  `[project.entry-points."astra.environments"]` and a line `lightcone = "<module>:<object>"`.
  Nothing else is wired.

Under the hood:

- `environments.registered` (`src/astra/environments.py:51`) loads every entry point of the
  group `astra.environments` (`:17`); `answers` (`:58`) asks each scheme that recognises the IRI.
  The checker loads them once per check (`src/astra/check.py:280`) and asks once per IRI
  (`:343`). The text is drawn by `src/astra/cli/text/check.py:49`.
- `standins.registered` (`src/astra/sources/standins.py:142`) gives `BUILT_IN` (`:138`), then the
  plug-ins. The validator loads them at each validation (`src/astra/rules/inputs.py:37`): a path
  with no file is fine where a stand-in recognises it (`:94`), the message names them all
  (`:99`), and `git ls-files` is asked about each stand-in's place too (`:52`).
- `_Checker._content` (`src/astra/check.py:509`) asks a stand-in for an input's hash only where
  the stand-in sits at the path itself (`place(path) == path`, `:516`), and then compares what
  it gives, never the stand-in's own bytes. A DVC file sits beside the path (`<path>.dvc`), so
  the checker never asks it: it hashes the file at the path where one is there (`:519`), as in
  a working tree after `dvc pull`, and the result can be `unchanged`. Only where no file is at
  the path (at a commit, or before `dvc pull`) does `_content` give `None` and the result go
  stale (`:487`), and only then because a DVC file gives an MD5, not a SHA-256
  (`src/astra/sources/standins.py:135`). Chapter 5's step 6 runs the stale case, and chapter
  4's step 9 a Git LFS pointer, which sits at the path.
- Both protocols are `typing.Protocol`s (`src/astra/environments.py:21`,
  `src/astra/sources/standins.py:32`): nothing to subclass.

## 9. Reading the code: its constraints, and the open questions

CLAUDE.md's global constraints shape every module. Each is visible from outside.

```console
$ cd ../noisy-line
$ rm -f ../../git.log
$ GIT_TRACE=$TOUR/work/06/git.log astra check
.astra/records/points.json  points  unchanged  present
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
$ sed -n 's/.*trace: built-in: //p' ../../git.log | sort | uniq -c | sort -rn
      2 git cat-file --batch
      1 git rev-parse --show-toplevel
      1 git rev-parse --quiet --verify 'HEAD^{commit}'
      1 git ls-files --stage -z -- ':(literal)config.json' ':(literal)config.json.dvc'
      1 git cat-file -t 3732bd7f8be4fcc70b1582a104224d2a55d14cea
$ cd ../line-fit
$ python -q
>>> import importlib
>>> from pathlib import Path
>>> from astra import api
>>> from astra.diagnostics import Catalogue, OWN
>>> src = Path(api.__file__).parent
>>> names = sorted(".".join(p.relative_to(src.parent).with_suffix("").parts).removesuffix(".__init__") for p in src.rglob("*.py"))
>>> len(names)
67
>>> found = []
>>> for name in names:
...     module = importlib.import_module(name)
...     for key, value in vars(module).items():
...         if not key.startswith("__") and isinstance(value, (dict, list, set, bytearray)):
...             found.append((name, key, type(value).__name__))
...
>>> found
[]
>>> type(OWN).__name__, type(Catalogue.load().rules).__name__
('mappingproxy', 'mappingproxy')
>>> Catalogue.load() is Catalogue.load()
False
>>> exit()
$ cd "$ASTRA_TOOLS"
$ git grep -l subprocess -- src/astra
src/astra/sources/git.py
$ git grep -n -e 'os.replace(' -e '\.rename(' -- src/astra
src/astra/api.py:238:        os.replace(temporary, file)
src/astra/cache.py:71:            os.replace(temporary, path)
src/astra/cache.py:94:                kept.rename(aside / namespace)
src/astra/cli/schema.py:43:            os.replace(temporary, path)
src/astra/records.py:162:        os.replace(temporary, path)
src/astra/records.py:296:        os.replace(source, target)
src/astra/records.py:306:        os.replace(temporary, target)
src/astra/sources/remote.py:68:            made.rename(path)
$ git grep -n -E '\(§[34]' -- src/astra
src/astra/api.py:177:    revision `at`, where it is valid (§4). Raises InvalidAnalysisError where it isn't, and
src/astra/check.py:288:        """`code` broken, at the level its rule's `MUST` or `SHOULD` gives (§4)."""
src/astra/diagnostics.py:6:broken is an error and a `SHOULD` a warning, in every layer (§4).
src/astra/diagnostics.py:140:        """The level of `code`: an error for a `MUST`, a warning for a `SHOULD` (§4)."""
src/astra/diagnostics.py:146:        """A diagnostic for `code`, at the level its rule's `MUST` or `SHOULD` gives (§4)."""
src/astra/reference.py:2:from astra-spec's LinkML sources through linkml-runtime, the extra `[reference]` (§3 *Fields*,
src/astra/rules/context.py:33:        """A diagnostic for `code`, at its rule's level (§4)."""
src/astra/validate.py:1:"""validate(): the validator's report on an analysis (§4, design §4.11).
src/astra/validate.py:40:        """True when no `MUST` is broken: warnings and `unchecked` notwithstanding (§4)."""
$ git grep -n 'OPEN(' -- src/astra; echo "exit $?"
exit 1
$ cd "$TOUR/work/06/build/line-fit"
```

What to notice, and why it matters when reading:

- **git only through its binary.** One check runs six git processes. There is one
  `cat-file --batch` per `CommitReader` (`src/astra/sources/reader.py:187`), each open for as
  long as its reader: one at the record's commit, 3732bd7, bound for the comparison
  (`src/astra/check.py:387`), after `cat-file -t` has asked whether git has it
  (`src/astra/sources/git.py:103`); one at HEAD, for `committed` (`src/astra/check.py:550`).
  `Objects`' docstring and design §4.3 read as one per repository; it is one per reader. The
  `ls-files` asks about `config.json`, and about `config.json.dvc`, the DVC stand-in's place.
  Every git question is a visible command in `sources/git.py`, with git's own configuration and
  authentication, and `GIT_TRACE` (to a file: astra-tools captures git's stderr) shows each one.
- **No module-level mutable state.** No module holds a dict, list or set at its top level (all
  67 imported), dunder names aside: the scan skips them, and `api.__all__` is a list. Constants
  are `MappingProxyType`, `frozenset` or tuples, and `Catalogue.load()` builds a new catalogue
  at each call. No in-process registry or module-level cache exists: the
  plug-ins are read from entry-point metadata at each call (`src/astra/check.py:279`-`280`,
  `src/astra/rules/inputs.py:37`), and the caches live on objects made for one call,
  `Context`'s `cached_property`s (`src/astra/rules/context.py:50`) and `_Checker`'s dicts
  (`src/astra/check.py:281`). So a call's output depends on its arguments, the files, the
  environment (`ASTRA_CACHE_DIR`, git's own configuration) and the distributions installed or
  visible on `PYTHONPATH` (step 8), never on what an earlier call left in memory; several
  processes can share one cache.
- **Atomic writes.** Six `os.replace` sites. Five replace the target by a temporary file
  written beside it: a record, a cache entry, an exported schema, `init`'s `astra.yaml`, and
  `land`'s copy across file systems (`records.py:306`). `land`'s first move (`records.py:296`)
  is itself an atomic rename of the run's file into the main checkout. Folders move by
  `Path.rename`: a new remote store into place, and a namespace set aside before `astra cache
  clear` removes it. A reader racing a runner sees the old record or the new one, never half of
  one.
- **The code's citations follow the long specification.** A bare `§n` in the code is the long
  specification's, at astra-spec's tag `v0.1-long-spec`, not the short one at the commit in
  `astra-spec.pin` (CLAUDE.md's *Design*); `design §n` is the design's. The citations moved
  from astra-spec 6c0ddb4, where §3 was *Conformance* and §4 *Conventions*, to
  `v0.1-long-spec`, past astra-spec's 9e18deb, which puts *Conventions* first: validity and
  levels are §4, *Fields* §3. The design document is the exception: it names the specification
  it was written against (`6c0ddb4`, in its header), so its `§3` for the four roles is right as
  it stands. The tour cites the published specification, the short one, instead, which has no
  numbered sections: validity and levels are in its
  [Rules](https://astra-spec.org/0.1/specification/#rules), and the field reference, which
  *Fields* names, in its [Schema files](https://astra-spec.org/0.1/specification/#schema-files).
- **The open questions.** None. Design §5 lists each question of the specification's meaning
  met in later work, with the reading kept meanwhile and the one place that keeps it, marked
  `# OPEN(<id>)`; the list is empty, so the grep finds no marker (chapter 1's step 7 ran it
  too). The three it held, O2, O16 and O30, were all about conditions, and closed when issue
  #93 took conditions out of the specification; switches took their place (chapter 3).

- **Design §1's seven principles** settle what the code does and doesn't do; read them before
  any module.

Under the hood:

- `_git` (`src/astra/sources/git.py:35`) runs every short git command, in `_environment`
  (`:25`): `GIT_TERMINAL_PROMPT=0`, and `GIT_NO_LAZY_FETCH=1` unless a lazy fetch is wanted
  (chapter 1's Try 4 and chapter 5's step 3 show the difference).
  `Objects` (`:218`) keeps the `cat-file --batch` process (`:225`), and `Objects.tree` (`:251`)
  parses tree objects from its output.
- `cache.put` (`src/astra/cache.py:61`) is the pattern: `mkstemp` in the entry's folder, write,
  `os.replace`, unlink the temporary file if it is still there. `records._move`
  (`src/astra/records.py:290`) tries the rename first and copies only on `EXDEV`;
  `remote._store` (`src/astra/sources/remote.py:58`) makes a bare repository in a temporary
  folder and renames it into place, and the process that loses the race removes its own
  (`:68`).
- Two more constraints have tests: rich is imported only under `cli/text/`, and what importing
  each module pulls in is listed in `tests/test_import_cost.py` (step 10).

## 10. The tests

How the suite is organised, and how to run one test of it.

```console
$ cd "$ASTRA_TOOLS"
$ cat astra-spec.pin
31a1a8b26117f505563b2bc2eeb00db2f3d4aa89
$ python -m pytest -q -p no:cacheprovider --collect-only | sed -n 's/::.*//p' | sort | uniq -c | sort -rn | head -8
    131 tests/test_fixtures.py
    122 tests/test_conformance.py
     80 tests/test_check.py
     73 tests/test_import_cost.py
     55 tests/test_validate.py
     52 tests/test_switches.py
     37 tests/test_plan.py
     36 tests/test_codes.py
$ python -m pytest -q -p no:cacheprovider tests/test_codes.py -k UNKNOWN_OPTION
.                                                                        [100%]
1 passed, 35 deselected in …s
$ python -m pytest -q -p no:cacheprovider -rp tests/test_conformance.py -k option
........                                                                 [100%]
=========================== short test summary info ============================
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[022-unknown-option]
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[030-missing-required-option]
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[031-incompatible-options]
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[032-excluded-option-selected]
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[067-option-without-a-case-builds-nothing]
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[078-case-keyed-by-an-unknown-option]
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[090-case-on-an-excluded-option-uses-statically]
PASSED tests/test_conformance.py::test_a_case_gives_its_verdict[105-switch-decision-selects-an-excluded-option]
8 passed, 114 deselected in …s
$ cd "$TOUR/work/06/build/line-fit"
```

The timings vary, and are elided as `…s`. `-p no:cacheprovider` keeps pytest from writing
`.pytest_cache` in the checkout; `-q` drops the header, which names your paths; `-rp` lists
the tests that passed, by id.

What to notice:

- The oracle is astra-spec (design §1, principle 6, which names its fixtures, examples and
  sections), now through its conformance suite (design §4.11), at the commit in
  `astra-spec.pin`. `test_fixtures.py` runs the suite's documents (parse and schema layers),
  `test_conformance.py` its 121 analysis cases, and one test that some are found.
- `test_codes.py` has one case per validator code, 34: rules.json's 31 and astra-tools' own
  three, and two tests that compare `CASES` and `unchecked` with the catalogue. The modules
  beside it, one per section (`test_decisions.py`, `test_inputs.py`, …), hold each rule's
  breaking and keeping cases in full, and the design §4.13 cases.
- Switches have modules of their own: `test_switches.py` for binding and the validator's rules
  on them, `test_switches_plan.py` for the plan, the view and the check through them. The
  conformance cases from 065 on are about switches and what a universe uses (four of them
  above).
- A test id says what it covers: a code, a conformance case's folder, a module's name.
- `test_import_cost.py` is 73 tests: one per module (67), one that every module is listed,
  three on the light commands (`--help`, completion, `validate --json`) and two on where rich
  and the `[evidence]` extra are imported. `-k 'astra.api'` runs `astra.api`'s.

Under the hood:

- `tests/conftest.py:19`: `SPEC` is the astra-spec that `astra.schema` is installed from, so the
  suite runs against whatever astra-spec the environment has. An autouse fixture gives every
  test a cache of its own (`tests/conftest.py:51`), and `build` (`tests/conftest.py:120`) is a
  runner that writes bytes and records without running a recipe.
- `test_codes.py`: `CASES` (`tests/test_codes.py:72`) maps each code to its section, its root's
  `astra.yaml` and the pointer it is reported at; the module fixture (`:361`) builds one
  repository with a folder per code; `test_every_validator_code_has_a_case` (`:403`) compares
  `CASES` with the catalogue, and the test (`:413`) is parametrised over
  `Catalogue.load().codes("validator")` (`:400`).
- `test_conformance.py`: each case's `files/` is copied, then its `setup.sh` runs, or else one
  commit of every file (`tests/test_conformance.py:45`), with a fixed identity and date, as this
  tour's setups do (`:22`). The test (`:76`) compares `valid`, then each `must_report` entry's
  code, and file and pointer where given (`:63`), then `must_not_report`.
- `test_import_cost.py`: `ALLOWED` (`tests/test_import_cost.py:26`) lists each module with the
  watched packages importing it may pull in; each is imported in a fresh interpreter (`:108`),
  and `test_every_module_is_listed` (`:100`) fails on a module missing from it.

## Try

1. In line-fit, give `method` a third option, `lasso: {}`, and put `fit` behind a switch on
   `method`, `fitted`, whose cases for `ols` and `huber` are both `fit`; make `comparison` read
   `fitted#ols` and `fitted#huber`, in its `inputs` and its command's placeholders. Predict
   `astra check`. Then make `huber` select `hubr`, as in step 7, and predict which places
   `astra check` gives statuses to now.

<details><summary>Answer</summary>

```console
$ perl -0pi -e 's/(    options:\n)/$1      lasso: {}\n/; s/(\n  comparison:\n)/\n  fitted:\n    label: The fitted line, for the methods it is made for\n    switch: method\n    cases: {ols: fit, huber: fit}$1/; s/fit#(ols|huber)/fitted#$1/g' astra.yaml
$ sed -n '/^  fitted:/,/compare.py/p' astra.yaml
  fitted:
    label: The fitted line, for the methods it is made for
    switch: method
    cases: {ols: fit, huber: fit}
  comparison:
    label: Least squares against Huber
    description: Both fitted lines, and how far the Huber line is from the least-squares one.
    type: table
    format: json
    inputs: [fitted#ols, fitted#huber]
    recipe:
      command: python3 src/compare.py {inputs.fitted#ols} {inputs.fitted#huber} {output}
$ astra check
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
.astra/records/ols/fit.json  fit#ols  unchanged  present
.astra/records/huber/fit.json  fit#huber  unchanged  present
.astra/records/comparison.json  comparison  stale  present
  error STALE_RESULT its recipe's command isn't the one it had at f9662d2fec04
  error STALE_RESULT its inputs are [`fitted#ols`, `fitted#huber`], in that order, where they were [`fit#ols`, `fit#huber`] at f9662d2fec04
astra.yaml
  58:19 error STALE_EVIDENCE `comparison` cites `comparison`, whose record is stale
astra.yaml: 4 place(s) of planned results, 3 unchanged, 1 stale, 0 missing; 0 absent
$ perl -pi -e 's/\{method: huber\}/{method: hubr}/' astra.yaml
$ astra check; echo "exit $?"
astra.yaml
  49:25 error UNKNOWN_OPTION `method` has no option `hubr`: its options are `lasso`, `ols`, `huber`
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
.astra/records/ols/fit.json  fit#ols  unchanged  present
astra.yaml: invalid, 1 error(s), so only the results it leaves determined; 2 place(s) of planned results, 2 unchanged, 0 stale, 0 missing; 0 absent
exit 1
$ git checkout --quiet astra.yaml
```

- First, `fit#ols` and `fit#huber` stay unchanged. `fit` is now named by a case, so it is
  planned only where something planned reads it (the short specification's Results
  *plans*): `comparison` reads it through `fitted#ols` and `fitted#huber`, each pin taking
  `fit` in its universe. Their commands, inputs and decisions are what their records hold, and
  a new option isn't among what `STALE_RESULT` compares
  ([Results](https://astra-spec.org/0.1/specification/#results) *made from*). `lasso` has no case,
  and that is no error: where `method` selected it, `fitted` wouldn't be built, nor what reads
  it without a pin (Elements *switch*). No universe selects it.
- `comparison` is stale: its command and its `inputs`, as written, aren't those of its record's
  commit, so two `STALE_RESULT` reasons, and the finding that cites it gets `STALE_EVIDENCE`.
  Rebuilt, it is also made from what it reads through `fitted`: the decision, the option
  selected where the pin reads it, and the case taken (Results *made from*). A later change of
  either option, or of the case it takes, makes it stale again, whatever bytes result.
- With `hubr`, `huber` selects an option that names nothing, so what `fitted` takes there is
  undetermined (design §4.13 case 6; `None` from `Meaning.taken`,
  `src/astra/universes.py:625`), and so is the planning of what is reached only through it:
  `fit#huber`, and `comparison`, which reads it, so `plan._reads` gives `None`
  (`src/astra/plan.py:394`) and `visit` leaves it out.
- Case 12: neither gets statuses, and nor does the evidence, which cites `comparison`
  (`src/astra/check.py:577-578`). The summary line says so, in astra-tools' own words
  (`src/astra/cli/text/check.py:67`). `fit#ols` keeps its: in `ols`, `fitted` takes `fit`.

</details>

2. Write `$TOUR/work/06/absent.py` with the API: for each place whose bytes are absent, print
   its address, its default place and its reasons' codes; then print `ok` or `not ok` from
   `report.ok`, and exit 1 when not ok. Predict its output in line-fit, then again after
   `rm results/huber/fit.json`. Is `comparison` affected?

<details><summary>Answer</summary>

```python
# $TOUR/work/06/absent.py
"""Each place whose bytes are absent, and why; exits 1 where the check fails."""

import sys

from astra import api

report = api.check(sys.argv[1] if len(sys.argv) > 1 else None)
for checked in report.results:
    for status in checked.statuses:
        if status.bytes_status == "absent":
            codes = [reason.code for reason in status.reasons]
            print(status.place.address, status.place.bytes, codes)
print("ok" if report.ok else "not ok")
sys.exit(0 if report.ok else 1)
```

```console
$ python ../../absent.py; echo "exit $?"
ok
exit 0
$ rm results/huber/fit.json
$ python ../../absent.py; echo "exit $?"
fit#huber results/huber/fit.json ['ABSENT_RESULT']
ok
exit 0
$ astra check
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
.astra/records/ols/fit.json  fit#ols  unchanged  present
.astra/records/huber/fit.json  fit#huber  unchanged  absent
  warning ABSENT_RESULT no file is at results/huber/fit.json, the result's default place
.astra/records/comparison.json  comparison  unchanged  present
astra.yaml
  53:19 unchanged `comparison`
astra.yaml: 4 place(s) of planned results, 4 unchanged, 0 stale, 0 missing; 1 absent
$ git checkout --quiet results/huber/fit.json
```

`ABSENT_RESULT` is a `SHOULD`, a warning, and absent bytes don't fail the check: `ok` stays True.
`comparison` stays unchanged: it compares the hash `fit#huber`'s record gives with the one it
recorded, not the file (`src/astra/check.py:505`).

</details>

3. Predict the module that reports each of `RESULT_IN_TWO_PLACES`, `INVALID_SYNTAX`,
   `REMOTE_UNREACHABLE` and `MISPLACED_RECORD`, from its layer and subject alone
   (`astra rules CODE` gives the layer and the rule, and chapter 2's step 6 lists the rule
   modules). Then find them.

<details><summary>Answer</summary>

```console
$ cd "$ASTRA_TOOLS"
$ git grep -n -e '"RESULT_IN_TWO_PLACES"' -e '"INVALID_SYNTAX"' -e '"REMOTE_UNREACHABLE"' -e '"MISPLACED_RECORD"' -- src/astra
src/astra/check.py:64:        "MISPLACED_RECORD",
src/astra/check.py:323:                reasons.append(self.reason("MISPLACED_RECORD", message, at))
src/astra/diagnostics.py:73:                "REMOTE_UNREACHABLE",
src/astra/load.py:30:CODES = frozenset({"INVALID_SYNTAX"})
src/astra/load.py:107:            raise ParseError("INVALID_SYNTAX", message)
src/astra/load.py:112:            raise ParseError("INVALID_SYNTAX", message, line, column)
src/astra/load.py:138:        raise ParseError("INVALID_SYNTAX", message) from None
src/astra/load.py:139:    raise ParseError("INVALID_SYNTAX", message, mark.line + 1, mark.column + 1) from None
src/astra/load.py:160:        raise ParseError("INVALID_SYNTAX", problem, line, column)
src/astra/load.py:169:        raise ParseError("INVALID_SYNTAX", f"a record is UTF-8, and this isn't: {error}") from None
src/astra/load.py:172:        raise ParseError("INVALID_SYNTAX", message, error.lineno, error.colno) from None
src/astra/load.py:180:            raise ParseError("INVALID_SYNTAX", message)
src/astra/load.py:186:    raise ParseError("INVALID_SYNTAX", f"{text} isn't a JSON number")
src/astra/rules/commits.py:40:    {"COMMIT_NOT_FOUND", "COMMIT_NOT_ANCESTOR", "REMOTE_UNREACHABLE", "DECLARED_ANALYSIS_INVALID"}
src/astra/rules/commits.py:77:                yield context.diagnostic("REMOTE_UNREACHABLE", message, at)
src/astra/rules/driving.py:49:        "RESULT_IN_TWO_PLACES",
src/astra/rules/driving.py:302:            yield context.diagnostic("RESULT_IN_TWO_PLACES", message, place, [related])
$ cd "$TOUR/work/06/build/line-fit"
```

- `RESULT_IN_TWO_PLACES` is a rule on driving, so `rules/driving.py`.
- `INVALID_SYNTAX` is the parse layer's, `load.py`, for both kinds of file: it raises
  `ParseError`, which binding (`src/astra/stack.py:305`) and `read_record`
  (`src/astra/records.py:140`) turn into a diagnostic, or a reason of `INVALID_RECORD`.
- `REMOTE_UNREACHABLE` is astra-tools' own (design §3): its rule is in `OWN`, and the module
  of analyses from a commit, `rules/commits.py`, reports it.
- `MISPLACED_RECORD` is a rule of the check layer, so `check.py`, as a `Reason`, not a
  `Diagnostic`.

</details>

4. If `UNKNOWN_OPTION`'s message stopped listing the options in backticks, which test would
   fail? Find it without editing anything, then run that file.

<details><summary>Answer</summary>

```console
$ cd "$ASTRA_TOOLS"
$ git grep -l UNKNOWN_OPTION -- tests
tests/test_codes.py
tests/test_decisions.py
tests/test_plan.py
tests/test_switches.py
tests/test_universes.py
$ git grep -n 'in selection.message' -- tests
tests/test_decisions.py:98:    assert "`a`, `b`" in selection.message
$ python -m pytest -q -p no:cacheprovider tests/test_decisions.py
....                                                                     [100%]
4 passed in …s
$ cd "$TOUR/work/06/build/line-fit"
```

`test_decisions.py`, the test of `rules/decisions.py`, checks a fragment of the message as well
as the pointers, the level, the line and the column. Tests compare codes, places, and fragments
of messages where a message must say something; never a rule's statement, which comes from
rules.json (design §3).

</details>

5. In noisy-line, put a tour pointer in place of `config.json`: its two lines,
   `tour-pointer` and the real file's hash and size. Predict `astra validate` and `astra check`,
   then the check with the plug-in on `PYTHONPATH`.

<details><summary>Answer</summary>

```console
$ cd ../noisy-line
$ printf 'tour-pointer\nsha256:%s %s\n' "$(sha256sum config.json | cut -d' ' -f1)" "$(wc -c < config.json)" > pointer
$ mv pointer config.json
$ cat config.json
tour-pointer
sha256:75c96f73e6c6ec40e5d516d601ef759f54a27dd9819d14a7def9ebb2e853a58d 101
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra check
.astra/records/points.json  points  stale  present
  error STALE_RESULT the content of `config`, config.json, isn't what the recipe read
astra.yaml: 1 place(s) of planned results, 0 unchanged, 1 stale, 0 missing; 0 absent
$ PYTHONPATH=$TOUR/work/06/plugin astra check
.astra/records/points.json  points  unchanged  present
  tour-python: urn:astra-examples:cpython-3.14 can't be recreated
    python3 3.14, its standard library only
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
$ git checkout --quiet config.json
$ git status --short
$ cd ../line-fit
```

- Valid either way: the pointer is a file.
- Without the plug-in, the checker hashes the pointer file itself, whose bytes aren't the
  recorded ones: stale.
- With it, the stand-in at the path gives the content's hash and size, and the checker compares
  those, never the stand-in's own bytes
  ([Results](https://astra-spec.org/0.1/specification/#results) *made from*;
  `src/astra/check.py:515`): unchanged.

</details>

## What you now know

- `astra.api`'s seven functions all take an analysis's folder and hand back frozen dataclasses
  (`History`, a query object, and `init`'s `(path, made)` tuple aside). All but `bind` and
  `init` validate the whole stack first: `plan`, `view` and `history` raise
  `InvalidAnalysisError` on a broken `MUST`; `check` gives statuses to the results whose
  planning is determined, with the errors (design §4.13 case 12).
- A `Stack` (identities, members, every address resolved once) is what rules, plan, view and
  check are functions of; a `CheckReport` is results, places, statuses and reasons, then
  evidence, walkable in a few lines.
- The four JSON shapes are astra-tools' own, made by hand-written `to_json` methods; `--json`
  prints exactly those dicts, and the exit codes belong to the CLI.
- A diagnostic traces as message, code, `Catalogue.rule` (rules.json's row), then
  `git grep '"CODE"'`, and the module's section: validator codes in `rules/<section>.py`
  (`NOT_IN_REPOSITORY` in `validate.py`), check codes in `check.py`, parse in `load.py`, schema
  through `contract.py`'s error map, and `UNSUPPORTED_SPEC_VERSION` in `contract.py` itself.
- Environment schemes and stand-ins plug in through the entry-point groups `astra.environments`
  and `astra.standins`, each an object with a protocol's members; that is how lightcone-cli would
  add its own.
- The code keeps git behind its binary, writes atomically and holds no module-level mutable
  state, though plug-ins are read from the installed distributions at each call; it holds no
  `OPEN(` marker, as design §5 has no open question; its tests take astra-spec's conformance
  suite as the oracle.
