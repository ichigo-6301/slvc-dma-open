#!/usr/bin/env python3
"""Validate and regenerate the sanitized ASIC paired-DC evidence bundle."""

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


EVIDENCE_REL = Path("evidence/asic_paired_dc")
MANIFEST_REL = EVIDENCE_REL / "manifest.yaml"
COMPARISONS_REL = EVIDENCE_REL / "comparisons.csv"
PUBLICATION_REL = Path("provenance/asic_paired_dc_publication.yaml")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")
EXPECTED_LIBRARY_SHA256 = (
    "111c429e7ae9341d51f5f04b0e4c7574e5c1359de32d51b151470463abe187de"
)

CSV_HEADERS = {
    "points.csv": (
        "evaluation_id", "point_id", "role", "source_commit", "top",
        "parameters", "tool", "tool_version", "compile_mode", "library",
        "corner", "library_sha256", "constraint_id", "clock_period_ns",
        "setup_uncertainty_ns", "hold_uncertainty_ns", "io_delay_ns",
        "input_transition_ns", "output_load", "max_fanout",
        "max_transition_ns", "total_cell_area", "combinational_area",
        "sequential_area", "noncombinational_area", "leaf_cell_count",
        "register_count", "writer_area", "writer_leaf_count",
        "writer_register_count", "setup_wns_ns", "setup_tns_ns",
        "hold_wns_ns", "hold_tns_ns", "writer_setup_wns_ns",
        "writer_hold_wns_ns", "reservation_object_count",
        "setup_violation_count", "hold_violation_count",
        "electrical_violation_count", "unresolved_reference_count",
        "unexpected_blackbox_count", "latch_count",
        "unclocked_sync_endpoint_count",
    ),
    "sources.csv": (
        "evaluation_id", "scope", "point_id", "source_commit", "path",
        "blob", "sha256", "size_bytes",
    ),
    "verification.csv": (
        "evaluation_id", "point_id", "platform", "tool_version",
        "suite_id", "status", "required_markers", "marker_count",
        "semantic_trace_sha256", "log_sha256", "log_size_bytes",
    ),
    "lint.csv": (
        "evaluation_id", "point_id", "scope", "status", "tool_version",
        "fatal_count", "error_count", "warning_count", "waived_count",
        "report_sha256",
    ),
    "artifacts.csv": (
        "evaluation_id", "point_id", "artifact_class", "logical_name",
        "sha256", "published_payload",
    ),
}

COMPARISON_HEADER = (
    "evaluation_id", "claim_id", "baseline_point_id", "candidate_point_id",
    "metric", "baseline", "candidate", "delta", "delta_percent",
)

EXPECTED_EVALUATIONS = {
    "writer_component": {
        "claim_id": "slvc_dma_writer_reservation_component_paired_dc",
        "metrics": (
            "total_cell_area", "combinational_area", "leaf_cell_count",
            "register_count", "setup_wns_ns", "reservation_object_count",
        ),
        "artifacts": (
            "area", "qor", "setup_top20", "hold_top20", "check_design",
            "check_timing", "constraint_identity", "reservation_matches",
        ),
        "roles": {
            "writer_component_w0": "baseline",
            "writer_component_w1": "candidate",
        },
    },
    "c2b4_writer": {
        "claim_id": "slvc_dma_c2b4_writer_subsystem_paired_dc",
        "metrics": (
            "total_cell_area", "combinational_area", "writer_area",
            "setup_wns_ns", "writer_setup_wns_ns",
            "reservation_object_count",
        ),
        "artifacts": (
            "area", "hierarchy_area", "qor", "setup_top20",
            "writer_setup_top20", "reservation_matches", "mapped_netlist",
            "ddc", "mapped_sdc",
        ),
        "roles": {
            "c2b4_writer_w0": "baseline",
            "c2b4_writer_w1": "candidate",
            "c2b4_writer_w2": "canary",
        },
    },
    "shared_pool_scheduler": {
        "claim_id": "slvc_dma_shared_pool_scheduler_paired_dc",
        "metrics": (
            "total_cell_area", "combinational_area", "sequential_area",
            "leaf_cell_count", "register_count", "setup_wns_ns",
        ),
        "artifacts": (
            "area", "qor", "setup_top20", "hold_top20", "check_design",
            "check_timing", "constraints",
        ),
        "roles": {
            "shared_pool_p6": "baseline",
            "shared_pool_p7": "candidate",
        },
    },
}

