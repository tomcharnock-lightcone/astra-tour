# 4. Building, records and check

astra-tools runs no recipe. This chapter does a runner's job by hand: run one planned result's
command, write its record through astra-tools' runner helpers, commit, check. Then the
examples' small runner, `run.py`, builds the rest, and `astra check` is taken apart: every
status and reason, what it hashes and caches, `--at`, uncommitted changes, and the JSON report.

Step 9 and Try 5 can be left for a second pass: nothing after them depends on them.

## Setup

```console
$ source env.sh
astra: …/astra-tools/.venv/bin/astra (astra, version 0.2.19.dev…)
work:  …/tour/work
$ sh setup/04.sh
work/04/words: 1b7d5fe Count the words and the characters of a poem
$ cd work/04/words && source ../shell.sh
```

- `work/04/words` is a new analysis in a repository of its own, one commit, nothing built. It
  has an input `text` (`data/poem.txt`), a decision `unit` (`words`, `chars`) with a universe
  for each, an output `count` built per universe, an output `summary` built once that reads
  `count#words` and `count#chars` through `{inputs}`, and a finding citing `summary`. Read its
  `astra.yaml` (45 lines) and `src/` first.
- `../record.py` and `../kept.py` are two short scripts on astra-tools' Python modules (steps 3
  and 10).
- `../shell.sh` exports a fixed git author, committer and date, and
  `GIT_CONFIG_GLOBAL=/dev/null`, so that your commits get the chapter's ids. It also defines
  `jq` through `nix shell nixpkgs#jq` if none is on your PATH. It lasts as long as the shell:
  close this shell when you finish the chapter, since a commit made in it elsewhere would get
  the Tour identity and date, and none of your signing configuration.
- run.py's records name the `python3` on PATH by its version, here
  `urn:astra-examples:cpython-3.14`; env.sh makes it the venv's. With another version the setup
  warns, and the ids of the commits that hold run.py's records (step 5 on) differ from the
  chapter's, as does the environment IRI in those records; nothing else does. The README's
  *Before you start* says how to get 3.14.

## 1. Nothing is built yet

The plan says what a runner would build; the check says none of it has a record.

```console
$ astra plan
count#words
  record    .astra/records/words/count.json
  bytes     results/words/count.json
  run in    .
  command   python3 src/count.py words data/poem.txt results/words/count.json
count#chars
  record    .astra/records/chars/count.json
  bytes     results/chars/count.json
  run in    .
  command   python3 src/count.py chars data/poem.txt results/chars/count.json
summary
  record    .astra/records/summary.json
  bytes     results/summary.json
  run in    .
  command   python3 src/summary.py results/words/count.json results/chars/count.json results/summary.json
3 planned result(s)
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  missing  absent
  error MISSING_RECORD no record is at .astra/records/words/count.json: build `count#words`, and record it there
.astra/records/chars/count.json  count#chars  missing  absent
  error MISSING_RECORD no record is at .astra/records/chars/count.json: build `count#chars`, and record it there
.astra/records/summary.json  summary  missing  absent
  error MISSING_RECORD no record is at .astra/records/summary.json: build `summary`, and record it there
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is missing
astra.yaml: 3 place(s) of planned results, 0 unchanged, 0 stale, 3 missing; 3 absent
exit 1
```

What to notice
- The check walks exactly the plan's results, in the plan's order, one line per place
  ([§18](https://astra-spec.org/0.1/specification/#18-results-and-where-they-go)).
- `missing` comes with `absent`, but no `ABSENT_RESULT` line; the last line still counts
  "3 absent".
- The evidence gets the status of what it cites: `missing`, so `STALE_EVIDENCE`. `45:19` is
  the `artifact` value.
- Exit 1: one place or evidence that isn't `unchanged` fails the check.

Under the hood
- `astra check` calls `api.check` (`src/astra/cli/check.py:37`), which validates the stack
  first (`src/astra/api.py:134`, `_read` → `validate.validated`) and passes the bound stack to
  `check.check` (`src/astra/api.py:139`).
- `check.check` takes its results from `plan(stack).results` (`src/astra/check.py:209`), the
  planner `astra plan` uses, so it reads no record the plan doesn't place
  ([§20](https://astra-spec.org/0.1/specification/#20-checking-results): "reads records only
  through planned results").
- `_Checker.place` (`src/astra/check.py:291`) calls `read_record`, which gives None where no
  file is at the place (`src/astra/records.py:134-136`): `MISSING_RECORD`
  (`src/astra/check.py:305-309`). The check layer reports §20's seven codes and no other
  (`src/astra/check.py:60-70`); astra-tools' three own codes are all in the validator layer
  (`src/astra/diagnostics.py:60-90`).
- With no valid record there are no recorded bytes: `_bytes` returns `absent` and no reason
  (`src/astra/check.py:527-528`), as chapter 2's step 8 found for an invalid record. That is
  design §4.13 case 9, astra-tools' policy on when a rule isn't checked: no `STALE_RESULT` or
  `ABSENT_RESULT` for a `missing` result.
- The exit code is `CheckReport.ok` (`src/astra/check.py:139-145`): no validation error, and
  every place and evidence `unchanged`; bytes don't count. The codes are astra-tools' own
  (design §4.12; chapter 1, step 3): 1 is `FAILED` and 2 `USAGE`
  (`src/astra/cli/__init__.py:50-51`); an `--at` that names no commit is a usage error
  (`src/astra/cli/check.py:38-39`).
- The plan's `command` line is `render_command(result, folder)`
  (`src/astra/cli/text/plan.py:39`, `src/astra/plan.py:711`): placeholders filled verbatim, no
  shell quoting, paths relative to the folder the recipe runs in. `{decisions.<entry>}` is the
  option the universe selects: each decision a planned result lists is set where it is built,
  or the file breaks `MISSING_DECISION` and has no plan.

## 2. Run one recipe by hand

A runner runs a recipe only in a checkout of a commit whose only changes are records and
results of runs (`UNCOMMITTED_CHANGES`,
[§21](https://astra-spec.org/0.1/specification/#21-runners)). Ask astra-tools, then run
`count#words`'s command as the plan renders it.

