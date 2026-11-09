"""Build the examples' git repositories from scratch, under build/: python build.py.

Each example in examples/ becomes a git repository of its own in build/, and the runner,
run.py, builds its results. Then the script makes a history of eight steps:

1. noisy-line is built and committed;
2. line-fit declares noisy-line at that commit, is built, and is committed;
3. noisy-line draws twice as many points, and is built again and committed;
4. line-fit declares noisy-line at its new commit, is built again, and is committed;
5. the Huber option's setting, HUBER_K in line-fit's src/fit.py, changes from 1.345 to 1.0,
   and line-fit's Huber fit is built again, and so is the comparison that reads it;
6. HUBER_K changes back to 1.345, and the Huber fit and the comparison are built again, with
   the bytes of step 4;
7. noisy-line pushes 6 of its points well above the line, not 3, and is built again;
8. line-fit declares noisy-line at that commit, is built again, and is committed.

Every commit has the same author and a fixed date, and git's own configuration is left out, so
building again gives the same commit ids, as long as build/ is in the same place and python3 has
the same version: line-fit names noisy-line by a file:// URL, its absolute path, and each record
names the Python the recipes ran with. The cache astra-tools keeps fetched commits and hashes in
is build/cache. Run it with the Python that has astra-tools installed.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
EXAMPLES = HERE / "examples"
START = datetime(2026, 11, 2, 9, 0, tzinfo=timezone.utc)


class Builder:
    def __init__(self) -> None:
        self.when = START
        self.env = {
            **os.environ,
            "ASTRA_CACHE_DIR": str(BUILD / "cache"),
            "GIT_CONFIG_GLOBAL": os.devnull,  # no signing, hooks or other settings of the user's
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Ada Example",
            "GIT_AUTHOR_EMAIL": "ada@example.org",
            "GIT_COMMITTER_NAME": "Ada Example",
            "GIT_COMMITTER_EMAIL": "ada@example.org",
        }

    def git(self, repo: Path, *args: str) -> str:
        done = subprocess.run(["git", "-C", str(repo), *args], env=self.env, check=True,
                              capture_output=True, text=True)
        return done.stdout.strip()

    def commit(self, repo: Path, message: str) -> str:
        """Commit everything in `repo`, an hour after the last commit, and give its id."""
        self.when += timedelta(hours=1)
        stamp = self.when.isoformat()
        self.env["GIT_AUTHOR_DATE"] = self.env["GIT_COMMITTER_DATE"] = stamp
        self.git(repo, "add", "--all")
        self.git(repo, "commit", "--quiet", "--message", message)
        commit = self.git(repo, "rev-parse", "HEAD")
        print(f"  {repo.name} {commit[:12]} {message}")
        return commit

    def run(self, repo: Path, *args: str) -> None:
        """Build `repo`'s results with run.py."""
        subprocess.run([sys.executable, str(HERE / "run.py"), str(repo), *args], env=self.env,
                       check=True, stdout=subprocess.DEVNULL)

    def start(self, name: str) -> Path:
        """A new repository in build/ holding examples/`name`."""
        repo = BUILD / name
        shutil.copytree(EXAMPLES / name, repo, ignore=shutil.ignore_patterns("__pycache__"))
        self.git(repo, "init", "--quiet", "--initial-branch", "main")
        return repo


def edit(path: Path, pattern: str, replacement: str) -> None:
    """Replace the one match of `pattern` in the file at `path`."""
    text, count = re.subn(pattern, replacement, path.read_text(encoding="utf-8"), flags=re.M)
    assert count == 1, (path, pattern)
    path.write_text(text, encoding="utf-8")


def declare(line_fit: Path, noisy_line: Path, commit: str) -> None:
    """Point line-fit's declaration of noisy-line at `commit` of the repository `noisy_line`."""
    yaml = line_fit / "astra.yaml"
    edit(yaml, r"^    url: .*$", f"    url: {noisy_line.as_uri()}")
    edit(yaml, r'^    commit: ".*"$', f'    commit: "{commit}"')


def main() -> None:
    shutil.rmtree(BUILD, ignore_errors=True)
    BUILD.mkdir()
    b = Builder()

    print("1. noisy-line is built and committed")
    noisy = b.start("noisy-line")
    b.commit(noisy, "Generate noisy points around a line")
    b.run(noisy)
    first = b.commit(noisy, "Build the points")

    print("2. line-fit declares noisy-line at that commit, and is built and committed")
    line = b.start("line-fit")
    declare(line, noisy, first)
    b.commit(line, "Fit noisy-line's points by least squares and by the Huber loss")
    b.run(line)
    b.commit(line, "Build the fits and their comparison")

    print("3. noisy-line draws twice as many points, and is built again")
    edit(noisy / "config.json", r'^  "points": 30,$', '  "points": 60,')
    b.commit(noisy, "Draw 60 points")
    b.run(noisy)
    second = b.commit(noisy, "Build the points again")

    print("4. line-fit declares noisy-line's new commit, and is built again")
    declare(line, noisy, second)
    b.commit(line, "Read noisy-line's 60 points")
    b.run(line)
    b.commit(line, "Build the fits and their comparison again")

    print("5. the Huber option's setting changes, and what it changes is built again")
    edit(line / "src" / "fit.py", r"^HUBER_K = 1\.345$", "HUBER_K = 1.0")
    b.commit(line, "Huber: turn linear from 1.0 robust standard deviations")
    b.run(line, "--rebuild", "fit#huber")
    b.commit(line, "Build the Huber fit and the comparison again")

    print("6. the Huber option's setting changes back, and what it changes is built again")
    edit(line / "src" / "fit.py", r"^HUBER_K = 1\.0$", "HUBER_K = 1.345")
    b.commit(line, "Huber: back to 1.345 robust standard deviations, the usual choice")
    b.run(line, "--rebuild", "fit#huber")
    b.commit(line, "Build the Huber fit and the comparison at 1.345")

    print("7. noisy-line pushes twice as many points above the line, and is built again")
    edit(noisy / "config.json", r'^  "outliers": 3,$', '  "outliers": 6,')
    b.commit(noisy, "Push 6 points above the line, not 3")
    b.run(noisy)
    third = b.commit(noisy, "Build the points with 6 outliers")

    print("8. line-fit declares noisy-line's newest commit, and is built again")
    declare(line, noisy, third)
    b.commit(line, "Read noisy-line's points with 6 outliers")
    b.run(line)
    b.commit(line, "Build the fits and their comparison with 6 outliers")


if __name__ == "__main__":
    main()
