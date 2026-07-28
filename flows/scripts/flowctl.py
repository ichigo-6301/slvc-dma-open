#!/usr/bin/env python3
"""Public-safe SLVC DMA flow dispatcher."""

import argparse
from collections import OrderedDict
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


MIN_PYTHON = (3, 6)
C2_PROFILE_ID = "dma_rx512_reg_c2_b4_m2_sp64"

PROFILE_CONTRACTS = {
    "slvc_dma_512_core_only": ("legacy64", "frame_dma_wrapper"),
    "slvc_dma_512": ("legacy64", "frame_dma_wrapper"),
    "slvc_dma_512_rx_wide": ("same_clock_512", "frame_dma_rx_top"),
    "slvc_dma_512_rx_async64": ("async64", "frame_dma_rx_top"),
    "slvc_dma_512_rx_async512": ("async512", "frame_dma_rx_top"),
    C2_PROFILE_ID: ("legacy64", "dma_rx512_memory_subsystem_top"),
}

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
    ("run_rtl_rx_mem_async64_backend.do", (
        "PASS tb_rtl_rx_mem_async64_backend",
        "PASS tb_rtl_async64_aw_planner candidate_stage=1 aw_stalls=1,2,7,31 source_credit=0,short,exact,surplus four_k_offsets=000,f80,fc0,ff0,ff8",
    )),
    ("run_rtl_rx_mem_async64_integration.do", (
        "PASS tb_rtl_rx_mem_async64_integration",
        "PASS tb_rtl_rx_payload_soft_reset_quiesce scenarios=collect,multi_queue,aw_w_b,cq,clock_stop,repeat,ufc,buffered_header",
    )),
]

RX_ASYNC512_SIM_CASES = [
    ("run_rtl_rx_mem_async512_backend.do", "PASS tb_rtl_rx_mem_async512_backend"),
    ("run_rtl_rx_mem_async512_integration.do", (
        "PASS tb_rtl_rx_mem_async512_integration",
        "PASS tb_rtl_rx_payload_soft_reset_quiesce scenarios=collect,multi_queue,aw_w_b,cq,clock_stop,repeat,ufc,buffered_header",
    )),
]


def marker_count(cases):
    return sum(
        len(markers) if isinstance(markers, tuple) else 1
        for _, markers in cases
    )


def parse_config(path):
    values = {}
    if not path.is_file():
        raise RuntimeError(
            "missing {}; run 'make <profile>_defconfig' first".format(path)
        )
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("# CONFIG_") and line.endswith(" is not set"):
            key = line[2:-11]
            value = "n"
        elif line.startswith("CONFIG_") and "=" in line:
            key, value = line.split("=", 1)
            value = value.strip().strip('"')
        else:
            continue
        if key in values:
            raise RuntimeError("duplicate config symbol: {}".format(key))
        values[key] = value
    return values


def split_tool(value):
    candidate = Path(value.strip('"'))
    if candidate.is_file():
        return [str(candidate)]
    return shlex.split(value, posix=(os.name != "nt"))


def require_tool(command):
    executable = command[0]
    if not Path(executable).is_file() and not shutil.which(executable):
        raise RuntimeError("tool not found on PATH: {}".format(executable))
    return executable


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
        "rx_count": marker_count(rx_cases),
        "rx_test_count": len(rx_cases),
        "total_count": len(SIM_CASES) + adapter_count + marker_count(rx_cases),
        "rx_cases": rx_cases,
    }


def validate_config(config):
    if config.get("CONFIG_SLVC_DMA_V1_512") != "y":
        raise RuntimeError("CONFIG_SLVC_DMA_V1_512 must be enabled")

    profile_id = config.get("CONFIG_SLVC_DMA_PROFILE_ID", "")
    if profile_id not in PROFILE_CONTRACTS:
        raise RuntimeError("unknown or missing public profile: {}".format(profile_id))

    backend = rx_memory_profile(config)
    expected_backend, expected_top = PROFILE_CONTRACTS[profile_id]
    if backend != expected_backend:
        raise RuntimeError(
            "profile {} requires RX backend {}, got {}".format(
                profile_id, expected_backend, backend
            )
        )
    if config.get("CONFIG_SLVC_DMA_TOP") != expected_top:
        raise RuntimeError(
            "profile {} requires top {}, got {}".format(
                profile_id, expected_top, config.get("CONFIG_SLVC_DMA_TOP")
            )
        )

    if (config.get("CONFIG_SLVC_DMA_ADAPTER_DC_OOC") == "y" and
            config.get("CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER") != "y"):
        raise RuntimeError(
            "adapter-dc-ooc requires CONFIG_SLVC_DMA_UDP_IPV4_ADAPTER=y"
        )
    if (config.get("CONFIG_SLVC_DMA_VIVADO_ASYNC64_2022_2_OOC") == "y" and
            backend != "async64"):
        raise RuntimeError(
            "vivado-async64-2022.2-ooc requires the async64 backend"
        )

    c2_symbols = (
        "CONFIG_SLVC_DMA_N45_C2_REG_AUDIT",
        "CONFIG_SLVC_DMA_N45_C2_REG_SIM",
        "CONFIG_SLVC_DMA_N45_C2_REG_DC",
        "CONFIG_SLVC_DMA_N45_C2_REG_PNR",
        "CONFIG_SLVC_DMA_N45_C2_REG_STA",
    )
    c2_enabled = [symbol for symbol in c2_symbols if config.get(symbol) == "y"]
    if c2_enabled and profile_id != C2_PROFILE_ID:
        raise RuntimeError(
            "C2B4 stages require profile {}".format(C2_PROFILE_ID)
        )
    if (any(config.get(symbol) == "y" for symbol in c2_symbols[1:]) and
            config.get(c2_symbols[0]) != "y"):
        raise RuntimeError("C2B4 execution stages require the C2 audit stage")
    if profile_id == C2_PROFILE_ID:
        unrelated = (
            "CONFIG_SLVC_DMA_SIM",
            "CONFIG_SLVC_DMA_FPGA_OOC",
            "CONFIG_SLVC_DMA_ADAPTER_DC_OOC",
            "CONFIG_SLVC_DMA_RX_WRITER_DC_OOC",
            "CONFIG_SLVC_DMA_VIVADO_ASYNC64_2022_2_OOC",
        )
        enabled = [symbol for symbol in unrelated if config.get(symbol) == "y"]
        if enabled:
            raise RuntimeError(
                "C2B4 profile enables unrelated stages: {}".format(
                    ", ".join(enabled)
                )
            )
    return config


