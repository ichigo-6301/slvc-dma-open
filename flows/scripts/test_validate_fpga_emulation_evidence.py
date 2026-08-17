#!/usr/bin/env python3
"""Unit and mutation tests for the U5 FPGA evidence gate."""

import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from flows.scripts import validate_fpga_emulation_evidence as gate


ROOT = Path(__file__).resolve().parents[2]


class FpgaEvidenceGateTest(unittest.TestCase):
    def test_decimal_derivation_matches_observation(self):
        actual = gate.derive_metrics(gate.RAW_ROW)
        self.assertEqual("1.558722", actual["mb_per_s_per_mhz"])
        self.assertEqual("155.872225", actual["mb_per_s_at_100mhz"])
        self.assertEqual("1.246978", actual["gbits_per_s_at_100mhz"])
        self.assertEqual("38.968056", actual["hp0_shared_model_efficiency"])

    def test_zero_ticks_fail_closed(self):
        row = dict(gate.RAW_ROW)
        row["xtime_ticks"] = "0"
        with self.assertRaises(gate.EvidenceError):
            gate.derive_metrics(row)

    def test_equivalent_cycles_are_recomputed(self):
        row = dict(gate.RAW_ROW)
        row["rounded_equivalent_pl_cycles"] = "2690861"
        with self.assertRaises(gate.EvidenceError):
            gate.derive_metrics(row)

    def test_sensitive_windows_path_is_rejected(self):
        with self.assertRaises(gate.EvidenceError):
            gate._verify_sensitive_text(Path("log.txt"), "D:/private/top.bit")

    def test_jtag_serial_is_rejected(self):
        with self.assertRaises(gate.EvidenceError):
            gate._verify_sensitive_text(
                Path("log.txt"), "Platform Cable USB II 136202079204c3"
            )

    def test_source_tree_uses_fixed_public_ref(self):
        with mock.patch.object(
                gate.subprocess, "check_output", return_value=b"") as command:
            with self.assertRaises(gate.EvidenceError):
                gate._verify_git_source_tree(ROOT)
        args = command.call_args[0][0]
        self.assertEqual(gate.PUBLIC_SOURCE_REF, args[3])
        self.assertNotIn("HEAD", args)

    def test_source_control_flow_rejects_report_before_checks(self):
        source = (ROOT / gate.BENCHMARK_REL / "helloworld.c")
        if not source.is_file():
            self.skipTest("publication benchmark is not present on policy-only ref")
        text = source.read_text(encoding="utf-8")
        broken = text.replace(
            'report_throughput_window("hardware_end_to_end"',
            'report_throughput_window_removed("hardware_end_to_end"',
        )
        with self.assertRaises(gate.EvidenceError):
            gate._verify_source_control_flow(broken)

    def test_source_control_flow_rejects_timer_before_start_write(self):
        source = (ROOT / gate.BENCHMARK_REL / "helloworld.c")
        if not source.is_file():
            self.skipTest("publication benchmark is not present on policy-only ref")
        text = source.read_text(encoding="utf-8")
        write_token = "dma_write_sync(desc + DMA_TX_DESC_CTRL,"
        timer_token = "XTime_GetTime(&start_time);"
        write_pos = text.index(write_token)
        timer_pos = text.index(timer_token, write_pos)
        broken = (
            text[:write_pos] + timer_token + "\n    " +
            text[write_pos:timer_pos] + text[timer_pos + len(timer_token):]
        )
        with self.assertRaises(gate.EvidenceError):
            gate._verify_source_control_flow(broken)

    def _published_fixture(self):
        claims = ROOT / gate.CLAIMS_REL
        if not claims.is_file() or "  - id: {}\n".format(
                gate.CLAIM_ID) not in claims.read_text(encoding="utf-8"):
            self.skipTest("publication fixture is not present on policy-only ref")
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name) / "repo"
        shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns(".git"))
        return temp, root

    def test_unpublished_implementation_mutation_fails(self):
        claims = (ROOT / gate.CLAIMS_REL).read_text(encoding="utf-8")
        if "  - id: {}\n".format(gate.CLAIM_ID) in claims:
            self.skipTest("unpublished fixture is not present on evidence ref")
        temp = tempfile.TemporaryDirectory()
        try:
            root = Path(temp.name) / "repo"
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns(".git"))
            path = root / "docs/en/fpga_implementation.md"
            path.write_text(
                path.read_text(encoding="utf-8") + "\nUnsupported 999 MHz Fmax.\n",
                encoding="utf-8",
            )
            with self.assertRaises(gate.EvidenceError):
                gate.validate(root, check_git_identity=False)
        finally:
            temp.cleanup()

    def test_published_fixture_passes_without_git_identity(self):
        temp, root = self._published_fixture()
        try:
            self.assertEqual(
                "FPGA_EMULATION_EVIDENCE_PASS",
                gate.validate(root, check_git_identity=False),
            )
        finally:
            temp.cleanup()

    def test_counter_mutation_fails(self):
        temp, root = self._published_fixture()
        try:
            path = root / gate.PACKAGE_REL / "raw_counters.csv"
            path.write_text(
                path.read_text(encoding="utf-8").replace("8969535", "8969534"),
                encoding="utf-8",
            )
            with self.assertRaises(gate.EvidenceError):
                gate.validate(root, check_git_identity=False)
        finally:
            temp.cleanup()

    def test_source_mutation_fails(self):
        temp, root = self._published_fixture()
        try:
            path = root / gate.BENCHMARK_REL / "helloworld.c"
            path.write_text(
                path.read_text(encoding="utf-8") + "\n/* mutation */\n",
                encoding="utf-8",
            )
            with self.assertRaises(gate.EvidenceError):
                gate.validate(root, check_git_identity=False)
        finally:
            temp.cleanup()

    def test_resume_promotion_fails(self):
        temp, root = self._published_fixture()
        try:
            path = root / gate.CLAIMS_REL
            text = path.read_text(encoding="utf-8")
            block = gate._item_block(text, gate.CLAIM_ID)
            path.write_text(
                text.replace(block, block.replace(
                    "    resume_eligible: false", "    resume_eligible: true"
                )),
                encoding="utf-8",
            )
            with self.assertRaises(gate.EvidenceError):
                gate.validate(root, check_git_identity=False)
        finally:
            temp.cleanup()

    def test_document_payload_mutation_fails(self):
        temp, root = self._published_fixture()
        try:
            path = root / "docs/en/fpga_implementation.md"
            path.write_text(
                path.read_text(encoding="utf-8").replace(
                    "no Fmax claim", "Fmax was achieved"
                ),
                encoding="utf-8",
            )
            with self.assertRaises(gate.EvidenceError):
                gate.validate(root, check_git_identity=False)
        finally:
            temp.cleanup()

    def test_document_block_position_mutation_fails(self):
        temp, root = self._published_fixture()
        try:
            path = root / "README.en.md"
            text = path.read_text(encoding="utf-8")
            start = text.index(gate.README_START)
            end = text.index(gate.README_END, start) + len(gate.README_END)
            if text[end:end + 1] == "\n":
                end += 1
            block = text[start:end]
            path.write_text(
                block + "\n" + text[:start] + text[end:], encoding="utf-8"
            )
            with self.assertRaises(gate.EvidenceError):
                gate.validate(root, check_git_identity=False)
        finally:
            temp.cleanup()


if __name__ == "__main__":
    unittest.main()
