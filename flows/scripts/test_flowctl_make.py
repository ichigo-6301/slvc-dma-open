#!/usr/bin/env python3
"""Bounded contracts for the Make-first SLVC DMA flow interface."""

from __future__ import print_function

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from flows.scripts import flowctl


ROOT = Path(__file__).resolve().parents[2]
FLOWCTL = ROOT / "flows/scripts/flowctl.py"
MAKE = shutil.which("make") or shutil.which("gmake")

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


def git_status():
    completed = subprocess.run(
        ["git", "status", "--porcelain"], cwd=str(ROOT),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        universal_newlines=True, check=True,
    )
    return completed.stdout


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
            "VSIM": "dma_test_vsim -64",
            "VIVADO": "dma_test_vivado -nolog",
            "VIVADO_2022_2": "dma_test_vivado_2022_2 -nolog",
            "DC_SHELL": "dma_test_dc_shell -64",
            "PT_SHELL": "dma_test_pt_shell -64",
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
            expected_prefixes = {
                "sim": "dma_test_vsim -64 -c -do",
                "fpga-ooc": "dma_test_vivado -nolog -mode batch",
                "adapter-dc-ooc": "dma_test_dc_shell -64 -f",
                "rx-payload-writer-dc-ooc": "dma_test_dc_shell -64 -f",
                "n45-c2-reg-dc": "dma_test_dc_shell -64 -f",
                "n45-c2-reg-sta": "dma_test_pt_shell -64 -f",
                "vivado-async64-2022.2-ooc": (
                    "dma_test_vivado_2022_2 -nolog -mode batch"
                ),
            }
            if stage in expected_prefixes:
                self.assertIn(expected_prefixes[stage], generic.stdout, stage)

    def test_show_config_reports_profile_and_enabled_stages(self):
        completed = run_flowctl([
            "--config", "configs/slvc_dma_512_rx_async64_defconfig",
            "show-config",
        ])
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("profile_id: slvc_dma_512_rx_async64", completed.stdout)
        self.assertIn("rx_memory_backend: async64", completed.stdout)
        self.assertIn("vivado-async64-2022.2-ooc", completed.stdout)


