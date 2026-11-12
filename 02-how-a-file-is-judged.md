# 2. How a file is judged: parse, schema, validator

Break the example analyses on purpose, one layer at a time, and read what comes back: the code,
the place, the level, the exit code. Then follow each verdict into astra-tools' source: `load.py`
for the parse layer, `contract.py` and `rules.json` for the schema layer, `rules/` for the
validator layer, and `check_record` for records.

## Setup

```console
$ cd ~/Projects/LightconeResearch/astra-tour
$ source env.sh
astra: …/astra-tools/.venv/bin/astra (astra, version 0.2.19.dev…)
work:  …/tour/work
$ python3 --version
Python 3.14.8
$ sh setup/02.sh
1. noisy-line is built and committed
  noisy-line c94c7b063ef9 Generate noisy points around a line
  noisy-line 2c5197a98df7 Build the points
…
8. line-fit declares noisy-line's newest commit, and is built again
  line-fit 907af16f9526 Read noisy-line's points with 6 outliers
  line-fit e889cebaabe4 Build the fits and their comparison with 6 outliers
two-names 041f343e9bf6 One result, reached through two chains of declarations
```

(Steps 2 to 7 of the build are cut, at the `…`.)

The commit ids hold only where `python3 --version` prints 3.14 (any patch release) after
`source env.sh`: run.py's records name the `python3` on PATH by its version
(`examples/run.py:149-158`). The README's *Before you start* says how to get 3.14. With another
version the setup ends with a line saying so, and every id from `Build the points` on differs:
in the setup's output, in step 1's `git log`, in step 6's `2dcf20f…`, and the commit named in
step 7's `REMOTE_UNREACHABLE` and in Try 4. Every code, message, line and column is the same.

`work/02/` now holds:

- `build/noisy-line` and `build/line-fit`: the examples, built by `build.py` with their
  eight-step history. line-fit's ids differ from the examples README's, since line-fit names
  noisy-line by its absolute `file://` URL, here under `work/02/build`. So they are the
  chapter's only with the tour in its own folder (the README's *Paths*).
- `two-names/`: astra-spec's conformance case 056, a result with two names, for step 7.
- `judge.py`: about 50 lines that run the parse and schema layers on one file, as astra-tools does
  inside, and print each schema error's absolute keyword location. Read it before step 4.

Every step breaks a file and puts it back with `git checkout`. `git status --short` in either
repository should print nothing between steps. Some JSON below is filtered with jq; if it isn't
on PATH: `jq() { nix shell 'nixpkgs#jq' --command jq "$@"; }`.

## 1. The verdict and its shape

A valid analysis first, to see the report's parts and the exit codes.

```console
$ cd work/02/build/noisy-line
$ git status --short; git log --oneline -1
2dcf20f Build the points with 6 outliers
$ astra validate; echo "exit $?"
astra.yaml: valid, 0 error(s), 0 warning(s)
exit 0
$ astra validate --json
{
  "shape": "astra-validation-report/1",
  "root": "astra.yaml",
  "valid": true,
  "diagnostics": [],
  "unchecked": []
}
$ astra validate ..; echo "exit $?"
astra: .. has no astra.yaml file: give the folder of an analysis
exit 2
```

What to notice:

- `valid` isn't stored: it is "no diagnostic is an error". Warnings never change it
  ([Rules](https://astra-spec.org/0.1/specification/#rules) *valid*).
- `unchecked` is empty: this build checks every validator code (step 7).
- The shape `astra-validation-report/1` and the exit codes are astra-tools' own (design §4.11,
  §4.12; chapter 1, steps 2 and 3): 0 valid, 1 a `MUST` broken, 2 when there is nothing to
  validate or the environment is broken. PATH is the analysis's folder; nothing is searched
  for, so `..` (that is, `work/02/build`) holds no analysis: exit 2, a broken invocation, not
  an invalid analysis.

Under the hood:

- `astra validate` calls `api.validate` (`src/astra/cli/validate.py:26`). It finds the
  repository that holds PATH and reads its working tree through a `WorktreeReader`
  (`src/astra/api.py:251-258`: the repository at 251, the reader at 255 outside one, 257
  inside); with no `astra.yaml` there it raises `NoAnalysisError`
  (`src/astra/api.py:261`), which `environment()` prints as `astra: …` with exit 2
  (`src/astra/cli/__init__.py:94`).
- `validate.validated` (`src/astra/validate.py:75`) is the whole pipeline: the catalogue from
  `rules.json` (81), binding, which loads and schema-checks every file of the stack (82), the
  validator rules (94), duplicates dropped (97), and a sort by commit, file, line, column, then
  code (98).
- `valid` is `src/astra/validate.py:39-41`; exit 1 is `src/astra/cli/validate.py:28-29`.

## 2. The parse layer: YAML that isn't, and a top level that isn't a map

A file is read before it is judged (YAML 1.2, core schema, content a map: `INVALID_SYNTAX`).
Break it as YAML, then as a map.

```console
$ perl -pi -e 's/inputs: \[config\]/inputs: [config/' astra.yaml
$ astra validate; echo "exit $?"
astra.yaml
  18:11 error INVALID_SYNTAX this isn't YAML 1.2 as Annex A reads it: while parsing a flow sequence expected ',' or ']', but got ':'
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit 1
$ astra validate --json | jq -c '.diagnostics[].location'
{"file":"astra.yaml","pointer":"","line":18,"column":11,"key":null,"commit":null,"url":null}
$ git checkout -q astra.yaml
$ perl -pi -e 's/^(?=.)/  /; s/^  /- / if $. == 1' astra.yaml
$ head -4 astra.yaml
- spec_version: "0.1.0"

  inputs:
    config:
$ astra validate
astra.yaml
  1:1 error INVALID_SYNTAX the top level is a list: an astra.yaml is a map
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ perl -pi -e 's/^(    label: Noisy points)$/$1\n    label: Points/' astra.yaml
$ astra validate
astra.yaml
  12:5 error INVALID_SYNTAX the key `label` is twice in one map, and YAML 1.2 allows a key once
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ perl -pi -e 's/^(    label:) Noisy points/$1 2026-11-09/' astra.yaml
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ git checkout -q astra.yaml
```

The second edit indents every non-empty line and makes the first a list item: valid YAML, a
list holding the whole analysis.

What to notice:

- One diagnostic each time: a file that breaks a parse rule is checked no further (design §4.13
  case 1). The schema never sees it.
- The pointer is `""`: a parse code is reported for the whole file. The line and column are
  astra-tools' extra, the loader's *problem* mark: where it noticed, the `:` after `recipe` on
  line 18, not where the `[` opened on line 17.
- The list is valid YAML, so the loader raises nothing: astra-tools tests the top node itself,
  after composing, and places the error there, at 1:1.
- A repeated key is `INVALID_SYNTAX`, not a code of its own: `DUPLICATE_KEY` left the
  specification (design §3).
- `label: 2026-11-09` is valid: a string, as the core schema's table reads it. ruamel's own
  resolver would make it a date, which the JSON check below would then refuse.

Under the hood:

- `load_yaml` (`src/astra/load.py:99`): ruamel's safe loader with `pure=True` (101: the C
  extension bundles libyaml 0.1.7, which refuses `{url: https://…}`), and `_CoreSchema` as the
  resolver (102), holding YAML 1.2.2's table and nothing else (34-45). These are design §4.1's
  settings, configuration rather than patches.