def show_config(config):
    validate_config(config)
    profile = simulation_profile(config)
    print("profile_id: {}".format(config["CONFIG_SLVC_DMA_PROFILE_ID"]))
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
    print("scheduled_rx_backend_tests: {}".format(profile["rx_test_count"]))
    print("required_total_markers: {}".format(profile["total_count"]))
    print("enabled_stages: {}".format(
        ", ".join(
            stage for stage, spec in STAGES.items()
            if spec.get("symbol") and config.get(spec["symbol"]) == "y"
        ) or "none"
    ))


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
    print("scheduled_rx_backend_tests: {}".format(profile["rx_test_count"]))
    print("required_total_markers: {}".format(profile["total_count"]))
    if profile["adapter_enabled"]:
        cases.extend(ADAPTER_SIM_CASES)
    cases.extend(profile["rx_cases"])
    tool = split_tool(os.environ.get("VSIM", "vsim"))
    commands = [(tool + ["-c", "-do", script], markers)
                for script, markers in cases]
    for command, _ in commands:
        print("command: " + " ".join(command))
    if dry_run:
        return
    require_tool(tool)
    for command, markers in commands:
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
        required_markers = markers if isinstance(markers, tuple) else (markers,)
        failed = failed or any(
            marker not in completed.stdout for marker in required_markers
        )
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


SHOWCASE_COMMANDS = {
    "n45-c2-reg-audit": "c2-audit",
    "n45-c2-reg-sim": "c2-sim",
    "n45-c2-reg-dc": "c2-dc",
    "n45-c2-reg-pnr": "c2-pnr",
    "n45-c2-reg-sta": "c2-sta",
    "vivado-async64-2022.2-ooc": "vivado-async64-2022.2-ooc",
    "n45-a5-model-audit": "a5-model-audit",
    "n45-a5-clock-delivery-audit": "a5-clock-delivery-audit",
}


STAGES = OrderedDict([
    ("n45-c2-reg-audit", {
        "symbol": "CONFIG_SLVC_DMA_N45_C2_REG_AUDIT",
        "selected": True,
        "kind": "showcase",
    }),
    ("sim", {
        "symbol": "CONFIG_SLVC_DMA_SIM",
        "selected": True,
        "kind": "sim",
    }),
    ("n45-c2-reg-sim", {
        "symbol": "CONFIG_SLVC_DMA_N45_C2_REG_SIM",
        "selected": True,
        "kind": "showcase",
    }),
    ("fpga-ooc", {
        "symbol": "CONFIG_SLVC_DMA_FPGA_OOC",
        "selected": True,
        "kind": "fpga-ooc",
    }),
    ("vivado-async64-2022.2-ooc", {
        "symbol": "CONFIG_SLVC_DMA_VIVADO_ASYNC64_2022_2_OOC",
        "selected": True,
        "kind": "showcase",
    }),
    ("adapter-dc-ooc", {
        "symbol": "CONFIG_SLVC_DMA_ADAPTER_DC_OOC",
        "selected": True,
        "kind": "adapter-dc-ooc",
    }),
    ("rx-payload-writer-dc-ooc", {
        "symbol": "CONFIG_SLVC_DMA_RX_WRITER_DC_OOC",
        "selected": True,
        "kind": "rx-writer-dc-ooc",
    }),
    ("n45-c2-reg-dc", {
        "symbol": "CONFIG_SLVC_DMA_N45_C2_REG_DC",
        "selected": True,
        "kind": "showcase",
    }),
    ("n45-c2-reg-pnr", {
        "symbol": "CONFIG_SLVC_DMA_N45_C2_REG_PNR",
        "selected": True,
        "kind": "showcase",
    }),
    ("n45-c2-reg-sta", {
        "symbol": "CONFIG_SLVC_DMA_N45_C2_REG_STA",
        "selected": True,
        "kind": "showcase",
    }),
    ("n45-a5-model-audit", {
        "symbol": None,
        "selected": False,
        "kind": "showcase",
    }),
    ("n45-a5-clock-delivery-audit", {
        "symbol": None,
        "selected": False,
        "kind": "showcase",
    }),
])


