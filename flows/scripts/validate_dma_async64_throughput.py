#!/usr/bin/env python3
"""Collect and validate the private Async64 end-to-end throughput experiment."""

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


BASELINE_COMMIT = "c20681fad0eaa6ad55dbb919149765b175b29117"
PACKAGE_REL = Path("evidence/throughput_private/async64_end_to_end")
MANIFEST_REL = PACKAGE_REL / "manifest.json"
POINTS_REL = PACKAGE_REL / "points.csv"
METRICS_REL = PACKAGE_REL / "metrics.csv"
LATENCY_REL = PACKAGE_REL / "latency.csv"
VERIFICATION_REL = PACKAGE_REL / "verification.csv"
ARTIFACTS_REL = PACKAGE_REL / "artifacts.csv"
MATRIX_REL = PACKAGE_REL / "matrix.csv"
STALLS_REL = PACKAGE_REL / "stall_breakdown.csv"

HEX64 = re.compile(r"^[0-9a-f]{64}$")
KEY_VALUE = re.compile(r"([A-Za-z0-9_]+)=([^\s]+)")
PRIVATE_PATTERNS = (
    re.compile(r"[A-Za-z]:[\\/]"),
    re.compile(r"/(?:home|Users|tmp)/[A-Za-z0-9_.-]+/"),
    re.compile(r"(?:LM_LICENSE_FILE|SNPSLMD_LICENSE_FILE|MGLS_LICENSE_FILE)", re.I),
    re.compile(r"(?:license[_-]?server|private[_-]?remote|hostname)", re.I),
)

POINT_HEADER = (
    "point_id", "platform", "simulator", "case", "frames",
    "payload_bytes", "shared_service", "response_latency_cycles",
    "service_percent", "mem_phase_ns", "clock_mhz", "hw_cycles",
    "steady_cycles", "rx_axis_valid", "rx_axis_ready", "rx_axis_fire",
    "tx_axis_valid", "tx_axis_ready", "tx_axis_fire", "main_read_bytes",
    "rx_payload_write_bytes", "cq_bus_write_bytes", "main_ar_bursts",
    "main_aw_bursts", "rx_aw_bursts", "rx_peak_outstanding",
    "tx_peak_outstanding", "rx_input_stall", "cdc_payload_stall",
    "aw_stall", "w_stall", "b_stall", "ar_stall", "r_stall",
    "rx_cqe", "tx_cqe", "frame_fail",
    "frame_drop", "deadlock", "protocol_error", "status", "pass_marker",
)
METRIC_HEADER = (
    "point_id", "window", "payload_bytes", "cycles", "bytes_per_cycle",
    "gb_per_s_at_100mhz", "gbits_per_s_at_100mhz", "frames_per_s_at_100mhz",
    "claim_eligible",
)
LATENCY_HEADER = ("point_id", "sample", "sequence", "channel", "cycles")
VERIFICATION_HEADER = (
    "verification_id", "platform", "simulator", "case", "frames",
    "model", "status", "required_marker", "marker_present",
    "pass_marker_present", "semantic_trace_sha256", "artifact_id", "note",
)
ARTIFACT_HEADER = ("artifact_id", "logical_name", "sha256", "size_bytes", "published")
MATRIX_HEADER = (
    "point_id", "scenario", "frames", "payload_bytes", "model",
    "response_latency_cycles", "service_percent", "mem_phase_ns", "status",
    "blocked_by",
)
STALL_HEADER = (
    "point_id", "rx_input_stall", "cdc_payload_stall", "aw_stall",
    "w_stall", "b_stall", "ar_stall", "r_stall",
)

SOURCE_PATHS = (
    "rtl/integration/frame_dma_rx_top.v",
    "rtl/rx/dma_rx_payload_cdc_bridge.v",
    "rtl/tx/dma_axi_read_prefetch.v",
    "filelists/dma_rtl.f",
    "pattern/dma_sim_def.vh",
    "pattern/axi_hp0_dual_master_64_model.v",
    "pattern/tb_rtl_dma_async64_end_to_end_throughput.v",
    "modelsim/run_rtl_dma_async64_end_to_end_throughput.do",
)

