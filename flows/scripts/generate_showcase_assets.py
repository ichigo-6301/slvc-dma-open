#!/usr/bin/env python3
"""Generate and verify deterministic SLVC DMA showcase SVG assets."""

from __future__ import print_function

import argparse
import csv
from decimal import Decimal, ROUND_HALF_EVEN, ROUND_HALF_UP
import hashlib
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path


ASSET_DIR = Path("docs/assets")
ASSET_MANIFEST_PATH = Path("provenance/showcase_assets.json")
CLAIMS_PATH = Path("provenance/claims.yaml")
COMPARISONS_PATH = Path("evidence/asic_paired_dc/comparisons.csv")
C2B4_EVIDENCE_PATH = Path(
    "evidence/slvc_dma_c2b4_n45_register_postroute_summary.yaml"
)
CDC_EVIDENCE_PATH = Path(
    "evidence/slvc_dma_rx_payload_cdc_regression_summary.yaml"
)
WRAPPER_PATH = Path("rtl/integration/slvc_dma_wrapper.v")
FRAME_WRAPPER_PATH = Path("rtl/integration/frame_dma_wrapper.v")
RX_TOP_PATH = Path("rtl/integration/frame_dma_rx_top.v")
C2B4_PROFILE_PATH = Path(
    "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml"
)
GENERATOR_PATH = Path("flows/scripts/generate_showcase_assets.py")
README_PATH = Path("README.md")
README_EN_PATH = Path("README.en.md")
ARCHITECTURE_PATH = Path("docs/zh-CN/architecture.md")
ARCHITECTURE_EN_PATH = Path("docs/en/architecture.md")
RESEARCH_PATH = Path("docs/zh-CN/research_branches.md")
RESEARCH_EN_PATH = Path("docs/en/research_branches.md")

OVERVIEW_ASSET = Path("docs/assets/slvc_dma_overview.svg")
VIRTUAL_CHANNEL_ASSET = Path(
    "docs/assets/slvc_dma_virtual_channel_buffering.svg"
)
FRAME_LIFECYCLE_ASSET = Path("docs/assets/slvc_dma_frame_lifecycle.svg")
MEMORY_PROFILES_ASSET = Path("docs/assets/slvc_dma_memory_profiles.svg")
PPA_ASSET = Path("docs/assets/slvc_dma_ppa_implementation.svg")
SYSTEM_OVERVIEW_PNG = Path(
    "docs/assets/showcase/slvc_dma_system_overview.png"
)
WRITER_CDC_PNG = Path(
    "docs/assets/showcase/slvc_dma_writer_transaction_cdc.png"
)
GENERATED_ASSETS = (
    OVERVIEW_ASSET,
    VIRTUAL_CHANNEL_ASSET,
    FRAME_LIFECYCLE_ASSET,
    MEMORY_PROFILES_ASSET,
    PPA_ASSET,
)
README_ASSET_ORDER = (
    SYSTEM_OVERVIEW_PNG,
    WRITER_CDC_PNG,
    PPA_ASSET,
)
README_ASSET_ALTS = {
    SYSTEM_OVERVIEW_PNG: "SLVC DMA shared-link system overview",
    WRITER_CDC_PNG: "512-bit AXI4 Writer and transaction-level CDC",
    PPA_ASSET: "SLVC DMA Writer PPA and C2B4 ASIC implementation",
}
README_DETAILED_ASSETS = (
    FRAME_LIFECYCLE_ASSET,
    VIRTUAL_CHANNEL_ASSET,
    MEMORY_PROFILES_ASSET,
)
ARCHITECTURE_ASSETS = (
    OVERVIEW_ASSET,
    FRAME_LIFECYCLE_ASSET,
    VIRTUAL_CHANNEL_ASSET,
    MEMORY_PROFILES_ASSET,
)
BINARY_ASSETS = {
    SYSTEM_OVERVIEW_PNG: {
        "role": "system_overview",
        "sha256": "05bc9f882666dec639682a119741c6aefd2711ec751399dc7cee4e6c6131bffa",
        "size_bytes": 1129541,
        "width": 1586,
        "height": 992,
    },
    WRITER_CDC_PNG: {
        "role": "writer_transaction_cdc",
        "sha256": "ec909aeb313ccc411def7273e6d6a6f158d59650dc1fd0cb2e8f160a7c76cb85",
        "size_bytes": 1166855,
        "width": 1586,
        "height": 992,
    },
}
OBSOLETE_ASSETS = (Path("docs/assets/slvc_dma_results_at_a_glance.svg"),)

NAVIGATION_ANCHORS = (
    "key-results-and-evidence",
    "frame-lifecycle",
    "memory-profiles-and-cdc",
    "throughput-ppa-and-asic",
    "fixed-implementation-points",
    "research-branches",
    "result-scope-levels",
    "quick-public-checks",
    "ten-minute-rtl-reading-path",
)
RESEARCH_BRANCH = "research/dma-a3-clock-gating-storage-positive-2026-08"
RESEARCH_COMMIT = "d99234ffb3d7d9a5b068ca4434fcfce8b7fd5c79"
CLAIM_MARKER = re.compile(
    r"<!-- claim:([A-Za-z0-9_.-]+) maturity:verified -->"
)

ADMISSION_CLAIM = "slvc_dma_channel_admission_isolation_directed"
WRITER_CLAIM = "slvc_dma_writer_reservation_component_paired_dc"
CDC_REGRESSION_CLAIM = "slvc_dma_rx_payload_cdc_regression"
THROUGHPUT_CLAIM = "slvc_dma_rx_payload_cdc_ideal_throughput"
C2B4_CLAIM = "slvc_dma_c2b4_n45_register_postroute_450"

COMPARISON_HEADER = (
    "evaluation_id", "claim_id", "baseline_point_id", "candidate_point_id",
    "metric", "baseline", "candidate", "delta", "delta_percent",
)

CLAIM_START = re.compile(r"^  - id: ([A-Za-z0-9_.-]+)$")
CLAIM_FIELD = re.compile(r"^    ([A-Za-z0-9_]+):\s*(.*)$")
CLAIM_LIST_ITEM = re.compile(r"^      -\s+(.+)$")
WRITER_STATEMENT = re.compile(
    r"^At the same ([0-9.]+) ns Nangate45 DC OOC constraint, the reservation "
    r"candidate reduced Writer total cell area by ([0-9.]+) percent and "
    r"combinational area by ([0-9.]+) percent; both points remained "
    r"setup-closed\.$"
)
C2B4_STATEMENT = re.compile(
    r"^The C2B4 register-expanded RX512 memory subsystem completed a "
    r"([0-9]+) MHz Design Compiler handoff and a ([0-9]+) MHz same-run "
    r"OpenROAD, OpenRCX, and PrimeTime closure point\.$"
)

WRITER_SCOPE = {
    "profile": "dma_axi_write_engine_512_component_eval",
    "statement": (
        "At the same 1.500 ns Nangate45 DC OOC constraint, the reservation "
        "candidate reduced Writer total cell area by 7.966353 percent and "
        "combinational area by 15.838902 percent; both points remained "
        "setup-closed."
    ),
    "metric": "component_paired_dc_total_cell_area",
    "value": "-7.966353",
    "unit": "percent candidate-minus-baseline",
    "benchmark": "dma_axi_write_engine_512 W0 versus W1",
    "configuration": (
        "MAX_OUTSTANDING=4; MAX_BURST_BEATS=16; register-expanded "
        "component; identical tool, library, and constraints"
    ),
    "source_ref": "adbc36aa92c6fee11253fbae31ec77216dae91cc",
    "tool": "Design Compiler O-2018.06-SP1",
    "evidence": ["slvc_dma_asic_paired_dc_publication"],
    "status": "verified",
    "caveat": (
        "Component-level DC OOC only; this does not establish C2B4 or "
        "complete-DMA area reduction, Fmax, P&R, power, or signoff."
    ),
    "public": True,
}

ADMISSION_SCOPE = {
    "profile": "slvc_dma_v1_512_udp_ipv4_adapter_p0",
    "statement": (
        "A directed adapter-to-DMA scenario accepted and completed a "
        "channel-1 packet while channel 0 had no available ring space."
    ),
    "metric": "directed_channel_admission_progress",
    "value": "pass",
    "unit": "result",
    "benchmark": "two-packet, two-channel adapter-to-DMA smoke with ch0_full_then_ch1=1",
    "configuration": (
        "512-bit SHDR64 DMA path with per-channel ring-space admission and "
        "two expected CQEs"
    ),
    "source_ref": "709e1c102af3cc8a195bae5dc126bd2c3cf23eb7",
    "tool": "ModelSim SE-64 2020.4 / Questa Sim-64 10.7c",
    "evidence": ["slvc_dma_udp_adapter_regression_summary"],
    "status": "verified",
    "caveat": (
        "This proves one directed per-channel ring-space scenario, not "
        "universal non-blocking behavior, formal channel isolation, or "
        "performance relative to an MCDMA implementation."
    ),
    "public": True,
}

CDC_REGRESSION_SCOPE = {
    "profile": "slvc_dma_v1_512_rx_payload_cdc_development",
    "statement": (
        "The same-clock 512, async64, and async512 RX memory profiles passed "
        "their configured regression sets on Windows ModelSim and Linux Questa."
    ),
    "metric": "directed_regression",
    "value": "pass",
    "unit": "result",
    "benchmark": (
        "default 14 markers, same-clock 12 markers, async64 15 markers from "
        "13 commands, async512 14 markers from 13 commands"
    ),
    "configuration": "Committed-frame RX source with optional dedicated RX memory backend",
    "source_ref": "18db34bf010ba48428fea5955ac42454e92f60a1",
    "tool": "ModelSim SE-64 2020.4 / Questa Sim-64 10.7c",
    "evidence": ["slvc_dma_rx_payload_cdc_regression_summary"],
    "status": "verified",
    "caveat": (
        "Directed and deterministic random simulation is not coverage closure, "
        "formal proof, or board validation."
    ),
    "public": True,
}