```console
$ git status --short
$ python -c 'from pathlib import Path; from astra.records import uncommitted_changes; print(uncommitted_changes(Path.cwd()))'
()
$ mkdir -p results/words
$ python3 src/count.py words data/poem.txt results/words/count.json
$ cat results/words/count.json
{"count": 28, "unit": "words"}
$ astra check | head -2
.astra/records/words/count.json  count#words  missing  absent
  error MISSING_RECORD no record is at .astra/records/words/count.json: build `count#words`, and record it there
```

`head -2` keeps `count#words`'s lines; the rest is as in step 1.

What to notice
- `()`: nothing stops a run. A runner asks this before each recipe.
- The recipe doesn't make `results/words/`; the runner does (`examples/run.py:196`).
  `{output}` is only a path.
- The bytes are at their default place, and they are still `absent`, the result still
  `missing`: without a record there are no recorded bytes for them to be (§20's table:
  `absent` is "anything else").

Under the hood
- `uncommitted_changes` (`src/astra/records.py:216`) runs `git status --porcelain=v2
  --untracked-files=all --no-renames --ignore-submodules=none` (`src/astra/sources/git.py:167-170`)
  and drops each path that is a record's place, or a default place holding the bytes the valid
  record at that name's place gives (`_run`, `src/astra/records.py:232-249`). It works from
  paths and §18's layout in each folder that holds an `astra.yaml`; it doesn't plan.

## 3. Write its record through the API

`../record.py` is what a runner does once the recipe returns: find the planned result, hash
what it read and made, write a record at each of its places.

```console
$ cat ../record.py
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
$ python ../record.py 'count#words'
changes before: ('results/words/count.json',)
wrote .astra/records/words/count.json
changes after:  ()
$ astra check
.astra/records/words/count.json  count#words  unchanged  present  not committed
.astra/records/chars/count.json  count#chars  missing  absent
  error MISSING_RECORD no record is at .astra/records/chars/count.json: build `count#chars`, and record it there
.astra/records/summary.json  summary  missing  absent
  error MISSING_RECORD no record is at .astra/records/summary.json: build `summary`, and record it there
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is missing
astra.yaml: 3 place(s) of planned results, 1 unchanged, 0 stale, 2 missing; 2 absent
$ git add --all && git commit --quiet --message "Build count#words by hand"
$ git log --oneline
9b54a3c Build count#words by hand
1b7d5fe Count the words and the characters of a poem
$ astra check | head -1
.astra/records/words/count.json  count#words  unchanged  present
```

`head -1` keeps `count#words`'s line.

What to notice
- Before the record, the new bytes are a change that would stop the next recipe. Once a valid
  record gives their hash, they pass, and the record does too.
- `unchanged  present  not committed`: a valid record, nothing it was made from has changed,
  and HEAD doesn't hold it yet. The commit clears `not committed`.