- `compose` (104) builds the node tree before any value. An empty stream (105-107) and a top
  node that isn't a mapping (108-112) are refused there.
- A `DuplicateKeyError` (116-119) and any other loader error (120-121) go through `_fail`
  (127-139), which prefers `problem_mark` to `context_mark` (133).
- `_check_json` (142-160) then walks the value for what JSON can't hold: a key that isn't a
  string, a number that isn't finite, a value of a tag beyond the core schema's.
- `stack._check` (`src/astra/stack.py:298-308`) catches the `ParseError`, places it at
  pointer `""` (306), and returns no document, so the contract is never called.

## 3. The schema layer: pointer, line, column, key

A file that parses is checked against `analysis.schema.json`
([Schema files](https://astra-spec.org/0.1/specification/#schema-files)). Five
breaks, five codes: an empty list and an empty map share one.

```console
$ perl -pi -e 's/      command:/      comand:/' astra.yaml
$ astra validate
astra.yaml
  19:7 error MISSING_FIELD `recipe` lacks `command`
  19:7 error UNKNOWN_FIELD `comand` isn't a field here
astra.yaml: invalid, 2 error(s), 0 warning(s)
$ astra validate --json | jq -c '.diagnostics[] | {code, pointer: .location.pointer, line: .location.line, column: .location.column, key: .location.key}'
{"code":"MISSING_FIELD","pointer":"/outputs/points/recipe","line":19,"column":7,"key":null}
{"code":"UNKNOWN_FIELD","pointer":"/outputs/points/recipe","line":19,"column":7,"key":"comand"}
$ git checkout -q astra.yaml
$ perl -pi -e 's/inputs: \[config\]/inputs: config/' astra.yaml && astra validate
astra.yaml
  17:13 error WRONG_TYPE `inputs` is a string, where it takes a list
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ perl -pi -e 's/^  points:/  Points:/' astra.yaml && astra validate
astra.yaml
  10:3 error INVALID_ID the key `Points` doesn't match `^[a-z][a-z0-9_]*$`
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ astra validate --json | jq -c '.diagnostics[] | {code, pointer: .location.pointer, line: .location.line, column: .location.column, key: .location.key}'
{"code":"INVALID_ID","pointer":"/outputs","line":10,"column":3,"key":"Points"}
$ git checkout -q astra.yaml
$ perl -pi -e 's/inputs: \[config\]/inputs: []/' astra.yaml && astra validate
astra.yaml
  17:13 error EMPTY_COLLECTION `inputs` is empty
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ perl -0pi -e 's/^outputs:\n.*/outputs: {}\n/ms' astra.yaml && astra validate
astra.yaml
  9:10 error EMPTY_COLLECTION `outputs` is empty
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
```

The last edit replaces the whole `outputs:` map, to the end of the file, with `outputs: {}`.

What to notice:

- One typo, two rules: `UNKNOWN_FIELD` for `comand` and `MISSING_FIELD` for `command`, as
  `recipie` gave in chapter 1's step 2. Both subjects are determined, so both are reported (the
  opening paragraph of design §4.13; only a file's parse rules are exempt).
- The places are astra-tools' (design §3, *Where*); the specification doesn't place a schema
  error. An unknown field is at its object, naming the field (`"key":"comand"`); an error on a
  key at its map, naming the key (`INVALID_ID` at `/outputs`, `"key":"Points"`); every other
  error at the value that fails.
- So are the line and column: the key's node where a key is named, otherwise the value's
  node. A block map's node starts at its first key, so `MISSING_FIELD` on `recipe` is at
  19:7, the `comand` line, not at `recipe:` on line 18. An empty flow map's starts at its `{`:
  9:10.
- `inputs: []` and `outputs: {}` are both `EMPTY_COLLECTION`, from two keywords: `minItems` on
  a list, `minProperties` on a map (step 4 shows the keywords behind each code).
- The messages are astra-tools' words, written per keyword. jsonschema's own show only through
  the fallback at `src/astra/contract.py:256`, which no keyword of the 0.1 schemas reaches.
- The report is sorted by place, then code: `MISSING_FIELD` before `UNKNOWN_FIELD`.

Under the hood:

- `stack._check` hands the document to `Contract.check_analysis`
  (`src/astra/contract.py:87`), which calls `_check("analysis", …)` at 96 (`_check` is defined
  at 113).
- `_check` takes every error `iter_errors` gives (116), not the first, and places each through
  `Document.position` (`src/astra/load.py:80-96`), which walks the composed node tree along the
  error's path, to the key's node where a key is named.
- `_explained` (`src/astra/contract.py:219-257`) writes each message: one diagnostic per
  unknown field for `additionalProperties` (230-232), a key's message for an error under
  `propertyNames` (228-229), and one wording for `minItems` and `minProperties` (239-240).
  `propertyNames` and `if` never reach the fallback (255-256): jsonschema descends into
  `propertyNames` and reports `pattern`, and tests `if` silently and reports the keyword inside
  `then`, such as `required`.

## 4. From an error to its code

The code isn't in the error: it is looked up in `rules.json`'s `errors`, keyed by the error's
absolute keyword location: `rules.json` gives "the code of each schema keyword whose error can
fail a file" ([Schema files](https://astra-spec.org/0.1/specification/#schema-files)).
`judge.py` shows the lookup.

```console
$ perl -pi -e 's/      command:/      comand:/' astra.yaml
$ python ../../judge.py astra.yaml
parse    ok: a JSON value
keyword  /outputs/points/recipe  https://w3id.org/astra/dev/analysis.schema.json#/$defs/Recipe/additionalProperties  UNKNOWN_FIELD
keyword  /outputs/points/recipe  https://w3id.org/astra/dev/analysis.schema.json#/$defs/Recipe/required  MISSING_FIELD
report   UNKNOWN_FIELD at /outputs/points/recipe 19:7 key comand: `comand` isn't a field here
report   MISSING_FIELD at /outputs/points/recipe 19:7: `recipe` lacks `command`
$ git checkout -q astra.yaml
$ python -c 'from astra.diagnostics import Catalogue; c = Catalogue.load(); print(c.version, "|", len(c.errors), "error locations"); by = {}; [by.setdefault(code, set()).add(key.rpartition("/")[2]) for key, code in c.errors.items()]; [print(code, *sorted(kws)) for code, kws in sorted(by.items())]'
ASTRA rule catalogue, schema version dev | 296 error locations
DUPLICATE_ENTRY uniqueItems
EMPTY_COLLECTION minItems minProperties
INVALID_COMMIT pattern
INVALID_DECLARATION_SOURCE if oneOf required
INVALID_EVIDENCE_SOURCE if not oneOf required
INVALID_ID pattern propertyNames
INVALID_IMPORT if not required
INVALID_PATH pattern
INVALID_REFERENCE pattern
INVALID_SWITCH if not required
INVALID_VALUE enum minimum pattern
MISSING_FIELD if required
UNKNOWN_FIELD additionalProperties
URL_WITHOUT_COMMIT if required
WRONG_TYPE type
```

The last command groups the 296 keys by code and prints the keyword (the key's last segment)
behind each.

What to notice:

- A keyword location is the schema's `$id`, `#`, the pointer to the failing subschema once
  every `$ref` is resolved (`$defs/Recipe`, not a path through `outputs`), then the keyword.
  Step 3's empty map is `…#/properties/outputs/minProperties`, its empty list
  `…#/$defs/Output__identifier_optional/properties/inputs/minItems`.
- The `$id` says `/dev/`, as chapter 1's step 6 showed: a release's say `/0.1/`, so each key
  names its minor version ([Schema files](https://astra-spec.org/0.1/specification/#schema-files)).
- 296 locations, every one a schema-layer code. The map is many to one: every `type` keyword is
  `WRONG_TYPE`, every `required` outside an `allOf` check `MISSING_FIELD`, and so is the one
  inside the check that an output other than a switch has a `type`, a `format` and a `recipe`. A
  keyword alone doesn't give the code: `pattern` is one of five codes, by where it sits.
- `if` and `propertyNames` are keys too, beside the keywords inside them. rules.json gives a
  code to both places; jsonschema reports only the keyword inside (`required` under a `then`,
  `pattern` under `propertyNames`), so astra-tools never looks up an `if` or a `propertyNames`
  key. Nor the four `required` keys inside a `oneOf` branch (`INVALID_DECLARATION_SOURCE`,
  `INVALID_EVIDENCE_SOURCE`): a failing `oneOf` is one error, at the `oneOf`. A declaration
  with neither `path` nor `url` gives `judge.py` the key `…/allOf/0/then/oneOf`.
- The `keyword` lines come in jsonschema's order; the `report` lines are what astra-tools makes
  of them, before `validate` sorts them.

Under the hood:

- `Contract.load` (`src/astra/contract.py:75-85`) makes one `Draft201909Validator` per schema,
  with `pattern` replaced (79-80) by one that matches as ECMA-262 does (152-180, design §4.1),
  and `_index` (138-149), the JSON Pointer of every object in the schema by its `id()` (84).
- `_check` (117-121) finds the failing subschema's pointer by the identity of `error.schema`,
  adds `error.validator`, the keyword, and looks the result up in `catalogue.errors`. jsonschema
  hands back the very dict it validated with, `$ref` resolved, and the validator keeps the
  schema alive so that no `id()` is reused (65).
- A location missing from `errors` raises `LookupError` (120-121), which the CLI prints as an
  internal error, exit 2 (`src/astra/cli/__init__.py:70-75`): astra-tools and astra-spec
  disagree.
- `Catalogue.load` (`src/astra/diagnostics.py:104-120`) reads `rules.json` from the installed
  `astra.schema` package at run time; nothing is copied into astra-tools.

## 5. What stops what: a schema error, the version, the repository

Each layer gates the next. Three gates, and what each hides. Chapter 1 met the version gate
(its Try 1) and `NOT_IN_REPOSITORY` (its step 3) on the scaffold; here each hides a breach.

```console
$ perl -pi -e 's/path: config.json/path: settings.json/; s/      command:/      comand:/' astra.yaml
$ astra validate
astra.yaml
  19:7 error MISSING_FIELD `recipe` lacks `command`
  19:7 error UNKNOWN_FIELD `comand` isn't a field here
astra.yaml: invalid, 2 error(s), 0 warning(s)
$ perl -pi -e 's/      comand:/      command:/' astra.yaml && astra validate
astra.yaml
  7:11 error MISSING_INPUT_FILE `settings.json` names no file, and no stand-in of Git LFS, git-annex, DVC
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ perl -pi -e 's/"0.1.0"/"0.2.0"/; s/      command:/      comand:/' astra.yaml && astra validate
astra.yaml
  1:15 error UNSUPPORTED_SPEC_VERSION spec_version 0.2.0 is ASTRA 0.2, and this astra-tools reads ASTRA 0.1 alone
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ perl -pi -e 's/"0.2.0"/"0.1"/' astra.yaml && astra validate
astra.yaml
  1:15 error INVALID_VALUE `spec_version` doesn't match `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`: "0.1"
  19:7 error MISSING_FIELD `recipe` lacks `command`
  19:7 error UNKNOWN_FIELD `comand` isn't a field here
astra.yaml: invalid, 3 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ grep -A2 '^analyses' ../../examples/line-fit/astra.yaml
analyses:
  noisy:
    url: file:///path/to/noisy-line
$ astra validate ../../examples/line-fit
astra.yaml
  error NOT_IN_REPOSITORY the analysis's folder isn't in the working tree of a git repository: make one with `git init`, or move the analysis into one
astra.yaml: invalid, 1 error(s), 0 warning(s)
```

What to notice:

- With a schema error in the file, the missing `settings.json` isn't reported at all: a file
  that isn't a valid document isn't checked by the validator layer (design §4.13 case 2). Fix
  the schema error and it appears.
- `"0.2.0"` is well formed and outside 0.1: astra-tools' own `UNSUPPORTED_SPEC_VERSION`, and
  the schema isn't run, so the typo stays hidden (case 1's last sentence).
- `"0.1"` is malformed, so the file goes to the 0.1 schema, which reports the version as
  `INVALID_VALUE` and the typo beside it (case 1).
- `examples/line-fit` is the unbuilt source, in no repository, declaring a placeholder URL at
  commit `000…0`. Only `NOT_IN_REPOSITORY` is reported, for the whole file: its declaration
  isn't followed, so nothing is fetched (case 11). This holds while git sees no repository above
  `work/`: the tour folder is one, which `env.sh`'s `GIT_CEILING_DIRECTORIES` hides (the README's
  *Paths*).

Under the hood:

- `bind` (`src/astra/stack.py:242`): `read()` (254-266) loads and checks each file and keeps
  no `analysis` where any diagnostic was found (262). A root with no analysis, or in no
  repository, returns `Bound(None, …)` at once (270-271): no declaration followed, no address
  resolved.
- `validated` runs the rules only where there is a stack, and reports `NOT_IN_REPOSITORY`
  itself, at pointer `""` with no line (`src/astra/validate.py:84-94`).
- For a declared analysis, `Stack.determined()` (`src/astra/stack.py:206-211`) yields only the
  valid files, so no rule reads an invalid one, and the declaration's outcome becomes `invalid`
  (283-284).
- The version gate is `Contract.check_analysis` (`src/astra/contract.py:89-96`). `_version`
  (131-135) takes only a well-formed string, so `0.1`, unquoted `0.1` and a missing version all
  fall through to the schema.

## 6. The validator layer: the stack and git

Now break what only the validator sees: files on disk and in git (`MISSING_INPUT_FILE`,
`INPUT_NOT_TRACKED`), addresses (`UNRESOLVED_ADDRESS`), and the outputs' graph
(`OUTPUT_CYCLE`).

```console
$ perl -pi -e 's/path: config.json/path: settings.json/' astra.yaml && astra validate
astra.yaml
  7:11 error MISSING_INPUT_FILE `settings.json` names no file, and no stand-in of Git LFS, git-annex, DVC
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ cp config.json settings.json && astra validate
astra.yaml
  7:11 error INPUT_NOT_TRACKED `settings.json` isn't tracked in the repository that holds this analysis: `git add` it (a file kept in a submodule is never tracked here, §7)
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git add settings.json && astra validate; echo "exit $?"
astra.yaml: valid, 0 error(s), 0 warning(s)
exit 0
$ git rm -q --cached settings.json && rm settings.json && git checkout -q astra.yaml && git status --short
$ cd ../line-fit
$ perl -pi -e 's/inputs: \[noisy.points\]/inputs: [noisy.point]/' astra.yaml && astra validate
astra.yaml
  27:14 error UNRESOLVED_ADDRESS `noisy.point` names nothing: `noisy` has no input or output `point`
  30:16 error UNDECLARED_TEMPLATE_REF `{inputs.noisy.points}` isn't a placeholder of this output: it takes `{inputs}`, `{output}`, and `{inputs.<entry>}` and `{decisions.<entry>}` for an entry of its `inputs` or `decisions` as written; `{{` and `}}` are literal braces
astra.yaml: invalid, 2 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ perl -pi -e 's/inputs: \[noisy.points\]/inputs: [noisy.points, comparison]/' astra.yaml && astra validate
astra.yaml
  27:28 error OUTPUT_CYCLE `fit` depends on itself through `comparison`: `fit` → `comparison` → `fit`
  36:14 error OUTPUT_CYCLE `comparison` depends on itself through `fit#ols`: `comparison` → `fit` → `comparison`
  36:23 error OUTPUT_CYCLE `comparison` depends on itself through `fit#huber`: `comparison` → `fit` → `comparison`
astra.yaml: invalid, 3 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ python -c 'from astra import rules; [print(m.__name__, *sorted(m.CODES)) for m in rules.MODULES]'
astra.rules.names UNRESOLVED_ADDRESS
astra.rules.inputs INPUT_IN_ANOTHER_ANALYSIS INPUT_NOT_TRACKED MISSING_INPUT_FILE RESERVED_PATH
astra.rules.decisions UNKNOWN_OPTION
astra.rules.outputs AMBIGUOUS_ID OUTPUT_CYCLE
astra.rules.recipes UNDECLARED_TEMPLATE_REF
astra.rules.universes DERIVED_FROM_CYCLE EXCLUDED_OPTION_SELECTED INACTIVE_DECISION INCOMPATIBLE_OPTIONS MISSING_REQUIRED_OPTION UNKNOWN_DERIVED_FROM UNUSED_DECISION
astra.rules.pins PIN_NOT_BUILT
astra.rules.insights INVALID_INSIGHT_REF
astra.rules.declarations CLASHING_RESULT_NAME DECLARATION_OUTSIDE_REPOSITORY MISSING_DECLARED_ANALYSIS
astra.rules.driving DUPLICATE_ELEMENT LOOPING_KEY MISSING_DECISION NOT_BUILT_IN_UNIVERSE RESULT_IN_TWO_PLACES UNDRIVEN_DECLARATION UNKNOWN_PIN_UNIVERSE
astra.rules.commits COMMIT_NOT_ANCESTOR COMMIT_NOT_FOUND DECLARED_ANALYSIS_INVALID REMOTE_UNREACHABLE
```

What to notice:

- `MISSING_INPUT_FILE` alone: a file that isn't there is never also reported as untracked
  (design §4.13 case 8).
- Tracked means in the index: staging the file is enough, with no commit. Chapter 1's Try 3
  took the same three steps on the scaffold.
- `noisy.point` is resolved through the declaration, in noisy-line's `astra.yaml` at
  `2dcf20f…`, read from the commit astra-tools fetched into its cache; that file has no
  `point`.
- One edit, two rules again: the command's `{inputs.noisy.points}` no longer names an entry as
  written, so `UNDECLARED_TEMPLATE_REF` comes with `UNRESOLVED_ADDRESS`.
- One cycle, three diagnostics: `OUTPUT_CYCLE` at each entry of `inputs` that lies on it
  (`src/astra/rules/outputs.py:44-45`). How often a breach is reported is astra-tools' own
  (design §3). Design §4.13 case 13 says "The breach is reported once, as `OUTPUT_CYCLE`";
  astra-tools reads "once" as "by no other rule" (`src/astra/rules/outputs.py:11`: "reported as
  `OUTPUT_CYCLE` alone"). That is its reading, not the design's words, which could be reworded
  to match.
- The rule modules: one per section of the long specification whose codes table states them
  (design §4.4), each declaring the codes it reports.

Under the hood:

- `rules.check` (`src/astra/rules/__init__.py:55-61`) runs each module of `MODULES` (37) on one
  `Context`; `commits` runs first, since its findings decide which of the others' get a related
  declaration (59-61).
- `Context` (`src/astra/rules/context.py`) computes what `universes.py` derives once each, as
  `cached_property`s (50-154), and holds the design §4.13 predicates the rules consult before
  reporting (156-209).
- `inputs._inputs` (`src/astra/rules/inputs.py:43-76`) asks git once for every input's path
  (54; one `git ls-files --stage`, `src/astra/sources/git.py:91`), then per input: `_no_file`
  (62) gives `MISSING_INPUT_FILE` (64), and only otherwise `INPUT_NOT_TRACKED` (65-73).
- Addresses are resolved once, at binding (`src/astra/stack.py:452-472`); `names.check`
  (`src/astra/rules/names.py:26-31`) reports each that resolved to nothing, unless it went
  through an undetermined analysis.
- `outputs._cycles` (`src/astra/rules/outputs.py:43-55`) looks, from each entry, for the
  shortest path back to the output that lists it, and reports at the entry's pointer.

## 7. Errors and warnings, astra-tools' own codes, `unchecked`

The level comes from the catalogue: a `MUST` broken is an error, a `SHOULD` a warning
([Rules](https://astra-spec.org/0.1/specification/#rules)). Then the three codes that aren't the
specification's, and what `unchecked` counts.

```console
$ astra validate ../../two-names; echo "exit $?"
astra.yaml
  4:5 warning RESULT_IN_TWO_PLACES the result of `output1` in `u1` and `u2` has two names, `stage.inner.output1` and `inner.output1`, since those universes drive two chains of declarations to its analysis, through this one and through the related one: drive it through one chain only
  6:5 warning RESULT_IN_TWO_PLACES the result of `output1` in `u1` and `u2` has two names, `stage.inner.output1` and `inner.output1`, since those universes drive two chains of declarations to its analysis, through this one and through the related one: drive it through one chain only
astra.yaml: valid, 0 error(s), 2 warning(s)
exit 0
$ astra validate --json ../../two-names | jq -c '.diagnostics[] | {level, pointer: .location.pointer, related: [.related[].pointer]}'
{"level":"warning","pointer":"/analyses/stage","related":["/analyses/inner"]}
{"level":"warning","pointer":"/analyses/inner","related":["/analyses/stage"]}
$ astra rules | grep -A3 "astra-tools' own"
validator, astra-tools' own
  UNSUPPORTED_SPEC_VERSION MUST Every `astra.yaml` of the stack states a `spec_version` whose minor version astra-tools has the schema of (0.1)
  REMOTE_UNREACHABLE MUST Every commit the stack gets from a remote (§17) can be got
  COMMIT_NOT_ANCESTOR SHOULD A declaration with a `path` and a `commit` names, in the repository that holds the declaring file, an ancestor of the commit the declaration is in or, read in the working tree, HEAD or an ancestor of it
$ perl -pi -e 's|url: file://.*|url: file:///nowhere/noisy-line|' astra.yaml && astra validate
astra.yaml
  5:5 error REMOTE_UNREACHABLE the commit `2dcf20f515e3eecf7e2126c182c54dd5f0f8f206` can't be fetched from `file:///nowhere/noisy-line`, and no earlier fetch kept it: check the URL and the commit, and that git can reach the remote (with --offline, nothing is fetched)
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
$ python -c 'from astra.diagnostics import Catalogue; from astra.validate import unchecked; c = Catalogue.load(); print(len(c.codes("validator")), unchecked(c))'
34 ()
```

What to notice:

- `RESULT_IN_TWO_PLACES` is a `SHOULD`
  ([Rules](https://astra-spec.org/0.1/specification/#rules)): a warning, the
  analysis stays valid, exit 0. `astra plan` shows the same fact as a `two_names` note, which is
  no diagnostic (design §4.6).
- It is reported at the first declaration of each chain that the other doesn't go through
  (here, where each chain starts), the other's as `related`
  (`src/astra/rules/driving.py:291-294`). Where a breach is reported is astra-tools' own
  (design §3).
- astra-tools' own three codes are listed apart, with their levels (design §3, `diagnostics.py`;
  chapter 1's step 6 met them). The first two are errors because without them the stack can't
  be read.
- `REMOTE_UNREACHABLE` is at the declaration (`/analyses/noisy`), and it is the only error:
  `noisy.points` isn't reported as unresolved, since the analysis it goes through is
  undetermined (design §4.13 cases 3 and 4). No network is used: `file:///nowhere` fails
  locally.
- `unchecked` is the catalogue's validator codes (31 from `rules.json`, 3 of astra-tools') that
  no module declares: none in this build (chapter 1, step 2). It describes the build, not the
  analysis. A rule that design §4.13 leaves unchecked on one subject is listed nowhere: it
  simply isn't reported, as in steps 5 and 6.

Under the hood:

- `Catalogue.level` (`src/astra/diagnostics.py:139-141`) is where error or warning is decided;
  `Catalogue.find` (122-124) looks in `rules.json`, then in `OWN` (60-90), and a code in
  neither makes `Catalogue.rule` raise `LookupError` (126-132), an internal error.
- `driving._two_places` (`src/astra/rules/driving.py:276-302`) makes the warning, with the
  other declaration as related place (302).
- `stack._follow` asks the cache's remote store for the URL and commit
  (`src/astra/stack.py:328-332`); none means the outcome `unreachable`, and `commits.check`
  reports it (`src/astra/rules/commits.py:63-77`). The store is a bare repository per URL,
  filled by `git fetch --filter=blob:none` (`src/astra/sources/remote.py:3-5`; chapter 1's
  step 8 opens one, chapter 5 follows it in full). `Remotes.get`
  asks it at 47: a commit it already keeps, or else a fetch (`Repository.fetch`,
  `src/astra/sources/git.py:150-156`), unless `--offline`.
- `unchecked` is `src/astra/validate.py:62-65`; the text report mentions it only when it isn't
  empty (`src/astra/cli/text/validate.py:21-24`).

## 8. Records: the same two layers, behind `INVALID_RECORD`

A record ([Results](https://astra-spec.org/0.1/specification/#results) *record*) is read by the
same `load` and `contract`, but the checker reports what it breaks as `INVALID_RECORD`, which
leaves the result `missing` ([Rules](https://astra-spec.org/0.1/specification/#rules)).

```console
$ cd ../noisy-line
$ astra check; echo "exit $?"
.astra/records/points.json  points  unchanged  present
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
exit 0
$ perl -pi -e 's/sha256:f207/sha256:F207/' .astra/records/points.json
$ astra check; echo "exit $?"
.astra/records/points.json  points  missing  absent
  error INVALID_RECORD (INVALID_VALUE) `content_hash` doesn't match `^sha256:[0-9a-f]{64}$`: "sha256:F207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47"
astra.yaml: 1 place(s) of planned results, 0 unchanged, 0 stale, 1 missing; 1 absent
exit 1
$ astra check --json | jq -c '.results[0].places[0] | {record_status, bytes_status, committed, reasons}'
{"record_status":"missing","bytes_status":"absent","committed":false,"reasons":[{"code":"INVALID_RECORD","level":"error","message":"`content_hash` doesn't match `^sha256:[0-9a-f]{64}$`: \"sha256:F207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47\"","location":{"file":".astra/records/points.json","pointer":"/content_hash","line":null,"column":null,"key":null,"commit":null,"url":null},"breaks":"INVALID_VALUE"}]}
$ python -c 'from astra import api; s = api.check().results[0].statuses[0]; print(s.record_status, s.bytes_status, [(r.code, r.breaks, r.location.pointer) for r in s.reasons])'
missing absent [('INVALID_RECORD', 'INVALID_VALUE', '/content_hash')]
$ python ../../judge.py .astra/records/points.json
parse    ok: a JSON value
keyword  /content_hash  https://w3id.org/astra/dev/provenance.schema.json#/properties/content_hash/pattern  INVALID_VALUE
report   INVALID_VALUE at /content_hash: `content_hash` doesn't match `^sha256:[0-9a-f]{64}$`: "sha256:F207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47"
$ git checkout -q .astra/records/points.json
$ perl -pi -e 's/"0.1.0"/"0.0.9"/' .astra/records/points.json && astra check
.astra/records/points.json  points  missing  absent
  error INVALID_RECORD records begin at 0.1.0: 0.0.9 has no schema
astra.yaml: 1 place(s) of planned results, 0 unchanged, 0 stale, 1 missing; 1 absent
$ git checkout -q .astra/records/points.json
$ rm results/points.csv && astra check; echo "exit $?"
.astra/records/points.json  points  unchanged  absent
  warning ABSENT_RESULT no file is at results/points.csv, the result's default place
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 1 absent
exit 0
$ git checkout -q results/points.csv && git status --short
```

What to notice:

- The schema code a record breaks comes in parentheses, `breaks` in the JSON: a field of
  astra-tools' `astra-check-report/1`, not of the specification.
- The bytes are `absent`, though `results/points.csv` is untouched: with no valid record there
  are no recorded bytes to find. There is no `ABSENT_RESULT` reason, since design §4.13 case 9
  leaves it unchecked for a `missing` result; the summary still counts one absent.
- A record's diagnostic has a pointer but no line or column, so the text shows no place. Only a
  JSON syntax error, from `json.loads`, would have one.
- `committed` is false: HEAD's record isn't, byte for byte, the one on disk.
- `0.0.9` has no record schema (records begin at 0.1), so it is
  `INVALID_RECORD` itself, with no `breaks`.
- `ABSENT_RESULT` is a check-layer `SHOULD`: a warning, and exit 0. `astra check`'s verdict
  looks at record statuses and errors, never at bytes.
- `api.check()` is what `astra check` prints: the same `Reason` objects, `breaks` included.

Under the hood:

- `_Checker.place` (`src/astra/check.py:291-341`) reads each place's record through
  `records.read_record` (301).
- `read_record` (`src/astra/records.py:128-148`) parses with `load_json` (139;
  `src/astra/load.py:163-172`, its hooks refusing a repeated name, 175-182, and `NaN` and
  `Infinity`, 185-186), then calls `Contract.check_record` (143).
- `check_record` (`src/astra/contract.py:98-106`) picks the schema by the version: below 0.1,
  `INVALID_RECORD` at once (102-104); above 0.1, the open schema (105-106); otherwise the closed
  one. A record has no node tree, so `Document.position` gives no line
  (`src/astra/load.py:80-96`).
- Each diagnostic becomes an `INVALID_RECORD` reason carrying the code it breaks
  (`src/astra/check.py:310-316`). `_bytes` gives `absent` with no reason where there is no
  record (527-528). The exit code follows `CheckReport.ok` (139-145).

## Try

Predict first: the code, the pointer, the line and column, the exit code. Then run, and open
the answer. Each answer ends by putting the file back.

### 1. Two required fields gone

In noisy-line, remove both `type:` and `format:` from `points`:

```sh
perl -ni -e 'print unless /^    (type|format): /' astra.yaml && astra validate
python ../../judge.py astra.yaml
```

How many diagnostics, at which line? How many raw errors does `judge.py` print?

<details><summary>Answer</summary>

```console
$ perl -ni -e 'print unless /^    (type|format): /' astra.yaml && astra validate
astra.yaml
  11:5 error MISSING_FIELD `points` lacks `type`, `format`
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ python ../../judge.py astra.yaml
parse    ok: a JSON value
keyword  /outputs/points  https://w3id.org/astra/dev/analysis.schema.json#/$defs/Output__identifier_optional/allOf/0/then/required  MISSING_FIELD
keyword  /outputs/points  https://w3id.org/astra/dev/analysis.schema.json#/$defs/Output__identifier_optional/allOf/0/then/required  MISSING_FIELD
report   MISSING_FIELD at /outputs/points 11:5: `points` lacks `type`, `format`
$ git checkout -q astra.yaml
```

- jsonschema gives one `required` error per missing field. `_explained` words each with every
  missing field, so the two diagnostics are equal and `dict.fromkeys` keeps one
  (`src/astra/contract.py:127-128`).
- 11:5 is the `points` map's first key, `label`, not `points:` at 10:3 (step 3).
- The `required` sits under `allOf/0/then`: an output needs `type`, `format` and `recipe` only
  if it isn't a switch (the `if` beside it), hence `MISSING_FIELD`'s `if` key in step 4.

</details>

### 2. A format written as a block scalar

```sh
perl -pi -e 's/^    format: csv/    format: |\n      csv/' astra.yaml && astra validate
```

`format: |` then `csv` on the next line. Valid?

<details><summary>Answer</summary>

```console
$ perl -pi -e 's/^    format: csv/    format: |\n      csv/' astra.yaml && astra validate
astra.yaml
  16:13 error INVALID_VALUE `format` doesn't match `^[a-z0-9][a-z0-9_.+-]*$`: "csv\n"
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ python -c 'import re; print(bool(re.search(r"^[a-z0-9][a-z0-9_.+-]*$", "csv\n")))'
True
$ git checkout -q astra.yaml
```

- A literal block scalar keeps its final line break, so the value is `"csv\n"`.
- Python's `re` lets `$` match before a final line break, so stock jsonschema would pass it.
  astra-tools' `pattern` rewrites each `$` outside a character class as `\Z`, as ECMA-262 reads
  it (design §4.1, `src/astra/contract.py:162-180`).

</details>

### 3. An empty map of inputs

Replace the whole `inputs:` map with `inputs: {}`:

```sh
perl -0pi -e 's/inputs:\n  config:\n.*?path: config.json\n/inputs: {}\n/s' astra.yaml && astra validate
```

`EMPTY_COLLECTION`? Which layer reports what, and where?

<details><summary>Answer</summary>

```console
$ perl -0pi -e 's/inputs:\n  config:\n.*?path: config.json\n/inputs: {}\n/s' astra.yaml && astra validate
astra.yaml
  13:14 error UNRESOLVED_ADDRESS `config` names nothing: this analysis has no input or output `config`
astra.yaml: invalid, 1 error(s), 0 warning(s)
$ git checkout -q astra.yaml
```

- `EMPTY_COLLECTION` covers `outputs`, `options`, `cases`, `evidence` and every list of
  strings (its row in [Rules](https://astra-spec.org/0.1/specification/#rules)), not `inputs`,
  so the file is a valid document. The schema has a `minProperties` on `outputs` (step 3's
  `outputs: {}`) and none on `inputs`.
- The validator then finds that `points`' entry `config` names nothing (13:14, the file is
  four lines shorter). The command's `{inputs.config}` still matches that entry as written, so
  no `UNDECLARED_TEMPLATE_REF`.

</details>

### 4. A cycle, under the checker

In line-fit, make the cycle of step 6 again, and run `astra check` instead of `validate`:

```sh
cd ../line-fit
perl -pi -e 's/inputs: \[noisy.points\]/inputs: [noisy.points, comparison]/' astra.yaml && astra check; echo "exit $?"
```

Which planned results get statuses? Does `points` get a bytes status?

<details><summary>Answer</summary>

```console
$ cd ../line-fit
$ perl -pi -e 's/inputs: \[noisy.points\]/inputs: [noisy.points, comparison]/' astra.yaml && astra check; echo "exit $?"
astra.yaml
  27:28 error OUTPUT_CYCLE `fit` depends on itself through `comparison`: `fit` → `comparison` → `fit`
  36:14 error OUTPUT_CYCLE `comparison` depends on itself through `fit#ols`: `comparison` → `fit` → `comparison`
  36:23 error OUTPUT_CYCLE `comparison` depends on itself through `fit#huber`: `comparison` → `fit` → `comparison`
astra.yaml: invalid, 3 error(s), so only the results it leaves determined; 0 place(s) of planned results, 0 unchanged, 0 stale, 0 missing; 0 absent
exit 1
$ git checkout -q astra.yaml
```

- `check` on an invalid analysis gives the errors first, then statuses for the results whose
  planning is determined (design §4.7). `fit` and `comparison` are on the cycle, so theirs isn't
  (design §4.13 cases 12 and 13).
- No result gets a status, not even `points`. line-fit plans from its own outputs, and
  noisy-line's `points` only because `fit` reads it (the short specification's Results
  *plans*); with `fit`'s planning undetermined, no planned result reads `points`.
- The finding that cites `comparison` gets no status, so no `STALE_EVIDENCE`: `comparison` is
  on the cycle, so whether it is built is undetermined, and design §4.13 case 12 gives no status
  to evidence citing a result whose planning isn't determined, as chapter 6's Try 1 shows for
  one a switch leaves undetermined. `_cited` (`src/astra/check.py:602-636`) tells that apart
  from an output that isn't built, which cites nothing and leaves the evidence `missing`. The
  summary's three errors are the validator's.
- Exit 1: the analysis breaks a `MUST`.

</details>

### 5. A record from a later minor version

Back in noisy-line, add a field the 0.1 record schema doesn't define, then claim a later
version:

```sh
cd ../noisy-line
perl -pi -e 's/^  "size": 1117,/  "size": 1117,\n  "note": "hello",/' .astra/records/points.json && astra check
perl -pi -e 's/"0.1.0"/"0.2.0"/' .astra/records/points.json && astra check
```

The status after each edit?

<details><summary>Answer</summary>

```console
$ cd ../noisy-line
$ perl -pi -e 's/^  "size": 1117,/  "size": 1117,\n  "note": "hello",/' .astra/records/points.json && astra check
.astra/records/points.json  points  missing  absent
  error INVALID_RECORD (UNKNOWN_FIELD) `note` isn't a field here
astra.yaml: 1 place(s) of planned results, 0 unchanged, 0 stale, 1 missing; 1 absent
$ perl -pi -e 's/"0.1.0"/"0.2.0"/' .astra/records/points.json && astra check
.astra/records/points.json  points  unchanged  present  not committed
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
$ git checkout -q .astra/records/points.json && git status --short
```

- At 0.1.0 the closed record schema refuses `note`: `missing`, at pointer `""` with key
  `note`, so no place in the text.
- At 0.2.0 the checker reads it by the open variant of its own record schema
  (`INVALID_RECORD`; the open variant is `provenance.open.schema.json`,
  [Schema files](https://astra-spec.org/0.1/specification/#schema-files)), and
  `Record.from_json` drops what 0.1 doesn't define (`src/astra/records.py:86-104`). Nothing
  compared has changed, so `unchanged`, but the file isn't HEAD's: `not committed`.

</details>

## What you now know

- Each file passes three layers in order, and each gates the next: a parse error stops the file
  (`load.py`), a schema error or `UNSUPPORTED_SPEC_VERSION` keeps the validator out of it and
  leaves its analysis undetermined (`stack.bind`), and only then do the rule modules judge the
  whole stack with git (`rules/`, one module per subject).
- A schema code is a lookup: the failing subschema's pointer, found by object identity, plus
  the keyword, in `rules.json`'s `errors`, which fixes the code
  ([Schema files](https://astra-spec.org/0.1/specification/#schema-files)); the place (the
  pointer and the key, design §3), the line and column, the words, the order, the exit codes
  and the JSON shapes are astra-tools'.
- Error or warning comes only from the catalogue's `MUST` or `SHOULD`; the three codes outside
  it are astra-tools' own, in `diagnostics.OWN`.
- `unchecked` lists the codes a build doesn't implement (none now). Design §4.13 is a different
  thing: a rule left unchecked on one subject because another breach leaves it undetermined, and
  never listed.
- A record goes through the same `load` and `contract`, by the schema its version picks, and
  whatever it breaks becomes `INVALID_RECORD`, leaving its result `missing`.
- Design §5 has no open question left, so no `OPEN(` reading lies on these paths, or on any.