LOG_SPECS = (
    ("win_rx4_shared", "rx_peak_4_final.log", "rx_peak", "4", "HP0_SHARED",
     "BLOCKED_PROTOCOL_CONTRACT"),
    ("win_loop1_shared", "loopback_peak_1_final.log", "loopback_peak", "1",
     "HP0_SHARED", "BLOCKED_PROTOCOL_CONTRACT"),
    ("win_loop2_shared", "loopback_peak_2_diag.log", "loopback_peak", "2",
     "HP0_SHARED", "INCONCLUSIVE_MULTI_FRAME_LOOPBACK"),
    ("win_loop2_split", "loopback_peak_2_split.log", "loopback_peak", "2",
     "IDEAL_SPLIT", "INCONCLUSIVE_MULTI_FRAME_LOOPBACK"),
)


class ValidationError(Exception):
    pass


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    return sha256_bytes(path.read_bytes())


def parse_marker(line, marker):
    if marker not in line:
        return None
    return dict(KEY_VALUE.findall(line.split(marker, 1)[1]))


def read_csv(path, header):
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != header:
            raise ValidationError("unexpected CSV header in {}".format(path))
        return list(reader)


def csv_bytes(header, rows):
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=header, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue().encode("utf-8")


def decimal_text(value):
    return format(value.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN), "f")


def generated_metrics(points):
    rows = []
    clock_hz = Decimal("100000000")
    for point in points:
        payload = Decimal(point["payload_bytes"])
        frames = Decimal(point["frames"])
        for window, cycle_field in (("hardware_end_to_end", "hw_cycles"),
                                    ("datapath_steady_state", "steady_cycles")):
            cycles = Decimal(point[cycle_field])
            bpc = payload / cycles
            rows.append({
                "point_id": point["point_id"],
                "window": window,
                "payload_bytes": point["payload_bytes"],
                "cycles": point[cycle_field],
                "bytes_per_cycle": decimal_text(bpc),
                "gb_per_s_at_100mhz": decimal_text(bpc * Decimal("0.1")),
                "gbits_per_s_at_100mhz": decimal_text(bpc * Decimal("0.8")),
                "frames_per_s_at_100mhz": decimal_text(clock_hz * frames / cycles),
                "claim_eligible": "false",
            })
    return rows


def generated_stalls(points):
    return [{field: point[field] for field in STALL_HEADER} for point in points]


def planned_matrix():
    rows = []
    blocker = "ASYNC64_SOURCE_PAYLOAD_WINDOW_CONTRACT"

    def add(point_id, scenario, payload, model="HP0_SHARED", latency=16,
            service=100, phase=3):
        rows.append({
            "point_id": point_id,
            "scenario": scenario,
            "frames": "1024",
            "payload_bytes": str(payload),
            "model": model,
            "response_latency_cycles": str(latency),
            "service_percent": str(service),
            "mem_phase_ns": str(phase),
            "status": "NOT_RUN_PREREQUISITE",
            "blocked_by": blocker,
        })

    for phase in (1, 3, 7):
        add("rx_peak_phase{}".format(phase), "rx_peak", 4096, phase=phase)
        add("loopback_peak_phase{}".format(phase), "loopback_peak", 4096,
            phase=phase)
    add("rx_peak_ideal_split", "rx_peak", 4096, model="IDEAL_SPLIT")
    add("loopback_peak_ideal_split", "loopback_peak", 4096,
        model="IDEAL_SPLIT")
    for size in (64, 128, 256, 1024, 4096):
        add("rx_size_{}".format(size), "rx_size", size)
        add("loopback_size_{}".format(size), "loopback_size", size)
    add("mixed16", "mixed16", "mixed_64_128_256_1024_4096")
    for latency in (8, 16, 32):
        for service in (100, 75, 50):
            add("hp0_l{}_s{}".format(latency, service), "hp0_sensitivity",
                4096, latency=latency, service=service)
    return rows


def normalized_trace(lines):
    selected = []
    for line in lines:
        for marker in ("DMA_TP_TRACE", "DMA_TP_BRIDGE_CAUSE",
                       "DMA_TP_ERROR_COUNTS", "DMA_TP_TIMEOUT_STATE"):
            if marker in line:
                selected.append(line.split(marker, 1)[1].strip())
                break
    return ("\n".join(selected) + ("\n" if selected else "")).encode("utf-8")