- The record names `1b7d5fe`, the commit the recipe ran from, and is committed in the next
  one, `9b54a3c` ([§19](https://astra-spec.org/0.1/specification/#19-records): "so it is
  committed in a later commit").

Under the hood
- `api.plan()` (`src/astra/api.py:94`) gives `Result`s (`src/astra/plan.py:77`): names, places
  (`name`, `address`, `record`, `bytes`), one `Read` per entry of `inputs`, the options its
  decisions select, the command template, the folder it runs in, and whether it is read
  through a record (`read_only`) or run at a commit (`run_at`).
- `new_record` (`src/astra/records.py:168`) hashes the bytes at the first place, where
  `{output}` put them (`src/astra/records.py:192`), and each entry's file at its path or, for a
  read at a commit, where `got` says the runner put the bytes it got from git
  (`src/astra/records.py:194-199`). It makes one `Record` per place, each with that place's
  address and the same hash (`src/astra/records.py:200-213`). `commit`, `environment` and
  `runner` are taken on trust; `started` and `finished` are optional, and left out here.
- `write_record` (`src/astra/records.py:151`) writes sorted keys, two-space indentation and a
  final newline to a temporary file in the same folder, then `os.replace`s it into place
  (`src/astra/records.py:155-162`).
- `not committed` is `_committed` (`src/astra/check.py:538-556`): the record's bytes against
  HEAD's blob at the same path. It is astra-tools' addition (design §4.7), not a §20 status,
  and the text shows it only for a record that is the result's
  (`src/astra/cli/text/check.py:44-45`).
- `unchanged`: `_then` bound the stack as it is at `1b7d5fe` (`src/astra/check.py:351-397`),
  and `_changes` found nothing different in the working tree (`src/astra/check.py:423-507`).
  Step 8 lists what it compares.
- Only `api.plan` comes from `astra.api`. Its `__all__` (`src/astra/api.py:33-53`) holds
  `validate`, `bind`, `init`, `plan`, `view`, `check`, `history`, `papers`, `quotes` and their
  result and error types, and design §2 makes `astra.api` "the one import path that stays
  stable". The runner's helpers are outside it: record.py imports `new_record`,
  `write_record`, `uncommitted_changes` and `Runner` from `astra.records` and `Repository` from
  `astra.sources.git`; run.py adds `land` from `astra.records`, and `Result` and
  `render_command` from `astra.plan`. That is
  astra-tools' choice, though design §4.8 writes those helpers "for lightcone-cli, and any
  other runner".

## 4. The record against provenance.schema.json

The record is a ProvenanceRecord (§19). Set it beside the schema astra-tools validates it with.

```console
$ cat .astra/records/words/count.json
{
  "address": "count#words",
  "content_hash": "sha256:88f81c6066bf6a4b6df869f0e08ea95f582105b40a7c56f71585cc8a3e9207bb",
  "generated_by": {
    "commit": "1b7d5fe2991af72a597b25dac409f09f2157eef5",
    "environment": {
      "iri": "urn:tour:by-hand"
    },
    "inputs": [
      {
        "content_hash": "sha256:7797676452e0c76c1cfbfbb4f77f33c081ee499ee464df25fadf321868402755",
        "entry": "text",
        "size": 140
      }
    ],
    "runner": {
      "id": "tour/record.py",
      "version": "1"
    }
  },
  "size": 31,
  "spec_version": "0.1.0"
}
$ sha256sum results/words/count.json data/poem.txt
88f81c6066bf6a4b6df869f0e08ea95f582105b40a7c56f71585cc8a3e9207bb  results/words/count.json
7797676452e0c76c1cfbfbb4f77f33c081ee499ee464df25fadf321868402755  data/poem.txt
$ wc -c results/words/count.json data/poem.txt
 31 results/words/count.json
140 data/poem.txt
171 total
$ astra schema show provenance | jq -r '"record: \(.required)", (."$defs" | to_entries[] | "\(.key): \(.value.required) of \(.value.properties | keys)")'
record: ["spec_version","address","content_hash","size","generated_by"]
Environment: ["iri"] of ["iri"]
Generation: ["commit","environment","runner"] of ["commit","environment","finished","inputs","runner","started"]
RecordedInput: ["entry","content_hash","size"] of ["content_hash","entry","size"]
Runner: ["id","version"] of ["id","version"]
$ astra schema show provenance | jq -r '[.additionalProperties, (."$defs"[] | .additionalProperties)] | @text'
[false,false,false,false,false]
$ astra schema show provenance | jq -r '.properties.content_hash.pattern, ."$defs".Generation.properties.commit.pattern'
^sha256:[0-9a-f]{64}$
^([0-9a-f]{40}|[0-9a-f]{64})$
```

The three `jq` filters print, of the schema, each level's `required` and properties, then each
level's `additionalProperties`, then two patterns.

What to notice

| Field | In provenance.schema.json | What `new_record` fills it from |
|---|---|---|
| `spec_version` | top level, required | `records.SPEC_VERSION`, `"0.1.0"` (`src/astra/records.py:37`) |
| `address` | top level, required | the place's address |
| `content_hash`, `size` | top level, required | `digest_file` of the bytes at the first place |
| `generated_by.commit` | `Generation`, required, 40 or 64 hex | the `commit` argument: HEAD when record.py ran |
| `generated_by.inputs[]` | `Generation`, optional; `RecordedInput` needs `entry`, `content_hash`, `size` | one item per entry of the output's `inputs`, `entry` as written |
| `generated_by.environment.iri` | `Environment`, required, an IRI pattern | the `environment` argument |
| `generated_by.runner` | `Runner`, required, `id` and `version` | the `runner` argument |
| `generated_by.started`, `.finished` | `Generation`, optional, UTC to the millisecond | `records.timestamp(datetime)` (`src/astra/records.py:324`), where given |

- Every level is closed (`additionalProperties: false`): a 0.1 record holds these fields and no
  other.
- `sha256sum` and `wc -c` give the record's hashes and sizes: the files' own.
- The keys are sorted by `write_record`, so `size` comes after `generated_by`. The items of
  `inputs` keep the order of the output's `inputs`, though their order carries no meaning
  (§20's `MISSING_RECORD_INPUTS`, and the schema's description of `inputs`; §19 says only that
  items are matched by `entry`).

Under the hood
- `read_record` (`src/astra/records.py:128`) parses with `load.load_json`, Annex A's rules
  (`src/astra/records.py:139`), then `Contract.check_record` (`src/astra/contract.py:98-106`)
  picks the schema by minor version: `provenance` for 0.1, `provenance.open` above (unknown
  fields ignored), and `INVALID_RECORD` below 0.1. A schema error maps to its code through
  `rules.json` (`src/astra/contract.py:116-126`); step 11 shows one, and chapter 2's step 8
  and Try 5 follow each branch.
- `Record.from_json` and `to_json` (`src/astra/records.py:86-125`); `to_json` leaves out
  `inputs`, `started` and `finished` where there are none.
- `astra schema show` prints astra-spec's installed file byte for byte
  (`src/astra/cli/schema.py:28`); astra-tools copies no schema.

## 5. Build the rest with run.py

`examples/run.py` is the loop of steps 2 and 3, driven by a check report.

```console
$ python $TOUR/examples/run.py
count#chars: python3 src/count.py chars data/poem.txt results/chars/count.json
summary: python3 src/summary.py results/words/count.json results/chars/count.json results/summary.json
2 result(s) built
$ astra check
.astra/records/words/count.json  count#words  unchanged  present
.astra/records/chars/count.json  count#chars  unchanged  present  not committed
.astra/records/summary.json  summary  unchanged  present  not committed
astra.yaml
  45:19 unchanged `summary`
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
$ git add --all && git commit --quiet --message "Build the rest with run.py"
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  unchanged  present
.astra/records/chars/count.json  count#chars  unchanged  present
.astra/records/summary.json  summary  unchanged  present
astra.yaml
  45:19 unchanged `summary`
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
exit 0
$ python $TOUR/examples/run.py
nothing to build: every result is unchanged
$ cat .astra/records/summary.json
{
  "address": "summary",
  "content_hash": "sha256:d999ceb7c7664faa484b11d3e3c7f85c48978bc3466847c2e1b13166cba6a5ea",
  "generated_by": {
    "commit": "9b54a3ca164b4a530773c345795ca9a96d17df9a",
    "environment": {
      "iri": "urn:astra-examples:cpython-3.14"
    },
    "inputs": [
      {
        "content_hash": "sha256:88f81c6066bf6a4b6df869f0e08ea95f582105b40a7c56f71585cc8a3e9207bb",
        "entry": "count#words",
        "size": 31
      },
      {
        "content_hash": "sha256:62779f6190ce9069189ce7f0a59071ca367daeb72aea122d1e115b4fac30be60",
        "entry": "count#chars",
        "size": 32
      }
    ],
    "runner": {
      "id": "astra-examples/run.py",
      "version": "0.3"
    }
  },
  "size": 53,
  "spec_version": "0.1.0"
}
```

What to notice
- run.py skips `count#words`, `unchanged` and `present`, and builds the others in the plan's
  order.
- `summary`'s record names `9b54a3c`, the commit holding record.py's record. Its inputs are
  keyed by the entries as written (`count#words`), and give the hashes of the bytes it read.
- The environment is run.py's own IRI. astra-tools checks only its form (the schema's
  pattern); `UNRECREATABLE_ENVIRONMENT` binds the runner. No environment scheme is registered,
  so the report's `environment` lists are empty (step 6).

Under the hood (`examples/run.py`)
- One `api.check(folder)` at the start (`examples/run.py:107`); an analysis that breaks a MUST
  is refused (`examples/run.py:108`).
- A result is skipped when every place is `unchanged` and `present`, it reads nothing built in
  this run, and `--rebuild` doesn't name it (`examples/run.py:117-121`). A result read through
  its record at a commit is never built (`examples/run.py:115`, `REBUILT_FROM_COMMIT`).
- Before each recipe, `uncommitted_changes` (`examples/run.py:123-126`). Then
  `render_command(result, cwd, got=got)`, run with `shell=True` in the analysis's folder
  (`examples/run.py:199-202`, `WRONG_WORKING_DIRECTORY`), then `new_record(…,
  commit=repo.head(), environment=…, runner=RUNNER)` and `write_record` at each place
  (`examples/run.py:213-216`).

## 6. The report as JSON

`--json` gives `astra-check-report/1`, the shape a runner or any other tool reads.

```console
$ astra check --json | jq -c '{shape, root, at, errors, results: (.results | length), evidence: (.evidence | length)}'
{"shape":"astra-check-report/1","root":"astra.yaml","at":"worktree","errors":[],"results":3,"evidence":1}
$ astra check --json | jq '.results[0]'
{
  "names": [
    "count"
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
    "id": "count"
  },
  "universe": "words",
  "places": [
    {
      "name": "count",
      "address": "count#words",
      "record": ".astra/records/words/count.json",
      "bytes": "results/words/count.json",
      "record_status": "unchanged",
      "bytes_status": "present",
      "committed": true,
      "reasons": [],
      "environment": []
    }
  ]
}
$ astra check --json | jq -c '.evidence[] | {artifact, cites, record_status, at: .location.pointer}'
{"artifact":"summary","cites":["summary"],"record_status":"unchanged","at":"/findings/short_words/evidence/0/artifact"}
```

The first and last are filtered (the first counts `results` and `evidence`); the second is one
result in full.

What to notice
- From §20: the two statuses per place and the reasons' codes. astra-tools' own (design §4.11):
  the shape's name, `at` (`worktree` or a commit), `owner` and `output` as identities (an
  analysis by folder and commit), `committed`, `environment`, `errors` (the MUSTs the analysis
  breaks), and the messages.
