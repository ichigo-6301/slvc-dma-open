#!/usr/bin/env python3
"""Public flow-contract and profile tests for the current showcase."""

import hashlib
import os
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def text(relative):
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")


CONTRACT_CHECKS = (
    ("profile_id", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "profile_id: dma_rx512_reg_c2_b4_m2_sp64"),
    ("profile_channels", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "channels: 2"),
    ("profile_words", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "fixed_payload_words_64b_per_channel: 512"),
    ("profile_meta", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "fixed_meta_depth: 2"),
    ("profile_shared", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "shared_block_num: 64"),
    ("profile_fixed_bits", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "expected_fixed_payload_bits: 65536"),
    ("profile_width_banks", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "width_banks: 4"),
    ("profile_depth_banks", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "depth_banks: 2"),
    ("profile_arrays", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "register_array_count: 8"),
    ("profile_shared_payload", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "shared_payload_bits: 32768"),
    ("profile_shared_keep", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "shared_keep_bits: 4096"),
    ("profile_total", "flows/profiles/dma_rx512_reg_c2_b4_m2_sp64/profile.yaml", "payload_keep_bits: 102400"),
    ("manifest_schema", "flows/asic/c2b4/rtl/manifest.json", "dma_a3_dc_source_override_v3"),
    ("manifest_profile", "flows/asic/c2b4/rtl/manifest.json", "dma_rx512_reg_c2_b4_m2_sp64"),
    ("manifest_depth", "flows/asic/c2b4/rtl/manifest.json", "\"depth\": 128"),
    ("manifest_depth_banks", "flows/asic/c2b4/rtl/manifest.json", "\"depth_banks\": 2"),
    ("manifest_width_banks", "flows/asic/c2b4/rtl/manifest.json", "\"width_banks\": 4"),
    ("manifest_array_count", "flows/asic/c2b4/rtl/manifest.json", "\"register_bank_count\": 8"),
    ("manifest_fixed_bits", "flows/asic/c2b4/rtl/manifest.json", "\"expected_fixed_payload_bits\": 65536"),
    ("manifest_rtl_clean", "flows/asic/c2b4/rtl/manifest.json", "\"production_rtl_modified\": false"),
    ("dc_filelist", "flows/asic/c2b4/dc/run.tcl", "flows asic c2b4 c2b4_register.f"),
    ("dc_profile_gate", "flows/asic/c2b4/dc/run.tcl", "C2B4 threshold profile banking contract mismatch"),
    ("dc_normal_compile", "flows/asic/c2b4/dc/run.tcl", "compile_ultra\n"),
    ("dc_zero_sram", "flows/asic/c2b4/dc/run.tcl", "register-only profile linked an SRAM reference"),
    ("dc_fixed_preserve", "flows/asic/c2b4/dc/run.tcl", "EXPECTED_FIXED_PAYLOAD_BITS"),
    ("dc_handoff_v", "flows/asic/c2b4/dc/run.tcl", "${TOP}.mapped.v"),
    ("dc_handoff_sdc", "flows/asic/c2b4/dc/run.tcl", "${TOP}.mapped.sdc"),
    ("dc_handoff_ddc", "flows/asic/c2b4/dc/run.tcl", "${TOP}.ddc"),
    ("dc_period", "flows/asic/c2b4/constraints/dc550.sdc", "-period 1.818182"),
    ("dc_setup_uncertainty", "flows/asic/c2b4/constraints/dc550.sdc", "-setup 0.200"),
    ("dc_hold_uncertainty", "flows/asic/c2b4/constraints/dc550.sdc", "-hold 0.050"),
    ("pnr_period", "flows/asic/c2b4/constraints/pnr450.sdc", "-period 2.222222"),
    ("pnr_setup_uncertainty", "flows/asic/c2b4/constraints/pnr450.sdc", "-setup 0.200"),
    ("pnr_hold_uncertainty", "flows/asic/c2b4/constraints/pnr450.sdc", "-hold 0.000"),
    ("constraints_fanout", "flows/asic/c2b4/constraints/pnr450.sdc", "set_max_fanout 16"),
    ("constraints_transition", "flows/asic/c2b4/constraints/pnr450.sdc", "set_max_transition 0.500"),
    ("orfs_mapped_handoff", "flows/asic/c2b4/openroad/config.mk", "SYNTH_NETLIST_FILES"),
    ("orfs_no_rtl", "flows/asic/c2b4/openroad/config.mk", "export VERILOG_FILES ="),
    ("orfs_density", "flows/asic/c2b4/openroad/config.mk", "PLACE_DENSITY = 0.45"),
    ("orfs_hold_split", "flows/asic/c2b4/openroad/pre_global_route_audit.tcl", "Unexpected global-route hold margin"),
    ("orfs_same_run_odb", "flows/asic/c2b4/openroad/run.sh", "6_final.odb"),
    ("orfs_same_run_spef", "flows/asic/c2b4/openroad/run.sh", "6_final.spef"),
    ("eco_manifest_hash_binding", "flows/asic/c2b4/openroad/hold_eco_dc550_pnr450.json", "baseline_postroute_netlist_sha256"),
    ("eco_exact_endpoint", "flows/asic/c2b4/openroad/pre_detail_route_hold_eco3.tcl", "u_fixed_ingress/payload_ram_wr_data_q_reg[278]/D"),
    ("pt_period_assertion", "flows/asic/c2b4/primetime/run.tcl", "clock-period mismatch"),
    ("pt_parasitics", "flows/asic/c2b4/primetime/run.tcl", "read_parasitics"),
    ("pt_payload_gate", "flows/asic/c2b4/primetime/run.tcl", "DMA_C4_REG_EXPECTED_PAYLOAD_BITS"),
    ("pt_fail_closed", "flows/asic/c2b4/primetime/run.tcl", "PrimeTime gate failed"),
)


class C2FlowContractTest(unittest.TestCase):
    pass


def make_contract_test(relative, token):
    def test_case(self):
        self.assertIn(token, text(relative))
    return test_case


for check_id, relative, token in CONTRACT_CHECKS:
    setattr(
        C2FlowContractTest,
        "test_contract_" + check_id,
        make_contract_test(relative, token),
    )


class ShowcaseIdentityTest(unittest.TestCase):
    def test_exact_contract_count(self):
        self.assertEqual(len(CONTRACT_CHECKS), 48)

    def test_writer_hashes(self):
        expected = {
            "rtl/rx/dma_axi_write_engine_512.v": "d6585993fdab2446049d0f7efcf90412755106587d59c5441228b789c7f500b2",
            "rtl/rx/dma_axi_write_engine_64_stream.v": "729e8bccf6f97997284ab54b7931c923944749c44e8824060c5ebe0333a0a23a",
        }
        for relative, digest in expected.items():
            self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), digest)

    def test_all_showcase_dry_runs(self):
        commands = (
            "n45-c2-reg-sim-dry-run", "n45-c2-reg-dc-dry-run",
            "n45-c2-reg-pnr-dry-run", "n45-c2-reg-sta-dry-run",
            "vivado-async64-2022.2-ooc-dry-run",
            "n45-a5-model-audit-dry-run",
            "n45-a5-clock-delivery-audit-dry-run",
        )
        for command in commands:
            completed = subprocess.run(
                [sys.executable, str(ROOT / "flows/scripts/flowctl.py"),
                 "--root", str(ROOT), command],
                cwd=str(ROOT), stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, universal_newlines=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)


if __name__ == "__main__":
    unittest.main()
