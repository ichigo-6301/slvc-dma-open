#!/usr/bin/env python3
"""Collect and fail-closed validate repaired private Async64 throughput data."""

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
from pathlib import Path, PurePosixPath

try:
    from flows.scripts.dma_async64_throughput_contract import (
        CLOCK_MHZ, MAIN_POINT_ID, correctness_ladder_points, matrix_points,
        expected_payload_bytes, payload_model_limit)
except ImportError:
    from dma_async64_throughput_contract import (
        CLOCK_MHZ, MAIN_POINT_ID, correctness_ladder_points, matrix_points,
        expected_payload_bytes, payload_model_limit)


BASELINE_COMMIT = "c20681fad0eaa6ad55dbb919149765b175b29117"
BLOCKED_COMMIT = "e6a6696603b10c4475fca468e9c40c727197ac9c"
RTL_FIX_COMMIT = "ad1ea4a927425773d772f6438c06c332e0b87830"
PACKAGE_REL = Path("evidence/throughput_private/async64_end_to_end_repaired")
MANIFEST_REL = PACKAGE_REL / "manifest.json"
POINTS_REL = PACKAGE_REL / "points.csv"
METRICS_REL = PACKAGE_REL / "metrics.csv"
STALLS_REL = PACKAGE_REL / "stall_breakdown.csv"
MATRIX_REL = PACKAGE_REL / "matrix.csv"
LADDER_REL = PACKAGE_REL / "correctness_ladder.csv"
LATENCY_REL = PACKAGE_REL / "latency_summary.csv"
FAIRNESS_REL = PACKAGE_REL / "flow_fairness.csv"
VERIFICATION_REL = PACKAGE_REL / "verification.csv"
ARTIFACTS_REL = PACKAGE_REL / "artifacts.csv"
IDENTITY_REL = PACKAGE_REL / "c2b4_physical_identity.json"
README_REL = PACKAGE_REL / "README.md"
DOC_REL = Path("docs/throughput_private/async64_end_to_end_throughput_repaired.md")

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_SIMULATORS = {
    "windows": (
        "Model Technology ModelSim SE-64 vsim 2020.4 "
        "Simulator 2020.10 Oct 13 2020"
    ),
    "linux": "Questa Sim-64 vsim 10.7c Simulator 2018.08 Aug 17 2018",
}
KEY_VALUE = re.compile(r"([A-Za-z0-9_]+)=([^\s]+)")
PRIVATE_PATTERNS = (
    re.compile(r"[A-Za-z]:[\\/]"),
    re.compile(r"/(?:home|Users|tmp)/[A-Za-z0-9_.-]+/"),
    re.compile(r"(?:LM_LICENSE_FILE|SNPSLMD_LICENSE_FILE|MGLS_LICENSE_FILE)", re.I),
    re.compile(r"(?:license[_-]?server|private[_-]?remote|hostname)", re.I),
)

POINT_HEADER = (
    "point_key", "point_id", "platform", "simulator", "scenario", "frames",
    "payload_bytes", "shared_service", "response_latency_cycles",
    "service_percent", "mem_phase_ns", "clock_mhz", "hw_cycles",
    "steady_cycles", "rx_axis_valid", "rx_axis_ready", "rx_axis_fire",
    "tx_axis_valid", "tx_axis_ready", "tx_axis_fire", "main_read_bytes",
    "rx_payload_write_bytes", "cq_bus_write_bytes", "main_ar_bursts",
    "main_aw_bursts", "rx_aw_bursts", "rx_peak_outstanding",
    "tx_peak_outstanding", "rx_input_stall", "cdc_payload_stall",
    "aw_stall", "w_stall", "b_stall", "ar_stall", "r_stall",
    "rx_cqe", "tx_cqe", "frame_fail", "frame_drop", "deadlock",
    "protocol_error", "payload_crc", "latency_count", "status", "pass_marker",
)
METRIC_HEADER = (
    "point_key", "point_id", "platform", "window", "payload_bytes", "cycles",
    "mbps_per_mhz", "mb_per_s_at_100mhz", "gbits_per_s_at_100mhz",
    "model_limit_mbps_per_mhz", "efficiency_percent",
    "frames_per_s_at_100mhz", "resume_eligible",
)
STALL_HEADER = (
    "point_key", "point_id", "platform", "rx_input_stall",
    "cdc_payload_stall", "aw_stall", "w_stall", "b_stall", "ar_stall",
    "r_stall",
)
MATRIX_HEADER = (
    "point_id", "scenario", "frames", "payload_arg_bytes", "model",
    "response_latency_cycles", "service_percent", "mem_phase_ns",
    "windows_status", "linux_status", "semantic_trace_sha256", "status",
)
LADDER_HEADER = (
    "point_id", "frames", "payload_bytes_per_frame", "model",
    "response_latency_cycles", "service_percent", "mem_phase_ns",
    "windows_status", "linux_status", "semantic_trace_sha256", "status",
)
LATENCY_HEADER = (
    "point_key", "point_id", "platform", "samples", "min_cycles",
    "p50_cycles", "p95_cycles", "p99_cycles", "max_cycles",
)
FAIRNESS_HEADER = (
    "point_key", "point_id", "platform", "channel", "completions",
    "min_gap_cycles", "max_gap_cycles",
)
VERIFICATION_HEADER = (
    "verification_id", "point_id", "platform", "simulator", "status",
    "pass_marker_count", "point_marker_count", "semantic_trace_sha256",
    "artifact_id",
)
ARTIFACT_HEADER = (
    "artifact_id", "logical_name", "sha256", "size_bytes", "published",
)

