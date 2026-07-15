#!/usr/bin/env python3
"""Public-safe SLVC DMA flow dispatcher."""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


MIN_PYTHON = (3, 6)

SIM_CASES = [
    ("run_rtl_v33c_tx_channel_table.do", "PASS: v33c TX channel table ownership split directed test"),
    ("run_rtl_v33e20a23_full_arch_throughput.do", "E20A22_FULL_ARCH_THROUGHPUT_PASS"),
    ("run_rtl_v33e20a_hybrid_rx_ingress_minimal.do", "OK: dma RTL v33e20a hybrid RX ingress minimal directed test passed."),
    ("run_rtl_v33e19_shared_frame_pool.do", "OK: dma RTL v33e19 shared frame pool test passed."),
    ("run_rtl_v13_parser_pipeline.do", "PASS tb_rtl_v13_parser_pipeline"),
    ("run_rtl_v15_axil_read_pipeline.do", "OK: dma RTL v15 AXI-Lite read pipeline test passed."),
    ("run_rtl_v33e20a10_tx_cq_space_check_pipeline.do", "PASS tb_rtl_v33e20a10_tx_cq_space_check_pipeline"),
    ("run_rtl_v28_tx_descriptor_queue.do", "OK: dma RTL v28 TX descriptor queue test passed."),
    ("run_rtl_v31_tx_desc_status_pipeline.do", "SUMMARY: v31 TX descriptor status pipeline PASS"),
    ("run_rtl_v33e20a23_w_prefetch_fifo.do", "OK: dma RTL v33e20a23 W prefetch FIFO test passed."),
]


def parse_config(path):
    values = {}
    if not path.is_file():
        raise RuntimeError("missing .config; run defconfig first")
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("CONFIG_") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value.strip().strip('"')
    return values


def require_tool(name):
    tool = shutil.which(name)
    if not tool:
        raise RuntimeError("tool not found on PATH: {}".format(name))
    return tool


def show_config(config):
    print("top: {}".format(config.get("CONFIG_SLVC_DMA_TOP", "frame_dma_wrapper")))
    print("clock_period_ns: {}".format(config.get("CONFIG_SLVC_DMA_CLOCK_PERIOD_NS", "5.000")))
    print("profile: slvc_dma_v1_512")


def run_sim(root, dry_run):
    commands = [(["vsim", "-c", "-do", script], marker) for script, marker in SIM_CASES]
    for command, _ in commands:
        print("command: " + " ".join(command))
    if dry_run:
        return
    require_tool("vsim")
    for command, marker in commands:
        completed = subprocess.run(
            command,
            cwd=str(root / "modelsim"),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        sys.stdout.write(completed.stdout)
        failed = completed.returncode != 0
        failed = failed or "** Error:" in completed.stdout
        failed = failed or "Error in macro" in completed.stdout
        failed = failed or "# Errors: 0" not in completed.stdout
        failed = failed or marker not in completed.stdout
        if failed:
            raise RuntimeError("ModelSim regression failed: {}".format(command[-1]))


def run_ooc(root, dry_run):
    tool_name = os.environ.get("VIVADO", "vivado")
    tool = shutil.which(tool_name) or tool_name
    command = [tool, "-mode", "batch", "-source", "fpga/xilinx/synth_frame_dma_ooc_2018_3.tcl"]
    print("command: " + " ".join(command))
    if dry_run:
        return
    if not shutil.which(tool_name) and not Path(tool_name).is_file():
        raise RuntimeError("tool not found on PATH: {}".format(tool_name))
    environment = os.environ.copy()
    environment["DMA_ROOT"] = str(root)
    environment.setdefault("REPORT_TAG", "fresh_clone_explore")
    if Path(tool).suffix.lower() in (".bat", ".cmd"):
        command = ["cmd", "/c", *command]
    subprocess.run(command, cwd=str(root), env=environment, check=True)


def main():
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write("flowctl: error: Python 3.6 or newer is required\n")
        return 2
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("--config", default=".config")
    sub = parser.add_subparsers(dest="command")
    defconfig = sub.add_parser("defconfig")
    defconfig.add_argument("--source", required=True)
    sub.add_parser("show-config")
    sub.add_parser("sim")
    sub.add_parser("sim-dry-run")
    sub.add_parser("fpga-ooc")
    sub.add_parser("fpga-ooc-dry-run")
    args = parser.parse_args()
    if args.command is None:
        parser.print_help()
        return 2
    root = Path(args.root).resolve()
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = root / config_path
    if args.command == "defconfig":
        source = Path(args.source).resolve()
        config_path.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
        print("wrote {}".format(config_path))
        return 0
    try:
        config = parse_config(config_path)
        if args.command == "show-config":
            show_config(config)
        elif args.command.startswith("sim"):
            run_sim(root, args.command.endswith("dry-run"))
        else:
            run_ooc(root, args.command.endswith("dry-run"))
        return 0
    except RuntimeError as error:
        print("flowctl: error: {}".format(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
