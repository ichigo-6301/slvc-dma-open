#!/usr/bin/env python3
"""Validate the sanitized branch-only ASIC clock-gating negative result."""

from __future__ import print_function

import argparse
import csv
import hashlib
import io
import json
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path


EVIDENCE_REL = Path("evidence/asic_power_clock_gating_negative")
PROVENANCE_REL = Path("provenance/experimental_power_branch.yaml")
README_FILES = ("README.md", "README.en.md")
DOC_FILES = (
    "docs/en/asic_power_clock_gating_experiment.md",
    "docs/zh-CN/asic_power_clock_gating_experiment.md",
)
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")

POINT_HEADER = (
    "point_id", "comparison_group", "variant", "scope", "workload_id",
    "seed", "warmup_cycles", "window_start_cycle", "window_cycles",
    "window_bytes", "functional_cycles", "functional_bytes",
    "throughput_denominator_cycles", "throughput_denominator_bytes",
    "trace_sha256", "top", "profile", "parameters_id", "parameters_sha256",
    "constraints_id", "constraints_sha256", "frequency_mhz", "tool",
    "tool_version", "library_id", "library_db_sha256", "compile_mode",
    "compile_script_sha256", "source_commit", "source_sha256",
    "shared_source_set_sha256", "variant_source_set_sha256", "activity_sha256",
    "handoff_id", "handoff_sha256", "input_coverage_pct",
    "sequential_coverage_pct", "overall_activity_pct", "icg_cell", "icg_count",
    "gated_bits", "gated_scope", "status", "area_total_um2",
    "area_combinational_um2", "area_sequential_um2", "cell_count",
    "register_count", "buffer_count", "wns_ns", "tns_ns", "dynamic_mw",
    "clock_mw", "sequential_mw", "combinational_mw", "net_switching_mw",
    "leakage_mw", "total_mw", "throughput_bytes_per_s", "aw_count",
    "w_count", "b_count", "completion_count", "latency_cycles", "w_bubbles",
    "peak_outstanding",
)
VERIFICATION_HEADER = (
    "verification_id", "point_id", "comparison_group", "variant", "scope",
    "workload_id", "platform", "simulator", "suite", "required_marker",
    "marker_status", "trace_sha256", "log_sha256", "status",
)
PHYSICAL_HEADER = (
    "attempt_id", "comparison_group", "variant", "stage", "scope",
    "frequency_mhz", "period_ns", "top", "profile", "source_commit",
    "source_sha256", "parent_dc_pair_sha256", "mapped_netlist_sha256",
    "mapped_sdc_sha256", "constraints_sha256", "floorplan_sha256",
    "pin_footprint_sha256", "library_sha256", "tool_version",
    "flow_matrix_sha256", "driver_sha256", "status", "stop_reason",
    "setup_wns_ns", "setup_tns_ns", "setup_violation_count", "hold_wns_ns",
    "hold_tns_ns", "hold_violation_count", "max_cap_violation_count",
    "max_fanout_violation_count", "max_slew_violation_count", "drc_count",
    "antenna_net_count", "antenna_pin_count", "route_flow_error_count",
    "final_flow_error_count", "standard_cell_area_um2", "standard_cell_count",
    "sequential_cell_count", "clock_buffer_count", "clock_inverter_count",
    "timing_repair_buffer_count",
)
ARTIFACT_HEADER = (
    "artifact_id", "attempt_id", "logical_name", "sha256", "size_bytes",
    "distribution",
)
COMPARISON_HEADER = (
    "comparison_id", "comparison_group", "scope", "workload_id",
    "baseline_point", "candidate_point", "metric", "baseline", "candidate",
    "delta", "delta_percent", "formula",
)

WORKLOADS = ("idle", "bursty", "saturated")
VARIANTS = ("G0", "G1")
POINT_METRICS = (
    "area_total_um2", "area_combinational_um2", "area_sequential_um2",
    "cell_count", "register_count", "buffer_count", "wns_ns", "tns_ns",
    "dynamic_mw", "clock_mw", "sequential_mw", "combinational_mw",
    "net_switching_mw", "leakage_mw", "total_mw",
    "throughput_bytes_per_s",
)
DERIVED_METRICS = (
    "clock_plus_sequential_mw", "incremental_energy_per_byte_nj",
    "dynamic_energy_per_byte_nj",
)
ALL_METRICS = POINT_METRICS + DERIVED_METRICS
NUMERIC_POINT_FIELDS = (
    "seed", "warmup_cycles", "window_start_cycle", "window_cycles",
    "window_bytes", "functional_cycles", "functional_bytes",
    "throughput_denominator_cycles", "throughput_denominator_bytes",
    "frequency_mhz", "input_coverage_pct", "sequential_coverage_pct",
    "overall_activity_pct", "icg_count", "gated_bits", "area_total_um2",
    "area_combinational_um2", "area_sequential_um2", "cell_count",
    "register_count", "wns_ns", "tns_ns", "dynamic_mw", "clock_mw",
    "sequential_mw", "combinational_mw", "net_switching_mw", "leakage_mw",
    "total_mw", "throughput_bytes_per_s", "aw_count", "w_count", "b_count",
    "completion_count", "latency_cycles", "w_bubbles", "peak_outstanding",
)

