#!/usr/bin/env python3
"""Fail-closed gate for the bounded Async64 RTL-simulation publication."""

from __future__ import print_function

import argparse
import hashlib
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


CLAIM_ID = "slvc_dma_async64_end_to_end_rtl_sim_throughput"
EVIDENCE_ID = "slvc_dma_async64_end_to_end_sim_summary"
NONCLAIM_ID = "slvc_dma_async64_end_to_end_not_hardware"
CHART_REL = Path("docs/assets/slvc_dma_async64_end_to_end_throughput.svg")
PACKAGE_REL = Path("evidence/throughput_simulation/async64_end_to_end")
BLOCKED_PACKAGE_REL = Path(
    "evidence/throughput_simulation/async64_end_to_end_blocked"
)
SUMMARY_REL = Path("evidence/slvc_dma_async64_end_to_end_sim_summary.yaml")
CLAIMS_REL = Path("provenance/claims.yaml")
EVIDENCE_REL = Path("provenance/evidence.yaml")
NONCLAIMS_REL = Path("provenance/nonclaims.yaml")
SHOWCASE_REL = Path("provenance/showcase_assets.json")
VALIDATOR_REL = Path("flows/scripts/validate_dma_async64_throughput.py")
BLOCKED_VALIDATOR_REL = Path(
    "flows/scripts/validate_dma_async64_throughput_blocked.py"
)
MAIN_POINT_ID = "loopback_peak_phase3"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")

CLAIM_FIELDS = frozenset({
    "profile", "statement", "metric", "value", "unit", "benchmark",
    "configuration", "source_ref", "tool", "evidence", "status",
    "caveat", "resume_eligible", "public",
})
CLAIM_FIXED = {
    "profile": "slvc_dma_v1_512_async64_full_loopback_sim",
    "statement": (
        "For 1024 x 4 KiB full TX-to-RX loopback at 100 MHz, hardware "
        "end-to-end payload throughput was 3.831177 MB/s/MHz "
        "(383.117735 MB/s, 3.064942 Gb/s), 95.779434% of the "
        "4 MB/s/MHz HP0_SHARED payload-only model ceiling."
    ),
    "metric": "end_to_end_payload_throughput",
    "value": "3.831177",
    "unit": "MB/s/MHz",
    "benchmark": "1024 x 4096-byte full TX-to-RX loopback",
    "configuration": (
        "16 RX/16 TX contexts; Async64 64-bit memory backend; "
        "aclk=mem_clk=100 MHz; phase 3 ns; seed 71; HP0_SHARED latency "
        "16 cycles and service 100%"
    ),
    "tool": "ModelSim SE-64 2020.4 / Questa Sim-64 10.7c",
    "evidence": [EVIDENCE_ID],
    "status": "verified",
    "caveat": (
        "Verified RTL simulation only; not FPGA/HP0 board throughput, "
        "DDR peak, Fmax, Same-clock512/Async512 64 B/cycle, or ASIC evidence."
    ),
    "resume_eligible": "false",
    "public": "true",
}
EVIDENCE_FIELDS = frozenset({
    "path", "type", "source_ref", "tool", "claims", "sha256", "public",
})
NONCLAIM_FIELDS = frozenset({"profile", "statement", "reason", "status", "public"})
NONCLAIM_FIXED = {
    "profile": "slvc_dma_v1_512_async64_full_loopback_sim",
    "statement": (
        "FPGA/HP0 board throughput, DDR peak, Fmax, Same-clock512/Async512 "
        "64 B/cycle, and ASIC performance are not claimed by this "
        "simulation result."
    ),
    "reason": (
        "The published point is a dual-platform RTL simulation using the "
        "bounded HP0_SHARED service model; FPGA emulation remains pending "
        "and not measured."
    ),
    "status": "not_claimed",
    "public": "true",
}
SUMMARY_PROFILE = {
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
}
SUMMARY_MAIN_POINT = {
    "point_id": MAIN_POINT_ID,
    "frames": 1024,
    "payload_bytes_per_frame": 4096,
    "model": "HP0_SHARED",
    "response_latency_cycles": 16,
    "service_percent": 100,
    "mem_phase_ns": 3,
    "e2e_mbps_per_mhz": "3.831177",
    "steady_mbps_per_mhz": "3.831723",
    "mb_per_s_at_100mhz": "383.117735",
    "gbits_per_s_at_100mhz": "3.064942",
    "payload_only_model_limit_mbps_per_mhz": "4.000000",
    "model_efficiency_percent": "95.779434",
}
SUMMARY_VALIDATION = {
    "windows_platform": "ModelSim SE-64 2020.4",
    "linux_platform": "Questa Sim-64 10.7c",
    "matrix_points": 28,
    "ladder_points": 5,
    "dual_platform_trace_match": True,
    "peak_outstanding": 4,
    "mixed16_fair": True,
    "frame_drop": 0,
    "protocol_error": 0,
    "deadlock": 0,
}
SUMMARY_BOUNDARIES = {
    "board_measurement": False,
    "ddr_peak": False,
    "fmax": False,
    "sameclock512_async512_64_bytes_per_cycle": False,
    "asic_result": False,
    "resume_eligible": False,
}
EXPECTED_PACKAGE_README = """# Async64 End-to-End RTL Simulation Throughput Evidence

Status: `VERIFIED_RTL_SIMULATION`. This package is a public RTL-simulation claim and is not resume eligible.

Profile: 16 RX/16 TX contexts, Async64 64-bit memory backend, `aclk=mem_clk=100 MHz` with 3 ns phase, seed 71.

Main point: 1024 x 4 KiB complete TX-to-RX loopback with the HP0_SHARED model, 16-cycle response latency, and 100% service.

| Window | MB/s/MHz | MB/s at 100 MHz | Gb/s at 100 MHz | Model efficiency |
| --- | ---: | ---: | ---: | ---: |
| Hardware end-to-end | 3.831177 | 383.117735 | 3.064942 | 95.779434% |
| Datapath steady-state | 3.831723 | 383.172335 | 3.065379 | 95.793084% |

Windows ModelSim SE-64 2020.4 and Linux Questa Sim-64 10.7c matched across the 28-point matrix. Peak outstanding reached 4, all 16 flows completed fairly, and drop, protocol error, and deadlock counts were zero.

FPGA emulation: **Pending / not measured / not claimed**.

The 4 MB/s/MHz HP0_SHARED value is a payload-only model ceiling. This result is not FPGA/HP0 board throughput, DDR peak, Fmax, the Same-clock512/Async512 64 B/cycle interface result, or ASIC evidence. C2B4 physical sources remained unchanged and no DC, P&R, OpenRCX, or PrimeTime rerun was performed.
"""

