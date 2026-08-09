#!/usr/bin/env python3
"""Validate the sanitized branch-only C2B4 storage clock-gating result."""
from __future__ import print_function

import argparse
import csv
import hashlib
import json
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path


EVIDENCE_REL = Path("evidence/asic_power_clock_gating_storage_positive")
PROVENANCE_REL = Path("provenance/experimental_storage_power_branch.yaml")
README_FILES = ("README.md", "README.en.md")
DOC_FILES = (
    "docs/en/asic_power_storage_clock_gating_experiment.md",
    "docs/zh-CN/asic_power_storage_clock_gating_experiment.md",
)
EXPERIMENT = "c2b4_storage_clock_gating_dc"
WORKLOADS = ("idle", "bursty", "saturated")
VARIANTS = ("S0", "S1")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
SENSITIVE = re.compile(
    r"(?:(?<![A-Za-z0-9])[A-Za-z]:[\\/]|\\\\|/(?:home|mnt|Users|work|tmp)/|"
    r"(?:LM_LICENSE_FILE|SNPSLMD_LICENSE_FILE|MGLS_LICENSE_FILE|HOSTNAME|USER)\s*[:=]|"
    r"(?:licen[sc]e|licserver|private[_-]?(?:remote|repo)|password|token)\s*[:=])",
    re.IGNORECASE,
)

BRANCH = "research/dma-a3-clock-gating-storage-positive-2026-08"
FIXED_REVISIONS = {
    "experiment_baseline": "14538a48b1483a50ba7fceef6f4abde8f6e5ea86",
    "flow_as_run": "0b7b4f489eaf8004b0e578f1333f45c20d6e6591",
    "annotation_launcher_identity": "40de1a2fa016c558e63f715cc27115a6ab26de21",
    "report_quantization_contract": "e33019b2594eb335dbf7dc9a8aebcccd8066c13c",
    "machine_evidence": "899af6d698980b17b71c67c35afa381511dff429",
    "final_documentation": "cb597a290301e284b1c2bca52ba8a2b122aa4f46",
    "rtl_closure": "45cd49764d26861027639cd1e3de638dfdc35454",
    "shared_source_set": "348df4949d4d88954a4402cd47118c6444099a17",
}
FIXED = {
    "top": "dma_rx512_memory_subsystem_top",
    "profile": "dma_rx512_reg_c2_b4_m2_sp64",
    "source_commit": FIXED_REVISIONS["rtl_closure"],
    "shared_source_set_sha256": "2316525a44e38bde84ea4d4cbf5139ff49f26e4abbcc91d1bfc1905919087bbb",
    "s0_source_sha256": "e55b69ddd343b2c20b93e8de674da95c7ea0ea6b7dc2e15ba2157eedb7de097f",
    "s1_source_sha256": "c1533ec05ac2ab5c5159f573ef0ab7919c503b71021fdc27cdf05d8c491d3270",
    "library_sha256": "111c429e7ae9341d51f5f04b0e4c7574e5c1359de32d51b151470463abe187de",
    "constraint_sha256": "0ded9f241bb7a14d13c284b5895fec3c16dfbb35866a78c481a47f97d3bcc6a7",
    "activity_identity_sha256": "3c67a84e0bf9c8f284b14ccd2ccfd25d0c6237905b65b2978be84c1ceb8e480b",
    "floorplan_sha256": "72e362371ca7dae86e06f9d1a5a5ce2228445ce2b526196476421e6de2a094f8",
    "handoff_policy_sha256": "92b643edf57a73935f36d7f3cf0bfe931470a6c87460037746810ea638803aba",
    "tool_version": "O-2018.06-SP1",
}
FIXED_VARIANT_METRICS = {
    "S0": {
        "total_area_um2": "946749.061998",
        "combinational_area_um2": "429844.296002",
        "sequential_area_um2": "516904.766",
        "cell_count": "472128",
        "register_count": "113741",
        "setup_wns_ns": "0.00336182",
        "hold_wns_ns": "0.0441018",
        "icg_cell_count": "0",
        "gated_bit_count": "0",
    },
    "S1": {
        "total_area_um2": "749598.107999",
        "combinational_area_um2": "229293.596",
        "sequential_area_um2": "520304.512",
        "cell_count": "253412",
        "register_count": "113752",
        "setup_wns_ns": "0.00553846",
        "hold_wns_ns": "0.0441018",
        "icg_cell_count": "837",
        "gated_bit_count": "102976",
    },
}
FIXED_TRACES = {
    "idle": "e5739c0c0c4b8d75f7624940f1c6fb25c7c80dcd1d0d794d76c97b847ec670d0",
    "bursty": "385be3b44377d8ba42dff33478781e96561fd3a2573776d2d5544751e76401d6",
    "saturated": "e838dfc4cbeb07f6ed22d42e4103d8b1dac512e63d76c3ac898c18244732a8ac",
}
FIXED_BINDINGS = {
    "pair_pass_sha256": "a970761b1adaf3caa317dc7b0a6dc84da94086d9227c142d1b3421a46da1990d",
    "collection_probe_result_sha256": "956b6dd8128b7fb2b02cfc2c1de64a7556fcaf15d75fc92a234bd242529bdb62",
    "S0_result_sha256": "0183b5971ea889fad805c6757990272ee5d7059e704a2c23903242ba03f7d2cf",
    "S1_result_sha256": "e2edca94e12c4d5dbe6442566daa8929c9b35a214c67c4eef2b8893f6dcdca82",
    "S0_identity_sha256": "d9b9213fa4bad8bfc0597bcd55f681d5b5692b7962dd3ef0effc083629e2c2b2",
    "S1_identity_sha256": "83f5e5d3d9358e22e0f0097176f57844fae174316e3a20383ceaa70b497625e3",
    "S0_annotation_audit_sha256": "eada0562b234cea3a71cf54e607bff4ad98b3e46ba3d1476d0d32eb135960221",
    "S1_annotation_audit_sha256": "907eb9fa5d2b62d739338adac0ce5e3a64c3a77dacb8602cdbba158435ce057f",
}

