# A tour of astra-tools

Six chapters of commands to run in a terminal against astra-tools v0.1. Each one gives the real
output, what to notice in it, and how astra-tools produces it, with pointers into the source.
Each ends with exercises: predict, then run. Each chapter's setup script builds its state from
nothing, so any chapter can be started, or started again, on its own. Read them in order the
first time: later chapters point back to where something was first explained. The
specification isn't explained again: a chapter gives a one-line reminder and links the
section.

## Before you start

On NixOS (or anywhere with nix and flakes), once, with a network connection:

```bash
git clone <this repository> ~/Projects/LightconeResearch/astra-tour
cd ~/Projects/LightconeResearch/astra-tour
nix develop          # Python 3.14, uv, git, jq, perl, as the flake pins them
./bootstrap.sh       # astra-tools and astra-spec at the tour's commits, and astra-tools' environment
```

`bootstrap.sh` clones astra-tools and astra-spec into `repos/` (git-ignored), checks out
astra-tools `2a05099` and, beside it, astra-spec at the commit in its `astra-spec.pin`
(`69b35f4`), and builds astra-tools' environment with every extra and the dev tools. It clones
from GitHub; while those commits aren't there, name another remote that has them:

```bash
ASTRA_TOOLS_URL=<gitea>/astra-tools.git ASTRA_SPEC_URL=<gitea>/astra-spec.git ./bootstrap.sh
```

After that, nothing needs the network. For each chapter, in a new terminal:

```bash
cd ~/Projects/LightconeResearch/astra-tour
nix develop
source env.sh
```

Things to know before step 1:

- **Python 3.14.** `examples/run.py` writes the `python3` version into each record's
  environment (`urn:astra-examples:cpython-3.14`), so commit ids from the first commit that
  holds a record ("Build the points") onwards match the chapters only on 3.14, which the flake
  gives. On another version they differ, and the setups warn; codes, messages, places and the
  results' bytes don't.
- **One shell per chapter.** Run `source env.sh` from this folder at the start of each
  chapter. Chapter 1's step 8 and chapter 5's Setup move `ASTRA_CACHE_DIR`. Chapter 4's
  `source ../shell.sh` fixes a git identity and date until that shell closes.
- **Paths.** `…/tour` in the output stands for this folder's absolute path. Two kinds of
  output contain that path. One is line-fit's commit ids, because line-fit declares
  noisy-line by a `file://` URL. The other is the names of chapter 1's and chapter 5's cache
  stores. Both match the chapters only with the tour at
  `/home/r/Projects/LightconeResearch/astra-tour`; elsewhere they differ, and nothing else does.
  The chapters work in `work/`. This folder is a git repository, and chapters 1 and 2 need
  analyses with no repository above them, so `env.sh` sets `GIT_CEILING_DIRECTORIES` to this
  folder: from inside `work/`, git never looks as high as this folder's own repository.
- **Elided output.** The astra version string shows as `0.2.19.dev…`, and test timings as `…s`.
- **jq.** `nix develop` puts jq on PATH. Where a chapter says to get it through
  `nix shell 'nixpkgs#jq'`, you can skip that.
- **Citations.** `§n` and `Annex X` are the specification at astra-spec `69b35f4`, linked at
  astra-spec.org/0.1. `design §n` is astra-tools' `design/2026-11-07-v0.1-tooling-design.md`.
  `src/astra/<path>.py:<line>` points into astra-tools: its `src/` code is the same from
  `8813f52` to `2a05099`, and only docstring citations changed in between, each in place.
  `examples/…` is the tour's copy of astra-examples.
- **The specification versus astra-tools.** Each chapter says which is which. These are
  astra-tools' own: the three own codes, the plan's notes, the four JSON shapes, the exit
  codes, the cache, and when a rule goes unchecked (design §4.13). So are the `OPEN(…)`
  readings of design §5.

## The chapters

1. [A first analysis, and the shape of astra-tools](01-first-analysis.md), 45–60 min:
   `init`, `validate` and its JSON, exit codes, lazy commands, `rules.json`, the pipeline by
   hand, the cache.
2. [How a file is judged: parse, schema, validator](02-how-a-file-is-judged.md), 40 min: each
   layer broken in turn, the error-to-code lookup, the gates, `INVALID_RECORD`.
3. [Decisions, universes, plan and view](03-universes-plan-view.md), 40 min: effective
   selections, `astra plan`, `render_command`, notes, `astra-plan/1`, `astra view`.
4. [Building, records and check](04-records-and-check.md), 45 min (steps 9 and Try 5
   optional): a runner's job by hand, `run.py`, every status and reason, the hash cache,
   `--at`.
5. [Other analyses, other commits, and history](05-other-analyses-and-history.md), 45 min (step
   6 optional): remote stores, lazy blobs, the three declaration forms, stand-ins,
   `astra history`.
6. [astra-tools from Python, and a map of the code](06-python-api-and-the-code.md), 45–60 min:
   `astra.api`, the JSON shapes, a diagnostic traced to its line, plug-ins, the code's
   constraints, the tests.

## astra-tools in one picture

The pipeline is read → load → contract → bind → {rules, plan, view, check} → surfaces. Each
layer imports only from the layers before it. The numbers are design §2's layout, which
CLAUDE.md repeats.