RAW_POINT_FIELDS = (
    "frames", "payload_bytes", "shared", "response_latency",
    "service_percent", "mem_phase_ns", "hw_cycles", "steady_cycles",
    "rx_axis_valid", "rx_axis_ready", "rx_axis_fire", "tx_axis_valid",
    "tx_axis_ready", "tx_axis_fire", "main_read_bytes",
    "rx_payload_write_bytes", "cq_bus_write_bytes", "main_ar_bursts",
    "main_aw_bursts", "rx_aw_bursts", "rx_peak_outstanding",
    "tx_peak_outstanding", "rx_input_stall", "cdc_payload_stall",
    "aw_stall", "w_stall", "b_stall", "ar_stall", "r_stall", "rx_cqe",
    "tx_cqe", "frame_fail", "frame_drop", "deadlock", "protocol_error",
    "payload_crc", "latency_count",
)

SOURCE_PATHS = (
    "rtl/integration/frame_dma_rx_top.v",
    "rtl/rx/dma_rx_payload_cdc_bridge.v",
    "rtl/tx/dma_axi_read_prefetch.v",
    "filelists/dma_rtl.f",
    "pattern/dma_sim_def.vh",
    "pattern/axi_hp0_dual_master_64_model.v",
    "pattern/tb_rtl_dma_async64_end_to_end_throughput.v",
    "pattern/tb_rtl_rx_payload_cdc_bridge.v",
    "pattern/tb_rtl_dma_axi_read_prefetch.v",
    "modelsim/run_rtl_dma_async64_end_to_end_throughput.do",
    "modelsim/run_rtl_rx_payload_cdc_bridge.do",
    "modelsim/run_rtl_dma_axi_read_prefetch.do",
    "flows/scripts/dma_async64_throughput_contract.py",
    "flows/scripts/run_dma_async64_throughput_matrix.py",
    "flows/scripts/validate_dma_async64_throughput_repaired.py",
    "flows/scripts/test_validate_dma_async64_throughput_repaired.py",
)


class ValidationError(Exception):
    pass


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    return sha256_bytes(path.read_bytes())


def write_utf8_lf(path, text):
    path.write_bytes(text.encode("utf-8"))


def parse_marker(line, marker):
    if marker not in line:
        return None
    return dict(KEY_VALUE.findall(line.split(marker, 1)[1]))


def csv_bytes(header, rows):
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=header, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue().encode("utf-8")


def read_csv(path, header):
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != header:
            raise ValidationError("unexpected CSV header in {}".format(path))
        return list(reader)


def decimal_text(value):
    return format(value.quantize(Decimal("0.000001"),
                                 rounding=ROUND_HALF_EVEN), "f")


def git_output(root, args):
    return subprocess.check_output(
        ["git", "-c", "safe.directory={}".format(root.as_posix()),
         "-c", "core.excludesfile=NUL"] + args,
        cwd=str(root), stderr=subprocess.DEVNULL)


def has_git_repo(root):
    try:
        return git_output(root, ["rev-parse", "--is-inside-work-tree"]).strip() == b"true"
    except (OSError, subprocess.CalledProcessError):
        return False


def git_blob(root, commit, rel):
    return git_output(root, ["show", "{}:{}".format(commit, rel)])


def source_bytes(root, commit, rel):
    if has_git_repo(root):
        return git_blob(root, commit, rel)
    return (root / rel).read_bytes().replace(b"\r\n", b"\n")


def generated_metrics(points, contract_by_id):
    rows = []
    clock_hz = Decimal(str(CLOCK_MHZ * 1000000))
    for point in points:
        payload = Decimal(point["payload_bytes"])
        frames = Decimal(point["frames"])
        limit = Decimal(str(payload_model_limit(contract_by_id[point["point_id"]])))
        for window, cycle_field in (("hardware_end_to_end", "hw_cycles"),
                                    ("datapath_steady_state", "steady_cycles")):
            cycles = Decimal(point[cycle_field])
            score = payload / cycles
            rows.append({
                "point_key": point["point_key"],
                "point_id": point["point_id"],
                "platform": point["platform"],
                "window": window,
                "payload_bytes": point["payload_bytes"],
                "cycles": point[cycle_field],
                "mbps_per_mhz": decimal_text(score),
                "mb_per_s_at_100mhz": decimal_text(score * Decimal("100")),
                "gbits_per_s_at_100mhz": decimal_text(score * Decimal("0.8")),
                "model_limit_mbps_per_mhz": decimal_text(limit),
                "efficiency_percent": decimal_text(score * Decimal("100") / limit),
                "frames_per_s_at_100mhz":
                    decimal_text(clock_hz * frames / cycles),
                "resume_eligible": "false",
            })
    return rows


def generated_stalls(points):
    return [{field: point[field] for field in STALL_HEADER} for point in points]


