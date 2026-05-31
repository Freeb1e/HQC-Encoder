#!/usr/bin/env python3
import argparse
from pathlib import Path
from typing import List


NUM_TESTS = 100
RS_WORDS = 46
OFFICIAL_WORD_HEX = 96
OUT_WORD_HEX = 32


def split_encoder_c(input_path: Path, output_path: Path) -> None:
    lines = [line.strip() for line in input_path.read_text().splitlines() if line.strip()]
    if len(lines) != NUM_TESTS:
        raise ValueError(f"{input_path} has {len(lines)} vectors, expected {NUM_TESTS}")

    output_lines: List[str] = []
    expected_width = RS_WORDS * OFFICIAL_WORD_HEX

    for test_idx, line in enumerate(lines):
        if len(line) != expected_width:
            raise ValueError(
                f"{input_path}:{test_idx + 1} has {len(line)} hex chars, "
                f"expected {expected_width}"
            )

        words: List[str] = []
        for word_idx in range(RS_WORDS):
            start = word_idx * OFFICIAL_WORD_HEX
            official_word = line[start : start + OFFICIAL_WORD_HEX]
            chunks = [
                official_word[i : i + OUT_WORD_HEX]
                for i in range(0, OFFICIAL_WORD_HEX, OUT_WORD_HEX)
            ]

            if chunks[1:] and any(chunk != chunks[0] for chunk in chunks[1:]):
                raise ValueError(
                    f"{input_path}:{test_idx + 1} word {word_idx} has non-identical "
                    "128-bit chunks; choose the needed chunk explicitly"
                )

            words.append(chunks[0].lower())

        output_lines.extend(words)

    output_path.write_text("\n".join(output_lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Split official HQC encoder output into one 128-bit word per line."
    )
    parser.add_argument("input", nargs="?", default="encoder_c.memh", type=Path)
    parser.add_argument("output", nargs="?", default="encoder_c_128.memh", type=Path)
    args = parser.parse_args()

    split_encoder_c(args.input, args.output)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
