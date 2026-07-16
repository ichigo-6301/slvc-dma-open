#!/usr/bin/env python3
"""Verify public-release checksums and local Markdown links."""

from __future__ import print_function

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path


CHECKSUM_LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")
MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
CHECKSUM_FILE = "provenance/checksums.sha256"


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = Path(args.root).resolve()
    try:
        checksum_errors, checksum_count = verify_checksums(root)
        link_errors = verify_markdown_links(root)
    except RuntimeError as error:
        print("public-hygiene: error: {}".format(error), file=sys.stderr)
        return 2

    errors = checksum_errors + link_errors
    if errors:
        for error in errors:
            print("public-hygiene: error: {}".format(error), file=sys.stderr)
        return 2
    print("public-hygiene: {} checksums and Markdown links verified".format(checksum_count))
    return 0


if __name__ == "__main__":
    sys.exit(main())
