#!/usr/bin/env python3
"""Validate and regenerate the sanitized ASIC paired-DC evidence bundle."""

from __future__ import print_function

import argparse
import csv
import hashlib
import io
import json
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path


EVIDENCE_REL = Path("evidence/asic_paired_dc")
MANIFEST_REL = EVIDENCE_REL / "manifest.yaml"
COMPARISONS_REL = EVIDENCE_REL / "comparisons.csv"
PUBLICATION_REL = Path("provenance/asic_paired_dc_publication.yaml")
CHECKSUM_REL = Path("provenance/checksums.sha256")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")
EXPECTED_LIBRARY_SHA256 = (
    "111c429e7ae9341d51f5f04b0e4c7574e5c1359de32d51b151470463abe187de"
)
EXPECTED_ARTIFACTS_SHA256 = (
    "8223251b7e2c43350f580d9312741f662c99a40bc900cc3d0b73c59655c13114"
)
EXPECTED_EVIDENCE_README_SHA256 = (
    "d89bec8697844f0c41a648a07a3d994305dfb688121ef24f8debb0877de5733f"
)
EXPECTED_VERIFICATION_SHA256 = (
    "061c9b70cd7a9862b599da1faa0cb8714d638e716e3441bacca277b7d9047d23"
)
EXPECTED_LINT_SHA256 = (
    "de5ea09b58807945c4bc5f6eb2f64f33619a71d8f136faa2f1b95bdd9289ea20"
)
EXPECTED_POINTS_SHA256 = (
    "d3e72231dc38b6ab0e0362fe44f16232b9f6bbc7cbd6a9e9a9b2ba3c668cb861"
)
EXPECTED_NONCLAIMS_SHA256 = (
    "98b910f4bd9b1e2020e44400c61c21445d3f5d413841fa95e21fa0042223dc1c"
)
EXPECTED_CLAIMS_SHA256 = (
    "b066370c84de86c0647705df19d919735bb6a7c7f10c6392a33be6a1de3f9a76"
)
EXPECTED_EVIDENCE_REGISTRY_NORMALIZED_SHA256 = (
    "a0f9ac81b1223f00dc29ab97357f7c2c8d2bed9c3a8214a73a0862ffaa4b6b70"
)
EXPECTED_PROVENANCE_README_SHA256 = (
    "12fe0583121fda0e2f5c53b0352c2ea8c40b1473924b1668d0158ce375db63cd"
)
AUTHORIZED_THROUGHPUT_CLAIM_ID = (
    "slvc_dma_async64_end_to_end_rtl_sim_throughput"
)
AUTHORIZED_THROUGHPUT_EVIDENCE_ID = (
    "slvc_dma_async64_end_to_end_sim_summary"
)
AUTHORIZED_THROUGHPUT_NONCLAIM_ID = (
    "slvc_dma_async64_end_to_end_not_hardware"
)
AUTHORIZED_RESULTS_START = (
    "<!-- throughput-publication:"
    "slvc_dma_async64_end_to_end_rtl_sim_throughput:start -->"
)
AUTHORIZED_RESULTS_END = (
    "<!-- throughput-publication:"
    "slvc_dma_async64_end_to_end_rtl_sim_throughput:end -->"
)

CSV_HEADERS = {
    "points.csv": (
        "evaluation_id", "point_id", "role", "source_commit", "top",
        "parameters", "tool", "tool_version", "compile_mode", "library",
        "corner", "library_sha256", "constraint_id", "clock_period_ns",
        "setup_uncertainty_ns", "hold_uncertainty_ns", "io_delay_ns",
        "input_transition_ns", "output_load", "max_fanout",
        "max_transition_ns", "total_cell_area", "combinational_area",
        "sequential_area", "noncombinational_area", "leaf_cell_count",
        "register_count", "writer_area", "writer_leaf_count",
        "writer_register_count", "setup_wns_ns", "setup_tns_ns",
        "hold_wns_ns", "hold_tns_ns", "writer_setup_wns_ns",
        "writer_hold_wns_ns", "reservation_object_count",
        "setup_violation_count", "hold_violation_count",
        "electrical_violation_count", "unresolved_reference_count",
        "unexpected_blackbox_count", "latch_count",
        "unclocked_sync_endpoint_count",
    ),
    "sources.csv": (
        "evaluation_id", "scope", "point_id", "source_commit", "path",
        "blob", "sha256", "size_bytes",
    ),
    "verification.csv": (
        "evaluation_id", "point_id", "platform", "tool_version",
        "suite_id", "status", "required_markers", "marker_count",
        "semantic_trace_sha256", "log_sha256", "log_size_bytes",
    ),
    "lint.csv": (
        "evaluation_id", "point_id", "scope", "status", "tool_version",
        "fatal_count", "error_count", "warning_count", "waived_count",
        "report_sha256",
    ),
    "artifacts.csv": (
        "evaluation_id", "point_id", "artifact_class", "logical_name",
        "sha256", "published_payload",
    ),
}

COMPARISON_HEADER = (
    "evaluation_id", "claim_id", "baseline_point_id", "candidate_point_id",
    "metric", "baseline", "candidate", "delta", "delta_percent",
)

