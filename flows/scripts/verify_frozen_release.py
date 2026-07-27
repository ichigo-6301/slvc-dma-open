#!/usr/bin/env python3
"""Verify the immutable RC1 tag and its Git-object checksum manifest."""

from __future__ import print_function

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import PurePosixPath, Path


TAG = "v0.1.0-rc1"
EXPECTED_TAG_OBJECT = "ae813bc1dee2c3fe1487010cafdb8d4211968d4d"
EXPECTED_PEELED_COMMIT = "d16f7bbb2e00289383e8325a67d76557504002c0"
MANIFEST = "provenance/checksums.sha256"
CHECKSUM_LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")


def git(repo, *args):
    try:
        return subprocess.check_output(
            ["git"] + list(args), cwd=str(repo), stderr=subprocess.STDOUT
        )
    except (OSError, subprocess.CalledProcessError) as error:
        output = getattr(error, "output", b"").decode("utf-8", errors="replace")
        raise RuntimeError("git {} failed: {}".format(" ".join(args), output.strip()))


def object_text(repo, *args):
    return git(repo, *args).decode("ascii").strip()


def safe_manifest_path(relative):
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or "\\" in relative:
        raise RuntimeError("unsafe manifest path: {}".format(relative))
    return relative


def verify(repo):
    tag_object = object_text(repo, "rev-parse", TAG)
    peeled = object_text(repo, "rev-parse", TAG + "^{}")
    object_type = object_text(repo, "cat-file", "-t", TAG)
    if tag_object != EXPECTED_TAG_OBJECT:
        raise RuntimeError("tag object mismatch: {}".format(tag_object))
    if peeled != EXPECTED_PEELED_COMMIT:
        raise RuntimeError("peeled commit mismatch: {}".format(peeled))
    if object_type != "tag":
        raise RuntimeError("{} is not an annotated tag".format(TAG))

    manifest_bytes = git(repo, "show", "{}:{}".format(peeled, MANIFEST))
    expected = {}
    for line_number, raw in enumerate(
            manifest_bytes.decode("utf-8").splitlines(), 1):
        match = CHECKSUM_LINE.match(raw)
        if not match:
            raise RuntimeError("{}:{} invalid checksum line".format(MANIFEST, line_number))
        digest, relative = match.groups()
        relative = safe_manifest_path(relative)
        if relative in expected:
            raise RuntimeError("duplicate checksum path: {}".format(relative))
        expected[relative] = digest

    listed = git(repo, "ls-tree", "-r", "--name-only", "-z", peeled)
    tracked = set(
        item.decode("utf-8") for item in listed.split(b"\0") if item
    )
    tracked.discard(MANIFEST)
    if tracked != set(expected):
        missing = sorted(tracked - set(expected))
        extra = sorted(set(expected) - tracked)
        raise RuntimeError(
            "manifest coverage mismatch: missing={} extra={}".format(missing, extra)
        )

    for relative, expected_digest in sorted(expected.items()):
        payload = git(repo, "show", "{}:{}".format(peeled, relative))
        actual_digest = hashlib.sha256(payload).hexdigest()
        if actual_digest != expected_digest:
            raise RuntimeError("{} checksum mismatch".format(relative))
    return len(expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    try:
        count = verify(Path(args.repo).resolve())
    except RuntimeError as error:
        print("frozen-release: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "FROZEN_RELEASE_INTEGRITY_PASS tag={} tag_object={} peeled_commit={} files={}".format(
            TAG, EXPECTED_TAG_OBJECT, EXPECTED_PEELED_COMMIT, count
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