EXPECTED_MARKERS = {
    "writer_2028": (
        "PASS tb_rtl_rx_payload_writer_512 cases=2028",
        "WIDE512_THROUGHPUT bytes_per_cycle_x1000=64000",
    ),
    "writer_integration": (
        "PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256",
    ),
    "a3_profile": (
        "PASS tb_dma_a3_ingress_profile channels=2 payload_words=512 meta_depth=2",
        "PASS tb_dma_rx512_memory_subsystem channels=2 payload_words=512 meta_depth=2",
    ),
    "shared_pool": (
        "E19_CASE T0 reset_init",
        "E19_CASE T1 single_frame",
        "E19_CASE T2 back_to_back",
        "E19_CASE T3 multi_channel",
        "E19_CASE T4 pool_full_nodrop",
        "E19_CASE T5 pool_full_drop",
        "E19_CASE T6 oversized_drop",
        "E19_CASE T7 drain_stall",
        "E19_CASE T8 reset_recovery",
        "OK: dma RTL v33e19 shared frame pool test passed.",
    ),
}

EXPECTED_SIMULATORS = {
    "windows": "ModelSim SE-64 2020.4",
    "linux": "Questa Sim-64 10.7c",
}

PAIR_IDENTITY_FIELDS = (
    "top", "parameters", "tool", "tool_version", "compile_mode", "library",
    "corner", "library_sha256", "constraint_id", "clock_period_ns",
    "setup_uncertainty_ns", "hold_uncertainty_ns", "io_delay_ns",
    "input_transition_ns", "output_load", "max_fanout", "max_transition_ns",
)

NUMERIC_FIELDS = set(CSV_HEADERS["points.csv"][13:])
ZERO_GATE_FIELDS = (
    "setup_violation_count", "hold_violation_count",
    "electrical_violation_count", "unresolved_reference_count",
    "unexpected_blackbox_count", "latch_count",
    "unclocked_sync_endpoint_count",
)

ALLOWED_SCOPE_PATHS = {
    ".github/workflows/public-integrity.yml",
    "Makefile",
    "docs/en/limitations.md",
    "docs/en/results.md",
    "docs/en/verification.md",
    "docs/zh-CN/limitations.md",
    "docs/zh-CN/results.md",
    "docs/zh-CN/verification.md",
    "flows/scripts/test_validate_asic_evidence.py",
    "flows/scripts/validate_asic_evidence.py",
    "provenance/README.md",
    "provenance/asic_paired_dc_publication.yaml",
    "provenance/checksums.sha256",
    "provenance/claims.yaml",
    "provenance/evidence.yaml",
    "provenance/nonclaims.yaml",
}

SENSITIVE_PATTERNS = (
    ("Windows absolute path", re.compile(r"(?i)(?<![A-Za-z0-9])[A-Z]:[\\/]")),
    ("UNC path", re.compile(r"(?m)(?:^|[\s\"'])\\\\[^\\\s]+\\[^\\\s]+")),
    ("private POSIX path", re.compile(r"(?i)/(?:home|users|mnt|workspace|tmp)/")),
    ("private Git remote", re.compile(r"(?i)(?:git@|ssh://|file://)")),
    ("private branch", re.compile(r"(?i)\b(?:eval|archive|fix)/[A-Za-z0-9_.\-/]+")),
    ("host or account field", re.compile(r"(?i)\b(?:host_?name|user_?name|account_?name)\b\s*[:=]")),
    ("license endpoint", re.compile(
        r"(?i)(?:SNPSLMD_LICENSE_FILE|LM_LICENSE_FILE|CDS_LIC_FILE|license_?(?:server|host))\s*[:=]"
    )),
)


class EvidenceError(RuntimeError):
    pass


def _fail(message):
    raise EvidenceError(message)


def _read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, TypeError, ValueError) as error:
        _fail("invalid JSON-syntax YAML {}: {}".format(path, error))