EXPECTED_EVALUATIONS = {
    "writer_component": {
        "claim_id": "slvc_dma_writer_reservation_component_paired_dc",
        "private_evidence_commit": "adbc36aa92c6fee11253fbae31ec77216dae91cc",
        "claim_scope": "Nangate45 component-level Design Compiler OOC",
        "nonclaims": (
            "C2B4 or complete-DMA area reduction",
            "place-and-route or extracted timing",
            "maximum frequency, power, or signoff",
        ),
        "top": "dma_axi_write_engine_512",
        "parameters": "MAX_BURST_BEATS=16;MAX_OUTSTANDING=4",
        "constraint_id": "writer_ooc_p1p5_su0p2_hu0p05_io0p5_tr0p1_load0p05_fo16_mt0p5_v1",
        "constraint_values": {
            "clock_period_ns": "1.5", "setup_uncertainty_ns": "0.2",
            "hold_uncertainty_ns": "0.05", "io_delay_ns": "0.5",
            "input_transition_ns": "0.1", "output_load": "0.05",
            "max_fanout": "16", "max_transition_ns": "0.5",
        },
        "claim_record": {
            "profile": "dma_axi_write_engine_512_component_eval",
            "statement": "\"At the same 1.500 ns Nangate45 DC OOC constraint, the reservation candidate reduced Writer total cell area by 7.966353 percent and combinational area by 15.838902 percent; both points remained setup-closed.\"",
            "metric": "component_paired_dc_total_cell_area",
            "value": "-7.966353",
            "unit": "percent candidate-minus-baseline",
            "benchmark": "dma_axi_write_engine_512 W0 versus W1",
            "configuration": "\"MAX_OUTSTANDING=4; MAX_BURST_BEATS=16; register-expanded component; identical tool, library, and constraints\"",
            "tool": "Design Compiler O-2018.06-SP1",
            "caveat": "\"Component-level DC OOC only; this does not establish C2B4 or complete-DMA area reduction, Fmax, P&R, power, or signoff.\"",
        },
        "claim_values": {
            "total_cell_area": {"delta_percent": "-7.966353"},
            "combinational_area": {"delta_percent": "-15.838902"},
        },
        "metrics": (
            "total_cell_area", "combinational_area", "leaf_cell_count",
            "register_count", "setup_wns_ns", "reservation_object_count",
        ),
        "artifacts": (
            "area", "qor", "setup_top20", "hold_top20", "check_design",
            "check_timing", "constraint_identity", "reservation_matches",
        ),
        "roles": {
            "writer_component_w0": "baseline",
            "writer_component_w1": "candidate",
        },
    },
    "c2b4_writer": {
        "claim_id": "slvc_dma_c2b4_writer_subsystem_paired_dc",
        "private_evidence_commit": "a630b1462efcc57d4e2748804ed652517da22a4b",
        "flow_as_run_commit": "9a7e465d7a92f0502287eb162a80468a717fc9fb",
        "claim_scope": "Nangate45 C2B4 register-expanded RX512 subsystem Design Compiler",
        "canary_classification": "NUMERIC_ANCHOR_MATCH_ONLY",
        "nonclaims": (
            "writer optimization enabled the first 550 MHz subsystem closure",
            "writer optimization reduced C2B4 writer hierarchy area",
            "complete DMA, Fmax, P&R, extracted STA, power, SRAM, or signoff",
        ),
        "top": "dma_rx512_memory_subsystem_top",
        "parameters": "CHANNELS=2;FIXED_META_AW=1;FIXED_META_DEPTH=2;FIXED_PAYLOAD_AW=9;FIXED_PAYLOAD_WORDS=512;MAX_BURST_BEATS=16;MAX_OUTSTANDING=4;SHARED_BLOCK_AW=6;SHARED_BLOCK_NUM=64",
        "constraint_id": "c2b4_writer_subsystem_p1p818182_su0p2_hu0p05_io0p5_tr0p1_load0p05_fo16_mt0p5_v1",
        "constraint_values": {
            "clock_period_ns": "1.818182", "setup_uncertainty_ns": "0.2",
            "hold_uncertainty_ns": "0.05", "io_delay_ns": "0.5",
            "input_transition_ns": "0.1", "output_load": "0.05",
            "max_fanout": "16", "max_transition_ns": "0.5",
        },
        "claim_record": {
            "profile": "dma_rx512_reg_c2_b4_m2_sp64",
            "statement": "\"At the same 1.818182 ns C2B4 DC constraint, W0 and W1 both closed setup; W1 increased Writer hierarchy area by 54.393209 percent and reduced setup margin, so subsystem promotion was not supported.\"",
            "metric": "subsystem_paired_dc_promotion",
            "value": "not_promoted",
            "unit": "result",
            "benchmark": "C2B4 register-expanded RX512 subsystem W0 versus W1",
            "configuration": "\"2 channels; 4 KiB fixed payload per channel; 64 shared blocks; identical tool, library, and constraints\"",
            "tool": "Design Compiler O-2018.06-SP1",
            "caveat": "\"W2 is a numeric anchor match only, not a methodology-identical reproduction; no complete-DMA, Fmax, P&R, power, or signoff conclusion is made.\"",
        },
        "claim_values": {
            "writer_area": {"delta_percent": "54.393209"},
            "setup_wns_ns": {
                "baseline": "0.0014981", "candidate": "0.00095892",
            },
            "writer_setup_wns_ns": {
                "baseline": "0.0392413", "candidate": "0.0172149",
                "delta": "-0.0220264",
            },
        },
        "metrics": (
            "total_cell_area", "combinational_area", "writer_area",
            "setup_wns_ns", "writer_setup_wns_ns",
            "reservation_object_count",
        ),
        "artifacts": (
            "area", "hierarchy_area", "qor", "setup_top20",
            "writer_setup_top20", "reservation_matches", "mapped_netlist",
            "ddc", "mapped_sdc",
        ),
        "roles": {
            "c2b4_writer_w0": "baseline",
            "c2b4_writer_w1": "candidate",
            "c2b4_writer_w2": "canary",
        },
    },
    "shared_pool_scheduler": {
        "claim_id": "slvc_dma_shared_pool_scheduler_paired_dc",
        "private_evidence_commit": "ac046053a5d959f265568e2ad6f1acf45b349be4",
        "claim_scope": "Nangate45 register-expanded Shared Pool component Design Compiler OOC",
        "nonclaims": (
            "complete DMA or SRAM-macro PPA",
            "maximum frequency, P&R, extracted timing, power, or signoff",
        ),
        "top": "dma_frame_shared_pool",
        "parameters": "BLOCK_AW=6;BLOCK_NUM=64;CH_ID_W=4;CH_NUM=16;DATA_W=512;DEBUG_OWNERSHIP=0;KEEP_W=64;MAX_FRAME_BLOCKS=32;META_AW=2;META_DEPTH=4",
        "constraint_id": "spdc_scheduler_n45_2p5ns_su0p2_hu0p05_io0p5_tr0p1_load0p05_fo16_mt0p5_v1",
        "constraint_values": {
            "clock_period_ns": "2.5", "setup_uncertainty_ns": "0.2",
            "hold_uncertainty_ns": "0.05", "io_delay_ns": "0.5",
            "input_transition_ns": "0.1", "output_load": "0.05",
            "max_fanout": "16", "max_transition_ns": "0.5",
        },
        "claim_record": {
            "profile": "dma_frame_shared_pool_register_expanded_eval",
            "statement": "\"At the same 2.500 ns Nangate45 DC OOC constraint, P7 improved setup WNS by 7.71332 ps while adding 52 registers and 0.019194 percent total cell area relative to P6.\"",
            "metric": "component_paired_dc_setup_wns",
            "value": "7.71332",
            "unit": "ps candidate-minus-baseline",
            "benchmark": "dma_frame_shared_pool P6 versus P7",
            "configuration": "\"16 channels; 64 by 512-bit blocks; metadata depth 4; DEBUG_OWNERSHIP=0; register-expanded storage\"",
            "tool": "Design Compiler O-2018.06-SP1",
            "caveat": "\"Component-level register-expanded DC OOC only; this is not SRAM-macro PPA, complete-DMA timing, Fmax, P&R, power, or signoff.\"",
        },
        "claim_values": {
            "setup_wns_ns": {"delta": "0.00771332"},
            "register_count": {"delta": "52"},
            "total_cell_area": {"delta_percent": "0.019194"},
        },
        "metrics": (
            "total_cell_area", "combinational_area", "sequential_area",
            "leaf_cell_count", "register_count", "setup_wns_ns",
        ),
        "artifacts": (
            "area", "qor", "setup_top20", "hold_top20", "check_design",
            "check_timing", "constraints",
        ),
        "roles": {
            "shared_pool_p6": "baseline",
            "shared_pool_p7": "candidate",
        },
    },
}

