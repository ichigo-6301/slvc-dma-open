#!/usr/bin/env python3
"""Validate evidence PR scope from trusted base-branch policy code."""

from __future__ import print_function

import argparse
import json
import re
import sys
from pathlib import Path


REPOSITORY = "ichigo-6301/slvc-dma-open"
SHA_RE = re.compile(r"[0-9a-f]{40}")

BOOTSTRAP_PR = 2
BOOTSTRAP_PATHS = frozenset({
    ".github/workflows/public-integrity.yml",
    "Makefile",
    "docs/en/limitations.md",
    "docs/en/results.md",
    "docs/en/verification.md",
    "docs/zh-CN/limitations.md",
    "docs/zh-CN/results.md",
    "docs/zh-CN/verification.md",
    "evidence/asic_paired_dc/README.md",
    "evidence/asic_paired_dc/artifacts.csv",
    "evidence/asic_paired_dc/comparisons.csv",
    "evidence/asic_paired_dc/lint.csv",
    "evidence/asic_paired_dc/manifest.yaml",
    "evidence/asic_paired_dc/points.csv",
    "evidence/asic_paired_dc/sources.csv",
    "evidence/asic_paired_dc/verification.csv",
    "flows/scripts/test_validate_asic_evidence.py",
    "flows/scripts/validate_asic_evidence.py",
    "provenance/README.md",
    "provenance/asic_paired_dc_publication.yaml",
    "provenance/checksums.sha256",
    "provenance/claims.yaml",
    "provenance/evidence.yaml",
    "provenance/nonclaims.yaml",
})

POLICY_PATHS = frozenset({
    ".github/workflows/public-integrity.yml",
    ".github/workflows/trusted-evidence-scope.yml",
    "Makefile",
    "flows/scripts/test_validate_asic_evidence.py",
    "flows/scripts/test_validate_pr_scope_policy.py",
    "flows/scripts/test_validate_throughput_publication_gate.py",
    "flows/scripts/validate_asic_evidence.py",
    "flows/scripts/validate_pr_scope_policy.py",
    "flows/scripts/validate_throughput_publication_gate.py",
})

FUTURE_PUBLICATION_PATHS = frozenset(
    path for path in BOOTSTRAP_PATHS
    if path not in {
        ".github/workflows/public-integrity.yml",
        "Makefile",
        "flows/scripts/test_validate_asic_evidence.py",
        "flows/scripts/validate_asic_evidence.py",
    }
)

EVIDENCE_TRIGGER_PATHS = FUTURE_PUBLICATION_PATHS - {
    "provenance/checksums.sha256",
}

THROUGHPUT_PUBLICATION_PATHS = frozenset({
    "README.en.md",
    "README.md",
    "docs/assets/slvc_dma_async64_end_to_end_throughput.svg",
    "docs/en/results.md",
    "docs/zh-CN/results.md",
    "evidence/slvc_dma_async64_end_to_end_sim_summary.yaml",
    "evidence/throughput_simulation/async64_end_to_end/README.md",
    "evidence/throughput_simulation/async64_end_to_end/artifacts.csv",
    "evidence/throughput_simulation/async64_end_to_end/c2b4_physical_identity.json",
    "evidence/throughput_simulation/async64_end_to_end/correctness_ladder.csv",
    "evidence/throughput_simulation/async64_end_to_end/flow_fairness.csv",
    "evidence/throughput_simulation/async64_end_to_end/latency_summary.csv",
    "evidence/throughput_simulation/async64_end_to_end/manifest.json",
    "evidence/throughput_simulation/async64_end_to_end/matrix.csv",
    "evidence/throughput_simulation/async64_end_to_end/metrics.csv",
    "evidence/throughput_simulation/async64_end_to_end/points.csv",
    "evidence/throughput_simulation/async64_end_to_end/stall_breakdown.csv",
    "evidence/throughput_simulation/async64_end_to_end/verification.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/README.md",
    "evidence/throughput_simulation/async64_end_to_end_blocked/artifacts.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/latency.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/manifest.json",
    "evidence/throughput_simulation/async64_end_to_end_blocked/matrix.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/metrics.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/points.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/stall_breakdown.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/verification.csv",
    "flows/scripts/check_showcase_render.py",
    "flows/scripts/dma_async64_throughput_contract.py",
    "flows/scripts/generate_showcase_assets.py",
    "flows/scripts/run_dma_async64_throughput_matrix.py",
    "flows/scripts/test_generate_showcase_assets.py",
    "flows/scripts/test_validate_dma_async64_throughput.py",
    "flows/scripts/test_validate_dma_async64_throughput_blocked.py",
    "flows/scripts/validate_dma_async64_throughput.py",
    "flows/scripts/validate_dma_async64_throughput_blocked.py",
    "modelsim/run_rtl_dma_async64_end_to_end_throughput.do",
    "modelsim/run_rtl_dma_axi_read_prefetch.do",
    "modelsim/run_rtl_rx_payload_cdc_bridge.do",
    "pattern/axi_hp0_dual_master_64_model.v",
    "pattern/dma_sim_def.vh",
    "pattern/tb_rtl_dma_async64_end_to_end_throughput.v",
    "pattern/tb_rtl_dma_axi_read_prefetch.v",
    "pattern/tb_rtl_rx_payload_cdc_bridge.v",
    "provenance/checksums.sha256",
    "provenance/claims.yaml",
    "provenance/evidence.yaml",
    "provenance/nonclaims.yaml",
    "provenance/showcase_assets.json",
    "rtl/integration/frame_dma_rx_top.v",
    "rtl/rx/dma_rx_payload_cdc_bridge.v",
    "rtl/tx/dma_axi_read_prefetch.v",
})

