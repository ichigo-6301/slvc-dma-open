#!/usr/bin/env python3
"""Generate the deterministic public worktree SHA-256 manifest."""

from __future__ import print_function

import argparse
import hashlib
import subprocess
from pathlib import Path


CHECKSUM_PATH = "provenance/checksums.sha256"


def repository_paths(root, include_untracked=False):
    command = ["git", "-C", str(root), "ls-files", "-z"]
    if include_untracked:
        command.extend(["--cached", "--others", "--exclude-standard"])
    output = subprocess.check_output(command)
    paths = []
    for raw_path in output.split(b"\0"):
        if not raw_path:
            continue
        path = raw_path.decode("utf-8")
        if path == CHECKSUM_PATH:
            continue
        candidate = root.joinpath(*Path(path).parts)
        if not candidate.is_file():
            raise RuntimeError("checksum input is missing: {}".format(path))
        paths.append(path)
    return sorted(set(paths), key=lambda item: item.encode("utf-8"))


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def render(root, paths):
    return "".join(
        "{}  {}\n".format(sha256(root.joinpath(*Path(path).parts)), path)
        for path in paths
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", default=CHECKSUM_PATH)
    parser.add_argument("--include-untracked", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    output = root.joinpath(*Path(args.output).parts)
    text = render(root, repository_paths(root, args.include_untracked))
    if args.check:
        actual = output.read_text(encoding="utf-8") if output.is_file() else ""
        if actual != text:
            raise SystemExit("canonical checksum manifest is stale")
        print("canonical checksums: PASS files={}".format(len(text.splitlines())))
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(text)
    print("wrote {} entries to {}".format(len(text.splitlines()), output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
