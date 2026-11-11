# ASTRA examples

Two small analyses in ASTRA v0.1, each in a git repository of its own, and a history of
changes to them, to show what ASTRA records and what astra-tools can tell you from it.

- **noisy-line** draws noisy points around a straight line, from a seeded script and a
  tracked config. Its one result, `points`, is built once, and its bytes are committed with
  its record, so that other analyses can read it at a commit.
- **line-fit** declares noisy-line by URL and commit, and fits a line to its points in two
  ways: a decision, `method`, with two options, `ols` (least squares) and `huber` (the Huber
  loss, which outliers pull less), and a universe for each. Its `fit` is built per universe,
  its `comparison` is built once from `fit#ols` and `fit#huber`, and a finding cites the
  comparison as evidence.

The scripts use Python's standard library alone. `examples/` holds the sources, `build.py`
makes the repositories under `build/`, `run.py` is the small runner that builds the results,
and `check.py` rebuilds everything and checks that every command below prints what is shown.

## Setting up

You need git, Python 3.11 or later, and astra-tools from its `v0.1-rebuild` branch, here at
`d7b20ec`, which reads ASTRA 0.1 at astra-spec `6c0ddb4`. Set it up as its CLAUDE.md's
*Development* section says, then put its environment first on your PATH, so that `astra` and
the Python that has astra-tools are the ones run:

    export PATH=/path/to/astra-tools/.venv/bin:$PATH

Then build the examples:

```console
$ python build.py
1. noisy-line is built and committed
  noisy-line c94c7b063ef9 Generate noisy points around a line
  noisy-line 2c5197a98df7 Build the points
2. line-fit declares noisy-line at that commit, and is built and committed
  line-fit 9f236ccb9bd6 Fit noisy-line's points by least squares and by the Huber loss
  line-fit 0108bb956d64 Build the fits and their comparison
3. noisy-line draws twice as many points, and is built again
  noisy-line 228881854072 Draw 60 points
  noisy-line 18cfe9d5695d Build the points again
4. line-fit declares noisy-line's new commit, and is built again
  line-fit 3032833ac1f0 Read noisy-line's 60 points
  line-fit 84b91dce5699 Build the fits and their comparison again
5. the Huber option's setting changes, and what it changes is built again
  line-fit 3e45dccdacfa Huber: turn linear from 1.0 robust standard deviations
  line-fit 8e3378d96e3a Build the Huber fit and the comparison again
6. the Huber option's setting changes back, and what it changes is built again
  line-fit 8b637b90c974 Huber: back to 1.345 robust standard deviations, the usual choice
  line-fit f03a04503999 Build the Huber fit and the comparison at 1.345
7. noisy-line pushes twice as many points above the line, and is built again
  noisy-line 3732bd7f8be4 Push 6 points above the line, not 3
  noisy-line 2dcf20f515e3 Build the points with 6 outliers
8. line-fit declares noisy-line's newest commit, and is built again
  line-fit 3db2bfb4848f Read noisy-line's points with 6 outliers
  line-fit 70524159bb29 Build the fits and their comparison with 6 outliers
```

Each step commits as an author with a fixed date, so the commit ids are the same each time
you build in the same place with the same Python. line-fit names noisy-line by a `file://`
URL, its absolute path, so its ids are these only where `build/` is where it was built for
this README. Each record names the Python the recipes ran with, the `python3` on PATH by its
version, here CPython 3.14, so from the first commit that holds a record, the ids are these
only with that version. Moving the repositories to GitHub changes only the `url` line of
line-fit's declaration, and with it line-fit's ids.

## The analyses

noisy-line's `astra.yaml` has an input, its config, and an output made from it:

```yaml
inputs:
  config:
    path: config.json
outputs:
  points:
    type: data
    format: csv
    inputs: [config]
    recipe:
      command: python3 src/make_points.py {inputs.config} {output}
```

line-fit declares noisy-line at a commit, and reads its points as `noisy.points`:

```yaml
analyses:
  noisy:
    url: file:///…/build/noisy-line
    commit: "2dcf20f515e3eecf7e2126c182c54dd5f0f8f206"
decisions:
  method:
    options: {ols: {}, huber: {}}
outputs:
  fit:
    inputs: [noisy.points]
    decisions: [method]
    recipe:
      command: python3 src/fit.py {decisions.method} {inputs.noisy.points} {output}
  comparison:
    inputs: [fit#ols, fit#huber]
    recipe:
      command: python3 src/compare.py {inputs.fit#ols} {inputs.fit#huber} {output}
universes:
  ols: {decisions: {method: ols}}
  huber: {decisions: {method: huber}}
findings:
  outliers_lift_least_squares:
    claim: The Huber line has a lower intercept than the least-squares line ...
    evidence:
      - artifact: comparison
```

(Labels and descriptions are left out here; the files in `examples/` have them.)

## Validating, describing and planning

Work in line-fit's repository. astra-tools keeps the commits it fetches from noisy-line in its
cache, here `build/cache`:

```console
$ cd build/line-fit
$ export ASTRA_CACHE_DIR="$PWD/../cache"
$ astra validate
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra validate ../noisy-line
astra.yaml: valid, 0 error(s), 0 warning(s)
$ astra info
astra.yaml
  analyses  noisy: astra.yaml at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 from file:///home/r/Projects/LightconeResearch/worktrees/astra-examples-history/build/noisy-line
  outputs   fit: table, json
            comparison: table, json
  decisions method: ols, huber
  universes ols
            huber
astra.yaml at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206 from file:///home/r/Projects/LightconeResearch/worktrees/astra-examples-history/build/noisy-line
  inputs    config: config.json
  outputs   points: data, csv
```

The plan lists every planned result, each after what it reads, with where its record and its
bytes go:

```console
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
```

`points` belongs to noisy-line at the declared commit, so it isn't built here: it is read
through its record at that commit. Its bytes aren't in line-fit's checkout either, so the plan
writes them as git does, `<commit>:<path>`; a runner gets them from git and passes their path
to the recipe.

## Checking

Every planned result has a record, and nothing it was made from has changed since, so all of
them are `unchanged`, and their bytes `present`:

```console
$ astra check
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
.astra/records/ols/fit.json  fit#ols  unchanged  present
.astra/records/huber/fit.json  fit#huber  unchanged  present
.astra/records/comparison.json  comparison  unchanged  present
astra.yaml
  53:19 unchanged `comparison`
astra.yaml: 4 place(s) of planned results, 4 unchanged, 0 stale, 0 missing; 0 absent
```

Change something a result depends on, without committing it: here the `huber` universe
selects `ols` instead. Its fit is now `stale`, and so are the comparison that reads it and the
finding that cites the comparison:

```console
$ perl -pi -e 's/decisions: \{method: huber\}/decisions: {method: ols}/' astra.yaml
$ astra check
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
.astra/records/ols/fit.json  fit#ols  unchanged  present
.astra/records/huber/fit.json  fit#huber  stale  present
  error STALE_RESULT `method` selects `ols` in `huber`, where it selected `huber` at 3db2bfb4848f
.astra/records/comparison.json  comparison  stale  present
  error STALE_RESULT `fit#huber`, which it reads, is stale
astra.yaml
  53:19 error STALE_EVIDENCE `comparison` cites `comparison`, whose record is stale
astra.yaml: 4 place(s) of planned results, 2 unchanged, 2 stale, 0 missing; 0 absent
$ git checkout --quiet astra.yaml
```

`--at` checks the analysis as it was at a commit, with its records and bytes there. One
commit back, at step 8, line-fit had just moved its declaration to noisy-line's points with 6
outliers, and nothing was built yet. Its records there were made from the points with 3:

```console
$ astra check --at HEAD~1
.astra/records/points.json at 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206  points  unchanged  present
.astra/records/ols/fit.json at 3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c  fit#ols  stale  present
  error STALE_RESULT `points`, which it reads through `noisy.points`, was made again since, with other bytes than it read