FIXED = {
    "branch": "research/dma-a3-clock-gating-power-negative-2026-08",
    "top": "dma_rx512_memory_subsystem_top",
    "profile": "dma_rx512_reg_c2_b4_m2_sp64",
    "comparison_group": "c2b4_clock_gating_dc",
    "scope": "c2b4_rx512_mapped_dc",
    "source_commit": "45cd49764d26861027639cd1e3de638dfdc35454",
    "source_sha256": "d6585993fdab2446049d0f7efcf90412755106587d59c5441228b789c7f500b2",
    "parameters_sha256": "4d0e48084982ba4451888b63c3f09016e05f09f186c4a100940979fccb89145f",
    "constraints_sha256": "0ded9f241bb7a14d13c284b5895fec3c16dfbb35866a78c481a47f97d3bcc6a7",
    "library_sha256": "111c429e7ae9341d51f5f04b0e4c7574e5c1359de32d51b151470463abe187de",
    "physical_library_sha256": "8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1",
    "compile_script_sha256": "18a4b0467082067e037a70d99119851655e9f707343a7a766047e60c383e9a79",
    "shared_source_set_sha256": "2316525a44e38bde84ea4d4cbf5139ff49f26e4abbcc91d1bfc1905919087bbb",
    "variant_source_set_sha256": "bf332ec11aab8327ccf91a47cce39b9b24abd857c44bd25e7916e2af2fa95282",
}
FIXED_REVISIONS = {
    "finalization": "14538a48b1483a50ba7fceef6f4abde8f6e5ea86",
    "machine_evidence": "6cb023413cdd814d35faf582a44ec96b51768515",
    "compatibility_validation": "1aaaae7902707a30f9375453b5f3136369e7fe58",
    "rtl_closure": "45cd49764d26861027639cd1e3de638dfdc35454",
    "shared_source_set": "348df4949d4d88954a4402cd47118c6444099a17",
}
WORKLOAD_CONTRACTS = {
    "idle": {
        "window_start_cycle": "4101", "window_bytes": "0",
        "functional_cycles": "8197", "functional_bytes": "0",
        "throughput_denominator_cycles": "4096",
        "throughput_denominator_bytes": "0",
    },
    "bursty": {
        "window_start_cycle": "4352", "window_bytes": "45056",
        "functional_cycles": "8448", "functional_bytes": "65536",
        "throughput_denominator_cycles": "4096",
        "throughput_denominator_bytes": "45056",
    },
    "saturated": {
        "window_start_cycle": "8197", "window_bytes": "55680",
        "functional_cycles": "12293", "functional_bytes": "1048576",
        "throughput_denominator_cycles": "4096",
        "throughput_denominator_bytes": "55680",
    },
}
EXPECTED_VARIANT_METRICS = {
    "G0": {
        "area_total_um2": "946749.061998",
        "area_combinational_um2": "429844.296002",
        "area_sequential_um2": "516904.766",
        "cell_count": "472128", "register_count": "113741",
        "wns_ns": "0.00336182", "tns_ns": "0",
    },
    "G1": {
        "area_total_um2": "946078.741998",
        "area_combinational_um2": "429072.630002",
        "area_sequential_um2": "517006.112",
        "cell_count": "470913", "register_count": "113753",
        "wns_ns": "0.00580668", "tns_ns": "0",
    },
}
EXPECTED_COMPARISON_PERCENT = {
    ("bursty", "area_total_um2"): "-0.070802",
    ("bursty", "area_combinational_um2"): "-0.179522",
    ("bursty", "area_sequential_um2"): "0.019606",
    ("bursty", "dynamic_mw"): "-0.759288",
    ("bursty", "clock_plus_sequential_mw"): "-0.737455",
    ("bursty", "incremental_energy_per_byte_nj"): "-25.000000",
    ("saturated", "dynamic_mw"): "0.490785",
}
FIXED_CONTENT_SHA256 = {
    "README.md": "40014575c2c99c374734ca8be67ee02b6c991d948e6c87002aee52d3dbf86c63",
    "manifest.json": "fce659711b9edb6944fc103042224dde49168e517a717409d87967ccad8448a3",
    "points.csv": "f4e0c3292fe567a01a1312377c460164e86e0f89df53b37223ff5a82510be9a2",
    "verification.csv": "5d672a1dc57cb2654daf7a620aed616da908ae6115fc2e3b520552f97afa429b",
    "physical_attempts.csv": "fe155893ea1e22e6ac8f5e1333799096654040e6c699d769d1d7478195150166",
    "physical_artifacts.csv": "22b72cd977e73c037278dbd0332ecafd83db46d8506543466e3d6b340e2cec03",
    "provenance/experimental_power_branch.yaml": "ad4fc6a5d31980cd2cf42440c7dad48d32b9afed039d407d711c98ed8074b1f4",
}