THROUGHPUT_SCOPE = {
    "profile": "slvc_dma_v1_512_rx_payload_cdc_development",
    "statement": (
        "Ideal-memory tests sustained one AXI W beat per clock for same-clock "
        "512, async64, and async512."
    ),
    "metric": "ideal_model_interface_throughput",
    "value": "100",
    "unit": "percent W-channel utilization",
    "benchmark": "1 MiB transfer with ready memory model",
    "configuration": (
        "same-clock 512 and async512 64 byte/cycle; async64 8 byte/cycle; "
        "four peak outstanding"
    ),
    "source_ref": "18db34bf010ba48428fea5955ac42454e92f60a1",
    "tool": "ModelSim SE-64 2020.4 / Questa Sim-64 10.7c",
    "evidence": ["slvc_dma_rx_payload_cdc_regression_summary"],
    "status": "verified",
    "caveat": (
        "This is RTL/model interface throughput, not a board DDR or "
        "lossless-network measurement."
    ),
    "public": True,
}

C2B4_SCOPE = {
    "profile": "dma_rx512_reg_c2_b4_m2_sp64",
    "statement": (
        "The C2B4 register-expanded RX512 memory subsystem completed a "
        "550 MHz Design Compiler handoff and a 450 MHz same-run OpenROAD, "
        "OpenRCX, and PrimeTime closure point."
    ),
    "metric": "internal_postroute_setup_hold",
    "value": "0.000341",
    "unit": "ns minimum setup or hold WNS",
    "benchmark": "C2B4 RX512 memory subsystem with 102400 payload and keep registers",
    "configuration": (
        "Nangate45 nominal corner; DC 550 MHz; P&R and PT 450 MHz; setup "
        "uncertainty 0.200 ns; nominal hold uncertainty 0 ns"
    ),
    "source_ref": "bb8591a8903e55027722f404e99fe9df9832dbf7",
    "tool": (
        "Design Compiler O-2018.06-SP1 / OpenROAD / OpenRCX / "
        "PrimeTime O-2018.06-SP1"
    ),
    "evidence": ["slvc_dma_c2b4_n45_register_postroute_summary"],
    "status": "verified",
    "caveat": (
        "This is a C2 development profile and internal nominal academic-corner "
        "result, not C4B4, Fmax, complete-DMA, power, IO, OCV/MMMC, foundry, "
        "or silicon signoff."
    ),
    "public": True,
}

CANVAS_WIDTH = "1600"
CANVAS_HEIGHT = "1000"
VIEW_BOX = "0 0 1600 1000"
PRESERVE_ASPECT_RATIO = "xMidYMid meet"

REPORT_STYLE = """
    .title{font:700 38px Arial,Helvetica,sans-serif;fill:#111827}
    .subtitle{font:400 22px Arial,Helvetica,sans-serif;fill:#4b5563}
    .panel-title{font:700 25px Arial,Helvetica,sans-serif;fill:#102f5e}
    .section{font:700 22px Arial,Helvetica,sans-serif;fill:#111827}
    .body{font:400 19px Arial,Helvetica,sans-serif;fill:#1f2937}
    .body-bold{font:700 19px Arial,Helvetica,sans-serif;fill:#111827}
    .metric{font:700 23px Arial,Helvetica,sans-serif;fill:#1456a0}
    .small{font:400 16px Arial,Helvetica,sans-serif;fill:#4b5563}
    .foot{font:400 17px Arial,Helvetica,sans-serif;fill:#374151}
    .table-head{font:700 17px Arial,Helvetica,sans-serif;fill:#ffffff}
    .table-header{font:700 16px Arial,Helvetica,sans-serif;fill:#111827}
    .table{font:400 17px Arial,Helvetica,sans-serif;fill:#1f2937}
    .table-strong{font:700 17px Arial,Helvetica,sans-serif;fill:#1456a0}
    .rule{stroke:#102f5e;stroke-width:1.5}
    .thin{stroke:#9ca3af;stroke-width:1}
    .box{fill:#ffffff;stroke:#6b7280;stroke-width:1.2}
    .box-blue{fill:#ffffff;stroke:#1456a0;stroke-width:1.4}
    .panel-header{fill:#102f5e;stroke:#102f5e;stroke-width:1}
    .flow{fill:none;stroke:#6b7280;stroke-width:1.5;marker-end:url(#arrow)}
    .flow-blue{fill:none;stroke:#1456a0;stroke-width:1.8;marker-end:url(#arrow-blue)}
    .flow-return{fill:none;stroke:#1456a0;stroke-width:1.8;marker-end:url(#arrow-blue)}
    .boundary{fill:none;stroke:#8b9199;stroke-width:1.5;stroke-dasharray:8 6}
    .orange{fill:#b45309}
    .green{fill:#047857}
""".strip()

BANNED_COLORS = (
    "#dbeafe", "#dcfce7", "#fef3c7", "#ede9fe", "#cffafe",
    "#fee2e2", "#eff6ff", "#f0fdf4", "#fff7ed",
)

THEME_TOKENS = (
    'width="1600"',
    'height="1000"',
    'viewBox="0 0 1600 1000"',
    'preserveAspectRatio="xMidYMid meet"',
    "#102f5e",
    "#1456a0",
    "#ffffff",
    ".title{font:700 38px",
    ".subtitle{font:400 22px",
    ".rule{stroke:#102f5e;stroke-width:1.5}",
)

GENERATED_RULES = {
    "slvc_dma_overview.svg": (
        "SLVC DMA shared-link system overview",
        "Source Boundaries",
        "SHDR64 Shared Link",
        "Channel Admission",
        "Hybrid Buffering",
        "DDR / Completion Ownership",
        "End-to-End Contract / Boundary",
        "Stream contract",
        "Software ownership",
        "Verification boundary",
        "Aurora / native SHDR64",
        "optional UDP adapter",
        "local endpoint / MCF",
        "AXI4-Lite",
        "PAUSE / RESUME",
        "CQ owner-last",
    ),
    "slvc_dma_virtual_channel_buffering.svg": (
        "Virtual-channel buffering and frame isolation",
        "SHDR64 context",
        "Fixed ingress",
        "dedicated capacity",
        "Shared Frame Pool",
        "free-list capacity",
        "Only committed frames are visible",
        "Selector locks one frame",
        "no source interleave",
        "channel 0 full",
        "channel 1 progresses",
    ),
    "slvc_dma_frame_lifecycle.svg": (
        "SHDR64 frame lifecycle and ownership boundaries",
        "Header beat",
        "Parse / CRC",
        "Match Context",
        "Check Ingress + Ring + CQ",
        "Reserve / Reject",
        "admission gate",
        "Payload beats",
        "Fixed / Shared collect",
        "WHOLE-FRAME COMMIT",
        "Frame-locked Source",
        "Memory Backend",
        "DDR / B response",
        "CQE body",
        "owner / valid",
        "release frame ownership",
        'data-requires="header-control,payload"',
    ),
    "slvc_dma_memory_profiles.svg": (
        "RX memory profiles and CDC boundaries",
        "Legacy64",
        "Same-clock512",
        "Async64",
        "Async512",
        "Command",
        "Ordered Payload",
        "Tagged Completion",
        'data-transaction="command" data-direction="aclk-to-mem-clk"',
        'data-transaction="ordered-payload" data-direction="aclk-to-mem-clk"',
        'data-transaction="tagged-completion" data-direction="mem-clk-to-aclk"',
        "Async FIFO boundary",
        "512-to-64 serializer",
        "CDC bypass",
        "AW / W / B",
        "not measured in this matrix",
        "64-bit compatibility path",
        "64 B/cycle",
        "8 B/cycle",
        "ideal ready-memory RTL/interface rates, not board DDR throughput.",
    ),
    "slvc_dma_ppa_implementation.svg": (
        "Throughput, Writer PPA, and C2B4 implementation",
        "Writer-only paired DC",
        "32 -&gt; 7 bit",
        "-7.97%",
        "-15.84%",
        "1.5 ns Nangate45 DC OOC",
        "Writer-only scope",
        "Interface throughput",
        "64 B/cycle",
        "8 B/cycle",
        "100% W utilization",
        "peak outstanding 4",
        "ready-memory scope",
        "C2B4 implementation chain",
        "2 channels x 4 KiB",
        "register-expanded",
        "550 MHz DC handoff",
        "450 MHz OpenROAD",
        "OpenRCX",
        "PrimeTime",
        "+0.041322 / +0.000341 ns",
        "1.04207 mm2",
        "Route DRC / antenna / electrical = 0",
        "Three independent evidence scopes; not one complete-DMA PPA result.",
    ),
}


class ShowcaseAssetError(RuntimeError):
    pass


