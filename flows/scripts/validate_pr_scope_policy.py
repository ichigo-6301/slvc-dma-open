#!/usr/bin/env python3
"""Validate evidence PR scope from trusted base-branch policy code."""

from __future__ import print_function

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


REPOSITORY = "ichigo-6301/slvc-dma-open"
SHA_RE = re.compile(r"[0-9a-f]{40}")

BOOTSTRAP_PR = 2
BOOTSTRAP_HEAD = "9e9159e7952314343fd2a6efa41364a26a0c0de2"
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
    ".github/workflows/trusted-evidence-scope.yml",
    "flows/scripts/test_validate_pr_scope_policy.py",
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


def validate_event(event, changed_paths, repository=REPOSITORY):
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
        if head_sha != BOOTSTRAP_HEAD:
            _fail("bootstrap evidence PR head SHA mismatch")
        if changed != BOOTSTRAP_PATHS:
            _fail("bootstrap evidence PR exact path set mismatch")
        return "BOOTSTRAP_EVIDENCE_SCOPE_PASS"

    publication_touched = any(
        path.startswith("evidence/asic_paired_dc/") for path in changed
    )
    if not publication_touched:
        return "NOT_APPLICABLE"
    if changed & POLICY_PATHS:
        _fail("evidence PR must not modify trusted policy")
    unexpected = changed - FUTURE_PUBLICATION_PATHS
    if unexpected:
        _fail("evidence PR contains forbidden path: {}".format(sorted(unexpected)[0]))
    return "EVIDENCE_SCOPE_PASS"


def fetch_changed_paths(repository, number, token):
    paths = []
    page = 1
    while True:
        url = (
            "https://api.github.com/repos/{}/pulls/{}/files?per_page=100&page={}"
            .format(repository, number, page)
        )
        request = urllib.request.Request(url)
        request.add_header("Accept", "application/vnd.github+json")
        request.add_header("Authorization", "Bearer {}".format(token))
        request.add_header("X-GitHub-Api-Version", "2022-11-28")
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except (OSError, ValueError, urllib.error.HTTPError) as error:
            _fail("cannot read pull request files: {}".format(error))
        if not isinstance(payload, list):
            _fail("GitHub files response is not a list")
        for item in payload:
            if not isinstance(item, dict) or not isinstance(item.get("filename"), str):
                _fail("GitHub files response has an invalid record")
            paths.append(item["filename"])
            previous = item.get("previous_filename")
            if previous is not None:
                if not isinstance(previous, str):
                    _fail("GitHub files response has an invalid previous path")
                paths.append(previous)
        if len(payload) < 100:
            break
        page += 1
        if page > 30:
            _fail("pull request file list exceeds policy limit")
    return paths


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--changed-files")
    args = parser.parse_args(argv)
    try:
        event = json.loads(Path(args.event).read_text(encoding="utf-8"))
        if args.changed_files:
            changed = json.loads(Path(args.changed_files).read_text(encoding="utf-8"))
        else:
            token = os.environ.get("GITHUB_TOKEN", "")
            if not token:
                _fail("GITHUB_TOKEN is required")
            changed = fetch_changed_paths(args.repository, event.get("number"), token)
        result = validate_event(event, changed, args.repository)
    except (OSError, ValueError, PolicyError) as error:
        print("trusted-scope: error: {}".format(error), file=sys.stderr)
        return 2
    print("trusted-scope: {} paths={} head={}".format(
        result, len(set(changed)), event["pull_request"]["head"]["sha"]
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
