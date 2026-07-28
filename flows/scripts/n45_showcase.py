#!/usr/bin/env python3
"""Public-safe entry points for the measured Nangate45 showcase profiles."""

from __future__ import print_function

import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


PROFILE_ID = "dma_rx512_reg_c2_b4_m2_sp64"
TOP = "dma_rx512_memory_subsystem_top"
EXPECTED_DB_SHA256 = "111c429e7ae9341d51f5f04b0e4c7574e5c1359de32d51b151470463abe187de"
EXPECTED_LIBERTY_SHA256 = "8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1"
EXPECTED_ORFS_COMMIT = "bea7dcd7be7f26d1328f6058b01cf42bf4352aa2"
EXPECTED_ORFS_IMAGE = (
    "openroad/orfs@sha256:"
    "5fb6465e18c42bfaa19f0ba40190f1c75cb6118feffd236b13ed8081ff3f573f"
)
MEASURED_MAPPED_NETLIST_SHA256 = (
    "38cf919b1dacf64516cca078f4e70cb76bb6e64f0c142561f5e73b44dc74a8ad"
)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_file(path, label, expected_sha=None):
    path = Path(path).resolve()
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError("missing {}: {}".format(label, path))
    if expected_sha and sha256(path) != expected_sha:
        raise RuntimeError("{} SHA-256 mismatch: {}".format(label, path))
    return path


def strip_matching_quotes(value):
    if (len(value) >= 2 and value[0] == value[-1] and
            value[0] in ("'", '"')):
        return value[1:-1]
    return value


def split_tool(value):
    value = value.strip()
    if not value:
        raise RuntimeError("tool command is empty")
    candidate = Path(strip_matching_quotes(value))
    if candidate.is_file():
        return [str(candidate)]
    try:
        command = shlex.split(value, posix=(os.name != "nt"))
    except ValueError as error:
        raise RuntimeError("invalid tool command: {}".format(error))
    if os.name == "nt":
        command = [strip_matching_quotes(item) for item in command]
    if not command or not command[0]:
        raise RuntimeError("tool command is empty")
    shell_operator_chars = "|&;<>\n\r"
    if any(any(char in item for char in shell_operator_chars)
           for item in command):
        raise RuntimeError("tool command must not contain shell operators")
    return command


def print_command(command):
    if os.name == "nt":
        rendered = subprocess.list2cmdline([str(item) for item in command])
    else:
        rendered = " ".join(shlex.quote(str(item)) for item in command)
    print("command: " + rendered)


def wrap_windows_batch(command, resolved_executable=None):
    executable = resolved_executable or command[0]
    if os.name == "nt" and Path(executable).suffix.lower() in (".bat", ".cmd"):
        return ["cmd", "/c"] + command
    return command


def run_command(command, root, environment, dry_run, cwd=None):
    if dry_run:
        print_command(wrap_windows_batch(command))
        return
    executable = command[0]
    resolved = (str(Path(executable).resolve())
                if Path(executable).is_file() else shutil.which(executable))
    if not resolved:
        raise RuntimeError("tool not found: {}".format(executable))
    command = wrap_windows_batch([resolved] + command[1:], resolved)
    print_command(command)
    subprocess.run(
        command, cwd=str(cwd or root), env=environment, check=True
    )


def c2_environment(root):
    environment = os.environ.copy()
    environment.update({
        "DMA_A3_CHANNELS": "2",
        "DMA_A3_PAYLOAD_WORDS": "512",
        "DMA_A3_PAYLOAD_AW": "9",
        "DMA_A3_FIXED_DEPTH": "128",
        "DMA_A3_FIXED_DEPTH_AW": "7",
        "DMA_A3_PAYLOAD_RAM_SOURCE": str(
            root / "flows/asic/c2b4/rtl/dma_payload_beat_ram.v"
        ),
        "DMA_A3_FRAME_PAYLOAD_RAM_SOURCE": str(
            root / "flows/asic/c2b4/rtl/dma_frame_payload_ram.v"
        ),
        "DMA_A3_FRAME_SHARED_POOL_SOURCE": str(
            root / "rtl/rx/dma_frame_shared_pool.v"
        ),
    })
    return environment


