#!/usr/bin/env python3
"""Prove that selected Verilog sources changed only in comments/whitespace."""

from __future__ import print_function

import argparse
import subprocess
import sys
from pathlib import Path


VERILOG_SUFFIXES = {".v", ".vh", ".sv", ".svh"}


def git_show(base, path):
    command = ["git", "show", "{}:{}".format(base, path.as_posix())]
    return subprocess.check_output(command)


def source_paths(root, requested):
    paths = []
    for value in requested:
        candidate = (root / value).resolve()
        if candidate.is_file():
            paths.append(candidate)
        elif candidate.is_dir():
            paths.extend(sorted(
                path for path in candidate.rglob("*")
                if path.is_file() and path.suffix.lower() in VERILOG_SUFFIXES
            ))
        else:
            raise RuntimeError("missing RTL path: {}".format(value))
    unique = {path.relative_to(root).as_posix(): path for path in paths}
    return [unique[key] for key in sorted(unique)]


def tokenize(data):
    """Lex enough Verilog syntax to keep strings, directives and operators intact."""
    text = data.decode("utf-8") if isinstance(data, bytes) else data
    tokens = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char.isspace():
            index += 1
            continue
        if text.startswith("//", index):
            newline = text.find("\n", index + 2)
            index = length if newline < 0 else newline + 1
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end < 0:
                raise RuntimeError("unterminated block comment")
            index = end + 2
            continue
        if char == '"':
            start = index
            index += 1
            while index < length:
                if text[index] == "\\":
                    index += 2
                elif text[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
            else:
                raise RuntimeError("unterminated string literal")
            tokens.append(text[start:index])
            continue
        if char == "\\":
            start = index
            index += 1
            while index < length and not text[index].isspace():
                index += 1
            tokens.append(text[start:index])
            continue
        if char == "`":
            start = index
            index += 1
            while index < length and (text[index].isalnum() or text[index] in "_$"):
                index += 1
            tokens.append(text[start:index])
            continue
        if char.isalpha() or char in "_$":
            start = index
            index += 1
            while index < length and (text[index].isalnum() or text[index] in "_$"):
                index += 1
            tokens.append(text[start:index])
            continue
        if char.isdigit() or char in "'":
            start = index
            index += 1
            while index < length and (text[index].isalnum() or text[index] in "_'xXzZ?+-."):
                index += 1
            tokens.append(text[start:index])
            continue
        tokens.append(char)
        index += 1
    return tokens


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="base Git commit")
    parser.add_argument("--paths", nargs="+", default=["rtl"])
    parser.add_argument(
        "--allow-missing-base",
        action="store_true",
        help="report and skip files that do not exist in the selected public base",
    )
    args = parser.parse_args()
    root = Path.cwd().resolve()
    failures = []
    checked = 0
    skipped = []
    for path in source_paths(root, args.paths):
        relative = path.relative_to(root)
        try:
            before = git_show(args.base, relative)
        except subprocess.CalledProcessError:
            if args.allow_missing_base:
                skipped.append(relative.as_posix())
                continue
            failures.append("{}: missing from base commit".format(relative))
            continue
        try:
            before_tokens = tokenize(before)
            after_tokens = tokenize(path.read_bytes())
        except (OSError, UnicodeError, RuntimeError) as error:
            failures.append("{}: {}".format(relative, error))
            continue
        checked += 1
        if before_tokens != after_tokens:
            limit = min(len(before_tokens), len(after_tokens))
            first = next((i for i in range(limit) if before_tokens[i] != after_tokens[i]), limit)
            failures.append(
                "{}: token delta at {} (base={!r}, current={!r})".format(
                    relative,
                    first,
                    before_tokens[first] if first < len(before_tokens) else "<eof>",
                    after_tokens[first] if first < len(after_tokens) else "<eof>",
                )
            )
    if failures:
        for failure in failures:
            print("COMMENT_ONLY_FAIL: {}".format(failure), file=sys.stderr)
        return 1
    print(
        "COMMENT_ONLY_PASS files={} token_delta=0 missing_base_skipped={}".format(
            checked, len(skipped)
        )
    )
    for path in skipped:
        print("COMMENT_ONLY_SKIP missing_from_base={}".format(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
