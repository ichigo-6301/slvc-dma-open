#!/usr/bin/env python3
"""Generate and verify the evidence-bound results-at-a-glance SVG."""

from __future__ import print_function

import argparse
import csv
from decimal import Decimal, ROUND_HALF_EVEN, ROUND_HALF_UP
import hashlib
import json
import re
import sys
from pathlib import Path


ASSET_PATH = Path("docs/assets/slvc_dma_results_at_a_glance.svg")
ASSET_MANIFEST_PATH = Path("provenance/showcase_assets.json")
COMPARISONS_PATH = Path("evidence/asic_paired_dc/comparisons.csv")
CLAIMS_PATH = Path("provenance/claims.yaml")
GENERATOR_PATH = Path("flows/scripts/generate_results_at_a_glance.py")

WRITER_CLAIM = "slvc_dma_writer_reservation_component_paired_dc"
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
THROUGHPUT_CONFIGURATION = re.compile(
    r"^same-clock 512 and async512 ([0-9]+) byte/cycle; async64 "
    r"([0-9]+) byte/cycle; four peak outstanding$"
)
C2B4_STATEMENT = re.compile(
    r"^The C2B4 register-expanded RX512 memory subsystem completed a "
    r"([0-9]+) MHz Design Compiler handoff and a ([0-9]+) MHz same-run "
    r"OpenROAD, OpenRCX, and PrimeTime closure point\.$"
)

WRITER_CAVEAT = (
    "Component-level DC OOC only; this does not establish C2B4 or "
    "complete-DMA area reduction, Fmax, P&R, power, or signoff."
)
THROUGHPUT_CAVEAT = (
    "This is RTL/model interface throughput, not a board DDR or "
    "lossless-network measurement."
)
C2B4_CAVEAT = (
    "This is a C2 development profile and internal nominal academic-corner "
    "result, not C4B4, Fmax, complete-DMA, power, IO, OCV/MMMC, foundry, "
    "or silicon signoff."
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
    "caveat": WRITER_CAVEAT,
    "public": True,
}

THROUGHPUT_SCOPE = {
    "profile": "slvc_dma_v1_512_rx_payload_cdc_development",
    "statement": (
        "Ideal-memory tests sustained one AXI W beat per clock for "
        "same-clock 512, async64, and async512."
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
    "caveat": THROUGHPUT_CAVEAT,
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
    "benchmark": (
        "C2B4 RX512 memory subsystem with 102400 payload and keep registers"
    ),
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
    "caveat": C2B4_CAVEAT,
    "public": True,
}


class ResultsAssetError(RuntimeError):
    pass


def _fail(message):
    raise ResultsAssetError(message)


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
        _fail(
            "claim scope identity mismatch: {} fields={}".format(
                claim_id, ",".join(fields)
            )
        )
    return claim


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
                baseline, candidate, delta, delta_percent)) or
                baseline == 0):
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
    claim_value = Decimal(str(writer_claim.get("value", "NaN")))
    if csv_total != -claim_total or csv_total != claim_value:
        _fail("Writer total-area CSV and claim mismatch")
    if csv_comb != -claim_comb:
        _fail("Writer combinational-area CSV and claim mismatch")
    if period != Decimal("1.500"):
        _fail("Writer period identity mismatch")
    return period, csv_total, csv_comb