ALLOWED_BRANCH_FILES = frozenset({
    "README.md",
    "README.en.md",
    "Makefile",
    "docs/en/asic_power_clock_gating_experiment.md",
    "docs/zh-CN/asic_power_clock_gating_experiment.md",
    "evidence/asic_power_clock_gating_negative/README.md",
    "evidence/asic_power_clock_gating_negative/manifest.json",
    "evidence/asic_power_clock_gating_negative/points.csv",
    "evidence/asic_power_clock_gating_negative/comparisons.csv",
    "evidence/asic_power_clock_gating_negative/verification.csv",
    "evidence/asic_power_clock_gating_negative/physical_attempts.csv",
    "evidence/asic_power_clock_gating_negative/physical_artifacts.csv",
    "evidence/asic_power_clock_gating_negative/hashes.sha256",
    "flows/scripts/validate_asic_power_clock_gating_experiment.py",
    "flows/scripts/test_validate_asic_power_clock_gating_experiment.py",
    "provenance/experimental_power_branch.yaml",
    "provenance/checksums.sha256",
})
PACKAGE_FILES = frozenset({
    "README.md", "manifest.json", "points.csv", "comparisons.csv",
    "verification.csv", "physical_attempts.csv", "physical_artifacts.csv",
})
FORBIDDEN_SUFFIXES = frozenset({
    ".log", ".rpt", ".ddc", ".sdc", ".spef", ".odb", ".vcd", ".saif",
    ".db", ".lib", ".liberty", ".lef", ".gds", ".def",
})
SENSITIVE_PATTERNS = (
    ("Windows absolute path", re.compile(r"(?i)(?<![A-Za-z0-9])[A-Z]:[\\/]")),
    ("UNC path", re.compile(r"(?m)(?<!\\)\\{2,4}[^\\\s]+\\{1,2}[^\\\s]+")),
    ("POSIX absolute path", re.compile(r"(?m)(?<![A-Za-z0-9./])/(?![/\s])[^\s\"'<>]*")),
    ("private Git remote", re.compile(r"(?i)(?:git@|ssh://|file://)")),
    ("private branch", re.compile(r"(?i)\b(?:perf|eval|archive|fix)/[A-Za-z0-9_.\-/]+")),
    ("host or account field", re.compile(r"(?i)\b(?:host_?name|user_?name|account_?name)\b\s*[:=]")),
    ("license endpoint", re.compile(r"(?i)\b(?:lm_license_file|snpslmd_license_file|license_server)\b")),
)


class EvidenceError(RuntimeError):
    pass


def _fail(message):
    raise EvidenceError(message)


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key {}".format(key))
        result[key] = value
    return result


def _read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_json_pairs)
    except (OSError, TypeError, ValueError) as error:
        _fail("invalid JSON {}: {}".format(path, error))


def _expect_keys(value, expected, context):
    if not isinstance(value, dict) or set(value) != set(expected):
        _fail("{} field set mismatch".format(context))


def _read_csv(path, header):
    try:
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            if tuple(reader.fieldnames or ()) != tuple(header):
                _fail("{} header mismatch".format(path.name))
            rows = list(reader)
    except (OSError, csv.Error) as error:
        _fail("cannot read {}: {}".format(path.name, error))
    for row in rows:
        if tuple(row) != tuple(header) or any(value is None for value in row.values()):
            _fail("{} has malformed row".format(path.name))
    return rows


def _decimal(value, context, allow_na=False):
    if value == "NA" and allow_na:
        return None
    try:
        return Decimal(value)
    except (InvalidOperation, TypeError):
        _fail("{} is not a decimal".format(context))


def _decimal_equal(actual, expected, context):
    if _decimal(actual, context) != Decimal(expected):
        _fail("{} fixed value mismatch".format(context))


def _format_decimal(value):
    return format(value.quantize(Decimal("0.000000000001"), rounding=ROUND_HALF_EVEN), ".12f")


def _format_percent(value):
    return _format_decimal(value)


def _percent(value, baseline):
    if baseline == 0:
        return None
    return Decimal("100") * value / baseline


def _point_id(workload, variant):
    role = "baseline" if variant == "G0" else "candidate"
    return "c2b4_clock_gating_{}_{}".format(workload, role)


def _index_unique(rows, fields, context):
    index = {}
    for row in rows:
        values = tuple(row[field] for field in fields)
        key = values[0] if len(values) == 1 else values
        if key in index:
            _fail("{} duplicate key {}".format(context, key))
        index[key] = row
    return index


