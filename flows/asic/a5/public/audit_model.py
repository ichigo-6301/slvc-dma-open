#!/usr/bin/env python3
"""Audit a user-provided A5 Liberty without distributing the macro view."""

import argparse
import math
import os
import re
from pathlib import Path


NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


def numbers(value):
    return [float(item) for item in re.findall(NUMBER, value)]


def increasing(values):
    return len(values) >= 2 and all(
        math.isfinite(item) for item in values
    ) and all(left < right for left, right in zip(values, values[1:]))


def audit(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    axes = []
    for match in re.finditer(r"index_[12]\s*\(\s*\"([^\"]+)\"\s*\)", text):
        axis = numbers(match.group(1))
        if not increasing(axis):
            raise RuntimeError("Liberty table axis is not finite and strictly increasing")
        axes.append(axis)
    if not axes:
        raise RuntimeError("Liberty contains no tabular axes")
    table_values = []
    for match in re.finditer(r"values\s*\((.*?)\)\s*;", text, re.DOTALL):
        table_values.extend(numbers(match.group(1)))
    if not table_values or not all(math.isfinite(item) for item in table_values):
        raise RuntimeError("Liberty table values are missing or non-finite")
    for token in ("clk0", "clk1", "minimum_period", "min_pulse_width", "max_capacitance"):
        if token not in text:
            raise RuntimeError("Liberty is missing required token: {}".format(token))
    if re.search(r"max_capacitance\s*:\s*0(?:\.0*)?\s*;", text):
        raise RuntimeError("active max_capacitance was removed")
    print(
        "N45_A5_MODEL_AUDIT_PASS file={} axes={} values={} policy=no_waiver".format(
            path, len(axes), len(table_values)
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    path_value = os.environ.get("DMA_A5_512_LIBERTY")
    if args.dry_run:
        print("required_env: DMA_A5_512_LIBERTY")
        print("checks: axes finite monotonic clock pins min-period min-pulse max-cap")
        return 0
    if not path_value:
        raise RuntimeError("DMA_A5_512_LIBERTY is required")
    path = Path(path_value).resolve()
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError("missing A5 Liberty: {}".format(path))
    audit(path)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        raise SystemExit("a5-model-audit: {}".format(error))
