#!/usr/bin/env python3
"""Verify public-release checksums and local Markdown links."""

from __future__ import print_function

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


CHECKSUM_LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")
MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
CLAIM_MARKER = re.compile(
    r"<!--\s*claim:([A-Za-z0-9_.-]+)\s+maturity:([A-Za-z_]+)\s*-->"
)
CLAIM_BLOCK = re.compile(
    r"(?ms)^  - id: ([A-Za-z0-9_.-]+)\n(.*?)(?=^  - id: |\Z)"
)
CLAIM_STATUS = re.compile(r"(?m)^    status: ([A-Za-z_]+)\s*$")
CHECKSUM_FILE = "provenance/checksums.sha256"
ASSET_MANIFEST_FILE = "provenance/showcase_assets.json"
README_FILES = ("README.md", "README.en.md")


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_path(root, relative):
    candidate = Path(relative)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise RuntimeError("unsafe checksum path: {}".format(relative))
    return root.joinpath(*candidate.parts)


def tracked_files(root):
    try:
        output = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=str(root), universal_newlines=False
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError("git ls-files failed: {}".format(error))
    return set(
        item.decode("utf-8") for item in output.split(b"\0") if item
    )


def verify_checksums(root):
    manifest = root / CHECKSUM_FILE
    if not manifest.is_file():
        raise RuntimeError("missing {}".format(CHECKSUM_FILE))

    expected = {}
    errors = []
    for line_number, raw in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
        match = CHECKSUM_LINE.match(raw)
        if not match:
            errors.append("{}:{} invalid checksum line".format(CHECKSUM_FILE, line_number))
            continue
        digest, relative = match.groups()
        if relative in expected:
            errors.append("{} duplicate checksum entry".format(relative))
            continue
        expected[relative] = digest
        try:
            path = safe_path(root, relative)
        except RuntimeError as error:
            errors.append(str(error))
            continue
        if not path.is_file():
            errors.append("{} missing".format(relative))
        elif sha256_file(path) != digest:
            errors.append("{} checksum mismatch".format(relative))

    tracked = tracked_files(root)
    tracked.discard(CHECKSUM_FILE)
    expected_paths = set(expected)
    for relative in sorted(tracked - expected_paths):
        errors.append("{} is tracked but absent from checksum manifest".format(relative))
    for relative in sorted(expected_paths - tracked):
        errors.append("{} is checksummed but not tracked".format(relative))
    return errors, len(expected)


def verify_markdown_links(root):
    errors = []
    for path in sorted(root.rglob("*.md")):
        if ".git" in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for raw_target in MARKDOWN_LINK.findall(text):
            target = raw_target.strip().strip("<>")
            if not target or target.startswith(("#", "http://", "https://", "mailto:")):
                continue
            target = target.split("#", 1)[0]
            if target and not (path.parent / target).resolve().exists():
                errors.append("{}: broken link {}".format(path.relative_to(root), target))
    return errors


def load_claim_statuses(root):
    path = root / "provenance" / "claims.yaml"
    if not path.is_file():
        raise RuntimeError("missing provenance/claims.yaml")
    statuses = {}
    text = path.read_text(encoding="utf-8")
    for claim_id, block in CLAIM_BLOCK.findall(text):
        match = CLAIM_STATUS.search(block)
        if not match:
            raise RuntimeError("claim {} has no status".format(claim_id))
        statuses[claim_id] = match.group(1)
    return statuses


def verify_readme_claim_parity(root):
    errors = []
    by_readme = {}
    statuses = load_claim_statuses(root)
    for relative in README_FILES:
        path = root / relative
        if not path.is_file():
            errors.append("{} missing".format(relative))
            continue
        markers = CLAIM_MARKER.findall(path.read_text(encoding="utf-8"))
        if len(markers) != len(set(markers)):
            errors.append("{} contains duplicate claim markers".format(relative))
        by_readme[relative] = set(markers)
        for claim_id, maturity in markers:
            if claim_id not in statuses:
                errors.append("{} references unknown claim {}".format(relative, claim_id))
            elif statuses[claim_id] != maturity:
                errors.append(
                    "{} claim {} maturity {} does not match status {}".format(
                        relative, claim_id, maturity, statuses[claim_id]
                    )
                )
    if len(by_readme) == len(README_FILES):
        first = by_readme[README_FILES[0]]
        second = by_readme[README_FILES[1]]
        if first != second:
            errors.append(
                "README claim marker mismatch: only {}={} only {}={}".format(
                    README_FILES[0], sorted(first - second),
                    README_FILES[1], sorted(second - first)
                )
            )
    marker_count = len(by_readme.get(README_FILES[0], set()))
    return errors, marker_count


def verify_showcase_assets(root):
    manifest_path = root / ASSET_MANIFEST_FILE
    if not manifest_path.is_file():
        raise RuntimeError("missing {}".format(ASSET_MANIFEST_FILE))
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (TypeError, ValueError) as error:
        raise RuntimeError("invalid {}: {}".format(ASSET_MANIFEST_FILE, error))
    errors = []
    seen = set()
    statuses = load_claim_statuses(root)
    assets = manifest.get("assets")
    if not isinstance(assets, list) or not assets:
        return ["{} has no assets".format(ASSET_MANIFEST_FILE)], 0
    for entry in assets:
        if not isinstance(entry, dict):
            errors.append("{} contains a non-object asset".format(ASSET_MANIFEST_FILE))
            continue
        relative = entry.get("path")
        digest = entry.get("sha256")
        if not isinstance(relative, str) or not relative.startswith("docs/assets/"):
            errors.append("unsafe showcase asset path {}".format(relative))
            continue
        if relative in seen:
            errors.append("duplicate showcase asset {}".format(relative))
            continue
        seen.add(relative)
        try:
            path = safe_path(root, relative)
        except RuntimeError as error:
            errors.append(str(error))
            continue
        if not path.is_file():
            errors.append("showcase asset {} missing".format(relative))
        elif not isinstance(digest, str) or sha256_file(path) != digest:
            errors.append("showcase asset {} hash mismatch".format(relative))
        for claim_id in entry.get("claim_ids", []):
            if claim_id not in statuses:
                errors.append("showcase asset {} references unknown claim {}".format(relative, claim_id))
    return errors, len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = Path(args.root).resolve()
    try:
        checksum_errors, checksum_count = verify_checksums(root)
        link_errors = verify_markdown_links(root)
        claim_errors, claim_count = verify_readme_claim_parity(root)
        asset_errors, asset_count = verify_showcase_assets(root)
    except RuntimeError as error:
        print("public-hygiene: error: {}".format(error), file=sys.stderr)
        return 2

    errors = checksum_errors + link_errors + claim_errors + asset_errors
    if errors:
        for error in errors:
            print("public-hygiene: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "public-hygiene: {} checksums, Markdown links, {} README claims, and {} showcase assets verified".format(
            checksum_count, claim_count, asset_count
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