def _fail(message):
    raise ShowcaseAssetError(message)


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _png_identity(path):
    payload = path.read_bytes()
    if payload[:8] != b"\x89PNG\r\n\x1a\n":
        _fail("invalid PNG signature: {}".format(path))
    offset = 8
    chunks = []
    ihdr = None
    while offset < len(payload):
        if len(payload) - offset < 12:
            _fail("truncated PNG chunk header: {}".format(path))
        length = struct.unpack(">I", payload[offset:offset + 4])[0]
        chunk_end = offset + 12 + length
        if chunk_end > len(payload):
            _fail("truncated PNG chunk payload: {}".format(path))
        raw_kind = payload[offset + 4:offset + 8]
        try:
            kind = raw_kind.decode("ascii")
        except UnicodeDecodeError:
            _fail("non-ASCII PNG chunk type: {}".format(path))
        if not re.fullmatch(r"[A-Za-z]{4}", kind):
            _fail("invalid PNG chunk type {}: {}".format(kind, path))
        data = payload[offset + 8:offset + 8 + length]
        stored_crc = struct.unpack(">I", payload[offset + 8 + length:chunk_end])[0]
        actual_crc = zlib.crc32(raw_kind)
        actual_crc = zlib.crc32(data, actual_crc) & 0xffffffff
        if stored_crc != actual_crc:
            _fail("PNG chunk CRC mismatch for {}: {}".format(kind, path))
        chunks.append(kind)
        if kind == "IHDR":
            if ihdr is not None or length != 13:
                _fail("invalid or duplicate PNG IHDR: {}".format(path))
            ihdr = struct.unpack(">IIBBBBB", data)
        if kind == "IEND" and length != 0:
            _fail("PNG IEND chunk must be empty: {}".format(path))
        offset = chunk_end
        if kind == "IEND":
            break
    if offset != len(payload):
        _fail("PNG has trailing data after IEND: {}".format(path))
    if not chunks or chunks[0] != "IHDR" or chunks[-1] != "IEND":
        _fail("PNG chunk order must start with IHDR and end with IEND: {}".format(path))
    if chunks.count("IHDR") != 1 or chunks.count("IEND") != 1:
        _fail("PNG must contain one IHDR and one IEND: {}".format(path))
    if set(chunks) != {"IHDR", "IDAT", "IEND"}:
        _fail("PNG contains forbidden metadata or ancillary chunks: {} {}".format(
            path, ",".join(chunks)
        ))
    idat_positions = [index for index, kind in enumerate(chunks) if kind == "IDAT"]
    if not idat_positions or idat_positions != list(range(
            idat_positions[0], idat_positions[-1] + 1)):
        _fail("PNG IDAT chunks must be present and contiguous: {}".format(path))
    width, height, bit_depth, color_type, compression, filtering, interlace = ihdr
    if (bit_depth, color_type, compression, filtering, interlace) != (8, 2, 0, 0, 0):
        _fail("PNG must be non-interlaced 8-bit RGB: {}".format(path))
    return {
        "sha256": hashlib.sha256(payload).hexdigest(),
        "size_bytes": len(payload),
        "width": width,
        "height": height,
        "chunks": tuple(chunks),
    }


def _validate_binary_assets(root):
    for relative, expected in BINARY_ASSETS.items():
        path = root / relative
        if not path.is_file():
            _fail("missing binary showcase asset: {}".format(relative))
        actual = _png_identity(path)
        for field in ("sha256", "size_bytes", "width", "height"):
            if actual[field] != expected[field]:
                _fail("binary showcase {} mismatch for {}: expected={} actual={}".format(
                    field, relative, expected[field], actual[field]
                ))


def _decode_scalar(raw):
    if raw.startswith('"'):
        try:
            value = json.loads(raw)
        except (TypeError, ValueError) as error:
            _fail("invalid quoted claim scalar: {}".format(error))
        if not isinstance(value, str):
            _fail("quoted claim scalar must be text")
        return value
    if raw == "true":
        return True
    if raw == "false":
        return False
    return raw


def _load_claims(path):
    claims = {}
    current_id = None
    current = None
    current_list = None
    for line_number, raw in enumerate(
            path.read_text(encoding="utf-8").splitlines(), 1):
        start = CLAIM_START.match(raw)
        if start:
            current_id = start.group(1)
            if current_id in claims:
                _fail("duplicate claim id: {}".format(current_id))
            current = {"id": current_id}
            claims[current_id] = current
            current_list = None
            continue
        if current is None:
            continue
        list_item = CLAIM_LIST_ITEM.match(raw)
        if list_item:
            if current_list is None:
                _fail("unexpected claim list item at line {}".format(line_number))
            current[current_list].append(_decode_scalar(list_item.group(1)))
            continue
        field = CLAIM_FIELD.match(raw)
        if not field:
            continue
        key, value = field.groups()
        if key in current:
            _fail("duplicate field {} in claim {}".format(key, current_id))
        current_list = None
        if not value:
            if key != "evidence":
                _fail("unsupported empty claim field: {}".format(key))
            current[key] = []
            current_list = key
        else:
            current[key] = _decode_scalar(value)
    return claims


def _require_claim(claims, claim_id, expected_scope):
    claim = claims.get(claim_id)
    if claim is None:
        _fail("missing required claim: {}".format(claim_id))
    expected = {"id": claim_id}
    expected.update(expected_scope)
    if claim != expected:
        fields = sorted(
            key for key in set(claim).union(expected)
            if claim.get(key) != expected.get(key)
        )
        _fail("claim scope identity mismatch: {} fields={}".format(
            claim_id, ",".join(fields)
        ))
    return claim


def _section_scalars(path, section):
    lines = path.read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index(section + ":") + 1
    except ValueError:
        _fail("missing YAML section {} in {}".format(section, path))
    values = {}
    for raw in lines[start:]:
        if raw and not raw.startswith(" "):
            break
        match = re.match(r"^  ([A-Za-z0-9_]+):\s*(.+)$", raw)
        if match:
            key, value = match.groups()
            if key in values:
                _fail("duplicate {}.{}".format(section, key))
            values[key] = value.strip().strip('"')
    return values


def _inline_record(path, section, key):
    lines = path.read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index(section + ":") + 1
    except ValueError:
        _fail("missing YAML section {} in {}".format(section, path))
    prefix = "  {}: {{".format(key)
    matches = [raw for raw in lines[start:] if raw.startswith(prefix)]
    if len(matches) != 1 or not matches[0].endswith("}"):
        _fail("missing or duplicate inline record {}.{}".format(section, key))
    body = matches[0][len(prefix):-1]
    values = {}
    for item in body.split(","):
        parts = item.strip().split(":", 1)
        if len(parts) != 2 or parts[0].strip() in values:
            _fail("invalid inline record {}.{}".format(section, key))
        values[parts[0].strip()] = parts[1].strip()
    return values


def _load_writer_metrics(path, writer_claim):
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        if tuple(reader.fieldnames or ()) != COMPARISON_HEADER:
            _fail("comparisons.csv header mismatch")
        selected = {}
        for row in reader:
            if (row["evaluation_id"] == "writer_component" and
                    row["claim_id"] == WRITER_CLAIM):
                metric = row["metric"]
                if metric in selected:
                    _fail("duplicate Writer comparison metric: {}".format(metric))
                selected[metric] = row

    required = {"total_cell_area", "combinational_area"}
    if not required.issubset(selected):
        _fail("Writer comparison metrics are incomplete")
    for metric in required:
        row = selected[metric]
        if (row["baseline_point_id"] != "writer_component_w0" or
                row["candidate_point_id"] != "writer_component_w1"):
            _fail("Writer comparison point identity mismatch")
        try:
            baseline = Decimal(row["baseline"])
            candidate = Decimal(row["candidate"])
            delta = Decimal(row["delta"])
            delta_percent = Decimal(row["delta_percent"])
        except (ArithmeticError, ValueError):
            _fail("Writer comparison contains a non-decimal value")
        if (not all(value.is_finite() for value in (
                baseline, candidate, delta, delta_percent)) or baseline == 0):
            _fail("Writer comparison contains an invalid numeric value")
        expected_delta = candidate - baseline
        expected_percent = (
            Decimal(100) * expected_delta / baseline
        ).quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN)
        if delta != expected_delta or delta_percent != expected_percent:
            _fail("Writer comparison formula mismatch: {}".format(metric))

    match = WRITER_STATEMENT.fullmatch(str(writer_claim.get("statement", "")))
    if not match:
        _fail("Writer claim statement mismatch")
    period, claim_total, claim_comb = (Decimal(value) for value in match.groups())
    csv_total = Decimal(selected["total_cell_area"]["delta_percent"])
    csv_comb = Decimal(selected["combinational_area"]["delta_percent"])
    if csv_total != -claim_total or csv_total != Decimal(writer_claim["value"]):
        _fail("Writer total-area CSV and claim mismatch")
    if csv_comb != -claim_comb or period != Decimal("1.500"):
        _fail("Writer combinational-area or period identity mismatch")
    return period, csv_total, csv_comb


def _validate_rtl_contract(root):
    wrapper = (root / WRAPPER_PATH).read_text(encoding="utf-8")
    frame_wrapper = (root / FRAME_WRAPPER_PATH).read_text(encoding="utf-8")
    rx_top = (root / RX_TOP_PATH).read_text(encoding="utf-8")
    profile = (root / C2B4_PROFILE_PATH).read_text(encoding="utf-8")
    required_wrapper = (
        "parameter integer SL_DATA_WIDTH = 512",
        "output     [63:0]  m_axi_wdata",
        "frame_dma_wrapper",
    )
    required_frame_wrapper = (
        "frame_dma_rx_top",
    )
    required_rx = (
        "`ifdef DMA_RX_WIDE_PAYLOAD_PROFILE",
        "dma_rx_payload_cdc_bridge",
        "dma_rx_payload_serializer_512_to_64",
        "dma_axi_write_engine_512",
    )
    required_profile = (
        "profile_id: dma_rx512_reg_c2_b4_m2_sp64",
        "channels: 2",
        "memory_axi_width: 512",
        "max_burst_beats: 16",
        "max_outstanding: 4",
    )
    for path, text, required in (
            (WRAPPER_PATH, wrapper, required_wrapper),
            (FRAME_WRAPPER_PATH, frame_wrapper, required_frame_wrapper),
            (RX_TOP_PATH, rx_top, required_rx),
            (C2B4_PROFILE_PATH, profile, required_profile)):
        for fragment in required:
            if fragment not in text:
                _fail("{} is missing architecture token {}".format(path, fragment))


