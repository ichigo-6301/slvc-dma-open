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

ADAPTER_SIM_CASES = [
    ("run_rtl_v33e20a104_udp_to_shdr_directed.do", "PASS tb_rtl_v33e20a104_udp_to_shdr_directed cases=18 parser_checks=18"),
    ("run_rtl_v33e20a105_udp_to_shdr_random.do", "PASS tb_rtl_v33e20a105_udp_to_shdr_random seeds=13579bdf,2468ace1,51a7c0de,6d2b79f5 packets_per_seed=100 total=400"),
    ("run_rtl_v33e20a106_udp_to_shdr_error_matrix.do", "PASS tb_rtl_v33e20a106_udp_to_shdr_error_matrix cases=23 drops=17 accepts=23"),
    ("run_rtl_v33e20a107_udp_to_dma_smoke.do", "PASS tb_rtl_v33e20a107_udp_to_dma_smoke packets=2 channels=2 cqes=2 ch0_full_then_ch1=1"),
]

WIDE_RX_SIM_CASES = [
    ("run_rtl_rx_payload_writer_512.do", "PASS tb_rtl_rx_payload_writer_512 cases=2028"),
    ("run_rtl_rx_payload_writer_512_integration.do", "PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256"),
]

RX_CDC_COMMON_SIM_CASES = [
    ("run_rtl_rx_payload_cdc_bridge.do", "PASS tb_rtl_rx_payload_cdc_bridge"),
]

RX_ASYNC64_SIM_CASES = [
    ("run_rtl_rx_mem_async64_backend.do", "PASS tb_rtl_rx_mem_async64_backend"),
    ("run_rtl_rx_mem_async64_integration.do", "PASS tb_rtl_rx_mem_async64_integration"),
]