.astra/records/huber/fit.json at 3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c  fit#huber  stale  present
  error STALE_RESULT `points`, which it reads through `noisy.points`, was made again since, with other bytes than it read
.astra/records/comparison.json at 3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c  comparison  stale  present
  error STALE_RESULT `fit#ols`, which it reads, is stale
  error STALE_RESULT `fit#huber`, which it reads, is stale
astra.yaml at 3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c
  53:19 error STALE_EVIDENCE `comparison` cites `comparison`, whose record is stale
astra.yaml at 3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c: 4 place(s) of planned results, 1 unchanged, 3 stale, 0 missing; 0 absent
```

The next commit, HEAD, holds them built again: that is the check above, where every result is
`unchanged`.

## History

`astra history` reads what git holds of a result's records over time, in the repository that
holds its analysis. Here is line-fit's history, newest first, which `HEAD~1`, `HEAD~2` and so
on count back through:

```console
$ git log --oneline
7052415 Build the fits and their comparison with 6 outliers
3db2bfb Read noisy-line's points with 6 outliers
f03a045 Build the Huber fit and the comparison at 1.345
8b637b9 Huber: back to 1.345 robust standard deviations, the usual choice
8e3378d Build the Huber fit and the comparison again
3e45dcc Huber: turn linear from 1.0 robust standard deviations
84b91dc Build the fits and their comparison again
3032833 Read noisy-line's 60 points
0108bb9 Build the fits and their comparison
9f236cc Fit noisy-line's points by least squares and by the Huber loss
```

Each version of a record is its file at a commit that changed it. The Huber fit was built five
times: at steps 2 and 4, at steps 5 and 6, when its setting changed and changed back, and at
step 8. Step 6 gave it the bytes of step 4 again, so those two versions have the same hash:

```console
$ astra history timeline 'fit#huber'
fit#huber  .astra/records/huber/fit.json
  70524159bb294d6fdf3a64fcd419ca200da7d766
    bytes        sha256:fdbc97616ab1d246f9c6ef4137a0dbc345623ce4d9547e7e541342e9c7b40cf4, 86 byte(s)
    made at      3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c
    environment  urn:astra-examples:cpython-3.14
  f03a04503999803cb19bfec6350f2990271d03b8
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      8b637b90c974dcb5db9ff6d2e6d8a09d42471b4b
    environment  urn:astra-examples:cpython-3.14
  8e3378d96e3a56f78ad953799849f941a5ee69c0
    bytes        sha256:72c18945d6a304e5887bca9bd3fa5628a8fa2dc33900083538d1fa1277aa7aa3, 86 byte(s)
    made at      3e45dccdacfa3d8303d9f193005d2a4dc4190ba8
    environment  urn:astra-examples:cpython-3.14
  84b91dce5699cbf6251a2145fef2fac6ac8fc556
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      3032833ac1f0a3c78a74633165901fd2d76f6814
    environment  urn:astra-examples:cpython-3.14
  0108bb956d644c326ee5d60437c182eae5b5b02a
    bytes        sha256:6e373f83ec8711725574156cd02b6571e249e9b5c971fbb793d9055ea3396132, 86 byte(s)
    made at      9f236ccb9bd6b54dfa774248e30f77006739392b
    environment  urn:astra-examples:cpython-3.14
5 version(s)
```

`find --hash` gives the versions of every planned result's record whose bytes have a hash,
here that one:

```console
$ astra history find --hash sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b
fit#huber  .astra/records/huber/fit.json
  f03a04503999803cb19bfec6350f2990271d03b8
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      8b637b90c974dcb5db9ff6d2e6d8a09d42471b4b
    environment  urn:astra-examples:cpython-3.14
  84b91dce5699cbf6251a2145fef2fac6ac8fc556
    bytes        sha256:44c15377928affe5652ede77ce155a77160138143faba005313400d8497df07b, 86 byte(s)
    made at      3032833ac1f0a3c78a74633165901fd2d76f6814
    environment  urn:astra-examples:cpython-3.14