EXPECTED_SOURCE_INVENTORY = frozenset({
    ("writer_component", "point", "writer_component_w0", "5c6829acd74ce525c5b986d609a2f94f8b75a11e", "rtl/rx/dma_axi_write_engine_512.v", "7a34840ceb0468a461d99a2544a6b6e3208d70cf", "bd4e0081cbc667a1947fb6ed68057fec46a24660d991dd72a6576d92b0cae32e", "13256"),
    ("writer_component", "point", "writer_component_w1", "529256758b33ba9628bc0bf93501297dd3e25487", "rtl/rx/dma_axi_write_engine_512.v", "9a21d55a0d22f1390bb356ae09adeb72557e44ac", "6ea3f0445916cd2304cb29fb6c513dbc70a0da60da134b5ff815f4a46310ad0b", "14002"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "filelists/dma_a3_target_b_register.f", "87c12dbdd49bad3c1c100a74bf569e87ca4454a3", "ff43e4f6fe198077ab766e01d6ad0dd6428ff2ce32cc29b7c7248f6724da7a79", "337"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/include/dma_defs.vh", "27aa63eaee05ef1737e767ee919281f20fb04ad2", "b4f1d77e577c9452c25ba4cd8013d48cd9b6c49be3f880be7a90f1f6c65cb0e2", "13786"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/common/dma_payload_beat_ram.v", "b8a131aaab18c966682683f6b426a8d8e1c0b510", "6029c43d87784c9f761949e1453449553127f364ffec13bd24a8584e6bcb4a38", "847"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/rx/dma_rx_fc_ingress_bank.v", "a9508ef31aae4ea7e8edf03eeb674cc5c66576c3", "132e72cf4fc48c0c809cc0380105d7b05b20b2426a387ea18633306b6b149f4a", "28261"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/rx/dma_frame_payload_ram.v", "875650a44e5f38e38b53fe5147dc2f0c4e88565a", "4f76689f7f8226084c7760d7888392e84c6efbdf37ff4d7871ff2db573f6b7c3", "1253"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/rx/dma_frame_shared_pool.v", "ec07e9627563c6abb2e316213f6108a6dc1822b2", "4cb4b2b174f740ea38c83e1a127ec2568b8503dc024bbc4e9459af75e6751720", "29562"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/rx/dma_rx_frame_shared_adapter.v", "e4c364d3ae260d794e0247bce96bb4ce100c4391", "46a2f72441ef2c38b620b64ad41e37b01250fd0e296078efc93b900d565133d8", "28101"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/rx/dma_rx_ingress_source_selector.v", "4eaa31a5e75c17ee57aa00fefaf5f6ec2fc569bd", "3cb25be9a0a58d0fd5c8ecb494898e3e927168e7acba9064a01ef79275269b18", "6853"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "flows/asic/a1/rtl/dma_rx512_writer_route_top.v", "9eab526285b538ca3886ace2d7146f09eec4e8a5", "f2c8f4780774e2296d0a1dc42a7bf968b2ac58a5508baa47e3d68b408d074ace", "2548"),
    ("c2b4_writer", "common", "*", "348df4949d4d88954a4402cd47118c6444099a17", "flows/asic/a1/rtl/dma_rx512_memory_subsystem_top.v", "2ac1eea9c7fd8339ad03025920af11721d355a67", "12b8147dc37614e0622f8bfe9f3c00e981b6f8d76e48efbc80c64647833700ad", "18110"),
    ("c2b4_writer", "point", "c2b4_writer_w2", "348df4949d4d88954a4402cd47118c6444099a17", "rtl/rx/dma_axi_write_engine_512.v", "0d53caa0b73df2302865b0222cd8aed5abf5193f", "d6585993fdab2446049d0f7efcf90412755106587d59c5441228b789c7f500b2", "14322"),
    ("c2b4_writer", "point", "c2b4_writer_w0", "5c6829acd74ce525c5b986d609a2f94f8b75a11e", "rtl/rx/dma_axi_write_engine_512.v", "7a34840ceb0468a461d99a2544a6b6e3208d70cf", "bd4e0081cbc667a1947fb6ed68057fec46a24660d991dd72a6576d92b0cae32e", "13256"),
    ("c2b4_writer", "point", "c2b4_writer_w1", "529256758b33ba9628bc0bf93501297dd3e25487", "rtl/rx/dma_axi_write_engine_512.v", "9a21d55a0d22f1390bb356ae09adeb72557e44ac", "6ea3f0445916cd2304cb29fb6c513dbc70a0da60da134b5ff815f4a46310ad0b", "14002"),
    ("shared_pool_scheduler", "point", "shared_pool_p6", "bbc5da96acda883257b6da67577f8360a6f7f555", "rtl/dma_frame_shared_pool.v", "39d3cf8b52682eec5243b51246bf3d79baf6ca23", "22c82fab06b67afbf66e6de5c6860ddef78f538cc3b84c053af1a584fa2d2a38", "16006"),
    ("shared_pool_scheduler", "point", "shared_pool_p6", "bbc5da96acda883257b6da67577f8360a6f7f555", "rtl/dma_frame_payload_ram.v", "4ffd61f4d2445aa540bb19a5bf75f8d608767753", "d71bf42e794b8eb8844ffcd863a57fd2f6a411c18c974f4b856940c8b0b7db78", "982"),
    ("shared_pool_scheduler", "point", "shared_pool_p7", "02b4f9f0ff47fd103d252f5207a25f46f59699d0", "rtl/dma_frame_shared_pool.v", "35fa118d65f8259f43535ac541da1b087f0c9704", "1e3f107fbec34d812ca5caf4dd8e8c110a026be5fa339cdc348ae8886cf90ee8", "18942"),
    ("shared_pool_scheduler", "point", "shared_pool_p7", "02b4f9f0ff47fd103d252f5207a25f46f59699d0", "rtl/dma_frame_payload_ram.v", "4ffd61f4d2445aa540bb19a5bf75f8d608767753", "d71bf42e794b8eb8844ffcd863a57fd2f6a411c18c974f4b856940c8b0b7db78", "982"),
})

EXPECTED_MARKERS = {
    "writer_2028": (
        "PASS tb_rtl_rx_payload_writer_512 cases=2028",
        "WIDE512_THROUGHPUT bytes_per_cycle_x1000=64000",
    ),
    "writer_integration": (
        "PASS tb_rtl_rx_payload_writer_512_integration directed_lengths=18 mixed_frames=256",
    ),
    "a3_profile": (
        "PASS tb_dma_a3_ingress_profile channels=2 payload_words=512 meta_depth=2",
        "PASS tb_dma_rx512_memory_subsystem channels=2 payload_words=512 meta_depth=2",
    ),
    "shared_pool": (
        "E19_CASE T0 reset_init",
        "E19_CASE T1 single_frame",
        "E19_CASE T2 back_to_back",
        "E19_CASE T3 multi_channel",
        "E19_CASE T4 pool_full_nodrop",
        "E19_CASE T5 pool_full_drop",
        "E19_CASE T6 oversized_drop",
        "E19_CASE T7 drain_stall",
        "E19_CASE T8 reset_recovery",
        "OK: dma RTL v33e19 shared frame pool test passed.",
    ),
}

EXPECTED_SIMULATORS = {
    "windows": "ModelSim SE-64 2020.4",
    "linux": "Questa Sim-64 10.7c",
}

EXPECTED_RESULT_ROWS = {
    "docs/en/results.md": (
        "| Writer reservation, component OOC | 1.500 ns | W0 -> W1 | total cell area `7526.204 -> 6926.640` (`-7.966353%`); combinational area `-15.838902%`; both setup-closed |",
        "| C2B4 register-expanded RX512 subsystem | 1.818182 ns | W0 -> W1 | both setup-closed; Writer hierarchy area `4637.976 -> 7160.720` (`+54.393209%`); setup WNS `+0.001498 -> +0.000959 ns` |",
        "| Register-expanded Shared Pool component OOC | 2.500 ns | P6 -> P7 | setup WNS `+0.001163 -> +0.008876 ns` (`+7.71332 ps`); registers `+52`; total area `+0.019194%` |",
    ),
    "docs/zh-CN/results.md": (
        "| Writer reservation，组件级 OOC | 1.500 ns | W0 -> W1 | 标准单元总面积 `7526.204 -> 6926.640`（`-7.966353%`）；组合面积 `-15.838902%`；两点均 setup 闭合 |",
        "| C2B4 寄存器展开 RX512 子系统 | 1.818182 ns | W0 -> W1 | 两点均 setup 闭合；Writer 层级面积 `4637.976 -> 7160.720`（`+54.393209%`）；setup WNS `+0.001498 -> +0.000959 ns` |",
        "| 寄存器展开 Shared Pool 组件级 OOC | 2.500 ns | P6 -> P7 | setup WNS `+0.001163 -> +0.008876 ns`（改善 `7.71332 ps`）；寄存器 `+52`；总面积 `+0.019194%` |",
    ),
}

EXPECTED_DOC_SHA256 = {
    "docs/en/results.md": (
        "e3bb0780925d02900cce02dee7cf196b8f28a997e9d5f0b7980c75b3d115688d"
    ),
    "docs/zh-CN/results.md": (
        "285d9f936c17e4a6cc39c5255c2e79330f6264eb0d93869578452dbc7f73b7fc"
    ),
    "docs/en/verification.md": (
        "5d5d4cfd3f4c1fa2285f182e1c6db9d12a4a44930e4799c002fbda6000feb068"
    ),
    "docs/zh-CN/verification.md": (
        "a689c556dd38901463ec001898998805893734938034a96bcdcae2979d5660bb"
    ),
    "docs/en/limitations.md": (
        "e4fa2563fefbc93a29cc2c8a2b938db96bda77860f5d5aafa9ef621a74dd6ccb"
    ),
    "docs/zh-CN/limitations.md": (
        "fa6e463b501b874f8d7e5cff2a44117514764bb9836283e141d273260d034934"
    ),
}

EXPECTED_EVIDENCE_RECORD = {
    "type": "sanitized_fixed_commit_paired_design_compiler_bundle",
    "source_ref": "738d890dbba85a1e430caae9b6eb6b8b269b9566",
    "tool": "Design Compiler O-2018.06-SP1 / ModelSim SE-64 2020.4 / Questa Sim-64 10.7c / SpyGlass L-2016.06",
    "public": "true",
}

EXPECTED_NONCLAIMS = {
    "slvc_dma_writer_component_scope_promotion": {
        "profile": "dma_axi_write_engine_512_component_eval",
        "statement": "\"The Writer component area reduction is not a C2B4 subsystem or complete-DMA area claim.\"",
        "reason": "\"The paired result synthesizes dma_axi_write_engine_512 alone; scope promotion is prohibited by the publication contract.\"",
        "status": "not_claimed",
        "public": "true",
    },
    "slvc_dma_c2b4_writer_enabled_closure": {
        "profile": "dma_rx512_reg_c2_b4_m2_sp64",
        "statement": "\"The reservation change is not claimed to have enabled the first 550 MHz C2B4 closure or reduced Writer hierarchy area.\"",
        "reason": "\"W0 already closes the fixed point, while W1 has higher Writer hierarchy area and lower setup margin.\"",
        "status": "not_claimed",
        "public": "true",
    },
    "slvc_dma_paired_dc_implementation_signoff": {
        "profile": "slvc_dma_asic_paired_dc_publication",
        "statement": "\"The paired-DC data is not complete-DMA, Fmax, P&R, extracted STA, power, SRAM-macro, MMMC/OCV, foundry, silicon, or signoff evidence.\"",
        "reason": "\"The publication contains bounded component/subsystem synthesis summaries and hashes only.\"",
        "status": "not_claimed",
        "public": "true",
    },
    "slvc_dma_c2b4_full_lint_clean": {
        "profile": "dma_rx512_reg_c2_b4_m2_sp64",
        "statement": "\"A lint-clean complete C2B4 design is not claimed by the bounded Writer SpyGlass result.\"",
        "reason": "\"The full common scope remains BLOCKED_COMMON_SCOPE with 0 fatal, 15 errors, 202 warnings, and 0 waivers.\"",
        "status": "not_claimed",
        "public": "true",
    },
}

EXPECTED_PUBLICATION_FILES = frozenset({
    "evidence/asic_paired_dc/README.md",
    "evidence/asic_paired_dc/artifacts.csv",
    "evidence/asic_paired_dc/comparisons.csv",
    "evidence/asic_paired_dc/lint.csv",
    "evidence/asic_paired_dc/manifest.yaml",
    "evidence/asic_paired_dc/points.csv",
    "evidence/asic_paired_dc/sources.csv",
    "evidence/asic_paired_dc/verification.csv",
})

PAIR_IDENTITY_FIELDS = (
    "top", "parameters", "tool", "tool_version", "compile_mode", "library",
    "corner", "library_sha256", "constraint_id", "clock_period_ns",
    "setup_uncertainty_ns", "hold_uncertainty_ns", "io_delay_ns",
    "input_transition_ns", "output_load", "max_fanout", "max_transition_ns",
)

NUMERIC_FIELDS = set(CSV_HEADERS["points.csv"][13:])
NONNEGATIVE_PHYSICAL_FIELDS = {
    "total_cell_area", "combinational_area", "sequential_area",
    "noncombinational_area", "writer_area", "leaf_cell_count",
    "register_count", "writer_leaf_count", "writer_register_count",
    "reservation_object_count", "setup_violation_count",
    "hold_violation_count", "electrical_violation_count",
    "unresolved_reference_count", "unexpected_blackbox_count",
    "latch_count", "unclocked_sync_endpoint_count",
}
DISCRETE_COUNT_FIELDS = {
    "leaf_cell_count", "register_count", "writer_leaf_count",
    "writer_register_count", "reservation_object_count",
    "setup_violation_count", "hold_violation_count",
    "electrical_violation_count", "unresolved_reference_count",
    "unexpected_blackbox_count", "latch_count",
    "unclocked_sync_endpoint_count",
}
ZERO_GATE_FIELDS = (
    "setup_violation_count", "hold_violation_count",
    "electrical_violation_count", "unresolved_reference_count",
    "unexpected_blackbox_count", "latch_count",
    "unclocked_sync_endpoint_count",
)

ALLOWED_SCOPE_PATHS = {
    ".github/workflows/public-integrity.yml",
    "Makefile",
    "docs/en/limitations.md",
    "docs/en/results.md",
    "docs/en/verification.md",
    "docs/zh-CN/limitations.md",
    "docs/zh-CN/results.md",
    "docs/zh-CN/verification.md",
    "flows/scripts/test_validate_asic_evidence.py",
    "flows/scripts/validate_asic_evidence.py",
    "provenance/README.md",
    "provenance/asic_paired_dc_publication.yaml",
    "provenance/checksums.sha256",
    "provenance/claims.yaml",
    "provenance/evidence.yaml",
    "provenance/nonclaims.yaml",
}

EVIDENCE_SCOPE_TRIGGER_PATHS = {
    path for path in ALLOWED_SCOPE_PATHS
    if path.startswith(("docs/", "provenance/"))
    and path != "provenance/checksums.sha256"
}

SENSITIVE_PATTERNS = (
    ("Windows absolute path", re.compile(r"(?i)(?<![A-Za-z0-9])[A-Z]:[\\/]")),
    ("UNC path", re.compile(
        r"(?m)(?<!\\)\\{2,4}[^\\\s]+\\{1,2}[^\\\s]+"
    )),
    ("POSIX absolute path", re.compile(
        r"(?m)(?<![A-Za-z0-9./])/(?![/\s])[^\s\"'<>]*"
    )),
    ("private Git remote", re.compile(r"(?i)(?:git@|ssh://|file://)")),
    ("private branch", re.compile(r"(?i)\b(?:eval|archive|fix)/[A-Za-z0-9_.\-/]+")),
    ("host or account field", re.compile(r"(?i)\b(?:host_?name|user_?name|account_?name)\b\s*[:=]")),
    ("license endpoint", re.compile(
        r"(?i)(?:SNPSLMD_LICENSE_FILE|LM_LICENSE_FILE|CDS_LIC_FILE|license_?(?:server|host))\s*[:=]"
    )),
)


class EvidenceError(RuntimeError):
    pass


def _fail(message):
    raise EvidenceError(message)


def _strict_json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key {!r}".format(key))
        result[key] = value
    return result


def _read_json(path):
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_strict_json_object,
        )
    except (OSError, TypeError, ValueError) as error:
        _fail("invalid JSON-syntax YAML {}: {}".format(path, error))


