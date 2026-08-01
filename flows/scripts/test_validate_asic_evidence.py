#!/usr/bin/env python3
"""Mutation contracts for the public ASIC paired-DC evidence validator."""

from __future__ import print_function

import csv
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from flows.scripts import validate_asic_evidence as validator


ROOT = Path(__file__).resolve().parents[2]


class AsicEvidenceMutationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        target = self.root / "evidence/asic_paired_dc"
        target.parent.mkdir(parents=True)
        shutil.copytree(ROOT / "evidence/asic_paired_dc", target)
        provenance = self.root / "provenance"
        provenance.mkdir()
        for name in (
            "asic_paired_dc_publication.yaml", "claims.yaml", "evidence.yaml"
        ):
            shutil.copy2(ROOT / "provenance" / name, provenance / name)

    def tearDown(self):
        self.temporary.cleanup()

    def csv_path(self, name):
        return self.root / "evidence/asic_paired_dc" / name

    def mutate_csv(self, name, predicate, field, value):
        path = self.csv_path(name)
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            fields = reader.fieldnames
            rows = list(reader)
        matches = [row for row in rows if predicate(row)]
        self.assertEqual(len(matches), 1, (name, field))
        matches[0][field] = value
        with path.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    def mutate_manifest(self, callback):
        path = self.csv_path("manifest.yaml")
        data = json.loads(path.read_text(encoding="utf-8"))
        callback(data)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def assert_fails(self, pattern):
        with self.assertRaisesRegex(validator.EvidenceError, pattern):
            validator.validate(self.root)

    def test_unmodified_bundle_passes(self):
        summary = validator.validate(self.root)
        self.assertEqual(summary["evaluations"], 3)
        self.assertEqual(summary["points"], 7)
        self.assertEqual(summary["comparisons"], 18)

    def test_csv_numeric_mutation_invalidates_generated_comparison(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "writer_component_w1",
            "total_cell_area", "6926.641",
        )
        self.assert_fails("Decimal recomputation")

    def test_commit_mapping_mismatch_fails(self):
        self.mutate_csv(
            "sources.csv",
            lambda row: row["evaluation_id"] == "writer_component"
            and row["point_id"] == "writer_component_w0",
            "source_commit", "0" * 40,
        )
        self.assert_fails("commit/source mapping mismatch")

    def test_source_hash_cross_reference_mismatch_fails(self):
        self.mutate_csv(
            "sources.csv",
            lambda row: row["evaluation_id"] == "writer_component"
            and row["point_id"] == "writer_component_w0",
            "sha256", "0" * 64,
        )
        self.assert_fails("source hash mismatch")

    def test_pair_identity_drift_fails(self):
        mutations = {
            "top": "different_top",
            "parameters": "MAX_BURST_BEATS=8;MAX_OUTSTANDING=4",
            "constraint_id": "different_constraint",
            "tool_version": "different_tool",
            "library_sha256": "0" * 64,
        }
        for field, value in mutations.items():
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as directory:
                    nested = Path(directory)
                    shutil.copytree(
                        self.root / "evidence", nested / "evidence"
                    )
                    original_root = self.root
                    self.root = nested
                    try:
                        self.mutate_csv(
                            "points.csv",
                            lambda row: row["point_id"] == "writer_component_w1",
                            field, value,
                        )
                        with self.assertRaises(validator.EvidenceError):
                            validator.validate(self.root)
                    finally:
                        self.root = original_root

    def test_required_marker_deletion_fails(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "c2b4_writer_w0"
            and row["platform"] == "windows" and row["suite_id"] == "writer_2028",
            "required_markers", "PASS tb_rtl_rx_payload_writer_512 cases=2028",
        )
        self.assert_fails("marker count mismatch")

    def test_semantic_trace_mismatch_fails(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "c2b4_writer_w0"
            and row["platform"] == "linux" and row["suite_id"] == "writer_2028",
            "semantic_trace_sha256", "0" * 64,
        )
        self.assert_fails("semantic trace mismatch")

    def test_claim_id_reuse_fails(self):
        def mutate(data):
            data["evaluations"][1]["claim_id"] = data["evaluations"][0]["claim_id"]
        self.mutate_manifest(mutate)
        self.assert_fails("claim ID reused")

    def test_c2b4_lint_cannot_be_disguised_as_pass(self):
        self.mutate_csv(
            "lint.csv",
            lambda row: row["scope"] == "full_c2b4_common",
            "status", "PASS_WITH_REVIEWED_WARNINGS",
        )
        self.assert_fails("C2B4 lint boundary")

    def test_nonzero_lint_waiver_fails(self):
        self.mutate_csv(
            "lint.csv",
            lambda row: row["point_id"] == "c2b4_writer_w1",
            "waived_count", "1",
        )
        self.assert_fails("waivers are not permitted")

    def test_missing_report_hash_fails(self):
        self.mutate_csv(
            "artifacts.csv",
            lambda row: row["point_id"] == "shared_pool_p7"
            and row["logical_name"] == "area",
            "sha256", "",
        )
        self.assert_fails("artifact hash")

    def test_publication_file_hash_mismatch_fails(self):
        publication = self.root / "provenance/asic_paired_dc_publication.yaml"
        data = json.loads(publication.read_text(encoding="utf-8"))
        data["files"]["evidence/asic_paired_dc/points.csv"] = "0" * 64
        publication.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        self.assert_fails("publication hash mismatch")

    def test_private_path_injection_fails(self):
        def mutate(data):
            data["evaluations"][0]["nonclaims"].append(
                "internal archive D:\\private\\run"
            )
        self.mutate_manifest(mutate)
        self.assert_fails("Windows absolute path")

    def test_comparison_formula_mutation_fails(self):
        self.mutate_csv(
            "comparisons.csv",
            lambda row: row["evaluation_id"] == "shared_pool_scheduler"
            and row["metric"] == "setup_wns_ns",
            "delta", "0.0077",
        )
        self.assert_fails("Decimal recomputation")

    def test_raw_commercial_artifact_fails(self):
        self.csv_path("private.rpt").write_text("raw report\n", encoding="utf-8")
        self.assert_fails("raw EDA artifact")

    def test_write_mode_restores_canonical_comparisons(self):
        self.mutate_csv(
            "comparisons.csv",
            lambda row: row["evaluation_id"] == "writer_component"
            and row["metric"] == "total_cell_area",
            "delta_percent", "0",
        )
        validator.validate(self.root, write_comparisons=True)
        validator.validate(self.root)


if __name__ == "__main__":
    unittest.main()
