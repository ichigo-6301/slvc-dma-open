#!/usr/bin/env python3
"""Bounded contracts for the Make-first SLVC DMA flow interface."""

from __future__ import print_function

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from flows.scripts import flowctl


ROOT = Path(__file__).resolve().parents[2]
FLOWCTL = ROOT / "flows/scripts/flowctl.py"

DEFCONFIGS = (
    "slvc_dma_512_core_only_defconfig",
    "slvc_dma_512_defconfig",
    "slvc_dma_512_rx_wide_defconfig",
    "slvc_dma_512_rx_async64_defconfig",
    "slvc_dma_512_rx_async512_defconfig",
    "dma_rx512_reg_c2_b4_m2_sp64_defconfig",
)

STAGE_CONFIG = {
    "sim": "slvc_dma_512_defconfig",
    "fpga-ooc": "slvc_dma_512_defconfig",
    "adapter-dc-ooc": "slvc_dma_512_defconfig",
    "rx-payload-writer-dc-ooc": "slvc_dma_512_rx_wide_defconfig",
    "n45-c2-reg-sim": "dma_rx512_reg_c2_b4_m2_sp64_defconfig",
    "n45-c2-reg-dc": "dma_rx512_reg_c2_b4_m2_sp64_defconfig",
    "n45-c2-reg-pnr": "dma_rx512_reg_c2_b4_m2_sp64_defconfig",
    "n45-c2-reg-sta": "dma_rx512_reg_c2_b4_m2_sp64_defconfig",
    "vivado-async64-2022.2-ooc": "slvc_dma_512_rx_async64_defconfig",
    "n45-a5-model-audit": "slvc_dma_512_defconfig",
    "n45-a5-clock-delivery-audit": "slvc_dma_512_defconfig",
}


def run_flowctl(arguments, environment=None):
    command = [sys.executable, str(FLOWCTL), "--root", str(ROOT)] + arguments
    completed = subprocess.run(
        command,
        cwd=str(ROOT),
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
    )
    return completed


def normalized_output(output):
    return "\n".join(
        line for line in output.splitlines()
        if "is a compatibility alias" not in line
    )


class ConfigContractTest(unittest.TestCase):
    def test_all_defconfigs_validate(self):
        for name in DEFCONFIGS:
            config = flowctl.parse_config(ROOT / "configs" / name)
            self.assertIs(flowctl.validate_config(config), config, name)

    def test_disabled_kconfig_form_is_parsed(self):
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / ".config"
            config_path.write_text(
                "CONFIG_SLVC_DMA_V1_512=y\n"
                "# CONFIG_SLVC_DMA_RX_MEM_ASYNC64 is not set\n",
                encoding="utf-8",
            )
            parsed = flowctl.parse_config(config_path)
            self.assertEqual(parsed["CONFIG_SLVC_DMA_RX_MEM_ASYNC64"], "n")

    def test_duplicate_config_symbol_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / ".config"
            config_path.write_text(
                "CONFIG_SLVC_DMA_V1_512=y\n"
                "CONFIG_SLVC_DMA_V1_512=n\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "duplicate config symbol"):
                flowctl.parse_config(config_path)

    def test_rx_backends_remain_mutually_exclusive(self):
        config = flowctl.parse_config(
            ROOT / "configs/slvc_dma_512_rx_async64_defconfig"
        )
        config["CONFIG_SLVC_DMA_RX_MEM_ASYNC512"] = "y"
        with self.assertRaisesRegex(RuntimeError, "mutually exclusive"):
            flowctl.validate_config(config)

    def test_c2_stage_requires_c2_profile_and_audit(self):
        config = flowctl.parse_config(ROOT / "configs/slvc_dma_512_defconfig")
        config["CONFIG_SLVC_DMA_N45_C2_REG_SIM"] = "y"
        with self.assertRaisesRegex(RuntimeError, "require profile"):
            flowctl.validate_config(config)

        config = flowctl.parse_config(
            ROOT / "configs/dma_rx512_reg_c2_b4_m2_sp64_defconfig"
        )
        config["CONFIG_SLVC_DMA_N45_C2_REG_AUDIT"] = "n"
        with self.assertRaisesRegex(RuntimeError, "require the C2 audit"):
            flowctl.validate_config(config)


class StageInterfaceTest(unittest.TestCase):
    def test_stage_registry_dependency_order(self):
        self.assertEqual(
            list(flowctl.STAGES),
            [
                "n45-c2-reg-audit",
                "sim",
                "n45-c2-reg-sim",
                "fpga-ooc",
                "vivado-async64-2022.2-ooc",
                "adapter-dc-ooc",
                "rx-payload-writer-dc-ooc",
                "n45-c2-reg-dc",
                "n45-c2-reg-pnr",
                "n45-c2-reg-sta",
                "n45-a5-model-audit",
                "n45-a5-clock-delivery-audit",
            ],
        )

    def test_disabled_stage_fails_closed(self):
        completed = run_flowctl([
            "--config", "configs/slvc_dma_512_defconfig",
            "run", "--stage", "n45-c2-reg-dc", "--dry-run",
        ])
        self.assertEqual(completed.returncode, 2, completed.stdout)
        self.assertIn("is disabled by CONFIG_SLVC_DMA_N45_C2_REG_DC", completed.stdout)

    def test_c2_selected_dry_run_has_required_order(self):
        completed = run_flowctl([
            "--config", "configs/dma_rx512_reg_c2_b4_m2_sp64_defconfig",
            "run-selected", "--dry-run",
        ])
        self.assertEqual(completed.returncode, 0, completed.stdout)
        expected = (
            "selected_stages: n45-c2-reg-audit, n45-c2-reg-sim, "
            "n45-c2-reg-dc, n45-c2-reg-pnr, n45-c2-reg-sta"
        )
        self.assertIn(expected, completed.stdout)
        offsets = [
            completed.stdout.index("stage: " + stage)
            for stage in (
                "n45-c2-reg-audit", "n45-c2-reg-sim", "n45-c2-reg-dc",
                "n45-c2-reg-pnr", "n45-c2-reg-sta",
            )
        ]
        self.assertEqual(offsets, sorted(offsets))

    def test_all_legacy_dry_runs_match_generic_stage_output(self):
        environment = os.environ.copy()
        environment.update({
            "VSIM": "dma_test_vsim",
            "VIVADO": "dma_test_vivado",
            "VIVADO_2022_2": "dma_test_vivado_2022_2",
            "DC_SHELL": "dma_test_dc_shell",
            "PT_SHELL": "dma_test_pt_shell",
        })
        for stage, config_name in STAGE_CONFIG.items():
            generic = run_flowctl([
                "--config", "configs/" + config_name,
                "run", "--stage", stage, "--dry-run",
            ], environment)
            legacy = run_flowctl([
                "--config", "configs/" + config_name,
                stage + "-dry-run",
            ], environment)
            self.assertEqual(generic.returncode, 0, generic.stdout)
            self.assertEqual(legacy.returncode, 0, legacy.stdout)
            self.assertEqual(
                normalized_output(legacy.stdout),
                normalized_output(generic.stdout),
                stage,
            )
            self.assertIn("is a compatibility alias", legacy.stdout)

    def test_show_config_reports_profile_and_enabled_stages(self):
        completed = run_flowctl([
            "--config", "configs/slvc_dma_512_rx_async64_defconfig",
            "show-config",
        ])
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("profile_id: slvc_dma_512_rx_async64", completed.stdout)
        self.assertIn("rx_memory_backend: async64", completed.stdout)
        self.assertIn("vivado-async64-2022.2-ooc", completed.stdout)


if __name__ == "__main__":
    unittest.main()