def _validate_manifest(root):
    manifest = _read_json(root / EVIDENCE_REL / "manifest.json")
    _expect_keys(manifest, (
        "schema", "publication_class", "branch", "classification", "branch_only",
        "promotion_eligible", "merge_recommended", "production_rtl_changed",
        "postroute_pair_completed", "lec_status", "release_or_tag_changed",
        "registered_verified_claim", "numeric_authority", "generated_derivative",
        "raw_commercial_artifacts_published", "fixed_provenance_revisions", "scope",
        "mapped_dc_identity", "pair_methodology", "activity_contract",
        "clock_gating_policy", "promotion_gate", "physical_boundary",
        "artifact_policy", "nonclaims",
    ), "manifest")
    fixed_scalars = {
        "schema": "slvc_dma_asic_power_clock_gating_negative_v1",
        "publication_class": "sanitized_branch_only_research",
        "branch": FIXED["branch"],
        "classification": "NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED",
        "lec_status": "not_available",
        "numeric_authority": "points.csv",
        "generated_derivative": "comparisons.csv",
    }
    for field, expected in fixed_scalars.items():
        if manifest[field] != expected:
            _fail("manifest {} mismatch".format(field))
    for field in (
        "branch_only", "promotion_eligible", "merge_recommended",
        "production_rtl_changed", "postroute_pair_completed",
        "release_or_tag_changed", "registered_verified_claim",
        "raw_commercial_artifacts_published",
    ):
        expected = field == "branch_only"
        if manifest[field] is not expected:
            _fail("manifest {} must be {}".format(field, expected))
    if manifest["promotion_eligible"] or manifest["merge_recommended"]:
        _fail("negative result must not be promotion or merge eligible")

    _expect_keys(manifest["fixed_provenance_revisions"], FIXED_REVISIONS, "manifest revisions")
    for key, expected in FIXED_REVISIONS.items():
        if manifest["fixed_provenance_revisions"][key] != expected:
            _fail("manifest fixed revision mismatch")

    scope = manifest["scope"]
    _expect_keys(scope, (
        "top", "profile", "channels", "fixed_payload_bytes_per_channel",
        "shared_block_count", "shared_block_width_bits", "max_burst_beats",
        "max_outstanding", "storage_model", "parameters_sha256",
        "writer_source_sha256", "shared_source_set_sha256",
        "variant_source_set_sha256",
    ), "manifest scope")
    expected_scope = {
        "top": FIXED["top"], "profile": FIXED["profile"], "channels": 2,
        "fixed_payload_bytes_per_channel": 4096, "shared_block_count": 64,
        "shared_block_width_bits": 512, "max_burst_beats": 16,
        "max_outstanding": 4, "storage_model": "register_expanded",
        "parameters_sha256": FIXED["parameters_sha256"],
        "writer_source_sha256": FIXED["source_sha256"],
        "shared_source_set_sha256": FIXED["shared_source_set_sha256"],
        "variant_source_set_sha256": FIXED["variant_source_set_sha256"],
    }
    if scope != expected_scope:
        _fail("manifest scope identity mismatch")

    identity = manifest["mapped_dc_identity"]
    _expect_keys(identity, (
        "tool", "tool_version", "library", "corner", "library_db_sha256",
        "library_power_audit", "constraint_id", "constraints_sha256",
        "clock_period_ns", "frequency_mhz", "compile_script_sha256",
    ), "manifest mapped-DC identity")
    expected_identity = {
        "tool": "Design Compiler", "tool_version": "O-2018.06-SP1",
        "library": "Nangate45", "corner": "typical",
        "library_db_sha256": FIXED["library_sha256"],
        "constraint_id": "c2b4_clock_gating_dc_2ns",
        "constraints_sha256": FIXED["constraints_sha256"],
        "clock_period_ns": "2.000000", "frequency_mhz": 500,
        "compile_script_sha256": FIXED["compile_script_sha256"],
    }
    for key, expected in expected_identity.items():
        if identity[key] != expected:
            _fail("manifest mapped-DC {} mismatch".format(key))
    if identity["library_power_audit"] != {
        "internal_power_groups": 2459, "leakage_power_groups": 2071,
        "legal_icg_cells": 8,
    }:
        _fail("manifest library power audit mismatch")

    policy = manifest["clock_gating_policy"]
    if not isinstance(policy, dict) or policy.get("icg_cell") != "CLKGATETST_X1":
        _fail("manifest ICG cell mismatch")
    if policy.get("icg_count") != 9 or policy.get("gated_bits") != 576:
        _fail("manifest clock-gating count mismatch")
    excluded = policy.get("excluded_scope")
    if not isinstance(excluded, list) or len(excluded) != 6:
        _fail("manifest clock-gating exclusions mismatch")
    blocked_words = ("cdc", "reset", "axi", "completion", "irq", "whole-domain")
    if not all(any(word in item.lower() for item in excluded) for word in blocked_words):
        _fail("manifest clock-gating exclusions are incomplete")

    promotion = manifest["promotion_gate"]
    if not isinstance(promotion, dict) or promotion.get("decision") != "NOT_PROMOTED":
        _fail("manifest promotion decision mismatch")
    if promotion.get("total_dynamic_percent") != -3 or promotion.get("clock_plus_sequential_percent") != -8:
        _fail("manifest promotion thresholds mismatch")
    physical = manifest["physical_boundary"]
    if not isinstance(physical, dict) or physical.get("G0_500MHz") != "BLOCKED_SETUP":
        _fail("manifest 500 MHz physical boundary mismatch")
    if physical.get("G0_475MHz") != "BLOCKED_ELECTRICAL" or physical.get("G1") != "NOT_STARTED_GATE_BLOCKED":
        _fail("manifest physical G1 boundary mismatch")
    if physical.get("common_postroute_frequency") != "none" or physical.get("primetime_postroute_paired_power") != "not_completed":
        _fail("manifest post-route boundary mismatch")
    if not isinstance(manifest["nonclaims"], list) or len(manifest["nonclaims"]) != 7:
        _fail("manifest nonclaims mismatch")
    return manifest