def _read_csv(path, expected_header):
    try:
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            if tuple(reader.fieldnames or ()) != tuple(expected_header):
                _fail("{} header mismatch".format(path.name))
            rows = list(reader)
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))
    for line_number, row in enumerate(rows, 2):
        if None in row:
            _fail("{}:{} has extra columns".format(path.name, line_number))
        if any(value is None for value in row.values()):
            _fail("{}:{} has missing columns".format(path.name, line_number))
    return rows


def _decimal(value, context):
    try:
        number = Decimal(value)
    except (InvalidOperation, ValueError):
        _fail("{} is not a decimal: {!r}".format(context, value))
    if not number.is_finite():
        _fail("{} is not finite".format(context))
    return number


def _canonical_decimal(number):
    if number == 0:
        return "0"
    rendered = format(number, "f")
    if "." in rendered:
        rendered = rendered.rstrip("0").rstrip(".")
    return rendered


def _validate_digest(value, bits, context):
    pattern = HEX40 if bits == 160 else HEX64
    if not pattern.fullmatch(value or ""):
        _fail("{} must be {} lowercase hex characters".format(context, bits // 4))


def _index_unique(rows, keys, label):
    indexed = {}
    for row in rows:
        key = tuple(row[name] for name in keys)
        if key in indexed:
            _fail("duplicate {} {}".format(label, key))
        indexed[key] = row
    return indexed


def _load_bundle(root):
    evidence = root / EVIDENCE_REL
    manifest = _read_json(root / MANIFEST_REL)
    tables = {}
    for name, header in CSV_HEADERS.items():
        tables[name] = _read_csv(evidence / name, header)
    return manifest, tables


def _validate_manifest(manifest):
    if manifest.get("schema") != "slvc_dma_public_asic_paired_dc_v1":
        _fail("manifest schema mismatch")
    if manifest.get("numeric_source") != "points.csv":
        _fail("points.csv must be the numeric source")
    if manifest.get("derived_source") != "comparisons.csv":
        _fail("comparisons.csv must be the derived source")
    expected_policy = {
        "delta": "candidate-baseline",
        "delta_percent": "100*(candidate-baseline)/baseline",
        "implementation": "decimal_v1",
        "delta_percent_scale": 6,
        "rounding": "ROUND_HALF_EVEN",
    }
    if manifest.get("formula_policy") != expected_policy:
        _fail("formula policy mismatch")
    evaluations = manifest.get("evaluations")
    if not isinstance(evaluations, list):
        _fail("manifest evaluations must be a list")
    by_id = {}
    claims = set()
    for item in evaluations:
        if not isinstance(item, dict) or not ID_RE.fullmatch(item.get("id", "")):
            _fail("invalid evaluation manifest entry")
        evaluation_id = item["id"]
        if evaluation_id in by_id:
            _fail("duplicate evaluation {}".format(evaluation_id))
        by_id[evaluation_id] = item
        claim_id = item.get("claim_id", "")
        if claim_id in claims:
            _fail("claim ID reused: {}".format(claim_id))
        claims.add(claim_id)
        for name in ("private_evidence_commit", "flow_as_run_commit"):
            if name in item:
                _validate_digest(item[name], 160, "{}.{}".format(evaluation_id, name))
    if set(by_id) != set(EXPECTED_EVALUATIONS):
        _fail("evaluation matrix mismatch")
    for evaluation_id, expected in EXPECTED_EVALUATIONS.items():
        item = by_id[evaluation_id]
        if item.get("claim_id") != expected["claim_id"]:
            _fail("{} claim ID mismatch".format(evaluation_id))
        for point_id, role in expected["roles"].items():
            manifest_key = {"baseline": "baseline", "candidate": "candidate", "canary": "canary"}[role]
            if item.get(manifest_key) != point_id:
                _fail("{} {} point mismatch".format(evaluation_id, role))
        metrics = item.get("comparison_metrics")
        if not isinstance(metrics, list) or tuple(metrics) != expected["metrics"]:
            _fail("{} fixed comparison metrics mismatch".format(evaluation_id))
        artifacts = item.get("required_artifacts")
        if not isinstance(artifacts, list) or tuple(artifacts) != expected["artifacts"]:
            _fail("{} fixed artifact list mismatch".format(evaluation_id))
    return by_id


def _validate_points(rows, evaluations):
    by_key = _index_unique(rows, ("evaluation_id", "point_id"), "point")
    expected_keys = {
        (evaluation_id, point_id)
        for evaluation_id, definition in EXPECTED_EVALUATIONS.items()
        for point_id in definition["roles"]
    }
    if set(by_key) != expected_keys:
        _fail("point matrix mismatch")
    for key, row in by_key.items():
        evaluation_id, point_id = key
        expected_role = EXPECTED_EVALUATIONS[evaluation_id]["roles"][point_id]
        if row["role"] != expected_role:
            _fail("{} role mismatch".format(point_id))
        _validate_digest(row["source_commit"], 160, "{}.source_commit".format(point_id))
        _validate_digest(row["library_sha256"], 256, "{}.library_sha256".format(point_id))
        if row["library_sha256"] != EXPECTED_LIBRARY_SHA256:
            _fail("{} library DB identity mismatch".format(point_id))
        if row["tool"] != "Design Compiler" or row["tool_version"] != "O-2018.06-SP1":
            _fail("{} tool identity mismatch".format(point_id))
        if row["compile_mode"] != "compile_ultra":
            _fail("{} compile mode mismatch".format(point_id))
        if row["library"] != "Nangate45" or row["corner"] != "typical":
            _fail("{} library/corner mismatch".format(point_id))
        if row["top"] != evaluations[evaluation_id]["top"]:
            _fail("{} top mismatch with manifest".format(point_id))
        if row["parameters"] != evaluations[evaluation_id]["parameters"]:
            _fail("{} parameters mismatch with manifest".format(point_id))
        if row["constraint_id"] != evaluations[evaluation_id]["constraint_id"]:
            _fail("{} constraint mismatch with manifest".format(point_id))
        for field in NUMERIC_FIELDS:
            if row[field] != "":
                _decimal(row[field], "{}.{}".format(point_id, field))
        for field in ZERO_GATE_FIELDS:
            if _decimal(row[field], "{}.{}".format(point_id, field)) != 0:
                _fail("{} has nonzero {}".format(point_id, field))
        if _decimal(row["setup_wns_ns"], point_id + ".setup_wns_ns") < 0:
            _fail("{} has negative setup WNS in setup-closed evidence".format(point_id))
        if _decimal(row["setup_tns_ns"], point_id + ".setup_tns_ns") != 0:
            _fail("{} has nonzero setup TNS in setup-closed evidence".format(point_id))
        if _decimal(row["hold_wns_ns"], point_id + ".hold_wns_ns") < 0:
            _fail("{} has negative hold WNS in hold-closed evidence".format(point_id))
        if _decimal(row["hold_tns_ns"], point_id + ".hold_tns_ns") != 0:
            _fail("{} has nonzero hold TNS in hold-closed evidence".format(point_id))
        for field in ("writer_setup_wns_ns", "writer_hold_wns_ns"):
            if row[field] != "" and _decimal(row[field], point_id + "." + field) < 0:
                _fail("{} has negative {}".format(point_id, field))
    for evaluation_id, item in evaluations.items():
        baseline = by_key[(evaluation_id, item["baseline"])]
        candidate = by_key[(evaluation_id, item["candidate"])]
        for field in PAIR_IDENTITY_FIELDS:
            if baseline[field] != candidate[field]:
                _fail("{} pair identity mismatch: {}".format(evaluation_id, field))
        for metric in item["comparison_metrics"]:
            if baseline[metric] == "" or candidate[metric] == "":
                _fail("{} comparison metric {} is empty".format(evaluation_id, metric))
    return by_key


def _validate_sources(rows, points):
    _index_unique(rows, ("evaluation_id", "scope", "point_id", "path"), "source")
    point_sources = {}
    for row in rows:
        _validate_digest(row["source_commit"], 160, "source commit")
        _validate_digest(row["blob"], 160, "source blob")
        _validate_digest(row["sha256"], 256, "source sha256")
        if _decimal(row["size_bytes"], "source size") <= 0:
            _fail("source size must be positive")
        if row["scope"] not in ("point", "common"):
            _fail("invalid source scope")
        if row["scope"] == "point":
            key = (row["evaluation_id"], row["point_id"])
            if key not in points:
                _fail("source references unknown point {}".format(key))
            if row["source_commit"] != points[key]["source_commit"]:
                _fail("commit/source mapping mismatch for {}".format(key))
            point_sources.setdefault(key, []).append(row)
        elif row["point_id"] != "*":
            _fail("common source point_id must be *")
    if set(point_sources) != set(points):
        _fail("every point must have a fixed source mapping")

    for component_point, c2b4_point in (
        ("writer_component_w0", "c2b4_writer_w0"),
        ("writer_component_w1", "c2b4_writer_w1"),
    ):
        left = point_sources[("writer_component", component_point)]
        right = point_sources[("c2b4_writer", c2b4_point)]
        left_map = {(row["path"], row["source_commit"], row["sha256"], row["blob"], row["size_bytes"]) for row in left}
        right_map = {(row["path"], row["source_commit"], row["sha256"], row["blob"], row["size_bytes"]) for row in right}
        if left_map != right_map:
            _fail("writer component/C2B4 source hash mismatch for {}".format(component_point))


def _validate_verification(rows, points, evaluations):
    by_key = _index_unique(
        rows, ("evaluation_id", "point_id", "platform", "suite_id"),
        "verification",
    )
    expected = set()
    for point_id in EXPECTED_EVALUATIONS["c2b4_writer"]["roles"]:
        for platform in ("windows", "linux"):
            for suite in ("writer_2028", "writer_integration", "a3_profile"):
                expected.add(("c2b4_writer", point_id, platform, suite))
    for point_id in EXPECTED_EVALUATIONS["shared_pool_scheduler"]["roles"]:
        for platform in ("windows", "linux"):
            expected.add(("shared_pool_scheduler", point_id, platform, "shared_pool"))
    if set(by_key) != expected:
        _fail("verification matrix mismatch")
    traces = {}
    for key, row in by_key.items():
        if row["status"] != "PASS":
            _fail("verification status is not PASS for {}".format(key))
        expected_tool = EXPECTED_SIMULATORS.get(row["platform"])
        if row["tool_version"] != expected_tool:
            _fail("simulator identity mismatch for {}".format(key))
        markers = tuple(row["required_markers"].split("|")) if row["required_markers"] else ()
        expected_markers = EXPECTED_MARKERS[row["suite_id"]]
        if markers != expected_markers:
            _fail("canonical required markers mismatch for {}".format(key))
        if int(row["marker_count"]) != len(expected_markers):
            _fail("required marker count mismatch for {}".format(key))
        _validate_digest(row["semantic_trace_sha256"], 256, "semantic trace")
        _validate_digest(row["log_sha256"], 256, "verification log")
        if int(row["log_size_bytes"]) <= 0:
            _fail("verification log size must be positive")
        trace_key = (row["evaluation_id"], row["suite_id"])
        traces.setdefault(trace_key, set()).add(row["semantic_trace_sha256"])
    for trace_key, digests in traces.items():
        if len(digests) != 1:
            _fail("semantic trace mismatch for {}".format(trace_key))
    if evaluations["writer_component"].get("verification_reference") != "c2b4_writer":
        _fail("writer component verification reference mismatch")
    for suffix in ("w0", "w1"):
        component = points[("writer_component", "writer_component_" + suffix)]
        subsystem = points[("c2b4_writer", "c2b4_writer_" + suffix)]
        if component["source_commit"] != subsystem["source_commit"]:
            _fail("writer verification source commit mismatch")


def _validate_lint(rows):
    by_key = _index_unique(rows, ("evaluation_id", "point_id", "scope"), "lint")
    expected_keys = {
        ("c2b4_writer", point_id, "writer_bounded")
        for point_id in EXPECTED_EVALUATIONS["c2b4_writer"]["roles"]
    }
    expected_keys.add(("c2b4_writer", "common_snapshot", "full_c2b4_common"))
    expected_keys.update({
        ("shared_pool_scheduler", point_id, "component_bounded")
        for point_id in EXPECTED_EVALUATIONS["shared_pool_scheduler"]["roles"]
    })
    if set(by_key) != expected_keys:
        _fail("lint matrix mismatch")
    for key, row in by_key.items():
        _validate_digest(row["report_sha256"], 256, "lint report")
        if row["tool_version"] != "SpyGlass L-2016.06":
            _fail("lint tool identity mismatch for {}".format(key))
        counts = {name: int(row[name]) for name in (
            "fatal_count", "error_count", "warning_count", "waived_count"
        )}
        if key == ("c2b4_writer", "common_snapshot", "full_c2b4_common"):
            expected = {"fatal_count": 0, "error_count": 15, "warning_count": 202, "waived_count": 0}
            if row["status"] != "BLOCKED_COMMON_SCOPE" or counts != expected:
                _fail("C2B4 lint boundary must remain BLOCKED_COMMON_SCOPE 0/15/202/0")
        else:
            if row["status"] != "PASS_WITH_REVIEWED_WARNINGS":
                _fail("bounded lint status mismatch for {}".format(key))
            if counts["fatal_count"] != 0 or counts["error_count"] != 0:
                _fail("bounded lint has fatal/error for {}".format(key))
            if counts["waived_count"] != 0:
                _fail("lint waivers are not permitted for {}".format(key))


def _validate_artifacts(rows, evaluations, points):
    by_key = _index_unique(rows, ("evaluation_id", "point_id", "logical_name"), "artifact")
    grouped = {}
    for key, row in by_key.items():
        evaluation_id, point_id, logical_name = key
        if (evaluation_id, point_id) not in points:
            _fail("artifact references unknown point {}".format(key))
        _validate_digest(row["sha256"], 256, "artifact hash")
        if row["published_payload"] != "hash_only":
            _fail("artifact payload must be hash_only")
        if row["artifact_class"] not in ("dc_report", "mapped_output"):
            _fail("invalid artifact class")
        grouped.setdefault((evaluation_id, point_id), set()).add(logical_name)
    for (evaluation_id, point_id) in points:
        required = set(evaluations[evaluation_id]["required_artifacts"])
        if grouped.get((evaluation_id, point_id)) != required:
            _fail("artifact checklist mismatch for {}".format(point_id))


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _registered_records(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))
    records = {}
    current_id = None
    current_lines = []
    for line in text.splitlines():
        match = re.fullmatch(r"  - id: ([a-z0-9_.-]+)", line)
        if match:
            if current_id is not None:
                records[current_id] = "\n".join(current_lines)
            current_id = match.group(1)
            if current_id in records:
                _fail("{} contains duplicate IDs".format(path))
            current_lines = []
        elif current_id is not None:
            current_lines.append(line)
    if current_id is not None:
        if current_id in records:
            _fail("{} contains duplicate IDs".format(path))
        records[current_id] = "\n".join(current_lines)
    return records


def _record_list(body, field, context):
    lines = body.splitlines()
    marker = "    {}:".format(field)
    try:
        start = lines.index(marker) + 1
    except ValueError:
        _fail("{} has no {} list".format(context, field))
    values = []
    for line in lines[start:]:
        match = re.fullmatch(r"      - ([a-z0-9_.-]+)", line)
        if not match:
            break
        values.append(match.group(1))
    if not values or len(values) != len(set(values)):
        _fail("{} has invalid {} list".format(context, field))
    return values


def _validate_publication(root, evaluations):
    publication = _read_json(root / PUBLICATION_REL)
    if publication.get("schema") != "slvc_dma_asic_paired_dc_publication_v1":
        _fail("publication schema mismatch")
    if publication.get("publication_class") != "sanitized_hash_bound_summary":
        _fail("publication class mismatch")
    if publication.get("numeric_authority") != str(EVIDENCE_REL / "points.csv").replace("\\", "/"):
        _fail("publication numeric authority mismatch")
    if publication.get("generated_derivative") != str(COMPARISONS_REL).replace("\\", "/"):
        _fail("publication derivative mismatch")
    if publication.get("raw_commercial_artifacts_published") is not False:
        _fail("raw commercial artifacts must remain unpublished")

    expected_claims = {item["claim_id"] for item in evaluations.values()}
    claim_ids = publication.get("claim_ids")
    if not isinstance(claim_ids, list) or len(claim_ids) != len(set(claim_ids)):
        _fail("publication claim IDs are invalid")
    if set(claim_ids) != expected_claims:
        _fail("publication claim IDs mismatch")
    expected_commits = {item["private_evidence_commit"] for item in evaluations.values()}
    commits = publication.get("fixed_evidence_commits")
    if not isinstance(commits, list) or set(commits) != expected_commits:
        _fail("publication evidence commits mismatch")
    for commit in commits:
        _validate_digest(commit, 160, "publication evidence commit")

    expected_files = {
        str(path.relative_to(root)).replace("\\", "/")
        for path in (root / EVIDENCE_REL).rglob("*") if path.is_file()
    }
    files = publication.get("files")
    if not isinstance(files, dict) or set(files) != expected_files:
        _fail("publication file inventory mismatch")
    for relative, digest in files.items():
        _validate_digest(digest, 256, "publication file hash")
        if _sha256(root / relative) != digest:
            _fail("publication hash mismatch for {}".format(relative))

    expected_lint = {
        "status": "BLOCKED_COMMON_SCOPE", "fatal": 0, "error": 15,
        "warning": 202, "waived": 0,
    }
    if publication.get("c2b4_lint_boundary") != expected_lint:
        _fail("publication C2B4 lint boundary mismatch")
    if publication.get("commercial_artifact_policy") != "logical_name_and_sha256_only":
        _fail("publication commercial artifact policy mismatch")

    claim_records = _registered_records(root / "provenance/claims.yaml")
    evidence_records = _registered_records(root / "provenance/evidence.yaml")
    if not expected_claims.issubset(claim_records):
        _fail("paired-DC claim is missing from provenance/claims.yaml")
    publication_id = "slvc_dma_asic_paired_dc_publication"
    if publication_id not in evidence_records:
        _fail("paired-DC evidence is missing from provenance/evidence.yaml")
    for claim_id in expected_claims:
        references = _record_list(claim_records[claim_id], "evidence", claim_id)
        if references != [publication_id]:
            _fail("paired-DC claims are not bound to publication evidence")
    mapped_claims = set(_record_list(
        evidence_records[publication_id], "claims", publication_id
    ))
    if mapped_claims != expected_claims:
        _fail("publication evidence claim mapping mismatch")
    publication_path = re.search(
        r"(?m)^    path: (\S+)\s*$", evidence_records[publication_id]
    )
    publication_hash = re.search(
        r"(?m)^    sha256: ([0-9a-f]{64})\s*$", evidence_records[publication_id]
    )
    expected_path = str(PUBLICATION_REL).replace("\\", "/")
    if not publication_path or publication_path.group(1) != expected_path:
        _fail("provenance evidence path must bind the publication manifest")
    if not publication_hash or publication_hash.group(1) != _sha256(root / PUBLICATION_REL):
        _fail("provenance evidence hash must bind the publication manifest")


def _comparison_bytes(evaluations, points):
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=COMPARISON_HEADER, lineterminator="\n")
    writer.writeheader()
    quantizer = Decimal("0.000001")
    for evaluation_id in ("writer_component", "c2b4_writer", "shared_pool_scheduler"):
        item = evaluations[evaluation_id]
        baseline = points[(evaluation_id, item["baseline"])]
        candidate = points[(evaluation_id, item["candidate"])]
        for metric in item["comparison_metrics"]:
            baseline_value = _decimal(baseline[metric], metric)
            candidate_value = _decimal(candidate[metric], metric)
            delta = candidate_value - baseline_value
            percent = ""
            if baseline_value != 0:
                percent = _canonical_decimal(
                    (Decimal(100) * delta / baseline_value).quantize(
                        quantizer, rounding=ROUND_HALF_EVEN
                    )
                )
            writer.writerow({
                "evaluation_id": evaluation_id,
                "claim_id": item["claim_id"],
                "baseline_point_id": item["baseline"],
                "candidate_point_id": item["candidate"],
                "metric": metric,
                "baseline": _canonical_decimal(baseline_value),
                "candidate": _canonical_decimal(candidate_value),
                "delta": _canonical_decimal(delta),
                "delta_percent": percent,
            })
    return output.getvalue().encode("utf-8")


