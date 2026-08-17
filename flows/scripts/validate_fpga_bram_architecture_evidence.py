#!/usr/bin/env python3
"""Fail-closed validator for the bounded U5 FPGA BRAM comparison."""

from __future__ import print_function

import argparse
import csv
import hashlib
import json
import re
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path


CLAIM_ID = "slvc_dma_u5_13ch_bram_architecture_comparison"
EVIDENCE_ID = "slvc_dma_u5_13ch_bram_architecture_summary"
NONCLAIM_ID = "slvc_dma_u5_bram_architecture_not_equivalent"
SOURCE_REF = "144231a9694b1a6f4698082a333ceb39d7029d08"
PACKAGE_REL = Path("evidence/fpga_resources/u5_13ch_bram_architecture")
SUMMARY_REL = Path("evidence/slvc_dma_u5_13ch_bram_architecture_summary.yaml")
CLAIMS_REL = Path("provenance/claims.yaml")
EVIDENCE_REL = Path("provenance/evidence.yaml")
NONCLAIMS_REL = Path("provenance/nonclaims.yaml")
README_START = "<!-- fpga-bram-publication:{}:readme:start -->".format(CLAIM_ID)
README_END = "<!-- fpga-bram-publication:{}:readme:end -->".format(CLAIM_ID)
RESULTS_START = "<!-- fpga-bram-publication:{}:start -->".format(CLAIM_ID)
RESULTS_END = "<!-- fpga-bram-publication:{}:end -->".format(CLAIM_ID)

CLAIM_FIXED = {
    "profile": "slvc_dma_u5_13rx13tx_sync_fpga_bram",
    "statement": (
        "In Vivado 2018.3 synthesis on xc7z100ffg900-2, the current U5 "
        "SLVC wrapper used 45.5 BRAM tiles versus 97.5 tiles for thirteen "
        "independent 512-bit by 128-beat payload FIFOs, a 53.333 percent "
        "reduction against that shallow-wide FIFO baseline."
    ),
    "metric": "fpga_bram_tiles_vs_independent_payload_fifos",
    "value": "53.333",
    "unit": "percent BRAM tile reduction",
    "benchmark": "SLVC U5 wrapper versus 13 independent 512-bit by 128-beat payload FIFOs",
    "configuration": (
        "Vivado 2018.3; xc7z100ffg900-2; DMA_MAX_CH=16; 13 RX/13 TX active; "
        "512-bit stream; 64-bit HP0; synchronous 100 MHz board profile"
    ),
    "source_ref": SOURCE_REF,
    "tool": "Vivado 2018.3",
    "evidence": [EVIDENCE_ID],
    "status": "partial",
    "caveat": (
        "Resource-budget comparison only. The current implementation retains "
        "the complete Fixed bank and adds Shared Pool; it does not beat the "
        "ideal packed-bank storage lower bound and is not functionally "
        "equivalent to MCDMA plus FIFOs."
    ),
    "resume_eligible": False,
    "public": True,
}
NONCLAIM_FIXED = {
    "profile": "slvc_dma_u5_13rx13tx_sync_fpga_bram",
    "statement": (
        "Shared Pool alone, complete functional equivalence to MCDMA, exact "
        "MCDMA internal FIFO depth, total FPGA area superiority, and lossless "
        "operation under arbitrary unbounded backpressure are not claimed."
    ),
    "reason": (
        "The measured U5 build retains sixteen 8 KiB Fixed payload banks and "
        "adds a 4 KiB Shared Pool. The independent FIFO and MCDMA runs are "
        "bounded synthesis baselines, while the ideal packed bank is a "
        "storage-only lower bound."
    ),
    "status": "not_claimed",
    "public": True,
}

PACKAGE_FILES = frozenset({
    "README.md", "artifacts.csv", "comparisons.csv", "manifest.json",
    "mcdma_owners.csv", "resources.csv",
})