def _extract_metrics(root):
    claims = _load_claims(root / CLAIMS_PATH)
    _require_claim(claims, ADMISSION_CLAIM, ADMISSION_SCOPE)
    writer = _require_claim(claims, WRITER_CLAIM, WRITER_SCOPE)
    _require_claim(claims, CDC_REGRESSION_CLAIM, CDC_REGRESSION_SCOPE)
    throughput = _require_claim(claims, THROUGHPUT_CLAIM, THROUGHPUT_SCOPE)
    c2b4 = _require_claim(claims, C2B4_CLAIM, C2B4_SCOPE)
    _validate_rtl_contract(root)

    period, writer_total, writer_comb = _load_writer_metrics(
        root / COMPARISONS_PATH, writer
    )

    same = _inline_record(root / CDC_EVIDENCE_PATH, "throughput_ideal_memory", "same_clock_512")
    async64 = _inline_record(root / CDC_EVIDENCE_PATH, "throughput_ideal_memory", "async64")
    async512 = _inline_record(root / CDC_EVIDENCE_PATH, "throughput_ideal_memory", "async512")
    if same != {
            "bytes": "1048576", "bytes_per_cycle": "64",
            "w_utilization_percent": "100", "peak_outstanding": "4"}:
        _fail("same-clock 512 throughput evidence mismatch")
    if async512 != {
            "bytes": "1048576", "bytes_per_mem_cycle": "64",
            "w_utilization_percent": "100", "peak_outstanding": "4"}:
        _fail("async512 throughput evidence mismatch")
    required_async64 = {
        "bytes": "1048576", "bytes_per_mem_cycle": "8",
        "w_utilization_percent": "100", "peak_outstanding": "4",
        "aw_bursts": "8192", "aw_beats": "131072",
        "average_burst_beats": "16", "planner_bubble_cycles": "8192",
        "aw_wait_cycles": "122825",
    }
    if async64 != required_async64:
        _fail("async64 throughput evidence mismatch")
    if throughput["value"] != "100" or "four peak outstanding" not in throughput["configuration"]:
        _fail("throughput claim identity mismatch")

    match = C2B4_STATEMENT.fullmatch(str(c2b4.get("statement", "")))
    if not match:
        _fail("C2B4 claim statement mismatch")
    dc_mhz, route_mhz = (int(value) for value in match.groups())
    profile = _section_scalars(root / C2B4_EVIDENCE_PATH, "profile")
    dc = _section_scalars(root / C2B4_EVIDENCE_PATH, "dc_handoff_550mhz")
    physical = _section_scalars(root / C2B4_EVIDENCE_PATH, "physical_450mhz")
    pt = _section_scalars(root / C2B4_EVIDENCE_PATH, "primetime_450mhz")
    if (profile.get("id") != c2b4["profile"] or profile.get("channels") != "2" or
            profile.get("memory_mode") != "register_expanded" or
            dc.get("status") != "verified" or physical.get("status") != "verified" or
            pt.get("status") != "verified" or (dc_mhz, route_mhz) != (550, 450)):
        _fail("C2B4 profile or stage identity mismatch")
    setup_wns = Decimal(pt.get("setup_wns_ns", "NaN"))
    hold_wns = Decimal(pt.get("hold_wns_ns", "NaN"))
    area_mm2 = Decimal(physical.get("standard_cell_area_um2", "NaN")) / Decimal(1000000)
    zero_fields = (
        (physical, "detail_route_drc_count"),
        (physical, "antenna_violation_count"),
        (physical, "electrical_violation_count"),
        (pt, "setup_violation_count"),
        (pt, "hold_violation_count"),
        (pt, "electrical_violation_count"),
        (pt, "min_pulse_width_violation_count"),
        (pt, "min_period_violation_count"),
    )
    if any(Decimal(record.get(field, "NaN")) != 0 for record, field in zero_fields):
        _fail("C2B4 physical or timing violation count is nonzero")
    if (setup_wns != Decimal("0.041322") or hold_wns != Decimal("0.000341") or
            area_mm2 != Decimal("1.04207") or Decimal(c2b4["value"]) != hold_wns):
        _fail("C2B4 timing or area evidence mismatch")

    return {
        "writer_period": period.quantize(Decimal("0.0")),
        "writer_total": writer_total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
        "writer_comb": writer_comb.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
        "wide_bytes": int(same["bytes_per_cycle"]),
        "async64_bytes": int(async64["bytes_per_mem_cycle"]),
        "w_utilization": int(same["w_utilization_percent"]),
        "peak_outstanding": int(same["peak_outstanding"]),
        "dc_mhz": dc_mhz,
        "route_mhz": route_mhz,
        "setup_wns": setup_wns,
        "hold_wns": hold_wns,
        "area_mm2": area_mm2,
        "physical_checks": 0,
    }


def _svg_document(title, desc, body):
    return """<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="{view_box}" preserveAspectRatio="{preserve}" role="img" aria-labelledby="title desc" data-theme-contract="mrtc-engineering-report">
  <title id="title">{title}</title>
  <desc id="desc">{desc}</desc>
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="#6b7280"/></marker>
    <marker id="arrow-blue" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="#1456a0"/></marker>
  </defs>
  <style>{style}</style>
  <rect width="1600" height="1000" fill="#ffffff"/>
{body}</svg>
""".format(
        width=CANVAS_WIDTH,
        height=CANVAS_HEIGHT,
        view_box=VIEW_BOX,
        preserve=PRESERVE_ASPECT_RATIO,
        title=title,
        desc=desc,
        style=REPORT_STYLE,
        body=body,
    ).encode("ascii")


def _report_header(title, subtitle):
    return """  <g data-layout-region="page-header">
    <rect data-layout-box="true" x="30" y="18" width="1540" height="112" fill="none" stroke="none"/>
    <text x="40" y="60" class="title">{title}</text>
    <text x="40" y="98" class="subtitle">{subtitle}</text>
    <line x1="40" y1="124" x2="1560" y2="124" class="rule"/>
  </g>
""".format(title=title, subtitle=subtitle)


def _overview_svg(_metrics):
    body = _report_header(
        "SLVC DMA shared-link system overview",
        "Frame-aware admission, hybrid buffering, memory movement, and owner-last software completion.",
    ) + """  <g data-layout-region="overview-source">
    <rect data-layout-box="true" x="50" y="165" width="280" height="410" class="box"/>
    <rect x="50" y="165" width="280" height="58" class="panel-header"/>
    <text x="190" y="203" text-anchor="middle" class="table-head">Source Boundaries</text>
    <text x="72" y="265" class="body-bold">Aurora / native SHDR64</text>
    <text x="72" y="305" class="body">optional UDP adapter</text>
    <text x="72" y="345" class="body">local endpoint / MCF</text>
    <line x1="72" y1="372" x2="308" y2="372" class="thin"/>
    <text x="72" y="415" class="body-bold">Control plane</text>
    <text x="72" y="455" class="body">AXI4-Lite</text>
    <text x="72" y="495" class="body">PAUSE / RESUME</text>
    <text x="72" y="535" class="small">source-specific adaptation</text>
  </g>
  <g data-layout-region="overview-link">
    <rect data-layout-box="true" x="355" y="165" width="280" height="410" class="box-blue"/>
    <rect x="355" y="165" width="280" height="58" class="panel-header"/>
    <text x="495" y="203" text-anchor="middle" class="table-head">SHDR64 Shared Link</text>
    <text x="377" y="265" class="body-bold">512-bit segment stream</text>
    <text x="377" y="305" class="body">64-byte frame header</text>
    <text x="377" y="345" class="body">flow_id + payload length</text>
    <line x1="377" y1="372" x2="613" y2="372" class="thin"/>
    <text x="377" y="415" class="body-bold">Elastic ingress</text>
    <text x="377" y="455" class="body">header / payload ordering</text>
    <text x="377" y="495" class="body">CRC and metadata context</text>
    <text x="377" y="535" class="small">one shared-link contract</text>
  </g>
  <g data-layout-region="overview-admission">
    <rect data-layout-box="true" x="660" y="165" width="280" height="410" class="box-blue"/>
    <rect x="660" y="165" width="280" height="58" class="panel-header"/>
    <text x="800" y="203" text-anchor="middle" class="table-head">Channel Admission</text>
    <text x="682" y="265" class="body-bold">flow_id match</text>
    <text x="682" y="305" class="body">up to 16 contexts</text>
    <text x="682" y="345" class="body">Ingress availability</text>
    <text x="682" y="385" class="body">DDR Ring free space</text>
    <text x="682" y="425" class="body">CQ credit</text>
    <line x1="682" y1="452" x2="918" y2="452" class="thin"/>
    <text x="682" y="495" class="body-bold">Joint reserve / reject</text>
    <text x="682" y="535" class="small">before frame visibility</text>
  </g>
  <g data-layout-region="overview-buffering">
    <rect data-layout-box="true" x="965" y="165" width="280" height="410" class="box-blue"/>
    <rect x="965" y="165" width="280" height="58" class="panel-header"/>
    <text x="1105" y="203" text-anchor="middle" class="table-head">Hybrid Buffering</text>
    <text x="987" y="265" class="body-bold">Fixed ingress</text>
    <text x="987" y="305" class="body">dedicated per-channel space</text>
    <text x="987" y="355" class="body-bold">Shared Frame Pool</text>
    <text x="987" y="395" class="body">block free list + chain</text>
    <line x1="987" y1="422" x2="1223" y2="422" class="thin"/>
    <text x="987" y="465" class="body-bold">Whole-frame commit</text>
    <text x="987" y="505" class="body">frame-locked selection</text>
    <text x="987" y="545" class="small">no source interleave</text>
  </g>
  <g data-layout-region="overview-ownership" data-stage="DDR / Completion Ownership">
    <rect data-layout-box="true" x="1270" y="165" width="280" height="410" class="box-blue"/>
    <rect x="1270" y="165" width="280" height="58" class="panel-header"/>
    <text x="1410" y="192" text-anchor="middle" class="table-head">DDR / Completion</text>
    <text x="1410" y="213" text-anchor="middle" class="table-head">Ownership</text>
    <text x="1292" y="265" class="body-bold">AXI4 memory backend</text>
    <text x="1292" y="305" class="body">AW / W / B progress</text>
    <text x="1292" y="345" class="body">4 KiB split + completion</text>
    <line x1="1292" y1="372" x2="1528" y2="372" class="thin"/>
    <text x="1292" y="415" class="body-bold">CQE body first</text>
    <text x="1292" y="455" class="body">CQ owner-last</text>
    <text x="1292" y="495" class="body">IRQ publication</text>
    <text x="1292" y="535" class="small">release frame ownership</text>
  </g>
  <path d="M330 370 H355" class="flow"/>
  <path d="M635 370 H660" class="flow"/>
  <path d="M940 370 H965" class="flow"/>
  <path d="M1245 370 H1270" class="flow"/>
  <g data-layout-region="overview-contract">
    <rect data-layout-box="true" x="50" y="635" width="1500" height="285" class="box"/>
    <rect x="50" y="635" width="1500" height="56" class="panel-header"/>
    <text x="800" y="672" text-anchor="middle" class="table-head">End-to-End Contract / Boundary</text>
    <line x1="550" y1="691" x2="550" y2="920" class="thin"/>
    <line x1="1050" y1="691" x2="1050" y2="920" class="thin"/>
    <text x="78" y="732" class="panel-title">Stream contract</text>
    <text x="78" y="772" class="body">SHDR64 header precedes payload</text>
    <text x="78" y="812" class="body">frame admission is atomic</text>
    <text x="78" y="852" class="body">committed sources do not interleave</text>
    <text x="578" y="732" class="panel-title">Software ownership</text>
    <text x="578" y="772" class="body">DDR response precedes CQ publish</text>
    <text x="578" y="812" class="body">CQ body precedes owner / valid</text>
    <text x="578" y="852" class="body">IRQ precedes frame release</text>
    <text x="1078" y="732" class="panel-title">Verification boundary</text>
    <text x="1078" y="772" class="body">directed architecture regressions</text>
    <text x="1078" y="812" class="body">profile-specific PPA evidence</text>
    <text x="1078" y="852" class="body">no complete-DMA PPA transfer</text>
  </g>
"""
    return _svg_document(
        "SLVC DMA shared-link system overview",
        "Five stages connect source adaptation, SHDR64 framing, channel admission, hybrid buffering, and DDR plus completion ownership.",
        body,
    )


