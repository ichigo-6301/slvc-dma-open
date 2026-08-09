#!/usr/bin/env python3
"""Fail-closed mutations for the branch-only storage clock-gating package."""

from __future__ import print_function

import csv
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from flows.scripts import validate_asic_power_storage_clock_gating_experiment as validator


ROOT = Path(__file__).resolve().parents[2]


class StoragePowerResearchMutationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        shutil.copytree(ROOT / validator.EVIDENCE_REL, self.root / validator.EVIDENCE_REL)
        for relative in (
                "README.md", "README.en.md",
                "docs/en/asic_power_storage_clock_gating_experiment.md",
                "docs/zh-CN/asic_power_storage_clock_gating_experiment.md",
                "provenance/experimental_storage_power_branch.yaml",
                "provenance/claims.yaml", "provenance/evidence.yaml",
                "provenance/nonclaims.yaml"):
            source = ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    def tearDown(self):
        self.temporary.cleanup()

    def evidence_path(self, name):
        return self.root / validator.EVIDENCE_REL / name

    def assert_fails(self, pattern):
        with self.assertRaisesRegex(validator.ValidationError, pattern):
            validator.validate(self.root)

    def mutate_csv(self, name, predicate, field, value):
        path = self.evidence_path(name)
        with path.open("r", encoding="ascii", newline="") as source:
            reader = csv.DictReader(source)
            rows = list(reader)
            fields = reader.fieldnames
        matches = [row for row in rows if predicate(row)]
        self.assertEqual(len(matches), 1, (name, field))
        matches[0][field] = value
        with path.open("w", encoding="ascii", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    def mutate_json(self, relative, callback):
        path = self.root / relative
        data = json.loads(path.read_text(encoding="ascii"))
        callback(data)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="ascii")

    def refresh_package_hashes(self):
        validator.write_package_hashes(self.root)

    def test_unmodified_bundle_passes(self):
        self.assertEqual(validator.validate(self.root), {
            "status": "PASS", "points": 6, "comparisons": 25,
            "categories": 4, "hierarchy": 24, "verification": 6,
            "artifacts": 146, "promotion": "POSITIVE_MAPPED_DC",
        })

    def test_points_numeric_mutation_fails(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "s1_bursty",
            "dynamic_mw", "48")
        self.assert_fails("point dynamic power|fixed mapped result")

    def test_comparison_formula_mutation_fails(self):
        self.mutate_csv(
            "comparisons.csv",
            lambda row: row["comparison_id"] == "bursty_dynamic_mw",
            "delta_percent", "-1")
        self.assert_fails("Decimal-generated")

    def test_source_commit_mismatch_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s0_idle",
            "source_commit", "0" * 40)
        self.assert_fails("fixed identity mismatch")

    def test_prepared_source_hash_mismatch_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s1_idle",
            "source_sha256", "0" * 64)
        self.assert_fails("fixed identity mismatch")

    def test_tool_version_drift_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s0_idle",
            "tool_version", "changed")
        self.assert_fails("fixed identity mismatch")

    def test_library_identity_drift_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s0_idle",
            "library_sha256", "0" * 64)
        self.assert_fails("fixed identity mismatch")

    def test_constraint_identity_drift_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s0_idle",
            "constraint_sha256", "0" * 64)
        self.assert_fails("fixed identity mismatch")

    def test_marker_mutation_fails(self):
        self.mutate_csv(
            "verification.csv", lambda row: row["verification_id"] == "s1_bursty",
            "required_marker", "POWER_C2B4_WORKLOAD_BURSTY_MISSING")
        self.assert_fails("marker is not PASS")

    def test_trace_mismatch_fails(self):
        self.mutate_csv(
            "verification.csv", lambda row: row["verification_id"] == "s1_bursty",
            "trace_sha256", "0" * 64)
        self.assert_fails("hash differs from point|trace identity mismatch")

    def test_annotation_coverage_mutation_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s1_saturated",
            "icg_enable_activity_coverage_pct", "99.9")
        self.assert_fails("annotation audit coverage|fixed ICG-enable")

    def test_icg_count_mutation_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s1_idle",
            "icg_cell_count", "836")
        self.assert_fails("fixed mapped result|clock-gating identity")

    def test_gated_bit_count_mutation_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s1_idle",
            "gated_bit_count", "102975")
        self.assert_fails("fixed mapped result|clock-gating identity")

    def test_category_count_mutation_fails(self):
        self.mutate_csv(
            "category_census.csv", lambda row: row["category"] == "fixed_payload",
            "gated_bits", "65535")
        self.assert_fails("category coverage|category census|sum to gated bits")

    def test_timing_failure_is_rejected(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s1_idle",
            "setup_wns_ns", "-0.001")
        self.assert_fails("point timing is not closed|fixed mapped result")

    def test_electrical_violation_is_rejected(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "s1_idle",
            "electrical_violation_count", "1")
        self.assert_fails("timing/structural/electrical")

    def test_manifest_cannot_recommend_main_merge(self):
        self.mutate_json(
            str(validator.EVIDENCE_REL / "manifest.json"),
            lambda data: data.__setitem__("main_merge_recommended", True))
        self.assert_fails("main_merge_recommended must be False")

    def test_manifest_cannot_claim_postroute_pair(self):
        self.mutate_json(
            str(validator.EVIDENCE_REL / "manifest.json"),
            lambda data: data.__setitem__("postroute_pair_completed", True))
        self.assert_fails("postroute_pair_completed must be False")

    def test_manifest_cannot_claim_lec(self):
        self.mutate_json(
            str(validator.EVIDENCE_REL / "manifest.json"),
            lambda data: data.__setitem__("lec_status", "pass"))
        self.assert_fails("lec_status mismatch")

    def test_quantization_contract_drift_fails(self):
        self.mutate_json(
            str(validator.EVIDENCE_REL / "manifest.json"),
            lambda data: data["report_quantization"].__setitem__(
                "top_power_arithmetic_tolerance_mw", "2"))
        self.assert_fails("report quantization mismatch")

    def test_artifact_hash_removal_fails(self):
        self.mutate_csv(
            "artifacts.csv", lambda row: row["artifact_id"] == "s1__mapped_netlist",
            "sha256", "")
        self.assert_fails("artifact SHA-256")

    def test_raw_eda_payload_is_rejected(self):
        self.evidence_path("raw_power.rpt").write_text(
            "raw commercial report\n", encoding="ascii")
        self.assert_fails("file inventory mismatch")

    def test_sensitive_path_injection_fails(self):
        path = self.evidence_path("README.md")
        path.write_text(
            path.read_text(encoding="utf-8") + "\nD" + ":\\private\\run\n",
            encoding="utf-8")
        self.refresh_package_hashes()
        self.assert_fails("sensitive or private text")

    def test_private_branch_injection_fails(self):
        path = self.evidence_path("README.md")
        path.write_text(
            path.read_text(encoding="utf-8") + "\nperf/hidden-branch\n",
            encoding="utf-8")
        self.refresh_package_hashes()
        self.assert_fails("sensitive or private text")

    def test_missing_document_boundary_fails(self):
        path = self.root / "docs/en/asic_power_storage_clock_gating_experiment.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "not recommended for merge into `main`", "review later"),
            encoding="utf-8")
        self.assert_fails("missing a branch-only result boundary")

    def test_formal_claim_registration_fails(self):
        path = self.root / "provenance/claims.yaml"
        path.write_text(
            path.read_text(encoding="utf-8") +
            "\n# asic_power_clock_gating_storage_positive\n",
            encoding="utf-8")
        self.assert_fails("must not be registered as a formal claim")

    def test_fixed_payload_hashes_are_populated(self):
        self.assertEqual(set(validator.FIXED_CONTENT_SHA256), {
            "README.md", "manifest.json", "points.csv", "category_census.csv",
            "hierarchy_power.csv", "verification.csv", "artifacts.csv",
            "provenance/experimental_storage_power_branch.yaml",
        })

    def test_fixed_payload_hash_blocks_synchronized_edit(self):
        path = self.evidence_path("README.md")
        path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        self.refresh_package_hashes()
        self.assert_fails("fixed published content hash mismatch")

    def test_branch_scope_excludes_production_files(self):
        self.assertNotIn("rtl/rx/dma_axi_write_engine_512.v",
                         validator.ALLOWED_BRANCH_FILES)
        self.assertNotIn("configs/slvc_dma_512_defconfig",
                         validator.ALLOWED_BRANCH_FILES)
        self.assertIn(
            "evidence/asic_power_clock_gating_storage_positive/points.csv",
            validator.ALLOWED_BRANCH_FILES)


if __name__ == "__main__":
    unittest.main()