2 version(s)
```

`find --environment IRI` gives the versions whose records name that environment, in the same
way. It isn't shown here: every record names the one Python the recipes ran with, so it would
give them all.

What a result was made from, as its record at HEAD says, down to the input files, across the
two repositories: the comparison read the two fits, each fit read noisy-line's points, and
the points were made from noisy-line's `config.json`:

```console
$ astra history lineage comparison
comparison  .astra/records/comparison.json
  70524159bb294d6fdf3a64fcd419ca200da7d766
    bytes        sha256:b1bd0abed9eecbbcbd8c249873ce28ab6b856376561b780d3c0674a4f0457cb8, 204 byte(s)
    made at      3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c
    environment  urn:astra-examples:cpython-3.14
made from
  fit#ols: sha256:6d8749c475f92a9acd5ee42be9112929f4a2a9149ff30a66c1654cbd66a19a98, 84 byte(s)
    fit#ols's record of 70524159bb294d6fdf3a64fcd419ca200da7d766, made at 3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c
    noisy.points: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
      points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
      config: sha256:75c96f73e6c6ec40e5d516d601ef759f54a27dd9819d14a7def9ebb2e853a58d, 101 byte(s)
        the file config.json
  fit#huber: sha256:fdbc97616ab1d246f9c6ef4137a0dbc345623ce4d9547e7e541342e9c7b40cf4, 86 byte(s)
    fit#huber's record of 70524159bb294d6fdf3a64fcd419ca200da7d766, made at 3db2bfb4848fe1ed2428acd6b1f17cd97ea76d4c
    noisy.points: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
      points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
      config: sha256:75c96f73e6c6ec40e5d516d601ef759f54a27dd9819d14a7def9ebb2e853a58d, 101 byte(s)
        the file config.json
```

`--used-by` goes the other way: the planned results whose records at HEAD list a result. Both
fits read noisy-line's points:

```console
$ astra history lineage points --used-by
points  .astra/records/points.json
  2dcf20f515e3eecf7e2126c182c54dd5f0f8f206
    bytes        sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    made at      3732bd7f8be4fcc70b1582a104224d2a55d14cea
    environment  urn:astra-examples:cpython-3.14
used by
  fit#ols, its record of 70524159bb294d6fdf3a64fcd419ca200da7d766, through `noisy.points`: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
  fit#huber, its record of 70524159bb294d6fdf3a64fcd419ca200da7d766, through `noisy.points`: sha256:f207f31c1130d630505807629ce9ee21d491851372f4a22de2fe15f3c8d58c47, 1117 byte(s)
    points's record of 2dcf20f515e3eecf7e2126c182c54dd5f0f8f206, made at 3732bd7f8be4fcc70b1582a104224d2a55d14cea
```

`get` gives the bytes a result had at a commit, checked against its record there. Two commits
back, at step 6, the comparison was made from noisy-line's 60 points with 3 outliers; at HEAD,
from the same 60 points with 6. The extra outliers lift the least-squares line's intercept from
1.77 to 2.94, and the Huber line stays near the line noisy-line draws around, with slope 2 and
intercept 1:

```console
$ astra history get 'comparison@HEAD~2'
{
  "ols": {
    "slope": 1.954668,
    "intercept": 1.766548
  },
  "huber": {
    "slope": 2.020757,
    "intercept": 1.041911
  },
  "slope_difference": 0.066089,
  "intercept_difference": -0.724637
}
$ astra history get 'comparison@HEAD'
{
  "ols": {
    "slope": 1.833439,
    "intercept": 2.940937
  },
  "huber": {
    "slope": 2.011187,
    "intercept": 1.136179
  },
  "slope_difference": 0.177748,
  "intercept_difference": -1.804758
}
```

## The runner

`run.py` is a tiny runner built on astra-tools' API (`astra.api`, and the helpers in
`astra.records`); lightcone-cli is the real one. It builds what the analysis needs, in the
plan's order and each result once: every planned result that isn't `unchanged` and `present`,
and everything that reads a result it has just built. It keeps the specification's runner
rules. With every result unchanged, there is nothing to do:

```console
$ python ../../run.py
nothing to build: every result is unchanged
```

The everyday loop, here in noisy-line: change what a result depends on, see it go stale,
commit, build, and commit what was built. The runner refuses to run a recipe while the change
is uncommitted, so that every recipe runs from a commit, and each record names that commit.
The records are then committed in the next one:

```console
$ cd ../noisy-line
$ perl -pi -e 's/"noise": 0.5/"noise": 0.6/' config.json
$ astra check
.astra/records/points.json  points  stale  present
  error STALE_RESULT the content of `config`, config.json, isn't what the recipe read
