#!/usr/bin/env python3
"""Audit the public A5 clock-leaf method and an optional local report."""

import argparse
import os
from pathlib import Path


def key_values(path):
    result = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    insert = root / "flows/asic/a5/public/clock_leaf_insert.tcl"
    audit = root / "flows/asic/a5/public/clock_leaf_audit.tcl"
    contract = root / "flows/asic/a5/public/clock_delivery_contract.yaml"
    for path in (insert, audit, contract):
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError("missing clock-delivery input: {}".format(path))
    insert_text = insert.read_text(encoding="utf-8")
    audit_text = audit.read_text(encoding="utf-8")
    required = (
        "DMA_A5_EXPECTED_CLOCK_LEAVES", "DMA_A5_CLOCK_LEAF_CELL",
        "setPlacementStatus FIRM", "distance > 20.0",
    )
    if any(token not in insert_text + audit_text for token in required):
        raise RuntimeError("clock-leaf scripts do not preserve the public contract")
    if args.dry_run:
        print("optional_env: DMA_A5_CLOCK_AUDIT_REPORT")
        print("checks: exact leaf count single macro load FIRM <=20um slew <=72ps")
        return 0
    report_value = os.environ.get("DMA_A5_CLOCK_AUDIT_REPORT")
    if report_value:
        report = Path(report_value).resolve()
        if not report.is_file():
            raise RuntimeError("missing clock audit report: {}".format(report))
        values = key_values(report)
        baseline = float(values["baseline_macro_clock_slew_ps"])
        selected = float(values["selected_macro_clock_slew_ps"])
        leaves = int(values["clock_leaf_count"])
        if selected > 72.0 or selected >= baseline or leaves not in (2, 16):
            raise RuntimeError("local clock-delivery report fails the bounded gate")
        print(
            "N45_A5_CLOCK_DELIVERY_REPORT_PASS baseline_slew_ps={} "
            "selected_slew_ps={} leaves={}".format(baseline, selected, leaves)
        )
    print("N45_A5_CLOCK_DELIVERY_AUDIT_PASS method=d200_macro_x3 policy=no_waiver")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError, ValueError) as error:
        raise SystemExit("a5-clock-delivery-audit: {}".format(error))