def _read_csv(path, expected_header):
    try:
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            if tuple(reader.fieldnames or ()) != tuple(expected_header):
                _fail("{} header mismatch".format(path.name))
            rows = list(reader)
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))
    for line_number, row in enumerate(rows, 2):
        if None in row:
            _fail("{}:{} has extra columns".format(path.name, line_number))
        if any(value is None for value in row.values()):
            _fail("{}:{} has missing columns".format(path.name, line_number))
    return rows


def _decimal(value, context):
    try:
        number = Decimal(value)
    except (InvalidOperation, ValueError):
        _fail("{} is not a decimal: {!r}".format(context, value))
    if not number.is_finite():
        _fail("{} is not finite".format(context))
    return number


def _canonical_decimal(number):
    if number == 0:
        return "0"
    rendered = format(number, "f")
    if "." in rendered:
        rendered = rendered.rstrip("0").rstrip(".")
    return rendered


def _validate_digest(value, bits, context):
    pattern = HEX40 if bits == 160 else HEX64
    if not pattern.fullmatch(value or ""):
        _fail("{} must be {} lowercase hex characters".format(context, bits // 4))


def _index_unique(rows, keys, label):
    indexed = {}
    for row in rows:
        key = tuple(row[name] for name in keys)
        if key in indexed:
            _fail("duplicate {} {}".format(label, key))
        indexed[key] = row
    return indexed


def _load_bundle(root):
    evidence = root / EVIDENCE_REL
    manifest = _read_json(root / MANIFEST_REL)
    tables = {}
    for name, header in CSV_HEADERS.items():
        tables[name] = _read_csv(evidence / name, header)
    return manifest, tables


def _validate_manifest(manifest):
    expected_manifest_fields = {
        "schema", "numeric_source", "derived_source", "formula_policy",
        "evaluations",
    }
    if set(manifest) != expected_manifest_fields:
        _fail("manifest field set mismatch")
    if manifest.get("schema") != "slvc_dma_public_asic_paired_dc_v1":
        _fail("manifest schema mismatch")
    if manifest.get("numeric_source") != "points.csv":
        _fail("points.csv must be the numeric source")
    if manifest.get("derived_source") != "comparisons.csv":
        _fail("comparisons.csv must be the derived source")
    expected_policy = {
        "delta": "candidate-baseline",
        "delta_percent": "100*(candidate-baseline)/baseline",
        "implementation": "decimal_v1",
        "delta_percent_scale": 6,
        "rounding": "ROUND_HALF_EVEN",
    }
    if manifest.get("formula_policy") != expected_policy:
        _fail("formula policy mismatch")
    evaluations = manifest.get("evaluations")
    if not isinstance(evaluations, list):
        _fail("manifest evaluations must be a list")
    by_id = {}
    claims = set()
    for item in evaluations:
        if not isinstance(item, dict) or not ID_RE.fullmatch(item.get("id", "")):
            _fail("invalid evaluation manifest entry")
        evaluation_id = item["id"]
        if evaluation_id in by_id:
            _fail("duplicate evaluation {}".format(evaluation_id))
        by_id[evaluation_id] = item
        claim_id = item.get("claim_id", "")
        if claim_id in claims:
            _fail("claim ID reused: {}".format(claim_id))
        claims.add(claim_id)
        for name in ("private_evidence_commit", "flow_as_run_commit"):
            if name in item:
                _validate_digest(item[name], 160, "{}.{}".format(evaluation_id, name))
    if set(by_id) != set(EXPECTED_EVALUATIONS):
        _fail("evaluation matrix mismatch")
    for evaluation_id, expected in EXPECTED_EVALUATIONS.items():
        item = by_id[evaluation_id]
        expected_fields = {
            "id", "claim_id", "private_evidence_commit", "claim_scope",
            "top", "baseline", "candidate", "parameters", "constraint_id",
            "comparison_metrics", "required_artifacts", "nonclaims",
        }
        if "flow_as_run_commit" in expected:
            expected_fields.update({
                "flow_as_run_commit", "canary", "canary_classification",
            })
        if evaluation_id == "writer_component":
            expected_fields.add("verification_reference")
        if set(item) != expected_fields:
            _fail("{} manifest field set mismatch".format(evaluation_id))
        if item.get("claim_id") != expected["claim_id"]:
            _fail("{} claim ID mismatch".format(evaluation_id))
        for field in (
            "private_evidence_commit", "top", "parameters", "constraint_id"
        ):
            if item.get(field) != expected[field]:
                _fail("{} fixed {} mismatch".format(evaluation_id, field))
        if item.get("flow_as_run_commit") != expected.get("flow_as_run_commit"):
            _fail("{} fixed flow_as_run_commit mismatch".format(evaluation_id))
        if item.get("claim_scope") != expected["claim_scope"]:
            _fail("{} fixed claim_scope mismatch".format(evaluation_id))
        if item.get("canary_classification") != expected.get(
            "canary_classification"
        ):
            _fail("{} fixed canary_classification mismatch".format(evaluation_id))
        nonclaims = item.get("nonclaims")
        if not isinstance(nonclaims, list) or tuple(nonclaims) != expected[
            "nonclaims"
        ]:
            _fail("{} fixed nonclaims mismatch".format(evaluation_id))
        for point_id, role in expected["roles"].items():
            manifest_key = {"baseline": "baseline", "candidate": "candidate", "canary": "canary"}[role]
            if item.get(manifest_key) != point_id:
                _fail("{} {} point mismatch".format(evaluation_id, role))
        metrics = item.get("comparison_metrics")
        if not isinstance(metrics, list) or tuple(metrics) != expected["metrics"]:
            _fail("{} fixed comparison metrics mismatch".format(evaluation_id))
        artifacts = item.get("required_artifacts")
        if not isinstance(artifacts, list) or tuple(artifacts) != expected["artifacts"]:
            _fail("{} fixed artifact list mismatch".format(evaluation_id))
    return by_id


def _validate_points(rows, evaluations):
    by_key = _index_unique(rows, ("evaluation_id", "point_id"), "point")
    expected_keys = {
        (evaluation_id, point_id)
        for evaluation_id, definition in EXPECTED_EVALUATIONS.items()
        for point_id in definition["roles"]
    }
    if set(by_key) != expected_keys:
        _fail("point matrix mismatch")
    for key, row in by_key.items():
        evaluation_id, point_id = key
        expected_role = EXPECTED_EVALUATIONS[evaluation_id]["roles"][point_id]
        if row["role"] != expected_role:
            _fail("{} role mismatch".format(point_id))
        _validate_digest(row["source_commit"], 160, "{}.source_commit".format(point_id))
        _validate_digest(row["library_sha256"], 256, "{}.library_sha256".format(point_id))
        if row["library_sha256"] != EXPECTED_LIBRARY_SHA256:
            _fail("{} library DB identity mismatch".format(point_id))
        if row["tool"] != "Design Compiler" or row["tool_version"] != "O-2018.06-SP1":
            _fail("{} tool identity mismatch".format(point_id))
        if row["compile_mode"] != "compile_ultra":
            _fail("{} compile mode mismatch".format(point_id))
        if row["library"] != "Nangate45" or row["corner"] != "typical":
            _fail("{} library/corner mismatch".format(point_id))
        for field in ("top", "parameters", "constraint_id"):
            if row[field] != EXPECTED_EVALUATIONS[evaluation_id][field]:
                _fail("{} fixed {} mismatch".format(point_id, field))
        for field, value in EXPECTED_EVALUATIONS[evaluation_id][
            "constraint_values"
        ].items():
            if row[field] != value:
                _fail("{} fixed numeric constraint mismatch: {}".format(
                    point_id, field
                ))
        for field in NUMERIC_FIELDS:
            if row[field] != "":
                _decimal(row[field], "{}.{}".format(point_id, field))
        for field in NONNEGATIVE_PHYSICAL_FIELDS:
            if row[field] == "":
                continue
            value = _decimal(row[field], "{}.{}".format(point_id, field))
            if value < 0:
                _fail("{} has negative physical metric {}".format(
                    point_id, field
                ))
            if field in DISCRETE_COUNT_FIELDS and value != value.to_integral_value():
                _fail("{} has non-integral count {}".format(point_id, field))
        for field in ZERO_GATE_FIELDS:
            if _decimal(row[field], "{}.{}".format(point_id, field)) != 0:
                _fail("{} has nonzero {}".format(point_id, field))
        if _decimal(row["setup_wns_ns"], point_id + ".setup_wns_ns") < 0:
            _fail("{} has negative setup WNS in setup-closed evidence".format(point_id))
        if _decimal(row["setup_tns_ns"], point_id + ".setup_tns_ns") != 0:
            _fail("{} has nonzero setup TNS in setup-closed evidence".format(point_id))
        if _decimal(row["hold_wns_ns"], point_id + ".hold_wns_ns") < 0:
            _fail("{} has negative hold WNS in hold-closed evidence".format(point_id))
        if _decimal(row["hold_tns_ns"], point_id + ".hold_tns_ns") != 0:
            _fail("{} has nonzero hold TNS in hold-closed evidence".format(point_id))
        for field in ("writer_setup_wns_ns", "writer_hold_wns_ns"):
            if row[field] != "" and _decimal(row[field], point_id + "." + field) < 0:
                _fail("{} has negative {}".format(point_id, field))
    for evaluation_id, item in evaluations.items():
        baseline = by_key[(evaluation_id, item["baseline"])]
        candidate = by_key[(evaluation_id, item["candidate"])]
        for field in PAIR_IDENTITY_FIELDS:
            if baseline[field] != candidate[field]:
                _fail("{} pair identity mismatch: {}".format(evaluation_id, field))
        for metric in item["comparison_metrics"]:
            if baseline[metric] == "" or candidate[metric] == "":
                _fail("{} comparison metric {} is empty".format(evaluation_id, metric))
    return by_key


def _validate_sources(rows, points):
    _index_unique(rows, ("evaluation_id", "scope", "point_id", "path"), "source")
    actual_inventory = {
        tuple(row[field] for field in (
            "evaluation_id", "scope", "point_id", "source_commit", "path",
            "blob", "sha256", "size_bytes",
        ))
        for row in rows
    }
    if actual_inventory != EXPECTED_SOURCE_INVENTORY:
        _fail("fixed source inventory mismatch")
    point_sources = {}
    for row in rows:
        _validate_digest(row["source_commit"], 160, "source commit")
        _validate_digest(row["blob"], 160, "source blob")
        _validate_digest(row["sha256"], 256, "source sha256")
        if _decimal(row["size_bytes"], "source size") <= 0:
            _fail("source size must be positive")
        if row["scope"] not in ("point", "common"):
            _fail("invalid source scope")
        source_path = row["path"]
        if (
            not source_path or "\\" in source_path or source_path.startswith("/")
            or re.match(r"(?i)^[a-z]:", source_path)
            or any(part in ("", ".", "..") for part in source_path.split("/"))
        ):
            _fail("source path must be repository-relative and normalized")
        if row["scope"] == "point":
            key = (row["evaluation_id"], row["point_id"])
            if key not in points:
                _fail("source references unknown point {}".format(key))
            if row["source_commit"] != points[key]["source_commit"]:
                _fail("commit/source mapping mismatch for {}".format(key))
            point_sources.setdefault(key, []).append(row)
        elif row["point_id"] != "*":
            _fail("common source point_id must be *")
    if set(point_sources) != set(points):
        _fail("every point must have a fixed source mapping")

    for component_point, c2b4_point in (
        ("writer_component_w0", "c2b4_writer_w0"),
        ("writer_component_w1", "c2b4_writer_w1"),
    ):
        left = point_sources[("writer_component", component_point)]
        right = point_sources[("c2b4_writer", c2b4_point)]
        left_map = {(row["path"], row["source_commit"], row["sha256"], row["blob"], row["size_bytes"]) for row in left}
        right_map = {(row["path"], row["source_commit"], row["sha256"], row["blob"], row["size_bytes"]) for row in right}
        if left_map != right_map:
            _fail("writer component/C2B4 source hash mismatch for {}".format(component_point))


def _validate_verification(root, rows, points, evaluations):
    by_key = _index_unique(
        rows, ("evaluation_id", "point_id", "platform", "suite_id"),
        "verification",
    )
    expected = set()
    for point_id in EXPECTED_EVALUATIONS["c2b4_writer"]["roles"]:
        for platform in ("windows", "linux"):
            for suite in ("writer_2028", "writer_integration", "a3_profile"):
                expected.add(("c2b4_writer", point_id, platform, suite))
    for point_id in EXPECTED_EVALUATIONS["shared_pool_scheduler"]["roles"]:
        for platform in ("windows", "linux"):
            expected.add(("shared_pool_scheduler", point_id, platform, "shared_pool"))
    if set(by_key) != expected:
        _fail("verification matrix mismatch")
    traces = {}
    for key, row in by_key.items():
        if row["status"] != "PASS":
            _fail("verification status is not PASS for {}".format(key))
        expected_tool = EXPECTED_SIMULATORS.get(row["platform"])
        if row["tool_version"] != expected_tool:
            _fail("simulator identity mismatch for {}".format(key))
        markers = tuple(row["required_markers"].split("|")) if row["required_markers"] else ()
        expected_markers = EXPECTED_MARKERS[row["suite_id"]]
        if markers != expected_markers:
            _fail("canonical required markers mismatch for {}".format(key))
        if int(row["marker_count"]) != len(expected_markers):
            _fail("required marker count mismatch for {}".format(key))
        _validate_digest(row["semantic_trace_sha256"], 256, "semantic trace")
        _validate_digest(row["log_sha256"], 256, "verification log")
        if int(row["log_size_bytes"]) <= 0:
            _fail("verification log size must be positive")
        trace_key = (row["evaluation_id"], row["suite_id"])
        traces.setdefault(trace_key, set()).add(row["semantic_trace_sha256"])
    for trace_key, digests in traces.items():
        if len(digests) != 1:
            _fail("semantic trace mismatch for {}".format(trace_key))
    if evaluations["writer_component"].get("verification_reference") != "c2b4_writer":
        _fail("writer component verification reference mismatch")
    for suffix in ("w0", "w1"):
        component = points[("writer_component", "writer_component_" + suffix)]
        subsystem = points[("c2b4_writer", "c2b4_writer_" + suffix)]
        if component["source_commit"] != subsystem["source_commit"]:
            _fail("writer verification source commit mismatch")
    if _sha256(root / EVIDENCE_REL / "verification.csv") != (
        EXPECTED_VERIFICATION_SHA256
    ):
        _fail("fixed verification digest inventory mismatch")


def _validate_lint(root, rows):
    by_key = _index_unique(rows, ("evaluation_id", "point_id", "scope"), "lint")
    expected_keys = {
        ("c2b4_writer", point_id, "writer_bounded")
        for point_id in EXPECTED_EVALUATIONS["c2b4_writer"]["roles"]
    }
    expected_keys.add(("c2b4_writer", "common_snapshot", "full_c2b4_common"))
    expected_keys.update({
        ("shared_pool_scheduler", point_id, "component_bounded")
        for point_id in EXPECTED_EVALUATIONS["shared_pool_scheduler"]["roles"]
    })
    if set(by_key) != expected_keys:
        _fail("lint matrix mismatch")
    for key, row in by_key.items():
        _validate_digest(row["report_sha256"], 256, "lint report")
        if row["tool_version"] != "SpyGlass L-2016.06":
            _fail("lint tool identity mismatch for {}".format(key))
        counts = {name: int(row[name]) for name in (
            "fatal_count", "error_count", "warning_count", "waived_count"
        )}
        if any(value < 0 for value in counts.values()):
            _fail("lint counts must be nonnegative for {}".format(key))
        if key == ("c2b4_writer", "common_snapshot", "full_c2b4_common"):
            expected = {"fatal_count": 0, "error_count": 15, "warning_count": 202, "waived_count": 0}
            if row["status"] != "BLOCKED_COMMON_SCOPE" or counts != expected:
                _fail("C2B4 lint boundary must remain BLOCKED_COMMON_SCOPE 0/15/202/0")
        else:
            if row["status"] != "PASS_WITH_REVIEWED_WARNINGS":
                _fail("bounded lint status mismatch for {}".format(key))
            if counts["fatal_count"] != 0 or counts["error_count"] != 0:
                _fail("bounded lint has fatal/error for {}".format(key))
            if counts["waived_count"] != 0:
                _fail("lint waivers are not permitted for {}".format(key))
    if _sha256(root / EVIDENCE_REL / "lint.csv") != EXPECTED_LINT_SHA256:
        _fail("fixed bounded-lint evidence inventory mismatch")


def _validate_artifacts(root, rows, evaluations, points):
    by_key = _index_unique(rows, ("evaluation_id", "point_id", "logical_name"), "artifact")
    grouped = {}
    for key, row in by_key.items():
        evaluation_id, point_id, logical_name = key
        if (evaluation_id, point_id) not in points:
            _fail("artifact references unknown point {}".format(key))
        _validate_digest(row["sha256"], 256, "artifact hash")
        if row["published_payload"] != "hash_only":
            _fail("artifact payload must be hash_only")
        if row["artifact_class"] not in ("dc_report", "mapped_output"):
            _fail("invalid artifact class")
        grouped.setdefault((evaluation_id, point_id), set()).add(logical_name)
    for (evaluation_id, point_id) in points:
        required = set(evaluations[evaluation_id]["required_artifacts"])
        if grouped.get((evaluation_id, point_id)) != required:
            _fail("artifact checklist mismatch for {}".format(point_id))
    if _sha256(root / EVIDENCE_REL / "artifacts.csv") != EXPECTED_ARTIFACTS_SHA256:
        _fail("fixed commercial-report digest inventory mismatch")


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _text_sha256(path):
    return hashlib.sha256(path.read_text(encoding="utf-8").encode("utf-8")).hexdigest()


def _strip_authorized_registry_item(text, item_id, context):
    pattern = re.compile(
        r"(?ms)^  - id: " + re.escape(item_id) + r"\n.*?(?=^  - id: |\Z)"
    )
    matches = list(pattern.finditer(text))
    if len(matches) > 1:
        _fail("{} contains duplicate authorized throughput records".format(context))
    if not matches:
        return text
    match = matches[0]
    return text[:match.start()] + text[match.end():]


def _registry_sha256_without_authorized_item(path, item_id):
    text = path.read_text(encoding="utf-8")
    normalized = _strip_authorized_registry_item(text, item_id, str(path))
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _normalized_evidence_registry_sha256(path):
    text = path.read_text(encoding="utf-8")
    text = _strip_authorized_registry_item(
        text, AUTHORIZED_THROUGHPUT_EVIDENCE_ID, str(path)
    )
    pattern = (
        r"(?ms)(^  - id: slvc_dma_asic_paired_dc_publication\n"
        r".*?^    sha256: )[0-9a-f]{64}(?=\n)"
    )
    normalized, replacements = re.subn(
        pattern, r"\1<PUBLICATION_SHA256>", text
    )
    if replacements != 1:
        _fail("paired-DC evidence registry hash field mismatch")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _registered_records(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))
    records = {}
    current_id = None
    current_lines = []
    for line in text.splitlines():
        match = re.fullmatch(r"  - id: ([a-z0-9_.-]+)", line)
        if match:
            if current_id is not None:
                records[current_id] = "\n".join(current_lines)
            current_id = match.group(1)
            if current_id in records:
                _fail("{} contains duplicate IDs".format(path))
            current_lines = []
        elif current_id is not None:
            current_lines.append(line)
    if current_id is not None:
        if current_id in records:
            _fail("{} contains duplicate IDs".format(path))
        records[current_id] = "\n".join(current_lines)
    return records


def _record_list(body, field, context):
    lines = body.splitlines()
    marker = "    {}:".format(field)
    if lines.count(marker) != 1:
        _fail("{} has no {} list".format(context, field))
    start = lines.index(marker) + 1
    values = []
    for line in lines[start:]:
        match = re.fullmatch(r"      - ([a-z0-9_.-]+)", line)
        if not match:
            break
        values.append(match.group(1))
    if not values or len(values) != len(set(values)):
        _fail("{} has invalid {} list".format(context, field))
    return values


def _record_scalar(body, field, context, value_pattern):
    matches = re.findall(
        r"(?m)^    {}: ({})$".format(field, value_pattern), body
    )
    if len(matches) != 1:
        _fail("{} has invalid {} field".format(context, field))
    return matches[0]


def _validate_record_fields(body, expected, context):
    fields = []
    for line in body.splitlines():
        if not line.startswith("    ") or line.startswith("      "):
            continue
        match = re.fullmatch(r"    ([a-z][a-z0-9_]*):(?: .*)?", line)
        if not match:
            _fail("{} contains noncanonical field syntax".format(context))
        fields.append(match.group(1))
    if len(fields) != len(set(fields)) or set(fields) != set(expected):
        _fail("{} field set mismatch".format(context))


def _validate_nonclaims(root):
    records = _registered_records(root / "provenance/nonclaims.yaml")
    if not set(EXPECTED_NONCLAIMS).issubset(records):
        _fail("paired-DC nonclaim registry record is missing")
    for nonclaim_id, expected in EXPECTED_NONCLAIMS.items():
        _validate_record_fields(
            records[nonclaim_id], expected, nonclaim_id
        )
        for field, value in expected.items():
            actual = _record_scalar(
                records[nonclaim_id], field, nonclaim_id, r".+"
            )
            if actual != value:
                _fail("{} fixed {} mismatch".format(nonclaim_id, field))
    if _registry_sha256_without_authorized_item(
        root / "provenance/nonclaims.yaml", AUTHORIZED_THROUGHPUT_NONCLAIM_ID
    ) != EXPECTED_NONCLAIMS_SHA256:
        _fail("fixed paired-DC nonclaim registry inventory mismatch")


def _validate_publication(root, evaluations):
    publication = _read_json(root / PUBLICATION_REL)
    expected_publication_fields = {
        "schema", "publication_class", "numeric_authority",
        "generated_derivative", "raw_commercial_artifacts_published",
        "claim_ids", "fixed_evidence_commits", "files",
        "c2b4_lint_boundary", "commercial_artifact_policy",
    }
    if set(publication) != expected_publication_fields:
        _fail("publication field set mismatch")
    if publication.get("schema") != "slvc_dma_asic_paired_dc_publication_v1":
        _fail("publication schema mismatch")
    if publication.get("publication_class") != "sanitized_hash_bound_summary":
        _fail("publication class mismatch")
    if publication.get("numeric_authority") != str(EVIDENCE_REL / "points.csv").replace("\\", "/"):
        _fail("publication numeric authority mismatch")
    if publication.get("generated_derivative") != str(COMPARISONS_REL).replace("\\", "/"):
        _fail("publication derivative mismatch")
    if publication.get("raw_commercial_artifacts_published") is not False:
        _fail("raw commercial artifacts must remain unpublished")

    expected_claims_ordered = tuple(
        EXPECTED_EVALUATIONS[evaluation_id]["claim_id"]
        for evaluation_id in (
            "writer_component", "c2b4_writer", "shared_pool_scheduler"
        )
    )
    expected_claims = set(expected_claims_ordered)
    claim_ids = publication.get("claim_ids")
    if not isinstance(claim_ids, list):
        _fail("publication claim IDs are invalid")
    if tuple(claim_ids) != expected_claims_ordered:
        _fail("publication claim IDs mismatch")
    expected_commits = {
        item["private_evidence_commit"]
        for item in EXPECTED_EVALUATIONS.values()
    }
    commits = publication.get("fixed_evidence_commits")
    if not isinstance(commits, list) or set(commits) != expected_commits:
        _fail("publication evidence commits mismatch")
    for commit in commits:
        _validate_digest(commit, 160, "publication evidence commit")

    evidence_root = root / EVIDENCE_REL
    if any(path.is_symlink() for path in evidence_root.rglob("*")):
        _fail("publication payload must not contain symlinks")
    actual_files = {
        str(path.relative_to(root)).replace("\\", "/")
        for path in evidence_root.rglob("*") if path.is_file()
    }
    if actual_files != EXPECTED_PUBLICATION_FILES:
        _fail("publication payload file set mismatch")
    if _sha256(root / EVIDENCE_REL / "README.md") != EXPECTED_EVIDENCE_README_SHA256:
        _fail("fixed evidence README content mismatch")
    files = publication.get("files")
    if not isinstance(files, dict) or set(files) != EXPECTED_PUBLICATION_FILES:
        _fail("publication file inventory mismatch")
    for relative, digest in files.items():
        _validate_digest(digest, 256, "publication file hash")
        if _sha256(root / relative) != digest:
            _fail("publication hash mismatch for {}".format(relative))

    expected_lint = {
        "status": "BLOCKED_COMMON_SCOPE", "fatal": 0, "error": 15,
        "warning": 202, "waived": 0,
    }
    if publication.get("c2b4_lint_boundary") != expected_lint:
        _fail("publication C2B4 lint boundary mismatch")
    if publication.get("commercial_artifact_policy") != "logical_name_and_sha256_only":
        _fail("publication commercial artifact policy mismatch")

    claim_records = _registered_records(root / "provenance/claims.yaml")
    evidence_records = _registered_records(root / "provenance/evidence.yaml")
    if not expected_claims.issubset(claim_records):
        _fail("paired-DC claim is missing from provenance/claims.yaml")
    publication_id = "slvc_dma_asic_paired_dc_publication"
    if publication_id not in evidence_records:
        _fail("paired-DC evidence is missing from provenance/evidence.yaml")
    _validate_record_fields(
        evidence_records[publication_id],
        {"path", "type", "source_ref", "tool", "claims", "sha256", "public"},
        publication_id,
    )
    claim_evidence = {
        claim_id: _record_list(body, "evidence", claim_id)
        for claim_id, body in claim_records.items()
    }
    bound_claims = {
        claim_id for claim_id, references in claim_evidence.items()
        if publication_id in references
    }
    if bound_claims != expected_claims:
        _fail("publication evidence has unexpected claim binding")
    for field, value in EXPECTED_EVIDENCE_RECORD.items():
        actual = _record_scalar(
            evidence_records[publication_id], field, publication_id, r".+"
        )
        if actual != value:
            _fail("publication evidence fixed {} mismatch".format(field))
    for claim_id in expected_claims:
        evaluation_id = next(
            name for name, item in EXPECTED_EVALUATIONS.items()
            if item["claim_id"] == claim_id
        )
        definition = EXPECTED_EVALUATIONS[evaluation_id]
        _validate_record_fields(
            claim_records[claim_id],
            set(definition["claim_record"])
            | {"source_ref", "evidence", "status", "public"},
            claim_id,
        )
        references = claim_evidence[claim_id]
        if references != [publication_id]:
            _fail("paired-DC claims are not bound to publication evidence")
        for field, value in definition["claim_record"].items():
            actual = _record_scalar(
                claim_records[claim_id], field, claim_id, r".+"
            )
            if actual != value:
                _fail("{} fixed {} mismatch".format(claim_id, field))
        source_ref = _record_scalar(
            claim_records[claim_id], "source_ref", claim_id, r"[0-9a-f]{40}"
        )
        if source_ref != definition["private_evidence_commit"]:
            _fail("{} source_ref does not match fixed evidence commit".format(claim_id))
        if _record_scalar(claim_records[claim_id], "status", claim_id, r"\S+") != "verified":
            _fail("{} must remain verified".format(claim_id))
        if _record_scalar(claim_records[claim_id], "public", claim_id, r"\S+") != "true":
            _fail("{} must remain public".format(claim_id))
    mapped_claims = tuple(_record_list(
        evidence_records[publication_id], "claims", publication_id
    ))
    if mapped_claims != expected_claims_ordered:
        _fail("publication evidence claim mapping mismatch")
    publication_path = _record_scalar(
        evidence_records[publication_id], "path", publication_id, r"\S+"
    )
    publication_hash = _record_scalar(
        evidence_records[publication_id], "sha256", publication_id, r"[0-9a-f]{64}"
    )
    expected_path = str(PUBLICATION_REL).replace("\\", "/")
    if publication_path != expected_path:
        _fail("provenance evidence path must bind the publication manifest")
    if publication_hash != _sha256(root / PUBLICATION_REL):
        _fail("provenance evidence hash must bind the publication manifest")
    if _registry_sha256_without_authorized_item(
        root / "provenance/claims.yaml", AUTHORIZED_THROUGHPUT_CLAIM_ID
    ) != EXPECTED_CLAIMS_SHA256:
        _fail("fixed claim registry inventory mismatch")
    if _normalized_evidence_registry_sha256(
        root / "provenance/evidence.yaml"
    ) != EXPECTED_EVIDENCE_REGISTRY_NORMALIZED_SHA256:
        _fail("fixed evidence registry inventory mismatch")
    if _text_sha256(
        root / "provenance/README.md"
    ) != EXPECTED_PROVENANCE_README_SHA256:
        _fail("fixed provenance README content mismatch")


def _comparison_records(evaluations, points):
    records = []
    quantizer = Decimal("0.000001")
    for evaluation_id in ("writer_component", "c2b4_writer", "shared_pool_scheduler"):
        item = evaluations[evaluation_id]
        baseline = points[(evaluation_id, item["baseline"])]
        candidate = points[(evaluation_id, item["candidate"])]
        for metric in item["comparison_metrics"]:
            baseline_value = _decimal(baseline[metric], metric)
            candidate_value = _decimal(candidate[metric], metric)
            delta = candidate_value - baseline_value
            percent = ""
            if baseline_value != 0:
                percent = _canonical_decimal(
                    (Decimal(100) * delta / baseline_value).quantize(
                        quantizer, rounding=ROUND_HALF_EVEN
                    )
                )
            records.append({
                "evaluation_id": evaluation_id,
                "claim_id": item["claim_id"],
                "baseline_point_id": item["baseline"],
                "candidate_point_id": item["candidate"],
                "metric": metric,
                "baseline": _canonical_decimal(baseline_value),
                "candidate": _canonical_decimal(candidate_value),
                "delta": _canonical_decimal(delta),
                "delta_percent": percent,
            })
    return records


def _validate_claim_values(evaluations, points):
    records = {
        (row["evaluation_id"], row["metric"]): row
        for row in _comparison_records(evaluations, points)
    }
    for evaluation_id, expected in EXPECTED_EVALUATIONS.items():
        for metric, fields in expected["claim_values"].items():
            row = records[(evaluation_id, metric)]
            for field, value in fields.items():
                if row[field] != value:
                    _fail(
                        "{} fixed claim value mismatch for {}.{}".format(
                            evaluation_id, metric, field
                        )
                    )


def _comparison_bytes(evaluations, points):
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=COMPARISON_HEADER, lineterminator="\n")
    writer.writeheader()
    for row in _comparison_records(evaluations, points):
        writer.writerow(row)
    return output.getvalue().encode("utf-8")