PROTECTED_MANIFEST_HASHES = {
    CLAIMS_REL: "b066370c84de86c0647705df19d919735bb6a7c7f10c6392a33be6a1de3f9a76",
    EVIDENCE_REL: "f919b98bd6b0b9fc6446229ac2c7acee4dcf2df7607a28e8d4cce99201d3fa0d",
    NONCLAIMS_REL: "98b910f4bd9b1e2020e44400c61c21445d3f5d413841fa95e21fa0042223dc1c",
}
PROTECTED_SHOWCASE_BINDINGS_SHA256 = (
    "f12a4dc9019a857479aeb043381b04fe4650d718ce48636ce04f74b40f8f9138"
)
TRUSTED_SHOWCASE_GENERATOR_SHA256 = (
    "7e83fdcc4e81d7ab393d0e6153e7721e80cd053da65d2327ccc19e3b0c74ab53"
)
PROTECTED_README_SHA256 = {
    Path("README.md"): (
        "a15293ac52b2001df825aec3ab8bfebe7d0eee1e6db94c9f1c515c0b83314a5a"
    ),
    Path("README.en.md"): (
        "637963bd8f558d653bb708dcf58d165916bee5458902a6f6e73eec95b6365f09"
    ),
}
README_START = (
    "<!-- throughput-publication:"
    "slvc_dma_async64_end_to_end_rtl_sim_throughput:readme:start -->"
)
README_END = (
    "<!-- throughput-publication:"
    "slvc_dma_async64_end_to_end_rtl_sim_throughput:readme:end -->"
)
RESULTS_START = (
    "<!-- throughput-publication:"
    "slvc_dma_async64_end_to_end_rtl_sim_throughput:start -->"
)
RESULTS_END = (
    "<!-- throughput-publication:"
    "slvc_dma_async64_end_to_end_rtl_sim_throughput:end -->"
)
EXPECTED_README_BLOCK_SHA256 = {
    Path("README.md"): (
        "b6cda206f805c8ce24921deb0c0fa9d1549bf5b06d3fd7a51d7a1e6c6dcf43ba"
    ),
    Path("README.en.md"): (
        "0b0300dda48196e7226531281f69c2f90b554094d220b0cec034b823fd139595"
    ),
}
EXPECTED_RESULTS_BLOCK_SHA256 = {
    Path("docs/en/results.md"): (
        "5fce2d07aef9c35f4a467cefbceacc06880902d40358c72a2ba4e59ab896fe92"
    ),
    Path("docs/zh-CN/results.md"): (
        "dfbd58de61a2c125d08d88f9474ea78e21b31185fe335378d24272a70e734bba"
    ),
}