def _validate_points(root):
    rows = _read_csv(root / EVIDENCE_REL / "points.csv", POINT_HEADER)
    if len(rows) != 6:
        _fail("points.csv must contain six points")
    index = _index_unique(rows, ("point_id",), "points")
    expected_ids = {_point_id(workload, variant) for workload in WORKLOADS for variant in VARIANTS}
    if set(index) != expected_ids:
        _fail("points.csv point matrix mismatch")
    by_pair = {}
    for point_id, row in index.items():
        workload = row["workload_id"]
        variant = row["variant"]
        if workload not in WORKLOADS or variant not in VARIANTS:
            _fail("points.csv variant/workload mismatch")
        if point_id != _point_id(workload, variant):
            _fail("points.csv point ID mismatch")
        key = (workload, variant)
        if key in by_pair:
            _fail("points.csv duplicate workload/variant")
        by_pair[key] = row
        for field in NUMERIC_POINT_FIELDS:
            _decimal(row[field], "points.csv {} {}".format(point_id, field))
        if row["buffer_count"] != "NA":
            _fail("points.csv buffer_count must remain NA")
        scalar_identity = {
            "comparison_group": FIXED["comparison_group"], "scope": FIXED["scope"],
            "seed": "71", "warmup_cycles": "4096", "window_cycles": "4096",
            "top": FIXED["top"], "profile": FIXED["profile"],
            "parameters_id": "c2b4_parameters",
            "parameters_sha256": FIXED["parameters_sha256"],
            "constraints_id": "c2b4_clock_gating_dc_2ns",
            "constraints_sha256": FIXED["constraints_sha256"],
            "frequency_mhz": "500", "tool": "Design Compiler",
            "tool_version": "O-2018.06-SP1", "library_id": "nangate45_typical_db",
            "library_db_sha256": FIXED["library_sha256"],
            "compile_script_sha256": FIXED["compile_script_sha256"],
            "source_commit": FIXED["source_commit"], "source_sha256": FIXED["source_sha256"],
            "shared_source_set_sha256": FIXED["shared_source_set_sha256"],
            "variant_source_set_sha256": FIXED["variant_source_set_sha256"],
            "status": "NEGATIVE",
        }
        for field, expected in scalar_identity.items():
            if row[field] != expected:
                _fail("points.csv {} identity mismatch".format(field))
        for field, expected in WORKLOAD_CONTRACTS[workload].items():
            if row[field] != expected:
                _fail("points.csv {} workload contract mismatch".format(field))
        expected_mode = "compile_ultra" if variant == "G0" else "compile_ultra_gate_clock"
        if row["compile_mode"] != expected_mode:
            _fail("points.csv compile mode mismatch")
        if variant == "G0":
            expected_gate = ("NA", "0", "0", "none", "c2b4_g0_mapped_netlist")
        else:
            expected_gate = ("CLKGATETST_X1", "9", "576", "writer_data_register_banks", "c2b4_g1_mapped_netlist")
        if (row["icg_cell"], row["icg_count"], row["gated_bits"], row["gated_scope"], row["handoff_id"]) != expected_gate:
            _fail("points.csv clock-gating identity mismatch")
        for field, expected in EXPECTED_VARIANT_METRICS[variant].items():
            _decimal_equal(row[field], expected, "points.csv {}".format(field))
        if row["input_coverage_pct"] != "100" or row["sequential_coverage_pct"] != "100":
            _fail("points.csv activity coverage mismatch")
        expected_overall = "97.14" if variant == "G0" else "97.11999999999999"
        if row["overall_activity_pct"] != expected_overall:
            _fail("points.csv overall activity coverage mismatch")
        for field in ("trace_sha256", "activity_sha256", "handoff_sha256"):
            if not HEX64.match(row[field]):
                _fail("points.csv {} SHA-256 mismatch".format(field))
    return by_pair


def _point_metric(row, metric, idle_row):
    if metric in POINT_METRICS:
        return _decimal(row[metric], "points.csv {}".format(metric), allow_na=True)
    if metric == "clock_plus_sequential_mw":
        return _decimal(row["clock_mw"], metric) + _decimal(row["sequential_mw"], metric)
    throughput = _decimal(row["throughput_bytes_per_s"], metric)
    if throughput == 0:
        return None
    if metric == "incremental_energy_per_byte_nj":
        total = _decimal(row["total_mw"], metric)
        idle_total = _decimal(idle_row["total_mw"], metric)
        return (total - idle_total) * Decimal("1000000") / throughput
    if metric == "dynamic_energy_per_byte_nj":
        return _decimal(row["dynamic_mw"], metric) * Decimal("1000000") / throughput
    _fail("unknown comparison metric {}".format(metric))


def _comparison_rows(by_pair):
    rows = []
    for workload in WORKLOADS:
        baseline = by_pair[(workload, "G0")]
        candidate = by_pair[(workload, "G1")]
        idle_baseline = by_pair[("idle", "G0")]
        idle_candidate = by_pair[("idle", "G1")]
        for metric in ALL_METRICS:
            base_value = _point_metric(baseline, metric, idle_baseline)
            candidate_value = _point_metric(candidate, metric, idle_candidate)
            if base_value is None or candidate_value is None:
                base_text = candidate_text = delta_text = percent_text = "NA"
            else:
                delta = candidate_value - base_value
                percent = _percent(delta, base_value)
                base_text = _format_decimal(base_value)
                candidate_text = _format_decimal(candidate_value)
                delta_text = _format_decimal(delta)
                percent_text = "NA" if percent is None else _format_percent(percent)
            if metric == "incremental_energy_per_byte_nj":
                formula = "incremental=(P_workload-P_idle)*1000000/throughput_Bps"
            elif metric == "dynamic_energy_per_byte_nj":
                formula = "dynamic=P_dynamic*1000000/throughput_Bps"
            else:
                formula = "delta=candidate-baseline;delta_percent=100*delta/baseline"
            rows.append({
                "comparison_id": "c2b4_clock_gating_dc__{}__{}".format(workload, metric),
                "comparison_group": FIXED["comparison_group"], "scope": FIXED["scope"],
                "workload_id": workload, "baseline_point": baseline["point_id"],
                "candidate_point": candidate["point_id"], "metric": metric,
                "baseline": base_text, "candidate": candidate_text, "delta": delta_text,
                "delta_percent": percent_text, "formula": formula,
            })
    return rows