def _validate_comparisons(root, expected, write):
    path = root / COMPARISONS_REL
    if write:
        path.write_bytes(expected)
        return
    if not path.is_file():
        _fail("comparisons.csv is missing")
    if path.read_bytes() != expected:
        _fail("comparisons.csv does not match Decimal recomputation")


def _replace_record_scalar(path, record_id, field, value):
    text = path.read_text(encoding="utf-8")
    start_marker = "  - id: {}\n".format(record_id)
    if text.count(start_marker) != 1:
        _fail("{} record is not unique in {}".format(record_id, path))
    prefix, remainder = text.split(start_marker, 1)
    next_record = remainder.find("\n  - id: ")
    if next_record < 0:
        body, suffix = remainder, ""
    else:
        body, suffix = remainder[:next_record], remainder[next_record:]
    pattern = re.compile(r"(?m)^    {}: \S+$".format(field))
    replacement = "    {}: {}".format(field, value)
    body, count = pattern.subn(replacement, body)
    if count != 1:
        _fail("{} has invalid {} field".format(record_id, field))
    with path.open("w", encoding="utf-8", newline="\n") as output:
        output.write(prefix + start_marker + body + suffix)


def _refresh_publication_chain(root):
    publication_path = root / PUBLICATION_REL
    publication = _read_json(publication_path)
    evidence_files = publication.get("files")
    if not isinstance(evidence_files, dict) or set(evidence_files) != EXPECTED_PUBLICATION_FILES:
        _fail("publication file inventory mismatch before regeneration")
    publication["files"] = {
        relative: _sha256(root / relative)
        for relative in sorted(EXPECTED_PUBLICATION_FILES)
    }
    with publication_path.open("w", encoding="utf-8", newline="\n") as output:
        output.write(json.dumps(publication, indent=2) + "\n")
    _replace_record_scalar(
        root / "provenance/evidence.yaml",
        "slvc_dma_asic_paired_dc_publication",
        "sha256",
        _sha256(publication_path),
    )