def _virtual_channel_svg(_metrics):
    body = _report_header(
        "Virtual-channel buffering and frame isolation",
        "Per-flow context chooses dedicated or shared capacity; only committed frames reach the locked output selector.",
    ) + """  <g data-layout-region="virtual-context">
    <rect data-layout-box="true" x="50" y="165" width="460" height="620" class="box"/>
    <rect x="50" y="165" width="460" height="58" class="panel-header"/>
    <text x="280" y="203" text-anchor="middle" class="table-head">Context / Admission</text>
    <text x="80" y="270" class="panel-title">SHDR64 context</text>
    <text x="80" y="315" class="body">flow_id -&gt; channel table</text>
    <text x="80" y="355" class="body">ingress + ring + CQ checks</text>
    <text x="80" y="395" class="body">reserve before acceptance</text>
    <line x1="80" y1="430" x2="480" y2="430" class="thin"/>
    <text x="80" y="480" class="body-bold">Accept</text>
    <text x="80" y="520" class="body">select Fixed or Shared target</text>
    <text x="80" y="570" class="body-bold">Reject / Drop</text>
    <text x="80" y="610" class="body">no partial frame visibility</text>
    <line x1="80" y1="650" x2="480" y2="650" class="thin"/>
    <text x="80" y="700" class="small">AXI4-Lite context configuration</text>
    <text x="80" y="735" class="small">per-channel resource accounting</text>
  </g>
  <g data-layout-region="virtual-storage">
    <rect data-layout-box="true" x="570" y="165" width="460" height="620" class="box-blue"/>
    <rect x="570" y="165" width="460" height="58" class="panel-header"/>
    <text x="800" y="203" text-anchor="middle" class="table-head">Fixed / Shared Storage</text>
    <rect x="605" y="265" width="390" height="180" class="box"/>
    <text x="635" y="305" class="panel-title">Fixed ingress</text>
    <text x="635" y="350" class="body-bold">dedicated capacity</text>
    <text x="635" y="390" class="body">per-channel frame collection</text>
    <text x="635" y="425" class="small">independent storage ownership</text>
    <rect x="605" y="485" width="390" height="210" class="box-blue"/>
    <text x="635" y="525" class="panel-title">Shared Frame Pool</text>
    <text x="635" y="570" class="body-bold">free-list capacity</text>
    <text x="635" y="610" class="body">block queue + hardware chain</text>
    <text x="635" y="650" class="body">whole-frame commit / release</text>
    <text x="635" y="680" class="small">dynamic capacity across channels</text>
    <text x="605" y="750" class="table-strong">Only committed frames are visible</text>
  </g>
  <g data-layout-region="virtual-selector">
    <rect data-layout-box="true" x="1090" y="165" width="460" height="620" class="box-blue"/>
    <rect x="1090" y="165" width="460" height="58" class="panel-header"/>
    <text x="1320" y="203" text-anchor="middle" class="table-head">Selection / Output</text>
    <text x="1120" y="275" class="panel-title">Source selector</text>
    <text x="1120" y="320" class="body-bold">Selector locks one frame</text>
    <text x="1120" y="360" class="body">Fixed and Shared arbitrate</text>
    <text x="1120" y="400" class="body">no source interleave</text>
    <line x1="1120" y1="435" x2="1520" y2="435" class="thin"/>
    <text x="1120" y="485" class="panel-title">AXI / CQ</text>
    <text x="1120" y="530" class="body">frame remains owned through B</text>
    <text x="1120" y="570" class="body">CQE body before owner / valid</text>
    <text x="1120" y="610" class="body">IRQ then frame release</text>
    <line x1="1120" y1="650" x2="1520" y2="650" class="thin"/>
    <text x="1120" y="700" class="small">per-channel DDR Ring destination</text>
    <text x="1120" y="735" class="small">software-visible completion ownership</text>
  </g>
  <path d="M510 460 H570" class="flow-blue"/>
  <path d="M1030 460 H1090" class="flow-blue"/>
  <g data-layout-region="virtual-caveat">
    <rect data-layout-box="true" x="50" y="830" width="1500" height="105" class="box"/>
    <text x="78" y="872" class="body-bold">Bounded evidence:</text>
    <text x="270" y="872" class="body">channel 0 full</text>
    <text x="450" y="872" class="body">while channel 1 progresses and publishes its CQE.</text>
    <text x="78" y="910" class="small">Directed scenario only; not universal non-blocking behavior or formal channel-isolation proof.</text>
  </g>
"""
    return _svg_document(
        "Virtual-channel buffering and frame isolation",
        "The diagram separates SHDR64 admission context, Fixed and Shared capacity, and frame-locked AXI plus CQ output ownership.",
        body,
    )