def run_c2_sim(root, dry_run):
    cases = (
        ("run_rtl_rx_payload_writer_512.do", "PASS tb_rtl_rx_payload_writer_512 cases=2028"),
        ("run_rtl_rx_payload_writer_512_integration.do", "PASS tb_rtl_rx_payload_writer_512_integration"),
        ("run_rtl_rx_mem_async64_backend.do", "PASS tb_rtl_rx_mem_async64_backend"),
        ("run_rtl_rx_mem_async64_integration.do", "PASS tb_rtl_rx_mem_async64_integration"),
        ("run_rtl_rx_mem_async512_backend.do", "PASS tb_rtl_rx_mem_async512_backend"),
        ("run_rtl_rx_mem_async512_integration.do", "PASS tb_rtl_rx_mem_async512_integration"),
        ("run_dma_a3_profile.do", "PASS tb_dma_rx512_memory_subsystem"),
        ("run_dma_a3_config_contract.do", "PASS tb_dma_a3_config_contract channels=2"),
        ("run_dma_a3_banked_memory_contract.do", "PASS tb_dma_a3_banked_memory_contract depth=128"),
    )
    tool = split_tool(os.environ.get("VSIM", "vsim"))
    environment = c2_environment(root)
    for script, marker in cases:
        command = tool + ["-c", "-do", script]
        print_command(command)
        print("required_marker: " + marker)
        if dry_run:
            continue
        completed = subprocess.run(
            command, cwd=str(root / "modelsim"), env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        sys.stdout.write(completed.stdout)
        if (completed.returncode != 0 or marker not in completed.stdout or
                "** Error:" in completed.stdout or
                "# Errors: 0" not in completed.stdout):
            raise RuntimeError("C2 regression failed: {}".format(script))


def c2_build_root(root):
    value = os.environ.get("DMA_C2_BUILD_ROOT")
    return Path(value).resolve() if value else root / "build/n45_c2_register"


def run_c2_dc(root, dry_run):
    build_root = c2_build_root(root)
    db_value = os.environ.get("DMA_N45_STDCELL_DB", "<DMA_N45_STDCELL_DB>")
    db = Path(db_value)
    if not dry_run:
        db = require_file(db, "Nangate45 standard-cell DB", EXPECTED_DB_SHA256)
    sdc = require_file(
        root / "flows/asic/c2b4/constraints/dc550.sdc",
        "C2 DC constraint",
        "d40bffb6c70ebdb460d70791e7c83fe2f6ee1d8c23923c68012f1d9b8ef3988c",
    )
    environment = c2_environment(root)
    environment.update({
        "DMA_A3_ROOT": str(root),
        "DMA_A3_BUILD_ROOT": str(build_root),
        "DMA_A3_CACHE_ROOT": str(build_root / "cache/dc550"),
        "DMA_A3_PROFILE_ID": PROFILE_ID,
        "DMA_A3_META_DEPTH": "2",
        "DMA_A3_META_AW": "1",
        "DMA_A3_SHARED_BLOCK_NUM": "64",
        "DMA_A3_SHARED_BLOCK_AW": "6",
        "DMA_A3_FIXED_WIDTH_BANKS": "4",
        "DMA_A3_FIXED_DEPTH_BANKS": "2",
        "DMA_A3_FIXED_REGISTER_ARRAY_COUNT": "8",
        "DMA_A3_EXPECTED_FIXED_PAYLOAD_BITS": "65536",
        "DMA_A3_EXPECTED_SHARED_PAYLOAD_BITS": "32768",
        "DMA_A3_EXPECTED_SHARED_KEEP_BITS": "4096",
        "DMA_A3_EXPECTED_PAYLOAD_KEEP_BITS": "102400",
        "DMA_A3_FREQUENCY_MHZ": "550",
        "DMA_A3_TECHNOLOGY": "nangate45",
        "DMA_A3_STDCELL_DB": str(db),
        "DMA_A3_DC_RX_INGRESS_BANK": str(root / "flows/asic/c2b4/rtl/dma_rx_fc_ingress_bank.v"),
        "DMA_A3_DC_PAYLOAD_RAM": str(root / "flows/asic/c2b4/rtl/dma_payload_beat_ram.v"),
        "DMA_A3_DC_FRAME_PAYLOAD_RAM": str(root / "flows/asic/c2b4/rtl/dma_frame_payload_ram.v"),
        "DMA_A3_COMPILE_MODE": "mrtc_default",
        "DMA_A3_EXTERNAL_SDC": str(sdc),
        "DMA_A3_EXTERNAL_SDC_SHA256": sha256(sdc),
        "DMA_A3_CLOCK_NAME": "a1_clk",
        "DMA_A3_EXPECTED_SETUP_UNCERTAINTY_NS": "0.200",
        "DMA_A3_EXPECTED_HOLD_UNCERTAINTY_NS": "0.050",
        "DMA_A3_DC_MAX_CORES": os.environ.get(
            "DMA_DC_MAX_CORES", str(os.cpu_count() or 1)
        ),
    })
    command = split_tool(os.environ.get("DC_SHELL", "dc_shell")) + [
        "-f", str(root / "flows/asic/c2b4/dc/run.tcl")
    ]
    run_command(command, root, environment, dry_run)


def c2_default_mapped_netlist(root):
    return c2_build_root(root) / (
        "dc/nangate45/{}/550mhz/{}.mapped.v".format(PROFILE_ID, TOP)
    )


def run_c2_pnr(root, dry_run):
    mapped = Path(os.environ.get(
        "DMA_C2_MAPPED_NETLIST", str(c2_default_mapped_netlist(root))
    )).resolve()
    if not dry_run:
        mapped = require_file(mapped, "C2 mapped netlist")
        try:
            mapped.relative_to(root)
        except ValueError:
            raise RuntimeError("mapped netlist must be inside the public checkout")
    measured_eco = sha256(mapped) == MEASURED_MAPPED_NETLIST_SHA256 if mapped.is_file() else False
    if not dry_run and not measured_eco and os.environ.get(
            "DMA_C2_ALLOW_UNMEASURED_ROUTE") != "1":
        raise RuntimeError(
            "exact ECO is hash-bound; set DMA_C2_ALLOW_UNMEASURED_ROUTE=1 "
            "to run without the measured ECO"
        )
    environment = os.environ.copy()
    environment.update({
        "DMA_C4_REG_ROOT": str(root),
        "DMA_C4_REG_BUILD_ROOT": str(c2_build_root(root)),
        "DMA_C4_REG_MAPPED_SOURCE_FREQUENCY_MHZ": "550",
        "DMA_C4_REG_MAPPED_SOURCE_CLOCK_PERIOD_NS": "1.818182",
        "DMA_C4_REG_PHYSICAL_FREQUENCY_MHZ": "450",
        "DMA_C4_REG_CLOCK_PERIOD_NS": "2.222222",
        "DMA_C4_REG_MAPPED_NETLIST": str(mapped),
        "DMA_C4_REG_SDC": str(root / "flows/asic/c2b4/constraints/pnr450.sdc"),
        "DMA_C4_REG_ORFS_IMAGE": EXPECTED_ORFS_IMAGE,
        "DMA_C4_REG_ORFS_COMMIT": EXPECTED_ORFS_COMMIT,
        "DMA_C4_REG_DESIGN_NAME": os.environ.get(
            "DMA_C2_DESIGN_NAME", TOP + "_CHANNELS2"
        ),
        "DMA_C4_REG_HANDOFF_BASENAME": TOP,
        "DMA_C4_REG_DESIGN_NICKNAME": "dma_c2b4_register_showcase",
        "DMA_C4_REG_EXPECTED_INPUT_PORTS": "1313",
        "DMA_C4_REG_EXPECTED_OUTPUT_PORTS": "777",
        "DMA_C4_REG_GRT_HOLD_SLACK_MARGIN_NS": "0.000",
        "DMA_C4_REG_HOLD_UNCERTAINTY_NS": "0.000",
        "DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS": "0.000050",
        "DMA_C4_REG_THREADS": str(os.cpu_count() or 1),
    })
    if measured_eco:
        environment["DMA_C2_REG_HOLD_ECO"] = "dc550_pnr450_eco3"
    else:
        environment.pop("DMA_C2_REG_HOLD_ECO", None)
    command = ["bash", str(root / "flows/asic/c2b4/openroad/run.sh")]
    run_command(command, root, environment, dry_run)


def run_c2_sta(root, dry_run):
    build_root = c2_build_root(root)
    handoff = build_root / "openroad/attempts/dc550mhz_pnr450mhz/handoff"
    db_value = os.environ.get("DMA_N45_STDCELL_DB", "<DMA_N45_STDCELL_DB>")
    db = Path(db_value)
    if not dry_run:
        db = require_file(db, "Nangate45 standard-cell DB", EXPECTED_DB_SHA256)
    environment = os.environ.copy()
    environment.update({
        "DMA_C4_REG_PT_OUTPUT": str(build_root / "primetime/dc550mhz_pnr450mhz"),
        "DMA_C4_REG_TOP": TOP,
        "DMA_C4_REG_FREQUENCY_MHZ": "450",
        "DMA_C4_REG_CLOCK_PERIOD_NS": "2.222222",
        "DMA_C4_REG_CLOCK_PERIOD_TOLERANCE_NS": "0.000050",
        "DMA_C4_REG_EXPECTED_PAYLOAD_BITS": "102400",
        "DMA_C4_REG_STDCELL_DB": str(db),
        "DMA_C4_REG_POSTROUTE_NETLIST": str(handoff / (TOP + "_postroute.v")),
        "DMA_C4_REG_POSTROUTE_SDC": str(handoff / (TOP + "_postroute.sdc")),
        "DMA_C4_REG_CONSTRAINT_SDC": str(root / "flows/asic/c2b4/constraints/pt450.sdc"),
        "DMA_C4_REG_POSTROUTE_SPEF": str(handoff / (TOP + "_postroute.spef")),
        "DMA_C4_REG_INPUT_DRIVER_TCL": str(root / "flows/asic/c2b4/primetime/input_driver_model.tcl"),
    })
    if not dry_run:
        for key in ("DMA_C4_REG_POSTROUTE_NETLIST", "DMA_C4_REG_POSTROUTE_SDC", "DMA_C4_REG_POSTROUTE_SPEF"):
            require_file(environment[key], key)
    command = split_tool(os.environ.get("PT_SHELL", "pt_shell")) + [
        "-f", str(root / "flows/asic/c2b4/primetime/run.tcl")
    ]
    run_command(command, root, environment, dry_run)


def audit_c2(root):
    expected = {
        "rtl/rx/dma_axi_write_engine_512.v": "d6585993fdab2446049d0f7efcf90412755106587d59c5441228b789c7f500b2",
        "rtl/rx/dma_axi_write_engine_64_stream.v": "729e8bccf6f97997284ab54b7931c923944749c44e8824060c5ebe0333a0a23a",
        "flows/asic/c2b4/rtl/manifest.json": "81e1cee28ba2efcb8e70d3e06c1b84509f1109def6c7c3dcc9daca5cafa379d4",
        "flows/asic/c2b4/rtl/dma_payload_beat_ram.v": "318587e22594a8e5d296af0e2877caf9500714ad137fbcc56756bc6413f8a59c",
        "flows/asic/c2b4/rtl/dma_frame_payload_ram.v": "395be85922922790dc06b91332a565836b3d93cce95c9c3c4ab00557a637ff09",
        "flows/asic/c2b4/rtl/dma_rx_fc_ingress_bank.v": "af6879df9bb60f83bd78f486e52632d51317cd6ccec8539478809b4647fd66e1",
        "flows/asic/c2b4/constraints/dc550.sdc": "d40bffb6c70ebdb460d70791e7c83fe2f6ee1d8c23923c68012f1d9b8ef3988c",
        "flows/asic/c2b4/openroad/hold_eco_dc550_pnr450.json": "cbd6e1ea4bf8084fd0330619e86538dafe3569aa30cfe2eb6c7d9eb70af49530",
        "flows/asic/c2b4/openroad/pre_detail_route_hold_eco3.tcl": "644cc3dfd27bcf67baec7f7bb4bd0c483fe5c63ea75d8b24a8cbf5a80450cd93",
    }
    for relative, digest in expected.items():
        require_file(root / relative, relative, digest)
    manifest = json.loads((root / "flows/asic/c2b4/rtl/manifest.json").read_text(encoding="utf-8"))
    banking = manifest["payload_ram"]["banking"]
    if (banking["depth"] != 128 or banking["width_banks"] != 4 or
            banking["depth_banks"] != 2 or banking["register_bank_count"] != 8 or
            banking["expected_fixed_payload_bits"] != 65536):
        raise RuntimeError("C2 fixed banking contract mismatch")
    if manifest.get("production_rtl_modified") is not False:
        raise RuntimeError("flow-only override claims a production RTL change")
    print("N45_C2_REGISTER_AUDIT_PASS profile={} payload_keep_bits=102400 arrays=13 macros=0".format(PROFILE_ID))


def run_vivado_async64(root, dry_run):
    environment = os.environ.copy()
    environment.update({
        "DMA_ROOT": str(root),
        "DMA_ACLK_PERIOD_NS": "5.000",
        "DMA_MEM_CLOCK_PERIOD_NS": "5.000",
        "REPORT_TAG": os.environ.get("REPORT_TAG", "async64_2022_2_public"),
    })
    command = split_tool(os.environ.get("VIVADO_2022_2", "vivado")) + [
        "-mode", "batch", "-source",
        str(root / "fpga/xilinx/synth_rx_payload_async64_ooc_2022_2.tcl"),
    ]
    run_command(command, root, environment, dry_run)


def run_a5_audit(root, kind, dry_run):
    script = root / "flows/asic/a5/public/{}.py".format(kind)
    command = [sys.executable, str(script), "--root", str(root)]
    if dry_run:
        command.append("--dry-run")
    run_command(command, root, os.environ.copy(), False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("command", choices=(
        "c2-sim", "c2-dc", "c2-pnr", "c2-sta", "c2-audit",
        "vivado-async64-2022.2-ooc", "a5-model-audit",
        "a5-clock-delivery-audit",
    ))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    if args.command == "c2-sim":
        run_c2_sim(root, args.dry_run)
    elif args.command == "c2-dc":
        run_c2_dc(root, args.dry_run)
    elif args.command == "c2-pnr":
        run_c2_pnr(root, args.dry_run)
    elif args.command == "c2-sta":
        run_c2_sta(root, args.dry_run)
    elif args.command == "c2-audit":
        audit_c2(root)
    elif args.command == "vivado-async64-2022.2-ooc":
        run_vivado_async64(root, args.dry_run)
    elif args.command == "a5-model-audit":
        run_a5_audit(root, "audit_model", args.dry_run)
    else:
        run_a5_audit(root, "audit_clock_delivery", args.dry_run)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print("n45-showcase: error: {}".format(error), file=sys.stderr)
        sys.exit(2)
