#!/usr/bin/env python3
"""Run the fixed private Async64 throughput matrix with ModelSim or Questa."""

from __future__ import print_function

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    from flows.scripts.dma_async64_throughput_contract import (
        correctness_ladder_points, matrix_points)
except ImportError:
    from dma_async64_throughput_contract import (
        correctness_ladder_points, matrix_points)


PASS_MARKER = "DMA_ASYNC64_END_TO_END_THROUGHPUT_PASS"
POINT_MARKER = "DMA_TP_POINT"
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
EXPECTED_SIMULATORS = {
    "windows": (
        "Model Technology ModelSim SE-64 vsim 2020.4 "
        "Simulator 2020.10 Oct 13 2020"
    ),
    "linux": "Questa Sim-64 vsim 10.7c Simulator 2018.08 Aug 17 2018",
}


class RunError(Exception):
    pass


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def command_output(command, cwd, env=None):
    process = subprocess.Popen(command, cwd=str(cwd), env=env,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
    output, _ = process.communicate()
    if process.returncode != 0:
        raise RunError("command failed ({}): {}".format(
            process.returncode, " ".join(command)))
    return output.decode("utf-8", errors="replace").strip()


def git_output(root, args):
    command = ["git", "-c", "safe.directory={}".format(root.as_posix())] + args
    process = subprocess.Popen(command, cwd=str(root), stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    output, error = process.communicate()
    if process.returncode != 0:
        raise RunError("git command failed ({}): {}: {}".format(
            process.returncode, " ".join(command),
            error.decode("utf-8", errors="replace").strip()))
    return output.decode("utf-8", errors="replace").strip()


def git_head(root):
    return git_output(root, ["rev-parse", "HEAD"]).splitlines()[-1]


def git_commit(root, revision):
    return git_output(
        root, ["rev-parse", "--verify", "{}^{{commit}}".format(revision)]
    ).splitlines()[-1]


def git_status(root):
    return git_output(
        root, ["status", "--porcelain", "--untracked-files=all"]
    )


def validate_source_checkout(root, requested_commit=None):
    head = git_head(root)
    if not HEX40.match(head):
        raise RunError("checkout HEAD is not a full commit SHA")
    if requested_commit is not None and not HEX40.match(requested_commit):
        raise RunError("--source-commit must be a full 40-character SHA")
    source_commit = git_commit(root, requested_commit or head)
    if source_commit != head:
        raise RunError(
            "source commit {} does not match checkout HEAD {}".format(
                source_commit, head
            )
        )
    dirty = git_status(root)
    if dirty:
        first = dirty.splitlines()[0]
        raise RunError(
            "source checkout must be clean before simulation: {}".format(first)
        )
    return source_commit


def validate_simulator(platform, version):
    expected = EXPECTED_SIMULATORS[platform]
    if version != expected:
        raise RunError(
            "unexpected simulator for {}: expected {!r}, got {!r}".format(
                platform, expected, version
            )
        )


def run(args):
    root = Path(args.root).resolve()
    modelsim = root / "modelsim"
    output_dir = Path(args.output_dir).resolve()
    source_commit = validate_source_checkout(root, args.source_commit)
    output_dir.mkdir(parents=True, exist_ok=True)
    selected = set(args.points.split(",")) if args.points else None
    contract = (matrix_points() if args.suite == "matrix" else
                correctness_ladder_points())
    points = [point for point in contract
              if selected is None or point["point_id"] in selected]
    if selected is not None and selected != {p["point_id"] for p in points}:
        missing = sorted(selected - {p["point_id"] for p in points})
        raise RunError("unknown matrix point(s): {}".format(", ".join(missing)))

    version = command_output([args.vsim, "-version"], modelsim).splitlines()[0]
    validate_simulator(args.platform, version)
    records = []
    failures = []
    for index, point in enumerate(points, 1):
        validate_source_checkout(root, source_commit)
        log_path = output_dir / (point["point_id"] + ".log")
        if log_path.exists() and not args.force:
            raise RunError("refusing to overwrite {}".format(log_path))
        env = os.environ.copy()
        env.update({
            "DMA_TP_CASE": point["scenario"],
            "DMA_TP_FRAMES": str(point["frames"]),
            "DMA_TP_PAYLOAD_BYTES": str(point["payload_arg_bytes"]),
            "DMA_TP_SHARED_SERVICE": str(point["shared_service"]),
            "DMA_TP_RESPONSE_LATENCY":
                str(point["response_latency_cycles"]),
            "DMA_TP_SERVICE_PERCENT": str(point["service_percent"]),
            "DMA_TP_MEM_PHASE_NS": str(point["mem_phase_ns"]),
        })
        print("[{}/{}] {} {}".format(index, len(points), args.platform,
                                      point["point_id"]), flush=True)
        with log_path.open("wb") as log_handle:
            process = subprocess.Popen(
                [args.vsim, "-c", "-do",
                 "run_rtl_dma_async64_end_to_end_throughput.do"],
                cwd=str(modelsim), env=env, stdout=log_handle,
                stderr=subprocess.STDOUT)
            returncode = process.wait()
        validate_source_checkout(root, source_commit)
        log_text = log_path.read_bytes().decode("utf-8", errors="replace")
        passed = (returncode == 0 and
                  log_text.count(PASS_MARKER) == 1 and
                  log_text.count(POINT_MARKER) == 1 and
                  "** Fatal:" not in log_text and
                  "** Error:" not in log_text)
        record = dict(point)
        record.update({
            "platform": args.platform,
            "simulator": version,
            "source_commit": source_commit,
            "returncode": returncode,
            "status": "PASS" if passed else "FAIL",
            "log_file": log_path.name,
            "log_sha256": sha256_file(log_path),
            "log_size_bytes": log_path.stat().st_size,
        })
        records.append(record)
        if not passed:
            failures.append(point["point_id"])
            if not args.keep_going:
                break

    validate_source_checkout(root, source_commit)
    index_path = output_dir / "run_index.json"
    index_path.write_text(
        json.dumps({
            "schema_version": 1,
            "suite": args.suite,
            "platform": args.platform,
            "simulator": version,
            "source_commit": source_commit,
            "seed": 71,
            "records": records,
        }, indent=2, sort_keys=True) + "\n",
        encoding="utf-8")
    if failures:
        raise RunError("matrix failures: {}".format(", ".join(failures)))
    if len(records) != len(points):
        raise RunError("matrix stopped before all selected points completed")
    print("DMA_ASYNC64_SUITE_PASS suite={} platform={} points={} index={}".format(
        args.suite, args.platform, len(records), index_path))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--platform", required=True,
                        choices=("windows", "linux"))
    parser.add_argument("--suite", default="matrix",
                        choices=("matrix", "ladder"))
    parser.add_argument("--vsim", default="vsim")
    parser.add_argument("--source-commit")
    parser.add_argument("--points",
                        help="comma-separated subset of fixed point IDs")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--keep-going", action="store_true")
    args = parser.parse_args(argv)
    try:
        return run(args)
    except (OSError, RunError, ValueError) as exc:
        print("DMA_ASYNC64_MATRIX_FAIL: {}".format(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