THROUGHPUT_REQUIRED_PATHS = frozenset({
    "README.en.md",
    "README.md",
    "docs/assets/slvc_dma_async64_end_to_end_throughput.svg",
    "docs/en/results.md",
    "docs/zh-CN/results.md",
    "evidence/slvc_dma_async64_end_to_end_sim_summary.yaml",
    "evidence/throughput_simulation/async64_end_to_end/manifest.json",
    "evidence/throughput_simulation/async64_end_to_end/points.csv",
    "evidence/throughput_simulation/async64_end_to_end/metrics.csv",
    "evidence/throughput_simulation/async64_end_to_end/verification.csv",
    "evidence/throughput_simulation/async64_end_to_end_blocked/manifest.json",
    "flows/scripts/dma_async64_throughput_contract.py",
    "flows/scripts/generate_showcase_assets.py",
    "flows/scripts/run_dma_async64_throughput_matrix.py",
    "flows/scripts/test_generate_showcase_assets.py",
    "flows/scripts/test_validate_dma_async64_throughput.py",
    "flows/scripts/test_validate_dma_async64_throughput_blocked.py",
    "flows/scripts/validate_dma_async64_throughput.py",
    "flows/scripts/validate_dma_async64_throughput_blocked.py",
    "modelsim/run_rtl_dma_async64_end_to_end_throughput.do",
    "modelsim/run_rtl_dma_axi_read_prefetch.do",
    "modelsim/run_rtl_rx_payload_cdc_bridge.do",
    "pattern/axi_hp0_dual_master_64_model.v",
    "pattern/dma_sim_def.vh",
    "pattern/tb_rtl_dma_async64_end_to_end_throughput.v",
    "pattern/tb_rtl_dma_axi_read_prefetch.v",
    "pattern/tb_rtl_rx_payload_cdc_bridge.v",
    "provenance/checksums.sha256",
    "provenance/claims.yaml",
    "provenance/evidence.yaml",
    "provenance/nonclaims.yaml",
    "provenance/showcase_assets.json",
    "rtl/integration/frame_dma_rx_top.v",
    "rtl/rx/dma_rx_payload_cdc_bridge.v",
    "rtl/tx/dma_axi_read_prefetch.v",
})

THROUGHPUT_TRIGGER_PATHS = frozenset({
    "docs/assets/slvc_dma_async64_end_to_end_throughput.svg",
    "evidence/slvc_dma_async64_end_to_end_sim_summary.yaml",
    "flows/scripts/validate_dma_async64_throughput.py",
})
THROUGHPUT_TRIGGER_PREFIX = "evidence/throughput_simulation/"


class PolicyError(RuntimeError):
    pass


def _fail(message):
    raise PolicyError(message)