def percentile(sorted_values, percent):
    index = ((percent * len(sorted_values) + 99) // 100) - 1
    return sorted_values[max(0, index)]


def normalized_trace(lines, point_row, flow_rows):
    selected = []
    for line in lines:
        if "DMA_TP_TRACE" in line:
            selected.append("TRACE " + line.split("DMA_TP_TRACE", 1)[1].strip())
    point_fields = (
        "scenario", "frames", "payload_bytes", "rx_axis_fire", "tx_axis_fire",
        "main_read_bytes", "rx_payload_write_bytes", "cq_bus_write_bytes",
        "rx_peak_outstanding", "tx_peak_outstanding", "rx_cqe", "tx_cqe",
        "frame_fail", "frame_drop", "deadlock", "protocol_error", "payload_crc",
    )
    selected.append("POINT " + " ".join(
        "{}={}".format(field, point_row[field]) for field in point_fields))
    for row in flow_rows:
        selected.append("FLOW channel={} completions={} min_gap_cycles={} max_gap_cycles={}".format(
            row["channel"], row["completions"], row["min_gap_cycles"],
            row["max_gap_cycles"]))
    return ("\n".join(selected) + "\n").encode("utf-8")


def load_run_index(run_dir, platform, flow_commit, contracts, suite):
    path = run_dir / "run_index.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if (data.get("schema_version") != 1 or data.get("platform") != platform or
            data.get("suite") != suite):
        raise ValidationError("run index identity mismatch: {}".format(path))
    if data.get("source_commit") != flow_commit or data.get("seed") != 71:
        raise ValidationError("run index source/seed mismatch: {}".format(path))
    expected_simulator = EXPECTED_SIMULATORS[platform]
    if data.get("simulator") != expected_simulator:
        raise ValidationError(
            "run index simulator mismatch for {}: {}".format(platform, path)
        )
    records = data.get("records", [])
    expected_ids = [point["point_id"] for point in contracts]
    if [record.get("point_id") for record in records] != expected_ids:
        raise ValidationError("run index matrix order mismatch: {}".format(path))
    if any(record.get("status") != "PASS" for record in records):
        raise ValidationError("run index contains a non-PASS point: {}".format(path))
    contract_fields = (
        "scenario", "frames", "payload_arg_bytes", "model",
        "shared_service", "response_latency_cycles", "service_percent",
        "mem_phase_ns",
    )
    for contract, record in zip(contracts, records):
        point_id = contract["point_id"]
        for field in contract_fields:
            if record.get(field) != contract[field]:
                raise ValidationError(
                    "run index {} mismatch for {}: {}".format(
                        field, point_id, path
                    )
                )
        if (record.get("platform") != platform or
                record.get("simulator") != expected_simulator or
                record.get("source_commit") != flow_commit or
                record.get("returncode") != 0 or
                record.get("log_file") != point_id + ".log"):
            raise ValidationError(
                "run index execution identity mismatch for {}: {}".format(
                    point_id, path
                )
            )
    return data, {record["point_id"]: record for record in records}


def collect_platform(run_dir, platform, flow_commit, contract_by_id,
                     contracts, suite):
    index, records = load_run_index(run_dir, platform, flow_commit,
                                    contracts, suite)
    points = []
    latencies = []
    fairness = []
    verification = []
    artifacts = []
    for contract in contracts:
        point_id = contract["point_id"]
        record = records[point_id]
        path = run_dir / record["log_file"]
        raw = path.read_bytes()
        if sha256_bytes(raw) != record["log_sha256"] or len(raw) != record["log_size_bytes"]:
            raise ValidationError("run-index artifact mismatch: {}".format(point_id))
        text = raw.decode("utf-8", errors="replace")
        lines = text.splitlines()
        point_markers = [parse_marker(line, "DMA_TP_POINT") for line in lines
                         if "DMA_TP_POINT" in line]
        if len(point_markers) != 1 or text.count(
                "DMA_ASYNC64_END_TO_END_THROUGHPUT_PASS") != 1:
            raise ValidationError("missing/duplicate PASS point marker: {}".format(point_id))
        raw_point = point_markers[0]
        if raw_point.get("case") != contract["scenario"]:
            raise ValidationError("scenario mismatch: {}".format(point_id))
        missing = [field for field in RAW_POINT_FIELDS if field not in raw_point]
        if missing:
            raise ValidationError("point {} missing fields {}".format(point_id, missing))
        if (raw_point["frames"] != str(contract["frames"]) or
                raw_point["payload_bytes"] !=
                str(expected_payload_bytes(contract)) or
                raw_point["shared"] != str(contract["shared_service"]) or
                raw_point["response_latency"] !=
                str(contract["response_latency_cycles"]) or
                raw_point["service_percent"] != str(contract["service_percent"]) or
                raw_point["mem_phase_ns"] != str(contract["mem_phase_ns"])):
            raise ValidationError("point contract mismatch: {}".format(point_id))
        point_key = "{}:{}".format(platform, point_id)
        point = {
            "point_key": point_key,
            "point_id": point_id,
            "platform": platform,
            "simulator": index["simulator"],
            "scenario": raw_point["case"],
            "frames": raw_point["frames"],
            "payload_bytes": raw_point["payload_bytes"],
            "shared_service": raw_point["shared"],
            "response_latency_cycles": raw_point["response_latency"],
            "service_percent": raw_point["service_percent"],
            "mem_phase_ns": raw_point["mem_phase_ns"],
            "clock_mhz": str(CLOCK_MHZ),
            "status": "PASS",
            "pass_marker": "true",
        }
        for field in POINT_HEADER:
            if field not in point and field in raw_point:
                point[field] = raw_point[field]

        latency_values = [int(parsed["cycles"])
                          for parsed in (parse_marker(line, "DMA_TP_LATENCY")
                                         for line in lines
                                         if "DMA_TP_LATENCY" in line)]
        if len(latency_values) != int(point["frames"]):
            raise ValidationError("latency sample count mismatch: {}".format(point_id))
        latency_values.sort()
        latencies.append({
            "point_key": point_key,
            "point_id": point_id,
            "platform": platform,
            "samples": str(len(latency_values)),
            "min_cycles": str(latency_values[0]),
            "p50_cycles": str(percentile(latency_values, 50)),
            "p95_cycles": str(percentile(latency_values, 95)),
            "p99_cycles": str(percentile(latency_values, 99)),
            "max_cycles": str(latency_values[-1]),
        })
        point_flows = []
        for line in lines:
            parsed = parse_marker(line, "DMA_TP_FLOW")
            if parsed:
                row = {
                    "point_key": point_key,
                    "point_id": point_id,
                    "platform": platform,
                    "channel": parsed["ch"],
                    "completions": parsed["completions"],
                    "min_gap_cycles": parsed["min_gap"],
                    "max_gap_cycles": parsed["max_gap"],
                }
                point_flows.append(row)
                fairness.append(row)
        if (point_id == "mixed16" and len(point_flows) != 16) or (
                point_id != "mixed16" and point_flows):
            raise ValidationError("flow fairness marker mismatch: {}".format(point_id))

        trace_sha = sha256_bytes(normalized_trace(lines, point, point_flows))
        artifact_id = "{}_{}".format(platform, point_id)
        artifacts.append({
            "artifact_id": artifact_id,
            "logical_name": "private_sim/{}/{}.log".format(platform, point_id),
            "sha256": sha256_bytes(raw),
            "size_bytes": str(len(raw)),
            "published": "false",
        })
        verification.append({
            "verification_id": artifact_id,
            "point_id": point_id,
            "platform": platform,
            "simulator": index["simulator"],
            "status": "PASS",
            "pass_marker_count": "1",
            "point_marker_count": "1",
            "semantic_trace_sha256": trace_sha,
            "artifact_id": artifact_id,
        })
        points.append(point)
    return points, latencies, fairness, verification, artifacts