def _render_csv(header, rows):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=header, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue()


def _validate_comparisons(root, by_pair, write=False):
    expected_text = _render_csv(COMPARISON_HEADER, _comparison_rows(by_pair))
    path = root / EVIDENCE_REL / "comparisons.csv"
    if write:
        with path.open("w", encoding="utf-8", newline="\n") as output:
            output.write(expected_text)
    try:
        actual = path.read_text(encoding="utf-8")
    except OSError as error:
        _fail("cannot read comparisons.csv: {}".format(error))
    if actual != expected_text:
        _fail("comparisons.csv Decimal recomputation mismatch")
    rows = _read_csv(path, COMPARISON_HEADER)
    if len(rows) != len(WORKLOADS) * len(ALL_METRICS):
        _fail("comparisons.csv row count mismatch")
    lookup = _index_unique(rows, ("workload_id", "metric"), "comparisons")
    for key, expected in EXPECTED_COMPARISON_PERCENT.items():
        actual_percent = _decimal(lookup[key]["delta_percent"], "comparison percent")
        if actual_percent.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN) != Decimal(expected):
            _fail("comparison fixed key value mismatch")
    return rows


def _validate_verification(root, by_pair):
    rows = _read_csv(root / EVIDENCE_REL / "verification.csv", VERIFICATION_HEADER)
    if len(rows) != 12:
        _fail("verification.csv must contain twelve records")
    index = _index_unique(rows, ("variant", "workload_id", "platform"), "verification")
    expected_keys = {(variant, workload, platform) for variant in VARIANTS for workload in WORKLOADS for platform in ("Windows", "Linux")}
    if set(index) != expected_keys:
        _fail("verification.csv matrix mismatch")
    trace_by_workload = {}
    for key, row in index.items():
        variant, workload, platform = key
        if row["point_id"] != by_pair[(workload, variant)]["point_id"]:
            _fail("verification point identity mismatch")
        expected_sim = "ModelSim" if platform == "Windows" else "Questa"
        if row["simulator"] != expected_sim or row["suite"] != "power_c2b4_a1_rtl_contract_reuse":
            _fail("verification platform identity mismatch")
        marker = "POWER_C2B4_WORKLOAD_{}_PASS".format(workload.upper())
        if row["required_marker"] != marker or row["marker_status"] != "PASS" or row["status"] != "PASS":
            _fail("verification marker mismatch")
        if row["comparison_group"] != FIXED["comparison_group"] or row["scope"] != FIXED["scope"]:
            _fail("verification scope mismatch")
        if row["trace_sha256"] != by_pair[(workload, variant)]["trace_sha256"]:
            _fail("verification trace identity mismatch")
        if not HEX64.match(row["trace_sha256"]) or not HEX64.match(row["log_sha256"]):
            _fail("verification SHA-256 mismatch")
        trace_by_workload.setdefault(workload, set()).add(row["trace_sha256"])
    if any(len(values) != 1 for values in trace_by_workload.values()):
        _fail("verification semantic trace mismatch")


def _validate_physical(root):
    rows = _read_csv(root / EVIDENCE_REL / "physical_attempts.csv", PHYSICAL_HEADER)
    if len(rows) != 4:
        _fail("physical_attempts.csv must contain four records")
    index = _index_unique(rows, ("attempt_id",), "physical attempts")
    expected_ids = {
        "c2b4_g0_500_openroad", "c2b4_g1_500_openroad",
        "c2b4_g0_475_openroad", "c2b4_g1_475_openroad",
    }
    if set(index) != expected_ids:
        _fail("physical attempt matrix mismatch")
    for attempt_id, row in index.items():
        if row["top"] != FIXED["top"] or row["profile"] != FIXED["profile"]:
            _fail("physical top/profile mismatch")
        if row["source_commit"] != FIXED["source_commit"] or row["source_sha256"] != FIXED["source_sha256"]:
            _fail("physical source identity mismatch")
        if row["library_sha256"] != FIXED["physical_library_sha256"] or not HEX64.match(row["mapped_netlist_sha256"]):
            _fail("physical handoff identity mismatch")
        for field in (
            "parent_dc_pair_sha256", "mapped_sdc_sha256", "constraints_sha256",
            "floorplan_sha256", "pin_footprint_sha256", "flow_matrix_sha256",
            "driver_sha256",
        ):
            if not HEX64.match(row[field]):
                _fail("physical {} SHA-256 mismatch".format(field))
        expected_variant = "G1" if "_g1_" in attempt_id else "G0"
        if row["variant"] != expected_variant or row["stage"] != "openroad":
            _fail("physical variant/stage mismatch")
        if expected_variant == "G1":
            if row["status"] != "NOT_STARTED_GATE_BLOCKED" or row["stop_reason"] != "predecessor_g0_blocked":
                _fail("physical G1 status mismatch")
            for field in PHYSICAL_HEADER[23:]:
                if row[field] != "NA":
                    _fail("physical G1 metric must remain NA")
    g0_500 = index["c2b4_g0_500_openroad"]
    if (g0_500["status"], g0_500["setup_wns_ns"], g0_500["max_fanout_violation_count"]) != ("BLOCKED_SETUP", "-0.0450512", "15"):
        _fail("500 MHz G0 physical boundary mismatch")
    g0_475 = index["c2b4_g0_475_openroad"]
    if (g0_475["status"], g0_475["setup_wns_ns"], g0_475["hold_wns_ns"], g0_475["max_fanout_violation_count"]) != ("BLOCKED_ELECTRICAL", "0.0363275", "0.0255909", "14"):
        _fail("475 MHz G0 physical boundary mismatch")
    return index


