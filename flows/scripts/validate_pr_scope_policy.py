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
    "flows/scripts/validate_asic_evidence.py",
    "flows/scripts/validate_pr_scope_policy.py",
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

    publication_touched = bool(changed & EVIDENCE_TRIGGER_PATHS) or any(
        path.startswith("evidence/asic_paired_dc/") for path in changed
    )
    if publication_touched and changed & POLICY_PATHS:
        _fail("evidence PR must not modify trusted policy")
    if not publication_touched:
        return "NOT_APPLICABLE"
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