POINT_FIELDS = (
    "point_id", "experiment", "variant", "workload", "period_ns",
    "frequency_mhz", "compile_mode", "top", "profile", "source_commit",
    "source_sha256", "shared_source_set_sha256", "library_sha256",
    "constraint_sha256", "activity_identity_sha256", "floorplan_sha256",
    "handoff_policy_sha256", "tool_version", "trace_sha256",
    "mapped_trace_sha256", "mapped_summary_sha256", "input_coverage_pct",
    "sequential_coverage_pct", "overall_coverage_pct",
    "clock_activity_coverage_pct", "icg_enable_activity_coverage_pct",
    "total_area_um2",
    "combinational_area_um2", "sequential_area_um2", "cell_count",
    "register_count", "setup_wns_ns", "setup_tns_ns", "hold_wns_ns",
    "hold_tns_ns", "setup_violation_count", "hold_violation_count",
    "electrical_violation_count", "latch_count", "unresolved_count",
    "gtech_count", "unclocked_register_count", "icg_cell_count",
    "gated_bit_count", "gated_state_coverage_pct", "switching_mw",
    "internal_mw", "dynamic_mw", "clock_dynamic_mw",
    "sequential_dynamic_mw", "combinational_dynamic_mw", "leakage_mw",
    "total_mw", "throughput_bytes_per_s", "dynamic_energy_pj_per_byte",
    "incremental_total_energy_pj_per_byte",
)
COMPARISON_FIELDS = (
    "comparison_id", "workload", "metric", "baseline", "candidate",
    "delta", "delta_percent", "unit",
)
CATEGORY_FIELDS = ("category", "eligible_bits", "gated_bits", "coverage_percent")
HIERARCHY_FIELDS = (
    "point_id", "variant", "workload", "group", "internal_mw",
    "switching_mw", "dynamic_mw", "leakage_mw", "total_mw",
)
VERIFICATION_FIELDS = (
    "verification_id", "variant", "workload", "status", "required_marker",
    "trace_sha256", "mapped_trace_sha256", "mapped_summary_sha256",
    "vcd_sha256", "saif_sha256", "marker_sha256", "annotation_audit_sha256",
    "annotation_summary_sha256", "annotation_clock_saif_sha256",
    "annotation_icg_enable_saif_sha256", "annotation_marker_sha256",
)
ARTIFACT_FIELDS = ("artifact_id", "variant", "logical_name", "sha256", "size_bytes")
EXPECTED_CATEGORIES = {
    "fixed_payload": 65536,
    "shared_payload": 32768,
    "shared_keep": 4096,
    "writer": 576,
}
REQUIRED_ARTIFACTS = {
    "mapped_netlist", "mapped_ddc", "mapped_sdc", "dc_summary",
    "activity_coverage_summary", "icg_summary", "mapped_gls_summary",
}
REQUIRED_ARTIFACTS.update(
    "{}_{}_{}".format(prefix, workload, suffix)
    for workload in WORKLOADS
    for prefix, suffix in (
        ("power", "report"), ("power_groups", "report"),
        ("mapped_gls", "trace"), ("mapped_gls", "summary"),
        ("mapped_gls", "marker"),
    )
)
ANNOTATION_ARTIFACTS = {"annotation_audit_json"}
ANNOTATION_ARTIFACTS.update(
    "annotation_{}_{}".format(workload, suffix)
    for workload in WORKLOADS
    for suffix in ("summary", "clock_saif", "icg_enable_saif", "marker")
)
EXPECTED_NONCLAIMS = {
    "not_complete_dma", "not_sram_profile", "not_postroute_power",
    "not_cts_clock_power", "not_signoff", "lec_not_available",
}
EXPECTED_THRESHOLDS = {
    "minimum_gated_state_coverage_pct": "20",
    "maximum_bursty_dynamic_delta_percent": "-10",
    "maximum_saturated_dynamic_delta_percent": "1",
    "maximum_total_area_delta_percent": "2",
}
EXPECTED_REPORT_QUANTIZATION = {
    "top_power_arithmetic_tolerance_mw": "1.1",
    "basis": "bounded independent half-LSB sum for three-significant-digit DC hierarchy fields",
}
COMPARE_METRICS = (
    ("total_area_um2", "um2"),
    ("combinational_area_um2", "um2"),
    ("sequential_area_um2", "um2"),
    ("dynamic_mw", "mW"),
    ("clock_plus_sequential_mw", "mW"),
    ("leakage_mw", "mW"),
    ("total_mw", "mW"),
    ("dynamic_energy_pj_per_byte", "pJ/B"),
    ("incremental_total_energy_pj_per_byte", "pJ/B"),
)

PACKAGE_FILES = frozenset({
    "README.md", "manifest.json", "points.csv", "comparisons.csv",
    "category_census.csv", "hierarchy_power.csv", "verification.csv",
    "artifacts.csv",
})
ALLOWED_BRANCH_FILES = frozenset({
    "README.md",
    "README.en.md",
    "Makefile",
    "docs/en/asic_power_storage_clock_gating_experiment.md",
    "docs/zh-CN/asic_power_storage_clock_gating_experiment.md",
    "evidence/asic_power_clock_gating_storage_positive/README.md",
    "evidence/asic_power_clock_gating_storage_positive/manifest.json",
    "evidence/asic_power_clock_gating_storage_positive/points.csv",
    "evidence/asic_power_clock_gating_storage_positive/comparisons.csv",
    "evidence/asic_power_clock_gating_storage_positive/category_census.csv",
    "evidence/asic_power_clock_gating_storage_positive/hierarchy_power.csv",
    "evidence/asic_power_clock_gating_storage_positive/verification.csv",
    "evidence/asic_power_clock_gating_storage_positive/artifacts.csv",
    "evidence/asic_power_clock_gating_storage_positive/hashes.sha256",
    "flows/scripts/validate_asic_power_storage_clock_gating_experiment.py",
    "flows/scripts/test_validate_asic_power_storage_clock_gating_experiment.py",
    "provenance/experimental_storage_power_branch.yaml",
    "provenance/checksums.sha256",
})
FORBIDDEN_SUFFIXES = frozenset({
    ".log", ".rpt", ".ddc", ".sdc", ".spef", ".odb", ".vcd", ".saif",
    ".db", ".lib", ".liberty", ".lef", ".gds", ".def", ".v",
})
FIXED_CONTENT_SHA256 = {
    "README.md": "756e0ce301237d8b5a74cc2735a74b9f42a18e00d3fa45c7a07dbfde094a10ea",
    "manifest.json": "639296dded5f3e89e38fc4e23760417c5401fd0aff20e057d5f476254b9c12de",
    "points.csv": "f51843313a96382e625a2e88cbaaacf047b3f716352174e8be575144a3c7f9c5",
    "category_census.csv": "c1d2934dec3d3c368dc8cee531eb135a885f1a8c1ea6aba96d79f6fbfc3e931f",
    "hierarchy_power.csv": "5bc4e0c714b30e12465297fa9a1c627c393354ea135c4aa163785c8f7c17a94d",
    "verification.csv": "6089d932b00c510cec70706ceeaaf9d2a9f3ba6138a112940d84313f4bc3c223",
    "artifacts.csv": "8ff3a15d1dfa3c107c3825f4d5ca9d4132f8051d0389e78ffb364a0db76ac435",
    "provenance/experimental_storage_power_branch.yaml":
        "06e3f5a98774d2b244bc1d554ca97596f703520a29244410841589a9f0c38a17",
}