def _refresh_repository_checksums(root):
    checksum_path = root / CHECKSUM_REL
    try:
        lines = checksum_path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        _fail("cannot read repository checksum manifest: {}".format(error))

    targets = set(EXPECTED_PUBLICATION_FILES)
    targets.update({
        str(PUBLICATION_REL).replace("\\", "/"),
        "provenance/evidence.yaml",
    })
    seen = set()
    rendered = []
    for line in lines:
        match = re.match(r"^([0-9a-f]{64})  (.+)$", line)
        if not match:
            _fail("repository checksum manifest has an invalid record")
        digest, relative = match.groups()
        if relative in seen:
            _fail("repository checksum manifest has a duplicate path")
        seen.add(relative)
        if relative in targets:
            candidate = root.joinpath(*Path(relative).parts)
            if not candidate.is_file():
                _fail("checksum refresh input is missing: {}".format(relative))
            digest = _sha256(candidate)
        rendered.append("{}  {}\n".format(digest, relative))
    missing = targets - seen
    if missing:
        _fail("repository checksum manifest is missing publication inputs")
    with checksum_path.open("w", encoding="utf-8", newline="\n") as output:
        output.write("".join(rendered))


def _validate_sanitization(root, extra_paths=None):
    evidence = root / EVIDENCE_REL
    forbidden_suffixes = {".log", ".rpt", ".ddc", ".sdc", ".spef", ".db"}
    for path in evidence.rglob("*"):
        if path.is_file() and path.suffix.lower() in forbidden_suffixes:
            _fail("raw EDA artifact is forbidden: {}".format(path.relative_to(root)))
    paths = [path for path in evidence.rglob("*") if path.is_file()]
    publication = root / "provenance/asic_paired_dc_publication.yaml"
    if publication.is_file():
        paths.append(publication)
    for path in extra_paths or ():
        candidate = root / path
        if candidate.is_file() and candidate not in paths:
            paths.append(candidate)
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        scan_text = text.replace("100*(candidate-baseline)/baseline", "")
        scan_text = re.sub(r"</[A-Za-z][A-Za-z0-9-]*>", "", scan_text)
        for label, pattern in SENSITIVE_PATTERNS:
            if pattern.search(scan_text):
                _fail("{} contains {}".format(path.relative_to(root), label))