RX_ASYNC512_SIM_CASES = [
    ("run_rtl_rx_mem_async512_backend.do", "PASS tb_rtl_rx_mem_async512_backend"),
    ("run_rtl_rx_mem_async512_integration.do", "PASS tb_rtl_rx_mem_async512_integration"),
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


def rx_memory_profile(config):
    selected = []
    if config.get("CONFIG_SLVC_DMA_RX_WIDE_PAYLOAD") == "y":
        selected.append("same_clock_512")
    if config.get("CONFIG_SLVC_DMA_RX_MEM_ASYNC64") == "y":
        selected.append("async64")
    if config.get("CONFIG_SLVC_DMA_RX_MEM_ASYNC512") == "y":
        selected.append("async512")
    if len(selected) > 1:
        raise RuntimeError(
            "RX memory backend profiles are mutually exclusive: {}".format(
                ", ".join(selected)
            )
        )
    return selected[0] if selected else "legacy64"


def simulation_profile(config):
    adapter_enabled = config.get("CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER") == "y"
    rx_profile = rx_memory_profile(config)
    adapter_count = len(ADAPTER_SIM_CASES) if adapter_enabled else 0
    if rx_profile == "same_clock_512":
        rx_cases = WIDE_RX_SIM_CASES
    elif rx_profile == "async64":
        rx_cases = RX_CDC_COMMON_SIM_CASES + RX_ASYNC64_SIM_CASES
    elif rx_profile == "async512":
        rx_cases = RX_CDC_COMMON_SIM_CASES + RX_ASYNC512_SIM_CASES
    else:
        rx_cases = []
    return {
        "adapter_enabled": adapter_enabled,
        "rx_profile": rx_profile,
        "core_count": len(SIM_CASES),
        "adapter_count": adapter_count,
        "rx_count": len(rx_cases),
        "total_count": len(SIM_CASES) + adapter_count + len(rx_cases),
        "rx_cases": rx_cases,
    }


def show_config(config):
    profile = simulation_profile(config)
    print("top: {}".format(config.get("CONFIG_SLVC_DMA_TOP", "frame_dma_wrapper")))
    print("clock_period_ns: {}".format(config.get("CONFIG_SLVC_DMA_CLOCK_PERIOD_NS", "5.000")))
    print("mem_clock_period_ns: {}".format(config.get("CONFIG_SLVC_DMA_MEM_CLOCK_PERIOD_NS", "5.000")))
    print("profile: {}".format(
        "slvc_dma_v1_512_rx_{}".format(profile["rx_profile"])
        if profile["rx_profile"] != "legacy64" else
        "slvc_dma_v1_512_udp_ipv4_adapter_p0"))
    print("udp_ipv4_adapter: {}".format(
        "y" if profile["adapter_enabled"] else "n"))
    print("rx_memory_backend: {}".format(profile["rx_profile"]))
    print("rx_memory_cdc: {}".format(
        "y" if profile["rx_profile"].startswith("async") else "n"))
    print("simulation_profile: {}".format(
        "frozen_core_plus_rx_{}".format(profile["rx_profile"])
        if profile["rx_count"] else
        ("frozen_core_plus_udp_adapter" if profile["adapter_enabled"] else
         "frozen_core")))
    print("required_core_markers: {}".format(profile["core_count"]))
    print("required_adapter_markers: {}".format(profile["adapter_count"]))
    print("required_rx_backend_markers: {}".format(profile["rx_count"]))
    print("required_total_markers: {}".format(profile["total_count"]))


def run_sim(root, config, dry_run):
    cases = list(SIM_CASES)
    profile = simulation_profile(config)
    print("simulation_profile: {}".format(
        "frozen_core_plus_rx_{}".format(profile["rx_profile"])
        if profile["rx_count"] else
        ("frozen_core_plus_udp_adapter" if profile["adapter_enabled"] else
         "frozen_core")))
    print("required_core_markers: {}".format(profile["core_count"]))
    print("required_adapter_markers: {}".format(profile["adapter_count"]))
    print("required_rx_backend_markers: {}".format(profile["rx_count"]))
    print("required_total_markers: {}".format(profile["total_count"]))
    if profile["adapter_enabled"]:
        cases.extend(ADAPTER_SIM_CASES)
    cases.extend(profile["rx_cases"])
    commands = [(["vsim", "-c", "-do", script], marker) for script, marker in cases]
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


def run_ooc(root, config, dry_run):
    tool_name = os.environ.get("VIVADO", "vivado")
    tool = shutil.which(tool_name) or tool_name
    rx_profile = rx_memory_profile(config)
    if rx_profile == "same_clock_512":
        script = "fpga/xilinx/synth_rx_payload_512_ooc_2018_3.tcl"
    elif rx_profile == "async64":
        script = "fpga/xilinx/synth_rx_payload_async64_ooc_2018_3.tcl"
    elif rx_profile == "async512":
        script = "fpga/xilinx/synth_rx_payload_async512_ooc_2018_3.tcl"
    else:
        script = "fpga/xilinx/synth_frame_dma_ooc_2018_3.tcl"
    command = [tool, "-mode", "batch", "-source", script]
    print("command: " + " ".join(command))
    if dry_run:
        return
    if not shutil.which(tool_name) and not Path(tool_name).is_file():
        raise RuntimeError("tool not found on PATH: {}".format(tool_name))
    environment = os.environ.copy()
    environment["DMA_ROOT"] = str(root)
    environment.setdefault("REPORT_TAG", "fresh_clone_explore")
    environment.setdefault(
        "DMA_ACLK_PERIOD_NS",
        config.get("CONFIG_SLVC_DMA_CLOCK_PERIOD_NS", "5.000"),
    )
    environment.setdefault(
        "DMA_MEM_CLOCK_PERIOD_NS",
        config.get("CONFIG_SLVC_DMA_MEM_CLOCK_PERIOD_NS", "5.000"),
    )
    if Path(tool).suffix.lower() in (".bat", ".cmd"):
        command = ["cmd", "/c", *command]
    subprocess.run(command, cwd=str(root), env=environment, check=True)


def run_adapter_dc_ooc(root, dry_run):
    tool_name = os.environ.get("DC_SHELL", "dc_shell")
    tool = shutil.which(tool_name) or tool_name
    command = [tool, "-f", "run_udp_to_shdr_ooc.tcl"]
    print("command: " + " ".join(command))
    if dry_run:
        return
    if not os.environ.get("DMA_DC_TARGET_LIBRARY"):
        raise RuntimeError("DMA_DC_TARGET_LIBRARY must name a local standard-cell .db library")
    if not shutil.which(tool_name) and not Path(tool_name).is_file():
        raise RuntimeError("tool not found on PATH: {}".format(tool_name))
    subprocess.run(command, cwd=str(root / "asic" / "dc"), check=True)


def run_rx_payload_writer_dc_ooc(root, config, dry_run):
    tool_name = os.environ.get("DC_SHELL", "dc_shell")
    tool = shutil.which(tool_name) or tool_name
    command = [tool, "-f", "run_rx_payload_writer_ooc.tcl"]
    environment = os.environ.copy()
    default_profile = {
        "legacy64": "wide512",
        "same_clock_512": "wide512",
        "async64": "async64",
        "async512": "async512",
    }[rx_memory_profile(config)]
    environment.setdefault("DMA_DC_WRITER_PROFILE", default_profile)
    environment.setdefault(
        "DMA_DC_CLOCK_PERIOD_NS",
        config.get("CONFIG_SLVC_DMA_CLOCK_PERIOD_NS", "5.000"),
    )
    print("writer_profile: {}".format(environment["DMA_DC_WRITER_PROFILE"]))
    print("clock_period_ns: {}".format(environment["DMA_DC_CLOCK_PERIOD_NS"]))
    print("command: " + " ".join(command))
    if dry_run:
        return
    if not environment.get("DMA_DC_TARGET_LIBRARY"):
        raise RuntimeError("DMA_DC_TARGET_LIBRARY must name a local standard-cell .db library")
    if not shutil.which(tool_name) and not Path(tool_name).is_file():
        raise RuntimeError("tool not found on PATH: {}".format(tool_name))
    subprocess.run(
        command,
        cwd=str(root / "asic" / "dc"),
        env=environment,
        check=True,
    )


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
    sub.add_parser("adapter-dc-ooc")
    sub.add_parser("adapter-dc-ooc-dry-run")
    sub.add_parser("rx-payload-writer-dc-ooc")
    sub.add_parser("rx-payload-writer-dc-ooc-dry-run")
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
            run_sim(root, config, args.command.endswith("dry-run"))
        elif args.command.startswith("fpga-ooc"):
            run_ooc(root, config, args.command.endswith("dry-run"))
        elif args.command.startswith("adapter-dc-ooc"):
            run_adapter_dc_ooc(root, args.command.endswith("dry-run"))
        else:
            run_rx_payload_writer_dc_ooc(
                root, config, args.command.endswith("dry-run")
            )
        return 0
    except RuntimeError as error:
        print("flowctl: error: {}".format(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