def _frame_lifecycle_svg(_metrics):
    body = _report_header(
        "SHDR64 frame lifecycle and ownership boundaries",
        "Header control and payload data meet at one admission gate before collection, commit, memory completion, and release.",
    ) + """  <g id="header-control-path" data-path="header-control" data-layout-region="lifecycle-control">
    <rect data-layout-box="true" x="50" y="160" width="680" height="400" class="box"/>
    <rect x="50" y="160" width="680" height="58" class="panel-header"/>
    <text x="390" y="198" text-anchor="middle" class="table-head">Header / Admission Control</text>
    <rect id="header-beat" data-control-order="1" x="90" y="245" width="260" height="65" class="box-blue"/>
    <text x="220" y="286" text-anchor="middle" class="body-bold">Header beat</text>
    <rect id="parse-crc" data-control-order="2" x="410" y="245" width="270" height="65" class="box"/>
    <text x="545" y="286" text-anchor="middle" class="body-bold">Parse / CRC</text>
    <rect id="match-context" data-control-order="3" x="90" y="350" width="260" height="65" class="box"/>
    <text x="220" y="391" text-anchor="middle" class="body-bold">Match Context</text>
    <rect id="check-resources" data-control-order="4" x="410" y="340" width="270" height="85" class="box"/>
    <text x="545" y="376" text-anchor="middle" class="body-bold">Check Ingress + Ring + CQ</text>
    <text x="545" y="405" text-anchor="middle" class="small">joint availability</text>
    <rect id="reserve-reject" data-control-order="5" x="230" y="465" width="320" height="65" class="box-blue"/>
    <text x="390" y="506" text-anchor="middle" class="body-bold">Reserve / Reject</text>
    <path id="header-to-parse" d="M350 278 H410" class="flow"/>
    <path id="parse-to-match" d="M545 310 V330 H220 V350" class="flow"/>
    <path id="match-to-check" d="M350 382 H410" class="flow"/>
    <path id="check-to-reserve" d="M545 425 V445 H390 V465" class="flow"/>
    <path id="reject-drop" d="M550 498 H610" class="flow"/>
    <text x="620" y="505" class="small orange">Reject / Drop</text>
  </g>
  <g id="payload-data-path" data-path="payload" data-layout-region="lifecycle-payload">
    <rect data-layout-box="true" x="870" y="160" width="680" height="400" class="box"/>
    <rect x="870" y="160" width="680" height="58" class="panel-header"/>
    <text x="1210" y="198" text-anchor="middle" class="table-head">512-bit Shared-link RX Payload</text>
    <rect id="payload-beats" x="1010" y="265" width="400" height="95" class="box-blue"/>
    <text x="1210" y="306" text-anchor="middle" class="body-bold">Payload beats</text>
    <text x="1210" y="337" text-anchor="middle" class="small">ordered behind the accepted Header beat</text>
    <text x="1210" y="425" text-anchor="middle" class="body">Elastic input retains frame ordering</text>
    <text x="1210" y="468" text-anchor="middle" class="body">No unconditional path into storage</text>
    <text x="1210" y="515" text-anchor="middle" class="small">Payload proceeds only when admission resolves</text>
  </g>
  <g id="admission-gate" data-requires="header-control,payload" data-layout-region="lifecycle-gate">
    <rect data-layout-box="true" x="50" y="610" width="250" height="86" class="box-blue"/>
    <text x="175" y="649" text-anchor="middle" class="panel-title">admission gate</text>
    <text x="175" y="679" text-anchor="middle" class="small">reserved frame only</text>
  </g>
  <path id="control-to-admission" data-connects="header-control-to-admission" d="M390 530 V580 H175 V610" class="flow-blue"/>
  <path id="payload-to-admission" data-connects="payload-to-admission" d="M1210 360 V580 H175 V610" class="flow-blue"/>
  <g data-layout-region="lifecycle-data-chain">
    <rect data-layout-box="true" x="330" y="580" width="1220" height="140" fill="none" stroke="none"/>
    <rect id="frame-collect" x="340" y="610" width="245" height="86" class="box-blue"/>
    <text x="462" y="649" text-anchor="middle" class="body-bold">Fixed / Shared collect</text>
    <text x="462" y="679" text-anchor="middle" class="small">whole frame remains private</text>
    <line id="commit-boundary" data-boundary-order="1" x1="625" y1="585" x2="625" y2="720" class="boundary"/>
    <text x="642" y="606" class="table-strong green">WHOLE-FRAME COMMIT</text>
    <rect id="frame-locked-source" x="670" y="610" width="245" height="86" class="box-blue"/>
    <text x="792" y="649" text-anchor="middle" class="body-bold">Frame-locked Source</text>
    <text x="792" y="679" text-anchor="middle" class="small">no source interleave</text>
    <rect id="memory-backend" x="960" y="610" width="245" height="86" class="box"/>
    <text x="1082" y="649" text-anchor="middle" class="body-bold">Memory Backend</text>
    <text x="1082" y="679" text-anchor="middle" class="small">burst planning + AXI</text>
    <rect id="ddr-b-response" x="1250" y="610" width="300" height="86" class="box"/>
    <text x="1400" y="649" text-anchor="middle" class="body-bold">DDR / B response</text>
    <text x="1400" y="679" text-anchor="middle" class="small">memory completion</text>
    <path d="M300 653 H340" class="flow-blue"/>
    <path d="M585 653 H605" class="flow-blue"/>
    <path d="M645 653 H670" class="flow-blue"/>
    <path d="M915 653 H960" class="flow-blue"/>
    <path d="M1205 653 H1250" class="flow-blue"/>
  </g>
  <g data-layout-region="lifecycle-completion">
    <rect data-layout-box="true" x="350" y="790" width="1200" height="120" fill="none" stroke="none"/>
    <rect id="cqe-body" data-completion-order="1" x="390" y="805" width="250" height="82" class="box"/>
    <text x="515" y="842" text-anchor="middle" class="body-bold">CQE body</text>
    <text x="515" y="872" text-anchor="middle" class="small">written first</text>
    <rect id="owner-valid" data-completion-order="2" x="700" y="805" width="270" height="82" class="box-blue"/>
    <text x="835" y="842" text-anchor="middle" class="body-bold">owner / valid + IRQ</text>
    <text x="835" y="872" text-anchor="middle" class="small">published after body</text>
    <line id="release-boundary" data-boundary-order="2" x1="1015" y1="780" x2="1015" y2="915" class="boundary"/>
    <rect id="release-frame-ownership" data-completion-order="3" x="1060" y="805" width="360" height="82" class="box"/>
    <text x="1240" y="842" text-anchor="middle" class="body-bold">release frame ownership</text>
    <text x="1240" y="872" text-anchor="middle" class="small">return source capacity</text>
    <path d="M1400 696 V755 H515 V805" class="flow-blue"/>
    <path d="M640 846 H700" class="flow-blue"/>
    <path d="M970 846 H1060" class="flow-blue"/>
  </g>
  <g data-layout-region="lifecycle-footnote">
    <rect data-layout-box="true" x="40" y="940" width="1520" height="45" fill="none" stroke="none"/>
    <text x="40" y="970" class="foot">Commit Boundary: incomplete frames are invisible. Release Boundary: storage remains owned through AXI completion and CQ owner-last publication.</text>
  </g>
"""
    return _svg_document(
        "SHDR64 frame lifecycle and ownership boundaries",
        "Header control and payload data converge at a fail-closed admission gate before whole-frame commit; completion publishes the CQ body before owner and releases storage last.",
        body,
    )


def _memory_profiles_svg(metrics):
    body = _report_header(
        "RX memory profiles and CDC boundaries",
        "Committed-frame ownership stays in aclk while only Command, ordered Payload, and Tagged Completion cross asynchronous profiles.",
    ) + """  <g data-layout-region="memory-table-header">
    <rect data-layout-box="true" x="40" y="150" width="1520" height="58" class="panel-header"/>
    <text x="60" y="187" class="table-head">Profile / measured rate</text>
    <text x="300" y="177" class="table-head">Committed Frame Source / Ownership</text>
    <text x="300" y="200" class="table-head">(aclk)</text>
    <text x="650" y="187" class="table-head">CDC transaction boundary</text>
    <text x="1010" y="187" class="table-head">Writer domain</text>
    <text x="1320" y="187" class="table-head">AXI Memory Interface / DDR</text>
  </g>
  <g id="profile-legacy64" data-profile="legacy64" data-layout-region="memory-legacy64">
    <rect data-layout-box="true" x="40" y="208" width="1520" height="150" class="box"/>
    <text x="60" y="250" class="panel-title">Legacy64</text>
    <text x="60" y="290" class="small">not measured in this matrix</text>
    <text x="60" y="324" class="small">64-bit compatibility path</text>
    <text x="300" y="270" class="body">Committed legacy frame source</text>
    <text x="300" y="310" class="small">ownership retained through completion</text>
    <text x="650" y="285" class="body">No RX payload CDC</text>
    <text x="1010" y="270" class="body">64-bit compatibility writer @ aclk</text>
    <text x="1010" y="310" class="small">same clock as source</text>
    <text x="1340" y="285" class="body">64-bit memory interface</text>
  </g>
  <g id="profile-same-clock512" data-profile="same-clock512" data-cdc="bypass" data-layout-region="memory-same512">
    <rect data-layout-box="true" x="40" y="358" width="1520" height="150" class="box-blue"/>
    <text x="60" y="400" class="panel-title">Same-clock512</text>
    <text x="60" y="448" class="metric">{wide_bytes} B/cycle</text>
    <text x="300" y="420" class="body">Committed 512-bit frame source</text>
    <text x="300" y="460" class="small">ownership retained through completion</text>
    <text x="650" y="435" class="body-bold">CDC bypass</text>
    <text x="1010" y="420" class="body">512-bit writer @ aclk</text>
    <text x="1010" y="460" class="small">same clock as source</text>
    <text x="1340" y="435" class="body">512-bit memory interface</text>
  </g>
  <g id="profile-async64" data-profile="async64" data-layout-region="memory-async64">
    <rect data-layout-box="true" x="40" y="508" width="1520" height="185" class="box"/>
    <text x="60" y="550" class="panel-title">Async64</text>
    <text x="60" y="598" class="metric">{async64_bytes} B/cycle</text>
    <text x="300" y="550" class="table">Command</text>
    <text x="300" y="595" class="table">Ordered Payload</text>
    <text x="300" y="640" class="table">Tagged Completion</text>
    <text x="625" y="535" class="small">Async FIFO boundary</text>
    <path id="async64-command" data-transaction="command" data-direction="aclk-to-mem-clk" d="M570 545 H940" class="flow-blue"/>
    <path id="async64-payload" data-transaction="ordered-payload" data-direction="aclk-to-mem-clk" d="M570 590 H940" class="flow-blue"/>
    <path id="async64-completion" data-transaction="tagged-completion" data-direction="mem-clk-to-aclk" d="M940 635 H570" class="flow-return"/>
    <line x1="760" y1="520" x2="760" y2="680" class="boundary"/>
    <text x="1010" y="550" class="body-bold">mem_clk: 512-to-64 serializer</text>
    <text x="1010" y="595" class="body">64-bit AXI writer</text>
    <text x="1010" y="640" class="small">completion returns before release</text>
    <text x="1340" y="570" class="body-bold">AW / W / B</text>
    <text x="1340" y="610" class="small">remain in mem_clk</text>
  </g>
  <g id="profile-async512" data-profile="async512" data-layout-region="memory-async512">
    <rect data-layout-box="true" x="40" y="693" width="1520" height="185" class="box-blue"/>
    <text x="60" y="735" class="panel-title">Async512</text>
    <text x="60" y="783" class="metric">{wide_bytes} B/cycle</text>
    <text x="300" y="735" class="table">Command</text>
    <text x="300" y="780" class="table">Ordered Payload</text>
    <text x="300" y="825" class="table">Tagged Completion</text>
    <text x="625" y="720" class="small">Async FIFO boundary</text>
    <path id="async512-command" data-transaction="command" data-direction="aclk-to-mem-clk" d="M570 730 H940" class="flow-blue"/>
    <path id="async512-payload" data-transaction="ordered-payload" data-direction="aclk-to-mem-clk" d="M570 775 H940" class="flow-blue"/>
    <path id="async512-completion" data-transaction="tagged-completion" data-direction="mem-clk-to-aclk" d="M940 820 H570" class="flow-return"/>
    <line x1="760" y1="705" x2="760" y2="865" class="boundary"/>
    <text x="1010" y="755" class="body-bold">mem_clk: 512-bit AXI writer</text>
    <text x="1010" y="800" class="small">completion returns before release</text>
    <text x="1340" y="755" class="body-bold">AW / W / B</text>
    <text x="1340" y="795" class="small">remain in mem_clk</text>
  </g>
  <g data-layout-region="memory-footnote">
    <rect data-layout-box="true" x="40" y="910" width="1520" height="65" fill="none" stroke="none"/>
    <text x="800" y="950" text-anchor="middle" class="foot">ideal ready-memory RTL/interface rates, not board DDR throughput.</text>
  </g>
""".format(**metrics)
    return _svg_document(
        "RX memory profiles and CDC boundaries",
        "Legacy and same-clock profiles stay in aclk; Async64 and Async512 cross command and payload toward mem_clk and tagged completion back toward aclk while AXI AW, W, and B stay in mem_clk.",
        body,
    )