def _validate_comparisons(root, expected, write):
    path = root / COMPARISONS_REL
    if write:
        path.write_bytes(expected)
        return
    if not path.is_file():
        _fail("comparisons.csv is missing")
    if path.read_bytes() != expected:
        _fail("comparisons.csv does not match Decimal recomputation")


def _validate_sanitization(root, extra_paths=None):
    evidence = root / EVIDENCE_REL
    forbidden_suffixes = {".log", ".rpt", ".ddc", ".sdc", ".spef", ".db"}
    for path in evidence.rglob("*"):
        if path.is_file() and path.suffix.lower() in forbidden_suffixes:
            _fail("raw EDA artifact is forbidden: {}".format(path.relative_to(root)))
    paths = [path for path in evidence.rglob("*") if path.is_file()]
    publication = root / "provenance/asic_paired_dc_publication.yaml"
    if publication.is_file():
        paths.append(publication)
    for path in extra_paths or ():
        candidate = root / path
        if candidate.is_file() and candidate not in paths:
            paths.append(candidate)
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        for label, pattern in SENSITIVE_PATTERNS:
            if pattern.search(text):
                _fail("{} contains {}".format(path.relative_to(root), label))


def _git_paths(root, arguments):
    try:
        output = subprocess.check_output(
            ["git"] + list(arguments), cwd=str(root), stderr=subprocess.STDOUT
        )
    except (OSError, subprocess.CalledProcessError) as error:
        _fail("git scope query failed: {}".format(error))
    return [item.decode("utf-8").replace("\\", "/") for item in output.split(b"\0") if item]


