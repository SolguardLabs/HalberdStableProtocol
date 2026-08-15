from __future__ import annotations

import ast
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def repository_files() -> list[Path]:
    output = subprocess.check_output(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
        cwd=ROOT,
    )
    return sorted(
        path
        for item in output.decode("utf-8").split("\0")
        if item and (path := ROOT / item).is_file()
    )


def main() -> None:
    checked = 0
    for path in repository_files():
        if path.suffix == ".py":
            ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            checked += 1
        if path.suffix in {".py", ".vy", ".md", ".yml", ".yaml", ".toml"}:
            text = path.read_text(encoding="utf-8")
            if "\t" in text:
                raise SystemExit(f"tab character found in {path.relative_to(ROOT)}")
            if not text.endswith("\n"):
                raise SystemExit(f"missing final newline in {path.relative_to(ROOT)}")
            for number, line in enumerate(text.splitlines(), start=1):
                if line.rstrip() != line:
                    raise SystemExit(
                        f"trailing whitespace in {path.relative_to(ROOT)}:{number}"
                    )

    print(f"checked {checked} Python files and repository text hygiene")


if __name__ == "__main__":
    main()