def _ppa_svg(metrics):
    body = _report_header(
        "Throughput, Writer PPA, and C2B4 implementation",
        "Three evidence-bound result scopes are shown independently and must not be transferred to the complete DMA.",
    ) + """  <g data-layout-region="ppa-writer">
    <rect data-layout-box="true" x="50" y="165" width="480" height="690" class="box-blue"/>
    <rect x="50" y="165" width="480" height="60" class="panel-header"/>
    <text x="290" y="204" text-anchor="middle" class="table-head">A. Writer-only paired DC</text>
    <text x="80" y="275" class="section">Reservation accounting</text>
    <text x="80" y="330" class="metric">32 -&gt; 7 bit</text>
    <line x1="80" y1="365" x2="500" y2="365" class="thin"/>
    <text x="80" y="420" class="body">Total area</text>
    <text x="300" y="420" class="metric">{writer_total}%</text>
    <text x="80" y="475" class="body">Combinational area</text>
    <text x="300" y="475" class="metric">{writer_comb}%</text>
    <line x1="80" y1="515" x2="500" y2="515" class="thin"/>
    <text x="80" y="565" class="body-bold">1.5 ns Nangate45 DC OOC</text>
    <text x="80" y="610" class="body">same library + constraint</text>
    <text x="80" y="655" class="body">both points setup-closed</text>
    <line x1="80" y1="700" x2="500" y2="700" class="thin"/>
    <text x="80" y="755" class="table-strong">Writer-only scope</text>
    <text x="80" y="800" class="small">not C2B4 or complete-DMA area</text>
  </g>
  <g data-layout-region="ppa-throughput" data-throughput-contract="100% W utilization; peak outstanding 4">
    <rect data-layout-box="true" x="560" y="165" width="480" height="690" class="box-blue"/>
    <rect x="560" y="165" width="480" height="60" class="panel-header"/>
    <text x="800" y="204" text-anchor="middle" class="table-head">B. Interface throughput</text>
    <text x="590" y="275" class="section">Ready-memory profiles</text>
    <text x="590" y="330" class="body">Same-clock512</text>
    <text x="850" y="330" class="metric">{wide_bytes} B/cycle</text>
    <text x="590" y="385" class="body">Async64</text>
    <text x="850" y="385" class="metric">{async64_bytes} B/cycle</text>
    <text x="590" y="440" class="body">Async512</text>
    <text x="850" y="440" class="metric">{wide_bytes} B/cycle</text>
    <line x1="590" y1="480" x2="1010" y2="480" class="thin"/>
    <text x="590" y="535" class="body">W utilization</text>
    <text x="850" y="535" class="metric">{w_utilization}%</text>
    <text x="590" y="590" class="body">Peak outstanding</text>
    <text x="850" y="590" class="metric">{peak_outstanding}</text>
    <line x1="590" y1="635" x2="1010" y2="635" class="thin"/>
    <text x="590" y="690" class="table-strong">ready-memory scope</text>
    <text x="590" y="735" class="small">RTL/interface delivery only</text>
    <text x="590" y="780" class="small">not board DDR or 10G throughput</text>
  </g>
  <g data-layout-region="ppa-c2b4" data-implementation-chain="550 MHz DC handoff; 450 MHz OpenROAD; OpenRCX; PrimeTime">
    <rect data-layout-box="true" x="1070" y="165" width="480" height="690" class="box-blue"/>
    <rect x="1070" y="165" width="480" height="60" class="panel-header"/>
    <text x="1310" y="204" text-anchor="middle" class="table-head">C. C2B4 implementation chain</text>
    <text x="1100" y="270" class="section">2 channels x 4 KiB</text>
    <text x="1100" y="310" class="body">register-expanded RX512</text>
    <line x1="1100" y1="345" x2="1520" y2="345" class="thin"/>
    <text x="1100" y="395" class="body">Design Compiler</text>
    <text x="1325" y="395" class="table-strong">{dc_mhz} MHz DC handoff</text>
    <text x="1100" y="445" class="body">OpenROAD</text>
    <text x="1325" y="445" class="table-strong">{route_mhz} MHz</text>
    <text x="1100" y="495" class="body">OpenRCX</text>
    <text x="1325" y="495" class="body">same-run extraction</text>
    <text x="1100" y="545" class="body">PrimeTime</text>
    <text x="1325" y="545" class="body">internal nominal STA</text>
    <line x1="1100" y1="580" x2="1520" y2="580" class="thin"/>
    <text x="1100" y="630" class="body">Setup / hold WNS</text>
    <text x="1100" y="670" class="metric">+{setup_wns} / +{hold_wns} ns</text>
    <text x="1100" y="720" class="body">Standard-cell area</text>
    <text x="1325" y="720" class="table-strong">{area_mm2} mm2</text>
    <text x="1100" y="770" class="small">Route DRC / antenna / electrical = {physical_checks}</text>
    <text x="1100" y="810" class="small">C2B4 subsystem; not Fmax or signoff</text>
  </g>
  <g data-layout-region="ppa-footnote">
    <rect data-layout-box="true" x="50" y="900" width="1500" height="70" class="box"/>
    <text x="800" y="944" text-anchor="middle" class="body-bold">Three independent evidence scopes; not one complete-DMA PPA result.</text>
  </g>
""".format(**metrics)
    return _svg_document(
        "Throughput, Writer PPA, and C2B4 implementation",
        "Independent columns summarize Writer-only paired Design Compiler area, ideal-memory interface throughput, and a fixed C2B4 implementation chain.",
        body,
    )


def _validate_svg(path, payload, required):
    try:
        text = payload.decode("ascii")
    except UnicodeDecodeError:
        _fail("{} must be deterministic ASCII SVG".format(path))
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        _fail("invalid SVG {}: {}".format(path, error))
    expected_root = {
        "width": CANVAS_WIDTH,
        "height": CANVAS_HEIGHT,
        "viewBox": VIEW_BOX,
        "preserveAspectRatio": PRESERVE_ASPECT_RATIO,
        "role": "img",
        "data-theme-contract": "mrtc-engineering-report",
    }
    if any(root.attrib.get(key) != value for key, value in expected_root.items()):
        _fail("{} does not satisfy the exact theme canvas contract".format(path))
    children = {child.tag.rsplit("}", 1)[-1] for child in root}
    if not {"title", "desc"}.issubset(children):
        _fail("{} is missing title or desc".format(path))
    forbidden = (
        r"<(?:image|linearGradient|radialGradient|filter|foreignObject|script)\b",
        r"(?:href|xlink:href)\s*=\s*[\"'](?:https?:|data:)",
        r"base64",
        r"@font-face",
        r"drop-shadow",
        r"(?i)(?:(?<![A-Z])[A-Z]:[\\/]|/home/|\\\\)",
    )
    for pattern in forbidden:
        if re.search(pattern, text):
            _fail("{} contains forbidden SVG content".format(path))
    lowered = text.lower()
    for color in BANNED_COLORS:
        if color in lowered:
            _fail("{} contains forbidden pastel color {}".format(path, color))
    for element in root.iter():
        if "rx" in element.attrib or "ry" in element.attrib:
            _fail("{} contains rounded box geometry".format(path))
    for fragment in THEME_TOKENS:
        if fragment not in text:
            _fail("{} is missing theme token: {}".format(path, fragment))
    if "data-layout-region=" not in text or "data-layout-box=" not in text:
        _fail("{} is missing browser layout regions".format(path))
    for fragment in required:
        if fragment not in text:
            _fail("{} is missing required text: {}".format(path, fragment))


def _render_assets(metrics):
    return {
        OVERVIEW_ASSET: _overview_svg(metrics),
        VIRTUAL_CHANNEL_ASSET: _virtual_channel_svg(metrics),
        FRAME_LIFECYCLE_ASSET: _frame_lifecycle_svg(metrics),
        MEMORY_PROFILES_ASSET: _memory_profiles_svg(metrics),
        PPA_ASSET: _ppa_svg(metrics),
    }


def _asset_entry(root, path, payload, source, inputs, claim_ids):
    return {
        "path": path.as_posix(),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "format": "svg",
        "source": source,
        "generator": GENERATOR_PATH.as_posix(),
        "generator_sha256": _sha256(root / GENERATOR_PATH),
        "command": "python flows/scripts/generate_showcase_assets.py --root . --write",
        "inputs": [
            {"path": item.as_posix(), "sha256": _sha256(root / item)}
            for item in inputs
        ],
        "claim_ids": list(claim_ids),
    }