```
0 foundations  diagnostics.py grammar.py model.py      Location, Diagnostic, the Catalogue
     │                                                 (rules.json + OWN); names; dataclasses
1 read         sources/ (paths git reader remote       every byte through a Reader: the working
     │         standins)  cache.py                     tree, or a commit by git cat-file
     ▼
  load         load.py                                 bytes → JSON value + positions (Annex A)
     ▼
  contract     contract.py                             JSON Schema + rules.json `errors` → codes
     ▼
2 bind         stack.py                                read each analysis once, follow every
     │                                                 declaration, resolve every address → Stack
     ▼
3 meaning      universes.py                            selections, activity, what is built where
     ├──▶ rules    rules/  validate.py                 validator rules → ValidationReport
     ├──▶ plan     plan.py                             planned results, commands, notes → Plan
     ├──▶ view     view.py                             one universe of the stack → UniverseView
     │
4 results      hashing.py records.py environments.py
     ├──▶ check    check.py                            each record vs its commit → CheckReport
     ├──▶ history  history.py                          records over time, from git → History
     ▼
5 surfaces     api.py   cli/ (rich only in cli/text/)   reference.py   evidence/
```

`plan`, `view`, `check` and `history` validate first. `api._read` calls `validate.validated`,
which binds and then runs the rules (`src/astra/api.py:185`). Only `bind` and `init` skip the
rules.

## Glossary of astra-tools' words

Module paths are under astra-tools' `src/astra/`.

- **stack**: `Stack` (`stack.py:170`), every analysis the root reaches, each read once, with
  every address resolved. **bound**: `Bound` (`stack.py:206`), what `bind` returns: the stack,
  or `None` where the root can't be read, plus the parse and schema diagnostics.
- **identity**: `Identity` (`stack.py:48`), an analysis as a folder and a commit, `None` for
  the working tree. A URL isn't part of it. **member**: `Member` (`stack.py:92`), one analysis
  of the stack: its file, document, reader and URL. **resolution**: `Resolution`
  (`stack.py:150`), one address as written and the `Element` it names.
- **reader**: the `Reader` protocol (`sources/reader.py:40`), the only way in for bytes.
  `WorktreeReader` reads the disk and the index. `CommitReader` reads a commit through one
  long-lived `git cat-file --batch` (`Objects`, `sources/git.py:218`) and checks nothing out.
- **store**: a bare repository per URL in the cache's `remotes`, named by the URL's SHA-256,
  one ref `refs/astra/<commit>` per commit fetched (`Remotes`, `sources/remote.py:27`).
- **catalogue**: `Catalogue` (`diagnostics.py:96`), `rules.json` read at each call, plus
  `OWN`, astra-tools' three codes. **contract**: `Contract` (`contract.py:69`), the JSON
  Schemas and the keyword-location → code map.
- **context**: `Context` (`rules/context.py:21`), what the rules share for one stack:
  selections, activity, what is built, and design §4.13's predicates. **undetermined**: what a
  rule is about, when another broken `MUST` leaves it unknown. The rule then isn't checked or
  reported, and design §4.13's closed list of cases says when that happens.
- **selection**: `Selection` (`universes.py:41`), a universe's effective selection: its
  entries, what it inherited, and the activity of each decision and output.
- **planned result**: `Result` (`plan.py:69`), one result to build or to read: names, places,
  reads, decisions, the command template, the folder it runs in. A result is **read-only**
  when its analysis is at a commit other than the root's: it is read through its record, never
  built. **place**: `Place` (`universes.py:474`), a name's address, record path and bytes path.
  **read**: `Read` (`plan.py:57`), one entry of a result's inputs: its path, commit and the
  result it reads.
- **note**: `Note` (`plan.py:93`), one of the plan's remarks, never a diagnostic:
  `fallback_pin`, `two_names`, `unplanned`, `same_computation`, `outside_folder`.
- **stand-in**: the `StandIn` protocol (`sources/standins.py:32`): Git LFS, git-annex, DVC, and
  anything registered under `astra.standins`. **environment scheme**: `environments.py`, under
  `astra.environments`.
- **status**: `Status` (`check.py:91`), a place's record status (`unchanged`, `stale`,
  `missing`) and bytes status (`present`, `absent`), plus astra-tools' `committed`.
  **reason**: `Reason` (`check.py:78`), a check code on one place or one evidence, with
  `breaks` under `INVALID_RECORD`.
- **digest**: `Digest` (`hashing.py:30`), a SHA-256 and a size.
- **the cache's namespaces**: `cache.py:21`. `remotes` holds the stores, `validity` the
  verdicts on analyses from a commit (`rules/commits.py`), `hashes` the working-tree files'
  digests by inode, `worktrees` the checkouts for runs, and `papers` the papers cited by DOI.
- **unchecked**: the validator codes of the installed `rules.json` that no module declares
  (`validate.py:62`). It is empty now.
- **shape**: the name and version a JSON output carries, such as `astra-plan/1` (each
  `to_json`).
- **runner helpers**: `new_record`, `write_record`, `uncommitted_changes` and `land`
  (`records.py`), with `render_command` (`plan.py`) and `Repository.worktree`. None of them is
  in `astra.api` (chapter 4, step 3).