- No record contents: no hash, no commit. A consumer reads the file at `record`.
- A reason is `{code, level, message, location, breaks}`; `breaks` is the parse or schema code
  under `INVALID_RECORD`.

Under the hood
- `CheckReport.to_json` (`src/astra/check.py:147-187`), `SHAPE` (`src/astra/check.py:58`),
  printed with `json.dumps(…, indent=2)` (`src/astra/cli/__init__.py:129-131`). Tests pin the
  shape until astra-spec's conformance suite gives it a JSON Schema (design §4.11).
- `api.check(path, at=, universes=, outputs=)` narrows the results to universes and outputs
  (`src/astra/check.py:210-224`); the CLI doesn't offer that.

## 7. An uncommitted change to an input

The check judges the working tree as it is; the runner refuses it; `--at` doesn't see it.

```console
$ echo "and then it checks the hash." >> data/poem.txt
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  stale  present
  error STALE_RESULT the content of `text`, data/poem.txt, isn't what the recipe read
.astra/records/chars/count.json  count#chars  stale  present
  error STALE_RESULT the content of `text`, data/poem.txt, isn't what the recipe read
.astra/records/summary.json  summary  stale  present
  error STALE_RESULT `count#words`, which it reads, is stale
  error STALE_RESULT `count#chars`, which it reads, is stale
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is stale
astra.yaml: 3 place(s) of planned results, 0 unchanged, 3 stale, 0 missing; 0 absent
exit 1
$ astra check --at HEAD | tail -1
astra.yaml at 9f675ba526aea1cbbd69e5dee7c265e498d70c05: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
$ python $TOUR/examples/run.py; echo "exit $?"
run.py: uncommitted changes: commit or discard them first: data/poem.txt
exit 1
$ git checkout --quiet data/poem.txt
$ astra check | tail -1
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
```

What to notice
- Both counts are stale for the same reason. `summary` is stale through them: nothing of its
  own changed, and nothing it reads is hashed; its reasons are the statuses of the two results
  it reads. The finding follows.
- Putting the bytes back makes every result `unchanged` again, with no rebuild: content
  counts, not the modification time, git's status or history.
- `--at HEAD` reads the commit, where the edit isn't.
- run.py refuses: `data/poem.txt` is neither a record's place nor a default place.

Under the hood
- For an input, `_changes` asks `_content` (`src/astra/check.py:485-496`, `509-519`): what a
  stand-in at the path gives (step 9), else `hashing.digest` of the file in the working tree;
  hash and size are compared with the record's item.
- For a result it reads, `_changes` takes the status already worked out for it (the plan puts
  it first): not `unchanged` gives "is stale" or "has no valid record"
  (`src/astra/check.py:497-504`).
- `--at REV`: `api._read` resolves REV with `git rev-parse --verify REV^{commit}`
  (`src/astra/api.py:194`, `src/astra/sources/git.py:118-124`) and reads everything through a
  `CommitReader` (`src/astra/api.py:197`): one long-lived `git cat-file --batch`, nothing
  checked out (`src/astra/sources/reader.py:170`). Bytes read at a commit are hashed as read,
  and not cached (`src/astra/hashing.py:74`).

## 8. What isn't compared, and a result made again

§20: code and environment are recorded but not compared, and editing a claim changes nothing.
A result made again with other bytes makes what reads it stale.

```console
$ perl -pi -e 's/MIN_LENGTH = 1/MIN_LENGTH = 2/' src/count.py
$ perl -pi -e 's/are short, under five/are short, fewer than five/' astra.yaml
$ git status --short
 M astra.yaml
 M src/count.py
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  unchanged  present
.astra/records/chars/count.json  count#chars  unchanged  present
.astra/records/summary.json  summary  unchanged  present
astra.yaml
  45:19 unchanged `summary`
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
exit 0
$ git commit --quiet --all --message "Count words of two characters or more"
$ python3 src/count.py words data/poem.txt results/words/count.json
$ cat results/words/count.json
{"count": 24, "unit": "words"}
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  unchanged  absent
  warning ABSENT_RESULT the bytes at results/words/count.json aren't the ones its record gives
