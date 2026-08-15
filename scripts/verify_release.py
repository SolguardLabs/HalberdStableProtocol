from __future__ import annotations

import ast
import hashlib
import re
import struct
import subprocess
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_DOCS = [
    "docs/arquitectura.md",
    "docs/despliegue-seguro.md",
    "docs/integracion.md",
    "docs/modelo-economico.md",
    "docs/operaciones.md",
    "docs/oraculos-y-riesgo.md",
    "docs/vaults-y-liquidaciones.md",
]
PROTECTED = {
    "src/HalberdStabilityModule.vy": "AB76D0BD867AB12E1E3F7715FF410007586E3E0E152FB8B3D010C6999D772CE2",
    "src/HalberdVaults.vy": "82899F0957DEABAF9A95EDDF3F5F5E3CB95991A671D58D92BC847CE757AF2271",
    "src/HalberdRiskEngine.vy": "CA2CC88715B4B1D94694AD24AC1E0987E71A4E90BCCD159E548055C8F7297350",
    "src/HalberdOracle.vy": "29FD3292707B16F027D08E1415357E8652A410D08159FF2B73993607B1717ED9",
}
TEXT_SUFFIXES = {".vy", ".py", ".md", ".yml", ".yaml", ".toml", ".txt", ".sh", ".ps1"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def normalized(path: Path) -> bytes:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").encode()


def repository_files() -> list[Path]:
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    )
    return sorted(
        path
        for item in output.decode().split("\0")
        if item and (path := ROOT / item).is_file()
    )


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def main() -> None:
    files = repository_files()
    names = [relative(path) for path in files]
    metadata = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
    assert metadata["project"]["version"] == "1.0.0"
    assert [name for name in names if name.startswith("docs/") and name.endswith(".md")] == EXPECTED_DOCS

    for name, expected in PROTECTED.items():
        assert sha256(normalized(ROOT / name)) == expected, f"{name} changed"

    banner = (ROOT / "assets/banner.png").read_bytes()
    assert sha256(banner) == "D31A5C6B7A0385A02CD1BD4E08D9D598BF82968861217E7EBDA28916223CF3CE"
    assert banner[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = struct.unpack(">II", banner[16:24])
    assert (width, height) == (1672, 941)

    docs = "\n".join(
        (ROOT / name).read_text(encoding="utf-8")
        for name in ["README.md", "SECURITY.md", *EXPECTED_DOCS]
    )
    assert len(re.findall(r"^```mermaid$", docs, flags=re.MULTILINE)) == 27
    assert "assets/banner.png" in (ROOT / "README.md").read_text(encoding="utf-8")

    restricted_parts = [
        "c" + "tf",
        "la" + "bs?",
        "labor" + "atorios?",
        "vulner" + "ability",
        "vulner" + "abilidad",
        "vulner" + "able",
        "bu" + "gs?",
        "ex" + "ploit",
        "by" + "pass",
        "attack" + "ers?",
        "atac" + "antes?",
    ]
    restricted = re.compile(rf"\b(?:{'|'.join(restricted_parts)})\b", re.IGNORECASE)
    for path in files:
        if path.suffix.lower() in TEXT_SUFFIXES:
            assert not restricted.search(path.read_text(encoding="utf-8")), (
                f"restricted public term in {relative(path)}"
            )

    contracts = [name for name in names if name.startswith("src/") and name.endswith(".vy")]
    assert len(contracts) == 19
    vyper_lines = sum(
        1
        for name in contracts
        for line in (ROOT / name).read_text(encoding="utf-8").splitlines()
        if line.strip()
    )
    test_functions = 0
    for path in files:
        if relative(path).startswith("tests/") and path.name.startswith("test_") and path.suffix == ".py":
            tree = ast.parse(path.read_text(encoding="utf-8"))
            test_functions += sum(
                isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
                and node.name.startswith("test_")
                for node in tree.body
            )
    assert test_functions >= 16

    for workflow in [".github/workflows/ci.yml", ".github/workflows/release-integrity.yml"]:
        contents = (ROOT / workflow).read_text(encoding="utf-8")
        assert "actions/checkout@v7" in contents
        assert "actions/setup-python@v7" in contents

    print(
        {
            "version": "1.0.0",
            "contracts": len(contracts),
            "vyper_lines": vyper_lines,
            "public_test_functions": test_functions,
            "docs": len(EXPECTED_DOCS),
            "diagrams": 27,
            "banner_sha256": sha256(banner),
        }
    )


if __name__ == "__main__":
    main()
