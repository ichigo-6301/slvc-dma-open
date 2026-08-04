#!/usr/bin/env python3
"""Fail-closed mutation tests for branch-only power research evidence."""

from __future__ import print_function

import csv
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from flows.scripts import validate_asic_power_clock_gating_experiment as validator


ROOT = Path(__file__).resolve().parents[2]


class PowerResearchMutationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        shutil.copytree(
            ROOT / "evidence/asic_power_clock_gating_negative",
            self.root / "evidence/asic_power_clock_gating_negative",
        )
        for relative in (
            "README.md", "README.en.md",
            "docs/en/asic_power_clock_gating_experiment.md",
            "docs/zh-CN/asic_power_clock_gating_experiment.md",
            "provenance/experimental_power_branch.yaml",
            "provenance/claims.yaml", "provenance/evidence.yaml",
            "provenance/nonclaims.yaml",
        ):
            source = ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    def tearDown(self):
        self.temporary.cleanup()

    def evidence_path(self, name):
        return self.root / "evidence/asic_power_clock_gating_negative" / name

    def assert_fails(self, pattern):
        with self.assertRaisesRegex(validator.EvidenceError, pattern):
            validator.validate(self.root)

    def mutate_csv(self, name, predicate, field, value):
        path = self.evidence_path(name)
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            rows = list(reader)
            fields = reader.fieldnames
        matches = [row for row in rows if predicate(row)]
        self.assertEqual(len(matches), 1, (name, field))
        matches[0][field] = value
        with path.open("w", encoding="utf-8", newline="\n") as output:
            writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    def mutate_json(self, relative, callback):
        path = self.root / relative
        data = json.loads(path.read_text(encoding="utf-8"))
        callback(data)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def refresh_package_hashes(self):
        validator._write_package_hashes(self.root)

    def test_unmodified_bundle_passes(self):
        summary = validator.validate(self.root)
        self.assertEqual(summary, {
            "points": 6, "comparisons": 57, "verification": 12,
            "physical_attempts": 4, "artifacts": 26,
        })

    def test_points_numeric_mutation_fails_recomputed_comparison(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "c2b4_clock_gating_bursty_candidate",
            "dynamic_mw", "390.7",
        )
        self.assert_fails("Decimal recomputation")

    def test_commit_or_source_hash_mismatch_fails(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "c2b4_clock_gating_idle_baseline",
            "source_sha256", "0" * 64,
        )
        self.assert_fails("identity mismatch")

    def test_comparison_formula_mutation_fails(self):
        self.mutate_csv(
            "comparisons.csv",
            lambda row: row["workload_id"] == "bursty" and row["metric"] == "dynamic_mw",
            "delta_percent", "0",
        )
        self.assert_fails("Decimal recomputation")

    def test_manifest_cannot_promote_the_result(self):
        self.mutate_json(
            "evidence/asic_power_clock_gating_negative/manifest.json",
            lambda data: data.__setitem__("promotion_eligible", True),
        )
        self.assert_fails("must be False")

    def test_marker_deletion_fails(self):
        path = self.evidence_path("verification.csv")
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            rows = [row for row in reader if row["verification_id"] != "c2b4_clock_gating_idle_g0_windows_modelsim"]
            fields = reader.fieldnames
        with path.open("w", encoding="utf-8", newline="\n") as output:
            writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        self.assert_fails("twelve records")

    def test_trace_mismatch_fails(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["verification_id"] == "c2b4_clock_gating_bursty_g1_linux_questa",
            "trace_sha256", "0" * 64,
        )
        self.assert_fails("trace identity mismatch")

    def test_g1_icg_count_mutation_fails(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "c2b4_clock_gating_idle_candidate",
            "icg_count", "8",
        )
        self.assert_fails("clock-gating identity mismatch")

    def test_g1_physical_start_is_rejected(self):
        self.mutate_csv(
            "physical_attempts.csv",
            lambda row: row["attempt_id"] == "c2b4_g1_500_openroad",
            "status", "PASS",
        )
        self.assert_fails("physical G1 status mismatch")

    def test_artifact_hash_removal_fails(self):
        self.mutate_csv(
            "physical_artifacts.csv",
            lambda row: row["artifact_id"] == "c2b4_g0_500_openroad__final_metrics",
            "sha256", "",
        )
        self.assert_fails("physical artifact identity mismatch")

    def test_unpublished_raw_report_fails(self):
        self.evidence_path("raw_area.rpt").write_text("raw EDA report\n", encoding="utf-8")
        self.assert_fails("file inventory mismatch")

    def test_sensitive_path_injection_fails(self):
        path = self.evidence_path("README.md")
        injected_path = "D" + ":" + "\\" + "private" + "\\" + "run"
        path.write_text(path.read_text(encoding="utf-8") + "\n" + injected_path + "\n", encoding="utf-8")
        self.refresh_package_hashes()
        self.assert_fails("Windows absolute path")

    def test_missing_document_boundary_fails(self):
        path = self.root / "docs/en/asic_power_clock_gating_experiment.md"
        text = path.read_text(encoding="utf-8")
        path.write_text(text.replace("branch-only", "research-only"), encoding="utf-8")
        self.assert_fails("missing a branch-only negative-result boundary")

    def test_formal_claim_registration_fails(self):
        path = self.root / "provenance/claims.yaml"
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\n# asic_power_clock_gating_negative must remain branch-only\n",
            encoding="utf-8",
        )
        self.assert_fails("must not be registered as a formal claim")

    def test_fixed_content_hash_blocks_synchronized_payload_edit(self):
        path = self.evidence_path("physical_artifacts.csv")
        text = path.read_text(encoding="utf-8")
        path.write_text(text.replace("not_distributed", "not_distributed", 1) + "\n", encoding="utf-8")
        self.refresh_package_hashes()
        self.assert_fails("fixed published content hash mismatch")

    def test_branch_scope_does_not_allow_rtl_or_profiles(self):
        self.assertNotIn("rtl/rx/dma_axi_write_engine_512.v", validator.ALLOWED_BRANCH_FILES)
        self.assertNotIn("configs/slvc_dma_512_defconfig", validator.ALLOWED_BRANCH_FILES)
        self.assertIn("evidence/asic_power_clock_gating_negative/points.csv", validator.ALLOWED_BRANCH_FILES)


if __name__ == "__main__":
    unittest.main()