def c2b4_source_members(root, revision):
    filelist = git_blob(
        root, revision, "flows/asic/c2b4/c2b4_register.f"
    ).decode()
    members = []
    for line in filelist.splitlines():
        rel = line.strip()
        if not rel or rel.startswith("#"):
            continue
        path = PurePosixPath(rel)
        if (path.is_absolute() or ".." in path.parts or
                rel.startswith(("+", "-"))):
            raise ValidationError(
                "unsupported C2B4 filelist member: {}".format(rel)
            )
        members.append(path.as_posix())
    if not members or len(members) != len(set(members)):
        raise ValidationError("C2B4 filelist is empty or contains duplicates")
    return members


def c2b4_identity(root, flow_commit):
    members = c2b4_source_members(root, flow_commit)
    paths = git_output(root, ["ls-tree", "-r", "--name-only", BASELINE_COMMIT,
                              "--", "flows/asic/c2b4"]).decode().splitlines()
    paths += members
    paths += ["configs/dma_rx512_reg_c2_b4_m2_sp64_defconfig", "Kconfig"]
    records = []
    for rel in sorted(set(paths)):
        baseline = git_blob(root, BASELINE_COMMIT, rel)
        repaired = git_blob(root, flow_commit, rel)
        if baseline != repaired:
            raise ValidationError("C2B4 identity changed: {}".format(rel))
        records.append({
            "path": rel,
            "baseline_sha256": sha256_bytes(baseline),
            "repaired_sha256": sha256_bytes(repaired),
            "identical": True,
        })
    forbidden = {"rtl/rx/dma_rx_payload_cdc_bridge.v",
                 "rtl/tx/dma_axi_read_prefetch.v"}
    if forbidden.intersection(members):
        raise ValidationError("fixed full-profile module entered C2B4 filelist")
    return {
        "schema_version": 1,
        "baseline_commit": BASELINE_COMMIT,
        "flow_as_run_commit": flow_commit,
        "c2b4_filelist": "flows/asic/c2b4/c2b4_register.f",
        "c2b4_source_members": members,
        "excluded_fixed_modules": sorted(forbidden),
        "files": records,
        "identity_equal": True,
        "physical_rerun_required": False,
    }


def generated_matrix(verification):
    by_key = {(row["platform"], row["point_id"]): row for row in verification}
    rows = []
    for point in matrix_points():
        win = by_key[("windows", point["point_id"])]
        linux = by_key[("linux", point["point_id"])]
        trace = win["semantic_trace_sha256"]
        rows.append({
            "point_id": point["point_id"],
            "scenario": point["scenario"],
            "frames": str(point["frames"]),
            "payload_arg_bytes": str(point["payload_arg_bytes"]),
            "model": point["model"],
            "response_latency_cycles": str(point["response_latency_cycles"]),
            "service_percent": str(point["service_percent"]),
            "mem_phase_ns": str(point["mem_phase_ns"]),
            "windows_status": win["status"],
            "linux_status": linux["status"],
            "semantic_trace_sha256": trace,
            "status": "PASS_DUAL_PLATFORM" if (
                win["status"] == "PASS" and linux["status"] == "PASS" and
                trace == linux["semantic_trace_sha256"]) else "FAIL",
        })
    return rows


def generated_ladder(verification, points):
    by_verification = {
        (row["platform"], row["point_id"]): row for row in verification}
    by_point = {(row["platform"], row["point_id"]): row for row in points}
    rows = []
    for point in correctness_ladder_points():
        point_id = point["point_id"]
        win = by_verification[("windows", point_id)]
        linux = by_verification[("linux", point_id)]
        trace = win["semantic_trace_sha256"]
        payload = by_point[("windows", point_id)]["payload_bytes"]
        rows.append({
            "point_id": point_id,
            "frames": str(point["frames"]),
            "payload_bytes_per_frame": str(point["payload_arg_bytes"]),
            "model": point["model"],
            "response_latency_cycles": str(point["response_latency_cycles"]),
            "service_percent": str(point["service_percent"]),
            "mem_phase_ns": str(point["mem_phase_ns"]),
            "windows_status": win["status"],
            "linux_status": linux["status"],
            "semantic_trace_sha256": trace,
            "status": "PASS_DUAL_PLATFORM" if (
                win["status"] == "PASS" and linux["status"] == "PASS" and
                trace == linux["semantic_trace_sha256"] and
                payload == str(point["frames"] * point["payload_arg_bytes"]))
                else "FAIL",
        })
    return rows


