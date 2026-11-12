"""A tiny runner for ASTRA v0.1, built on astra-tools: python run.py [PATH] [--rebuild ADDR]
[--worktree].

It builds what the analysis in PATH (the current folder by default) needs, in the plan's
order, each result at most once: every planned result that isn't `unchanged` and `present`,
every one that reads a result built earlier in the same run, and those --rebuild names. It
keeps the specification's runner rules, the runner layer of its Rules:

- UNCOMMITTED_CHANGES: before each recipe, it refuses to run while the checkout holds changes
  other than the records and results of a run, so every recipe runs from a commit (HEAD);
- REBUILT_FROM_COMMIT and STALE_INPUT: it never builds a result of an analysis read at a
  commit. It refuses to build anything that reads one that isn't `unchanged` and `present`,
  and otherwise gets its bytes from git at that commit, checked against its record;
- WRONG_WORKING_DIRECTORY: each recipe runs in its analysis's folder;
- UNRECORDED_RESULT and FALSE_RECORD: it writes a record at each of the result's places,
  naming the commit it ran from and the Python the recipes ran with.

If a recipe fails, the bytes it was replacing are put back.

By default it runs in the working tree, which must then hold no uncommitted change. With
--worktree it runs in a checkout of HEAD of its own, which astra-tools makes in its cache
(`Repository.worktree`), so you can go on editing while it runs: UNCOMMITTED_CHANGES is
about the checkout a recipe runs in. Each result finished there is then moved into the
working tree, its bytes and then its record, and no git command touches the working tree
(`records.land`); a record there from a later commit is kept. You commit them when you choose.

lightcone-cli is the real runner: this one runs one recipe at a time, and drives no analysis
from a commit.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from astra import api
from astra.check import CheckReport
from astra.history import NotInHistoryError
from astra.plan import Result, render_command
from astra.records import Runner, land, new_record, uncommitted_changes, write_record
from astra.cache import CacheError
from astra.sources.git import GitError, Repository

RUNNER = Runner("astra-examples/run.py", "0.3")


class Refused(Exception):
    """What stops the run, said to the user."""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", nargs="?", default=".", help="the analysis's folder")
    parser.add_argument("--rebuild", action="append", default=[], metavar="ADDR",
                        help="build this result again, even if it is unchanged")
    parser.add_argument("--worktree", action="store_true",
                        help="build in a checkout of HEAD of its own, and move what it makes here")
    arguments = parser.parse_args()
    folder = Path(arguments.path).resolve()
    try:
        if arguments.worktree:
            built, landed = run_in_own_checkout(folder, set(arguments.rebuild))
        else:
            built, landed = run(folder, set(arguments.rebuild)), None
    except Refused as refusal:
        print(f"run.py: {refusal}", file=sys.stderr)
        return 1
    if not built:
        print("nothing to build: every result is unchanged")
    elif landed is None:
        print(f"{len(built)} result(s) built")
    else:
        print(f"{len(built)} result(s) built in a checkout of HEAD, {landed} place(s) moved here")
    return 0


def run_in_own_checkout(folder: Path, rebuild: set[str]) -> tuple[list[Result], int]:
    """Build what the analysis in `folder` needs at HEAD, in a checkout of HEAD of its own, and
    move each result finished there into `folder`'s working tree; give the results built and
    how many places were moved. The checkout is removed afterwards."""
    main = Repository.discover(folder)
    commit = None if main is None else main.head()
    if main is None or commit is None:
        raise Refused(f"{folder} isn't in a git repository with a commit")
    try:
        own = main.worktree(commit)
    except (GitError, CacheError) as error:
        raise Refused(str(error)) from None
    try:
        built = run(own.top / folder.relative_to(main.top), rebuild)
        return built, len(land(own.top, main.top, built))
    finally:
        subprocess.run(["git", "-C", str(main.top), "worktree", "remove", "--force",
                        str(own.top)], capture_output=True)


def run(folder: Path, rebuild: set[str]) -> list[Result]:
    """Build what the analysis in `folder` needs, in the checkout that holds it; give the
    results built."""
    repo = Repository.discover(folder)
    if repo is None or repo.head() is None:
        raise Refused(f"{folder} isn't in a git repository with a commit")
    report = api.check(folder)
    if report.errors:
        raise Refused("the analysis breaks a MUST: `astra validate` says where")
    forced = forced_results(report, rebuild)
    environment = python_environment()
    built: dict[int, Result] = {}  # the results built in this run, by id()
    for checked in report.results:
        result = checked.result
        if result.read_only:
            continue  # read through its record at a commit, never built here (REBUILT_FROM_COMMIT)
        done = all(s.record_status == "unchanged" and s.bytes_status == "present"
                   for s in checked.statuses)
        reads_new = any(read.result is not None and id(read.result) in built
                        for read in result.inputs)
        if done and not reads_new and id(result) not in forced:
            continue
        changes = uncommitted_changes(repo.top)
        if changes:
            raise Refused("uncommitted changes: commit or discard them first: "
                          + ", ".join(changes))
        build(result, report, repo, folder, environment)
        built[id(result)] = result
    return list(built.values())


def forced_results(report: CheckReport, rebuild: set[str]) -> set[int]:
    """The results --rebuild names, by id(): an address names one; an output's name without a
    universe, all its results. Refused where one names nothing this runner builds."""
    forced: set[int] = set()
    for address in rebuild:
        named = [checked.result for checked in report.results
                 if any(place.address == address or place.address.split("#")[0] == address
                        for place in checked.result.places)]
        if not named:
            raise Refused(f"--rebuild {address}: no planned result has that address")
        if all(result.read_only for result in named):
            raise Refused(f"--rebuild {address}: it is read through its record at a commit, "
                          "and isn't built here")
        forced |= {id(result) for result in named if not result.read_only}
    return forced


def python_environment() -> str:
    """The environment the recipes run in, as an IRI: the `python3` on PATH, by its version."""
    done = subprocess.run(
        ["python3", "-c", "import platform as p; print(p.python_implementation().lower() + '-'"
                          " + '.'.join(p.python_version_tuple()[:2]))"],
        capture_output=True, text=True,
    )
    if done.returncode != 0:
        raise Refused("the recipes run `python3`, and there is none on PATH")
    return f"urn:astra-examples:{done.stdout.strip()}"


def build(result: Result, report: CheckReport, repo: Repository, folder: Path,
          environment: str) -> None:
    """Run `result`'s recipe in its analysis's folder, put its bytes at each of its default
    places, and write its records; put the old bytes back if the recipe fails."""
    names = ", ".join(place.address for place in result.places)
    if result.run_at is not None:
        raise Refused(f"{names}: this runner drives no analysis from a commit")
    statuses = {id(checked.result): checked.statuses for checked in report.results}
    top = repo.top
    with tempfile.TemporaryDirectory(prefix="astra-run-") as kept:
        got = {}
        for read in result.inputs:
            if read.commit is None:
                continue  # in the working tree, where the recipe opens it
            if read.result is None or read.place is None:
                raise Refused(f"{names}: `{read.entry}` is an input of an analysis at a commit, "
                              "and this runner doesn't get input files from git")
            if id(read.result) not in statuses or not all(
                s.record_status == "unchanged" and s.bytes_status == "present"
                for s in statuses[id(read.result)]
            ):
                raise Refused(f"{names}: `{read.entry}` reads a result at a commit that isn't "
                              "unchanged and present, so nothing can be built from it "
                              "(STALE_INPUT)")
            try:  # its bytes at that commit, checked against its record there
                data = api.history(folder).get(read.place.address, read.commit)
            except NotInHistoryError as error:
                raise Refused(f"{names}: can't get `{read.entry}`: {error}") from None
            path = Path(kept) / f"{len(got)}-{Path(read.path).name}"
            path.write_bytes(data)
            got[read.entry] = str(path)
        old = Path(kept) / "old"
        old.mkdir()
        for i, place in enumerate(result.places):
            target = top / place.bytes
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                shutil.copy2(target, old / str(i))
        cwd = top / result.workdir
        command = render_command(result, cwd, got=got)
        print(f"{names}: {command}", flush=True)
        if subprocess.run(command, shell=True, cwd=cwd).returncode != 0:
            for i, place in enumerate(result.places):
                saved, target = old / str(i), top / place.bytes
                if saved.exists():
                    shutil.copy2(saved, target)
                else:
                    target.unlink(missing_ok=True)
            raise Refused(f"{names}: the recipe failed, and the bytes it replaced are back: "
                          f"{command}")
        for place in result.places[1:]:  # `{output}` is the first name's place
            shutil.copyfile(top / result.places[0].bytes, top / place.bytes)
        records = new_record(result, checkout=top, commit=repo.head(), environment=environment,
                             runner=RUNNER, got=got)
    for place, record in zip(result.places, records, strict=True):
        write_record(top / place.record, record)


if __name__ == "__main__":
    sys.exit(main())
