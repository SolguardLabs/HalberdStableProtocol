from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(*args: str) -> None:
    subprocess.run(args, cwd=ROOT, check=True)


def main() -> None:
    run(sys.executable, "-m", "compileall", "-q", "scripts", "tests")
    run(sys.executable, "scripts/check_public.py")
    run(sys.executable, "scripts/compile_all.py")
    run(sys.executable, "-m", "pytest", "-q")
    run(sys.executable, "scripts/verify_release.py")


if __name__ == "__main__":
    main()