LEGACY_COMMANDS = {}
for _stage in STAGES:
    LEGACY_COMMANDS[_stage] = (_stage, False)
    if _stage != "n45-c2-reg-audit":
        LEGACY_COMMANDS[_stage + "-dry-run"] = (_stage, True)


def run_showcase(root, stage, dry_run):
    showcase_command = SHOWCASE_COMMANDS[stage]
    invocation = [
        sys.executable,
        str(root / "flows/scripts/n45_showcase.py"),
        "--root", str(root), showcase_command,
    ]
    if dry_run:
        invocation.append("--dry-run")
    completed = subprocess.run(invocation, cwd=str(root))
    if completed.returncode:
        raise RuntimeError(
            "{} failed with exit status {}".format(stage, completed.returncode)
        )


def run_stage(root, config_path, config, stage, dry_run, enforce_enabled=True):
    spec = STAGES[stage]
    symbol = spec.get("symbol")
    if enforce_enabled and symbol and config.get(symbol) != "y":
        raise RuntimeError(
            "{} is disabled by {} in {}".format(stage, symbol, config_path)
        )

    print("stage: {}".format(stage))
    print("config_symbol: {}".format(symbol or "utility"))
    print("dry_run: {}".format("y" if dry_run else "n"))
    sys.stdout.flush()

    kind = spec["kind"]
    if kind == "sim":
        run_sim(root, config, dry_run)
    elif kind == "fpga-ooc":
        run_ooc(root, config, dry_run)
    elif kind == "adapter-dc-ooc":
        run_adapter_dc_ooc(root, dry_run)
    elif kind == "rx-writer-dc-ooc":
        run_rx_payload_writer_dc_ooc(root, config, dry_run)
    else:
        run_showcase(root, stage, dry_run)


def run_selected(root, config_path, config, dry_run):
    selected = [
        stage for stage, spec in STAGES.items()
        if spec.get("selected") and spec.get("symbol") and
        config.get(spec["symbol"]) == "y"
    ]
    if not selected:
        raise RuntimeError("selected profile enables no executable stages")
    print("selected_stages: {}".format(", ".join(selected)))
    for stage in selected:
        run_stage(root, config_path, config, stage, dry_run)


def list_stages():
    for stage, spec in STAGES.items():
        print("{:<38} symbol={:<49} selected={}".format(
            stage,
            spec.get("symbol") or "utility",
            "y" if spec.get("selected") else "n",
        ))


def write_defconfig(source, destination):
    source = source.resolve()
    if not source.is_file():
        raise RuntimeError("missing defconfig: {}".format(source))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
    print("wrote {}".format(destination))


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
    sub.add_parser("validate-config")
    sub.add_parser("list-stages")
    run = sub.add_parser("run")
    run.add_argument("--stage", choices=tuple(STAGES), required=True)
    run.add_argument("--dry-run", action="store_true")
    selected = sub.add_parser("run-selected")
    selected.add_argument("--dry-run", action="store_true")
    for command in sorted(LEGACY_COMMANDS):
        sub.add_parser(command)
    args = parser.parse_args()
    if args.command is None:
        parser.print_help()
        return 2
    root = Path(args.root).resolve()
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = root / config_path
    try:
        if args.command == "defconfig":
            write_defconfig(Path(args.source), config_path)
            return 0
        if args.command == "list-stages":
            list_stages()
            return 0

        if args.command in LEGACY_COMMANDS:
            stage, dry_run = LEGACY_COMMANDS[args.command]
            print(
                "flowctl: warning: '{}' is a compatibility alias; use "
                "'make {}{}'".format(
                    args.command, stage, "-dry-run" if dry_run else ""
                ),
                file=sys.stderr,
            )
            if stage in SHOWCASE_COMMANDS and not config_path.is_file():
                config = {}
            else:
                config = parse_config(config_path)
            run_stage(
                root, config_path, config, stage, dry_run,
                enforce_enabled=False,
            )
            return 0

        config = parse_config(config_path)
        validate_config(config)
        if args.command == "show-config":
            show_config(config)
        elif args.command == "validate-config":
            print(
                "DMA_FLOW_CONFIG_VALID profile={} backend={} stages={}".format(
                    config["CONFIG_SLVC_DMA_PROFILE_ID"],
                    rx_memory_profile(config),
                    sum(
                        1 for spec in STAGES.values()
                        if spec.get("symbol") and
                        config.get(spec["symbol"]) == "y"
                    ),
                )
            )
        elif args.command == "run":
            run_stage(root, config_path, config, args.stage, args.dry_run)
        else:
            run_selected(root, config_path, config, args.dry_run)
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print("flowctl: error: {}".format(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