def _validate_result_tables(root):
    for relative, expected_rows in EXPECTED_RESULT_ROWS.items():
        try:
            text = (root / relative).read_text(encoding="utf-8")
        except OSError as error:
            _fail("cannot read result table {}: {}".format(relative, error))
        for expected in expected_rows:
            if text.count(expected) != 1:
                _fail("fixed result table row mismatch in {}".format(relative))

    for relative, expected_hash in EXPECTED_DOC_SHA256.items():
        try:
            text = (root / relative).read_text(encoding="utf-8")
        except OSError as error:
            _fail("cannot read evidence document {}: {}".format(relative, error))
        if relative in ("docs/en/results.md", "docs/zh-CN/results.md"):
            marker_pattern = re.compile(
                r"(?ms)^" + re.escape(AUTHORIZED_RESULTS_START) +
                r"\n.*?^" + re.escape(AUTHORIZED_RESULTS_END) + r"\n?"
            )
            matches = list(marker_pattern.finditer(text))
            if len(matches) > 1 or (
                    text.count(AUTHORIZED_RESULTS_START) != len(matches) or
                    text.count(AUTHORIZED_RESULTS_END) != len(matches)):
                _fail("invalid authorized throughput block in {}".format(relative))
            if matches:
                match = matches[0]
                text = text[:match.start()] + text[match.end():]
        digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
        if digest != expected_hash:
            _fail("fixed evidence document content mismatch in {}".format(relative))