.astra/records/chars/count.json  count#chars  unchanged  present
.astra/records/summary.json  summary  unchanged  present
astra.yaml
  45:19 unchanged `summary`
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 1 absent
exit 0
$ python ../record.py 'count#words'
changes before: ('results/words/count.json',)
wrote .astra/records/words/count.json
changes after:  ()
$ astra check
.astra/records/words/count.json  count#words  unchanged  present  not committed
.astra/records/chars/count.json  count#chars  unchanged  present
.astra/records/summary.json  summary  stale  present
  error STALE_RESULT `count#words`, which it reads, was made again since, with other bytes than it read
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is stale
astra.yaml: 3 place(s) of planned results, 2 unchanged, 1 stale, 0 missing; 0 absent
$ python $TOUR/examples/run.py
summary: python3 src/summary.py results/words/count.json results/chars/count.json results/summary.json
1 result(s) built
$ git add --all && git commit --quiet --message "Build the words and the summary again"
$ git log --oneline
decaf94 Build the words and the summary again
ece610c Count words of two characters or more
9f675ba Build the rest with run.py
9b54a3c Build count#words by hand
1b7d5fe Count the words and the characters of a poem
$ astra check | tail -1
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
```

What to notice
- After the edits, everything is unchanged and the exit is 0: the code change shows only once
  the recipe runs again and makes other bytes (§20's table, its third row).
- Right after the recipe, before its record: `count#words` is `unchanged absent`. Other bytes
  than the recorded ones are `absent` (§20's table), with `ABSENT_RESULT` as a warning. The
  record is `unchanged`: nothing it is compared on has changed, and code isn't compared.
  `summary` stays unchanged: it is compared through `count#words`' record, and the bytes of a
  result it reads never enter. Exit 0.
- `changes before` lists those bytes: the record still there gives the old ones.
- `count#words` is unchanged: its new record names `ece610c`, and nothing it is compared on
  differs. `summary` is stale: its record noted one hash for `count#words`, whose record now
  gives another.
- run.py builds only `summary`. `count#words`'s uncommitted record and bytes don't stop it.

Under the hood: what `STALE_RESULT` compares, in `_changes` (`src/astra/check.py:423-507`),
against the stack bound at the record's commit, and nothing else:
- the command as declared (`441`), the inputs in their order (`443`), the decisions as a set
  (`448`), the format (`453`);
- the option each decision selects in the result's universe (`455-462`);
- for each switch an entry reads through, its decision, the option selected where it is read
  and the case it takes (`_switched`, `482-484`; none here: chapter 6's Try 1 has one);
- each input's content (`485-496`);
- each result it reads: its status (`502-504`), then its record's hash and size against the
  item recorded (`505-506`). The bytes of a result it reads never enter;
- and, first, whether the record's commit and its output are there at all
  (`src/astra/check.py:325-328`, `366-370`, `380-397`): stale if not (step 11).

The bytes are judged apart, by `_bytes` (`src/astra/check.py:521-536`): the hash and size at
the default place against the record's, `present` if equal, else `absent` with
`ABSENT_RESULT`, "no file" (`533`) or "aren't the ones its record gives" (`535`).

## 9. A stand-in in the input's place (optional)

`STALE_RESULT` compares "the content of its inputs, never what stands in for it".
[§7](https://astra-spec.org/0.1/specification/#7-inputs) defines a stand-in only in general
terms ("such as a large-file tool's pointer"); which ones count is astra-tools' choice
(design §4.5): Git LFS pointers, git-annex links and DVC files. It fetches none of them.

```console
$ printf 'version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %s\n' "$(sha256sum < data/poem.txt | cut -c1-64)" "$(wc -c < data/poem.txt)" > ../pointer
$ mv ../pointer data/poem.txt
$ cat data/poem.txt
version https://git-lfs.github.com/spec/v1
oid sha256:7797676452e0c76c1cfbfbb4f77f33c081ee499ee464df25fadf321868402755
size 140
$ sha256sum data/poem.txt
be2e28d7887bfd396ff0208bf79a92de653fbe95e9b0331bcb34b1dc30cd83a3  data/poem.txt
$ astra check | tail -1
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
$ perl -pi -e 's/size 140/size 141/' data/poem.txt
$ astra check | head -2
.astra/records/words/count.json  count#words  stale  present
  error STALE_RESULT the content of `text`, data/poem.txt, isn't what the recipe read
$ git checkout --quiet data/poem.txt
```

What to notice
- The pointer's own hash is `be2e28d7…`; the records hold the poem's, `77976764…`, which the
  pointer gives: unchanged.
- A size alone differing makes it stale: what is compared is hash and size.

Under the hood
- `_content` tries each registered stand-in whose place is the path itself and which
  recognises what is there, and takes the hash and size it gives
  (`src/astra/check.py:515-518`); `GitLfs.gives` parses the pointer
  (`src/astra/sources/standins.py:72-86`). A git-annex link gives them for its `SHA256` and
  `SHA256E` backends (`src/astra/sources/standins.py:102-106`). A DVC file sits beside the
  path, so `_content` passes it by and hashes the file at the path, if there is one.
  `Dvc.gives` gives nothing, since a DVC file holds an MD5
  (`src/astra/sources/standins.py:134-135`), where design §4.5's table says "size". Other
  packages add stand-ins through the entry-point group `astra.standins`
  (`src/astra/sources/standins.py:142-146`).
- A result's bytes get no such reading: `_bytes` hashes whatever is at the default place
  (`src/astra/check.py:529`), so a stand-in there is `absent` (§18).
- `new_record` doesn't look for stand-ins either (`src/astra/records.py:198`). A runner that
  runs a recipe with the pointer in place records the pointer's hash, and the check calls the
  result stale as soon as it is built: the record is true, and the recipe didn't read the
  content.

## 10. How hashes are cached

A check hashes every input and every result's bytes it compares. In the working tree, it does
so once per version of a file.

```console
$ cat ../kept.py
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
$ touch data/poem.txt && astra check > /dev/null && python ../kept.py data/poem.txt
no entry for the file as it is now: a check hashes it
$ sleep 2; astra check > /dev/null; python ../kept.py data/poem.txt
sha256:7797676452e0c76c1cfbfbb4f77f33c081ee499ee464df25fadf321868402755 140 kept: a check takes it, and doesn't read the file
$ sha256sum data/poem.txt
7797676452e0c76c1cfbfbb4f77f33c081ee499ee464df25fadf321868402755  data/poem.txt
```

What to notice
- Right after `touch`, the check hashes the file and keeps nothing. Two seconds later, it keeps
  the hash.
- From then on, checking this file costs a `stat`.

Under the hood
- `digest_file` (`src/astra/hashing.py:43-63`): the key is `st_dev:st_ino` (`47`), the entry a
  file `hashes/<SHA-256 of the key>` in the cache (`src/astra/cache.py:104-105`). A hit needs
  the size and `mtime_ns` kept to be the file's (`51`). Otherwise it hashes in 1 MiB chunks
  (`53-59`), and keeps the result only if the file was last modified at least two seconds
  before hashing began, and its size held (`60-62`, `_RECENT_NS` at `25`): a write in the same
  tick of the file system's clock would leave the time as it was.
- Only working-tree files go through it (`src/astra/hashing.py:72-73`). Entries are written
  atomically (`src/astra/cache.py:61-79`). `astra cache clear` removes the cache's five
  namespaces, `remotes`, `validity`, `hashes`, `worktrees` and `papers`
  (`src/astra/cache.py:21`, `82-101`; chapter 1's step 8 has a table of them). The tour's
  cache, `$TOUR/work/cache`, is shared by every chapter that doesn't move `ASTRA_CACHE_DIR`.
- A file written anew gets a new inode and a new modification time, so it misses: `git
  checkout` unlinks and recreates it, `perl -pi` and `write_record` rename over it. Try 5
  writes in place.

## 11. Missing and stale through the record itself

The check takes the record and git as they are. Break `count#words`'s record four ways,
putting it back each time.

```console
$ r=.astra/records/words/count.json
$ perl -ni -e 'print unless /^  "size"/' $r
$ astra check
.astra/records/words/count.json  count#words  missing  absent
  error INVALID_RECORD (MISSING_FIELD) the document lacks `size`
.astra/records/chars/count.json  count#chars  unchanged  present
.astra/records/summary.json  summary  stale  present
  error STALE_RESULT `count#words`, which it reads, has no valid record
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is stale
astra.yaml: 3 place(s) of planned results, 1 unchanged, 1 stale, 1 missing; 1 absent
$ git checkout --quiet $r
$ perl -pi -e 's/"count#words"/"count#chars"/' $r
$ astra check | head -3
.astra/records/words/count.json  count#words  missing  absent
  error MISPLACED_RECORD the record's address is `count#chars`, where this place is `count#words`'s: a record is the record only of the result it names
.astra/records/chars/count.json  count#chars  unchanged  present
$ perl -ni -e 'print unless /^  "size"/' $r
$ astra check | head -3
.astra/records/words/count.json  count#words  missing  absent
  error INVALID_RECORD (MISSING_FIELD) the document lacks `size`
.astra/records/chars/count.json  count#chars  unchanged  present
$ git checkout --quiet $r
$ perl -pi -e 's/"entry": "text"/"entry": "poem"/' $r
$ astra check | head -3
.astra/records/words/count.json  count#words  missing  absent
  error MISSING_RECORD_INPUTS the record has no item for `text`, which its output lists at ece610cc9f46
  error MISSING_RECORD_INPUTS the record has an item for `poem`, which its output doesn't list at ece610cc9f46
$ git checkout --quiet $r
$ perl -pi -e 's/"commit": "\K\w+/0 x 40/e' $r
$ astra check
.astra/records/words/count.json  count#words  stale  present  not committed
  error STALE_RESULT the record names the commit `0000000000000000000000000000000000000000`, which the repository that holds its analysis hasn't, so what the result was made from can't be compared
.astra/records/chars/count.json  count#chars  unchanged  present
.astra/records/summary.json  summary  stale  present
  error STALE_RESULT `count#words`, which it reads, is stale
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is stale
astra.yaml: 3 place(s) of planned results, 1 unchanged, 2 stale, 0 missing; 0 absent
$ git checkout --quiet $r
$ astra check | tail -1
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
```

`head -3` keeps `count#words`'s lines. The last perl replaces the commit by forty zeros.

What to notice
- Without `size`: `INVALID_RECORD`, the schema code it breaks in parentheses, `missing`. The
  bytes, still there, are `absent` with no `ABSENT_RESULT`. `summary` says "has no valid
  record", not "is stale".
- A wrong `address`: `MISPLACED_RECORD`. With `size` gone too, only `INVALID_RECORD` is
  reported (design §4.13 case 9).
- A renamed entry: `MISSING_RECORD_INPUTS`, both ways, against the output's `inputs` at the
  record's commit, `ece610c`.
- A commit git doesn't have: `stale`, not `missing`. The record is valid; what it was made from
  can't be compared (§20). `not committed` shows again, for a record that is the result's.

Under the hood
- In `_Checker.place` (`src/astra/check.py:291-341`): `INVALID_RECORD` carries each parse or
  schema code as `breaks` (`310-316`); `MISPLACED_RECORD` (`318-323`); `_inputs`
  (`src/astra/check.py:399-421`) matches items to entries by `entry`, in any order, on every
  valid record whose commit can be read, misplaced or not (`330`); `_changes` runs only where
  no reason was found (`331-334`).
- `_bind` asks `git cat-file -t <commit>` (`src/astra/check.py:380`,
  `src/astra/sources/git.py:101-104`) and gives a message in place of a stack
  (`src/astra/check.py:381-386`), which `place` turns into `STALE_RESULT` (`325-328`). The
  stacks bound at records' commits are kept for the check, by repository, commit and folder
  (`src/astra/check.py:359-361`).

## Try

Mark where step 11 leaves you; each answer ends by going back there.

```console
$ git tag built
```

1. **One byte of an input.** `perl -pi -e 's/hash;/hash,/' data/poem.txt` changes one byte, and
   keeps the size and both counts. Predict each status and the exit code. Then commit it and
   run run.py: what does `git status --short` show?

<details><summary>Answer</summary>

```console
$ perl -pi -e 's/hash;/hash,/' data/poem.txt
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  stale  present
  error STALE_RESULT the content of `text`, data/poem.txt, isn't what the recipe read
.astra/records/chars/count.json  count#chars  stale  present
  error STALE_RESULT the content of `text`, data/poem.txt, isn't what the recipe read
.astra/records/summary.json  summary  stale  present
  error STALE_RESULT `count#words`, which it reads, is stale
  error STALE_RESULT `count#chars`, which it reads, is stale
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is stale
astra.yaml: 3 place(s) of planned results, 0 unchanged, 3 stale, 0 missing; 0 absent
exit 1
$ git commit --quiet --all --message "A comma, not a semicolon"
$ python $TOUR/examples/run.py
count#words: python3 src/count.py words data/poem.txt results/words/count.json
count#chars: python3 src/count.py chars data/poem.txt results/chars/count.json
summary: python3 src/summary.py results/words/count.json results/chars/count.json results/summary.json
3 result(s) built
$ git status --short
 M .astra/records/chars/count.json
 M .astra/records/summary.json
 M .astra/records/words/count.json
$ astra check | tail -1
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
$ git reset --quiet --hard built && git clean -dfq
```

- Both counts are stale: the hash differs, whatever the size or the counts. `summary` is stale
  through them.
- run.py builds all three. Its one check, at the start (`examples/run.py:107`), found all
  three stale, `summary` through the counts, so none is done (`examples/run.py:117-118`);
  `summary` also reads results built in this run (`examples/run.py:119-121`). run.py doesn't
  check again: once the counts came back with the same bytes and new records, a check would
  call `summary` unchanged (§20), but run.py goes by its first one. That is run.py's policy.
  Try 2 is the case where reading a result built in this run alone decides.
- Every result's bytes come out the same, so only the records change: their `commit`, and for
  the counts the input's hash.

</details>

2. **Delete a result's bytes.** `rm results/chars/count.json`. Predict `count#chars`'s two
   statuses, `summary`'s, the exit code, and what run.py does.

<details><summary>Answer</summary>

```console
$ rm results/chars/count.json
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  unchanged  present
.astra/records/chars/count.json  count#chars  unchanged  absent
  warning ABSENT_RESULT no file is at results/chars/count.json, the result's default place
.astra/records/summary.json  summary  unchanged  present
astra.yaml
  45:19 unchanged `summary`
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 1 absent
exit 0
$ python $TOUR/examples/run.py
run.py: uncommitted changes: commit or discard them first: results/chars/count.json
$ git commit --quiet --all --message "Drop the characters' count"
$ python $TOUR/examples/run.py
count#chars: python3 src/count.py chars data/poem.txt results/chars/count.json
summary: python3 src/summary.py results/words/count.json results/chars/count.json results/summary.json
2 result(s) built
$ git status --short
 M .astra/records/chars/count.json
 M .astra/records/summary.json
?? results/chars/
$ git reset --quiet --hard built && git clean -dfq
```

- `count#chars` is `unchanged absent`, with `ABSENT_RESULT` as a warning (a SHOULD). `summary`
  is unchanged: a result it reads is compared through its record, not its bytes. Exit 0:
  absent bytes fail no check.
- run.py refuses: git reports the deletion, and a default place passes `uncommitted_changes`
  only while it holds the recorded bytes (`src/astra/records.py:242-248`). That is
  astra-tools' reading of "each result's bytes the recorded ones" in `UNCOMMITTED_CHANGES`.
  Once the deletion is committed, run.py builds `count#chars`, which isn't `present`, and
  `summary`, which was `unchanged` and `present` at the start but reads `count#chars`, built in
  this run (`examples/run.py:119-121`): that clause alone decides here.

</details>

3. **Change the recipe's command.** (a) Quote `count`'s command in the YAML:
   `perl -pi -e 's/command: (python3 src\/count.py.*)/command: "$1"/' astra.yaml`. Predict.
   Put it back, then (b) write `{inputs}` for `{inputs.text}`, which renders the same command
   line here: `perl -pi -e 's/\{inputs.text\}/{inputs}/' astra.yaml`. Predict.

<details><summary>Answer</summary>

```console
$ perl -pi -e 's/command: (python3 src\/count.py.*)/command: "$1"/' astra.yaml
$ grep 'command: "' astra.yaml
      command: "python3 src/count.py {decisions.unit} {inputs.text} {output}"
$ astra check | tail -1
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
$ git checkout --quiet astra.yaml
$ perl -pi -e 's/\{inputs.text\}/{inputs}/' astra.yaml
$ astra plan | grep 'command   python3 src/count.py'
  command   python3 src/count.py words data/poem.txt results/words/count.json
  command   python3 src/count.py chars data/poem.txt results/chars/count.json
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  stale  present
  error STALE_RESULT its recipe's command isn't the one it had at ece610cc9f46
.astra/records/chars/count.json  count#chars  stale  present
  error STALE_RESULT its recipe's command isn't the one it had at 9b54a3ca164b
.astra/records/summary.json  summary  stale  present
  error STALE_RESULT `count#words`, which it reads, is stale
  error STALE_RESULT `count#chars`, which it reads, is stale
astra.yaml
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is stale
astra.yaml: 3 place(s) of planned results, 0 unchanged, 3 stale, 0 missing; 0 absent
exit 1
$ git reset --quiet --hard built && git clean -dfq
```

- (a) Unchanged: the comparison is of the string as parsed (`src/astra/check.py:441`), and the
  quotes aren't in it.
- (b) Stale: the rendered command lines are the same, but `STALE_RESULT` compares the command
  as declared, the template. Each count names its own record's commit: `ece610c` for words,
  rebuilt in step 8, and `9b54a3c` for chars.

</details>

4. **Check at an old commit.** With `git log --oneline` (step 8) in front of you, predict
   `astra check --at HEAD~3`, the by-hand build, and `astra check --at HEAD~1`, where
   `MIN_LENGTH` changed and nothing was built yet.

<details><summary>Answer</summary>

```console
$ git log --oneline
decaf94 Build the words and the summary again
ece610c Count words of two characters or more
9f675ba Build the rest with run.py
9b54a3c Build count#words by hand
1b7d5fe Count the words and the characters of a poem
$ astra check --at HEAD~3; echo "exit $?"
.astra/records/words/count.json at 9b54a3ca164b4a530773c345795ca9a96d17df9a  count#words  unchanged  present
.astra/records/chars/count.json at 9b54a3ca164b4a530773c345795ca9a96d17df9a  count#chars  missing  absent
  error MISSING_RECORD no record is at .astra/records/chars/count.json: build `count#chars`, and record it there
.astra/records/summary.json at 9b54a3ca164b4a530773c345795ca9a96d17df9a  summary  missing  absent
  error MISSING_RECORD no record is at .astra/records/summary.json: build `summary`, and record it there
astra.yaml at 9b54a3ca164b4a530773c345795ca9a96d17df9a
  45:19 error STALE_EVIDENCE `summary` cites `summary`, whose record is missing
astra.yaml at 9b54a3ca164b4a530773c345795ca9a96d17df9a: 3 place(s) of planned results, 1 unchanged, 0 stale, 2 missing; 2 absent
exit 1
$ astra check --at HEAD~1; echo "exit $?"
.astra/records/words/count.json at ece610cc9f465caef33771e21eb2ef89ef29cf11  count#words  unchanged  present
.astra/records/chars/count.json at ece610cc9f465caef33771e21eb2ef89ef29cf11  count#chars  unchanged  present
.astra/records/summary.json at ece610cc9f465caef33771e21eb2ef89ef29cf11  summary  unchanged  present
astra.yaml at ece610cc9f465caef33771e21eb2ef89ef29cf11
  45:19 unchanged `summary`
astra.yaml at ece610cc9f465caef33771e21eb2ef89ef29cf11: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
exit 0
```

- `HEAD~3`: the by-hand record and its bytes are there, the others aren't. Every line says
  `at` the commit: records and bytes are read there, not in the working tree.
- `HEAD~1`: everything unchanged, exit 0. At the commit that changed the code, the results made
  before it are unchanged, since code isn't compared; only the rebuild in HEAD, with other
  bytes, shows the change.

</details>

5. **Fool the hash cache** (optional). Make sure the cache holds the poem's hash, then change
   one byte in place, keeping the inode, and put the modification time back:

   ```sh
   sleep 2; astra check > /dev/null; python ../kept.py data/poem.txt
   cp -p data/poem.txt ../poem.before
   printf K | dd of=data/poem.txt bs=1 seek=2 conv=notrunc status=none
   touch -r ../poem.before data/poem.txt
   ```

   Predict `astra check`, `python ../kept.py data/poem.txt` and `git status --short`. Then
   `touch data/poem.txt` and check again.

<details><summary>Answer</summary>

```console
$ sleep 2; astra check > /dev/null; python ../kept.py data/poem.txt
sha256:7797676452e0c76c1cfbfbb4f77f33c081ee499ee464df25fadf321868402755 140 kept: a check takes it, and doesn't read the file
$ cp -p data/poem.txt ../poem.before
$ printf K | dd of=data/poem.txt bs=1 seek=2 conv=notrunc status=none
$ touch -r ../poem.before data/poem.txt
$ head -1 data/poem.txt
I Keep a record of each run,
$ astra check; echo "exit $?"
.astra/records/words/count.json  count#words  unchanged  present
.astra/records/chars/count.json  count#chars  unchanged  present
.astra/records/summary.json  summary  unchanged  present
astra.yaml
  45:19 unchanged `summary`
astra.yaml: 3 place(s) of planned results, 3 unchanged, 0 stale, 0 missing; 0 absent
exit 0
$ python ../kept.py data/poem.txt
sha256:7797676452e0c76c1cfbfbb4f77f33c081ee499ee464df25fadf321868402755 140 kept: a check takes it, and doesn't read the file
$ git status --short
 M data/poem.txt
$ touch data/poem.txt
$ astra check | tail -1
astra.yaml: 3 place(s) of planned results, 0 unchanged, 3 stale, 0 missing; 0 absent
$ git reset --quiet --hard built && git clean -dfq && rm ../poem.before
```

- The check says unchanged: same device and inode, same size, same `mtime_ns`, so
  `digest_file` takes the kept hash and never reads the file (`src/astra/hashing.py:48-52`).
- git says modified: its index compares the change time too, which `touch -r` can't put back.
  hashing.py compares size and modification time only.
- `touch` gives a new modification time: a miss, a fresh hash, stale. `astra cache clear` would
  do the same, for every chapter's cache.

</details>

## What you now know

- astra-tools gives a runner its pieces and runs nothing: the plan's `Result` and
  `render_command`, `uncommitted_changes` before each recipe, `new_record` and `write_record`
  after it, and `api.check` to decide what to build. Only `plan` and `check` are in the stable
  `astra.api`; the helpers come from `astra.records` and `astra.plan`. Running, getting bytes
  at a commit and naming the environment are the runner's.
- A record holds what the commit can't give: the hashes and sizes of what was read and made,
  the commit, the environment and the runner. A check binds the stack at the record's commit
  and compares the declaration, the selections, the inputs' content and the records of what it
  reads: never code, claims, the bytes of a result it reads, or a stand-in's own hash.
- `missing` is no valid record at the place (four codes), and then the bytes are `absent` with
  no `ABSENT_RESULT`. `stale` is a valid record with something changed, or with nothing to
  compare against. `absent` bytes alone fail nothing.
- A check reads the working tree, uncommitted changes and all, and adds astra-tools'
  `not committed`; `--at REV` reads a commit through `git cat-file`, records and bytes
  included.
- Working-tree hashes are cached by device and inode, trusted while size and modification time
  match, and not kept for a file modified in the last two seconds.
- `astra-check-report/1` holds statuses and reasons, not records. Exit 0 when everything is
  `unchanged`, 1 when not or when the analysis breaks a MUST, 2 for a usage error or an
  analysis that can't be read: astra-tools' own codes, like the shape (design §4.11, §4.12).
