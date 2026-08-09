#!/usr/bin/env python3
"""Generate and verify deterministic SLVC DMA showcase SVG assets."""

from __future__ import print_function

import argparse
import csv
from decimal import Decimal, ROUND_HALF_EVEN, ROUND_HALF_UP
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
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

FRAME_LIFECYCLE_ASSET = Path("docs/assets/slvc_dma_frame_lifecycle.svg")
MEMORY_PROFILES_ASSET = Path("docs/assets/slvc_dma_memory_profiles.svg")
PPA_ASSET = Path("docs/assets/slvc_dma_ppa_implementation.svg")
GENERATED_ASSETS = (
    FRAME_LIFECYCLE_ASSET,
    MEMORY_PROFILES_ASSET,
    PPA_ASSET,
)
AUTHORED_ASSETS = (
    Path("docs/assets/slvc_dma_overview.svg"),
    Path("docs/assets/slvc_dma_virtual_channel_buffering.svg"),
)
OBSOLETE_ASSETS = (Path("docs/assets/slvc_dma_results_at_a_glance.svg"),)

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

AUTHORED_RULES = {
    "slvc_dma_overview.svg": (
        "SLVC DMA: multiple sources, one shared-link contract",
        "Channel admission",
        "Memory and software ownership",
    ),
    "slvc_dma_virtual_channel_buffering.svg": (
        "Virtual channels with dedicated and shared storage",
        "Shared frame pool",
        "Lock one frame",
        "no source interleave",
    ),
}

