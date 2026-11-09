"""Rebuild the examples from scratch and rerun the README's walk-through: python check.py.

Each ```console block of README.md is a session: a line starting `$ ` is a command, and the
lines after it, up to the next command or the end of the block, are what it prints, stdout and
stderr together. The blocks run in order, in one shell state of their own: `cd DIR` and
`export NAME=VALUE` carry over, and every other command runs in bash. The check fails where a
command prints anything else. With --update, the README is rewritten with what they print.

Run it with the Python that has astra-tools installed, and `astra` on PATH.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
README = HERE / "README.md"
BLOCK = re.compile(r"^```console\n(.*?)^```\n", re.S | re.M)


class Session:
    def __init__(self) -> None:
        self.cwd = HERE
        self.env = {**os.environ}
        self.env.pop("ASTRA_CACHE_DIR", None)
        self.env["NO_COLOR"] = "1"

    def run(self, command: str) -> str:
        if command.startswith("cd "):
            self.cwd = (self.cwd / command[3:].strip()).resolve()
            return ""
        if command.startswith("export "):
            name, _, value = command[7:].partition("=")
            self.env[name] = os.path.expandvars(value.strip('"').replace("$PWD", str(self.cwd)))
            return ""
        done = subprocess.run(["bash", "-c", command], cwd=self.cwd, env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        return done.stdout


def sessions(text: str) -> list[tuple[re.Match[str], list[tuple[str, str]]]]:
    """Each console block, with its commands and the output each shows."""
    found = []
    for block in BLOCK.finditer(text):
        steps: list[tuple[str, str]] = []
        for line in block[1].splitlines(keepends=True):
            if line.startswith("$ "):
                steps.append((line[2:].rstrip("\n"), ""))
            elif steps:
                steps[-1] = (steps[-1][0], steps[-1][1] + line)
        found.append((block, steps))
    return found


def main() -> int:
    update = "--update" in sys.argv[1:]
    subprocess.run([sys.executable, str(HERE / "build.py")], check=True, stdout=subprocess.DEVNULL)
    text = README.read_text(encoding="utf-8")
    session, failures, pieces, last = Session(), 0, [], 0
    for block, steps in sessions(text):
        body = ""
        for command, shown in steps:
            printed = session.run(command)
            body += f"$ {command}\n{printed}"
            if printed != shown:
                failures += 1
                print(f"--- `{command}` printed:\n{printed}--- where the README shows:\n{shown}")
        pieces += [text[last : block.start(1)], body]
        last = block.end(1)
    pieces.append(text[last:])
    if update:
        README.write_text("".join(pieces), encoding="utf-8")
        print("README.md updated")
        return 0
    print("the walk-through gives what the README shows" if not failures else
          f"{failures} command(s) printed something else")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