def _normalize_paths(paths):
    normalized = []
    for path in paths:
        if not isinstance(path, str) or not path or "\\" in path:
            _fail("invalid changed path")
        if path.startswith("/") or path.startswith("../") or "/../" in path:
            _fail("unsafe changed path: {}".format(path))
        normalized.append(path)
    if len(normalized) != len(set(normalized)):
        _fail("duplicate changed path")
    return frozenset(normalized)


def validate_event(event, changed_paths, bootstrap_head, repository=REPOSITORY):
    if event.get("repository", {}).get("full_name") != repository:
        _fail("repository identity mismatch")
    pull = event.get("pull_request")
    if not isinstance(pull, dict):
        _fail("pull_request event payload is required")
    if pull.get("base", {}).get("ref") != "main":
        _fail("base branch must be main")
    base_sha = pull.get("base", {}).get("sha", "")
    head_sha = pull.get("head", {}).get("sha", "")
    if not SHA_RE.fullmatch(base_sha) or not SHA_RE.fullmatch(head_sha):
        _fail("invalid pull request commit identity")
    number = event.get("number")
    if not isinstance(number, int) or number <= 0:
        _fail("invalid pull request number")
    changed = _normalize_paths(changed_paths)

    if number == BOOTSTRAP_PR:
        if not SHA_RE.fullmatch(bootstrap_head):
            _fail("trusted bootstrap head is not configured")
        if head_sha != bootstrap_head:
            _fail("bootstrap evidence PR head SHA mismatch")
        if changed != BOOTSTRAP_PATHS:
            _fail("bootstrap evidence PR exact path set mismatch")
        return "BOOTSTRAP_EVIDENCE_SCOPE_PASS"

    throughput_publication_touched = bool(changed & THROUGHPUT_TRIGGER_PATHS) or any(
        path.startswith(THROUGHPUT_TRIGGER_PREFIX) for path in changed
    )
    asic_specific_touched = (
        "provenance/asic_paired_dc_publication.yaml" in changed or any(
            path.startswith("evidence/asic_paired_dc/") for path in changed
        )
    )
    # Claims, result pages, and nonclaims are shared publication surfaces. If
    # a throughput-specific sentinel is present, those paths belong to that
    # bounded publication; otherwise retain the existing ASIC policy behavior.
    asic_publication_touched = asic_specific_touched or (
        bool(changed & EVIDENCE_TRIGGER_PATHS) and
        not throughput_publication_touched
    )
    if asic_publication_touched and throughput_publication_touched:
        _fail("ASIC and throughput publications must use separate pull requests")
    publication_touched = asic_publication_touched or throughput_publication_touched
    if publication_touched and changed & POLICY_PATHS:
        _fail("evidence PR must not modify trusted policy")
    if not publication_touched:
        return "NOT_APPLICABLE"
    if throughput_publication_touched:
        unexpected = changed - THROUGHPUT_PUBLICATION_PATHS
        if unexpected:
            _fail("throughput PR contains forbidden path: {}".format(
                sorted(unexpected)[0]
            ))
        missing = THROUGHPUT_REQUIRED_PATHS - changed
        if missing:
            _fail("throughput PR is missing required path: {}".format(
                sorted(missing)[0]
            ))
        return "THROUGHPUT_EVIDENCE_SCOPE_PASS"
    unexpected = changed - FUTURE_PUBLICATION_PATHS
    if unexpected:
        _fail("evidence PR contains forbidden path: {}".format(sorted(unexpected)[0]))
    return "EVIDENCE_SCOPE_PASS"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--changed-files-z", required=True)
    parser.add_argument("--bootstrap-head", required=True)
    args = parser.parse_args(argv)
    try:
        event = json.loads(Path(args.event).read_text(encoding="utf-8"))
        raw_paths = Path(args.changed_files_z).read_bytes().split(b"\0")
        changed = [path.decode("utf-8") for path in raw_paths if path]
        result = validate_event(
            event, changed, args.bootstrap_head, args.repository
        )
    except (OSError, ValueError, PolicyError) as error:
        print("trusted-scope: error: {}".format(error), file=sys.stderr)
        return 2
    print("trusted-scope: {} paths={} head={}".format(
        result, len(set(changed)), event["pull_request"]["head"]["sha"]
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