GENERATED_RULES = {
    "slvc_dma_frame_lifecycle.svg": (
        "SHDR64 frame lifecycle",
        "Ingress + DDR Ring + CQ",
        "WHOLE-FRAME COMMIT",
        "CQE body",
        "owner / valid + IRQ",
        "Release frame ownership",
        "Data path",
        "Admission / control",
        "Software-visible completion",
    ),
    "slvc_dma_memory_profiles.svg": (
        "RX memory profiles and CDC boundaries",
        "Legacy64",
        "Same-clock512",
        "Async64",
        "Async512",
        "Command FIFO",
        "Ordered payload FIFO",
        "Completion FIFO",
        "AW / W / B stay in mem_clk",
        "64 B/cycle",
        "8 B/cycle",
        "ideal ready-memory RTL interface",
    ),
    "slvc_dma_ppa_implementation.svg": (
        "Verified throughput, Writer PPA, and ASIC implementation",
        "Writer-only DC OOC",
        "32 -&gt; 7 bit",
        "-7.97%",
        "-15.84%",
        "64 B/cycle",
        "100% W utilization",
        "peak outstanding 4",
        "550 MHz DC handoff",
        "450 MHz route / PT",
        "+0.041322 / +0.000341 ns",
        "1.04207 mm2",
        "physical checks 0",
        "Three separate scopes - not one complete-DMA result",
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


def _frame_lifecycle_svg(_metrics):
    return """<svg xmlns="http://www.w3.org/2000/svg" width="1480" height="700" viewBox="0 0 1480 700" role="img" aria-labelledby="title desc">
  <title id="title">SHDR64 frame lifecycle through SLVC DMA</title>
  <desc id="desc">The diagram separates payload movement, admission control, and software-visible completion. It marks whole-frame commit and the final frame-ownership release point.</desc>
  <defs><marker id="life-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="#334155"/></marker></defs>
  <style>.title{font:700 28px Arial,sans-serif;fill:#0f172a}.sub{font:400 16px Arial,sans-serif;fill:#475569}.lane{font:700 15px Arial,sans-serif}.head{font:700 16px Arial,sans-serif;fill:#0f172a}.body{font:400 14px Arial,sans-serif;fill:#334155}.tiny{font:400 13px Arial,sans-serif;fill:#475569}.box{stroke-width:2;rx:6}.flow{stroke:#334155;stroke-width:3;fill:none;marker-end:url(#life-arrow)}.dash{stroke:#d97706;stroke-width:2.5;stroke-dasharray:7 5;fill:none;marker-end:url(#life-arrow)}.soft{stroke:#16a34a;stroke-width:2.5;fill:none;marker-end:url(#life-arrow)}</style>
  <rect width="1480" height="700" fill="#ffffff"/>
  <text x="40" y="46" class="title">SHDR64 frame lifecycle</text>
  <text x="40" y="74" class="sub">Admission is resolved before visibility; completion is published before ownership is released.</text>

  <rect x="34" y="112" width="1412" height="128" fill="#fff7ed" stroke="#fed7aa" class="box"/>
  <text x="58" y="142" class="lane" fill="#c2410c">Admission / control</text>
  <rect x="190" y="142" width="170" height="66" fill="#ffffff" stroke="#d97706" class="box"/>
  <text x="275" y="169" text-anchor="middle" class="head">SHDR64 parse / CRC</text><text x="275" y="191" text-anchor="middle" class="tiny">flow_id + length</text>
  <rect x="410" y="142" width="160" height="66" fill="#ffffff" stroke="#d97706" class="box"/>
  <text x="490" y="169" text-anchor="middle" class="head">Channel match</text><text x="490" y="191" text-anchor="middle" class="tiny">context lookup</text>
  <rect x="620" y="132" width="230" height="86" fill="#ffffff" stroke="#d97706" class="box"/>
  <text x="735" y="161" text-anchor="middle" class="head">Ingress + DDR Ring + CQ</text><text x="735" y="184" text-anchor="middle" class="tiny">joint availability check</text><text x="735" y="204" text-anchor="middle" class="tiny">fail closed before payload commit</text>
  <rect x="900" y="142" width="150" height="66" fill="#ffffff" stroke="#d97706" class="box"/>
  <text x="975" y="169" text-anchor="middle" class="head">Reserve</text><text x="975" y="191" text-anchor="middle" class="tiny">ring + buffer + CQ</text>
  <path d="M360 175 H410 M570 175 H620 M850 175 H900" class="dash"/>

  <rect x="34" y="270" width="1412" height="188" fill="#eff6ff" stroke="#bfdbfe" class="box"/>
  <text x="58" y="302" class="lane" fill="#1d4ed8">Data path</text>
  <rect x="90" y="328" width="150" height="78" fill="#ffffff" stroke="#2563eb" class="box"/>
  <text x="165" y="359" text-anchor="middle" class="head">Shared-link RX</text><text x="165" y="383" text-anchor="middle" class="tiny">elastic 512-bit input</text>
  <rect x="285" y="318" width="220" height="98" fill="#ffffff" stroke="#2563eb" class="box"/>
  <text x="395" y="347" text-anchor="middle" class="head">Fixed ingress</text><text x="395" y="370" text-anchor="middle" class="body">or Shared Frame Pool</text><text x="395" y="394" text-anchor="middle" class="tiny">free-list + linked blocks</text>
  <path d="M975 208 V254 H395 V318" class="dash"/>
  <line x1="555" y1="292" x2="555" y2="438" stroke="#16a34a" stroke-width="4"/>
  <text x="570" y="315" class="lane" fill="#166534">WHOLE-FRAME COMMIT</text>
  <rect x="650" y="328" width="170" height="78" fill="#ffffff" stroke="#2563eb" class="box"/>
  <text x="735" y="359" text-anchor="middle" class="head">Frame-locked source</text><text x="735" y="383" text-anchor="middle" class="tiny">no source interleave</text>
  <rect x="865" y="328" width="170" height="78" fill="#ffffff" stroke="#2563eb" class="box"/>
  <text x="950" y="359" text-anchor="middle" class="head">Memory backend</text><text x="950" y="383" text-anchor="middle" class="tiny">4 KiB burst split</text>
  <rect x="1080" y="328" width="145" height="78" fill="#ffffff" stroke="#2563eb" class="box"/>
  <text x="1152" y="359" text-anchor="middle" class="head">DDR Ring</text><text x="1152" y="383" text-anchor="middle" class="tiny">per channel</text>
  <rect x="1270" y="328" width="130" height="78" fill="#ffffff" stroke="#2563eb" class="box"/>
  <text x="1335" y="359" text-anchor="middle" class="head">AXI response</text><text x="1335" y="383" text-anchor="middle" class="tiny">B completion</text>
  <path d="M240 367 H285 M505 367 H535 M590 367 H650 M820 367 H865 M1035 367 H1080 M1225 367 H1270" class="flow"/>

  <rect x="34" y="488" width="1412" height="152" fill="#f0fdf4" stroke="#bbf7d0" class="box"/>
  <text x="58" y="520" class="lane" fill="#166534">Software-visible completion</text>
  <rect x="455" y="535" width="170" height="70" fill="#ffffff" stroke="#16a34a" class="box"/>
  <text x="540" y="565" text-anchor="middle" class="head">CQE body</text><text x="540" y="587" text-anchor="middle" class="tiny">written first</text>
  <rect x="690" y="535" width="190" height="70" fill="#ffffff" stroke="#16a34a" class="box"/>
  <text x="785" y="565" text-anchor="middle" class="head">owner / valid + IRQ</text><text x="785" y="587" text-anchor="middle" class="tiny">published last</text>
  <rect x="945" y="535" width="220" height="70" fill="#ffffff" stroke="#16a34a" class="box"/>
  <text x="1055" y="565" text-anchor="middle" class="head">Release frame ownership</text><text x="1055" y="587" text-anchor="middle" class="tiny">blocks return to free list</text>
  <path d="M1335 406 V470 H540 V535 M625 570 H690 M880 570 H945" class="soft"/>
  <text x="40" y="674" class="tiny">Commit boundary: incomplete Shared frames are invisible. Release boundary: source storage is retained until AXI completion and CQ publication.</text>
</svg>
""".encode("ascii")


def _memory_profiles_svg(metrics):
    return """<svg xmlns="http://www.w3.org/2000/svg" width="1480" height="720" viewBox="0 0 1480 720" role="img" aria-labelledby="title desc">
  <title id="title">SLVC DMA RX memory profiles and CDC boundaries</title>
  <desc id="desc">Four profiles show where AXI writes run and how asynchronous command, ordered payload, and completion transactions cross clock domains. AXI AW, W, and B remain together in the memory clock domain.</desc>
  <style>.title{{font:700 28px Arial,sans-serif;fill:#0f172a}}.sub{{font:400 16px Arial,sans-serif;fill:#475569}}.head{{font:700 18px Arial,sans-serif;fill:#0f172a}}.body{{font:400 14px Arial,sans-serif;fill:#334155}}.tiny{{font:400 13px Arial,sans-serif;fill:#475569}}.metric{{font:700 20px Arial,sans-serif;fill:#166534}}.panel{{stroke:#334155;stroke-width:2;rx:6}}.box{{stroke:#64748b;stroke-width:1.8;rx:5}}.arrow{{stroke:#334155;stroke-width:2.4;fill:none}}.cdc{{stroke:#d97706;stroke-width:2;stroke-dasharray:7 5;fill:none}}</style>
  <rect width="1480" height="720" fill="#ffffff"/>
  <text x="40" y="46" class="title">RX memory profiles and CDC boundaries</text>
  <text x="40" y="74" class="sub">Cross Command / ordered Payload / Completion transactions - never five independent AXI channels.</text>

  <g transform="translate(30 110)"><rect width="330" height="520" fill="#eff6ff" class="panel"/><text x="165" y="38" text-anchor="middle" class="head">Legacy64</text><text x="165" y="63" text-anchor="middle" class="tiny">default compatibility path</text><rect x="48" y="105" width="234" height="58" fill="#fff" class="box"/><text x="165" y="140" text-anchor="middle" class="body">Committed frame source</text><path d="M165 163 V202" class="arrow"/><rect x="48" y="202" width="234" height="70" fill="#fff" class="box"/><text x="165" y="233" text-anchor="middle" class="body">Legacy 64-bit AXI Writer</text><text x="165" y="254" text-anchor="middle" class="tiny">aclk</text><path d="M165 272 V315" class="arrow"/><rect x="48" y="315" width="234" height="66" fill="#fff" class="box"/><text x="165" y="343" text-anchor="middle" class="body">AW / W / B @ aclk</text><text x="165" y="365" text-anchor="middle" class="tiny">64-bit memory W channel</text><text x="165" y="438" text-anchor="middle" class="metric">compatibility profile</text><text x="165" y="469" text-anchor="middle" class="tiny">No RX payload CDC</text></g>

  <g transform="translate(390 110)"><rect width="330" height="520" fill="#ecfdf5" class="panel"/><text x="165" y="38" text-anchor="middle" class="head">Same-clock512</text><text x="165" y="63" text-anchor="middle" class="tiny">wide development profile</text><rect x="48" y="105" width="234" height="58" fill="#fff" class="box"/><text x="165" y="140" text-anchor="middle" class="body">Committed 512-bit source</text><path d="M165 163 V202" class="arrow"/><rect x="48" y="202" width="234" height="70" fill="#fff" class="box"/><text x="165" y="233" text-anchor="middle" class="body">512-bit AXI Writer</text><text x="165" y="254" text-anchor="middle" class="tiny">aclk</text><path d="M165 272 V315" class="arrow"/><rect x="48" y="315" width="234" height="66" fill="#fff" class="box"/><text x="165" y="343" text-anchor="middle" class="body">AW / W / B @ aclk</text><text x="165" y="365" text-anchor="middle" class="tiny">512-bit memory W channel</text><text x="165" y="438" text-anchor="middle" class="metric">{wide_bytes} B/cycle</text><text x="165" y="469" text-anchor="middle" class="tiny">ideal ready-memory RTL interface</text></g>

  <g transform="translate(750 110)"><rect width="330" height="520" fill="#fff7ed" class="panel"/><text x="165" y="38" text-anchor="middle" class="head">Async64</text><text x="165" y="63" text-anchor="middle" class="tiny">dual-clock serialized profile</text><text x="28" y="100" class="tiny">aclk</text><rect x="42" y="112" width="246" height="45" fill="#fff" class="box"/><text x="165" y="140" text-anchor="middle" class="body">Command FIFO</text><rect x="42" y="168" width="246" height="45" fill="#fff" class="box"/><text x="165" y="196" text-anchor="middle" class="body">Ordered payload FIFO</text><rect x="42" y="224" width="246" height="45" fill="#fff" class="box"/><text x="165" y="252" text-anchor="middle" class="body">Completion FIFO</text><line x1="18" y1="292" x2="312" y2="292" class="cdc"/><text x="165" y="286" text-anchor="middle" class="tiny">async transaction boundary</text><text x="28" y="318" class="tiny">mem_clk</text><rect x="42" y="330" width="246" height="48" fill="#fff" class="box"/><text x="165" y="360" text-anchor="middle" class="body">512-to-64 serializer</text><rect x="42" y="390" width="246" height="48" fill="#fff" class="box"/><text x="165" y="420" text-anchor="middle" class="body">64-bit AXI Writer</text><text x="165" y="465" text-anchor="middle" class="metric">{async64_bytes} B/cycle</text><text x="165" y="492" text-anchor="middle" class="tiny">AW / W / B stay in mem_clk</text><text x="165" y="514" text-anchor="middle" class="tiny">completion returns before release</text></g>

  <g transform="translate(1110 110)"><rect width="330" height="520" fill="#f0fdf4" class="panel"/><text x="165" y="38" text-anchor="middle" class="head">Async512</text><text x="165" y="63" text-anchor="middle" class="tiny">dual-clock wide profile</text><text x="28" y="100" class="tiny">aclk</text><rect x="42" y="112" width="246" height="45" fill="#fff" class="box"/><text x="165" y="140" text-anchor="middle" class="body">Command FIFO</text><rect x="42" y="168" width="246" height="45" fill="#fff" class="box"/><text x="165" y="196" text-anchor="middle" class="body">Ordered payload FIFO</text><rect x="42" y="224" width="246" height="45" fill="#fff" class="box"/><text x="165" y="252" text-anchor="middle" class="body">Completion FIFO</text><line x1="18" y1="292" x2="312" y2="292" class="cdc"/><text x="165" y="286" text-anchor="middle" class="tiny">async transaction boundary</text><text x="28" y="318" class="tiny">mem_clk</text><rect x="42" y="340" width="246" height="58" fill="#fff" class="box"/><text x="165" y="368" text-anchor="middle" class="body">512-bit AXI Writer</text><text x="165" y="389" text-anchor="middle" class="tiny">AW / W / B stay in mem_clk</text><text x="165" y="465" text-anchor="middle" class="metric">{wide_bytes} B/cycle</text><text x="165" y="492" text-anchor="middle" class="tiny">completion returns before release</text></g>
  <text x="740" y="677" text-anchor="middle" class="sub">All rates are ideal ready-memory RTL interface results; not measured board DDR throughput.</text>
</svg>
""".format(**metrics).encode("ascii")


def _ppa_svg(metrics):
    return """<svg xmlns="http://www.w3.org/2000/svg" width="1480" height="500" viewBox="0 0 1480 500" role="img" aria-labelledby="title desc">
  <title id="title">Verified SLVC DMA throughput, Writer PPA, and ASIC implementation</title>
  <desc id="desc">Three isolated evidence scopes show Writer-only Design Compiler area, ideal-memory interface throughput, and the fixed C2B4 subsystem implementation point.</desc>
  <style>.title{{font:700 28px Arial,sans-serif;fill:#0f172a}}.sub{{font:400 16px Arial,sans-serif;fill:#475569}}.head{{font:700 18px Arial,sans-serif;fill:#0f172a}}.metric{{font:700 28px Arial,sans-serif}}.body{{font:400 14px Arial,sans-serif;fill:#334155}}.tiny{{font:400 13px Arial,sans-serif;fill:#475569}}.panel{{stroke:#334155;stroke-width:2;rx:6}}</style>
  <rect width="1480" height="500" fill="#ffffff"/>
  <text x="40" y="46" class="title">Verified throughput, Writer PPA, and ASIC implementation</text>
  <text x="40" y="74" class="sub">Evidence-bound fixed points with explicit, non-transferable scope.</text>
  <rect x="35" y="110" width="440" height="300" fill="#eff6ff" class="panel"/>
  <text x="65" y="148" class="head">Writer-only DC OOC</text><text x="65" y="181" class="body">reservation accounting</text><text x="65" y="221" class="metric" fill="#1d4ed8">32 -&gt; 7 bit</text><text x="65" y="274" class="metric" fill="#1d4ed8">{writer_total}% total area</text><text x="65" y="319" class="metric" fill="#1d4ed8">{writer_comb}% combinational</text><text x="65" y="363" class="tiny">Nangate45 paired DC OOC at {writer_period} ns</text><text x="65" y="387" class="tiny">not C2B4 or complete-DMA area</text>
  <rect x="520" y="110" width="440" height="300" fill="#f0fdf4" class="panel"/>
  <text x="550" y="148" class="head">Ideal-memory interface</text><text x="550" y="181" class="body">Same-clock512 / Async512</text><text x="550" y="231" class="metric" fill="#166534">{wide_bytes} B/cycle</text><text x="550" y="284" class="metric" fill="#166534">{w_utilization}% W utilization</text><text x="550" y="329" class="metric" fill="#166534">peak outstanding {peak_outstanding}</text><text x="550" y="363" class="tiny">ready-memory RTL workload</text><text x="550" y="387" class="tiny">not board DDR or 10G throughput</text>
  <rect x="1005" y="110" width="440" height="300" fill="#fff7ed" class="panel"/>
  <text x="1035" y="148" class="head">C2B4 subsystem</text><text x="1035" y="181" class="body">two-channel register-expanded RX512</text><text x="1035" y="221" class="metric" fill="#c2410c">{dc_mhz} MHz DC handoff</text><text x="1035" y="258" class="metric" fill="#c2410c">{route_mhz} MHz route / PT</text><text x="1035" y="300" class="metric" fill="#c2410c">+{setup_wns} / +{hold_wns} ns</text><text x="1035" y="340" class="metric" fill="#c2410c">{area_mm2} mm2</text><text x="1035" y="366" class="body">standard-cell area</text><text x="1035" y="394" class="tiny">physical checks {physical_checks}; not Fmax or signoff</text>
  <rect x="240" y="438" width="1000" height="40" fill="#f8fafc" stroke="#cbd5e1" rx="6"/>
  <text x="740" y="464" text-anchor="middle" class="body">Three separate scopes - not one complete-DMA result</text>
</svg>
""".format(**metrics).encode("ascii")


def _validate_svg(path, payload, required):
    try:
        text = payload.decode("ascii")
    except UnicodeDecodeError:
        _fail("{} must be deterministic ASCII SVG".format(path))
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        _fail("invalid SVG {}: {}".format(path, error))
    if root.attrib.get("viewBox") is None or root.attrib.get("role") != "img":
        _fail("{} is missing SVG accessibility metadata".format(path))
    children = {child.tag.rsplit("}", 1)[-1] for child in root}
    if not {"title", "desc"}.issubset(children):
        _fail("{} is missing title or desc".format(path))
    forbidden = (
        r"<(?:image|linearGradient|radialGradient|filter)\b",
        r"(?:href|xlink:href)\s*=\s*[\"'](?:https?:|data:)",
        r"base64",
        r"(?i)(?:(?<![A-Z])[A-Z]:[\\/]|/home/|\\\\)",
    )
    for pattern in forbidden:
        if re.search(pattern, text):
            _fail("{} contains forbidden SVG content".format(path))
    for fragment in required:
        if fragment not in text:
            _fail("{} is missing required text: {}".format(path, fragment))


def _render_assets(metrics):
    return {
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


def _expected_manifest(root, rendered):
    authored = [
        {
            "path": AUTHORED_ASSETS[0].as_posix(),
            "sha256": _sha256(root / AUTHORED_ASSETS[0]),
            "format": "svg",
            "source": (
                "hand-authored architecture diagram derived from the public "
                "RTL hierarchy and interface documentation"
            ),
            "claim_ids": [],
        },
        {
            "path": AUTHORED_ASSETS[1].as_posix(),
            "sha256": _sha256(root / AUTHORED_ASSETS[1]),
            "format": "svg",
            "source": (
                "hand-authored architecture diagram derived from the public "
                "admission, fixed-ingress, shared-pool, selector, writer, and CQ RTL"
            ),
            "claim_ids": [ADMISSION_CLAIM],
        },
    ]
    generated = [
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
    return {
        "kind": "showcase_asset_manifest",
        "schema_version": "1.0.0",
        "assets": authored + generated,
    }


def _manifest_bytes(manifest):
    return (json.dumps(manifest, indent=2, ensure_ascii=True) + "\n").encode("ascii")


def _validate_all(root, rendered):
    for path, payload in rendered.items():
        _validate_svg(path, payload, GENERATED_RULES[path.name])
    for path in AUTHORED_ASSETS:
        if not (root / path).is_file():
            _fail("missing authored asset {}".format(path))
        _validate_svg(path, (root / path).read_bytes(), AUTHORED_RULES[path.name])


def write(root):
    metrics = _extract_metrics(root)
    rendered = _render_assets(metrics)
    _validate_all(root, rendered)
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
    metrics = _extract_metrics(root)
    rendered = _render_assets(metrics)
    _validate_all(root, rendered)
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