def render_docs(root, main_metrics):
    hw = main_metrics["hardware_end_to_end"]
    steady = main_metrics["datapath_steady_state"]
    text = """# Async64 End-to-End Throughput (Repaired Private Simulation)\n\n"""
    text += "Status: `VERIFIED_PRIVATE_SIMULATION`. This package is not a public or resume claim.\n\n"
    text += "The fixed main point is 1024 x 4 KiB full TX-to-RX loopback, HP0_SHARED, "
    text += "16-cycle response latency, 100% service, 3 ns CDC phase, seed 71.\n\n"
    text += "The 1/2/5/32/1024-frame correctness ladder passed on both simulators "
    text += "before the 28-point matrix was accepted.\n\n"
    text += "| Window | MB/s/MHz | MB/s at 100 MHz | Gb/s at 100 MHz | Model efficiency |\n"
    text += "| --- | ---: | ---: | ---: | ---: |\n"
    for label, row in (("Hardware end-to-end", hw), ("Datapath steady-state", steady)):
        text += "| {} | {} | {} | {} | {}% |\n".format(
            label, row["mbps_per_mhz"], row["mb_per_s_at_100mhz"],
            row["gbits_per_s_at_100mhz"], row["efficiency_percent"])
    text += "\nThe HP0_SHARED payload-only loopback ceiling is 4 MB/s/MHz; "
    text += "IDEAL_SPLIT is 8 MB/s/MHz. These are RTL model limits, not board DDR throughput.\n\n"
    text += "The existing 64 B/cycle result remains a Same-clock512/Async512 ready-memory "
    text += "Writer-interface result and is not reused here. C2B4 physical sources are byte-identical "
    text += "to the fixed 550/450 MHz evidence chain; no DC, P&R, OpenRCX, or PrimeTime rerun was performed.\n"
    (root / README_REL).parent.mkdir(parents=True, exist_ok=True)
    write_utf8_lf(root / README_REL, text)
    doc = """# Async64 自回环修复与每 MHz 吞吐评估\n\n"""
    doc += "状态：`VERIFIED_PRIVATE_SIMULATION`，不构成公开 Claim 或简历板测结论。\n\n"
    doc += text.split("\n", 2)[2]
    doc += "\n## 修复边界\n\n"
    doc += "修复仅涉及 CDC 合法窗口检查与 TX 读预取 FIFO occupancy；接口、容量、流水和 4 KiB 合同不变。"
    doc += "C2B4 source set不包含这两个模块，既有物理证据未重跑也未改写。\n"
    (root / DOC_REL).parent.mkdir(parents=True, exist_ok=True)
    write_utf8_lf(root / DOC_REL, doc)