def _validate_artifacts(root, physical):
    rows = _read_csv(root / EVIDENCE_REL / "physical_artifacts.csv", ARTIFACT_HEADER)
    if len(rows) != 26:
        _fail("physical_artifacts.csv must contain 26 artifact hashes")
    index = _index_unique(rows, ("artifact_id",), "physical artifacts")
    per_attempt = {}
    for artifact_id, row in index.items():
        if row["attempt_id"] not in ("c2b4_g0_500_openroad", "c2b4_g0_475_openroad"):
            _fail("physical artifact references an unstarted attempt")
        if not artifact_id.startswith(row["attempt_id"] + "__"):
            _fail("physical artifact ID mismatch")
        if not ID_RE.match(row["logical_name"]) or not HEX64.match(row["sha256"]):
            _fail("physical artifact identity mismatch")
        if not row["size_bytes"].isdigit() or row["distribution"] != "not_distributed":
            _fail("physical artifact distribution mismatch")
        per_attempt[row["attempt_id"]] = per_attempt.get(row["attempt_id"], 0) + 1
    if per_attempt != {"c2b4_g0_500_openroad": 13, "c2b4_g0_475_openroad": 13}:
        _fail("physical artifact inventory mismatch")
    for attempt in per_attempt:
        if attempt not in physical:
            _fail("physical artifact attempt is missing")


def _validate_provenance(root, manifest):
    provenance = _read_json(root / PROVENANCE_REL)
    _expect_keys(provenance, (
        "schema", "branch", "evidence_path", "status", "promotion_eligible",
        "merge_recommended", "production_rtl_changed", "postroute_pair_completed",
        "lec_status", "registered_verified_claim", "release_or_tag_changed",
        "fixed_provenance_revisions", "publication_boundary", "decision",
    ), "experimental provenance")
    expected = {
        "schema": "slvc_dma_experimental_power_branch_v1", "branch": FIXED["branch"],
        "evidence_path": "evidence/asic_power_clock_gating_negative/manifest.json",
        "status": "negative", "promotion_eligible": False, "merge_recommended": False,
        "production_rtl_changed": False, "postroute_pair_completed": False,
        "lec_status": "not_available", "registered_verified_claim": False,
        "release_or_tag_changed": False,
    }
    for field, value in expected.items():
        if provenance[field] != value:
            _fail("experimental provenance {} mismatch".format(field))
    if provenance["fixed_provenance_revisions"] != {
        key: value for key, value in FIXED_REVISIONS.items()
        if key in ("finalization", "machine_evidence", "compatibility_validation")
    }:
        _fail("experimental provenance revisions mismatch")
    boundary = provenance["publication_boundary"]
    if not isinstance(boundary, dict) or boundary != {
        "branch_only": True, "main_modified": False, "pull_request_created": False,
        "release_tag_changed": False, "raw_commercial_artifacts_published": False,
    }:
        _fail("experimental provenance publication boundary mismatch")
    if "no production RTL change" not in provenance["decision"] or "no merge recommendation" not in provenance["decision"]:
        _fail("experimental provenance decision boundary mismatch")
    if manifest["promotion_eligible"] or provenance["promotion_eligible"]:
        _fail("experimental provenance cannot promote the negative result")


def _validate_no_formal_registration(root):
    for relative in ("provenance/claims.yaml", "provenance/evidence.yaml", "provenance/nonclaims.yaml"):
        text = (root / relative).read_text(encoding="utf-8")
        if "asic_power_clock_gating_negative" in text or "automatic_clock_gating_mapped_dc_negative" in text:
            _fail("experimental result must not be registered as a formal claim")


def _validate_docs(root):
    required = {
        "README.md": (
            "ASIC 功耗研究分支", "NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED",
            "不改生产 RTL", "post-route paired power", "LEC/Formality PASS",
        ),
        "README.en.md": (
            "ASIC Power Research Branch", "branch-only",
            "NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED",
            "no production RTL change", "post-route paired power", "LEC/Formality PASS",
        ),
        "docs/en/asic_power_clock_gating_experiment.md": (
            "branch-only", "NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED",
            "no production RTL change", "No post-route paired-power result is made.",
            "LEC/Formality", "not recommended for merge",
        ),
        "docs/zh-CN/asic_power_clock_gating_experiment.md": (
            "branch-only", "NEGATIVE / NOT_PROMOTED / PHYSICALLY_BLOCKED",
            "生产 RTL 保持不变", "post-route paired power", "LEC/Formality",
            "不建议合入 `main`",
        ),
    }
    for relative, needles in required.items():
        text = (root / relative).read_text(encoding="utf-8")
        if any(needle not in text for needle in needles):
            _fail("{} is missing a branch-only negative-result boundary".format(relative))


