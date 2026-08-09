#!/usr/bin/env python3
"""Fail-closed tests for deterministic DMA showcase assets and navigation."""

import json
from pathlib import Path
import shutil
import tempfile
import unittest

from flows.scripts import generate_showcase_assets as generator


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class ShowcaseAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        inputs = (
            generator.COMPARISONS_PATH,
            generator.CLAIMS_PATH,
            generator.C2B4_EVIDENCE_PATH,
            generator.CDC_EVIDENCE_PATH,
            generator.WRAPPER_PATH,
            generator.FRAME_WRAPPER_PATH,
            generator.RX_TOP_PATH,
            generator.C2B4_PROFILE_PATH,
            generator.GENERATOR_PATH,
            generator.README_PATH,
            generator.README_EN_PATH,
            generator.RESEARCH_PATH,
            generator.RESEARCH_EN_PATH,
        ) + generator.AUTHORED_ASSETS
        for relative in inputs:
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

    def reset_file(self, relative):
        shutil.copyfile(REPOSITORY_ROOT / relative, self.root / relative)

    def test_tracked_assets_and_navigation_are_fresh(self):
        generator.check(REPOSITORY_ROOT)

    def test_generated_copy_passes_with_exact_metrics(self):
        metrics = generator.check(self.root)
        self.assertEqual(str(metrics["writer_total"]), "-7.97")
        self.assertEqual(str(metrics["writer_comb"]), "-15.84")
        self.assertEqual(metrics["wide_bytes"], 64)
        self.assertEqual(metrics["w_utilization"], 100)
        self.assertEqual(metrics["peak_outstanding"], 4)
        self.assertEqual((metrics["dc_mhz"], metrics["route_mhz"]), (550, 450))

    def test_repeated_generation_is_byte_identical(self):
        tracked = generator.GENERATED_ASSETS + (generator.ASSET_MANIFEST_PATH,)
        before = {path: (self.root / path).read_bytes() for path in tracked}
        generator.write(self.root)
        after = {path: (self.root / path).read_bytes() for path in tracked}
        self.assertEqual(before, after)

    def test_writer_csv_delta_drift_fails(self):
        self.replace_text(generator.COMPARISONS_PATH, "-7.966353", "-7.900000")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "formula mismatch"):
            generator.check(self.root)

    def test_writer_csv_formula_input_drift_fails(self):
        self.replace_text(generator.COMPARISONS_PATH, "7526.204", "7526.205")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "formula mismatch"):
            generator.check(self.root)

    def test_required_claim_removal_fails(self):
        self.replace_text(
            generator.CLAIMS_PATH,
            "  - id: " + generator.THROUGHPUT_CLAIM,
            "  - id: removed_throughput_claim",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "missing required claim"):
            generator.check(self.root)

    def test_duplicate_claim_id_fails(self):
        path = self.root / generator.CLAIMS_PATH
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\n  - id: {}\n    status: verified\n".format(generator.WRITER_CLAIM),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "duplicate claim"):
            generator.check(self.root)

    def test_claim_scope_and_caveat_drift_fail(self):
        mutations = (
            (generator.WRITER_SCOPE["profile"], "complete_dma_profile"),
            (generator.WRITER_SCOPE["benchmark"], "complete DMA W0 versus W1"),
            (generator.THROUGHPUT_SCOPE["caveat"], "Measured board DDR throughput."),
            (generator.C2B4_SCOPE["source_ref"], "f" * 40),
        )
        for old, new in mutations:
            with self.subTest(new=new):
                self.reset_file(generator.CLAIMS_PATH)
                self.replace_text(generator.CLAIMS_PATH, old, new)
                with self.assertRaisesRegex(generator.ShowcaseAssetError, "scope identity"):
                    generator.check(self.root)

    def test_throughput_evidence_drift_fails(self):
        self.replace_text(generator.CDC_EVIDENCE_PATH, "bytes_per_cycle: 64", "bytes_per_cycle: 63")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "throughput evidence mismatch"):
            generator.check(self.root)

    def test_c2b4_evidence_drift_fails(self):
        self.replace_text(generator.C2B4_EVIDENCE_PATH, "setup_wns_ns: 0.041322", "setup_wns_ns: 0.040000")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "timing or area evidence mismatch"):
            generator.check(self.root)

    def test_rtl_and_profile_identity_drift_fail(self):
        mutations = (
            (generator.RX_TOP_PATH, "dma_rx_payload_cdc_bridge", "removed_cdc_bridge"),
            (generator.C2B4_PROFILE_PATH, "memory_axi_width: 512", "memory_axi_width: 256"),
        )
        for path, old, new in mutations:
            with self.subTest(path=path):
                self.reset_file(path)
                self.replace_text(path, old, new)
                with self.assertRaisesRegex(generator.ShowcaseAssetError, "architecture token"):
                    generator.check(self.root)

    def test_generated_svg_tamper_fails(self):
        path = self.root / generator.PPA_ASSET
        path.write_bytes(path.read_bytes() + b"<!-- tampered -->\n")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "stale showcase assets"):
            generator.check(self.root)

    def test_manifest_tamper_fails(self):
        path = self.root / generator.ASSET_MANIFEST_PATH
        data = json.loads(path.read_text(encoding="utf-8"))
        data["assets"][-1]["sha256"] = "0" * 64
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "manifest is stale"):
            generator.check(self.root)

    def test_obsolete_asset_reappearance_fails(self):
        path = self.root / generator.OBSOLETE_ASSETS[0]
        path.write_text("obsolete\n", encoding="utf-8")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "stale showcase assets"):
            generator.check(self.root)

    def test_authored_svg_external_resource_fails(self):
        path = generator.AUTHORED_ASSETS[0]
        self.replace_text(path, "</svg>", '<image href="https://example.com/x.png"/></svg>')
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "forbidden SVG content"):
            generator.check(self.root)

    def test_authored_svg_private_path_fails(self):
        path = generator.AUTHORED_ASSETS[0]
        self.replace_text(path, "</svg>", "<text>C:\\private\\asset</text></svg>")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "forbidden SVG content"):
            generator.check(self.root)

    def test_authored_svg_gradient_fails(self):
        path = generator.AUTHORED_ASSETS[0]
        self.replace_text(path, "</svg>", '<linearGradient id="g"/></svg>')
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "forbidden SVG content"):
            generator.check(self.root)

    def test_readme_asset_reference_deletion_fails(self):
        self.replace_text(
            generator.README_PATH,
            "({})".format(generator.MEMORY_PROFILES_ASSET.as_posix()),
            "(docs/assets/missing.svg)",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "must reference"):
            generator.check(self.root)

    def test_readme_anchor_deletion_fails(self):
        self.replace_text(
            generator.README_EN_PATH,
            '<a id="memory-profiles-and-cdc"></a>',
            '<a id="memory-profiles-and-cdc-removed"></a>',
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "must contain anchor"):
            generator.check(self.root)

    def test_readme_claim_marker_mismatch_fails(self):
        self.replace_text(
            generator.README_EN_PATH,
            generator.WRITER_CLAIM,
            "wrong_writer_claim",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "claim marker parity"):
            generator.check(self.root)

    def test_research_commit_drift_fails(self):
        self.replace_text(generator.RESEARCH_PATH, generator.RESEARCH_COMMIT, "0" * 40)
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "fixed-commit identity"):
            generator.check(self.root)

    def test_research_power_metric_injection_fails(self):
        path = self.root / generator.RESEARCH_EN_PATH
        path.write_text(path.read_text(encoding="utf-8") + "\nBursty: -87.91%\n", encoding="utf-8")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "must not publish"):
            generator.check(self.root)


if __name__ == "__main__":
    unittest.main()