astra.yaml: 1 place(s) of planned results, 0 unchanged, 1 stale, 0 missing; 0 absent
$ python ../../run.py
run.py: uncommitted changes: commit or discard them first: config.json
$ git commit --quiet --all --message "Noisier points"
$ python ../../run.py
points: python3 src/make_points.py config.json results/points.csv
1 result(s) built
$ astra check
.astra/records/points.json  points  unchanged  present  not committed
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
$ git add --all && git commit --quiet --message "Build the noisier points"
$ astra check
.astra/records/points.json  points  unchanged  present
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
```

### Building while you work

The runner refuses to build while you have uncommitted changes. With `--worktree`, it builds
HEAD in a checkout of its own instead, which astra-tools makes in its cache and the runner
removes afterwards, so you can go on editing while it runs. Each finished result is then moved
into your working tree, its bytes and then its record, without touching your index. Here a
change is committed, and another is still in progress when the build starts:

```console
$ perl -pi -e 's/"noise": 0.6/"noise": 0.7/' config.json
$ git commit --quiet --all --message "Noisier still"
$ perl -pi -e 's/"slope": 2.0/"slope": 2.5/' config.json
$ python ../../run.py
run.py: uncommitted changes: commit or discard them first: config.json
$ python ../../run.py --worktree
points: python3 src/make_points.py config.json results/points.csv
1 result(s) built in a checkout of HEAD, 1 place(s) moved here
$ astra check
.astra/records/points.json  points  stale  present  not committed
  error STALE_RESULT the content of `config`, config.json, isn't what the recipe read
astra.yaml: 1 place(s) of planned results, 0 unchanged, 1 stale, 0 missing; 0 absent
```

The points were made from HEAD's `config.json`, so against your working tree, where the slope
is being changed, they are `stale`, and they aren't committed yet. Drop the change in
progress, and they are `unchanged`; commit them when you choose:

```console
$ git checkout --quiet config.json
$ astra check
.astra/records/points.json  points  unchanged  present  not committed
astra.yaml: 1 place(s) of planned results, 1 unchanged, 0 stale, 0 missing; 0 absent
$ git add --all && git commit --quiet --message "Build the noisier points"
```

Commit what was moved before the next `--worktree` run: until HEAD holds those records, a run
from HEAD can't see them, and builds them again.

line-fit reads noisy-line's points at the commit it declares, so it is unaffected until it
moves its declaration to the new commit, as steps 4 and 8 did. Had noisy-line committed the
new `config.json` without building, line-fit could declare a commit whose points are `stale`:
`astra check` would show them so, and the runner would refuse to build anything from them
(`STALE_INPUT`), since a result read at a commit is never built again, only read.

The runner gets the bytes of `points` from git at the declared commit, checked against its
record there. `--rebuild ADDR` builds a result again even where it is unchanged, and an
output's name without a universe, such as `fit`, builds all its results: steps 5 and 6 used
it after editing the Huber setting in `src/fit.py`, since ASTRA records the code by its commit
but doesn't compare it. The comparison reads the Huber fit, so it was built again too. If a
recipe fails, the runner puts back the bytes it was replacing.
