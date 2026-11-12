# 1. A first analysis, and the shape of astra-tools

`astra init` makes an analysis; `validate`, `info` and `plan` read it; a broken byte shows the
`astra-validation-report/1` shape and the exit codes. Then the machinery: commands loaded
lazily, rules and schemas read from astra-spec's `astra.schema`, the pipeline run one layer at a
time in Python, and the cache filled by an analysis from another repository.

## Setup

```console
$ source env.sh
astra: …/astra-tools/.venv/bin/astra (astra, version 0.2.19.dev…)
work:  …/tour/work
$ sh setup/01.sh
work/01 is ready: …/tour/work/01
  upstream 345e144 Spell recipe right
  upstream b26542c Count the words
$ cd work/01
```

- Run it from the tour folder. `…/tour` in every block stands for that folder's absolute path.
- Steps 1 and 3 rely on no git repository above `work/01`. The tour folder is one, and
  `env.sh`'s `GIT_CEILING_DIRECTORIES` keeps git from looking that high.
- `work/01/upstream` is a git repository with a tiny analysis in two commits: the first
  misspells `recipe` as `recipie`, the second fixes it. Step 8 declares it by URL.
- `work/01/loaded.py` runs one `astra` command in-process and lists the modules it imported
  (step 5).
- Steps 2, 4, 6 and 8 use `jq`. If `command -v jq` finds none, run `nix shell 'nixpkgs#jq'`
  first: a shell with jq on PATH that keeps what `env.sh` exported.
- Every command runs in `work/01`, in order. Step 8 moves `ASTRA_CACHE_DIR`; `source env.sh`
  again before the next chapter.

## 1. `astra init`: the file, and the repository it makes

A minimal analysis, and what astra-tools does and doesn't do to git.

```console
$ astra init first
Made first/astra.yaml, in a new git repository.
Check it with: astra validate first
$ cat first/astra.yaml
spec_version: "0.1.0"
outputs:
  result:
    type: metric
    format: json
    recipe:
      command: python src/result.py '{output}'
$ git -C first status --porcelain
?? astra.yaml
$ git -C first rev-parse --git-dir
.git
$ git -C first rev-parse --verify --quiet HEAD; echo "exit code $?"
exit code 1
$ astra init first; echo "exit code $?"
astra: first has an astra.yaml already: give a folder without one
exit code 2
```

What to notice

- The file holds `spec_version`, the one top-level field the schema requires, and one output
  with the fields an output requires: `type`, `format`, and a `recipe` with its `command`
  (`MISSING_FIELD`). `outputs` itself may be empty or left out: an analysis need not make
  anything.
