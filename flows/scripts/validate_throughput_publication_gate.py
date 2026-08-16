#!/usr/bin/env python3
"""Fail-closed gate for the bounded Async64 RTL-simulation publication."""

from __future__ import print_function

import argparse
import hashlib
import json
import re
import subprocess
import sys
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

PROTECTED_MANIFEST_HASHES = {
    CLAIMS_REL: "b066370c84de86c0647705df19d919735bb6a7c7f10c6392a33be6a1de3f9a76",
    EVIDENCE_REL: "f919b98bd6b0b9fc6446229ac2c7acee4dcf2df7607a28e8d4cce99201d3fa0d",
    NONCLAIMS_REL: "98b910f4bd9b1e2020e44400c61c21445d3f5d413841fa95e21fa0042223dc1c",
}

REQUIRED_PATHS = frozenset({
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
    SUMMARY_REL,
    Path("docs/en/results.md"),
    Path("docs/zh-CN/results.md"),
    Path("flows/scripts/dma_async64_throughput_contract.py"),
    Path("flows/scripts/run_dma_async64_throughput_matrix.py"),
    Path("flows/scripts/test_validate_dma_async64_throughput.py"),
    Path("flows/scripts/test_validate_dma_async64_throughput_blocked.py"),
    VALIDATOR_REL,
    BLOCKED_VALIDATOR_REL,
    CLAIMS_REL,
    EVIDENCE_REL,
    NONCLAIMS_REL,
    SHOWCASE_REL,
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


def _require_tokens(label, text, tokens):
    for token in tokens:
        if token not in text:
            _fail("{} is missing fixed token: {}".format(label, token))


def _validate_showcase_binding(root):
    try:
        manifest = json.loads(_read_text(root / SHOWCASE_REL))
    except (TypeError, ValueError) as error:
        _fail("invalid showcase asset manifest: {}".format(error))
    assets = manifest.get("assets")
    if not isinstance(assets, list):
        _fail("showcase asset manifest has no assets list")
    matches = [item for item in assets if isinstance(item, dict) and
               item.get("path") == CHART_REL.as_posix()]
    if len(matches) != 1:
        _fail("throughput chart must have exactly one showcase binding")
    chart = matches[0]
    if chart.get("numeric_authority") is not False:
        _fail("throughput chart must not be numeric authority")
    if chart.get("source_type") != "deterministic_generated_showcase":
        _fail("throughput chart source type mismatch")
    if chart.get("claim_ids") != [CLAIM_ID]:
        _fail("throughput chart claim binding mismatch")
    inputs = chart.get("inputs")
    input_paths = {
        item.get("path") for item in inputs or [] if isinstance(item, dict)
    }
    for required in (SUMMARY_REL.as_posix(), (PACKAGE_REL / "points.csv").as_posix(),
                     CLAIMS_REL.as_posix()):
        if required not in input_paths:
            _fail("throughput chart is missing source binding: {}".format(required))


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

    _require_tokens("throughput claim", claim_block, (
        "profile: slvc_dma_v1_512_async64_full_loopback_sim",
        "value: 3.831177",
        "unit: MB/s/MHz",
        "383.117735 MB/s",
        "3.064942 Gb/s",
        "95.779434%",
        "resume_eligible: false",
        "status: verified",
        "- {}".format(EVIDENCE_ID),
    ))
    _require_tokens("throughput evidence", evidence_block, (
        "path: {}".format(SUMMARY_REL.as_posix()),
        "- {}".format(CLAIM_ID),
        "public: true",
    ))
    _require_tokens("throughput nonclaim", nonclaim_block, (
        "status: not_claimed",
        "FPGA",
        "64 B/cycle",
        "Fmax",
    ))

    summary = _read_text(root / SUMMARY_REL)
    _require_tokens("throughput summary", summary, (
        "classification: VERIFIED_RTL_SIMULATION",
        "claim_id: {}".format(CLAIM_ID),
        "e2e_mbps_per_mhz: 3.831177",
        "mb_per_s_at_100mhz: 383.117735",
        "gbits_per_s_at_100mhz: 3.064942",
        "model_efficiency_percent: 95.779434",
        "resume_eligible: false",
        "fpga_emulation: pending_not_measured_not_claimed",
    ))
    _validate_showcase_binding(root)

    chart_text = _read_text(root / CHART_REL)
    _require_tokens("throughput chart", chart_text, (
        "1600", "1000", CLAIM_ID,
        "Pending / not measured / not claimed",
    ))

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