def _validate_scope(root, base_ref):
    changed = set(_git_paths(root, ("diff", "--name-only", "-z", base_ref + "...HEAD")))
    changed.update(_git_paths(root, ("diff", "--name-only", "-z")))
    changed.update(_git_paths(root, ("diff", "--cached", "--name-only", "-z")))
    changed.update(_git_paths(root, ("ls-files", "--others", "--exclude-standard", "-z")))
    for path in sorted(changed):
        if path.startswith("evidence/asic_paired_dc/"):
            continue
        if path not in ALLOWED_SCOPE_PATHS:
            _fail("PR scope forbids change to {}".format(path))
    published_text = {
        path for path in changed
        if path.startswith(("evidence/", "provenance/", "docs/"))
    }
    _validate_sanitization(root, published_text)


def validate(root, write_comparisons=False, base_ref=None):
    root = Path(root).resolve()
    manifest, tables = _load_bundle(root)
    evaluations = _validate_manifest(manifest)
    points = _validate_points(tables["points.csv"], evaluations)
    _validate_sources(tables["sources.csv"], points)
    _validate_verification(tables["verification.csv"], points, evaluations)
    _validate_lint(tables["lint.csv"])
    _validate_artifacts(tables["artifacts.csv"], evaluations, points)
    expected = _comparison_bytes(evaluations, points)
    _validate_comparisons(root, expected, write_comparisons)
    _validate_sanitization(root)
    _validate_publication(root, evaluations)
    if base_ref:
        _validate_scope(root, base_ref)
    return {
        "evaluations": len(evaluations),
        "points": len(points),
        "comparisons": expected.count(b"\n") - 1,
        "verification_records": len(tables["verification.csv"]),
        "artifact_hashes": len(tables["artifacts.csv"]),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("--write-comparisons", action="store_true")
    parser.add_argument("--base-ref")
    args = parser.parse_args(argv)
    try:
        summary = validate(args.root, args.write_comparisons, args.base_ref)
    except EvidenceError as error:
        print("asic-evidence: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "asic-evidence: {evaluations} evaluations, {points} points, "
        "{comparisons} comparisons, {verification_records} verification records, "
        "and {artifact_hashes} artifact hashes verified".format(**summary)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