def _extract_metrics(root):
    claims = _load_claims(root / CLAIMS_PATH)
    writer = _require_claim(claims, WRITER_CLAIM, WRITER_SCOPE)
    throughput = _require_claim(claims, THROUGHPUT_CLAIM, THROUGHPUT_SCOPE)
    c2b4 = _require_claim(claims, C2B4_CLAIM, C2B4_SCOPE)

    period, writer_total, writer_comb = _load_writer_metrics(
        root / COMPARISONS_PATH, writer
    )

    throughput_match = THROUGHPUT_CONFIGURATION.fullmatch(
        str(throughput.get("configuration", ""))
    )
    if not throughput_match:
        _fail("ideal-memory throughput configuration mismatch")
    wide_bytes, async64_bytes = (
        int(value) for value in throughput_match.groups()
    )
    if wide_bytes != 64 or async64_bytes != 8:
        _fail("ideal-memory throughput value mismatch")

    c2b4_match = C2B4_STATEMENT.fullmatch(str(c2b4.get("statement", "")))
    if not c2b4_match:
        _fail("C2B4 claim statement mismatch")
    dc_mhz, route_mhz = (int(value) for value in c2b4_match.groups())
    if c2b4.get("profile") != "dma_rx512_reg_c2_b4_m2_sp64":
        _fail("C2B4 profile identity mismatch")
    if (dc_mhz, route_mhz) != (550, 450):
        _fail("C2B4 frequency identity mismatch")

    scale = Decimal("0.01")
    return {
        "bytes_per_cycle": wide_bytes,
        "peak_outstanding": 4,
        "writer_period": period.quantize(Decimal("0.0")),
        "writer_total": writer_total.quantize(scale, rounding=ROUND_HALF_UP),
        "writer_comb": writer_comb.quantize(scale, rounding=ROUND_HALF_UP),
        "dc_mhz": dc_mhz,
        "route_mhz": route_mhz,
    }


def _render_svg(metrics):
    return """<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1280\" height=\"240\" viewBox=\"0 0 1280 240\" role=\"img\" aria-labelledby=\"title desc\">\n\
  <title id=\"title\">SLVC DMA results at a glance</title>\n\
  <desc id=\"desc\">Three evidence-bound results: ideal-memory RTL interface throughput, Writer-only Design Compiler area changes, and fixed C2B4 subsystem implementation points. Scope labels prohibit subsystem and complete-DMA extrapolation.</desc>\n\
  <style>\n\
    .title {{ font: 700 22px Arial, sans-serif; fill: #0f172a; }}\n\
    .metric {{ font: 700 31px Arial, sans-serif; }}\n\
    .label {{ font: 700 15px Arial, sans-serif; fill: #0f172a; }}\n\
    .note {{ font: 400 13px Arial, sans-serif; fill: #475569; }}\n\
    .divider {{ stroke: #cbd5e1; stroke-width: 2; }}\n\
  </style>\n\
  <rect width=\"1280\" height=\"240\" fill=\"#f8fafc\"/>\n\
  <text x=\"40\" y=\"38\" class=\"title\">Verified results at a glance</text>\n\
  <line x1=\"426\" y1=\"62\" x2=\"426\" y2=\"214\" class=\"divider\"/>\n\
  <line x1=\"853\" y1=\"62\" x2=\"853\" y2=\"214\" class=\"divider\"/>\n\
\n\
  <text x=\"40\" y=\"103\" class=\"metric\" fill=\"#166534\">{bytes_per_cycle} B/cycle</text>\n\
  <text x=\"40\" y=\"134\" class=\"label\">512-bit memory interface</text>\n\
  <text x=\"40\" y=\"160\" class=\"note\">ready ideal-memory RTL model</text>\n\
  <text x=\"40\" y=\"184\" class=\"note\">peak outstanding {peak_outstanding}; not board DDR/10G</text>\n\
\n\
  <text x=\"466\" y=\"103\" class=\"metric\" fill=\"#1d4ed8\">{writer_total}% / {writer_comb}%</text>\n\
  <text x=\"466\" y=\"134\" class=\"label\">Writer-only total / combinational area</text>\n\
  <text x=\"466\" y=\"160\" class=\"note\">Nangate45 paired DC OOC at {writer_period} ns</text>\n\
  <text x=\"466\" y=\"184\" class=\"note\">not C2B4 or complete-DMA area</text>\n\
\n\
  <text x=\"893\" y=\"103\" class=\"metric\" fill=\"#a16207\">{dc_mhz} MHz -&gt; {route_mhz} MHz</text>\n\
  <text x=\"893\" y=\"134\" class=\"label\">DC handoff -&gt; route / PrimeTime</text>\n\
  <text x=\"893\" y=\"160\" class=\"note\">C2B4 two-channel RX512 subsystem</text>\n\
  <text x=\"893\" y=\"184\" class=\"note\">fixed closure points; not complete DMA or Fmax</text>\n\
</svg>\n""".format(**metrics).encode("ascii")


