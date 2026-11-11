# 5. Other analyses, other commits, and history

line-fit declares noisy-line by a `file://` URL and a commit. This chapter follows that declaration into astra-tools: the store it fetches into, the `git cat-file` reader it reads through, what lands in the cache, and how the three forms of declaration are read.
Then stand-ins, briefly, and `astra history`, which reads records back out of git.
Step 6 (stand-ins) can be left for a second pass: nothing after it depends on it.

## Setup

```console
$ source env.sh
astra: …/astra-tools/.venv/bin/astra (astra, version 0.2.19.dev…)
work:  …/tour/work
$ sh setup/05.sh
1. noisy-line is built and committed
  noisy-line c94c7b063ef9 Generate noisy points around a line
  noisy-line 2c5197a98df7 Build the points
2. line-fit declares noisy-line at that commit, and is built and committed
  line-fit 61da112d31fa Fit noisy-line's points by least squares and by the Huber loss
  line-fit aca519ee76e7 Build the fits and their comparison
3. noisy-line draws twice as many points, and is built again
  noisy-line 228881854072 Draw 60 points
  noisy-line 18cfe9d5695d Build the points again
4. line-fit declares noisy-line's new commit, and is built again
  line-fit 398cd34fffab Read noisy-line's 60 points
  line-fit 5e496bf35e59 Build the fits and their comparison again
5. the Huber option's setting changes, and what it changes is built again
  line-fit b4e668612ca3 Huber: turn linear from 1.0 robust standard deviations
  line-fit 48b131e715b8 Build the Huber fit and the comparison again
6. the Huber option's setting changes back, and what it changes is built again
  line-fit b0e7c5691722 Huber: back to 1.345 robust standard deviations, the usual choice
  line-fit 1e6c554d18d7 Build the Huber fit and the comparison at 1.345
7. noisy-line pushes twice as many points above the line, and is built again
  noisy-line 3732bd7f8be4 Push 6 points above the line, not 3
  noisy-line 2dcf20f515e3 Build the points with 6 outliers
8. line-fit declares noisy-line's newest commit, and is built again
  line-fit 5b049987ddc8 Read noisy-line's points with 6 outliers
  line-fit 47395b7e07cf Build the fits and their comparison with 6 outliers
$ cd work/05/build/line-fit
$ export ASTRA_CACHE_DIR=$TOUR/work/05/cache
```