def _git_paths(root, arguments):
    try:
        output = subprocess.check_output(
            ["git"] + list(arguments), cwd=str(root), stderr=subprocess.STDOUT
        )
    except (OSError, subprocess.CalledProcessError) as error:
        _fail("git scope query failed: {}".format(error))
    return [item.decode("utf-8").replace("\\", "/") for item in output.split(b"\0") if item]


def _validate_scope(root, base_ref):
    changed = set(_git_paths(root, ("diff", "--name-only", "-z", base_ref + "...HEAD")))
    changed.update(_git_paths(root, ("diff", "--name-only", "-z")))
    changed.update(_git_paths(root, ("diff", "--cached", "--name-only", "-z")))
    changed.update(_git_paths(root, ("ls-files", "--others", "--exclude-standard", "-z")))
    if not _evidence_scope_active(changed):
        return "NOT_APPLICABLE"
    for path in sorted(changed):
        if path.startswith("evidence/asic_paired_dc/"):
            continue
        if path not in ALLOWED_SCOPE_PATHS:
            _fail("PR scope forbids change to {}".format(path))
    published_text = {
        path for path in changed
        if path.startswith(("evidence/", "provenance/", "docs/"))
    }
    _validate_sanitization(root, published_text)
    return "EVIDENCE_SCOPE_PASS"


def _evidence_scope_active(changed):
    return bool(set(changed) & EVIDENCE_SCOPE_TRIGGER_PATHS) or any(
        path.startswith("evidence/asic_paired_dc/") for path in changed
    )


def validate(root, write_comparisons=False, base_ref=None):
    root = Path(root).resolve()
    manifest, tables = _load_bundle(root)
    evaluations = _validate_manifest(manifest)
    points = _validate_points(tables["points.csv"], evaluations)
    _validate_claim_values(evaluations, points)
    if _sha256(root / EVIDENCE_REL / "points.csv") != EXPECTED_POINTS_SHA256:
        _fail("fixed points numeric authority mismatch")
    _validate_sources(tables["sources.csv"], points)
    _validate_verification(root, tables["verification.csv"], points, evaluations)
    _validate_lint(root, tables["lint.csv"])
    _validate_artifacts(root, tables["artifacts.csv"], evaluations, points)
    expected = _comparison_bytes(evaluations, points)
    _validate_comparisons(root, expected, write_comparisons)
    if write_comparisons:
        _refresh_publication_chain(root)
        _refresh_repository_checksums(root)
    published_text = {
        path for path in ALLOWED_SCOPE_PATHS
        if path.startswith(("docs/", "provenance/"))
        and path != "provenance/checksums.sha256"
    }
    _validate_sanitization(root, published_text)
    _validate_result_tables(root)
    _validate_nonclaims(root)
    _validate_publication(root, evaluations)
    if base_ref:
        _validate_scope(root, base_ref)
    return {
        "evaluations": len(evaluations),
        "points": len(points),
        "comparisons": expected.count(b"\n") - 1,
        "verification_records": len(tables["verification.csv"]),
        "artifact_hashes": len(tables["artifacts.csv"]),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("--write-comparisons", action="store_true")
    parser.add_argument("--base-ref")
    args = parser.parse_args(argv)
    try:
        summary = validate(args.root, args.write_comparisons, args.base_ref)
    except EvidenceError as error:
        print("asic-evidence: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "asic-evidence: {evaluations} evaluations, {points} points, "
        "{comparisons} comparisons, {verification_records} verification records, "
        "and {artifact_hashes} artifact hashes verified".format(**summary)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