class ToolCommandContractTest(unittest.TestCase):
    def test_split_tool_accepts_name_and_literal_startup_arguments(self):
        self.assertEqual(
            flowctl.split_tool("dc_shell -64 -no_gui"),
            ["dc_shell", "-64", "-no_gui"],
        )

    def test_split_tool_accepts_quoted_path_with_spaces(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "tool with spaces"
            executable.write_text("bounded test tool\n", encoding="utf-8")
            quoted = '"{}"'.format(executable)
            self.assertEqual(flowctl.split_tool(quoted), [str(executable)])
            self.assertEqual(
                flowctl.split_tool(quoted + " -64"),
                [str(executable), "-64"],
            )

    def test_split_tool_fails_closed_on_empty_or_shell_expression(self):
        with self.assertRaisesRegex(RuntimeError, "empty"):
            flowctl.split_tool("   ")
        with self.assertRaisesRegex(RuntimeError, "invalid tool command"):
            flowctl.split_tool('dc_shell "unterminated')
        for value in (
                "dc_shell | tee run.log",
                "dc_shell > run.log",
                "dc_shell; other_tool",
                "dc_shell && other_tool"):
            with self.assertRaisesRegex(RuntimeError, "shell operators"):
                flowctl.split_tool(value)
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "tool&chain.cmd"
            executable.write_text("@echo off\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "shell operators"):
                flowctl.split_tool(str(executable))
            if os.name == "nt":
                with self.assertRaisesRegex(RuntimeError, "shell operators"):
                    flowctl.wrap_windows_batch([str(executable), "-64"])

    def test_require_tool_checks_only_executable_token(self):
        with mock.patch.object(
                flowctl.shutil, "which", return_value="/tools/dc_shell") as which:
            resolved = flowctl.require_tool(["dc_shell", "-64"])
        self.assertEqual(resolved, "/tools/dc_shell")
        which.assert_called_once_with("dc_shell")
        with mock.patch.object(
                flowctl.shutil, "which",
                return_value="C:/EDA&Tools/dc_shell.exe"):
            with self.assertRaisesRegex(RuntimeError, "shell operators"):
                flowctl.require_tool(["dc_shell", "-64"])

    def test_public_stage_dry_runs_preserve_prefix_argument_order(self):
        config = flowctl.parse_config(ROOT / "configs/slvc_dma_512_rx_wide_defconfig")
        environment = {
            "VSIM": "dma_vsim -64",
            "VIVADO": "dma_vivado -nolog",
            "DC_SHELL": "dma_dc_shell -64",
        }
        output = io.StringIO()
        with mock.patch.dict(os.environ, environment, clear=False):
            with contextlib.redirect_stdout(output):
                flowctl.run_sim(ROOT, config, True)
                flowctl.run_ooc(ROOT, config, True)
                flowctl.run_adapter_dc_ooc(ROOT, True)
                flowctl.run_rx_payload_writer_dc_ooc(ROOT, config, True)
        rendered = output.getvalue()
        self.assertIn("dma_vsim -64 -c -do", rendered)
        self.assertIn("dma_vivado -nolog -mode batch -source", rendered)
        self.assertIn("dma_dc_shell -64 -f run_udp_to_shdr_ooc.tcl", rendered)
        self.assertIn("dma_dc_shell -64 -f run_rx_payload_writer_ooc.tcl", rendered)

    def test_windows_batch_wrapper_keeps_prefix_before_stage_arguments(self):
        command = ["C:/Program Files/EDA/vivado.bat", "-nolog", "-mode", "batch"]
        wrapped = flowctl.wrap_windows_batch(command)
        if os.name == "nt":
            self.assertEqual(wrapped[:2], ["cmd", "/c"])
            self.assertEqual(wrapped[2:], command)
        else:
            self.assertEqual(wrapped, command)


@unittest.skipUnless(
    MAKE and os.name != "nt",
    "GNU Make external-CWD contracts run on Linux",
)
class ExternalMakeInvocationTest(unittest.TestCase):
    def setUp(self):
        self.status_before = git_status()
        self.external_directory = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.external_directory.cleanup()
        self.assertEqual(git_status(), self.status_before)

    def run_make(self, arguments, environment=None):
        command = [MAKE, "-f", str(ROOT / "Makefile")]
        command.extend(arguments)
        completed = subprocess.run(
            command, cwd=self.external_directory.name,
            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        return completed

    def test_external_make_uses_root_relative_config_for_all_read_commands(self):
        completed = self.run_make([
            "PYTHON=" + sys.executable,
            "CONFIG=configs/slvc_dma_512_rx_async64_defconfig",
            "showconfig", "validate-profile", "selected-dry-run",
        ])
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("profile_id: slvc_dma_512_rx_async64", completed.stdout)
        self.assertIn("DMA_FLOW_CONFIG_VALID", completed.stdout)
        self.assertIn("selected_stages:", completed.stdout)

    def test_external_make_accepts_absolute_config_and_defconfig_paths(self):
        source = ROOT / "configs/slvc_dma_512_rx_wide_defconfig"
        destination = Path(self.external_directory.name) / "absolute.config"
        completed = self.run_make([
            "PYTHON=" + sys.executable,
            "CONFIG=" + str(destination),
            "DEFCONFIG=" + str(source),
            "defconfig",
        ])
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertEqual(destination.read_text(encoding="utf-8"),
                         source.read_text(encoding="utf-8"))

        completed = self.run_make([
            "PYTHON=" + sys.executable,
            "CONFIG=" + str(destination),
            "showconfig", "validate-profile",
        ])
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("profile_id: slvc_dma_512_rx_wide", completed.stdout)

    def test_root_relative_local_config_and_command_line_priority(self):
        with tempfile.TemporaryDirectory(dir=str(ROOT)) as directory:
            local_root = Path(directory)
            config = local_root / "selected.config"
            local_config = local_root / "toolchain.mk"
            config.write_text(
                (ROOT / "configs/slvc_dma_512_rx_wide_defconfig").read_text(
                    encoding="utf-8") + "\nVSIM := config_vsim\n",
                encoding="utf-8",
            )
            local_config.write_text("VSIM := local_vsim -64\n", encoding="utf-8")
            config_relative = config.relative_to(ROOT).as_posix()
            local_relative = local_config.relative_to(ROOT).as_posix()

            completed = self.run_make([
                "PYTHON=" + sys.executable,
                "CONFIG=" + config_relative,
                "LOCAL_CONFIG=" + local_relative,
                "sim-dry-run",
            ])
            self.assertEqual(completed.returncode, 0, completed.stdout)
            self.assertIn("local_vsim -64 -c -do", completed.stdout)
            self.assertNotIn("config_vsim -c -do", completed.stdout)

            completed = self.run_make([
                "PYTHON=" + sys.executable,
                "CONFIG=" + str(config),
                "LOCAL_CONFIG=" + str(local_config),
                "VSIM=command_vsim -32",
                "sim-dry-run",
            ])
            self.assertEqual(completed.returncode, 0, completed.stdout)
            self.assertIn("command_vsim -32 -c -do", completed.stdout)
            self.assertNotIn("local_vsim -64 -c -do", completed.stdout)

    def test_menuconfig_receives_canonical_config_and_kconfig_paths(self):
        external = Path(self.external_directory.name)
        config = external / "menu.config"
        config.write_text(
            (ROOT / "configs/slvc_dma_512_defconfig").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        frontend = external / "fake mconf"
        frontend.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$KCONFIG_CONFIG\" \"$1\" > \"$MCONF_LOG\"\n",
            encoding="utf-8",
        )
        frontend.chmod(0o755)
        log = external / "mconf.log"
        environment = os.environ.copy()
        environment["MCONF_LOG"] = str(log)
        completed = self.run_make([
            "PYTHON=" + sys.executable,
            "CONFIG=" + str(config),
            "KCONFIG_MCONF=" + str(frontend),
            "menuconfig",
        ], environment)
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertEqual(
            log.read_text(encoding="utf-8").splitlines(),
            [str(config.resolve()), str((ROOT / "Kconfig").resolve())],
        )

    def test_windows_rooted_unc_and_relative_paths_are_classified_from_root(self):
        evaluation = (
            "print-path-contract: ; @printf '%s\\n' "
            "'CONFIG_PATH=$(CONFIG_PATH)' "
            "'LOCAL_CONFIG_PATH=$(LOCAL_CONFIG_PATH)' "
            "'DEFCONFIG_PATH=$(DEFCONFIG_PATH)'"
        )

        def read_paths(assignments):
            completed = self.run_make(
                ["--eval=" + evaluation] + assignments + ["print-path-contract"]
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)
            values = {}
            for line in completed.stdout.splitlines():
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                if key in ("CONFIG_PATH", "LOCAL_CONFIG_PATH", "DEFCONFIG_PATH"):
                    values[key] = value
            self.assertEqual(len(values), 3, completed.stdout)
            return values

        absolute = read_paths([
            r"CONFIG=\\server\share\profile.config",
            r"LOCAL_CONFIG=\rooted\toolchain.mk",
            r"DEFCONFIG=C:\profiles\default_defconfig",
        ])
        self.assertEqual(absolute["CONFIG_PATH"], "//server/share/profile.config")
        self.assertEqual(absolute["LOCAL_CONFIG_PATH"], "/rooted/toolchain.mk")
        self.assertEqual(
            absolute["DEFCONFIG_PATH"], "C:/profiles/default_defconfig"
        )

        relative = read_paths([
            r"CONFIG=configs\selected.config",
            r"LOCAL_CONFIG=flows\local\toolchain.mk",
            r"DEFCONFIG=configs\selected_defconfig",
        ])
        self.assertEqual(
            relative["CONFIG_PATH"],
            (ROOT / "configs/selected.config").as_posix(),
        )
        self.assertEqual(
            relative["LOCAL_CONFIG_PATH"],
            (ROOT / "flows/local/toolchain.mk").as_posix(),
        )
        self.assertEqual(
            relative["DEFCONFIG_PATH"],
            (ROOT / "configs/selected_defconfig").as_posix(),
        )


if __name__ == "__main__":
    unittest.main()