- `setup/05.sh` copies `examples/` into `work/05/` and runs `build.py` there (about five seconds).
- noisy-line's ids are the examples README's. line-fit's differ: its declaration holds the absolute `file://` URL of `work/05/build/noisy-line`, and the URL is part of the committed `astra.yaml`. So line-fit's ids, and the store's name in step 2, are the chapter's only with the tour in its own folder (`…/tour` stands for it; the README's *Paths*).
- The ids hold only where `python3 --version` prints 3.14 (any patch release) after `source env.sh`: run.py's records name the `python3` on PATH by its version (`examples/run.py:149-158`). With another version the setup ends with a line saying so, and every id from `Build the points` on differs, the commit line-fit declares among them, so nearly every block below differs too, as do the `environment` lines. The README's *Before you start* says how to get 3.14.
- The chapter keeps a cache of its own, `work/05/cache`, so that it starts empty: it doesn't exist until step 2 makes it. The build doesn't use it: `build.py` gives its git and `run.py` processes a cache of their own, `work/05/build/cache` (`examples/build.py:45`). The next `source env.sh` puts `ASTRA_CACHE_DIR` back to `work/cache`.

## 1. Two repositories, one declaration

line-fit's only link to noisy-line is four lines of its `astra.yaml`. Look at both histories and those lines before astra-tools reads anything.

```console
$ git --no-pager log --oneline --no-decorate
47395b7 Build the fits and their comparison with 6 outliers
5b04998 Read noisy-line's points with 6 outliers
1e6c554 Build the Huber fit and the comparison at 1.345
b0e7c56 Huber: back to 1.345 robust standard deviations, the usual choice
48b131e Build the Huber fit and the comparison again
b4e6686 Huber: turn linear from 1.0 robust standard deviations
5e496bf Build the fits and their comparison again
398cd34 Read noisy-line's 60 points
aca519e Build the fits and their comparison
61da112 Fit noisy-line's points by least squares and by the Huber loss
$ git -C ../noisy-line --no-pager log --oneline --no-decorate
2dcf20f Build the points with 6 outliers
3732bd7 Push 6 points above the line, not 3
18cfe9d Build the points again
2288818 Draw 60 points
2c5197a Build the points
c94c7b0 Generate noisy points around a line
$ sed -n '3,6p' astra.yaml
analyses:
  noisy:
    url: file://…/tour/work/05/build/noisy-line
    commit: "2dcf20f515e3eecf7e2126c182c54dd5f0f8f206"
$ astra cache path
…/tour/work/05/cache
$ test -d "$ASTRA_CACHE_DIR" || echo "no cache yet"
no cache yet
```

What to notice:
- `HEAD~n` later counts back through this log: `HEAD~1` is 5b04998 (step 8's new declaration, nothing built), `HEAD~4` is 48b131e (step 5's build), `HEAD~8` is aca519e (step 2's build), `HEAD~9` the first commit.
- The declared commit is noisy-line's HEAD, step 7's build: a commit that holds the records, later than the one their recipe ran from ([§20 *Results of an analysis from a commit*](https://astra-spec.org/0.1/specification/#results-of-an-analysis-from-a-commit)).
- A `file://` URL is §17's form for another repository on the same machine ([§17](https://astra-spec.org/0.1/specification/#17-analyses-from-another-commit-or-repository)).
- `astra cache path` prints where the cache would be. Nothing has made it yet.

Under the hood:
- `cache.root()` (`src/astra/cache.py:32`) takes `ASTRA_CACHE_DIR` and refuses a relative one (`CacheError`, exit 2), since it would land inside whatever repository astra runs in. Otherwise it is the platform's user cache folder. `astra cache path` only prints it (`src/astra/cli/cache.py:28`).
- Before anything below runs, the schema layer holds the declaration to `URL_WITHOUT_COMMIT` and `INVALID_COMMIT` (a full 40- or 64-digit id). A file that breaks either isn't a valid document, so its declarations aren't followed (design §4.13 case 2), and a branch name never reaches git.

## 2. The first read fetches noisy-line into a store

Validating line-fit means reading noisy-line's `astra.yaml` at 2dcf20f, a commit line-fit's repository doesn't have. astra-tools fetches it into a bare repository of its own in the cache.

```console
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ ls -1 "$ASTRA_CACHE_DIR"
remotes
validity
$ ls "$ASTRA_CACHE_DIR/remotes"
59e1d0836369cdb8035c557152283ff6f23a1eb38face13c06987dfcaaea4c71
$ ls "$ASTRA_CACHE_DIR/validity" | wc -l
1
$ printf %s "$(sed -n 's/^    url: //p' astra.yaml)" | sha256sum
59e1d0836369cdb8035c557152283ff6f23a1eb38face13c06987dfcaaea4c71  -
$ export STORE=$ASTRA_CACHE_DIR/remotes/59e1d0836369cdb8035c557152283ff6f23a1eb38face13c06987dfcaaea4c71
$ git -C "$STORE" config --get remote.origin.url
file://…/tour/work/05/build/noisy-line
$ git -C "$STORE" for-each-ref
2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 commit	refs/astra/2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
$ git -C "$STORE" cat-file --batch-all-objects --batch-check='%(objecttype)' 2>/dev/null | sort | uniq -c
     11 blob
      6 commit
     16 tree
$ cat "$ASTRA_CACHE_DIR"/validity/*; echo
[]
```

What to notice:
- The store is as chapter 1's step 8 opened one: one per URL, named by the SHA-256 of the URL as written, its `origin` that URL, and one ref per commit asked for, `refs/astra/<commit>`. What is new: it holds 6 commits, since the fetch brings 2dcf20f with all its ancestors (no `--depth`).
- It holds 11 blobs too, every blob of noisy-line's history, though astra-tools fetches with `--filter=blob:none`: a `file://` remote ignores the filter unless it sets `uploadpack.allowFilter`, and astra-tools drops git's warning (chapter 1, step 8). `2>/dev/null` hides git's other warning, that the store is a partial clone. Step 3 shows the difference.
- `validity` holds one verdict, `[]`: noisy-line at 2dcf20f, judged as its own root, breaks no `MUST`. Its file name hashes astra-tools' version too, so it differs between builds of astra-tools (which is why it isn't shown).

Under the hood:
- `bind` (`src/astra/stack.py:242`) follows each declaration through `_follow` (`stack.py:311`). A `url` declaration gets `remotes.get(url, commit)`, then a `CommitReader` on the store, at the folder `""` (`stack.py:328-333`).
- `Remotes.get` (`src/astra/sources/remote.py:34`): a store that has the commit counts as got, and otherwise, unless offline, it fetches (`remote.py:47`). Each URL and commit is asked for once per run (`remote.py:45-48`). `None` makes the outcome `unreachable`, astra-tools' `REMOTE_UNREACHABLE`.
- `_store` (`remote.py:58`) names the folder by the URL's hash (`remote.py:62`) and makes it in a temporary folder with `Repository.init_bare` (`src/astra/sources/git.py:61`), which sets only `remote.origin.url` (`git.py:65`). It then renames it into place (`remote.py:68`), so two processes never make one store together.
- `Repository.fetch` (`git.py:150`) runs `git fetch --quiet --no-tags --no-write-fetch-head --filter=blob:none origin <commit>:refs/astra/<commit>` (`git.py:154-157`) and then asks `has_commit` (`git.py:158`). `_git` captures git's stderr (`git.py:35-42`), and `fetch` looks at nothing but `has_commit` afterwards, so git's warning goes nowhere. `GIT_TERMINAL_PROMPT=0` stops git from waiting for a password (`git.py:30`).
- `CommitReader` (`src/astra/sources/reader.py:170`) never checks anything out. It reads through one long-lived `git cat-file --batch` (`Objects`, `git.py:218-249`): the commit for its tree (`_root`, `reader.py:251-260`), a tree per path segment (`_walk`, `reader.py:236-249`), then the blob (`read`, `reader.py:193-197`).
- `DECLARED_ANALYSIS_INVALID` needs noisy-line validated as its own root at its commit. `_judged` (`src/astra/rules/commits.py:173`) does that and keeps the list of `MUST`s broken in `validity`, keyed by astra-tools' version, the catalogue's version, the folder and the commit (`commits.py:186`). It keeps nothing where the verdict rests on a commit not got or on `COMMIT_NOT_FOUND` (`commits.py:200`). The URL isn't in the key: a commit is one analysis wherever it came from ([§17 *Identity*](https://astra-spec.org/0.1/specification/#identity)).
- The store, the fetch and the `validity` verdicts are astra-tools' own (design §4.3, §4.9). The specification says only that a commit counts as got when it can be fetched or was kept from an earlier fetch ([§17 *Reading one*](https://astra-spec.org/0.1/specification/#reading-one)).

## 3. A remote that serves partial clones, and what astra-tools reads

Let noisy-line's repository honour the filter, as GitHub does. Chapter 1's Try 4 did this to `upstream` and counted one blob; here the store shows exactly which files `validate` and `check` read.

```console
$ git -C ../noisy-line config uploadpack.allowFilter true
$ astra cache clear
Cleared the cache in …/tour/work/05/cache.
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ git -C "$STORE" cat-file --batch-all-objects --batch-check='%(objecttype)' 2>/dev/null | sort | uniq -c
      1 blob
      6 commit
     16 tree
$ git -C "$STORE" ls-tree -r 2dcf20f | while read -r m t oid name; do GIT_NO_LAZY_FETCH=1 git -C "$STORE" cat-file -e "$oid" 2>/dev/null && echo "kept     $name" || echo "not kept $name"; done
not kept .astra/records/points.json
kept     astra.yaml
not kept config.json
not kept results/points.csv
not kept src/make_points.py
$ astra check
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
.astra/records/ols/fit.json  fit#ols  unchanged  present
.astra/records/huber/fit.json  fit#huber  unchanged  present
.astra/records/comparison.json  comparison  unchanged  present
astra.yaml
  53:19 unchanged `comparison`
astra.yaml: 4 place(s) of planned results, 4 unchanged, 0 stale, 0 missing; 0 absent
$ git -C "$STORE" ls-tree -r 2dcf20f | while read -r m t oid name; do GIT_NO_LAZY_FETCH=1 git -C "$STORE" cat-file -e "$oid" 2>/dev/null && echo "kept     $name" || echo "not kept $name"; done
kept     .astra/records/points.json
kept     astra.yaml
kept     config.json
kept     results/points.csv
not kept src/make_points.py
```

What to notice:
- The store is at the same path: `cache clear` removed it, and `validate` made it again. With the filter honoured, the fetch brings commits and trees only.
- `validate` reads one blob, noisy-line's `astra.yaml` at 2dcf20f. It never opens `config.json`: `MISSING_INPUT_FILE` and `INPUT_NOT_TRACKED` at a commit need only the entry's mode in the commit's tree.
- `check` reads three more: `points`'s record (its record status), `config.json` (`STALE_RESULT` compares the content of the input at 2dcf20f with what the record lists), and `points.csv` (the fits read it, so it gets a bytes status).
- `src/make_points.py` stays at the remote. The code is recorded by its commit and never compared ([§20 *When a result is unchanged*](https://astra-spec.org/0.1/specification/#when-a-result-is-unchanged)).
- `uploadpack.allowFilter` stays set for the rest of the chapter, so the store behaves from here as one fetched from GitHub would.

Under the hood:
- A `CommitReader` makes `Objects(repo, lazy=not remotes.offline)` (`reader.py:187`). Lazy, git's environment leaves `GIT_NO_LAZY_FETCH` out (`git.py:25-32`), so `cat-file --batch` fetches a missing blob from the promisor remote when it is asked for. With `--offline` the blob reads as missing, and the reader says it "isn't kept in the cache: validate without --offline to fetch it" (`reader.py:267-275`).
- The input rules stat before they read: `_no_file` returns at once for a file (`src/astra/rules/inputs.py:84-86`), and tracked at a commit means present in the commit's tree (`reader.py:208-214`). Neither needs the blob.
- For `STALE_RESULT`, the checker binds the stack at the commit the record names, 3732bd7, from the same store (`_bind`, `src/astra/check.py:377`), and compares the input's content now through `_content` (`check.py:509`). The bytes status hashes `points.csv` as read from git (`_bytes`, `check.py:521`, then `hashing.digest`, `src/astra/hashing.py:66-74`).
- `astra cache clear` (`cache.py:82`) moves each of astra-tools' namespaces aside and deletes it. Anything else in the folder stays.

## 4. info and plan across the two repositories

The stack now spans two repositories. `info` shows how each analysis is known, and `plan` what that means for results.

```console
$ astra info
astra.yaml
  analyses  noisy: astra.yaml at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 from file://…/tour/work/05/build/noisy-line
  outputs   fit: table, json
            comparison: table, json
  decisions method: ols, huber
  universes ols
            huber
astra.yaml at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 from file://…/tour/work/05/build/noisy-line
  inputs    config: config.json
  outputs   points: data, csv
$ astra plan
points
  record    .astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
  bytes     results/points.csv at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
  read through its record at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
fit#ols
  record    .astra/records/ols/fit.json
  bytes     results/ols/fit.json
  run in    .
  command   python3 src/fit.py ols 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206:results/points.csv results/ols/fit.json
fit#huber
  record    .astra/records/huber/fit.json
  bytes     results/huber/fit.json
  run in    .
  command   python3 src/fit.py huber 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206:results/points.csv results/huber/fit.json
comparison
  record    .astra/records/comparison.json
  bytes     results/comparison.json
  run in    .
  command   python3 src/compare.py results/ols/fit.json results/huber/fit.json results/comparison.json
4 planned result(s)
$ astra plan --json | nix shell 'nixpkgs#jq' --command jq -c '.results[] | {address: [.places[].address], owner, read_only, inputs: [.inputs[] | {entry, path, commit, result}]}'
{"address":["points"],"owner":{"folder":"","commit":"2dcf20f515e3eecf7e2126c182c54dd5f0f8f206"},"read_only":true,"inputs":[{"entry":"config","path":"config.json","commit":"2dcf20f515e3eecf7e2126c182c54dd5f0f8f206","result":null}]}
{"address":["fit#ols"],"owner":{"folder":"","commit":null},"read_only":false,"inputs":[{"entry":"noisy.points","path":"results/points.csv","commit":"2dcf20f515e3eecf7e2126c182c54dd5f0f8f206","result":0}]}
{"address":["fit#huber"],"owner":{"folder":"","commit":null},"read_only":false,"inputs":[{"entry":"noisy.points","path":"results/points.csv","commit":"2dcf20f515e3eecf7e2126c182c54dd5f0f8f206","result":0}]}
{"address":["comparison"],"owner":{"folder":"","commit":null},"read_only":false,"inputs":[{"entry":"fit#ols","path":"results/ols/fit.json","commit":null,"result":1},{"entry":"fit#huber","path":"results/huber/fit.json","commit":null,"result":2}]}
$ git -C "$STORE" show 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206:results/points.csv | head -3
x,y
0.374957,1.351965
0.392073,11.914969
```

(The JSON is filtered by `jq` to four fields of each result of `astra-plan/1`.)

What to notice:
- `info` names each analysis by its file and, for one read at a commit, the commit and the URL it came from. Nothing there says which repository holds the root.
- `points` is planned, since the fits read it, but is never built here: "read through its record at 2dcf20f". Its record and bytes places are noisy-line's, at that commit ([§17 *Using one*](https://astra-spec.org/0.1/specification/#using-one)).
- The fits' command writes the input as `2dcf20f…:results/points.csv`, git's name for a file at a commit. It names a file in the store: line-fit's repository has no such commit. A runner substitutes the path of the bytes it got (`examples/run.py` gets them with `history.get`).
- In the JSON, `owner` is an identity, a folder and a commit, with no URL: a URL says only where to get the commit ([§17 *Identity*](https://astra-spec.org/0.1/specification/#identity)). `read_only` is true for `points`. Each input read at a commit carries that commit, and `result` is the index of the planned result it reads.

Under the hood:
- `info` heads each member with `file_named` (`src/astra/cli/text/info.py:16`, `src/astra/cli/text/__init__.py:23-29`), from the `Location` that `Stack.location` builds with the member's commit and URL (`src/astra/stack.py:213-219`), and prints each declaration's row through `_reached` (`info.py:42`), which names the member it reached the same way. It checks nothing: it exits 1 only where there is no stack to show (the root's file isn't a valid document, or the root is in no repository), so an unreachable declaration still exits 0, shown as "nothing (unreachable)".
- `Identity` (`stack.py:48-59`) is a folder and a commit, `None` for the working tree.
- `read_only = result.owner.commit != stack.root.commit` (`src/astra/plan.py:417`); the text plan prints "read through its record" for it (`src/astra/cli/text/plan.py:30`).
- `render_command` writes `<commit>:<path>` for an entry read at a commit that its `got` doesn't give (`plan.py:743`).

## 5. Three forms of declaration, three ways of reading

[§17](https://astra-spec.org/0.1/specification/#17-analyses-from-another-commit-or-repository)'s table has three forms. Add the two line-fit lacks, by `path` and by `path` and `commit`, both naming line-fit's own folder (§17's *Earlier results* pattern), and see how each is read.

```console
$ sed -i "/^analyses:/a\\  before: {path: ., commit: \"$(git rev-parse 'HEAD~8')\"}" astra.yaml
$ sed -i '/^analyses:/a\  here: {path: .}' astra.yaml
$ sed -n '3,8p' astra.yaml
analyses:
  here: {path: .}
  before: {path: ., commit: "aca519ee76e71f7392dbd216d2e1bc71d7d5adfd"}
  noisy:
    url: file://…/tour/work/05/build/noisy-line
    commit: "2dcf20f515e3eecf7e2126c182c54dd5f0f8f206"
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra info
astra.yaml
  analyses  here: astra.yaml
            before: astra.yaml at aca519ee76e71f7392dbd216d2e1bc71d7d5adfd
            noisy: astra.yaml at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 from file://…/tour/work/05/build/noisy-line
  outputs   fit: table, json
            comparison: table, json
  decisions method: ols, huber
  universes ols
            huber
astra.yaml at aca519ee76e71f7392dbd216d2e1bc71d7d5adfd
  analyses  noisy: astra.yaml at 2c5197a98df7d378a402a48ac036add64662960b from file://…/tour/work/05/build/noisy-line
  outputs   fit: table, json
            comparison: table, json
  decisions method: ols, huber
  universes ols
            huber
astra.yaml at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 from file://…/tour/work/05/build/noisy-line
  inputs    config: config.json
  outputs   points: data, csv
astra.yaml at 2c5197a98df7d378a402a48ac036add64662960b from file://…/tour/work/05/build/noisy-line
  inputs    config: config.json
  outputs   points: data, csv
$ git -C "$STORE" for-each-ref
2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 commit	refs/astra/2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
$ ls -1 "$ASTRA_CACHE_DIR"
hashes
remotes
validity
$ ls "$ASTRA_CACHE_DIR/validity" | wc -l
3
$ ls "$ASTRA_CACHE_DIR/hashes" | wc -l
3
$ git checkout -q astra.yaml
```

What to notice:
- `here` reaches `astra.yaml`, the root itself: same folder, also in the working tree, so the same identity, and it isn't read again. An address through it is another spelling of a root element ([§15 *One analysis, however it is declared*](https://astra-spec.org/0.1/specification/#one-analysis-however-it-is-declared)).
- `before` is read at aca519e in line-fit's own repository, so no "from". It declares noisy-line at 2c5197a, step 1's build, and `info` lists that as a fourth analysis: same folder, another commit, another analysis.
- The store still has one ref. 2c5197a is an ancestor of 2dcf20f, fetched with it in step 3, so it counts as got and nothing is fetched.
- `validity` has three verdicts now, one for each analysis from a commit. `hashes` has three entries: line-fit's three result files, hashed by step 3's `check`. Had that `check` run within two seconds of the setup's last build, `hashes` would be missing here (`hashing.py:60`); run by hand, it never is.
- The analysis stays valid, and its plan is the same: nothing reads `here` or `before`. `COMMIT_NOT_ANCESTOR`, astra-tools' own warning (design §3), holds, since aca519e is an ancestor of HEAD.

Under the hood:
- `_follow` (`stack.py:311`), by `path` alone: the declaring analysis's own reader, here the `WorktreeReader` (`stack.py:347-349`). `bind` reads a place only if its identity isn't a member yet (`stack.py:280`).
- `WorktreeReader` (`src/astra/sources/reader.py:77`) reads files from disk. Its `tracked` asks the index (`Repository.tracked`, `git ls-files --stage`, `git.py:83-99`), where a `CommitReader` looks the path up in the commit's tree (`reader.py:208-214`). Its `holding` (`reader.py:105-111`) is the innermost checked-out submodule on the way to the folder, or the root's repository.
- By `path` and `commit`: the repository that holds the declaring file (`Reader.holding`, `stack.py:336`). Where that repository lacks the commit, the outcome is `absent`, which is `COMMIT_NOT_FOUND` (`stack.py:338-340`). With it, a `CommitReader` with no URL (`stack.py:341`). In a file read from a remote, the same commit is got from that remote instead (`stack.py:342-346`).
- noisy-line at 2c5197a: `Remotes.get` finds the commit in the store (`remote.py:47`), so nothing is fetched and no ref is added.
- `COMMIT_NOT_ANCESTOR` (`src/astra/rules/commits.py:82-98`) is judged only for a declaration with a `path` and a `commit`, against the commit the declaration is in or, in the working tree, HEAD. A `url` declaration's commit is never compared with anything.
- `hashes` belongs to `hashing.digest_file` (`src/astra/hashing.py:43`), which chapter 4's step 10 takes apart: keyed by device and inode, holding the size, the modification time and the hash, so an unchanged file costs a `stat`. A file modified less than two seconds before it is hashed isn't kept (`hashing.py:60`).
- The five namespaces are in `cache.py:21` (chapter 1's step 8 has a table of them). `worktrees` holds the checkouts of `Repository.worktree`, which `run.py --worktree` uses.

## 6. Stand-ins, briefly

[§7](https://astra-spec.org/0.1/specification/#7-inputs) lets an input's path hold a stand-in that "the validator recognises". Which stand-ins count is astra-tools' choice (design §4.5). Chapter 4's step 9 put a Git LFS pointer in an input's place; here the same on noisy-line's `config.json`, then a DVC file, both uncommitted.

```console
$ cd ../noisy-line
$ python -c 'from astra.sources.standins import registered; [print(s.name, "->", s.place("config.json")) for s in registered()]'
Git LFS -> config.json
git-annex -> config.json
DVC -> config.json.dvc
$ printf 'version https://git-lfs.github.com/spec/v1\noid sha256:%s\nsize %s\n' $(sha256sum config.json | cut -c1-64) $(wc -c < config.json) > pointer
$ mv pointer config.json
$ cat config.json
version https://git-lfs.github.com/spec/v1
oid sha256:75c96f73e6c6ec40e5d516d601ef759f54a27dd9819d14a7def9ebb2e853a58d
size 101
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra check
.astra/records/points.json  points  unchanged  present
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
$ sed -i 's/^size 101$/size 102/' config.json
$ astra check
.astra/records/points.json  points  stale  present
  error STALE_RESULT the content of `config`, config.json, isn't what the recipe read
astra.yaml: 1 place(s) of planned results, 0 unchanged, 1 stale, 0 missing; 0 absent
$ git checkout -q config.json
$ git mv config.json config.json.dvc
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra check
.astra/records/points.json  points  stale  present
  error STALE_RESULT the content of `config` can't be read at config.json: no file is there, or only a stand-in that gives no SHA-256
astra.yaml: 1 place(s) of planned results, 0 unchanged, 1 stale, 0 missing; 0 absent
$ git mv config.json.dvc config.json
$ cd ../line-fit
```

What to notice:
- With a Git LFS pointer that gives `config.json`'s real hash and size in its place, `points` stays `unchanged`. `STALE_RESULT` compares the content, never what stands in for it, and the pointer gives the content's hash ([§20 *The rules*](https://astra-spec.org/0.1/specification/#20-checking-results)).
- Change the pointer's size to 102 and `points` is `stale`. astra-tools takes the pointer's word for the content: its oid and size are the digest compared, both at once (`hashing.Digest`, `hashing.py:30`), and nothing is fetched to check them. Size 102 names other content, so the content counts as changed, though the data didn't.
- With a DVC file beside the path and `config.json` gone, the analysis is valid: `MISSING_INPUT_FILE` accepts the stand-in, and `INPUT_NOT_TRACKED` the tracked `config.json.dvc`. The "DVC file" is only `config.json` renamed: astra-tools recognises one by its name alone (`standins.py:130-132`).
- The checker asks only stand-ins kept at the path itself, so it never asks DVC. `config.json` is gone, so there is nothing to hash, and the result is `stale`, never `unchanged`, as §20 requires where an input's content can't be read or sits behind a stand-in that gives no hash ([§20 *When a result is unchanged*](https://astra-spec.org/0.1/specification/#when-a-result-is-unchanged)). The same holds for any stand-in kept beside the path, built-in or registered: the checker never asks it for a hash, whatever its `gives` returns, so with no file at the path its result can only be stale. That is astra-tools' choice (the `_content` docstring, `check.py:510-513`).
- astra-tools runs neither git-lfs nor dvc, and fetches nothing a stand-in stands for.

Under the hood:
- The `StandIn` protocol (`src/astra/sources/standins.py:32-51`): `place(path)` is what git tracks for the file, `recognises` says whether it is there, and `gives` returns the content's hash and size. Git LFS and git-annex keep it at the path itself (`standins.py:66-67`, `standins.py:96-97`), DVC beside it (`standins.py:127-128`), and DVC's `gives` is `None` (`standins.py:134-135`). Design §4.5's table says DVC gives the size; the code gives nothing, since `gives` returns a hash and a size together or `None` (`standins.py:48-51`; chapter 4's step 9 noted it too). git-annex, not tried here, is a symlink into `annex/objects/`, never followed, or an unlocked pointer naming one; a key of the `SHA256` or `SHA256E` backend gives the hash and size (`standins.py:102-106`).
- `registered()` (`standins.py:142-146`) gives the three built-ins, then each object registered in the entry-point group `astra.standins` (`standins.py:28`). Nothing is registered here.
- The validator asks git about every stand-in place at once (`src/astra/rules/inputs.py:48-54`), accepts a recognised stand-in where no file is (`inputs.py:94`), and a tracked stand-in for tracking (`inputs.py:65-68`).
- The checker's `_content` (`src/astra/check.py:509-519`) consults only stand-ins kept at the path itself (`check.py:516`). A DVC file beside the path is never consulted, the path holds no file, and `STALE_RESULT` says the content "can't be read" (`check.py:489`).

## 7. History: a record's versions

`astra history` reads what git holds of each planned result's records, on demand. It is astra-tools' own, beyond the specification (design §6 *Phase 4*), built on records ([§19](https://astra-spec.org/0.1/specification/#19-records)) and their places ([§18](https://astra-spec.org/0.1/specification/#18-results-and-where-they-go)).

```console
$ astra history timeline 'fit#huber'
fit#huber  .astra/records/huber/fit.json
  47395b7e07cfc906fc5615d3efb5c65938f8e01a
    bytes        sha256:fdbc97616ab1d246f9c6ef4137a0dbc345623ce4d9547e7e541342e9c7b40cf4, 86 byte(s)
    made at      5b049987ddc8717cc33fb4bd967209e517ba0433
    environment  urn:astra-examples:cpython-3.14
  1e6c554d18d73e7d2d29be5140680d2a955dcd09
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      b0e7c5691722b0f8c286513d34e6c954be5c605f
    environment  urn:astra-examples:cpython-3.14
  48b131e715b8be775ceb21754c35d1a4b1e9c00e
    bytes        sha256:72c18945d6a304e5887bca9bd3fa5628a8fa2dc33900083538d1fa1277aa7aa3, 86 byte(s)
    made at      b4e668612ca3634daf76529928888e4ac4f225ba
    environment  urn:astra-examples:cpython-3.14
  5e496bf35e59765099614870b0a274f1368d3e28
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      398cd34fffabc1980aa9c770d0ac07deb95355d4
    environment  urn:astra-examples:cpython-3.14
  aca519ee76e71f7392dbd216d2e1bc71d7d5adfd
    bytes        sha256:6e373f83ec8711725574156cd02b6571e249e9b5c971fbb793d9055ea3396132, 86 byte(s)
    made at      61da112d31fa11d8b477ba3bbfcb19c318578468
    environment  urn:astra-examples:cpython-3.14
5 version(s)
$ git --no-pager log --format='%H %s' -- .astra/records/huber/fit.json
47395b7e07cfc906fc5615d3efb5c65938f8e01a Build the fits and their comparison with 6 outliers
1e6c554d18d73e7d2d29be5140680d2a955dcd09 Build the Huber fit and the comparison at 1.345
48b131e715b8be775ceb21754c35d1a4b1e9c00e Build the Huber fit and the comparison again
5e496bf35e59765099614870b0a274f1368d3e28 Build the fits and their comparison again
aca519ee76e71f7392dbd216d2e1bc71d7d5adfd Build the fits and their comparison
$ astra history timeline points
points  .astra/records/points.json
  2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
    bytes        sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    made at      3732bd7f8be4fcc70b1582a104224d2a55d14cea
    environment  urn:astra-examples:cpython-3.14
1 version(s)
$ astra history timeline points ../noisy-line
points  .astra/records/points.json
  2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
    bytes        sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    made at      3732bd7f8be4fcc70b1582a104224d2a55d14cea
    environment  urn:astra-examples:cpython-3.14
  18cfe9d5695d7fc13a3d93bbbba2f6a644bd284d
    bytes        sha256:11d14fd855f6a3eae39dcd3ffaa849d0d8f2562ea907b31eb140369af0c4d6d9, 1114 byte(s)
    made at      2288818540727575fa0a5953bfebea956a07b787
    environment  urn:astra-examples:cpython-3.14
  2c5197a98df7d378a402a48ac036add64662960b
    bytes        sha256:5e7c855a7fda19230dd956b3aafe4e05ec3c0f01b47c6651a45fe6acdf84f8f9, 558 byte(s)
    made at      c94c7b063ef955f5287fc08db8a4279a96cd62f1
    environment  urn:astra-examples:cpython-3.14
3 version(s)
```

What to notice:
- The five versions are exactly what `git log -- <record>` lists. A version's commit is the one that changed the record's file; "made at" is the commit the record names, where the recipe ran: here always the one before.
- 5e496bf (step 4) and 1e6c554 (step 6) give one hash: `HUBER_K` went to 1.0 and back.
- From line-fit, `points` has one version, its record at the declared commit, 2dcf20f, made at 3732bd7. From noisy-line, where `points` is the root's own result, it has three.
- `PATH` comes after `ADDR`. The address is resolved against today's plan, from the working tree's `astra.yaml`; the versions come only from commits, never from the working tree.

Under the hood:
- `api.history` (`src/astra/api.py:142-150`) needs a valid stack (`_valid`, `api.py:173-183`): on one that breaks a `MUST`, every history command prints `validate`'s report and exits 1. `History.__init__` plans the stack once (`src/astra/history.py:96`).
- `_versions` (`history.py:186-206`): for a read-only result, its record through its analysis's own reader, as one version at the declared commit (`history.py:193-197`). Otherwise `Repository.log` (`src/astra/sources/git.py:129-140`), which runs `git log --format=%H HEAD -- :(literal)<path>` (`git.py:136`), and a `CommitReader` per commit, each record read as the checker reads one (`history.py:200-204`).
- Nothing is indexed or kept in the cache: `_kept` lives only as long as the `History` object.
- History prints text only, as `info` and `universe` do (design §4.12).

## 8. lineage, and --used-by

`lineage` follows a record's `inputs` down, across both repositories; `--used-by` goes up.

```console
$ astra history lineage comparison
comparison  .astra/records/comparison.json
  47395b7e07cfc906fc5615d3efb5c65938f8e01a
    bytes        sha256:b1bd0abed9eecbbcbd8c249873ce28ab6b856376561b780d3c0674a4f0457cb8, 204 byte(s)
    made at      5b049987ddc8717cc33fb4bd967209e517ba0433
    environment  urn:astra-examples:cpython-3.14
made from
  fit#ols: sha256:6d8749c475f92a9acd5ee42be9112929f4a2a9149ff30a66c1654cbd66a19a98, 84 byte(s)
    fit#ols's record of 47395b7e07cfc906fc5615d3efb5c65938f8e01a, made at 5b049987ddc8717cc33fb4bd967209e517ba0433
    noisy.points: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
      points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
      config: sha256:75c96f73e6c6ec40e5d516d601ef759f54a27dd9819d14a7def9ebb2e853a58d, 101 byte(s)
        the file config.json
  fit#huber: sha256:fdbc97616ab1d246f9c6ef4137a0dbc345623ce4d9547e7e541342e9c7b40cf4, 86 byte(s)
    fit#huber's record of 47395b7e07cfc906fc5615d3efb5c65938f8e01a, made at 5b049987ddc8717cc33fb4bd967209e517ba0433
    noisy.points: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
      points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
      config: sha256:75c96f73e6c6ec40e5d516d601ef759f54a27dd9819d14a7def9ebb2e853a58d, 101 byte(s)
        the file config.json
$ astra history lineage points --used-by
points  .astra/records/points.json
  2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
    bytes        sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    made at      3732bd7f8be4fcc70b1582a104224d2a55d14cea
    environment  urn:astra-examples:cpython-3.14
used by
  fit#ols, its record of 47395b7e07cfc906fc5615d3efb5c65938f8e01a, through `noisy.points`: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
  fit#huber, its record of 47395b7e07cfc906fc5615d3efb5c65938f8e01a, through `noisy.points`: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
```

What to notice:
- `lineage` starts from the record at HEAD and walks its `inputs`: each entry's hash and size, the version of that result's record that gives them, then what that version read, down to input files. It crosses into noisy-line on the way.
- The versions are matched by hash and size, not by commit: the fits' records name no commit of noisy-line.
- `--used-by` goes one level: the planned results whose records at HEAD list `points`.

Under the hood:
- `_inputs` (`history.py:208`) pairs each entry of a record's `inputs` with today's plan of that result. An entry today's output no longer lists prints as such (`src/astra/cli/text/history.py:75`).
- `_made` (`history.py:254-274`) takes the newest version with that hash and size. Where one repository holds both records, it must be committed no later than the record that lists it (`is_ancestor`, `history.py:271`). Across repositories, or for a read-only result, there is no such bound (`history.py:264`).
- `--used-by` is `_users` and `_uses` (`history.py:227-252`), over today's planned results only.

## 9. find --hash, and get ADDR@REV

`find` looks for a hash across every version of every planned result; `get` gives back the bytes one version recorded.

```console
$ astra history find --hash sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b
fit#huber  .astra/records/huber/fit.json
  1e6c554d18d73e7d2d29be5140680d2a955dcd09
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      b0e7c5691722b0f8c286513d34e6c954be5c605f
    environment  urn:astra-examples:cpython-3.14
  5e496bf35e59765099614870b0a274f1368d3e28
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      398cd34fffabc1980aa9c770d0ac07deb95355d4
    environment  urn:astra-examples:cpython-3.14
2 version(s)
$ astra history get 'fit#huber@HEAD~4'
{
  "method": "huber",
  "points": 60,
  "slope": 2.025348,
  "intercept": 1.011923
}
$ astra history get 'fit#huber@HEAD'
{
  "method": "huber",
  "points": 60,
  "slope": 2.011187,
  "intercept": 1.136179
}
$ astra history get 'comparison@HEAD~9'; echo "exit $?"
astra: 61da112d31fa11d8b477ba3bbfcb19c318578468 holds no record at .astra/records/comparison.json
exit 1
```

What to notice:
- `find` searches every place of today's planned results, by each record's own `content_hash`, in the plan's order and each result's newest first.
- `get` prints the bytes at the result's default place at that commit, once they match the record there. At `HEAD~4`, step 5's build with `HUBER_K = 1.0`, the Huber intercept is 1.01; at HEAD, with 6 outliers, 1.14.
- At `HEAD~9`, before any build, there is no record: a message and exit 1. An `ADDR` that names no planned result, or a `REV` that names no commit, is a usage error, exit 2.

Under the hood:
- `find` (`history.py:119-138`) takes exactly one of `--hash` and `--environment` (`src/astra/cli/history.py:105`).
- The CLI splits `ADDR@REV` at the first `@`, since an address holds none (`cli/history.py:122`, Annex C).
- `History.get` (`history.py:140-167`): `REV` through `git rev-parse --verify <rev>^{commit}` in the repository that holds the result's analysis (`history.py:149`, `git.py:118-127`); the record read and its `address` compared (`history.py:153-156`); the bytes' entry, which must be a file in git (`history.py:158`); their hash and size against the record (`history.py:163`). The CLI writes the bytes as they are (`cli/history.py:127`).
- Exit codes: `_answering` (`cli/history.py:32-47`) turns `InvalidAnalysisError` and `NotInHistoryError` into 1, and `RequestError` into a usage error, 2.

## Try

Each exercise starts where the chapter ends, in line-fit, and puts back what it changes.

1. Move line-fit's declaration to step 3's build of noisy-line, 18cfe9d, without committing. Predict `astra validate`, `astra check` (which results are stale, and why), and `astra history lineage 'fit#ols'`. Then move it to 2288818, step 3's commit before its build, and predict `astra check` again.

    ```
    sed -i 's/2dcf20f515e3eecf7e2126c182c54dd5f0f8f206/18cfe9d5695d7fc13a3d93bbbba2f6a644bd284d/' astra.yaml
    sed -i 's/18cfe9d5695d7fc13a3d93bbbba2f6a644bd284d/2288818540727575fa0a5953bfebea956a07b787/' astra.yaml
    git checkout -q astra.yaml
    ```

<details><summary>Answer</summary>

```console
$ sed -i 's/2dcf20f515e3eecf7e2126c182c54dd5f0f8f206/18cfe9d5695d7fc13a3d93bbbba2f6a644bd284d/' astra.yaml
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra check
.astra/records/points.json at 18cfe9d5695d7fc13a3d93bbbba2f6a644bd284d  points  unchanged  present
.astra/records/ols/fit.json  fit#ols  stale  present
  error STALE_RESULT `points`, which it reads through `noisy.points`, was made again since, with other bytes than it read
.astra/records/huber/fit.json  fit#huber  stale  present
  error STALE_RESULT `points`, which it reads through `noisy.points`, was made again since, with other bytes than it read
.astra/records/comparison.json  comparison  stale  present
  error STALE_RESULT `fit#ols`, which it reads, is stale
  error STALE_RESULT `fit#huber`, which it reads, is stale
astra.yaml
  53:19 error STALE_EVIDENCE `comparison` cites `comparison`, whose record is stale
astra.yaml: 4 place(s) of planned results, 1 unchanged, 3 stale, 0 missing; 0 absent
$ astra history lineage 'fit#ols'
fit#ols  .astra/records/ols/fit.json
  47395b7e07cfc906fc5615d3efb5c65938f8e01a
    bytes        sha256:6d8749c475f92a9acd5ee42be9112929f4a2a9149ff30a66c1654cbd66a19a98, 84 byte(s)
    made at      5b049987ddc8717cc33fb4bd967209e517ba0433
    environment  urn:astra-examples:cpython-3.14
made from
  noisy.points: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    no version of points's record gives them
$ sed -i 's/18cfe9d5695d7fc13a3d93bbbba2f6a644bd284d/2288818540727575fa0a5953bfebea956a07b787/' astra.yaml
$ astra check
.astra/records/points.json at 2288818540727575fa0a5953bfebea956a07b787  points  stale  present
  error STALE_RESULT the content of `config`, config.json, isn't what the recipe read
.astra/records/ols/fit.json  fit#ols  stale  present
  error STALE_RESULT `points`, which it reads through `noisy.points`, is stale
.astra/records/huber/fit.json  fit#huber  stale  present
  error STALE_RESULT `points`, which it reads through `noisy.points`, is stale
.astra/records/comparison.json  comparison  stale  present
  error STALE_RESULT `fit#ols`, which it reads, is stale
  error STALE_RESULT `fit#huber`, which it reads, is stale
astra.yaml
  53:19 error STALE_EVIDENCE `comparison` cites `comparison`, whose record is stale
astra.yaml: 4 place(s) of planned results, 0 unchanged, 4 stale, 0 missing; 0 absent
$ git checkout -q astra.yaml
```

- Valid: 18cfe9d is in the store already, an ancestor of 2dcf20f, and nothing compares a `url` declaration's commit with anything (`COMMIT_NOT_ANCESTOR` is only for `path` and `commit`).
- At 18cfe9d, `points` is unchanged: its record there was made at 2288818, and nothing it depends on changed between the two. The fits are stale because their records list the hash of the points at 2dcf20f: "made again since, with other bytes than it read" (`check.py:506`). The wording assumes a newer build, though the declaration moved back to an older one: astra-tools compares only the two digests, so an older build gives the same message. The check rules on a read-only result are §20's *Results of an analysis from a commit*.
- `lineage` resolves `points` against today's plan, where its one version is now at 18cfe9d, with another hash. So no version gives what the fit's record lists.
- At 2288818, `points`'s record is step 1's, made at c94c7b0 from 30 points, while `config.json` at 2288818 asks for 60: `points` itself is stale, and the fits read a stale result (`check.py:503`). A runner would refuse to build from it (`STALE_INPUT`).

</details>

2. `fit#huber` has two versions with one hash. Which other planned result of line-fit has two, and at which steps? Work it out from the build's eight steps, then check.

<details><summary>Answer</summary>

```console
$ astra history timeline comparison | grep -B1 bytes
  47395b7e07cfc906fc5615d3efb5c65938f8e01a
    bytes        sha256:b1bd0abed9eecbbcbd8c249873ce28ab6b856376561b780d3c0674a4f0457cb8, 204 byte(s)
--
  1e6c554d18d73e7d2d29be5140680d2a955dcd09
    bytes        sha256:444faf4dbe91be66de33a0c9c9e0889f2c3a06287e26ee685b8cc0c6453a284e, 204 byte(s)
--
  48b131e715b8be775ceb21754c35d1a4b1e9c00e
    bytes        sha256:8bcd008e9c04824cdf116a2d44d1f1f3028b449665f279e06cfa0fe57bb48ae2, 203 byte(s)
--
  5e496bf35e59765099614870b0a274f1368d3e28
    bytes        sha256:444faf4dbe91be66de33a0c9c9e0889f2c3a06287e26ee685b8cc0c6453a284e, 204 byte(s)
--
  aca519ee76e71f7392dbd216d2e1bc71d7d5adfd
    bytes        sha256:7bd1a00ea538783eadf53c5b1a69d35029413940b4725b1eeddb928d90dcb4dc, 204 byte(s)
$ astra history find --hash sha256:444faf4dbe91be66de33a0c9c9e0889f2c3a06287e26ee685b8cc0c6453a284e
comparison  .astra/records/comparison.json
  1e6c554d18d73e7d2d29be5140680d2a955dcd09
    bytes        sha256:444faf4dbe91be66de33a0c9c9e0889f2c3a06287e26ee685b8cc0c6453a284e, 204 byte(s)
    made at      b0e7c5691722b0f8c286513d34e6c954be5c605f
    environment  urn:astra-examples:cpython-3.14
  5e496bf35e59765099614870b0a274f1368d3e28
    bytes        sha256:444faf4dbe91be66de33a0c9c9e0889f2c3a06287e26ee685b8cc0c6453a284e, 204 byte(s)
    made at      398cd34fffabc1980aa9c770d0ac07deb95355d4
    environment  urn:astra-examples:cpython-3.14
2 version(s)
```

- The comparison, at steps 4 (5e496bf) and 6 (1e6c554). It reads both fits, and step 6 gives both the bytes of step 4: `fit#ols` wasn't rebuilt, and `fit#huber` came back to the same bytes.
- `fit#ols` has none: it was built only at steps 2, 4 and 8 (steps 5 and 6 used `--rebuild fit#huber`), each time from other points.
- Step 5's comparison is one byte shorter, 203: its `slope_difference` is 0.07068, a digit fewer (`astra history get 'comparison@HEAD~4'` shows it).

</details>

3. From line-fit, get noisy-line's `points` at `HEAD`, and at 18cfe9d. Predict which works, and how many lines it prints. Then compare its hash with what noisy-line's own history gives at its `HEAD~2` (`get` takes a `PATH` too), and with the timeline in step 7.

<details><summary>Answer</summary>

```console
$ astra history get 'points@HEAD'; echo "exit $?"
Usage: astra history get [OPTIONS] ADDR@REV [PATH]
Try 'astra history get --help' for help.

Error: Invalid value for ADDR@REV: `HEAD` names no commit of …/tour/work/05/cache/remotes/59e1d0836369cdb8035c557152283ff6f23a1eb38face13c06987dfcaaea4c71
exit 2
$ astra history get 'points@18cfe9d' | wc -l
61
$ astra history get 'points@18cfe9d' | sha256sum
11d14fd855f6a3eae39dcd3ffaa849d0d8f2562ea907b31eb140369af0c4d6d9  -
$ astra history get 'points@HEAD~2' ../noisy-line | sha256sum
11d14fd855f6a3eae39dcd3ffaa849d0d8f2562ea907b31eb140369af0c4d6d9  -
```

- `REV` is resolved in the repository that holds the result's analysis (`history.py:147-149`). For `points`, that is the store: a bare repository with no branch, so `HEAD` names nothing there, and the usage error names a path in the cache.
- A short id works, and any ancestor of the declared commit does too, since the fetch brought them all. `get` isn't limited to the declared commit, though `timeline` shows only that one version.
- 61 lines: a header and step 3's 60 points. The hash is the one step 7's noisy-line timeline gives for 18cfe9d, and the bytes are noisy-line's own at its `HEAD~2`.

</details>

4. Declare `before` at noisy-line's commit, 2dcf20f, which the cache's store holds (adapt step 5's first `sed`). Predict the code. Then clear the cache and validate offline: predict again.

<details><summary>Answer</summary>

```console
$ sed -i '/^analyses:/a\  before: {path: ., commit: "2dcf20f515e3eecf7e2126c182c54dd5f0f8f206"}' astra.yaml
$ astra validate; echo "exit $?"
astra.yaml
  4:29 error COMMIT_NOT_FOUND the repository that holds this file has no commit `2dcf20f515e3eecf7e2126c182c54dd5f0f8f206`: give a full id of one of its commits, or fetch the commit into it
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit 1
$ git checkout -q astra.yaml
$ astra cache clear
Cleared the cache in …/tour/work/05/cache.
$ astra validate --offline; echo "exit $?"
astra.yaml
  5:5 error REMOTE_UNREACHABLE the commit `2dcf20f515e3eecf7e2126c182c54dd5f0f8f206` can't be fetched from `file://…/tour/work/05/build/noisy-line`, and no earlier fetch kept it: check the URL and the commit, and that git can reach the remote (with --offline, nothing is fetched)
astra.yaml: invalid, 1 error(s), 0 warning(s)
exit 1
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra rules COMMIT_NOT_FOUND
COMMIT_NOT_FOUND
validator, MUST
In a file not read from a remote, a `path` and `commit` name a commit of the file's repository
$ astra rules REMOTE_UNREACHABLE
REMOTE_UNREACHABLE
validator, MUST, astra-tools
Every commit the stack gets from a remote (§17) can be got
```

- `COMMIT_NOT_FOUND`, the specification's code: a `path` and `commit` in a file not read from a remote is read only from the repository that holds the declaring file (`stack.py:338-340`), never from a store. It is reported at the `commit` value (`4:29`), and `COMMIT_NOT_ANCESTOR` isn't checked on it (design §4.13 case 3, `commits.py:52-59`).
- Offline with an empty cache, `REMOTE_UNREACHABLE`, astra-tools' own error (design §3), at the declaration (`5:5`, the `noisy` map), as in chapter 1's Try 4. `--offline` exists only on `validate`; `check`, `plan`, `info` and `history` always may fetch.
- The last `validate` fetches again, and the cache is back to one store with one blob.
- `astra rules` says whose each code is: the specification's, by its layer and level alone, or astra-tools' own, marked "astra-tools", from its table `OWN` beside `rules.json`'s (`src/astra/diagnostics.py:60`).

</details>

## What you now know

- A `url` declaration is read from a bare store per URL in the cache, fetched once by a ref of its own with all its ancestors. Its blobs are read lazily where the server honours `--filter=blob:none`, and a `file://` server doesn't unless `uploadpack.allowFilter` is set.
- A `path` and `commit` declaration, in a file not read from a remote, is read only from the repository that holds the declaring file (`COMMIT_NOT_FOUND` otherwise); in one read from a remote, from that remote (`REMOTE_UNREACHABLE` otherwise). A `path` alone is read the way the declaring analysis is read. An analysis is its folder and its commit; the URL isn't part of it.
- Analyses from a commit are read through `git cat-file --batch`, never checked out. `validate` reads their `astra.yaml`; `check` adds the records, inputs and bytes it compares; the code is never read.
- The cache holds `remotes`, `validity` (verdicts by astra-tools' version, folder and commit), `hashes` (working-tree files by inode), `worktrees` and `papers`, and all of it is safe to delete.
- Three stand-ins are built in and more can be registered under `astra.standins`. The checker takes what a stand-in at the path gives, and one that gives no SHA-256 leaves its result stale.
- `astra history` is `git log` over record paths, resolved against today's plan: a read-only result has one version, `lineage` matches by hash and size, and `get` checks the bytes against the record and resolves `REV` in the repository that holds the analysis, the store for a `url` one.