def _expected_asset_entry(root, svg_bytes):
    return {
        "path": ASSET_PATH.as_posix(),
        "sha256": hashlib.sha256(svg_bytes).hexdigest(),
        "format": "svg",
        "source": (
            "deterministically generated from tracked public claims and "
            "sanitized paired-DC comparisons"
        ),
        "generator": GENERATOR_PATH.as_posix(),
        "generator_sha256": _sha256(root / GENERATOR_PATH),
        "command": (
            "python flows/scripts/generate_results_at_a_glance.py "
            "--root . --write"
        ),
        "inputs": [
            {
                "path": COMPARISONS_PATH.as_posix(),
                "sha256": _sha256(root / COMPARISONS_PATH),
            },
            {
                "path": CLAIMS_PATH.as_posix(),
                "sha256": _sha256(root / CLAIMS_PATH),
            },
        ],
        "claim_ids": [WRITER_CLAIM, THROUGHPUT_CLAIM, C2B4_CLAIM],
    }


def _load_asset_manifest(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, TypeError, ValueError) as error:
        _fail("invalid showcase asset manifest: {}".format(error))
    if (not isinstance(data, dict) or
            data.get("kind") != "showcase_asset_manifest" or
            not isinstance(data.get("assets"), list)):
        _fail("showcase asset manifest schema mismatch")
    paths = [entry.get("path") for entry in data["assets"]
             if isinstance(entry, dict)]
    if len(paths) != len(set(paths)):
        _fail("duplicate showcase asset path")
    return data


def write(root):
    metrics = _extract_metrics(root)
    svg_bytes = _render_svg(metrics)
    asset_path = root / ASSET_PATH
    asset_path.parent.mkdir(parents=True, exist_ok=True)
    asset_path.write_bytes(svg_bytes)

    manifest_path = root / ASSET_MANIFEST_PATH
    manifest = _load_asset_manifest(manifest_path)
    expected = _expected_asset_entry(root, svg_bytes)
    existing = [entry for entry in manifest["assets"]
                if entry.get("path") == ASSET_PATH.as_posix()]
    if existing:
        manifest["assets"][manifest["assets"].index(existing[0])] = expected
    else:
        manifest["assets"].append(expected)
    with manifest_path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n")
    return metrics


def check(root):
    metrics = _extract_metrics(root)
    expected_svg = _render_svg(metrics)
    asset_path = root / ASSET_PATH
    if not asset_path.is_file() or asset_path.read_bytes() != expected_svg:
        _fail("results-at-a-glance SVG is stale")
    manifest = _load_asset_manifest(root / ASSET_MANIFEST_PATH)
    entries = [entry for entry in manifest["assets"]
               if entry.get("path") == ASSET_PATH.as_posix()]
    if len(entries) != 1:
        _fail("results-at-a-glance asset manifest entry is missing")
    if entries[0] != _expected_asset_entry(root, expected_svg):
        _fail("results-at-a-glance asset manifest entry is stale")
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
    except (OSError, ResultsAssetError, ValueError) as error:
        print("results-asset: error: {}".format(error), file=sys.stderr)
        return 2
    action = "WROTE" if args.write else "PASS"
    print(
        "RESULTS_ASSET_{} bytes_per_cycle={} writer_total={} "
        "writer_comb={} c2b4={}->{}".format(
            action,
            metrics["bytes_per_cycle"],
            metrics["writer_total"],
            metrics["writer_comb"],
            metrics["dc_mhz"],
            metrics["route_mhz"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