def collect(root, smoke_dir):
    package = root / PACKAGE_REL
    package.mkdir(parents=True, exist_ok=True)
    points = []
    latencies = []
    verification = []
    artifacts = []

    for point_id, filename, case_name, frames, model, expected_status in LOG_SPECS:
        path = smoke_dir / filename
        if not path.is_file():
            raise ValidationError("missing smoke log {}".format(path))
        raw = path.read_bytes()
        text = raw.decode("utf-8", errors="replace")
        lines = text.splitlines()
        raw_point = next((parse_marker(line, "DMA_TP_RAW_POINT") for line in lines
                          if "DMA_TP_RAW_POINT" in line), None)
        error_counts = next((parse_marker(line, "DMA_TP_ERROR_COUNTS") for line in lines
                             if "DMA_TP_ERROR_COUNTS" in line), None)
        pass_present = "DMA_ASYNC64_END_TO_END_THROUGHPUT_PASS" in text
        cause_present = "cause=source_payload_outside_frame" in text
        timeout_present = "DMA_TP_TIMEOUT_STATE" in text
        artifact_id = "log_{}".format(point_id)
        artifacts.append({
            "artifact_id": artifact_id,
            "logical_name": "private_smoke/{}".format(filename),
            "sha256": sha256_bytes(raw),
            "size_bytes": str(len(raw)),
            "published": "false",
        })
        verification.append({
            "verification_id": point_id,
            "platform": "windows",
            "simulator": "ModelSim SE-64 2020.4",
            "case": case_name,
            "frames": frames,
            "model": model,
            "status": expected_status,
            "required_marker": ("DMA_TP_BRIDGE_CAUSE" if "PROTOCOL" in expected_status
                                else "DMA_TP_TIMEOUT_STATE"),
            "marker_present": "true" if (cause_present if "PROTOCOL" in expected_status
                                              else timeout_present) else "false",
            "pass_marker_present": "true" if pass_present else "false",
            "semantic_trace_sha256": sha256_bytes(normalized_trace(lines)),
            "artifact_id": artifact_id,
            "note": ("Payload and CQ completed before the strict protocol gate."
                     if raw_point else
                     "Multi-frame smoke timed out before a claimable point."),
        })
        if raw_point:
            if error_counts is None:
                raise ValidationError("missing error counts in {}".format(filename))
            point = {
                "point_id": point_id,
                "platform": "windows",
                "simulator": "ModelSim SE-64 2020.4",
                "case": raw_point["case"],
                "frames": raw_point["frames"],
                "payload_bytes": raw_point["payload_bytes"],
                "shared_service": raw_point["shared"],
                "response_latency_cycles": raw_point["response_latency"],
                "service_percent": raw_point["service_percent"],
                "mem_phase_ns": raw_point["mem_phase_ns"],
                "clock_mhz": "100",
                "hw_cycles": raw_point["hw_cycles"],
                "steady_cycles": raw_point["steady_cycles"],
                "rx_axis_valid": raw_point["rx_axis_valid"],
                "rx_axis_ready": raw_point["rx_axis_ready"],
                "rx_axis_fire": raw_point["rx_axis_fire"],
                "tx_axis_valid": raw_point["tx_axis_valid"],
                "tx_axis_ready": raw_point["tx_axis_ready"],
                "tx_axis_fire": raw_point["tx_axis_fire"],
                "main_read_bytes": raw_point["main_read_bytes"],
                "rx_payload_write_bytes": raw_point["rx_payload_write_bytes"],
                "cq_bus_write_bytes": raw_point["cq_bus_write_bytes"],
                "main_ar_bursts": raw_point["main_ar_bursts"],
                "main_aw_bursts": raw_point["main_aw_bursts"],
                "rx_aw_bursts": raw_point["rx_aw_bursts"],
                "rx_peak_outstanding": raw_point["rx_peak_outstanding"],
                "tx_peak_outstanding": raw_point["tx_peak_outstanding"],
                "rx_input_stall": raw_point["rx_input_stall"],
                "cdc_payload_stall": raw_point["cdc_payload_stall"],
                "aw_stall": raw_point["aw_stall"],
                "w_stall": raw_point["w_stall"],
                "b_stall": raw_point["b_stall"],
                "ar_stall": raw_point["ar_stall"],
                "r_stall": raw_point["r_stall"],
                "rx_cqe": raw_point["rx_cqe"],
                "tx_cqe": raw_point["tx_cqe"],
                "frame_fail": error_counts["frame_fail"],
                "frame_drop": error_counts["frame_drop"],
                "deadlock": error_counts["deadlock"],
                "protocol_error": raw_point["protocol_error"],
                "status": expected_status,
                "pass_marker": "true" if pass_present else "false",
            }
            points.append(point)
        sample = 0
        for line in lines:
            parsed = parse_marker(line, "DMA_TP_LATENCY")
            if parsed:
                sample += 1
                latencies.append({
                    "point_id": point_id,
                    "sample": str(sample),
                    "sequence": parsed["seq"],
                    "channel": parsed["ch"],
                    "cycles": parsed["cycles"],
                })

    verification.append({
        "verification_id": "linux_questa_reference",
        "platform": "linux",
        "simulator": "Questa",
        "case": "rx_peak",
        "frames": "1",
        "model": "HP0_SHARED",
        "status": "NOT_RUN_ENVIRONMENT_UNREACHABLE",
        "required_marker": "DMA_TP_BRIDGE_CAUSE",
        "marker_present": "false",
        "pass_marker_present": "false",
        "semantic_trace_sha256": "",
        "artifact_id": "",
        "note": "SSH endpoint was unreachable; no Linux result is claimed.",
    })

    (root / POINTS_REL).write_bytes(csv_bytes(POINT_HEADER, points))
    (root / METRICS_REL).write_bytes(csv_bytes(METRIC_HEADER, generated_metrics(points)))
    (root / STALLS_REL).write_bytes(csv_bytes(STALL_HEADER, generated_stalls(points)))
    (root / MATRIX_REL).write_bytes(csv_bytes(MATRIX_HEADER, planned_matrix()))
    (root / LATENCY_REL).write_bytes(csv_bytes(LATENCY_HEADER, latencies))
    (root / VERIFICATION_REL).write_bytes(csv_bytes(VERIFICATION_HEADER, verification))
    (root / ARTIFACTS_REL).write_bytes(csv_bytes(ARTIFACT_HEADER, artifacts))

    sources = []
    for rel in SOURCE_PATHS:
        path = root / rel
        sources.append({"path": rel, "sha256": sha256_file(path),
                        "size_bytes": path.stat().st_size})
    manifest = {
        "schema_version": 1,
        "experiment_id": "slvc_dma_u5_async64_end_to_end_throughput",
        "classification": "BLOCKED_PROTOCOL_CONTRACT",
        "baseline_commit": BASELINE_COMMIT,
        "baseline_tag": "resume-2026-08-r3",
        "benchmark_branch": "perf/dma-u5-async64-throughput-sim",
        "claim_id": None,
        "promotion_eligible": False,
        "public_claim_eligible": False,
        "board_bridge_ready": False,
        "formal_matrix_completed": False,
        "production_rtl_changed": False,
        "profile": {
            "top": "frame_dma_rx_top",
            "rx_contexts": 16,
            "tx_contexts": 16,
            "rx_frontend_bits": 512,
            "rx_memory_bits": 64,
            "aclk_mhz": 100,
            "mem_clk_mhz": 100,
            "max_burst_beats": 16,
            "max_outstanding": 4,
            "seed": 71,
            "descriptor_workload_entries": 1024,
            "descriptor_ring_capacity_entries": 2048,
            "cq_entries": 4096,
        },
        "blockers": [
            {
                "id": "ASYNC64_SOURCE_PAYLOAD_WINDOW_CONTRACT",
                "status": "REPRODUCED_WINDOWS_MODELSIM",
                "condition": "s_cmd_fire=1 while s_payload_tvalid=1 and source_active_q=0",
                "effect": "source_payload_outside_frame sets sticky s_protocol_error",
            },
            {
                "id": "MULTI_FRAME_LOOPBACK_INCOMPLETE",
                "status": "INCONCLUSIVE_TEST_INFRASTRUCTURE_OR_RTL",
                "condition": "two-frame loopback did not reach all expected TX/RX CQEs",
                "effect": "formal loopback and 16-flow matrices were not started",
            },
        ],
        "boundaries": {
            "async64_interface_limit_bytes_per_cycle": "8",
            "async64_interface_limit_gb_per_s_at_100mhz": "0.8",
            "sameclock512_64_bytes_per_cycle_claim_reused": False,
            "hp0_model_is_board_measurement": False,
            "legacy_9p5_gbps_used_in_comparison": False,
        },
        "sources": sources,
        "files": {
            name: sha256_file(package / name)
            for name in ("points.csv", "metrics.csv", "stall_breakdown.csv",
                         "matrix.csv", "latency.csv",
                         "verification.csv", "artifacts.csv")
        },
        "formulas": {
            "bytes_per_cycle": "payload_bytes / cycles",
            "gb_per_s_at_100mhz": "bytes_per_cycle * 0.1",
            "gbits_per_s_at_100mhz": "bytes_per_cycle * 0.8",
            "frames_per_s_at_100mhz": "100000000 * frames / cycles",
        },
    }
    (root / MANIFEST_REL).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def validate(root):
    package = root / PACKAGE_REL
    manifest = json.loads((root / MANIFEST_REL).read_text(encoding="utf-8"))
    errors = []

    def require(condition, message):
        if not condition:
            errors.append(message)

    require(manifest.get("schema_version") == 1, "schema_version must be 1")
    require(manifest.get("classification") == "BLOCKED_PROTOCOL_CONTRACT",
            "classification must remain BLOCKED_PROTOCOL_CONTRACT")
    require(manifest.get("baseline_commit") == BASELINE_COMMIT,
            "baseline commit mismatch")
    require(manifest.get("claim_id") is None, "blocked experiment must not have claim_id")
    for field in ("promotion_eligible", "public_claim_eligible", "board_bridge_ready",
                  "formal_matrix_completed", "production_rtl_changed"):
        require(manifest.get(field) is False, "{} must be false".format(field))
    profile = manifest.get("profile", {})
    require(profile.get("top") == "frame_dma_rx_top", "top identity mismatch")
    require(profile.get("rx_contexts") == 16 and profile.get("tx_contexts") == 16,
            "context identity mismatch")
    require(profile.get("rx_frontend_bits") == 512 and profile.get("rx_memory_bits") == 64,
            "Async64 width identity mismatch")
    require(profile.get("aclk_mhz") == 100 and profile.get("mem_clk_mhz") == 100,
            "clock identity mismatch")
    require(profile.get("max_burst_beats") == 16 and
            profile.get("max_outstanding") == 4, "AXI bound mismatch")
    boundaries = manifest.get("boundaries", {})
    require(boundaries.get("async64_interface_limit_bytes_per_cycle") == "8",
            "Async64 limit must remain 8 B/cycle")
    require(boundaries.get("sameclock512_64_bytes_per_cycle_claim_reused") is False,
            "64 B/cycle claim must not be reused for Async64")
    require(boundaries.get("hp0_model_is_board_measurement") is False,
            "HP0 model must not be described as board measurement")

    blocker_ids = {item.get("id") for item in manifest.get("blockers", [])}
    require("ASYNC64_SOURCE_PAYLOAD_WINDOW_CONTRACT" in blocker_ids,
            "missing protocol-contract blocker")
    require("MULTI_FRAME_LOOPBACK_INCOMPLETE" in blocker_ids,
            "missing multi-frame blocker")

    sources = manifest.get("sources", [])
    require({item.get("path") for item in sources} == set(SOURCE_PATHS),
            "source manifest mismatch")
    for source in sources:
        path = root / source.get("path", "")
        require(path.is_file(), "missing source {}".format(source.get("path")))
        if path.is_file():
            require(source.get("sha256") == sha256_file(path),
                    "source hash mismatch: {}".format(source.get("path")))
            require(source.get("size_bytes") == path.stat().st_size,
                    "source size mismatch: {}".format(source.get("path")))

    points = read_csv(root / POINTS_REL, POINT_HEADER)
    metrics = read_csv(root / METRICS_REL, METRIC_HEADER)
    stalls = read_csv(root / STALLS_REL, STALL_HEADER)
    matrix = read_csv(root / MATRIX_REL, MATRIX_HEADER)
    latencies = read_csv(root / LATENCY_REL, LATENCY_HEADER)
    verification = read_csv(root / VERIFICATION_REL, VERIFICATION_HEADER)
    artifacts = read_csv(root / ARTIFACTS_REL, ARTIFACT_HEADER)
    require(len(points) == 2, "exactly two completed blocked smoke points required")
    require((root / METRICS_REL).read_bytes() ==
            csv_bytes(METRIC_HEADER, generated_metrics(points)),
            "metrics.csv is not the Decimal regeneration of points.csv")
    require((root / STALLS_REL).read_bytes() ==
            csv_bytes(STALL_HEADER, generated_stalls(points)),
            "stall_breakdown.csv is not regenerated from points.csv")
    require((root / MATRIX_REL).read_bytes() ==
            csv_bytes(MATRIX_HEADER, planned_matrix()),
            "matrix.csv does not match the fixed workload contract")
    require(len(matrix) == 28, "unexpected formal matrix size")
    for row in matrix:
        require(row["status"] == "NOT_RUN_PREREQUISITE",
                "formal matrix point cannot be promoted")
        require(row["blocked_by"] == "ASYNC64_SOURCE_PAYLOAD_WINDOW_CONTRACT",
                "formal matrix blocker mismatch")
    for point in points:
        require(point["status"] == "BLOCKED_PROTOCOL_CONTRACT",
                "completed smoke point must remain blocked")
        require(point["pass_marker"] == "false", "blocked point cannot have PASS marker")
        require(int(point["protocol_error"]) > 0,
                "blocked point must retain protocol_error")
        require(int(point["frame_fail"]) == 0 and int(point["frame_drop"]) == 0,
                "payload smoke unexpectedly reported frame failure/drop")
        require(int(point["rx_peak_outstanding"]) == 4,
                "completed smoke did not observe four RX outstanding")
    for row in metrics:
        require(row["claim_eligible"] == "false", "smoke metric cannot be claim eligible")
    require(len(latencies) == 8, "unexpected latency sample count")
    require(len(verification) == 5, "unexpected verification row count")
    for row in verification[:4]:
        require(row["marker_present"] == "true", "required failure marker missing")
        require(row["pass_marker_present"] == "false", "failure log contains PASS marker")
        require(HEX64.match(row["semantic_trace_sha256"]) is not None,
                "invalid semantic trace hash")
    require(verification[-1]["status"] == "NOT_RUN_ENVIRONMENT_UNREACHABLE",
            "Linux endpoint status must remain explicit")
    require(verification[-1]["pass_marker_present"] == "false",
            "Linux NOT_RUN row cannot claim PASS")
    artifact_ids = {row["artifact_id"] for row in artifacts}
    require(len(artifacts) == 4 and len(artifact_ids) == 4,
            "artifact inventory mismatch")
    for row in artifacts:
        require(HEX64.match(row["sha256"]) is not None, "invalid artifact hash")
        require(int(row["size_bytes"]) > 0, "invalid artifact size")
        require(row["published"] == "false", "raw simulator log cannot be published")

    for name, expected_hash in manifest.get("files", {}).items():
        path = package / name
        require(path.is_file(), "manifest-listed file missing: {}".format(name))
        if path.is_file():
            require(expected_hash == sha256_file(path), "package hash mismatch: {}".format(name))

    scan_paths = [root / MANIFEST_REL, root / POINTS_REL, root / METRICS_REL,
                  root / STALLS_REL, root / MATRIX_REL,
                  root / LATENCY_REL, root / VERIFICATION_REL, root / ARTIFACTS_REL,
                  root / "docs/throughput_private/async64_end_to_end_throughput.md"]
    scan_text = "\n".join(path.read_text(encoding="utf-8") for path in scan_paths
                            if path.is_file())
    for pattern in PRIVATE_PATTERNS:
        require(pattern.search(scan_text) is None,
                "sensitive/private token matched: {}".format(pattern.pattern))
    require("9.5 Gbps" not in scan_text and "9.5Gbps" not in scan_text,
            "legacy throughput must not enter comparison")
    require("Async64 64 B/cycle" not in scan_text,
            "Async64 must not inherit the 64 B/cycle claim")

    try:
        changed = subprocess.check_output(
            ["git", "-c", "safe.directory={}".format(root.as_posix()),
             "-c", "core.excludesfile=NUL",
             "diff", "--name-only", BASELINE_COMMIT, "--", "rtl", "configs",
             "filelists", "constraints", "Kconfig"],
            cwd=str(root), universal_newlines=True, stderr=subprocess.DEVNULL)
        protected = [line for line in changed.splitlines()
                     if line and line != "pattern/dma_sim_def.vh"]
        require(not protected, "protected production paths changed: {}".format(protected))
    except (OSError, subprocess.CalledProcessError) as exc:
        errors.append("unable to audit protected paths: {}".format(exc))

    if errors:
        raise ValidationError("\n".join(errors))
    return {
        "points": len(points),
        "metrics": len(metrics),
        "stalls": len(stalls),
        "matrix": len(matrix),
        "latencies": len(latencies),
        "verification": len(verification),
        "artifacts": len(artifacts),
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--collect-smoke-dir")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    try:
        if args.collect_smoke_dir:
            collect(root, Path(args.collect_smoke_dir).resolve())
        result = validate(root)
    except (ValidationError, ValueError, KeyError, InvalidOperation, json.JSONDecodeError) as exc:
        print("DMA Async64 throughput evidence: FAIL")
        print(exc)
        return 1
    print("DMA Async64 throughput evidence: PASS")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