def _binary_asset_entry(path, identity):
    return {
        "path": path.as_posix(),
        "sha256": identity["sha256"],
        "format": "png",
        "size_bytes": identity["size_bytes"],
        "width": identity["width"],
        "height": identity["height"],
        "role": identity["role"],
        "source_type": "authored_binary_showcase",
        "numeric_authority": False,
        "source": (
            "pixel-preserving metadata-free authored showcase; tracked public "
            "Evidence remains the numeric authority"
        ),
        "claim_ids": [],
    }


def _expected_manifest(root, rendered):
    generated = [
        _asset_entry(
            root, OVERVIEW_ASSET, rendered[OVERVIEW_ASSET],
            "deterministically generated from tracked public integration RTL and architecture contracts",
            (WRAPPER_PATH, FRAME_WRAPPER_PATH, RX_TOP_PATH, CLAIMS_PATH),
            (),
        ),
        _asset_entry(
            root, VIRTUAL_CHANNEL_ASSET, rendered[VIRTUAL_CHANNEL_ASSET],
            "deterministically generated from tracked buffering RTL identity and the bounded admission claim",
            (WRAPPER_PATH, FRAME_WRAPPER_PATH, RX_TOP_PATH, CLAIMS_PATH),
            (ADMISSION_CLAIM,),
        ),
        _asset_entry(
            root, FRAME_LIFECYCLE_ASSET, rendered[FRAME_LIFECYCLE_ASSET],
            "deterministically generated from tracked RTL architecture and the bounded admission claim",
            (WRAPPER_PATH, FRAME_WRAPPER_PATH, RX_TOP_PATH, CLAIMS_PATH),
            (ADMISSION_CLAIM,),
        ),
        _asset_entry(
            root, MEMORY_PROFILES_ASSET, rendered[MEMORY_PROFILES_ASSET],
            "deterministically generated from tracked RTL, regression evidence, and CDC claims",
            (WRAPPER_PATH, FRAME_WRAPPER_PATH, RX_TOP_PATH, C2B4_PROFILE_PATH,
             CDC_EVIDENCE_PATH, CLAIMS_PATH),
            (CDC_REGRESSION_CLAIM, THROUGHPUT_CLAIM),
        ),
        _asset_entry(
            root, PPA_ASSET, rendered[PPA_ASSET],
            "deterministically generated from tracked public claims and sanitized implementation evidence",
            (COMPARISONS_PATH, CDC_EVIDENCE_PATH, C2B4_EVIDENCE_PATH,
             C2B4_PROFILE_PATH, CLAIMS_PATH),
            (WRITER_CLAIM, THROUGHPUT_CLAIM, C2B4_CLAIM),
        ),
    ]
    generated.extend(
        _binary_asset_entry(path, identity)
        for path, identity in BINARY_ASSETS.items()
    )
    return {
        "kind": "showcase_asset_manifest",
        "schema_version": "1.1.0",
        "assets": generated,
    }


def _manifest_bytes(manifest):
    return (json.dumps(manifest, indent=2, ensure_ascii=True) + "\n").encode("ascii")


def _validate_all(root, rendered):
    for path, payload in rendered.items():
        _validate_svg(path, payload, GENERATED_RULES[path.name])


def _validate_navigation(root):
    readmes = {
        README_PATH: (root / README_PATH).read_text(encoding="utf-8"),
        README_EN_PATH: (root / README_EN_PATH).read_text(encoding="utf-8"),
    }
    marker_lists = []
    for path, text in readmes.items():
        positions = []
        for anchor in NAVIGATION_ANCHORS:
            token = '<a id="{}"></a>'.format(anchor)
            if text.count(token) != 1:
                _fail("{} must contain anchor {} exactly once".format(path, anchor))
            positions.append(text.index(token))
        if positions != sorted(positions):
            _fail("{} showcase anchor order mismatch".format(path))
        image_block = re.compile(
            r'<p align="center">\s*<a href="([^"]+)">\s*'
            r'<img src="([^"]+)"\s+width="([^"]+)"\s+alt="([^"]+)">\s*'
            r'</a>\s*</p>',
            re.MULTILINE,
        )
        blocks = list(image_block.finditer(text))
        if len(blocks) != len(README_ASSET_ORDER) or text.count("<img ") != 3:
            _fail("{} must contain exactly three centered homepage images".format(path))
        for block, expected in zip(blocks, README_ASSET_ORDER):
            href, source, width, alt = block.groups()
            expected_path = expected.as_posix()
            if href != expected_path or source != expected_path:
                _fail("{} homepage image order or href/src identity mismatch".format(path))
            if width != "1000":
                _fail("{} homepage image width must be 1000".format(path))
            if alt != README_ASSET_ALTS[expected]:
                _fail("{} homepage image alt mismatch for {}".format(path, expected))
            if "![]({})".format(expected_path) in text:
                _fail("{} must not use Markdown image syntax for {}".format(path, expected))
        for asset in GENERATED_ASSETS:
            if asset == PPA_ASSET:
                continue
            if re.search(
                    r'<img[^>]+src="{}"'.format(re.escape(asset.as_posix())), text):
                _fail("{} must not embed detailed SVG {} on the homepage".format(
                    path, asset
                ))
        for asset in README_DETAILED_ASSETS:
            if text.count("({})".format(asset.as_posix())) != 1:
                _fail("{} must link detailed asset {} exactly once".format(path, asset))
        for forbidden in ("102,976", "837 x", "-87.91", "-87.30", "-20.82", "-89.53"):
            if forbidden in text:
                _fail("{} must not publish branch-only power metric {}".format(
                    path, forbidden
                ))
        marker_lists.append(CLAIM_MARKER.findall(text))
        if text.count(RESEARCH_BRANCH) != 1:
            _fail("{} canonical research branch identity mismatch".format(path))
    expected_english = (
        "Verified quantitative results are separated into three "
        "non-transferable scopes"
    )
    if expected_english not in readmes[README_EN_PATH]:
        _fail("README.en.md is missing the unambiguous quantitative-scope wording")
    if marker_lists[0] != marker_lists[1] or len(marker_lists[0]) != len(set(marker_lists[0])):
        _fail("README claim marker parity mismatch")

    architecture_texts = {
        ARCHITECTURE_PATH: (root / ARCHITECTURE_PATH).read_text(encoding="utf-8"),
        ARCHITECTURE_EN_PATH: (root / ARCHITECTURE_EN_PATH).read_text(encoding="utf-8"),
    }
    for path, text in architecture_texts.items():
        for asset in ARCHITECTURE_ASSETS:
            if text.count(asset.name) != 1:
                _fail("{} must embed detailed asset {} exactly once".format(
                    path, asset
                ))

    claims_text = (root / CLAIMS_PATH).read_text(encoding="utf-8")
    if "authored_binary_showcase" in claims_text:
        _fail("formal claims must not register authored binary showcase assets")
    for asset in BINARY_ASSETS:
        if asset.as_posix() in claims_text:
            _fail("formal claims must not reference {}".format(asset))

    research_texts = {
        RESEARCH_PATH: (root / RESEARCH_PATH).read_text(encoding="utf-8"),
        RESEARCH_EN_PATH: (root / RESEARCH_EN_PATH).read_text(encoding="utf-8"),
    }
    for path, text in research_texts.items():
        if text.count(RESEARCH_BRANCH) != 2 or text.count(RESEARCH_COMMIT) != 2:
            _fail("{} research branch or fixed-commit identity mismatch".format(path))
        if "%" in text or any(token in text for token in (
                "102,976", "837", "-87.91", "-87.30", "-20.82", "-89.53")):
            _fail("{} must not publish branch-only power metrics".format(path))
        for boundary in (
                "not complete DMA" if path == RESEARCH_EN_PATH else "不是完整 DMA",
                "post-route power",
                "Production RTL"):
            if boundary not in text:
                _fail("{} is missing research boundary {}".format(path, boundary))


def write(root):
    _validate_binary_assets(root)
    metrics = _extract_metrics(root)
    rendered = _render_assets(metrics)
    _validate_all(root, rendered)
    _validate_navigation(root)
    ASSET_DIR_ABS = root / ASSET_DIR
    ASSET_DIR_ABS.mkdir(parents=True, exist_ok=True)
    for path, payload in rendered.items():
        (root / path).write_bytes(payload)
    for path in OBSOLETE_ASSETS:
        candidate = root / path
        if candidate.exists():
            candidate.unlink()
    manifest = _expected_manifest(root, rendered)
    (root / ASSET_MANIFEST_PATH).write_bytes(_manifest_bytes(manifest))
    return metrics


def check(root):
    _validate_binary_assets(root)
    metrics = _extract_metrics(root)
    rendered = _render_assets(metrics)
    _validate_all(root, rendered)
    _validate_navigation(root)
    stale = [path.as_posix() for path, payload in rendered.items()
             if not (root / path).is_file() or (root / path).read_bytes() != payload]
    stale.extend(path.as_posix() for path in OBSOLETE_ASSETS if (root / path).exists())
    if stale:
        _fail("stale showcase assets: {}".format(", ".join(stale)))
    expected_manifest = _manifest_bytes(_expected_manifest(root, rendered))
    if not (root / ASSET_MANIFEST_PATH).is_file() or (
            root / ASSET_MANIFEST_PATH).read_bytes() != expected_manifest:
        _fail("showcase asset manifest is stale")
    return metrics


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    try:
        metrics = write(root) if args.write else check(root)
    except (OSError, ShowcaseAssetError, ValueError) as error:
        print("showcase-assets: error: {}".format(error), file=sys.stderr)
        return 2
    action = "WROTE" if args.write else "PASS"
    print(
        "SHOWCASE_ASSETS_{} generated={} writer_total={} throughput={} "
        "c2b4={}->{}".format(
            action, len(GENERATED_ASSETS), metrics["writer_total"],
            metrics["wide_bytes"], metrics["dc_mhz"], metrics["route_mhz"]
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