RESOURCE_FIELDS = (
    "design_id", "stage", "scope", "stream_width_bits", "memory_width_bits",
    "channels", "logical_payload_bytes", "lut", "ff", "ramb36", "ramb18",
    "bram_tiles", "status",
)
RESOURCE_ROWS = (
    ("slvc_wrapper_synth", "synthesis", "complete_slvc_wrapper", "512", "64",
     "DMA_MAX_CH=16;active_rx=13;active_tx=13", "135168", "41363", "35650",
     "44", "3", "45.5", "measured"),
    ("slvc_wrapper_routed", "routed", "complete_slvc_wrapper", "512", "64",
     "DMA_MAX_CH=16;active_rx=13;active_tx=13", "135168", "", "", "44", "3",
     "45.5", "identity_confirmation"),
    ("slvc_fixed_ingress", "synthesis", "fixed_ingress_bank", "512", "64", "16",
     "131072", "1533", "1836", "33", "1", "33.5", "measured"),
    ("slvc_shared_adapter", "synthesis", "shared_adapter_including_pool", "512",
     "64", "16", "4096", "3108", "6449", "11", "2", "12.0", "measured"),
    ("slvc_shared_pool", "synthesis", "shared_pool_payload_subset", "512", "64",
     "16", "4096", "1967", "3528", "7", "1", "7.5", "measured_subset"),
    ("fifo13_payload512", "synthesis", "13_independent_payload_fifos", "512", "",
     "13", "106496", "325", "286", "91", "13", "97.5", "measured"),
    ("fifo13_axis577", "synthesis", "13_independent_axis_frame_fifos", "577", "",
     "13", "106496", "325", "286", "104", "13", "110.5", "measured"),
    ("packed_bank_13x8k", "synthesis", "ideal_centralized_payload_bank", "512", "",
     "13", "106496", "0", "0", "28", "1", "28.5", "lower_bound"),
    ("mcdma13x13_512_512", "synthesis", "axi_mcdma_13_mm2s_13_s2mm", "512", "512",
     "13+13", "", "15216", "17049", "25", "6", "28.0", "measured_lower_bound"),
    ("mcdma13x13_64_512", "elaboration", "axi_mcdma_13_mm2s_13_s2mm", "512", "64",
     "13+13", "", "", "", "", "", "", "unsupported_by_vivado_2018_3"),
)

COMPARISON_FIELDS = (
    "comparison_id", "slvc_tiles", "baseline_tiles", "reduction_percent",
    "classification",
)
COMPARISON_ROWS = (
    ("buffer_vs_13x_payload_fifo", "45.5", "97.5", "53.333",
     "independent-wide-fifo-fragmentation-advantage"),
    ("buffer_vs_13x_axis_fifo", "45.5", "110.5", "58.824",
     "independent-wide-fifo-fragmentation-advantage"),
    ("buffer_vs_ideal_packed_bank", "45.5", "28.5", "-59.649",
     "no-buffer-only-advantage"),
    ("dma_budget_vs_payload_fifo_plus_mcdma512", "45.5", "125.5", "63.745",
     "resource-budget-only"),
    ("dma_budget_vs_axis_fifo_plus_mcdma512", "45.5", "138.5", "67.148",
     "resource-budget-only"),
    ("dma_budget_vs_packed_bank_plus_mcdma512", "45.5", "56.5", "19.469",
     "resource-budget-only-conservative-lower-bound"),
)

OWNER_FIELDS = ("owner", "instance", "lut", "ff", "ramb36", "ramb18", "note")
OWNER_ROWS = (
    ("sg_engine", "GEN_SG_ENGINE.I_SG_ENGINE", "3853", "3699", "0", "2",
     "hierarchies may overlap"),
    ("s2mm_buffer_fifo", "INCLUDE_S2MM_SOF_EOF_GENERATOR.INCLUDE_BUF_FIFO.I_BUF_FIFO",
     "304", "96", "8", "1", "hierarchies may overlap"),
    ("primary_datamover", "I_PRMRY_DATAMOVER", "5376", "7569", "17", "3",
     "hierarchies may overlap"),
    ("s2mm_realigner", "GEN_INCLUDE_REALIGNER.I_S2MM_REALIGNER", "1229", "1407",
     "1", "1", "hierarchies may overlap"),
    ("tstrb_fifo", "I_TSTRB_FIFO", "122", "68", "1", "1",
     "hierarchies may overlap"),
)