def _validate_sanitization(root):
    evidence = root / EVIDENCE_REL
    actual_files = {path.name for path in evidence.iterdir() if path.is_file()}
    if actual_files != PACKAGE_FILES | {"hashes.sha256"}:
        _fail("evidence package file inventory mismatch")
    text_paths = [path for path in evidence.iterdir() if path.is_file()]
    text_paths.append(root / PROVENANCE_REL)
    text_paths.extend(root / relative for relative in DOC_FILES)
    for relative in README_FILES:
        text = (root / relative).read_text(encoding="utf-8")
        marker = "## ASIC "
        start = text.find(marker)
        if start < 0:
            _fail("{} is missing the research section".format(relative))
        next_section = text.find("\n<a id=", start)
        section = text[start:] if next_section < 0 else text[start:next_section]
        temporary = evidence / ("__{}".format(relative))
        text_paths.append((temporary, section))
    for item in text_paths:
        if isinstance(item, tuple):
            path, text = item
        else:
            path = item
            if path.suffix.lower() in FORBIDDEN_SUFFIXES:
                _fail("raw EDA payload is forbidden: {}".format(path.relative_to(root)))
            text = path.read_text(encoding="utf-8", errors="replace")
        scan_text = re.sub(r"</[A-Za-z][A-Za-z0-9-]*>", "", text)
        for label, pattern in SENSITIVE_PATTERNS:
            if pattern.search(scan_text):
                _fail("{} contains {}".format(path.relative_to(root) if path.exists() else path.name, label))


def _write_package_hashes(root):
    evidence = root / EVIDENCE_REL
    rows = []
    for name in sorted(PACKAGE_FILES):
        rows.append("{}  {}\n".format(_sha256(evidence / name), name))
    with (evidence / "hashes.sha256").open("w", encoding="utf-8", newline="\n") as output:
        output.write("".join(rows))


def _validate_package_hashes(root, write=False):
    if write:
        _write_package_hashes(root)
    path = root / EVIDENCE_REL / "hashes.sha256"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        _fail("cannot read hashes.sha256: {}".format(error))
    entries = {}
    for line in lines:
        match = re.match(r"^([0-9a-f]{64})  ([A-Za-z0-9_.-]+)$", line)
        if not match:
            _fail("hashes.sha256 line is invalid")
        digest, name = match.groups()
        if name in entries:
            _fail("hashes.sha256 contains a duplicate entry")
        entries[name] = digest
    if set(entries) != PACKAGE_FILES:
        _fail("hashes.sha256 inventory mismatch")
    for name, digest in entries.items():
        if _sha256(root / EVIDENCE_REL / name) != digest:
            _fail("hashes.sha256 digest mismatch")


def _validate_fixed_content_hashes(root):
    for relative, expected in FIXED_CONTENT_SHA256.items():
        path = root / relative if relative.startswith("provenance/") else root / EVIDENCE_REL / relative
        if _sha256(path) != expected:
            _fail("fixed published content hash mismatch for {}".format(relative))


def _git_paths(root, arguments):
    try:
        output = subprocess.check_output(["git"] + list(arguments), cwd=str(root), stderr=subprocess.STDOUT)
    except (OSError, subprocess.CalledProcessError) as error:
        _fail("git scope query failed: {}".format(error))
    return {item.decode("utf-8").replace("\\", "/") for item in output.split(b"\0") if item}


def _validate_branch_scope(root, base_ref):
    changed = set()
    changed.update(_git_paths(root, ("diff", "--name-only", "-z", base_ref + "...HEAD")))
    changed.update(_git_paths(root, ("diff", "--name-only", "-z")))
    changed.update(_git_paths(root, ("diff", "--cached", "--name-only", "-z")))
    changed.update(_git_paths(root, ("ls-files", "--others", "--exclude-standard", "-z")))
    forbidden = sorted(changed - ALLOWED_BRANCH_FILES)
    if forbidden:
        _fail("branch-only scope forbids change to {}".format(forbidden[0]))


def validate(root, write_generated=False, base_ref=None):
    root = Path(root).resolve()
    manifest = _validate_manifest(root)
    by_pair = _validate_points(root)
    comparisons = _validate_comparisons(root, by_pair, write=write_generated)
    _validate_verification(root, by_pair)
    physical = _validate_physical(root)
    _validate_artifacts(root, physical)
    _validate_provenance(root, manifest)
    _validate_no_formal_registration(root)
    _validate_docs(root)
    _validate_package_hashes(root, write=write_generated)
    _validate_sanitization(root)
    _validate_fixed_content_hashes(root)
    if base_ref:
        _validate_branch_scope(root, base_ref)
    return {
        "points": len(by_pair), "comparisons": len(comparisons),
        "verification": 12, "physical_attempts": len(physical), "artifacts": 26,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("--write-generated", action="store_true")
    parser.add_argument("--base-ref")
    args = parser.parse_args(argv)
    try:
        summary = validate(args.root, args.write_generated, args.base_ref)
    except EvidenceError as error:
        print("power-research: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "power-research: {points} points, {comparisons} comparisons, "
        "{verification} verification records, {physical_attempts} physical attempts, "
        "and {artifacts} artifact hashes verified".format(**summary)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