class ValidationError(RuntimeError):
    pass


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def decimal(value, label, nonnegative=False):
    if isinstance(value, bool):
        raise ValidationError("{} is not numeric".format(label))
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise ValidationError("{} is not numeric".format(label))
    if not number.is_finite() or (nonnegative and number < 0):
        raise ValidationError("{} is out of range".format(label))
    return number


def decimal_text(value):
    text = format(Decimal(value), "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text or "0"


def percent_delta(baseline, candidate, label):
    baseline = decimal(baseline, label + " baseline")
    candidate = decimal(candidate, label + " candidate")
    if baseline == 0:
        raise ValidationError("{} baseline is zero".format(label))
    return (candidate - baseline) * Decimal("100") / baseline


def require_close(left, right, label):
    left = decimal(left, label)
    right = decimal(right, label)
    tolerance = max(Decimal("0.000001"), max(abs(left), abs(right)) * Decimal("0.000001"))
    if abs(left - right) > tolerance:
        raise ValidationError("{} is not internally consistent".format(label))


def require_absolute_close(left, right, tolerance, label):
    """Bound coarse report-display quantization with an explicit absolute limit."""
    left = decimal(left, label)
    right = decimal(right, label)
    if abs(left - right) > Decimal(tolerance):
        raise ValidationError("{} exceeds report-quantization tolerance".format(label))


def read_json(path, label):
    def unique_object(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("duplicate key {}".format(key))
            value[key] = item
        return value
    try:
        value = json.loads(
            Path(path).read_text(encoding="ascii"), object_pairs_hook=unique_object)
    except (OSError, UnicodeError, ValueError) as error:
        raise ValidationError("cannot read {}: {}".format(label, error))
    if not isinstance(value, dict):
        raise ValidationError("{} is not an object".format(label))
    return value


def read_csv(path, fields, label):
    try:
        with Path(path).open("r", encoding="ascii", newline="") as stream:
            reader = csv.DictReader(stream)
            if reader.fieldnames != list(fields):
                raise ValidationError("{} header mismatch".format(label))
            rows = list(reader)
    except OSError as error:
        raise ValidationError("cannot read {}: {}".format(label, error))
    if not rows:
        raise ValidationError("{} is empty".format(label))
    return rows


def write_csv(path, fields, rows):
    with Path(path).open("w", encoding="ascii", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(fields), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def require_hash(value, label):
    if not isinstance(value, str) or not SHA256.match(value):
        raise ValidationError("{} is not a SHA-256".format(label))


def require_int(value, label, nonnegative=True):
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        raise ValidationError("{} is not an integer".format(label))
    if str(parsed) != str(value) or (nonnegative and parsed < 0):
        raise ValidationError("{} is out of range".format(label))
    return parsed


def point_metric(row, metric):
    if metric == "clock_plus_sequential_mw":
        return decimal(row["clock_dynamic_mw"], metric) + decimal(
            row["sequential_dynamic_mw"], metric)
    return decimal(row[metric], metric)


def generate_comparisons(points):
    lookup = {(row["variant"], row["workload"]): row for row in points}
    rows = []
    for workload in WORKLOADS:
        baseline = lookup[("S0", workload)]
        candidate = lookup[("S1", workload)]
        for metric, unit in COMPARE_METRICS:
            if workload == "idle" and metric.endswith("energy_pj_per_byte"):
                continue
            base_value = point_metric(baseline, metric)
            candidate_value = point_metric(candidate, metric)
            delta = candidate_value - base_value
            rows.append({
                "comparison_id": "{}_{}".format(workload, metric),
                "workload": workload,
                "metric": metric,
                "baseline": decimal_text(base_value),
                "candidate": decimal_text(candidate_value),
                "delta": decimal_text(delta),
                "delta_percent": decimal_text(percent_delta(
                    base_value, candidate_value, "{} {}".format(workload, metric))),
                "unit": unit,
            })
    return rows


def csv_bytes(fields, rows):
    import io
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=list(fields), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("ascii")


def validate_points(rows, manifest):
    if len(rows) != 6:
        raise ValidationError("points.csv must contain six rows")
    keys = {(row["variant"], row["workload"]) for row in rows}
    if keys != set((variant, workload) for variant in VARIANTS for workload in WORKLOADS):
        raise ValidationError("points.csv matrix is incomplete or duplicated")
    common_fields = (
        "experiment", "period_ns", "frequency_mhz", "top", "profile",
        "source_commit", "shared_source_set_sha256", "library_sha256",
        "constraint_sha256", "activity_identity_sha256", "floorplan_sha256",
        "handoff_policy_sha256", "tool_version",
    )
    first = rows[0]
    for row in rows:
        if any(row[field] != first[field] for field in common_fields):
            raise ValidationError("paired identity differs in points.csv")
        if row["experiment"] != EXPERIMENT or row["variant"] not in VARIANTS:
            raise ValidationError("point experiment/variant mismatch")
        expected_identity = {
            "period_ns": "2.000000",
            "frequency_mhz": "500",
            "top": FIXED["top"],
            "profile": FIXED["profile"],
            "source_commit": FIXED["source_commit"],
            "source_sha256": FIXED[row["variant"].lower() + "_source_sha256"],
            "shared_source_set_sha256": FIXED["shared_source_set_sha256"],
            "library_sha256": FIXED["library_sha256"],
            "constraint_sha256": FIXED["constraint_sha256"],
            "activity_identity_sha256": FIXED["activity_identity_sha256"],
            "floorplan_sha256": FIXED["floorplan_sha256"],
            "handoff_policy_sha256": FIXED["handoff_policy_sha256"],
            "tool_version": FIXED["tool_version"],
        }
        if any(row[field] != value for field, value in expected_identity.items()):
            raise ValidationError("point fixed identity mismatch")
        if not COMMIT.match(row["source_commit"]):
            raise ValidationError("source commit is not full lowercase SHA-1")
        for field in (
                "source_sha256", "shared_source_set_sha256", "library_sha256",
                "constraint_sha256", "activity_identity_sha256", "floorplan_sha256",
                "handoff_policy_sha256", "trace_sha256", "mapped_trace_sha256",
                "mapped_summary_sha256"):
            require_hash(row[field], "point {}".format(field))
        if row["compile_mode"] != ("compile_ultra" if row["variant"] == "S0" else
                                   "compile_ultra_gate_clock"):
            raise ValidationError("point compile mode mismatch")
        if row["trace_sha256"] != FIXED_TRACES[row["workload"]] or \
                row["mapped_trace_sha256"] != FIXED_TRACES[row["workload"]]:
            raise ValidationError("point fixed trace identity mismatch")
        for field in (
                "input_coverage_pct", "sequential_coverage_pct", "overall_coverage_pct",
                "clock_activity_coverage_pct",
                "total_area_um2", "combinational_area_um2", "sequential_area_um2",
                "setup_wns_ns", "setup_tns_ns", "hold_wns_ns", "hold_tns_ns",
                "gated_state_coverage_pct", "switching_mw", "internal_mw",
                "dynamic_mw", "clock_dynamic_mw", "sequential_dynamic_mw",
                "combinational_dynamic_mw", "leakage_mw", "total_mw",
                "throughput_bytes_per_s"):
            decimal(row[field], "point {}".format(field), nonnegative=field not in (
                "setup_wns_ns", "setup_tns_ns", "hold_wns_ns", "hold_tns_ns"))
        if row["workload"] == "idle":
            if row["dynamic_energy_pj_per_byte"] != "NA" or \
                    row["incremental_total_energy_pj_per_byte"] != "NA":
                raise ValidationError("idle energy/byte must be NA")
        else:
            decimal(row["dynamic_energy_pj_per_byte"], "dynamic energy", True)
            decimal(row["incremental_total_energy_pj_per_byte"], "incremental energy")
        if row["variant"] == "S0":
            if row["icg_enable_activity_coverage_pct"] != "NA":
                raise ValidationError("S0 ICG-enable coverage must be NA")
        else:
            decimal(row["icg_enable_activity_coverage_pct"], "ICG-enable coverage", True)
        if decimal(row["clock_activity_coverage_pct"], "clock coverage") != 100 or \
                (row["variant"] == "S1" and decimal(
                    row["icg_enable_activity_coverage_pct"], "ICG-enable coverage") != 100):
            raise ValidationError("annotation audit coverage is not exactly 100%")
        require_close(
            decimal(row["switching_mw"], "switching") +
            decimal(row["internal_mw"], "internal"),
            row["dynamic_mw"], "point dynamic power")
        require_absolute_close(
            decimal(row["dynamic_mw"], "dynamic") +
            decimal(row["leakage_mw"], "leakage"),
            row["total_mw"],
            EXPECTED_REPORT_QUANTIZATION["top_power_arithmetic_tolerance_mw"],
            "point total power")
        for field in (
                "cell_count", "register_count", "setup_violation_count",
                "hold_violation_count", "electrical_violation_count", "latch_count",
                "unresolved_count", "gtech_count", "unclocked_register_count",
                "icg_cell_count", "gated_bit_count"):
            require_int(row[field], "point {}".format(field))
        if any(require_int(row[field], field) != 0 for field in (
                "setup_violation_count", "hold_violation_count",
                "electrical_violation_count", "latch_count", "unresolved_count",
                "gtech_count", "unclocked_register_count")):
            raise ValidationError("point timing/structural/electrical gate is not clean")
        if any(decimal(row[field], field) < 0 for field in (
                "setup_wns_ns", "setup_tns_ns", "hold_wns_ns", "hold_tns_ns")):
            raise ValidationError("point timing is not closed")
        if decimal(row["input_coverage_pct"], "input coverage") < 100 or \
                decimal(row["sequential_coverage_pct"], "sequential coverage") < 95 or \
                decimal(row["overall_coverage_pct"], "overall coverage") < 90:
            raise ValidationError("point activity coverage is below threshold")
        if any(row[field] != value for field, value in
               FIXED_VARIANT_METRICS[row["variant"]].items()):
            raise ValidationError("point fixed mapped result mismatch")
        if any(row[field] != "100" for field in (
                "input_coverage_pct", "sequential_coverage_pct",
                "overall_coverage_pct", "clock_activity_coverage_pct")):
            raise ValidationError("point fixed activity coverage mismatch")
        if row["variant"] == "S1" and row["icg_enable_activity_coverage_pct"] != "100":
            raise ValidationError("S1 fixed ICG-enable coverage mismatch")
    lookup = {(row["variant"], row["workload"]): row for row in rows}
    invariant_fields = (
        "period_ns", "frequency_mhz", "compile_mode", "top", "profile",
        "source_commit", "source_sha256", "shared_source_set_sha256",
        "library_sha256", "constraint_sha256", "activity_identity_sha256",
        "floorplan_sha256", "handoff_policy_sha256", "tool_version", "total_area_um2",
        "combinational_area_um2", "sequential_area_um2", "cell_count",
        "register_count", "setup_wns_ns", "setup_tns_ns", "hold_wns_ns",
        "hold_tns_ns", "setup_violation_count", "hold_violation_count",
        "electrical_violation_count", "latch_count", "unresolved_count",
        "gtech_count", "unclocked_register_count", "icg_cell_count",
        "gated_bit_count", "gated_state_coverage_pct",
    )
    for variant in VARIANTS:
        reference = lookup[(variant, "idle")]
        for workload in WORKLOADS[1:]:
            if any(lookup[(variant, workload)][field] != reference[field]
                   for field in invariant_fields):
                raise ValidationError(
                    "variant identity/structural metrics drift across workloads")
    for workload in WORKLOADS:
        left, right = lookup[("S0", workload)], lookup[("S1", workload)]
        if left["trace_sha256"] != right["trace_sha256"] or \
                left["mapped_trace_sha256"] != right["mapped_trace_sha256"] or \
                left["mapped_summary_sha256"] != right["mapped_summary_sha256"]:
            raise ValidationError("paired trace/summary differs for {}".format(workload))
        for field in ("input_coverage_pct", "sequential_coverage_pct", "overall_coverage_pct"):
            if abs(decimal(left[field], field) - decimal(right[field], field)) > Decimal("0.5"):
                raise ValidationError("paired activity coverage differs by over 0.5 pp")
    s0 = lookup[("S0", "bursty")]
    s1 = lookup[("S1", "bursty")]
    if require_int(s0["icg_cell_count"], "S0 ICG count") != 0 or \
            require_int(s0["gated_bit_count"], "S0 gated bits") != 0:
        raise ValidationError("S0 unexpectedly contains clock gates")
    if require_int(s1["icg_cell_count"], "S1 ICG count") != 837 or \
            require_int(s1["gated_bit_count"], "S1 gated bits") != 102976:
        raise ValidationError("S1 fixed clock-gating identity mismatch")
    expected_coverage = Decimal(s1["gated_bit_count"]) * Decimal("100") / Decimal(
        s0["register_count"])
    for workload in WORKLOADS:
        if abs(decimal(lookup[("S1", workload)]["gated_state_coverage_pct"],
                       "gated coverage") - expected_coverage) > Decimal("0.000001"):
            raise ValidationError("gated-state coverage is not reproducible")
    if manifest.get("experiment") != EXPERIMENT:
        raise ValidationError("manifest experiment mismatch")


def validate_categories(rows, points):
    if len(rows) != 4 or {row["category"] for row in rows} != set(EXPECTED_CATEGORIES):
        raise ValidationError("category census is incomplete or duplicated")
    total = 0
    for row in rows:
        eligible = require_int(row["eligible_bits"], "eligible bits")
        gated = require_int(row["gated_bits"], "gated bits")
        if eligible != EXPECTED_CATEGORIES[row["category"]] or gated > eligible:
            raise ValidationError("category census count mismatch")
        expected = Decimal(gated) * Decimal("100") / Decimal(eligible)
        if abs(decimal(row["coverage_percent"], "category coverage") - expected) > Decimal("0.000001"):
            raise ValidationError("category coverage is not reproducible")
        total += gated
    candidate = next(row for row in points if row["variant"] == "S1")
    if total != int(candidate["gated_bit_count"]):
        raise ValidationError("category census does not sum to gated bits")


def validate_hierarchy(rows, points):
    expected = set((variant, workload, group) for variant in VARIANTS
                   for workload in WORKLOADS
                   for group in ("clock_network", "register", "sequential", "combinational"))
    keys = {(row["variant"], row["workload"], row["group"]) for row in rows}
    if len(rows) != 24 or keys != expected:
        raise ValidationError("hierarchy power matrix is incomplete or duplicated")
    point_ids = {row["point_id"] for row in points}
    for row in rows:
        if row["point_id"] not in point_ids:
            raise ValidationError("hierarchy row references an unknown point")
        for field in HIERARCHY_FIELDS[4:]:
            decimal(row[field], "hierarchy {}".format(field), True)
        require_close(
            decimal(row["internal_mw"], "hierarchy internal") +
            decimal(row["switching_mw"], "hierarchy switching"),
            row["dynamic_mw"], "hierarchy dynamic power")
    hierarchy = {(row["variant"], row["workload"], row["group"]): row for row in rows}
    for point in points:
        key = (point["variant"], point["workload"])
        require_close(point["clock_dynamic_mw"],
                      hierarchy[key + ("clock_network",)]["dynamic_mw"],
                      "point/hierarchy clock power")
        require_close(point["sequential_dynamic_mw"],
                      hierarchy[key + ("register",)]["dynamic_mw"],
                      "point/hierarchy sequential power")
        require_close(point["combinational_dynamic_mw"],
                      hierarchy[key + ("combinational",)]["dynamic_mw"],
                      "point/hierarchy combinational power")


def validate_verification(rows, points):
    if len(rows) != 6 or {(r["variant"], r["workload"]) for r in rows} != \
            set((v, w) for v in VARIANTS for w in WORKLOADS):
        raise ValidationError("verification matrix is incomplete or duplicated")
    point_map = {(r["variant"], r["workload"]): r for r in points}
    for row in rows:
        expected_marker = "POWER_C2B4_WORKLOAD_{}_PASS".format(
            row["workload"].upper())
        if row["status"] != "PASS" or row["required_marker"] != expected_marker:
            raise ValidationError("verification marker is not PASS")
        for field in VERIFICATION_FIELDS[5:]:
            require_hash(row[field], "verification {}".format(field))
        point = point_map[(row["variant"], row["workload"])]
        for field in ("trace_sha256", "mapped_trace_sha256", "mapped_summary_sha256"):
            if row[field] != point[field]:
                raise ValidationError("verification hash differs from point")
        if row["trace_sha256"] != FIXED_TRACES[row["workload"]]:
            raise ValidationError("verification fixed trace identity mismatch")


def promotion(points):
    lookup = {(r["variant"], r["workload"]): r for r in points}
    bursty_dynamic = percent_delta(lookup[("S0", "bursty")]["dynamic_mw"],
                                    lookup[("S1", "bursty")]["dynamic_mw"], "bursty dynamic")
    saturated_dynamic = percent_delta(lookup[("S0", "saturated")]["dynamic_mw"],
                                       lookup[("S1", "saturated")]["dynamic_mw"],
                                       "saturated dynamic")
    area = percent_delta(lookup[("S0", "bursty")]["total_area_um2"],
                         lookup[("S1", "bursty")]["total_area_um2"], "area")
    coverage = decimal(lookup[("S1", "bursty")]["gated_state_coverage_pct"],
                       "gated-state coverage")
    annotation_pass = all(
        decimal(row["clock_activity_coverage_pct"], "clock coverage") == 100 and
        (row["variant"] == "S0" or decimal(
            row["icg_enable_activity_coverage_pct"], "enable coverage") == 100)
        for row in points)
    passed = (annotation_pass and coverage >= Decimal("20") and
              bursty_dynamic <= Decimal("-10") and
              saturated_dynamic <= Decimal("1") and area <= Decimal("2"))
    return {
        "status": "POSITIVE" if passed else "NOT_PROMOTED",
        "eligible": passed,
        "annotation_audit_pass": annotation_pass,
        "gated_state_coverage_pct": decimal_text(coverage),
        "bursty_dynamic_delta_percent": decimal_text(bursty_dynamic),
        "saturated_dynamic_delta_percent": decimal_text(saturated_dynamic),
        "total_area_delta_percent": decimal_text(area),
    }


def validate_manifest(root):
    manifest = read_json(root / EVIDENCE_REL / "manifest.json", "manifest")
    expected_keys = {
        "schema", "experiment", "publication_class", "branch", "classification",
        "branch_only", "promotion_eligible", "main_merge_recommended",
        "production_rtl_changed", "postroute_pair_completed", "lec_status",
        "registered_verified_claim", "release_or_tag_changed", "numeric_authority",
        "generated_derivative", "raw_commercial_artifacts_published",
        "fixed_provenance_revisions", "raw_bindings", "tool_identity", "scope",
        "mapped_dc_identity", "pair_methodology", "activity_contract",
        "clock_gating_policy", "promotion_gate", "report_quantization",
        "physical_boundary", "prior_negative_experiment", "artifact_policy",
        "nonclaims",
    }
    if set(manifest) != expected_keys:
        raise ValidationError("manifest top-level key set mismatch")
    fixed_scalars = {
        "schema": "slvc_dma_asic_power_storage_clock_gating_positive_v1",
        "experiment": EXPERIMENT,
        "publication_class": "sanitized_branch_only_research",
        "branch": BRANCH,
        "classification": "POSITIVE_MAPPED_DC / BRANCH_ONLY",
        "lec_status": "not_available",
        "numeric_authority": "points.csv",
        "generated_derivative": "comparisons.csv",
    }
    for field, expected in fixed_scalars.items():
        if manifest.get(field) != expected:
            raise ValidationError("manifest {} mismatch".format(field))
    expected_bools = {
        "branch_only": True,
        "promotion_eligible": True,
        "main_merge_recommended": False,
        "production_rtl_changed": False,
        "postroute_pair_completed": False,
        "registered_verified_claim": False,
        "release_or_tag_changed": False,
        "raw_commercial_artifacts_published": False,
    }
    for field, expected in expected_bools.items():
        if manifest.get(field) is not expected:
            raise ValidationError("manifest {} must be {}".format(field, expected))
    if manifest.get("fixed_provenance_revisions") != FIXED_REVISIONS:
        raise ValidationError("manifest fixed revisions mismatch")
    if manifest.get("raw_bindings") != FIXED_BINDINGS:
        raise ValidationError("manifest raw bindings mismatch")
    tool = manifest.get("tool_identity")
    expected_tool = {
        "dc_version": "O-2018.06-SP1",
        "vcd2saif_version": "O-2018.06-SP1",
        "questa_version": "Questa Sim-64 10.7c",
        "dc_executable_sha256": "185937f0aef4f430288f5ebbc35e39b6aa6fe038f1ef348522478f3fe0e01edf",
        "vcd2saif_executable_sha256": "100e35e860983342c6590ca894461273fb6b8de8b2efc4865b973bfdac4bb6da",
        "questa_executable_sha256": "45c6fe768922fa291b8209f7c4a1a04f8b5c6fb426db2e495fd6ad161903ac14",
    }
    if tool != expected_tool:
        raise ValidationError("manifest tool identity mismatch")
    scope = manifest.get("scope")
    expected_scope = {
        "top": FIXED["top"],
        "profile": FIXED["profile"],
        "channels": 2,
        "fixed_payload_bytes_per_channel": 4096,
        "shared_block_count": 64,
        "shared_block_width_bits": 512,
        "max_burst_beats": 16,
        "max_outstanding": 4,
        "storage_model": "register_expanded",
        "source_commit": FIXED["source_commit"],
        "shared_source_set_sha256": FIXED["shared_source_set_sha256"],
        "s0_prepared_manifest_sha256": FIXED["s0_source_sha256"],
        "s1_prepared_manifest_sha256": FIXED["s1_source_sha256"],
    }
    if scope != expected_scope:
        raise ValidationError("manifest scope identity mismatch")
    mapped = manifest.get("mapped_dc_identity")
    expected_mapped = {
        "tool": "Design Compiler",
        "tool_version": FIXED["tool_version"],
        "library": "Nangate45",
        "corner": "typical",
        "library_db_sha256": FIXED["library_sha256"],
        "library_power_audit": {
            "internal_power_groups": 2459,
            "leakage_power_groups": 2071,
            "legal_icg_cells": 8,
        },
        "constraint_id": "c2b4_storage_clock_gating_dc_2ns",
        "constraints_sha256": FIXED["constraint_sha256"],
        "clock_period_ns": "2.000000",
        "frequency_mhz": 500,
        "activity_identity_sha256": FIXED["activity_identity_sha256"],
        "floorplan_identity_sha256": FIXED["floorplan_sha256"],
        "handoff_policy_sha256": FIXED["handoff_policy_sha256"],
    }
    if mapped != expected_mapped:
        raise ValidationError("manifest mapped-DC identity mismatch")
    pair = manifest.get("pair_methodology")
    if not isinstance(pair, dict) or set(pair) != {
            "baseline", "candidate", "shared_identity",
            "prepared_manifest_boundary", "per_point_activity"}:
        raise ValidationError("manifest pair methodology mismatch")
    if pair["baseline"] != "S0: compile_ultra" or \
            pair["candidate"] != "S1: compile_ultra -gate_clock" or \
            "production RTL is unchanged" not in pair["prepared_manifest_boundary"]:
        raise ValidationError("manifest paired compile boundary mismatch")
    activity = manifest.get("activity_contract")
    if not isinstance(activity, dict) or activity.get("seed") != 71 or \
            activity.get("warmup_cycles") != 4096 or \
            activity.get("mapped_gls_trace_equivalent") is not True or \
            activity.get("power_test_en_functional_value") != 0 or \
            activity.get("verification_tool") != "Questa Sim-64 10.7c":
        raise ValidationError("manifest activity contract mismatch")
    if set(activity.get("workloads", {})) != set(WORKLOADS) or \
            activity.get("coverage_gate") != {
                "input_percent": 100, "sequential_percent": 100,
                "overall_percent": 100, "clock_annotation_percent": 100,
                "s1_icg_enable_annotation_percent": 100,
            }:
        raise ValidationError("manifest workload or coverage contract mismatch")
    gating = manifest.get("clock_gating_policy")
    if not isinstance(gating, dict) or gating.get("icg_cells") != {
            "CLKGATETST_X1": 837} or gating.get("icg_count") != 837 or \
            gating.get("gated_bits") != 102976 or \
            gating.get("minimum_bit_width") != 32 or \
            gating.get("maximum_gate_fanout") != 128 or \
            gating.get("allowlist_categories") != EXPECTED_CATEGORIES:
        raise ValidationError("manifest clock-gating policy mismatch")
    if Decimal(gating.get("gated_state_coverage_percent", "NaN")) != Decimal(
            "90.53551489788203022656737676"):
        raise ValidationError("manifest gated-state coverage mismatch")
    excluded = " ".join(gating.get("excluded_scope", [])).lower()
    if any(term not in excluded for term in (
            "metadata", "cdc", "reset", "axi", "completion", "irq", "whole-domain")):
        raise ValidationError("manifest excluded clock-gating scope mismatch")
    if manifest.get("report_quantization") != EXPECTED_REPORT_QUANTIZATION:
        raise ValidationError("manifest report quantization mismatch")
    if manifest.get("physical_boundary") != {
            "pnr_started": False, "cts_started": False,
            "openrcx_started": False, "primetime_started": False,
            "paired_postroute_power": "not_completed"}:
        raise ValidationError("manifest physical boundary mismatch")
    prior = manifest.get("prior_negative_experiment")
    if not isinstance(prior, dict) or prior.get("public_commit") != \
            "78d4d3336270d4d01c4731050e9eea7fe8e47497" or \
            prior.get("classification") != \
            "NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED":
        raise ValidationError("manifest prior negative experiment mismatch")
    nonclaims = manifest.get("nonclaims")
    if not isinstance(nonclaims, list) or len(nonclaims) != 7 or \
            not all(isinstance(item, str) and item for item in nonclaims):
        raise ValidationError("manifest nonclaims mismatch")
    return manifest


def validate_artifacts(rows, verification):
    if len(rows) != 146:
        raise ValidationError("artifacts.csv must contain 146 records")
    artifact_ids = set()
    artifact_names = dict((variant, set()) for variant in VARIANTS)
    artifact_hashes = {}
    for row in rows:
        if row["artifact_id"] in artifact_ids or row["variant"] not in VARIANTS:
            raise ValidationError("artifact identity is duplicate or malformed")
        artifact_ids.add(row["artifact_id"])
        if row["logical_name"] in artifact_names[row["variant"]]:
            raise ValidationError("artifact logical name is duplicated")
        artifact_names[row["variant"]].add(row["logical_name"])
        artifact_hashes[(row["variant"], row["logical_name"])] = row["sha256"]
        require_hash(row["sha256"], "artifact SHA-256")
        if require_int(row["size_bytes"], "artifact size") <= 0 or \
                "/" in row["logical_name"] or "\\" in row["logical_name"]:
            raise ValidationError("artifact record is malformed")
    for variant in VARIANTS:
        required = set(REQUIRED_ARTIFACTS) | set(ANNOTATION_ARTIFACTS)
        if variant == "S1":
            required.add("icg_category_summary")
        else:
            required.update(("collection_probe_summary", "collection_probe_marker"))
        if not required.issubset(artifact_names[variant]):
            raise ValidationError("required sanitized artifact binding is missing")
    for row in verification:
        expected = {
            "annotation_audit_sha256": "annotation_audit_json",
            "annotation_summary_sha256": "annotation_{}_summary".format(row["workload"]),
            "annotation_clock_saif_sha256":
                "annotation_{}_clock_saif".format(row["workload"]),
            "annotation_icg_enable_saif_sha256":
                "annotation_{}_icg_enable_saif".format(row["workload"]),
            "annotation_marker_sha256": "annotation_{}_marker".format(row["workload"]),
        }
        for field, logical_name in expected.items():
            if row[field] != artifact_hashes.get((row["variant"], logical_name)):
                raise ValidationError("verification annotation artifact binding differs")


def validate_provenance(root, manifest):
    provenance = read_json(root / PROVENANCE_REL, "experimental provenance")
    expected_keys = {
        "schema", "branch", "evidence_path", "status", "classification",
        "promotion_eligible", "main_merge_recommended", "production_rtl_changed",
        "postroute_pair_completed", "lec_status", "registered_verified_claim",
        "release_or_tag_changed", "fixed_provenance_revisions",
        "prior_negative_public_commit", "publication_boundary", "decision",
    }
    if set(provenance) != expected_keys:
        raise ValidationError("experimental provenance field set mismatch")
    expected = {
        "schema": "slvc_dma_experimental_storage_power_branch_v1",
        "branch": BRANCH,
        "evidence_path": str(EVIDENCE_REL / "manifest.json").replace("\\", "/"),
        "status": "positive_mapped_dc",
        "classification": "POSITIVE_MAPPED_DC / BRANCH_ONLY",
        "promotion_eligible": True,
        "main_merge_recommended": False,
        "production_rtl_changed": False,
        "postroute_pair_completed": False,
        "lec_status": "not_available",
        "registered_verified_claim": False,
        "release_or_tag_changed": False,
        "fixed_provenance_revisions": FIXED_REVISIONS,
        "prior_negative_public_commit": "78d4d3336270d4d01c4731050e9eea7fe8e47497",
    }
    for field, value in expected.items():
        if provenance.get(field) != value:
            raise ValidationError("experimental provenance {} mismatch".format(field))
    if provenance.get("publication_boundary") != {
            "branch_only": True, "main_modified": False,
            "pull_request_created": False, "release_tag_changed": False,
            "raw_commercial_artifacts_published": False}:
        raise ValidationError("experimental provenance publication boundary mismatch")
    decision = provenance.get("decision", "")
    if "mapped-DC promotion gates" not in decision or \
            "no main merge recommendation" not in decision:
        raise ValidationError("experimental provenance decision boundary mismatch")
    if manifest["main_merge_recommended"] or provenance["main_merge_recommended"]:
        raise ValidationError("branch-only result cannot recommend a main merge")


def validate_no_formal_registration(root):
    forbidden_ids = (
        "asic_power_clock_gating_storage_positive",
        "storage_clock_gating_mapped_dc_positive",
    )
    for relative in (
            "provenance/claims.yaml", "provenance/evidence.yaml",
            "provenance/nonclaims.yaml"):
        text = (root / relative).read_text(encoding="utf-8")
        if any(item in text for item in forbidden_ids):
            raise ValidationError(
                "experimental result must not be registered as a formal claim")


def validate_docs(root):
    required = {
        "README.md": (
            "ASIC 存储 Bank Clock Gating 研究分支",
            "POSITIVE_MAPPED_DC / BRANCH_ONLY", "不修改生产 RTL",
            "没有 post-route paired power", "没有 LEC/Formality PASS",
            "不建议合入 `main`",
        ),
        "README.en.md": (
            "ASIC Storage-Bank Clock-Gating Research Branch",
            "POSITIVE_MAPPED_DC / BRANCH_ONLY", "no production RTL change",
            "no post-route paired power", "no LEC/Formality PASS",
            "not recommended for merge into `main`",
        ),
        "docs/en/asic_power_storage_clock_gating_experiment.md": (
            "branch-only", "POSITIVE_MAPPED_DC / BRANCH_ONLY",
            "production RTL remains unchanged", "No P&R, CTS, OpenRCX",
            "LEC/Formality", "not recommended for merge into `main`",
        ),
        "docs/zh-CN/asic_power_storage_clock_gating_experiment.md": (
            "branch-only", "POSITIVE_MAPPED_DC / BRANCH_ONLY",
            "生产 RTL 保持不变", "没有运行 P&R、CTS、OpenRCX",
            "LEC/Formality", "不建议合入 `main`",
        ),
    }
    for relative, needles in required.items():
        text = (root / relative).read_text(encoding="utf-8")
        if any(needle not in text for needle in needles):
            raise ValidationError(
                "{} is missing a branch-only result boundary".format(relative))


def write_package_hashes(root):
    evidence = root / EVIDENCE_REL
    lines = ["{}  {}\n".format(sha256_file(evidence / name), name)
             for name in sorted(PACKAGE_FILES)]
    with (evidence / "hashes.sha256").open(
            "w", encoding="utf-8", newline="\n") as output:
        output.write("".join(lines))


def validate_package_hashes(root, write=False):
    if write:
        write_package_hashes(root)
    path = root / EVIDENCE_REL / "hashes.sha256"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise ValidationError("cannot read hashes.sha256: {}".format(error))
    entries = {}
    for line in lines:
        match = re.match(r"^([0-9a-f]{64})  ([A-Za-z0-9_.-]+)$", line)
        if not match:
            raise ValidationError("hashes.sha256 line is invalid")
        digest, name = match.groups()
        if name in entries:
            raise ValidationError("hashes.sha256 contains a duplicate entry")
        entries[name] = digest
    if set(entries) != PACKAGE_FILES:
        raise ValidationError("hashes.sha256 inventory mismatch")
    for name, digest in entries.items():
        if sha256_file(root / EVIDENCE_REL / name) != digest:
            raise ValidationError("hashes.sha256 digest mismatch")


def validate_fixed_content_hashes(root):
    for relative, expected in FIXED_CONTENT_SHA256.items():
        path = root / relative if relative.startswith("provenance/") else \
            root / EVIDENCE_REL / relative
        if sha256_file(path) != expected:
            raise ValidationError(
                "fixed published content hash mismatch for {}".format(relative))


def validate_sanitization(root):
    evidence = root / EVIDENCE_REL
    actual_files = {path.name for path in evidence.iterdir() if path.is_file()}
    if actual_files != PACKAGE_FILES | {"hashes.sha256"}:
        raise ValidationError("evidence package file inventory mismatch")
    text_paths = [path for path in evidence.iterdir() if path.is_file()]
    text_paths.append(root / PROVENANCE_REL)
    text_paths.extend(root / relative for relative in DOC_FILES)
    text_paths.extend(root / relative for relative in README_FILES)
    private_branch = re.compile(r"(?i)\b(?:perf|eval|fix|archive)/[A-Za-z0-9_.\-/]+")
    private_remote = re.compile(r"(?i)(?:git@|ssh://|file://)")
    account_field = re.compile(
        r"(?i)\b(?:host_?name|user_?name|account_?name|license_server)\b\s*[:=]")
    for path in text_paths:
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            raise ValidationError("raw EDA payload is forbidden")
        text = path.read_text(encoding="utf-8", errors="replace")
        if SENSITIVE.search(text) or private_branch.search(text) or \
                private_remote.search(text) or account_field.search(text):
            raise ValidationError(
                "sensitive or private text detected in {}".format(
                    path.relative_to(root)))


def git_paths(root, arguments):
    try:
        output = subprocess.check_output(
            ["git"] + list(arguments), cwd=str(root), stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError) as error:
        raise ValidationError("git scope query failed: {}".format(error))
    return {item.decode("utf-8").replace("\\", "/")
            for item in output.split(b"\0") if item}


def validate_branch_scope(root, base_ref):
    changed = set()
    changed.update(git_paths(root, ("diff", "--name-only", "-z", base_ref + "...HEAD")))
    changed.update(git_paths(root, ("diff", "--name-only", "-z")))
    changed.update(git_paths(root, ("diff", "--cached", "--name-only", "-z")))
    changed.update(git_paths(root, ("ls-files", "--others", "--exclude-standard", "-z")))
    forbidden = sorted(changed - ALLOWED_BRANCH_FILES)
    if forbidden:
        raise ValidationError(
            "branch-only scope forbids change to {}".format(forbidden[0]))


def validate(root, write_generated=False, base_ref=None):
    root = Path(root).resolve()
    manifest = validate_manifest(root)
    evidence = root / EVIDENCE_REL
    points = read_csv(evidence / "points.csv", POINT_FIELDS, "points.csv")
    categories = read_csv(
        evidence / "category_census.csv", CATEGORY_FIELDS, "category_census.csv")
    hierarchy = read_csv(
        evidence / "hierarchy_power.csv", HIERARCHY_FIELDS, "hierarchy_power.csv")
    verification = read_csv(
        evidence / "verification.csv", VERIFICATION_FIELDS, "verification.csv")
    artifacts = read_csv(evidence / "artifacts.csv", ARTIFACT_FIELDS, "artifacts.csv")
    validate_points(points, manifest)
    validate_categories(categories, points)
    validate_hierarchy(hierarchy, points)
    validate_verification(verification, points)
    validate_artifacts(artifacts, verification)
    generated = generate_comparisons(points)
    comparisons_path = evidence / "comparisons.csv"
    if write_generated:
        write_csv(comparisons_path, COMPARISON_FIELDS, generated)
    elif not comparisons_path.is_file() or comparisons_path.read_bytes() != \
            csv_bytes(COMPARISON_FIELDS, generated):
        raise ValidationError("comparisons.csv is not Decimal-generated from points.csv")
    decision = promotion(points)
    gate = manifest["promotion_gate"]
    expected_gate = {
        "primary_workload": "bursty",
        "minimum_gated_state_coverage_percent": 20,
        "maximum_bursty_dynamic_delta_percent": -10,
        "maximum_saturated_dynamic_delta_percent": 1,
        "maximum_total_area_delta_percent": 2,
        "observed_bursty_dynamic_delta_percent":
            decision["bursty_dynamic_delta_percent"],
        "observed_saturated_dynamic_delta_percent":
            decision["saturated_dynamic_delta_percent"],
        "observed_total_area_delta_percent": decision["total_area_delta_percent"],
        "decision": "POSITIVE_MAPPED_DC",
    }
    if decision["status"] != "POSITIVE" or not decision["eligible"] or \
            gate != expected_gate:
        raise ValidationError("manifest promotion decision is not reproducible")
    validate_provenance(root, manifest)
    validate_no_formal_registration(root)
    validate_docs(root)
    validate_package_hashes(root, write=write_generated)
    validate_sanitization(root)
    validate_fixed_content_hashes(root)
    if base_ref:
        validate_branch_scope(root, base_ref)
    return {
        "status": "PASS", "points": len(points), "comparisons": len(generated),
        "categories": len(categories), "hierarchy": len(hierarchy),
        "verification": len(verification), "artifacts": len(artifacts),
        "promotion": "POSITIVE_MAPPED_DC",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("--write-generated", action="store_true")
    parser.add_argument("--base-ref")
    args = parser.parse_args(argv)
    try:
        result = validate(args.root, args.write_generated, args.base_ref)
    except ValidationError as error:
        print("power-research: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "power-research: {points} points, {comparisons} comparisons, "
        "{categories} categories, {hierarchy} hierarchy rows, "
        "{verification} verification records, and {artifacts} artifact hashes "
        "verified; promotion={promotion}".format(**result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