# These data products were generated by the completed Windows/Linux run and
# are the numeric/semantic publication payload. Locking them here keeps the
# publication decision base-owned even though the feature PR carries its own
# reproducibility validators.
TRUSTED_EVIDENCE_FILE_SHA256 = {
    "c2b4_physical_identity.json": (
        "9659d97801e21f3dbdc17259fdcbf517e63aea6ea4c605382e72208515b01828"
    ),
    "correctness_ladder.csv": (
        "d543dd0d5f011c132bad104114a0e7236648070b002eeb0312e3647e0440d1c5"
    ),
    "flow_fairness.csv": (
        "c4982bb573f9bae5a27ba1cb5db8ee536329c57574939678fd2679d0cdf8c1d8"
    ),
    "latency_summary.csv": (
        "63a9843b6c3f556d47faf31e6cc5c9ae3c20fbcda7db860782284c03f5ef1a35"
    ),
    "matrix.csv": (
        "7c7d9c7c972e898e310b8fef9e770908bc38afb2a448a4f29057acd03e7aac09"
    ),
    "metrics.csv": (
        "745d644482ed69aa1a4d4f726bb3c90e62d4483f0e9852fe903c2feec52ea516"
    ),
    "points.csv": (
        "ebc1eb35c92d2ca58e97ee0c751c9dd354e131cacbdafbd1d691c79d2186da4c"
    ),
    "stall_breakdown.csv": (
        "c5157c30cfcc7122721c008b0651f83305338ab6aed34aded60a62193ef9df40"
    ),
    "verification.csv": (
        "4a2834e4c5551054bc492ba7df68417330b78308a94c95c37cb242a25368384f"
    ),
}
TRUSTED_BLOCKED_FILE_SHA256 = {
    "README.md": "4bf7e42747d5fa09e553da903fa66ce21f092659bf24972f1d9dae59b3ad7242",
    "artifacts.csv": "836547f38bf435f5c693412a799c4d339bdadd39dee62f4c0cc10d87ade1b218",
    "latency.csv": "f469961aa662cc7e45f0e7fcf32ceae08aabdc2d19b75a860b0a01e8f17b6c7d",
    "manifest.json": "a7c75738d12817a51bc69b91a84c7953554d58f8c2d6a4e51527447c0da67c13",
    "matrix.csv": "02cfad983f30636fcfe1d40472615f8329618b1bbc9e222946b611d8cdb116e5",
    "metrics.csv": "ae11c798e6c90457bb82ad278058a4a6cca7ef463c546ddfc1ee8b645424de19",
    "points.csv": "157b1f90f2b5f54110d837484af145abfc7eb95b94649a9f36ce8ae6d68daf78",
    "stall_breakdown.csv": "0f9755c7aa057d65e6f49afa677c71578a0d60766cbb1f4681134d4b00c772dc",
    "verification.csv": "f1f97d1b909e21befe0dd90fb1b94a7cc9d99abe2461301dc5eec4144c0f4161",
}
REQUIRED_SOURCE_PATHS = (
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
    "flows/scripts/validate_dma_async64_throughput.py",
    "flows/scripts/test_validate_dma_async64_throughput.py",
)

REQUIRED_PATHS = frozenset({
    Path("README.en.md"),
    Path("README.md"),
    CHART_REL,
    PACKAGE_REL / "README.md",
    PACKAGE_REL / "artifacts.csv",
    PACKAGE_REL / "c2b4_physical_identity.json",
    PACKAGE_REL / "correctness_ladder.csv",
    PACKAGE_REL / "flow_fairness.csv",
    PACKAGE_REL / "latency_summary.csv",
    PACKAGE_REL / "manifest.json",
    PACKAGE_REL / "matrix.csv",
    PACKAGE_REL / "metrics.csv",
    PACKAGE_REL / "points.csv",
    PACKAGE_REL / "stall_breakdown.csv",
    PACKAGE_REL / "verification.csv",
    BLOCKED_PACKAGE_REL / "manifest.json",
    BLOCKED_PACKAGE_REL / "README.md",
    BLOCKED_PACKAGE_REL / "artifacts.csv",
    BLOCKED_PACKAGE_REL / "latency.csv",
    BLOCKED_PACKAGE_REL / "matrix.csv",
    BLOCKED_PACKAGE_REL / "metrics.csv",
    BLOCKED_PACKAGE_REL / "points.csv",
    BLOCKED_PACKAGE_REL / "stall_breakdown.csv",
    BLOCKED_PACKAGE_REL / "verification.csv",
    SUMMARY_REL,
    Path("docs/en/results.md"),
    Path("docs/zh-CN/results.md"),
    Path("flows/scripts/dma_async64_throughput_contract.py"),
    Path("flows/scripts/generate_showcase_assets.py"),
    Path("flows/scripts/run_dma_async64_throughput_matrix.py"),
    Path("flows/scripts/test_generate_showcase_assets.py"),
    Path("flows/scripts/test_validate_dma_async64_throughput.py"),
    Path("flows/scripts/test_validate_dma_async64_throughput_blocked.py"),
    VALIDATOR_REL,
    BLOCKED_VALIDATOR_REL,
    Path("modelsim/run_rtl_dma_async64_end_to_end_throughput.do"),
    Path("modelsim/run_rtl_dma_axi_read_prefetch.do"),
    Path("modelsim/run_rtl_rx_payload_cdc_bridge.do"),
    Path("pattern/axi_hp0_dual_master_64_model.v"),
    Path("pattern/dma_sim_def.vh"),
    Path("pattern/tb_rtl_dma_async64_end_to_end_throughput.v"),
    Path("pattern/tb_rtl_dma_axi_read_prefetch.v"),
    Path("pattern/tb_rtl_rx_payload_cdc_bridge.v"),
    CLAIMS_REL,
    EVIDENCE_REL,
    NONCLAIMS_REL,
    SHOWCASE_REL,
    Path("rtl/integration/frame_dma_rx_top.v"),
    Path("rtl/rx/dma_rx_payload_cdc_bridge.v"),
    Path("rtl/tx/dma_axi_read_prefetch.v"),
})