ARTIFACT_FIELDS = ("artifact_id", "retention", "role", "size_bytes", "sha256")
ARTIFACT_ROWS = (
    ("slvc_synth_dcp", "private_external", "SLVC synthesis checkpoint", "11293399",
     "093752e913351b34e1bc99107d777d5a1f2fdb05d9db5a490383231f95a35d3d"),
    ("slvc_routed_dcp", "private_external", "SLVC routed identity checkpoint", "42310199",
     "8cb63300153de63e084be7d18de58711e08f730e4f2e296155105e46df5cf597"),
    ("slvc_bitstream", "private_external", "protected U5 bitstream identity", "7167253",
     "0aff10f9479ae96b99bb525b42f486d8dd4904b2b88e8057080abf375b7645fa"),
    ("slvc_resource_counts", "private_external", "sanitized hierarchy extraction", "1775",
     "cea80165bd8edc0edcdb9c6f44797db8549dc0fcda4f181d4eb2e1b72fb68c4d"),
    ("fifo_resource_counts", "private_external", "FIFO OOC counters", "174",
     "25501cdbae5e8f71cea9836fdf13b0346a9ac81059b4e6b8654018e6b3bf01d5"),
    ("mcdma_resource_counts", "private_external", "MCDMA OOC counters", "211",
     "ff817dd778078cad7e67e889649430367845ae38da50996687071e13e053c03e"),
    ("fifo_baseline_rtl", "private_external", "generated FIFO baseline RTL", "3898",
     "d21557db4dea0a69cee11d23845bfa33f8c980a0878f4c6612ad96d1092e516c"),
    ("fifo_ooc_script", "private_external", "FIFO OOC Vivado script", "2138",
     "e4b6eee14101281647b7ff53ed507c71f3fe60d74b1399df8e8cc24d88536128"),
    ("mcdma_ooc_script", "private_external", "MCDMA OOC Vivado script", "3831",
     "cb5fbe2908e17478cee9a25c66d24fb5aa444004b345bf07d7095bde85eb062c"),
    ("slvc_extract_script", "private_external", "SLVC checkpoint extraction script", "3910",
     "7e097186fa40b0f9627f7c47da8d7db7db8d40100fc23e0c2260e857e5a3a981"),
    ("summary_script", "private_external", "Decimal comparison generator", "14600",
     "b583472ccc47be2fb7b40c12f705ec2f41677c3ef65708c6e4ae0576ab1cfac2"),
)

SENSITIVE_PATTERNS = (
    re.compile(r"[A-Za-z]:[\\/]"),
    re.compile(r"(?i)ichigo"),
    re.compile(r"(?i)desktop-[a-z0-9]+"),
    re.compile(r"(?i)users[/\\]"),
    re.compile(r"(?i)appdata"),
)
FORBIDDEN_OVERCLAIMS = (
    "Shared Pool alone reduced BRAM",
    "functionally equivalent to MCDMA",
    "arbitrary unbounded backpressure is lossless",
    "complete-DMA area reduction",
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


def _read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))


def _read_csv(path, fields, rows):
    try:
        with path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.reader(stream)
            actual = list(reader)
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))
    expected = [list(fields)] + [list(row) for row in rows]
    if actual != expected:
        _fail("{} fixed rows mismatch".format(path.name))


def _item_block(text, item_id):
    pattern = re.compile(r"(?ms)^  - id: " + re.escape(item_id) + r"\n.*?(?=^  - id: |\Z)")
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        _fail("expected exactly one {} item".format(item_id))
    return matches[0].group(0)


def _yaml_scalar(raw, context):
    if raw.startswith('"'):
        try:
            value = json.loads(raw)
        except (TypeError, ValueError) as error:
            _fail("{} invalid quoted scalar: {}".format(context, error))
        if not isinstance(value, str):
            _fail("{} quoted scalar must be text".format(context))
        return value
    if raw == "true":
        return True
    if raw == "false":
        return False
    if not raw or raw != raw.strip():
        _fail("{} invalid scalar".format(context))
    return raw


def _parse_registry_record(text, item_id):
    fields = {}
    active_list = None
    for line in _item_block(text, item_id).splitlines()[1:]:
        scalar = re.fullmatch(r"    ([a-z][a-z0-9_]*):(?: (.*))?", line)
        if scalar:
            key, raw = scalar.groups()
            if key in fields:
                _fail("{} duplicate {}".format(item_id, key))
            if raw is None:
                fields[key] = []
                active_list = key
            else:
                fields[key] = _yaml_scalar(raw, "{}.{}".format(item_id, key))
                active_list = None
            continue
        item = re.fullmatch(r"      - (.+)", line)
        if item and active_list is not None:
            fields[active_list].append(_yaml_scalar(item.group(1), item_id))
            continue
        _fail("{} unsupported registry syntax".format(item_id))
    return fields


