from pathlib import Path

from vyper import compile_code


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    for source in sorted((ROOT / "src").glob("*.vy")):
        compile_code(source.read_text(), output_formats=["abi", "bytecode"])
        print(f"compiled {source.name}")


if __name__ == "__main__":
    main()