PUBLICATION_SENTINELS = (
    CHART_REL,
    PACKAGE_REL / "manifest.json",
    SUMMARY_REL,
)


class PublicationError(RuntimeError):
    pass


def _fail(message):
    raise PublicationError(message)


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        _fail("cannot read {}: {}".format(path, error))


def _strict_json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: {}".format(key))
        result[key] = value
    return result


def _read_json(path):
    try:
        value = json.loads(
            _read_text(path), object_pairs_hook=_strict_json_object
        )
    except (TypeError, ValueError) as error:
        _fail("invalid JSON-syntax YAML {}: {}".format(path, error))
    if not isinstance(value, dict):
        _fail("{} must contain one JSON object".format(path))
    return value


def _sha256_file(path):
    try:
        return _sha256(path.read_bytes())
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))


def _bounded_block(text, start, end, label, required):
    pattern = re.compile(
        r"(?ms)^" + re.escape(start) + r"\n.*?^" +
        re.escape(end) + r"\n?"
    )
    matches = list(pattern.finditer(text))
    marker_count_valid = (
        text.count(start) == len(matches) and text.count(end) == len(matches)
    )
    expected_count = 1 if required else 0
    if not marker_count_valid or len(matches) != expected_count:
        _fail("{} bounded publication block mismatch".format(label))
    if not matches:
        return text, ""
    match = matches[0]
    return text[:match.start()] + text[match.end():], match.group(0)