def _require_record(actual, expected, context):
    if set(actual) != set(expected):
        _fail("{} field set mismatch".format(context))
    for key, value in expected.items():
        if actual.get(key) != value:
            _fail("{} fixed {} mismatch".format(context, key))


def _decimal(raw, context):
    try:
        return Decimal(raw)
    except (InvalidOperation, ValueError):
        _fail("{} is not decimal".format(context))


def _validate_derivations(root):
    resources_path = root / PACKAGE_REL / "resources.csv"
    with resources_path.open("r", encoding="utf-8", newline="") as stream:
        resources = {row["design_id"]: row for row in csv.DictReader(stream)}
    values = {key: _decimal(row["bram_tiles"], key) for key, row in resources.items()
              if row["bram_tiles"]}
    expected = {
        "buffer_vs_13x_payload_fifo": values["fifo13_payload512"],
        "buffer_vs_13x_axis_fifo": values["fifo13_axis577"],
        "buffer_vs_ideal_packed_bank": values["packed_bank_13x8k"],
        "dma_budget_vs_payload_fifo_plus_mcdma512": (
            values["fifo13_payload512"] + values["mcdma13x13_512_512"]
        ),
        "dma_budget_vs_axis_fifo_plus_mcdma512": (
            values["fifo13_axis577"] + values["mcdma13x13_512_512"]
        ),
        "dma_budget_vs_packed_bank_plus_mcdma512": (
            values["packed_bank_13x8k"] + values["mcdma13x13_512_512"]
        ),
    }
    slvc = values["slvc_wrapper_synth"]
    with (root / PACKAGE_REL / "comparisons.csv").open(
            "r", encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    for row in rows:
        baseline = expected[row["comparison_id"]]
        reduction = ((baseline - slvc) / baseline * Decimal("100")).quantize(
            Decimal("0.001"), rounding=ROUND_HALF_EVEN
        )
        if _decimal(row["baseline_tiles"], row["comparison_id"]) != baseline:
            _fail("{} baseline mismatch".format(row["comparison_id"]))
        if _decimal(row["slvc_tiles"], row["comparison_id"]) != slvc:
            _fail("{} SLVC tile mismatch".format(row["comparison_id"]))
        if _decimal(row["reduction_percent"], row["comparison_id"]) != reduction:
            _fail("{} Decimal derivation mismatch".format(row["comparison_id"]))


def _validate_manifest(root):
    path = root / PACKAGE_REL / "manifest.json"
    try:
        manifest = json.loads(_read_text(path))
    except (TypeError, ValueError) as error:
        _fail("invalid manifest: {}".format(error))
    expected = {
        "schema_version": "1.0.0",
        "evidence_id": EVIDENCE_ID,
        "claim_id": CLAIM_ID,
        "classification": "FPGA_VIVADO_2018_3_RESOURCE_COMPARISON",
        "status": "partial",
        "source_ref": SOURCE_REF,
        "tool": "Vivado 2018.3 build 2405991",
        "device": "xc7z100ffg900-2",
        "numeric_authority": "resources.csv",
        "derived_results": "comparisons.csv",
        "resume_eligible": False,
        "public": True,
        "files": sorted(PACKAGE_FILES),
    }
    if manifest != expected:
        _fail("manifest fixed contract mismatch")


def _validate_docs(root):
    required = {
        Path("README.md"): (README_START, README_END, "53.333%", "独立浅宽 FIFO"),
        Path("README.en.md"): (README_START, README_END, "53.333%", "independent shallow-wide FIFO"),
        Path("docs/zh-CN/results.md"): (RESULTS_START, RESULTS_END, "28.5", "资源预算对比"),
        Path("docs/en/results.md"): (RESULTS_START, RESULTS_END, "28.5", "resource-budget comparison"),
        Path("docs/zh-CN/fpga_implementation.md"): (RESULTS_START, RESULTS_END, "135168", "Shared Pool"),
        Path("docs/en/fpga_implementation.md"): (RESULTS_START, RESULTS_END, "135168", "Shared Pool"),
    }
    for relative, tokens in required.items():
        text = _read_text(root / relative)
        for token in tokens:
            if text.count(token) != 1:
                _fail("{} token count mismatch: {}".format(relative, token))
        start = text.index(tokens[0])
        end = text.index(tokens[1], start) + len(tokens[1])
        publication = text[start:end]
        for phrase in FORBIDDEN_OVERCLAIMS:
            if phrase in publication:
                _fail("{} contains forbidden overclaim".format(relative))


def _validate_sensitive_text(root):
    for relative in [SUMMARY_REL] + [PACKAGE_REL / name for name in PACKAGE_FILES]:
        text = _read_text(root / relative)
        for pattern in SENSITIVE_PATTERNS:
            if pattern.search(text):
                _fail("{} contains sensitive identity or absolute path".format(relative))


def validate(root):
    root = Path(root).resolve()
    claims = _read_text(root / CLAIMS_REL)
    evidence = _read_text(root / EVIDENCE_REL)
    nonclaims = _read_text(root / NONCLAIMS_REL)
    registered = "  - id: {}\n".format(CLAIM_ID) in claims
    sentinels = (CLAIM_ID in evidence, NONCLAIM_ID in nonclaims, (root / PACKAGE_REL).exists(),
                 (root / SUMMARY_REL).exists())
    doc_text = "\n".join(_read_text(root / path) for path in (
        Path("README.md"), Path("README.en.md"), Path("docs/zh-CN/results.md"),
        Path("docs/en/results.md"), Path("docs/zh-CN/fpga_implementation.md"),
        Path("docs/en/fpga_implementation.md"),
    ))
    if not registered:
        if any(sentinels) or CLAIM_ID in doc_text or NONCLAIM_ID in doc_text:
            _fail("orphan FPGA BRAM publication payload")
        return "FPGA_BRAM_ARCHITECTURE_NOT_PUBLISHED"
    if not all(sentinels):
        _fail("incomplete FPGA BRAM publication payload")
    actual_files = frozenset(
        str(path.relative_to(root / PACKAGE_REL)).replace("\\", "/")
        for path in (root / PACKAGE_REL).rglob("*") if path.is_file()
    )
    if actual_files != PACKAGE_FILES:
        _fail("FPGA BRAM package file set mismatch")
    evidence_fixed = {
        "path": str(SUMMARY_REL).replace("\\", "/"),
        "type": "fpga_vivado_2018_3_resource_comparison",
        "source_ref": SOURCE_REF,
        "tool": "Vivado 2018.3",
        "claims": [CLAIM_ID],
        "sha256": _sha256(root / SUMMARY_REL),
        "public": True,
    }
    _require_record(_parse_registry_record(claims, CLAIM_ID), CLAIM_FIXED, CLAIM_ID)
    _require_record(_parse_registry_record(evidence, EVIDENCE_ID), evidence_fixed, EVIDENCE_ID)
    _require_record(_parse_registry_record(nonclaims, NONCLAIM_ID), NONCLAIM_FIXED, NONCLAIM_ID)
    _read_csv(root / PACKAGE_REL / "resources.csv", RESOURCE_FIELDS, RESOURCE_ROWS)
    _read_csv(root / PACKAGE_REL / "comparisons.csv", COMPARISON_FIELDS, COMPARISON_ROWS)
    _read_csv(root / PACKAGE_REL / "mcdma_owners.csv", OWNER_FIELDS, OWNER_ROWS)
    _read_csv(root / PACKAGE_REL / "artifacts.csv", ARTIFACT_FIELDS, ARTIFACT_ROWS)
    _validate_derivations(root)
    _validate_manifest(root)
    _validate_docs(root)
    _validate_sensitive_text(root)
    summary = _read_text(root / SUMMARY_REL)
    for token in (CLAIM_ID, SOURCE_REF, "45.5", "97.5", "53.333", "28.5",
                  "resource-budget comparison", "numeric_authority: false"):
        if summary.count(token) != 1:
            _fail("summary token count mismatch: {}".format(token))
    return "FPGA_BRAM_ARCHITECTURE_EVIDENCE_PASS"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    try:
        result = validate(args.root)
    except (OSError, ValueError, EvidenceError) as error:
        print("fpga-bram-evidence: error: {}".format(error), file=sys.stderr)
        return 2
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