- `src/result.py` doesn't exist, and nothing says so: no validator rule and no plan note
  checks that a recipe's code exists. `CODE_OUTSIDE_ANALYSIS` is a runner `SHOULD`
  ([Rules](https://astra-spec.org/0.1/specification/#rules)). The
  plan's `outside_folder` note covers only part of it, a path that climbs out of the folder or
  enters a nested analysis (Try 2), and never looks at whether the file exists or is tracked.
- `'{output}'` is quoted in the template itself: placeholders are filled verbatim, with no
  shell quoting ([Elements](https://astra-spec.org/0.1/specification/#elements) *placeholders*).
- `git init` and nothing more: `astra.yaml` is untracked and HEAD has no commit. The branch
  name is whatever your git configuration says.
- A second `init` refuses, exit 2, and leaves the file alone.

Under the hood

- `src/astra/cli/init.py:25` calls `api.init` (`src/astra/api.py:213`), which writes the
  constant `MINIMAL` (`src/astra/api.py:201`).
- `src/astra/api.py:226`: `Repository.discover` runs `git rev-parse --show-toplevel`
  (`src/astra/sources/git.py:78`). Only where that finds nothing does `Repository.init` run
  `git init --quiet` (`src/astra/sources/git.py:54`). Inside a working tree, no repository is
  made (Try 2).
- The write is atomic: a temporary file in the same folder, `chmod 0644`, then `os.replace`
  (`src/astra/api.py:229` to `:234`). Every file astra-tools writes goes through a temporary
  file and `os.replace` (CLAUDE.md's *Key Conventions*). `init`, `write_record`
  (`src/astra/records.py:161`) and `astra schema export` (`src/astra/cli/schema.py:42`) set
  0644 before the rename; a cache entry (`cache.put`, `src/astra/cache.py:61`) keeps
  `mkstemp`'s 0600.
- `FileExistsError`, `GitError` and `OSError` become `astra: <message>` and exit 2
  (`src/astra/cli/init.py:26` to `:29`, through `fail` at `src/astra/cli/__init__.py:78`).

## 2. `astra validate`, as text and as `--json`

The validator's report, first empty, then with three errors from two typos.

```console
$ cd first
$ astra validate; echo "exit code $?"
astra.yaml: valid, 0 error(s), 0 warning(s)
exit code 0
$ astra validate --json
{
  "shape": "astra-validation-report/1",
  "root": "astra.yaml",
  "valid": true,
  "diagnostics": [],
  "unchecked": []
}
$ perl -pi -e 's/type: metric/type: metrc/; s/recipe:/recipie:/' astra.yaml
$ astra validate; echo "exit code $?"
astra.yaml
  4:5 error MISSING_FIELD `result` lacks `recipe`
  4:11 error INVALID_VALUE `type` is "metrc", not one of `metric`, `figure`, `table`, `data`, `report`
  6:5 error UNKNOWN_FIELD `recipie` isn't a field here
astra.yaml: invalid, 3 error(s), 0 warning(s)
exit code 1
$ astra validate --json | jq -c '.diagnostics[]'
{"code":"MISSING_FIELD","level":"error","message":"`result` lacks `recipe`","location":{"file":"astra.yaml","pointer":"/outputs/result","line":4,"column":5,"key":null,"commit":null,"url":null},"related":[]}
{"code":"INVALID_VALUE","level":"error","message":"`type` is \"metrc\", not one of `metric`, `figure`, `table`, `data`, `report`","location":{"file":"astra.yaml","pointer":"/outputs/result/type","line":4,"column":11,"key":null,"commit":null,"url":null},"related":[]}
{"code":"UNKNOWN_FIELD","level":"error","message":"`recipie` isn't a field here","location":{"file":"astra.yaml","pointer":"/outputs/result","line":6,"column":5,"key":"recipie","commit":null,"url":null},"related":[]}
$ perl -pi -e 's/type: metrc/type: metric/; s/recipie:/recipe:/' astra.yaml
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ cd ..
```

The jq filter prints only `diagnostics`, one per line. The shape, field by field (astra-tools'
own, shared with astra-typescript):

| Field | Holds |
|---|---|
| `shape` | the shape's name; a change of form gets a new name |
| `root` | the root's `astra.yaml`, named as a location's `file` names it |
| `valid` | true when no diagnostic is an `error`; warnings don't count |
| `diagnostics[].code` | a code of `rules.json`, or one of astra-tools' three (step 6) |
| `diagnostics[].level` | `error` for a `MUST`, `warning` for a `SHOULD`, read from the catalogue |
| `diagnostics[].message` | astra-tools' own words; the rule's own are in `astra rules CODE` |
| `location.file` | the file's path from the top of its repository; outside one, from the analysis's folder |
| `location.pointer` | a JSON Pointer into the document; `""` for the whole file |
| `location.line`, `.column` | from 1; `null` where no node is meant (step 3) |
| `location.key` | the map key or field the diagnostic names |
| `location.commit`, `.url` | the commit a file was read at, and the remote it came from (step 8) |
| `diagnostics[].related` | further locations (step 8) |
| `unchecked` | validator codes this build doesn't check: empty while astra-tools declares every validator code of the installed `rules.json`, as now |

What to notice

- Two typos, three errors. `recipie` is an unknown field and leaves `recipe` missing. Both
  subjects are determined, so both are reported, though one edit fixes both.
- `MISSING_FIELD` sits at 4:5, not on line 3 where `result:` is written: a map's position is
  where its content starts. `UNKNOWN_FIELD` points at the object, `/outputs/result`, and names
  the field in `key`; its line and column are the key's own. The code is the one `rules.json`
  gives the failing keyword
  ([Schema files](https://astra-spec.org/0.1/specification/#schema-files)); the place, at the
  object and naming the field, the line, column and message are astra-tools'.
- Diagnostics come sorted by file, line, column, then code. The text groups them by file.
- Exit 1 because `valid` is false. A warning alone would leave exit 0.

Under the hood

- `src/astra/cli/validate.py:26` calls `api.validate`; `:27` prints the report; `:28` and
  `:29` exit 1 when `report.valid` is false (`src/astra/validate.py:38`).
- `ValidationReport.to_json` (`src/astra/validate.py:42`) is the shape. Each diagnostic is
  `dataclasses.asdict` of the frozen `Diagnostic` (`src/astra/diagnostics.py:44`), so the field
  order is the dataclass's. `write_json` uses `json.dumps(indent=2,
  ensure_ascii=False)` (`src/astra/cli/__init__.py:131`).
- The order: `src/astra/validate.py:97`, keyed by `_order` (`src/astra/validate.py:54`): the
  working tree's files first, then each commit's.
- Positions: `Document.position` (`src/astra/load.py:80`) walks ruamel's composed node tree and
  returns the node's start mark plus one (`src/astra/load.py:96`).
- Text: `src/astra/cli/text/validate.py:12`, through `by_file` and `rule_line`
  (`src/astra/cli/text/__init__.py:48` and `:32`). rich colours it on a terminal only, and
  never under `NO_COLOR`.
- `unchecked` is the catalogue's validator codes minus those `load`, `contract`, `validate` and
  the rule modules declare (`src/astra/validate.py:61`), computed at each run against the
  installed `rules.json`: a device from when most validator rules weren't written yet. An
  astra-spec that adds a validator code makes it non-empty again.

## 3. Exit codes 0, 1 and 2

When each happens, by provoking each. They are astra-tools' own (its `docs/cli.md`, *Conventions*):
the specification says what is valid, not how a tool exits.

```console
$ mkdir empty
$ astra validate empty; echo "exit code $?"
astra: empty has no astra.yaml file: give the folder of an analysis
exit code 2
$ astra validate --strict first; echo "exit code $?"
Usage: astra validate [OPTIONS] [PATH]
Try 'astra validate --help' for help.

Error: No such option '--strict'.
exit code 2
$ mkdir loose && cp first/astra.yaml loose/
$ astra validate loose; echo "exit code $?"
astra.yaml
  error NOT_IN_REPOSITORY the analysis's folder isn't in the working tree of a git repository: make one with `git init`, or move the analysis into one
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit code 1
$ astra info loose; echo "exit code $?"
astra: the analysis's astra.yaml isn't a valid document, or isn't in a git repository, so there is no stack to show: `astra validate loose` says why
exit code 1
$ astra plan loose; echo "exit code $?"
astra.yaml
  error NOT_IN_REPOSITORY the analysis's folder isn't in the working tree of a git repository: make one with `git init`, or move the analysis into one
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit code 1
```

| Exit | When |
|---|---|
| 0 | the command answers: `validate` finds no error, `plan` has a plan, `check` finds every result and evidence `unchanged` |
| 1 | `validate` finds an error; `check` finds a result or evidence that isn't `unchanged`, or a `MUST` broken; `plan`, `view`, `history` and `paper` meet an analysis that breaks a `MUST` (they print the validation report); `history` finds nothing; `info` and `universe` have no stack to show |
| 2 | a usage error (click's, with `Usage:` lines); no analysis in PATH; git, the cache or a file that can't be used; an internal error |

What to notice

- No `astra.yaml` is no analysis: a broken invocation, exit 2 like a usage error, not a
  diagnostic. It goes through `fail`, not click's `UsageError`, so no `Usage:` lines. PATH is
  the analysis's folder, and nothing is searched for, upwards or downwards.
- `NOT_IN_REPOSITORY` has no `line:col`: it is about the folder, not a place in the file
  ([Rules](https://astra-spec.org/0.1/specification/#rules)). The file is
  otherwise the valid scaffold. The parse and schema rules still run, and astra-tools'
  `UNSUPPORTED_SPEC_VERSION`, but no other validator rule is checked and no declaration is
  followed.
- `info` has nothing to show and says which command explains why. `plan` prints the
  validation report in place of a plan; with `--json` it prints `astra-validation-report/1`,
  not `astra-plan/1`, so a consumer dispatches on `shape`.

Under the hood

- `FAILED = 1` and `USAGE = 2`: `src/astra/cli/__init__.py:50` and `:51`.
- `environment()` (`src/astra/cli/__init__.py:85`) turns `NoAnalysisError`, `CacheError`,
  `GitError` and `OSError` into `astra: <message>` and exit 2.
- `api._root` (`src/astra/api.py:241`) raises `NoAnalysisError` where PATH isn't a folder
  (`src/astra/api.py:245`) or holds no `astra.yaml` file (`src/astra/api.py:255` to `:257`);
  a symlink isn't one.
- Any other exception is an internal error, exit 2, with a traceback under `ASTRA_DEBUG`
  (`_Astra.invoke`, `src/astra/cli/__init__.py:64`; Try 5 provokes one).
- `NOT_IN_REPOSITORY` is added in `src/astra/validate.py:83` to `:91`, at a location with no
  line. Binding stops at the root when the reader has no repository
  (`src/astra/stack.py:270`), so `Bound.stack` is `None`, which `read_stack` turns into exit 1
  (`src/astra/cli/__init__.py:100`).
- `src/astra/cli/plan.py:40` to `:42`: `InvalidAnalysisError` prints its validation report
  and exits 1.

## 4. `astra info` and `astra plan` on the scaffold

The stack in brief, and the one result it plans.

```console
$ astra info first
astra.yaml
  outputs   result: metric, json
$ astra plan first
result
  record    .astra/records/result.json
  bytes     results/result.json
  run in    .
  command   python src/result.py 'results/result.json'
1 planned result(s)
$ astra plan first --json | jq -c 'del(.results)'
{"shape":"astra-plan/1","root":"astra.yaml","notes":[]}
$ astra plan first --json | jq -c '.results[0]'
{"names":["result"],"owner":{"folder":"","commit":null},"output":{"analysis":{"folder":"","commit":null},"kind":"output","id":"result"},"universe":null,"places":[{"name":"result","address":"result","record":".astra/records/result.json","bytes":"results/result.json"}],"inputs":[],"decisions":{},"command":"python src/result.py '{output}'","workdir":"","read_only":false,"run_at":null,"resources":null}
```

What to notice

- `info` checks nothing. It binds the stack and prints each analysis, the root first (text
  only).
- The places are the specification's
  ([Results](https://astra-spec.org/0.1/specification/#results) *place*, *default place*):
  `.astra/records/<name>.json` and `results/<name>.<format>`, with no universe segment because
  there are no universes.
- `run in .` is `workdir: ""`: the analysis's folder, as a path from the repository's top.
- The text fills the placeholders; the JSON keeps the template. A runner fills it itself, with
  `render_command` and the paths it got for reads at a commit. The quotes stay: `'{output}'`
  becomes `'results/result.json'`.
- `owner` and `output.analysis` are identities: a folder and a commit, `null` for the working
  tree. The plan's whole JSON form is astra-tools'.
- `notes` is empty. Notes are astra-tools' own remarks, never diagnostics (Try 2 makes one).

Under the hood

- `src/astra/cli/info.py:23`: `show(read_stack(path))`, which is `api.bind` alone, without
  the rules.
- `src/astra/cli/plan.py:39` calls `api.plan`, which is `plan_stack(_valid(path), …)`
  (`src/astra/api.py:104`). `_valid` (`src/astra/api.py:169`) validates first and raises
  `InvalidAnalysisError` on a broken `MUST` (`src/astra/api.py:177`).
- `plan.plan` (`src/astra/plan.py:185`) builds the results; `universes.places`
  (`src/astra/universes.py:481`) gives each name's record and bytes
  (`src/astra/universes.py:492` and `:493`).
- `Plan.to_json` (`src/astra/plan.py:123`) is `astra-plan/1`. The text renders each command
  with `render_command(result, folder)` (`src/astra/cli/text/plan.py:39`;
  `src/astra/plan.py:712`).

## 5. `astra --help`: commands loaded lazily

What each command costs to start, measured.

```console
$ astra --help
Usage: astra [OPTIONS] COMMAND [ARGS]...

  Validate ASTRA analyses, show their stacks, and read the specification.

Options:
  --version  Show the version and exit.
  --help     Show this message and exit.

Commands:
  cache       Show or clear the cache.
  check       Check the records and bytes of the planned results of the...
  completion  Print the shell completion script.
  guide       Print the ASTRA guide for agents (llms.txt).
  history     Show what git holds of the records of an analysis's planned...
  info        Show the stack of the analysis in PATH, in brief.
  init        Make a minimal analysis in DIR.
  paper       Keep the papers an analysis cites by DOI, and seek its...
  plan        Show the planned results of the analysis in PATH, each...
  rules       List the specification's rules and astra-tools' own, or...
  schema      Show or export the JSON Schemas of ASTRA files.
  spec        Describe the fields of ASTRA files.
  universe    Show the universes of an analysis.
  validate    Validate the analysis in PATH.
  view        Show the analysis in PATH as it is in UNIVERSE, one of its...
$ python loaded.py --help
exit code: 0
astra (18): cli cli.cache cli.check cli.completion cli.guide cli.history cli.info cli.init cli.paper cli.plan cli.rules cli.schema cli.spec cli.universe cli.validate cli.view contract diagnostics
libraries: click
$ python loaded.py cache path
exit code: 0
astra (3): cache cli cli.cache
libraries: click
$ python loaded.py rules
exit code: 0
astra (6): cli cli.rules cli.text cli.text.rules diagnostics schema
libraries: click rich
$ python loaded.py validate first --json
exit code: 0
astra (39): api cache check cli cli.validate contract diagnostics environments grammar hashing history load model plan records rules rules.commits rules.context rules.decisions rules.declarations rules.driving rules.inputs rules.insights rules.names rules.outputs rules.pins rules.recipes rules.universes schema sources sources.git sources.paths sources.reader sources.remote sources.standins stack universes validate view
libraries: click jsonschema ruamel
$ python loaded.py validate first
exit code: 0
astra (41): api cache check cli cli.text cli.text.validate cli.validate contract diagnostics environments grammar hashing history load model plan records rules rules.commits rules.context rules.decisions rules.declarations rules.driving rules.inputs rules.insights rules.names rules.outputs rules.pins rules.recipes rules.universes schema sources sources.git sources.paths sources.reader sources.remote sources.standins stack universes validate view
libraries: click jsonschema rich ruamel
```

`loaded.py` (`cat loaded.py`) calls `astra.cli.main` with the arguments, throws its output
away, and lists the `astra.*` modules then in `sys.modules`, and which of astra-tools'
libraries were imported.

What to notice

- `--help` imports all fifteen command modules, since click asks each for its one-line help,
  but no library besides click. `contract` and `diagnostics` come in because `cli/schema.py`
  imports `astra.contract` at the top, for the names `schema show` accepts
  (`src/astra/cli/schema.py:12`); jsonschema stays out.
- `cache path` needs three modules.
- In `rules`, `schema` is astra-spec's `astra.schema`, imported by `importlib.resources` to
  read `rules.json` (step 6).
- `validate --json` loads 39 modules, the whole core library, `check` and `history` included,
  because `api.py` imports them at its top (`src/astra/api.py:14` to `:27`). rich isn't among
  them: CLAUDE.md makes import cost part of the API, and `tests/test_import_cost.py` holds
  astra-tools to it.
- The text report adds `cli.text`, `cli.text.validate` and rich. rich comes only through
  `cli.text`, the one package that imports it (`src/astra/cli/text/__init__.py:10`): `rules`
  and the text report load it, `--help` and `validate --json` don't.

Under the hood

- `COMMANDS` (`src/astra/cli/__init__.py:29`) maps each name to its module.
  `_Astra.get_command` imports the one asked for with `importlib.import_module`
  (`src/astra/cli/__init__.py:61`).
- Each command imports `astra.api` inside its function (`src/astra/cli/validate.py:23`), so
  parsing options costs nothing more.
- `Contract.load` imports jsonschema inside the method (`src/astra/contract.py:77`); `load.py`
  imports ruamel at its top, so ruamel comes with `api`.
- The `astra` script is `astra.cli:main` (`src/astra/cli/__init__.py:134`).

## 6. Where the rules and the schemas come from

astra-tools copies nothing from the specification: it reads astra-spec's installed files at run
time.

```console
$ python -c 'import astra, pathlib; [print(sorted(p.name for p in pathlib.Path(d).iterdir() if p.name != "__pycache__")) for d in astra.__path__]'
['docs', 'schema']
['_version.py', 'datamodel', 'schema']
['api.py', 'cache.py', 'check.py', 'cli', 'contract.py', 'diagnostics.py', 'environments.py', 'evidence', 'grammar.py', 'hashing.py', 'history.py', 'load.py', 'model.py', 'plan.py', 'py.typed', 'records.py', 'reference.py', 'rules', 'sources', 'stack.py', 'universes.py', 'validate.py', 'view.py']
$ python -c 'from importlib.resources import files; print(sorted(f"{d.name}/{p.name}" for d in files("astra.schema").iterdir() if d.is_dir() for p in d.iterdir()))'
['jsonld/provenance.context.jsonld', 'jsonschema/analysis.schema.json', 'jsonschema/provenance.open.schema.json', 'jsonschema/provenance.schema.json', 'rules/rules.json']
$ RULES=$(python -c 'from importlib.resources import files; print(files("astra.schema") / "rules" / "rules.json")')
$ jq -c '{comment: ."$comment", rules: (.rules | length), errors: (.errors | length)}' "$RULES"
{"comment":"ASTRA rule catalogue, schema version dev","rules":64,"errors":295}
$ jq -c '[.rules[].layer] | group_by(.) | map({(.[0]): length}) | add' "$RULES"
{"check":7,"parse":1,"runner":10,"schema":15,"validator":31}
$ jq -c '.rules[] | select(.code == "STALE_RESULT")' "$RULES"
{"code":"STALE_RESULT","layer":"check","level":"MUST","statement":"Nothing the result is made from has changed since its record's commit","status":"`stale`"}
$ jq -r '.errors["https://w3id.org/astra/dev/analysis.schema.json#/$defs/OutputType/enum"]' "$RULES"
INVALID_VALUE
$ astra rules | grep -v '^  '
parse

schema

validator

check

runner

validator, astra-tools' own

$ astra rules | grep -c '^  '
67
$ astra rules | tail -4
  UNSUPPORTED_SPEC_VERSION MUST Every `astra.yaml` of the stack states a `spec_version` whose minor version astra-tools has the schema of (0.1)
  REMOTE_UNREACHABLE MUST Every commit the stack gets from a remote can be got
  COMMIT_NOT_ANCESTOR SHOULD A declaration with a `path` and a `commit` names, in the repository that holds the declaring file, an ancestor of the commit the declaration is in or, read in the working tree, HEAD or an ancestor of it

$ astra rules missing_input_file
MISSING_INPUT_FILE
validator, MUST
An input's `path` names a file (no symlink, folder or gitlink) or a stand-in
$ astra rules UNSUPPORTED_SPEC_VERSION
UNSUPPORTED_SPEC_VERSION
validator, MUST, astra-tools
Every `astra.yaml` of the stack states a `spec_version` whose minor version astra-tools has the schema of (0.1)
$ astra rules NO_UNIVERSES; echo "exit code $?"
Usage: astra rules [OPTIONS] [CODE]
Try 'astra rules --help' for help.

Error: Invalid value for CODE: no rule has the code NO_UNIVERSES
exit code 2
$ astra schema show analysis | jq -c '{"$schema", "$id", required}'
{"$schema":"https://json-schema.org/draft/2019-09/schema","$id":"https://w3id.org/astra/dev/analysis.schema.json","required":["spec_version"]}
$ astra schema show analysis | cmp - "$(python -c 'from astra.contract import schema_file; print(schema_file("analysis"))')" && echo identical
identical
```

What to notice

- `astra` is one PEP 420 namespace in three portions, none with an `__init__.py`: astra-spec's
  installed data (`docs/llms.txt`, which `astra guide` prints, and the generated files under
  `schema/`), astra-spec's sources (the LinkML sources in `schema/`, the Python models in
  `datamodel/`), and astra-tools' modules. An `__init__.py` in any of them would hide the
  others. `astra.schema` is itself spread over two portions, so it is read through
  `importlib.resources`, which joins them, not through one folder.
- `jsonschema/`, `jsonld/` and `rules/` hold the five files of the specification's table
  ([Schema files](https://astra-spec.org/0.1/specification/#schema-files)), in the folders the
  LinkML project template keeps them in. `datamodel/` holds the Python models of the two
  documents, LinkML's dataclasses and Pydantic models, which astra-tools doesn't use.
- `$comment` says `dev`, and the `$id`s carry `/dev/`: astra-spec is installed from a source
  tree, not a release, whose files would carry `/0.1/`. The keys of `errors` carry the `$id`,
  so they follow it.
- 64 rules: 1 parse, 15 schema, 31 validator, 7 check, 10 runner. A check rule has a `status`.
- The `INVALID_VALUE` of step 2 came from that one entry of `errors`: the keyword
  `#/$defs/OutputType/enum`.
- `astra rules` lists 67: the 64, then astra-tools' three in a section of their own, with
  `astra-tools` as their source. `UNSUPPORTED_SPEC_VERSION` and `REMOTE_UNREACHABLE` are
  errors, `COMMIT_NOT_ANCESTOR` a warning.
- CODE is read in any case. A code the specification dropped, such as `NO_UNIVERSES`, isn't
  offered: exit 2.
- `astra schema show` is the installed file, byte for byte.

Under the hood

- `Catalogue.load` (`src/astra/diagnostics.py:105`) reads
  `files("astra.schema") / "rules" / "rules.json"` (`src/astra/diagnostics.py:107`) at each
  call: no module-level cache. The three own codes are the table `OWN`
  (`src/astra/diagnostics.py:60`).
- `Catalogue.level` (`src/astra/diagnostics.py:139`): `MUST` gives `error`, `SHOULD` gives
  `warning`. A code in neither table is a `LookupError`, an internal error.
- `Contract.load` (`src/astra/contract.py:76`) extends jsonschema's `Draft201909Validator`
  with a `pattern` of its own, whose `$` matches only at the end, as ECMA-262's does
  (`src/astra/contract.py:80`), and keeps each schema's `$id`
  (`src/astra/contract.py:84`).
- `Contract._check` (`src/astra/contract.py:113`): for each error, the keyword location is the
  `$id`, `#`, the failing subschema's pointer (found by object identity in an index of the
  schema) and the keyword (`src/astra/contract.py:118`), looked up in `errors`
  (`src/astra/contract.py:119`). A miss raises `LookupError` (`src/astra/contract.py:121`):
  astra-tools and astra-spec disagree.
- `astra rules CODE`: `find(code.upper())` (`src/astra/cli/rules.py:24`); no rule is click's
  `BadParameter` (`src/astra/cli/rules.py:26`), a usage error.
- `astra schema show` prints `schema_file(name).read_bytes()` (`src/astra/cli/schema.py:28`;
  `schema_file` at `src/astra/contract.py:56`).

## 7. The pipeline, one layer at a time

Each layer imports only from those before it (CLAUDE.md's *Key Design Principles*):

| Layer | Modules | What it does |
|---|---|---|
| foundations | `diagnostics.py`, `grammar.py`, `model.py` | locations, diagnostics and the catalogue; the forms of a name (Elements *id*, *address*, *reference*); frozen dataclasses of the two documents |
| read | `sources/paths.py`, `sources/git.py`, `sources/reader.py`, `sources/remote.py`, `sources/standins.py`, `cache.py` | every byte through a `Reader`; git only through the `git` binary |
| load | `load.py` | bytes to a JSON value with positions; `INVALID_SYNTAX` |
| contract | `contract.py` | JSON Schema 2019-09 and `rules.json`'s `errors`; `UNSUPPORTED_SPEC_VERSION` |
| bind | `stack.py` | every analysis read once, every declaration followed, every address resolved: a `Stack` |
| rules, plan, view | `universes.py`, `rules/`, `validate.py`, `plan.py`, `view.py` | functions of a `Stack` |
| check | `hashing.py`, `records.py`, `environments.py`, `check.py`, `history.py` | records, hashes and statuses |
| surfaces | `api.py`, `cli/`, `reference.py`, `evidence/` | the stable functions, and the commands |

The layers say what imports what, not where IO happens. The code keeps the import order and
has no module-level state, but neither foundations nor the meaning layer is free of IO:

- Foundations: `Catalogue.load` reads `rules.json` (`src/astra/diagnostics.py:107`) at every
  call, and `validate`, `plan` and `view` each call it (`src/astra/validate.py:80`,
  `src/astra/plan.py:202`, `src/astra/view.py:104`). `grammar.py` and `model.py` do no IO.
- Rules, plan and view take a `Stack` and do their IO through its readers. `rules/inputs.py`
  asks which inputs are tracked (`src/astra/rules/inputs.py:53`: `git ls-files` in the working
  tree) and stats them (`:83`, `:109`); a stand-in is recognised by reading the file
  (`src/astra/sources/standins.py:77`); the plan's `outside_folder` note stats through a
  reader (`src/astra/plan.py:631`).
- `rules/commits.py` goes further: `git merge-base --is-ancestor` for `COMMIT_NOT_ANCESTOR`
  (`src/astra/rules/commits.py:88`), the cache's `validity` read and written (`:185`,
  `:200`), and, on a miss, a whole nested `validate` on a `CommitReader` (`:190`), which can
  fetch (step 8, Try 4).

The same `validate` as step 2, a layer at a time, in Python (leave with Ctrl-D):

```console
$ python -q
>>> from pathlib import Path
>>> from astra.sources.git import Repository
>>> from astra.sources.reader import WorktreeReader
>>> repo = Repository.discover(Path("first"))
>>> reader = WorktreeReader(repo.top, repo)
>>> reader.stat("astra.yaml"), reader.tracked("", ["astra.yaml"])
(Entry(kind='file', target=None), frozenset())
>>> data = reader.read("astra.yaml")
>>> from astra.load import load_yaml
>>> doc = load_yaml(data)
>>> doc.value["outputs"]["result"]["type"], doc.position(["outputs", "result", "type"])
('metric', (4, 11))
>>> from astra.diagnostics import Catalogue
>>> catalogue = Catalogue.load()
>>> catalogue.version, len(catalogue.rules), len(catalogue.errors)
('ASTRA rule catalogue, schema version dev', 64, 295)
>>> from astra.contract import Contract
>>> contract = Contract.load(catalogue)
>>> contract.check_analysis(doc, "astra.yaml")
()
>>> contract.check_analysis(load_yaml(data.replace(b"metric", b"metrc")), "astra.yaml")[0].code
'INVALID_VALUE'
>>> from astra.stack import bind
>>> bound = bind(reader, "")
>>> bound.diagnostics, bound.stack.root
((), Identity(folder='', commit=None))
>>> bound.stack.analyses[bound.stack.root].analysis.outputs["result"].recipe
Recipe(command="python src/result.py '{output}'", resources=None)
>>> from astra.rules import check
>>> from astra.rules.context import Context
>>> check(Context(bound.stack, catalogue))
[]
>>> from astra.plan import plan
>>> plan(bound.stack).results[0].places
(Place(name='result', address='result', record='.astra/records/result.json', bytes='results/result.json'),)
>>> from astra import api
>>> api.validate("first")
ValidationReport(root='astra.yaml', diagnostics=(), unchecked=())
```

What to notice

- The reader is the only way in for bytes: a `WorktreeReader` here, a `CommitReader` for a
  commit (step 8, and `check --at`). Paths are from the repository's top, so `""` is the top:
  here, the root's folder.
- `tracked` reads the index. `astra.yaml` isn't tracked, and no rule minds; Try 3 shows where
  tracking matters.
- Only `load_yaml` raises on a broken rule: a `ParseError`, which `bind` turns into an
  `INVALID_SYNTAX` diagnostic (`src/astra/stack.py:304`). The contract and the rules return
  diagnostics.
- `bind` reports only parse and schema diagnostics, and astra-tools' `UNSUPPORTED_SPEC_VERSION`.
  Addresses and declarations are the rules' business.
- The plan is computed again on each call, from the stack and a catalogue loaded afresh. Nothing
  is kept between calls: no module keeps state (CLAUDE.md's *Key Conventions*).

How `astra validate first` runs, call by call:

1. `astra.cli:main` (`src/astra/cli/__init__.py:134`) imports `astra.cli.validate`
   (`src/astra/cli/__init__.py:61`).
2. `command` (`src/astra/cli/validate.py:16`) calls `api.validate` inside `environment()`
   (`src/astra/cli/validate.py:25` and `:26`).
3. `api.validate` calls `api._root` (`src/astra/api.py:81`, defined at `:241`):
   `Repository.discover` (`src/astra/api.py:247`), a `WorktreeReader` at the repository's top
   (`src/astra/api.py:253`), and the root's folder as a path from there.
4. `api.validate` then calls `validate.validate` (`src/astra/api.py:82`, imported as
   `validate_reader`), which is `validated(...)[0]` (`src/astra/validate.py:71`): the report
   without the stack.
5. `validate.validated` (`src/astra/validate.py:74`): `Catalogue.load` (`:80`), then `bind`
   (`:81`).
6. `stack.bind` (`src/astra/stack.py:242`) reads the root (`src/astra/stack.py:270`):
   `_check` (`src/astra/stack.py:298`) runs `load_yaml` (`:304`) and `check_analysis` (`:308`).
   A valid document becomes `model.Analysis.from_json` (`src/astra/stack.py:262`). Then each
   declaration is followed (`src/astra/stack.py:278`) and every address resolved
   (`src/astra/stack.py:288`).
7. `rules.check(Context(stack, catalogue))` (`src/astra/validate.py:93`; defined at
   `src/astra/rules/__init__.py:54`) runs the eleven modules of `MODULES`
   (`src/astra/rules/__init__.py:36`), one per subject, names, inputs, decisions and so on
   (`NOT_IN_REPOSITORY` is in `validate.py`). `commits` runs
   first (`:58`), and `commits.related` adds the declarations that lead to a commit's file as
   related places to the other modules' diagnostics (`:60`).
8. Duplicates go, the rest are sorted (`src/astra/validate.py:96` and `:97`), and the
   `ValidationReport` goes back to the CLI, which prints it.

`plan`, `view`, `check` and `history` start the same way, through `api._read`
(`src/astra/api.py:182`), which calls `validated` directly (`src/astra/api.py:197`), since they
need the stack as well as the report: each of them validates first. While astra-tools was
rebuilt for 0.1, a reading kept for an open question of the specification's meaning was marked
`# OPEN(<id>)`, at the one place that kept it. None is open now, so the code holds no marker:

```console
$ git --no-pager -C "$TOUR"/repos/astra-tools grep -n 'OPEN(' -- src/astra; echo "exit code $?"
exit code 1
```

## 8. The cache, and an analysis from another repository

What astra-tools keeps, where, and when it starts keeping anything. Here the cache moves to a
folder of this chapter's own, so that what shows up is only what this step puts there.

```console
$ astra cache path
…/tour/work/cache
$ export ASTRA_CACHE_DIR="$TOUR/work/01/cache"
$ astra cache path
…/tour/work/01/cache
$ test -e "$ASTRA_CACHE_DIR" || echo "nothing there yet"
nothing there yet
$ git --no-pager -C upstream log --format='%h %s'
345e144 Spell recipe right
b26542c Count the words
$ printf 'analyses:\n  up:\n    url: file://%s\n    commit: "%s"\n' "$TOUR/work/01/upstream" "$(git -C upstream rev-parse HEAD)" >> first/astra.yaml
$ tail -4 first/astra.yaml
analyses:
  up:
    url: file://…/tour/work/01/upstream
    commit: "345e144f4fe5d2829fedf07f2305c3a83672df4a"
$ astra validate first
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra info first
astra.yaml
  analyses  up: astra.yaml at 345e144f4fe5d2829fedf07f2305c3a83672df4a from file://…/tour/work/01/upstream
  outputs   result: metric, json
astra.yaml at 345e144f4fe5d2829fedf07f2305c3a83672df4a from file://…/tour/work/01/upstream
  inputs    words: words.txt
  outputs   count: metric, json
$ ls -1 "$ASTRA_CACHE_DIR"
remotes
validity
$ ls -1 "$ASTRA_CACHE_DIR"/remotes
746cbe23d4eae1f14135338f70758f9b04e7e99098ceb2f027f3c036aa37c360
$ printf %s "file://$TOUR/work/01/upstream" | sha256sum
746cbe23d4eae1f14135338f70758f9b04e7e99098ceb2f027f3c036aa37c360  -
$ git -C "$ASTRA_CACHE_DIR"/remotes/* config remote.origin.url
file://…/tour/work/01/upstream
$ git -C "$ASTRA_CACHE_DIR"/remotes/* for-each-ref --format='%(refname)'
refs/astra/345e144f4fe5d2829fedf07f2305c3a83672df4a
$ git -C "$ASTRA_CACHE_DIR"/remotes/* cat-file --batch-check --batch-all-objects 2>/dev/null | cut -d' ' -f2 | sort | uniq -c
      4 blob
      2 commit
      3 tree
$ cat "$ASTRA_CACHE_DIR"/validity/*; echo
[]
```

Now declare the first commit, the one that misspells `recipe`:

```console
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD)/$(git -C upstream rev-parse HEAD~1)/" first/astra.yaml
$ astra validate first; echo "exit code $?"
astra.yaml
  10:5 error DECLARED_ANALYSIS_INVALID `up` names an analysis that isn't valid at its commit: it breaks MISSING_FIELD, UNKNOWN_FIELD, each reported at its place in that commit's files
astra.yaml at b26542cb3af9c9b7ba52870d1a20541c2d9df231 from file://…/tour/work/01/upstream
  7:5 error MISSING_FIELD `count` lacks `recipe`
  10:5 error UNKNOWN_FIELD `recipie` isn't a field here
astra.yaml: invalid, 3 error(s), 0 warning(s)
exit code 1
$ astra validate first --json | jq -c '.diagnostics[0]'
{"code":"DECLARED_ANALYSIS_INVALID","level":"error","message":"`up` names an analysis that isn't valid at its commit: it breaks MISSING_FIELD, UNKNOWN_FIELD, each reported at its place in that commit's files","location":{"file":"astra.yaml","pointer":"/analyses/up","line":10,"column":5,"key":null,"commit":null,"url":null},"related":[{"file":"astra.yaml","pointer":"/outputs/count","line":7,"column":5,"key":null,"commit":"b26542cb3af9c9b7ba52870d1a20541c2d9df231","url":"file://…/tour/work/01/upstream"},{"file":"astra.yaml","pointer":"/outputs/count","line":10,"column":5,"key":"recipie","commit":"b26542cb3af9c9b7ba52870d1a20541c2d9df231","url":"file://…/tour/work/01/upstream"}]}
$ ls -1 "$ASTRA_CACHE_DIR"/validity | wc -l
2
$ git -C "$ASTRA_CACHE_DIR"/remotes/* for-each-ref --format='%(refname)'
refs/astra/345e144f4fe5d2829fedf07f2305c3a83672df4a
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD~1)/$(git -C upstream rev-parse HEAD)/" first/astra.yaml
$ astra validate first
astra.yaml: valid, 0 error(s), 0 warning(s)
```

The jq filter prints the first diagnostic alone. The cache's five folders (the
cache is astra-tools' own, outside the specification):

| Folder | Holds | Filled by |
|---|---|---|
| `remotes` | one bare repository per URL, named by the URL's SHA-256 | a `url` declaration (or a gitlink's submodule URL at a commit), whenever the stack is bound: by every command that reads an analysis (`validate`, `info`, `universe`, `plan`, `view`, `check`, `history`, `paper`) |
| `validity` | the `MUST`s an analysis from a commit breaks as its own root, `[]` when none | a declaration with a `commit`, whenever the rules run: `validate`, and `plan`, `view`, `check`, `history` and `paper`, which validate first (`info` and `universe` only bind) |
| `hashes` | a file's SHA-256 and size, by device and inode, with its size and modification time | `astra check`, and a runner's `new_record` |
| `worktrees` | checkouts of a commit, for a run that leaves your checkout alone | a runner, through `Repository.worktree` |
| `papers` | papers cited by DOI | `astra paper add` (extra `[evidence]`) |

What to notice

- The folder is made only when something needs it. Nothing in steps 1 to 7 needed one, since
  the scaffold declares nothing and has no record to hash (Try 4 shows a bad cache setting
  going unnoticed for that reason).
- The store is a bare repository whose `origin` is the URL. Each commit asked for is kept by
  a ref of its own, `refs/astra/<commit>`, so it is fetched once.
- The store's name hashes a URL that holds the tour folder's absolute path. The `746cbe23…`
  shown is for the tour at `/home/r/Projects/LightconeResearch/astra-tour`; elsewhere both
  lines show another hash, the same in each.
- The fetch asks for no blobs (`--filter=blob:none`), yet the store holds all four blobs of
  the two commits (`words.txt` and `src/count.py`, the same in both, and two `astra.yaml`s).
  The `git upload-pack` that serves `upstream` ignores filters unless that repository sets
  `uploadpack.allowFilter`, false by default. The fetch warns that the filter is ignored, on a
  stderr astra-tools captures and drops. `2>/dev/null` hides git's other warning, that the
  store is a partial clone.
- `b26542c` needed no fetch and got no ref: the store already had it, as the parent of
  `345e144`, and a kept commit counts as got.
  Here its blobs were there too, because `upstream` ignored the filter. From a remote that
  honours it, as GitHub does, the commit and its trees come without blobs, and a blob is
  fetched when it is first read, online, and never offline (Try 4 makes `upstream` honour
  it).
- `validity` has an entry per commit judged: `[]` for `345e144`, the two diagnostics for
  `b26542c`. Its file names hash a key that includes astra-tools' version, so they differ
  between installs; this chapter never shows them.
- The report fills the last fields of step 2's table. `DECLARED_ANALYSIS_INVALID` sits on the
  declaration, in the file you can edit, with no `commit`; its `related` are the places in the
  commit's file, which carry `commit` and `url`. Each `MUST` is also reported at its own place,
  under `astra.yaml at <commit> from <url>`. Reporting both is astra-tools' choice.
- Both files are `astra.yaml`: each path is from the top of its own repository.
- Back on `345e144`, the verdict comes from `validity`, not from validating again (Try 5
  proves it).

Under the hood

- `cache.root` (`src/astra/cache.py:32`): `ASTRA_CACHE_DIR`, refused when relative
  (`src/astra/cache.py:38` to `:42`), or else the platform's user cache folder. An entry is
  `<namespace>/<sha256 of its key>` (`src/astra/cache.py:104`), written atomically
  (`src/astra/cache.py:61`). `NAMESPACES` (`src/astra/cache.py:21`) is what `astra cache clear`
  deletes, and nothing else.
- `Remotes.get` (`src/astra/sources/remote.py:47`): the store's commit, or else a fetch,
  unless `--offline`. `_store` (`src/astra/sources/remote.py:58`) names the folder by the
  URL's SHA-256 (`:62`) and makes it with `init_bare`, `origin` set to the URL (`:66`).
- `Repository.fetch` (`src/astra/sources/git.py:150`): `git fetch --filter=blob:none origin
  <commit>:refs/astra/<commit>` (`src/astra/sources/git.py:156`), its output captured and
  dropped (`_git`, `src/astra/sources/git.py:35`).
- Every `git` astra-tools runs gets `_environment()` (`src/astra/sources/git.py:25`):
  `GIT_TERMINAL_PROMPT=0`, so git never waits for a password, and `GIT_NO_LAZY_FETCH=1`
  (`:31`), so an object a partial clone lacks reads as missing. One process is the exception:
  a `CommitReader` reads objects through a long-lived `git cat-file --batch` (`Objects`,
  `src/astra/sources/git.py:218`), made with `lazy=not remotes.offline`
  (`src/astra/sources/reader.py:186`). Online, a blob the store lacks is fetched as it is
  read. Offline, `_blob` raises `FileNotFoundError` (`src/astra/sources/reader.py:273`), an
  `OSError`, which `environment()` turns into exit 2 (Try 4).
- `stack.bind` stamps each diagnostic of a file read at a commit with that commit and its URL
  (`src/astra/stack.py:259`).
- `rules/commits.py`: `_judged` (`src/astra/rules/commits.py:171`) builds the key from
  astra-tools' version, `rules.json`'s `$comment`, the folder and the commit (`:184`), and
  reads it (`:185`). On a miss it validates the analysis as its own root at its commit
  (`:190`), and keeps the verdict (`:200`) unless it rests on a commit that couldn't be got or
  on `COMMIT_NOT_FOUND` (`:198`). `_invalid` (`:152`) reports `DECLARED_ANALYSIS_INVALID`
  with the broken `MUST`s as related places (`:167`), then each of them.
- The other namespaces: `hashing.py` keys an entry by `st_dev:st_ino`
  (`src/astra/hashing.py:47`) and doesn't keep a file modified less than two seconds before
  (`src/astra/hashing.py:60`); `Repository.worktree` makes its checkouts under `worktrees`
  (`src/astra/sources/git.py:197`).

## Try

Run them in order, from where step 8 left off.

**1. Versions before the schema.** Predict the codes, how many, and the exit code, for each
`spec_version`: `"0.2.0"` with `recipe` misspelt again; `0.1` unquoted; `"0.1"` quoted;
`"0.1.7"`.

```console
$ perl -pi -e 's/"0.1.0"/"0.2.0"/; s/recipe:/recipie:/' first/astra.yaml
$ astra validate first; echo "exit code $?"
$ perl -pi -e 's/"0.2.0"/0.1/' first/astra.yaml
$ astra validate first; echo "exit code $?"
$ perl -pi -e 's/^spec_version: 0.1$/spec_version: "0.1"/; s/recipie:/recipe:/' first/astra.yaml
$ astra validate first; echo "exit code $?"
$ perl -pi -e 's/"0.1"/"0.1.7"/' first/astra.yaml
$ astra validate first; echo "exit code $?"
$ perl -pi -e 's/"0.1.7"/"0.1.0"/' first/astra.yaml
```

<details><summary>Answer</summary>

```console
$ perl -pi -e 's/"0.1.0"/"0.2.0"/; s/recipe:/recipie:/' first/astra.yaml
$ astra validate first; echo "exit code $?"
astra.yaml
  1:15 error UNSUPPORTED_SPEC_VERSION spec_version 0.2.0 is ASTRA 0.2, and this astra-tools reads ASTRA 0.1 alone
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit code 1
$ perl -pi -e 's/"0.2.0"/0.1/' first/astra.yaml
$ astra validate first; echo "exit code $?"
astra.yaml
  1:15 error WRONG_TYPE `spec_version` is a number, where it takes a string
  4:5 error MISSING_FIELD `result` lacks `recipe`
  6:5 error UNKNOWN_FIELD `recipie` isn't a field here
astra.yaml: invalid, 3 error(s), 0 warning(s)
exit code 1
$ perl -pi -e 's/^spec_version: 0.1$/spec_version: "0.1"/; s/recipie:/recipe:/' first/astra.yaml
$ astra validate first; echo "exit code $?"
astra.yaml
  1:15 error INVALID_VALUE `spec_version` doesn't match `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`: "0.1"
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit code 1
$ perl -pi -e 's/"0.1"/"0.1.7"/' first/astra.yaml
$ astra validate first; echo "exit code $?"
astra.yaml: valid, 0 error(s), 0 warning(s)
exit code 0
$ perl -pi -e 's/"0.1.7"/"0.1.0"/' first/astra.yaml
```

- `"0.2.0"` is well formed and outside 0.1: astra-tools' own `UNSUPPORTED_SPEC_VERSION`, and
  the schema isn't run, so `recipie` goes unreported (`src/astra/contract.py:90` to `:95`).
  The file isn't a valid document, so its declaration isn't followed either: `up` isn't read
  at all.
- `0.1` is a number, so there is no well-formed version to read (`_version`,
  `src/astra/contract.py:131`), and the 0.1 schema runs: `WRONG_TYPE`, and `recipie`'s two
  errors with it.
- `"0.1"` is a string that breaks the version pattern: `INVALID_VALUE`, the schema's code.
- `"0.1.7"` is valid: a file is read by the schema of its minor version, and any patch of 0.1
  is valid exactly when `0.1.0` is
  ([Rules](https://astra-spec.org/0.1/specification/#rules) *valid*).

</details>

**2. An analysis inside an analysis.** `astra init first/src`. Predict: is a repository made,
what `root` does `astra validate first/src` report, and does `astra plan first` change?

```console
$ astra init first/src
$ git -C first status --porcelain
$ astra validate first/src
$ astra validate first
$ astra plan first; echo "exit code $?"
$ astra plan first --notes
```

<details><summary>Answer</summary>

```console
$ astra init first/src
Made first/src/astra.yaml, in the git repository that holds it.
Check it with: astra validate first/src
$ git -C first status --porcelain
?? astra.yaml
?? src/
$ astra validate first/src
src/astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra validate first
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra plan first; echo "exit code $?"
result
  record    .astra/records/result.json
  bytes     results/result.json
  run in    .
  command   python src/result.py 'results/result.json'
1 planned result(s), and notes, none of them a breach (--notes lists them):
  1 command(s) name a path outside their analysis (CODE_OUTSIDE_ANALYSIS)
exit code 0
$ astra plan first --notes
result
  record    .astra/records/result.json
  bytes     results/result.json
  run in    .
  command   python src/result.py 'results/result.json'
note astra.yaml:7:16 the command names `src/result.py`, inside `src`, which holds an analysis of its own: a recipe should run only code tracked in its analysis's folder, outside every folder below it that holds an analysis of its own, or that its output's inputs give it (`CODE_OUTSIDE_ANALYSIS`)
1 planned result(s), and notes, none of them a breach:
  1 command(s) name a path outside their analysis (CODE_OUTSIDE_ANALYSIS)
```

- No repository: `first` already holds `src`. The `root` is `src/astra.yaml`, a path from
  the repository's top, not from PATH.
- `first` stays valid: no validator rule forbids an analysis in a folder below another.
- The plan gains an `outside_folder` note: the scaffold's command names `src/result.py`, and
  `src` now holds an analysis of its own. A note is astra-tools' own remark: no
  code is reported, and the exit code stays 0. It is found by looking for an `astra.yaml` in
  each folder on the way to a path the command names (`_outside_folder`,
  `src/astra/plan.py:609`; the note at `:656`).

</details>

**3. Tracked means the index.** Give `first` an input, `words`, at `words.txt`. Predict the
code before the file exists, once it exists, and after `git add`, without a commit.

```console
$ perl -0pi -e 's/outputs:/inputs:\n  words:\n    path: words.txt\noutputs:/' first/astra.yaml
$ astra validate first; echo "exit code $?"
$ echo "one two three" > first/words.txt
$ astra validate first; echo "exit code $?"
$ git -C first add words.txt
$ astra validate first; echo "exit code $?"
$ git -C first rev-parse --verify --quiet HEAD; echo "exit code $?"
```

<details><summary>Answer</summary>

```console
$ perl -0pi -e 's/outputs:/inputs:\n  words:\n    path: words.txt\noutputs:/' first/astra.yaml
$ astra validate first; echo "exit code $?"
astra.yaml
  4:11 error MISSING_INPUT_FILE `words.txt` names no file, and no stand-in of Git LFS, git-annex, DVC
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit code 1
$ echo "one two three" > first/words.txt
$ astra validate first; echo "exit code $?"
astra.yaml
  4:11 error INPUT_NOT_TRACKED `words.txt` isn't tracked in the repository that holds this analysis: `git add` it (a file kept in a submodule is never tracked here)
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit code 1
$ git -C first add words.txt
$ astra validate first; echo "exit code $?"
astra.yaml: valid, 0 error(s), 0 warning(s)
exit code 0
$ git -C first rev-parse --verify --quiet HEAD; echo "exit code $?"
exit code 1
```

- With no file, only `MISSING_INPUT_FILE`: an input with no file isn't checked by
  `INPUT_NOT_TRACKED`.
- Tracked means in the index, read with `git ls-files --stage`
  (`src/astra/sources/git.py:91`). A staged file is enough, and HEAD
  still has no commit.
- The message names the stand-ins astra-tools recognises: Git LFS, git-annex and DVC
  ([Elements](https://astra-spec.org/0.1/specification/#elements) *stand-in*).

</details>

**4. When the cache is asked for, and what a fetch brings.** Predict both exit codes with a
relative `ASTRA_CACHE_DIR`. Then clear the cache and predict `--offline`. Then make `upstream`
honour the blob filter, as GitHub does, and predict how many blobs the store gets, and what
`--offline` says once the declaration names `b26542c`.

```console
$ ASTRA_CACHE_DIR=cache astra validate first/src; echo "exit code $?"
$ ASTRA_CACHE_DIR=cache astra validate first; echo "exit code $?"
$ astra cache clear
$ astra validate --offline first; echo "exit code $?"
$ git -C upstream config uploadpack.allowFilter true
$ astra validate first
$ git -C "$ASTRA_CACHE_DIR"/remotes/* cat-file --batch-check --batch-all-objects 2>/dev/null | cut -d' ' -f2 | sort | uniq -c
$ astra validate --offline first
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD)/$(git -C upstream rev-parse HEAD~1)/" first/astra.yaml
$ astra validate --offline first; echo "exit code $?"
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD~1)/$(git -C upstream rev-parse HEAD)/" first/astra.yaml
```

<details><summary>Answer</summary>

```console
$ ASTRA_CACHE_DIR=cache astra validate first/src; echo "exit code $?"
src/astra.yaml: valid, 0 error(s), 0 warning(s)
exit code 0
$ ASTRA_CACHE_DIR=cache astra validate first; echo "exit code $?"
astra: ASTRA_CACHE_DIR is the relative path 'cache', which would put the cache inside whatever repository astra runs in: give it an absolute path
exit code 2
$ astra cache clear
Cleared the cache in …/tour/work/01/cache.
$ astra validate --offline first; echo "exit code $?"
astra.yaml
  13:5 error REMOTE_UNREACHABLE the commit `345e144f4fe5d2829fedf07f2305c3a83672df4a` can't be fetched from `file://…/tour/work/01/upstream`, and no earlier fetch kept it: check the URL and the commit, and that git can reach the remote (with --offline, nothing is fetched)
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit code 1
$ git -C upstream config uploadpack.allowFilter true
$ astra validate first
astra.yaml: valid, 0 error(s), 0 warning(s)
$ git -C "$ASTRA_CACHE_DIR"/remotes/* cat-file --batch-check --batch-all-objects 2>/dev/null | cut -d' ' -f2 | sort | uniq -c
      1 blob
      2 commit
      3 tree
$ astra validate --offline first
astra.yaml: valid, 0 error(s), 0 warning(s)
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD)/$(git -C upstream rev-parse HEAD~1)/" first/astra.yaml
$ astra validate --offline first; echo "exit code $?"
astra: can't read astra.yaml: astra.yaml at b26542cb3af9c9b7ba52870d1a20541c2d9df231 isn't kept in the cache: validate without --offline to fetch it
exit code 2
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD~1)/$(git -C upstream rev-parse HEAD)/" first/astra.yaml
```

- `first/src` declares nothing, so nothing asks for the cache, and the bad setting goes
  unnoticed. `first` declares a URL: `_store` calls `cache.root()`, whose `CacheError` is
  exit 2 (`src/astra/cache.py:38`; `src/astra/cli/__init__.py:94`).
- Offline with an empty cache, the commit can't be got: `REMOTE_UNREACHABLE`, astra-tools' own
  error, on the declaration (13:5 now, after Try 3's three lines). The analysis that can't be
  got isn't judged, so `DECLARED_ANALYSIS_INVALID` isn't checked and no verdict goes into
  `validity`.
- With `uploadpack.allowFilter`, the fetch brings both commits and their three trees, and no
  blob. The one blob is `345e144`'s `astra.yaml`, fetched into a pack of its own by the
  `CommitReader`'s `cat-file` when `bind` read it (`ls "$ASTRA_CACHE_DIR"/remotes/*/objects/pack`
  shows two packs, each with a `.promisor` file). Nothing reads `words.txt` or `src/count.py`: whether an
  input is a file, and tracked, is read from the tree.
- Offline, `345e144` reads from the store. `b26542c`'s commit object is kept, and
  `Remotes.get` counts a commit as got by its commit object alone (`has_commit`,
  `src/astra/sources/remote.py:47`), so there is no `REMOTE_UNREACHABLE`. Its `astra.yaml`
  was never read, so its blob isn't there: `_blob` raises `FileNotFoundError`, an `OSError`,
  which `environment()` makes exit 2, with astra-tools' message and no diagnostic.
- That is astra-tools' current handling, and nothing written names the case. Its
  `docs/cli.md` says only that `--offline` fetches nothing and uses only the commits already in
  the cache, and the specification doesn't say when a commit counts as got. "A commit kept from
  an earlier fetch counts as got", in the docstring of `src/astra/sources/remote.py`, could as
  well be read so that a commit kept without the blobs it needs isn't got, which would make it
  a `REMOTE_UNREACHABLE`. A gap, not something derived from what is written.

</details>

**5. The cache is trusted.** Validate the bad commit once more, so that `validity` holds both
verdicts, then copy the bad verdict over the good one. Predict what `astra validate first`
says, on `345e144`. Then break the entry outright.

```console
$ good=$(grep -lx '\[\]' "$ASTRA_CACHE_DIR"/validity/*)
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD)/$(git -C upstream rev-parse HEAD~1)/" first/astra.yaml
$ astra validate first > /dev/null
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD~1)/$(git -C upstream rev-parse HEAD)/" first/astra.yaml
$ bad=$(grep -Lx '\[\]' "$ASTRA_CACHE_DIR"/validity/*)
$ cp "$bad" "$good"
$ astra validate first; echo "exit code $?"
$ printf 'not json' > "$good"
$ astra validate first; echo "exit code $?"
$ ASTRA_DEBUG=1 astra validate first 2>&1 | grep -o 'astra/rules/commits.py", line [0-9]*, in .*'
$ astra cache clear
$ astra validate first
```

<details><summary>Answer</summary>

```console
$ good=$(grep -lx '\[\]' "$ASTRA_CACHE_DIR"/validity/*)
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD)/$(git -C upstream rev-parse HEAD~1)/" first/astra.yaml
$ astra validate first > /dev/null
$ perl -pi -e "s/$(git -C upstream rev-parse HEAD~1)/$(git -C upstream rev-parse HEAD)/" first/astra.yaml
$ bad=$(grep -Lx '\[\]' "$ASTRA_CACHE_DIR"/validity/*)
$ cp "$bad" "$good"
$ astra validate first; echo "exit code $?"
astra.yaml
  13:5 error DECLARED_ANALYSIS_INVALID `up` names an analysis that isn't valid at its commit: it breaks MISSING_FIELD, UNKNOWN_FIELD, each reported at its place in that commit's files
astra.yaml at b26542cb3af9c9b7ba52870d1a20541c2d9df231 from file://…/tour/work/01/upstream
  7:5 error MISSING_FIELD `count` lacks `recipe`
  10:5 error UNKNOWN_FIELD `recipie` isn't a field here
astra.yaml: invalid, 3 error(s), 0 warning(s)
exit code 1
$ printf 'not json' > "$good"
$ astra validate first; echo "exit code $?"
astra: internal error: JSONDecodeError: Expecting value: line 1 column 1 (char 0)
This is a bug in astra-tools: please report it.
exit code 2
$ ASTRA_DEBUG=1 astra validate first 2>&1 | grep -o 'astra/rules/commits.py", line [0-9]*, in .*'
astra/rules/commits.py", line 78, in check
astra/rules/commits.py", line 158, in _invalid
astra/rules/commits.py", line 187, in _judged
$ astra cache clear
Cleared the cache in …/tour/work/01/cache.
$ astra validate first
astra.yaml: valid, 0 error(s), 0 warning(s)
```

- The declaration names `345e144`, and the report shows `b26542c`'s places: an entry is
  believed as it is, never checked against its key. That is the proof that the verdict came
  from the cache.
- Garbage in an entry is an internal error, exit 2, whose message blames astra-tools
  (`_judged`'s `json.loads`, `src/astra/rules/commits.py:187`). astra-tools never writes half
  an entry, and has no message of its own for a damaged one: input the specification never
  describes is left to whatever the library gives. The message's "bug in astra-tools" points at
  the wrong culprit. `ASTRA_DEBUG`
  prints the traceback, filtered here to `rules/commits.py`'s frames.
- `astra cache clear` mends both: everything in the cache is safe to delete.

</details>

## What you now know

- `astra init` writes `MINIMAL` and runs `git init`, and does nothing else to git. A valid
  analysis needs no commit and no tracked `astra.yaml`; inputs need to be in the index.
- `astra-validation-report/1` is the report's dataclasses as JSON: `shape`, `root`, `valid`,
  sorted `diagnostics` with a `location` (file, pointer, line, column, key, commit, url) and
  `related`, and an `unchecked` that stays empty while astra-tools declares every validator
  code of the installed `rules.json`. Exit 1 is an answer you won't like
  (a broken `MUST`, a result that isn't `unchanged`); exit 2 means astra couldn't answer.
- A command's module is imported when it runs, or when `--help` lists it; `api` brings in the
  whole core library, and rich comes only with text output.
- Codes, levels and statements are read at run time from astra-spec's `astra.schema`
  (`rules.json`, the JSON Schemas), with astra-tools' three own codes beside them, and a
  schema error gets its code from its keyword's absolute location.
- Every command on an analysis runs read, load, contract, bind, then rules, plan, view or
  check, entered through `api.py`; each layer can be called by hand. The later layers aren't
  pure: they read through the stack's readers, and `rules/commits.py` through the cache.
- The cache is a folder of plain files, made only when needed: `remotes` (a bare repository
  per URL, a ref per commit, blobs fetched as they are read where the remote honours the
  filter, and never offline) whenever a stack is bound, and `validity` (verdicts on analyses
  from a commit) whenever the rules run, then `hashes`, `worktrees` and `papers`. It is
  trusted, and safe to delete.