def _source_blob(root, commit, relative):
    try:
        return subprocess.check_output(
            ["git", "-c", "safe.directory={}".format(root.as_posix()),
             "show", "{}:{}".format(commit, relative)],
            cwd=str(root), stderr=subprocess.STDOUT,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        _fail("cannot read source_ref {}:{}: {}".format(
            commit, relative, error
        ))


def _validate_readme_blocks(root):
    required_common = (
        "<!-- claim:{} maturity:verified -->".format(CLAIM_ID),
        "3.831177 MB/s/MHz",
        "383.117735 MB/s",
        "3.064942 Gb/s",
        "95.779434%",
    )
    result_links = {
        Path("README.md"): "docs/zh-CN/results.md",
        Path("README.en.md"): "docs/en/results.md",
    }
    for relative, expected_hash in PROTECTED_README_SHA256.items():
        text = _read_text(root / relative)
        protected, block = _bounded_block(
            text, README_START, README_END, str(relative), True
        )
        if _sha256(protected.encode("utf-8")) != expected_hash:
            _fail("{} modifies protected homepage content".format(relative))
        if (_sha256(block.encode("utf-8")) !=
                EXPECTED_README_BLOCK_SHA256[relative]):
            _fail("{} throughput block payload mismatch".format(relative))
        for token in required_common + (result_links[relative],):
            if block.count(token) != 1:
                _fail("{} throughput block token mismatch: {}".format(
                    relative, token
                ))
        if ("<img" in block or "width=\"1000\"" in block or
                re.search(r"!\[[^\]]*\]\([^\n)]+\)", block)):
            _fail("{} throughput block must not add a homepage image".format(
                relative
            ))


def _validate_results_blocks(root):
    required_common = (
        "<!-- claim:{} maturity:verified -->".format(CLAIM_ID),
        CHART_REL.as_posix(),
        "width=\"1000\"",
        "3.831177 MB/s/MHz",
        "383.117735 MB/s",
        "3.064942 Gb/s",
        "95.779434%",
        "Pending / not measured / not claimed",
    )
    for relative in (Path("docs/en/results.md"),
                     Path("docs/zh-CN/results.md")):
        text = _read_text(root / relative)
        _, block = _bounded_block(
            text, RESULTS_START, RESULTS_END, str(relative), True
        )
        if (_sha256(block.encode("utf-8")) !=
                EXPECTED_RESULTS_BLOCK_SHA256[relative]):
            _fail("{} throughput result block payload mismatch".format(relative))
        for token in required_common:
            if token not in block:
                _fail("{} throughput result token missing: {}".format(
                    relative, token
                ))
        if block.count("<img") != 1 or block.count("<a href=") != 1:
            _fail("{} throughput result image contract mismatch".format(relative))


def _publication_markers_present(root):
    for relative, start, end in (
            (Path("README.md"), README_START, README_END),
            (Path("README.en.md"), README_START, README_END),
            (Path("docs/en/results.md"), RESULTS_START, RESULTS_END),
            (Path("docs/zh-CN/results.md"), RESULTS_START, RESULTS_END)):
        path = root / relative
        if path.is_file():
            text = _read_text(path)
            if start in text or end in text:
                return True
    return False


def _item_block(text, item_id):
    pattern = re.compile(
        r"(?ms)^  - id: " + re.escape(item_id) + r"\n.*?(?=^  - id: |\Z)"
    )
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        _fail("expected exactly one {} item".format(item_id))
    return matches[0]


def _verify_append_only(path, text, item_id):
    match = _item_block(text, item_id)
    protected = (text[:match.start()] + text[match.end():]).encode("utf-8")
    if _sha256(protected) != PROTECTED_MANIFEST_HASHES[path]:
        _fail("{} modifies a protected pre-publication item".format(path))
    return match.group(0)


def _yaml_scalar(raw, context):
    if raw.startswith('"'):
        try:
            value = json.loads(raw)
        except (TypeError, ValueError) as error:
            _fail("{} has invalid quoted scalar: {}".format(context, error))
        if not isinstance(value, str):
            _fail("{} quoted scalar must be text".format(context))
        return value
    if not raw or raw != raw.strip():
        _fail("{} has noncanonical scalar".format(context))
    return raw


def _parse_registry_record(block, item_id):
    lines = block.splitlines()
    if not lines or lines[0] != "  - id: {}".format(item_id):
        _fail("{} has invalid record header".format(item_id))
    fields = {}
    active_list = None
    for line in lines[1:]:
        scalar = re.fullmatch(r"    ([a-z][a-z0-9_]*):(?: (.*))?", line)
        if scalar:
            key, raw = scalar.groups()
            if key in fields:
                _fail("{} has duplicate {} field".format(item_id, key))
            if raw is None:
                fields[key] = []
                active_list = key
            else:
                fields[key] = _yaml_scalar(raw, "{}.{}".format(item_id, key))
                active_list = None
            continue
        item = re.fullmatch(r"      - (.+)", line)
        if item and active_list is not None:
            fields[active_list].append(
                _yaml_scalar(item.group(1), "{}.{}".format(item_id, active_list))
            )
            continue
        _fail("{} contains unsupported or noncanonical YAML".format(item_id))
    return fields


def _require_field_set(label, record, expected):
    if set(record) != set(expected):
        _fail("{} field set mismatch".format(label))


def _require_fixed_fields(label, record, expected):
    for field, value in expected.items():
        if record.get(field) != value:
            _fail("{} fixed {} mismatch".format(label, field))


def _normalized_showcase_bindings(root, manifest):
    if set(manifest) != {"kind", "schema_version", "assets"}:
        _fail("showcase asset manifest field set mismatch")
    assets = manifest.get("assets")
    if not isinstance(assets, list):
        _fail("showcase asset manifest has no assets list")
    existing = []
    chart_count = 0
    for asset in assets:
        if not isinstance(asset, dict):
            _fail("showcase asset entry must be an object")
        if asset.get("path") == CHART_REL.as_posix():
            chart_count += 1
            continue
        output_rel = Path(str(asset.get("path", "")))
        if output_rel.is_absolute() or ".." in output_rel.parts:
            _fail("existing showcase output path is invalid")
        if asset.get("sha256") != _sha256_file(root / output_rel):
            _fail("existing showcase output hash mismatch: {}".format(output_rel))
        normalized = json.loads(json.dumps(asset))
        if "generator_sha256" in normalized:
            generator_rel = Path(str(normalized.get("generator", "")))
            if generator_rel.is_absolute() or ".." in generator_rel.parts:
                _fail("existing showcase generator path is invalid")
            if normalized["generator_sha256"] != _sha256_file(
                    root / generator_rel):
                _fail("existing showcase generator hash mismatch: {}".format(
                    generator_rel
                ))
            normalized["generator_sha256"] = "<GENERATOR_SHA256>"
        inputs = normalized.get("inputs")
        if inputs is not None:
            if not isinstance(inputs, list):
                _fail("showcase asset inputs must be a list")
            for source in inputs:
                if not isinstance(source, dict) or "path" not in source:
                    _fail("showcase asset input binding is invalid")
                if "sha256" in source:
                    input_rel = Path(str(source["path"]))
                    if input_rel.is_absolute() or ".." in input_rel.parts:
                        _fail("existing showcase input path is invalid")
                    if source["sha256"] != _sha256_file(root / input_rel):
                        _fail("existing showcase input hash mismatch: {}".format(
                            input_rel
                        ))
                    source["sha256"] = "<INPUT_SHA256>"
        existing.append(normalized)
    if chart_count not in (0, 1):
        _fail("throughput chart has duplicate showcase bindings")
    protected = {
        "kind": manifest["kind"],
        "schema_version": manifest["schema_version"],
        "assets": existing,
    }
    return _sha256(json.dumps(
        protected, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("ascii"))


def _validate_showcase_binding(root):
    generator_rel = Path("flows/scripts/generate_showcase_assets.py")
    if _sha256_file(root / generator_rel) != TRUSTED_SHOWCASE_GENERATOR_SHA256:
        _fail("base-owned showcase generator identity mismatch")
    manifest = _read_json(root / SHOWCASE_REL)
    if (_normalized_showcase_bindings(root, manifest) !=
            PROTECTED_SHOWCASE_BINDINGS_SHA256):
        _fail("existing showcase asset bindings changed")
    assets = manifest.get("assets")
    matches = [item for item in assets if isinstance(item, dict) and
               item.get("path") == CHART_REL.as_posix()]
    if len(matches) != 1:
        _fail("throughput chart must have exactly one showcase binding")
    chart = matches[0]
    expected_fields = {
        "path", "sha256", "format", "source", "source_type",
        "numeric_authority", "generator", "generator_sha256", "command",
        "inputs", "claim_ids",
    }
    _require_field_set("throughput chart binding", chart, expected_fields)
    if chart.get("sha256") != _sha256((root / CHART_REL).read_bytes()):
        _fail("throughput chart output hash mismatch")
    if chart.get("format") != "svg":
        _fail("throughput chart format mismatch")
    if chart.get("numeric_authority") is not False:
        _fail("throughput chart must not be numeric authority")
    if chart.get("source_type") != "deterministic_generated_showcase":
        _fail("throughput chart source type mismatch")
    if chart.get("claim_ids") != [CLAIM_ID]:
        _fail("throughput chart claim binding mismatch")
    if chart.get("generator") != generator_rel.as_posix():
        _fail("throughput chart generator binding mismatch")
    if chart.get("generator_sha256") != _sha256((root / generator_rel).read_bytes()):
        _fail("throughput chart generator hash mismatch")
    inputs = chart.get("inputs")
    if not isinstance(inputs, list):
        _fail("throughput chart inputs must be a list")
    input_map = {}
    for item in inputs:
        if not isinstance(item, dict) or set(item) != {"path", "sha256"}:
            _fail("throughput chart input record is invalid")
        path = item["path"]
        if path in input_map:
            _fail("throughput chart input path is duplicated")
        input_map[path] = item["sha256"]
    required_inputs = (
        SUMMARY_REL,
        PACKAGE_REL / "points.csv",
        CLAIMS_REL,
    )
    if set(input_map) != {item.as_posix() for item in required_inputs}:
        _fail("throughput chart source binding set mismatch")
    for relative in required_inputs:
        if input_map[relative.as_posix()] != _sha256((root / relative).read_bytes()):
            _fail("throughput chart source hash mismatch: {}".format(relative))


def _validate_summary(root, source_ref):
    summary = _read_json(root / SUMMARY_REL)
    expected_fields = {
        "schema", "classification", "claim_id", "numeric_authority",
        "source_ref", "profile", "main_point", "validation", "boundaries",
        "fpga_emulation",
    }
    _require_field_set("throughput summary", summary, expected_fields)
    expected_scalars = {
        "schema": "slvc_dma_async64_end_to_end_rtl_simulation_v1",
        "classification": "VERIFIED_RTL_SIMULATION",
        "claim_id": CLAIM_ID,
        "numeric_authority": (PACKAGE_REL / "points.csv").as_posix(),
        "source_ref": source_ref,
    }
    _require_fixed_fields("throughput summary", summary, expected_scalars)
    if summary.get("profile") != SUMMARY_PROFILE:
        _fail("throughput summary profile mismatch")
    if summary.get("main_point") != SUMMARY_MAIN_POINT:
        _fail("throughput summary main point mismatch")
    if summary.get("validation") != SUMMARY_VALIDATION:
        _fail("throughput summary validation mismatch")
    if summary.get("boundaries") != SUMMARY_BOUNDARIES:
        _fail("throughput summary boundary mismatch")
    if summary.get("fpga_emulation") != {
            "status": "pending_not_measured_not_claimed", "value": None}:
        _fail("throughput summary FPGA boundary mismatch")


def _validate_package_manifest(root, source_ref):
    manifest = _read_json(root / PACKAGE_REL / "manifest.json")
    fixed = {
        "schema_version": 3,
        "experiment_id": "slvc_dma_async64_end_to_end_rtl_simulation",
        "classification": "VERIFIED_RTL_SIMULATION",
        "flow_as_run_commit": source_ref,
        "claim_id": CLAIM_ID,
        "public_claim_eligible": True,
        "resume_eligible": False,
        "formal_matrix_completed": True,
        "correctness_ladder_completed": True,
        "dual_platform_complete": True,
        "c2b4_physical_source_changed": False,
        "c2b4_physical_rerun_performed": False,
        "rtl_fix_commit": source_ref,
        "baseline_commit": "c20681fad0eaa6ad55dbb919149765b175b29117",
        "blocked_evidence_commit": "e6a6696603b10c4475fca468e9c40c727197ac9c",
    }
    expected_fields = set(fixed) | {
        "profile", "main_point", "boundaries", "document_sha256",
        "files", "sources",
    }
    _require_field_set("throughput package manifest", manifest, expected_fields)
    _require_fixed_fields("throughput package manifest", manifest, fixed)
    if manifest.get("profile") != dict(
            SUMMARY_PROFILE,
            descriptor_workload_entries=1024,
            descriptor_ring_capacity_entries=2048,
            cq_entries=4096):
        _fail("throughput package profile mismatch")
    if manifest.get("main_point") != dict(
            SUMMARY_MAIN_POINT,
            workload="1024 x 4096-byte full TX-to-RX loopback"):
        _fail("throughput package main point mismatch")
    boundaries = manifest.get("boundaries")
    expected_boundaries = {
        "hp0_shared_is_board_measurement": False,
        "score_is_fmax": False,
        "sameclock512_64_bytes_per_cycle_claim_reused": False,
        "legacy_9p5_gbps_used_in_comparison": False,
        "public_claim_updated": True,
        "fpga_emulation_measured": False,
    }
    if boundaries != expected_boundaries:
        _fail("throughput package boundary mismatch")

    package_files = {
        path.name for path in REQUIRED_PATHS
        if path.parent == PACKAGE_REL and path.name != "manifest.json"
    }
    file_hashes = manifest.get("files")
    if not isinstance(file_hashes, dict) or set(file_hashes) != package_files:
        _fail("throughput package file inventory mismatch")
    for name, digest in file_hashes.items():
        if not HEX64.fullmatch(str(digest)):
            _fail("throughput package file hash is invalid: {}".format(name))
        if digest != _sha256_file(root / PACKAGE_REL / name):
            _fail("throughput package file hash mismatch: {}".format(name))

    for name, digest in TRUSTED_EVIDENCE_FILE_SHA256.items():
        if _sha256_file(root / PACKAGE_REL / name) != digest:
            _fail("trusted throughput evidence changed: {}".format(name))

    document_hash = manifest.get("document_sha256")
    if document_hash != _sha256_file(root / PACKAGE_REL / "README.md"):
        _fail("throughput package document hash mismatch")
    package_readme = _read_text(root / PACKAGE_REL / "README.md")
    if package_readme != EXPECTED_PACKAGE_README:
        _fail("throughput package README payload mismatch")

    sources = manifest.get("sources")
    if not isinstance(sources, list):
        _fail("throughput package source inventory is missing")
    source_map = {}
    for item in sources:
        if not isinstance(item, dict) or set(item) != {
                "path", "sha256", "size_bytes"}:
            _fail("throughput package source record is invalid")
        path = item["path"]
        if path in source_map:
            _fail("throughput package source path is duplicated")
        source_map[path] = item
    if set(source_map) != set(REQUIRED_SOURCE_PATHS):
        _fail("throughput package source inventory mismatch")
    for relative in REQUIRED_SOURCE_PATHS:
        blob = _source_blob(root, source_ref, relative)
        item = source_map[relative]
        if item["sha256"] != _sha256(blob) or item["size_bytes"] != len(blob):
            _fail("throughput package source identity mismatch: {}".format(
                relative
            ))
        try:
            current = (root / relative).read_bytes()
        except OSError as error:
            _fail("cannot read current publication source {}: {}".format(
                relative, error
            ))
        if current != blob:
            _fail("checked-out source differs from source_ref: {}".format(
                relative
            ))

    for name, digest in TRUSTED_BLOCKED_FILE_SHA256.items():
        if _sha256_file(root / BLOCKED_PACKAGE_REL / name) != digest:
            _fail("blocked throughput evidence changed: {}".format(name))


def _validate_chart(root):
    try:
        svg = ET.fromstring((root / CHART_REL).read_bytes())
    except (OSError, ET.ParseError) as error:
        _fail("invalid throughput chart: {}".format(error))
    expected = {
        "width": "1600", "height": "1000", "viewBox": "0 0 1600 1000",
        "preserveAspectRatio": "xMidYMid meet",
        "data-claim-id": CLAIM_ID,
        "data-classification": "VERIFIED_RTL_SIMULATION",
        "data-e2e-mbps-per-mhz": "3.831177",
        "data-steady-mbps-per-mhz": "3.831723",
        "data-model-efficiency-percent": "95.779434",
        "data-fpga-emulation": "pending-not-measured-not-claimed",
    }
    for field, value in expected.items():
        if svg.get(field) != value:
            _fail("throughput chart {} mismatch".format(field))
    text = " ".join(" ".join(svg.itertext()).split())
    required_text = (
        CLAIM_ID,
        "Async64 End-to-End RTL Simulation Throughput",
        "3.831177 MB/s/MHz",
        "3.831723 MB/s/MHz",
        "383.117735 MB/s",
        "3.064942 Gb/s",
        "4.000000 MB/s/MHz",
        "95.779434%",
        "64 B: 0.453734 MB/s/MHz",
        "128 B: 0.858762 MB/s/MHz",
        "256 B: 1.514215 MB/s/MHz",
        "1024 B: 3.400603 MB/s/MHz",
        "4096 B: 3.831177 MB/s/MHz",
        "50%: 1.941126 MB/s/MHz",
        "75%: 2.892408 MB/s/MHz",
        "100%: 3.831177 MB/s/MHz",
        "ModelSim SE-64 2020.4 + Questa Sim-64 10.7c",
        "Peak outstanding = 4",
        "16-flow fairness = PASS",
        "Drop / protocol error / deadlock = 0",
        "Pending / not measured / not claimed",
        "not FPGA/HP0 board throughput",
        "not DDR peak",
        "not Fmax",
        "not ASIC evidence",
    )
    for required in required_text:
        if required not in text:
            _fail("throughput chart is missing {}".format(required))

    measurements = set(re.findall(
        r"(?<![A-Za-z0-9_.])(?:[0-9]+(?:\.[0-9]+)?)\s*"
        r"(?:MB/s/MHz|MB/s|GB/s|Gb/s|B/cycle|%)",
        text,
    ))
    allowed_measurements = {
        "0.453734 MB/s/MHz", "0.858762 MB/s/MHz",
        "1.514215 MB/s/MHz", "1.941126 MB/s/MHz",
        "2.892408 MB/s/MHz", "3.400603 MB/s/MHz",
        "3.831177 MB/s/MHz", "3.831723 MB/s/MHz",
        "4.000000 MB/s/MHz", "383.117735 MB/s",
        "3.064942 Gb/s", "95.779434%", "50%", "75%", "100%",
        "64 B/cycle",
    }
    unexpected = measurements - allowed_measurements
    if unexpected:
        _fail("throughput chart contains unauthorized measurement {}".format(
            sorted(unexpected)[0]
        ))


def _run_validator(root, relative):
    completed = subprocess.run(
        [sys.executable, str(root / relative), "--root", str(root)],
        cwd=str(root),
    )
    if completed.returncode != 0:
        _fail("{} failed".format(relative))


def validate(root, execute_validators=True):
    root = Path(root).resolve()
    claims_text = _read_text(root / CLAIMS_REL)
    claim_present = ("  - id: {}\n".format(CLAIM_ID) in claims_text)
    sentinels_present = [path for path in PUBLICATION_SENTINELS if (root / path).exists()]
    if _publication_markers_present(root):
        sentinels_present.append(Path("bounded-publication-marker"))
    if not claim_present:
        if sentinels_present:
            _fail("throughput publication files exist without the registered claim")
        return "NOT_PUBLISHED"

    missing = [path for path in sorted(REQUIRED_PATHS, key=lambda item: item.as_posix())
               if not (root / path).is_file()]
    if missing:
        _fail("throughput publication is missing {}".format(missing[0]))

    claim_block = _verify_append_only(CLAIMS_REL, claims_text, CLAIM_ID)
    evidence_text = _read_text(root / EVIDENCE_REL)
    evidence_block = _verify_append_only(EVIDENCE_REL, evidence_text, EVIDENCE_ID)
    nonclaims_text = _read_text(root / NONCLAIMS_REL)
    nonclaim_block = _verify_append_only(NONCLAIMS_REL, nonclaims_text, NONCLAIM_ID)
    claim = _parse_registry_record(claim_block, CLAIM_ID)
    _require_field_set("throughput claim", claim, CLAIM_FIELDS)
    _require_fixed_fields("throughput claim", claim, CLAIM_FIXED)
    source_ref = claim.get("source_ref", "")
    if not HEX40.fullmatch(source_ref):
        _fail("throughput claim source_ref must be a full commit SHA")

    evidence = _parse_registry_record(evidence_block, EVIDENCE_ID)
    _require_field_set("throughput evidence", evidence, EVIDENCE_FIELDS)
    evidence_fixed = {
        "path": SUMMARY_REL.as_posix(),
        "type": "bounded_dual_platform_rtl_simulation",
        "source_ref": source_ref,
        "tool": CLAIM_FIXED["tool"],
        "claims": [CLAIM_ID],
        "public": "true",
    }
    _require_fixed_fields("throughput evidence", evidence, evidence_fixed)
    if evidence.get("sha256") != _sha256((root / SUMMARY_REL).read_bytes()):
        _fail("throughput evidence SHA does not bind the summary")

    nonclaim = _parse_registry_record(nonclaim_block, NONCLAIM_ID)
    _require_field_set("throughput nonclaim", nonclaim, NONCLAIM_FIELDS)
    _require_fixed_fields("throughput nonclaim", nonclaim, NONCLAIM_FIXED)

    _validate_summary(root, source_ref)
    _validate_package_manifest(root, source_ref)
    _validate_readme_blocks(root)
    _validate_results_blocks(root)
    _validate_showcase_binding(root)
    _validate_chart(root)

    if execute_validators:
        _run_validator(root, BLOCKED_VALIDATOR_REL)
        _run_validator(root, VALIDATOR_REL)
    return "VERIFIED_RTL_SIMULATION_PUBLISHED"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    try:
        status = validate(args.root)
    except PublicationError as error:
        print("throughput-publication: error: {}".format(error), file=sys.stderr)
        return 2
    print("throughput-publication: {}".format(status))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
