#!/usr/bin/env python3
"""Fail-closed tests for the results-at-a-glance asset generator."""

import csv
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from flows.scripts import generate_results_at_a_glance as generator


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class ResultsAtAGlanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for relative in (
                generator.COMPARISONS_PATH,
                generator.CLAIMS_PATH,
                generator.GENERATOR_PATH,
                generator.ASSET_MANIFEST_PATH):
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPOSITORY_ROOT / relative, destination)
        generator.write(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def replace_text(self, relative, old, new):
        path = self.root / relative
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def test_tracked_asset_is_fresh(self):
        generator.check(REPOSITORY_ROOT)

    def test_generated_copy_passes(self):
        metrics = generator.check(self.root)
        self.assertEqual(metrics["bytes_per_cycle"], 64)
        self.assertEqual(str(metrics["writer_total"]), "-7.97")

    def test_writer_csv_drift_fails(self):
        self.replace_text(
            generator.COMPARISONS_PATH, "-7.966353", "-7.900000"
        )
        with self.assertRaisesRegex(generator.ResultsAssetError, "formula mismatch"):
            generator.check(self.root)

    def test_writer_csv_formula_input_drift_fails(self):
        self.replace_text(
            generator.COMPARISONS_PATH, "7526.204", "7526.205"
        )
        with self.assertRaisesRegex(generator.ResultsAssetError, "formula mismatch"):
            generator.check(self.root)

    def test_required_claim_removal_fails(self):
        self.replace_text(
            generator.CLAIMS_PATH,
            "  - id: " + generator.THROUGHPUT_CLAIM,
            "  - id: removed_throughput_claim",
        )
        with self.assertRaisesRegex(generator.ResultsAssetError, "missing required claim"):
            generator.check(self.root)

    def test_duplicate_claim_id_fails(self):
        path = self.root / generator.CLAIMS_PATH
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text + "\n  - id: {}\n    status: verified\n".format(
                generator.WRITER_CLAIM
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(generator.ResultsAssetError, "duplicate claim"):
            generator.check(self.root)

    def test_ideal_memory_caveat_deletion_fails(self):
        self.replace_text(
            generator.CLAIMS_PATH,
            generator.THROUGHPUT_CAVEAT,
            "",
        )
        with self.assertRaisesRegex(generator.ResultsAssetError, "scope identity"):
            generator.check(self.root)

    def test_claim_scope_identity_drift_fails_write(self):
        mutations = (
            (
                generator.WRITER_SCOPE["profile"],
                "dma_rx512_reg_c2_b4_m2_sp64",
            ),
            (
                generator.WRITER_SCOPE["benchmark"],
                "complete DMA W0 versus W1",
            ),
            (
                generator.WRITER_SCOPE["configuration"],
                "different parameters and constraints",
            ),
            (
                generator.WRITER_SCOPE["tool"],
                "another synthesis tool",
            ),
            (
                generator.WRITER_SCOPE["source_ref"],
                "0" * 40,
            ),
            (
                generator.WRITER_SCOPE["evidence"][0],
                "different_evidence_record",
            ),
            (
                generator.THROUGHPUT_SCOPE["statement"],
                "A board test sustained one AXI W beat per clock.",
            ),
            (
                generator.THROUGHPUT_SCOPE["benchmark"],
                "board DDR measurement",
            ),
            (
                generator.C2B4_SCOPE["source_ref"],
                "f" * 40,
            ),
            (
                generator.C2B4_SCOPE["tool"],
                "unrelated physical implementation flow",
            ),
            (
                generator.C2B4_SCOPE["evidence"][0],
                "different_c2b4_evidence_record",
            ),
        )
        for old, new in mutations:
            with self.subTest(new=new):
                shutil.copyfile(
                    REPOSITORY_ROOT / generator.CLAIMS_PATH,
                    self.root / generator.CLAIMS_PATH,
                )
                self.replace_text(generator.CLAIMS_PATH, old, new)
                with self.assertRaisesRegex(
                        generator.ResultsAssetError, "scope identity"):
                    generator.write(self.root)

    def test_c2b4_scope_or_frequency_drift_fails(self):
        mutations = (
            (generator.C2B4_CAVEAT, "This is complete-DMA signoff."),
            ("550 MHz Design Compiler", "600 MHz Design Compiler"),
        )
        for old, new in mutations:
            with self.subTest(new=new):
                shutil.copyfile(
                    REPOSITORY_ROOT / generator.CLAIMS_PATH,
                    self.root / generator.CLAIMS_PATH,
                )
                self.replace_text(generator.CLAIMS_PATH, old, new)
                with self.assertRaises(generator.ResultsAssetError):
                    generator.write(self.root)

    def test_svg_tamper_fails(self):
        path = self.root / generator.ASSET_PATH
        path.write_bytes(path.read_bytes() + b"<!-- tampered -->\n")
        with self.assertRaisesRegex(generator.ResultsAssetError, "SVG is stale"):
            generator.check(self.root)

    def test_manifest_tamper_fails(self):
        path = self.root / generator.ASSET_MANIFEST_PATH
        data = json.loads(path.read_text(encoding="utf-8"))
        for entry in data["assets"]:
            if entry["path"] == generator.ASSET_PATH.as_posix():
                entry["sha256"] = "0" * 64
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(generator.ResultsAssetError, "manifest entry is stale"):
            generator.check(self.root)


if __name__ == "__main__":
    unittest.main()