def collect(root, windows_dir, linux_dir, windows_ladder_dir,
            linux_ladder_dir, flow_commit):
    if not HEX40.match(flow_commit):
        raise ValidationError("flow-as-run commit must be a full SHA")
    matrix_contracts = matrix_points()
    ladder_contracts = correctness_ladder_points()
    all_contracts = matrix_contracts + ladder_contracts
    contract_by_id = {point["point_id"]: point for point in all_contracts}
    collected = []
    latencies = []
    fairness = []
    verification = []
    artifacts = []
    for platform, run_dir in (("windows", windows_dir), ("linux", linux_dir)):
        result = collect_platform(run_dir, platform, flow_commit, contract_by_id,
                                  matrix_contracts, "matrix")
        collected.extend(result[0])
        latencies.extend(result[1])
        fairness.extend(result[2])
        verification.extend(result[3])
        artifacts.extend(result[4])
    for platform, run_dir in (("windows", windows_ladder_dir),
                              ("linux", linux_ladder_dir)):
        result = collect_platform(run_dir, platform, flow_commit, contract_by_id,
                                  ladder_contracts, "ladder")
        collected.extend(result[0])
        latencies.extend(result[1])
        fairness.extend(result[2])
        verification.extend(result[3])
        artifacts.extend(result[4])
    metrics = generated_metrics(collected, contract_by_id)
    stalls = generated_stalls(collected)
    matrix = generated_matrix(verification)
    ladder = generated_ladder(verification, collected)
    if any(row["status"] != "PASS_DUAL_PLATFORM" for row in matrix):
        raise ValidationError("Windows/Linux semantic traces differ")
    if any(row["status"] != "PASS_DUAL_PLATFORM" for row in ladder):
        raise ValidationError("Windows/Linux correctness ladder differs")
    main_metrics = {
        row["window"]: row for row in metrics
        if row["platform"] == "windows" and row["point_id"] == MAIN_POINT_ID
    }
    render_docs(root, main_metrics)
    package = root / PACKAGE_REL
    package.mkdir(parents=True, exist_ok=True)
    outputs = (
        (POINTS_REL, POINT_HEADER, collected),
        (METRICS_REL, METRIC_HEADER, metrics),
        (STALLS_REL, STALL_HEADER, stalls),
        (MATRIX_REL, MATRIX_HEADER, matrix),
        (LADDER_REL, LADDER_HEADER, ladder),
        (LATENCY_REL, LATENCY_HEADER, latencies),
        (FAIRNESS_REL, FAIRNESS_HEADER, fairness),
        (VERIFICATION_REL, VERIFICATION_HEADER, verification),
        (ARTIFACTS_REL, ARTIFACT_HEADER, artifacts),
    )
    for rel, header, rows in outputs:
        (root / rel).write_bytes(csv_bytes(header, rows))
    identity = c2b4_identity(root, flow_commit)
    write_utf8_lf(root / IDENTITY_REL,
                  json.dumps(identity, indent=2, sort_keys=True) + "\n")
    sources = []
    for rel in SOURCE_PATHS:
        blob = source_bytes(root, flow_commit, rel)
        sources.append({"path": rel, "sha256": sha256_bytes(blob),
                        "size_bytes": len(blob)})
    package_files = [rel for rel, _, _ in outputs] + [IDENTITY_REL, README_REL]
    manifest = {
        "schema_version": 2,
        "experiment_id": "slvc_dma_u5_async64_end_to_end_throughput_repaired",
        "classification": "VERIFIED_PRIVATE_SIMULATION",
        "baseline_commit": BASELINE_COMMIT,
        "blocked_evidence_commit": BLOCKED_COMMIT,
        "rtl_fix_commit": RTL_FIX_COMMIT,
        "flow_as_run_commit": flow_commit,
        "claim_id": None,
        "public_claim_eligible": False,
        "resume_eligible": False,
        "board_bridge_ready": True,
        "formal_matrix_completed": True,
        "correctness_ladder_completed": True,
        "dual_platform_complete": True,
        "full_profile_rtl_repaired": True,
        "c2b4_physical_source_changed": False,
        "c2b4_physical_rerun_performed": False,
        "profile": {
            "top": "frame_dma_rx_top", "rx_contexts": 16,
            "tx_contexts": 16, "rx_frontend_bits": 512,
            "rx_memory_bits": 64, "aclk_mhz": 100, "mem_clk_mhz": 100,
            "max_burst_beats": 16, "max_outstanding": 4, "seed": 71,
            "descriptor_workload_entries": 1024,
            "descriptor_ring_capacity_entries": 2048, "cq_entries": 4096,
        },
        "main_point": {
            "point_id": MAIN_POINT_ID,
            "workload": "1024 x 4096-byte full TX-to-RX loopback",
            "model": "HP0_SHARED", "response_latency_cycles": 16,
            "service_percent": 100, "mem_phase_ns": 3,
            "e2e_mbps_per_mhz": main_metrics["hardware_end_to_end"]["mbps_per_mhz"],
            "steady_mbps_per_mhz": main_metrics["datapath_steady_state"]["mbps_per_mhz"],
            "payload_only_model_limit_mbps_per_mhz": "4.000000",
        },
        "boundaries": {
            "hp0_shared_is_board_measurement": False,
            "score_is_fmax": False,
            "sameclock512_64_bytes_per_cycle_claim_reused": False,
            "legacy_9p5_gbps_used_in_comparison": False,
            "public_claim_updated": False,
        },
        "formulas": {
            "e2e_mbps_per_mhz": "payload_bytes / hardware_end_to_end_cycles",
            "steady_mbps_per_mhz": "payload_bytes / datapath_steady_state_cycles",
            "mb_per_s_at_100mhz": "mbps_per_mhz * 100",
            "gbits_per_s_at_100mhz": "mbps_per_mhz * 100 * 0.008",
            "efficiency_percent": "100 * mbps_per_mhz / model_limit_mbps_per_mhz",
        },
        "sources": sources,
        "files": {rel.relative_to(PACKAGE_REL).as_posix(): sha256_file(root / rel)
                  for rel in package_files},
        "document_sha256": sha256_file(root / DOC_REL),
    }
    write_utf8_lf(root / MANIFEST_REL,
                  json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def validate_git_identity(root, manifest, require):
    if not has_git_repo(root):
        return
    flow_commit = manifest["flow_as_run_commit"]
    rtl_diff = git_output(root, ["diff", "--name-only", BLOCKED_COMMIT,
                                  flow_commit, "--", "rtl"]).decode().splitlines()
    require(set(rtl_diff) == {
        "rtl/rx/dma_rx_payload_cdc_bridge.v",
        "rtl/tx/dma_axi_read_prefetch.v",
    }, "RTL repair whitelist mismatch: {}".format(rtl_diff))
    protected_paths = [
        "flows/asic/c2b4", "configs/dma_rx512_reg_c2_b4_m2_sp64_defconfig",
        "Kconfig", "evidence/asic_paired_dc", "provenance/claims.yaml",
        "provenance/evidence.yaml", "provenance/nonclaims.yaml",
    ] + c2b4_source_members(root, flow_commit)
    protected = git_output(root, [
        "diff", "--name-only", BASELINE_COMMIT, flow_commit, "--",
    ] + protected_paths).decode().splitlines()
    require(not protected, "C2B4/ASIC evidence identity changed: {}".format(protected))


def validate(root):
    manifest = json.loads((root / MANIFEST_REL).read_text(encoding="utf-8"))
    errors = []

    def require(condition, message):
        if not condition:
            errors.append(message)

    require(manifest.get("schema_version") == 2, "schema_version must be 2")
    require(manifest.get("classification") == "VERIFIED_PRIVATE_SIMULATION",
            "classification mismatch")
    require(manifest.get("baseline_commit") == BASELINE_COMMIT,
            "baseline commit mismatch")
    require(manifest.get("blocked_evidence_commit") == BLOCKED_COMMIT,
            "blocked evidence identity mismatch")
    require(manifest.get("rtl_fix_commit") == RTL_FIX_COMMIT,
            "RTL fix commit mismatch")
    require(HEX40.match(manifest.get("flow_as_run_commit", "")) is not None,
            "invalid flow-as-run commit")
    require(manifest.get("claim_id") is None, "private simulation cannot have claim ID")
    for field in ("public_claim_eligible", "resume_eligible",
                  "c2b4_physical_source_changed", "c2b4_physical_rerun_performed"):
        require(manifest.get(field) is False, "{} must be false".format(field))
    for field in ("board_bridge_ready", "formal_matrix_completed",
                  "correctness_ladder_completed", "dual_platform_complete",
                  "full_profile_rtl_repaired"):
        require(manifest.get(field) is True, "{} must be true".format(field))
    boundaries = manifest.get("boundaries", {})
    for field in ("hp0_shared_is_board_measurement", "score_is_fmax",
                  "sameclock512_64_bytes_per_cycle_claim_reused",
                  "legacy_9p5_gbps_used_in_comparison", "public_claim_updated"):
        require(boundaries.get(field) is False, "boundary drift: {}".format(field))

    all_contracts = matrix_points() + correctness_ladder_points()
    contract_by_id = {point["point_id"]: point for point in all_contracts}
    points = read_csv(root / POINTS_REL, POINT_HEADER)
    metrics = read_csv(root / METRICS_REL, METRIC_HEADER)
    stalls = read_csv(root / STALLS_REL, STALL_HEADER)
    matrix = read_csv(root / MATRIX_REL, MATRIX_HEADER)
    ladder = read_csv(root / LADDER_REL, LADDER_HEADER)
    latencies = read_csv(root / LATENCY_REL, LATENCY_HEADER)
    fairness = read_csv(root / FAIRNESS_REL, FAIRNESS_HEADER)
    verification = read_csv(root / VERIFICATION_REL, VERIFICATION_HEADER)
    artifacts = read_csv(root / ARTIFACTS_REL, ARTIFACT_HEADER)
    require(len(points) == 66, "expected 66 matrix/ladder dual-platform points")
    require(len(metrics) == 132, "expected two metrics per point")
    require(len(stalls) == 66 and len(matrix) == 28 and len(ladder) == 5 and
            len(latencies) == 66,
            "matrix/stall/latency row count mismatch")
    require(len(fairness) == 32, "mixed16 fairness row count mismatch")
    require(len(verification) == 66 and len(artifacts) == 66,
            "verification/artifact row count mismatch")
    require((root / METRICS_REL).read_bytes() ==
            csv_bytes(METRIC_HEADER, generated_metrics(points, contract_by_id)),
            "metrics.csv is not the Decimal regeneration of points.csv")
    require((root / STALLS_REL).read_bytes() ==
            csv_bytes(STALL_HEADER, generated_stalls(points)),
            "stall_breakdown.csv is not regenerated from points.csv")
    require((root / MATRIX_REL).read_bytes() ==
            csv_bytes(MATRIX_HEADER, generated_matrix(verification)),
            "matrix.csv is not regenerated from verification.csv")
    require((root / LADDER_REL).read_bytes() ==
            csv_bytes(LADDER_HEADER, generated_ladder(verification, points)),
            "correctness_ladder.csv is not regenerated from raw points")

    for point in points:
        contract = contract_by_id.get(point["point_id"])
        require(contract is not None,
                "unknown point contract: {}".format(point["point_id"]))
        if contract is not None:
            require(
                point["scenario"] == contract["scenario"] and
                point["frames"] == str(contract["frames"]) and
                point["payload_bytes"] ==
                str(expected_payload_bytes(contract)) and
                point["shared_service"] == str(contract["shared_service"]) and
                point["response_latency_cycles"] ==
                str(contract["response_latency_cycles"]) and
                point["service_percent"] == str(contract["service_percent"]) and
                point["mem_phase_ns"] == str(contract["mem_phase_ns"]),
                "point contract mismatch: {}".format(point["point_key"]),
            )
        require(point["status"] == "PASS" and point["pass_marker"] == "true",
                "non-PASS point: {}".format(point["point_key"]))
        for field in ("frame_fail", "frame_drop", "deadlock", "protocol_error"):
            require(point[field] == "0", "{} nonzero: {}".format(
                field, point["point_key"]))
        require(point["rx_cqe"] == point["frames"],
                "RX CQE count mismatch: {}".format(point["point_key"]))
        if point["scenario"].startswith("loopback") or point["scenario"] in (
                "mixed16", "hp0_sensitivity"):
            require(point["tx_cqe"] == point["frames"],
                    "TX CQE count mismatch: {}".format(point["point_key"]))
        else:
            require(point["tx_cqe"] == "0", "RX-only point emitted TX CQE")
        if point["payload_bytes"] == str(1024 * 4096):
            require(point["rx_peak_outstanding"] == "4",
                    "RX peak outstanding mismatch")
            if not point["scenario"].startswith("rx_"):
                require(point["tx_peak_outstanding"] == "4",
                        "TX peak outstanding mismatch")

    by_id_platform = {(row["point_id"], row["platform"]): row for row in points}
    comparable_fields = [field for field in POINT_HEADER
                         if field not in ("point_key", "platform", "simulator")]
    for point_id in contract_by_id:
        windows_key = (point_id, "windows")
        linux_key = (point_id, "linux")
        win = by_id_platform.get(windows_key)
        linux = by_id_platform.get(linux_key)
        if win is None or linux is None:
            require(False, "missing dual-platform point: {}".format(point_id))
            continue
        require(all(win[field] == linux[field] for field in comparable_fields),
                "cross-platform counter mismatch: {}".format(point_id))
    for row in matrix:
        require(row["status"] == "PASS_DUAL_PLATFORM" and
                HEX64.match(row["semantic_trace_sha256"]) is not None,
                "dual-platform semantic trace gate failed: {}".format(row["point_id"]))
    for row in ladder:
        require(row["status"] == "PASS_DUAL_PLATFORM" and
                HEX64.match(row["semantic_trace_sha256"]) is not None,
                "dual-platform ladder gate failed: {}".format(row["point_id"]))
    for row in verification:
        require(row["status"] == "PASS" and row["pass_marker_count"] == "1" and
                row["point_marker_count"] == "1" and
                HEX64.match(row["semantic_trace_sha256"]) is not None,
                "verification marker/hash mismatch")
    for row in artifacts:
        require(HEX64.match(row["sha256"]) is not None and
                int(row["size_bytes"]) > 0 and row["published"] == "false",
                "raw artifact identity/publication mismatch")
    for row in fairness:
        require(row["completions"] == "64", "mixed16 channel fairness mismatch")

    phase_scores = []
    for phase in (1, 3, 7):
        key = "loopback_peak_phase{}".format(phase)
        metric = next(row for row in metrics if row["platform"] == "windows" and
                      row["point_id"] == key and
                      row["window"] == "hardware_end_to_end")
        phase_scores.append(Decimal(metric["mbps_per_mhz"]))
    spread = (max(phase_scores) - min(phase_scores)) * Decimal("100") / phase_scores[1]
    require(spread <= Decimal("1"), "CDC phase score spread exceeds 1%")

    main = manifest.get("main_point", {})
    for window, field in (("hardware_end_to_end", "e2e_mbps_per_mhz"),
                          ("datapath_steady_state", "steady_mbps_per_mhz")):
        row = next(item for item in metrics if item["platform"] == "windows" and
                   item["point_id"] == MAIN_POINT_ID and item["window"] == window)
        require(main.get(field) == row["mbps_per_mhz"],
                "main score does not bind generated metrics")
    require(main.get("payload_only_model_limit_mbps_per_mhz") == "4.000000",
            "HP0_SHARED model limit mismatch")

    sources = manifest.get("sources", [])
    require({row.get("path") for row in sources} == set(SOURCE_PATHS),
            "source manifest mismatch")
    for source in sources:
        try:
            blob = source_bytes(root, manifest["flow_as_run_commit"], source["path"])
            require(source.get("sha256") == sha256_bytes(blob) and
                    source.get("size_bytes") == len(blob),
                    "source hash/size mismatch: {}".format(source["path"]))
        except (OSError, subprocess.CalledProcessError) as exc:
            errors.append("unable to bind source {}: {}".format(source["path"], exc))
    identity = json.loads((root / IDENTITY_REL).read_text(encoding="utf-8"))
    require(identity.get("identity_equal") is True and
            identity.get("physical_rerun_required") is False,
            "C2B4 physical identity gate mismatch")
    for record in identity.get("files", []):
        require(record.get("baseline_sha256") == record.get("repaired_sha256") and
                record.get("identical") is True,
                "C2B4 file identity mismatch")
    identity_paths = {record.get("path") for record in identity.get("files", [])}
    require(set(identity.get("c2b4_source_members", [])).issubset(identity_paths),
            "C2B4 filelist members are not all hash-bound")
    validate_git_identity(root, manifest, require)

    for name, expected in manifest.get("files", {}).items():
        path = root / PACKAGE_REL / name
        require(path.is_file() and sha256_file(path) == expected,
                "package hash mismatch: {}".format(name))
    require(sha256_file(root / DOC_REL) == manifest.get("document_sha256"),
            "document hash mismatch")
    scan_paths = [root / MANIFEST_REL, root / DOC_REL]
    scan_paths += [root / PACKAGE_REL / name for name in manifest.get("files", {})]
    scan_text = "\n".join(path.read_text(encoding="utf-8") for path in scan_paths
                            if path.is_file())
    for pattern in PRIVATE_PATTERNS:
        require(pattern.search(scan_text) is None,
                "sensitive/private token matched: {}".format(pattern.pattern))
    require("9.5 Gbps" not in scan_text and "Async64 64 B/cycle" not in scan_text,
            "unrelated throughput claim entered repaired evidence")

    if errors:
        raise ValidationError("\n".join(errors))
    return {
        "points": len(points), "metrics": len(metrics), "matrix": len(matrix),
        "ladder": len(ladder),
        "latencies": len(latencies), "fairness": len(fairness),
        "verification": len(verification), "artifacts": len(artifacts),
        "phase_spread_percent": decimal_text(spread),
        "main_e2e_mbps_per_mhz": main["e2e_mbps_per_mhz"],
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--collect-windows-dir")
    parser.add_argument("--collect-linux-dir")
    parser.add_argument("--collect-windows-ladder-dir")
    parser.add_argument("--collect-linux-ladder-dir")
    parser.add_argument("--flow-commit")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    try:
        if (args.collect_windows_dir or args.collect_linux_dir or
                args.collect_windows_ladder_dir or
                args.collect_linux_ladder_dir):
            if not (args.collect_windows_dir and args.collect_linux_dir and
                    args.collect_windows_ladder_dir and
                    args.collect_linux_ladder_dir and args.flow_commit):
                raise ValidationError(
                    "collection requires matrix/ladder dirs and --flow-commit")
            collect(root, Path(args.collect_windows_dir).resolve(),
                    Path(args.collect_linux_dir).resolve(),
                    Path(args.collect_windows_ladder_dir).resolve(),
                    Path(args.collect_linux_ladder_dir).resolve(),
                    args.flow_commit)
        result = validate(root)
    except (ValidationError, ValueError, KeyError, InvalidOperation,
            json.JSONDecodeError, OSError, subprocess.CalledProcessError) as exc:
        print("DMA Async64 repaired throughput evidence: FAIL")
        print(exc)
        return 1
    print("DMA Async64 repaired throughput evidence: PASS")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
