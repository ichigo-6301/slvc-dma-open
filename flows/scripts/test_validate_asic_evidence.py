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
            "asic_paired_dc_publication.yaml", "checksums.sha256", "claims.yaml",
            "evidence.yaml"
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

    def filter_csv(self, name, keep):
        path = self.csv_path(name)
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.DictReader(source)
            fields = reader.fieldnames
            rows = [row for row in reader if keep(row)]
        with path.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    def mutate_manifest(self, callback):
        path = self.csv_path("manifest.yaml")
        data = json.loads(path.read_text(encoding="utf-8"))
        callback(data)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    def replace_provenance(self, name, old, new):
        path = self.root / "provenance" / name
        text = path.read_text(encoding="utf-8")
        self.assertGreaterEqual(text.count(old), 1, (name, old))
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

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
        self.assert_fails("fixed claim value mismatch")

    def test_commit_mapping_mismatch_fails(self):
        self.mutate_csv(
            "sources.csv",
            lambda row: row["evaluation_id"] == "writer_component"
            and row["point_id"] == "writer_component_w0",
            "source_commit", "0" * 40,
        )
        self.assert_fails("fixed source inventory mismatch")

    def test_source_hash_cross_reference_mismatch_fails(self):
        self.mutate_csv(
            "sources.csv",
            lambda row: row["evaluation_id"] == "writer_component"
            and row["point_id"] == "writer_component_w0",
            "sha256", "0" * 64,
        )
        self.assert_fails("fixed source inventory mismatch")

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

    def test_manifest_and_points_identity_drift_together_fails(self):
        def mutate(data):
            data["evaluations"][0]["top"] = "different_top"
            data["evaluations"][0]["parameters"] = "MAX_BURST_BEATS=8;MAX_OUTSTANDING=4"
        self.mutate_manifest(mutate)
        for point_id in ("writer_component_w0", "writer_component_w1"):
            self.mutate_csv(
                "points.csv", lambda row, point_id=point_id: row["point_id"] == point_id,
                "top", "different_top",
            )
            self.mutate_csv(
                "points.csv", lambda row, point_id=point_id: row["point_id"] == point_id,
                "parameters", "MAX_BURST_BEATS=8;MAX_OUTSTANDING=4",
            )
        self.assert_fails("fixed top mismatch")

    def test_private_evidence_commit_cannot_drift_with_publication(self):
        replacement = "0" * 40
        def mutate(data):
            data["evaluations"][0]["private_evidence_commit"] = replacement
        self.mutate_manifest(mutate)
        publication = self.root / "provenance/asic_paired_dc_publication.yaml"
        data = json.loads(publication.read_text(encoding="utf-8"))
        data["fixed_evidence_commits"][0] = replacement
        publication.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        self.replace_provenance(
            "claims.yaml", validator.EXPECTED_EVALUATIONS["writer_component"]["private_evidence_commit"],
            replacement,
        )
        self.assert_fails("fixed private_evidence_commit mismatch")

    def test_c2b4_common_source_inventory_is_required(self):
        self.filter_csv(
            "sources.csv",
            lambda row: not (
                row["evaluation_id"] == "c2b4_writer" and row["scope"] == "common"
            ),
        )
        self.assert_fails("fixed source inventory mismatch")

    def test_required_marker_deletion_fails(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "c2b4_writer_w0"
            and row["platform"] == "windows" and row["suite_id"] == "writer_2028",
            "required_markers", "PASS tb_rtl_rx_payload_writer_512 cases=2028",
        )
        self.assert_fails("canonical required markers mismatch")

    def test_empty_required_markers_fail(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "shared_pool_p6"
            and row["platform"] == "linux",
            "required_markers", "",
        )
        self.assert_fails("canonical required markers mismatch")

    def test_same_count_wrong_marker_text_fails(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "c2b4_writer_w1"
            and row["platform"] == "linux" and row["suite_id"] == "writer_2028",
            "required_markers",
            "PASS tb_rtl_rx_payload_writer_512 cases=2027|"
            "WIDE512_THROUGHPUT bytes_per_cycle_x1000=64000",
        )
        self.assert_fails("canonical required markers mismatch")

    def test_marker_order_swap_fails(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "shared_pool_p7"
            and row["platform"] == "linux",
            "required_markers",
            "OK: dma RTL v33e19 shared frame pool test passed.|"
            "E19_CASE T0 reset_init|E19_CASE T1 single_frame|"
            "E19_CASE T2 back_to_back|E19_CASE T3 multi_channel|"
            "E19_CASE T4 pool_full_nodrop|E19_CASE T5 pool_full_drop|"
            "E19_CASE T6 oversized_drop|E19_CASE T7 drain_stall|"
            "E19_CASE T8 reset_recovery",
        )
        self.assert_fails("canonical required markers mismatch")

    def test_wrong_simulator_identity_fails(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "shared_pool_p7"
            and row["platform"] == "windows",
            "tool_version", "Questa Sim-64 10.7c",
        )
        self.assert_fails("simulator identity mismatch")

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

    def test_comparison_metric_removal_fails(self):
        def mutate(data):
            data["evaluations"][0]["comparison_metrics"].pop()
        self.mutate_manifest(mutate)
        self.assert_fails("fixed comparison metrics mismatch")

    def test_required_artifact_removal_fails(self):
        def mutate(data):
            data["evaluations"][2]["required_artifacts"].pop()
        self.mutate_manifest(mutate)
        self.assert_fails("fixed artifact list mismatch")

    def test_negative_setup_wns_fails(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "writer_component_w0",
            "setup_wns_ns", "-0.000001",
        )
        self.assert_fails("negative setup WNS")

    def test_negative_hold_wns_fails(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "shared_pool_p6",
            "hold_wns_ns", "-0.000001",
        )
        self.assert_fails("negative hold WNS")

    def test_nonzero_setup_tns_fails(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "shared_pool_p7",
            "setup_tns_ns", "-0.000001",
        )
        self.assert_fails("nonzero setup TNS")

    def test_negative_writer_setup_wns_fails(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "c2b4_writer_w0",
            "writer_setup_wns_ns", "-0.000001",
        )
        self.assert_fails("negative writer_setup_wns_ns")

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

    def test_negative_lint_warning_count_fails(self):
        self.mutate_csv(
            "lint.csv", lambda row: row["point_id"] == "shared_pool_p6",
            "warning_count", "-1",
        )
        self.assert_fails("lint counts must be nonnegative")

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

    def test_nested_uninventoried_payload_fails(self):
        nested = self.csv_path("nested/raw/report.txt")
        nested.parent.mkdir(parents=True)
        nested.write_text("not inventoried\n", encoding="utf-8")
        self.assert_fails("publication payload file set mismatch")

    def test_nested_payload_fails_even_when_inventoried(self):
        nested = self.csv_path("nested/note.txt")
        nested.parent.mkdir(parents=True)
        nested.write_text("inventoried but forbidden\n", encoding="utf-8")
        publication = self.root / "provenance/asic_paired_dc_publication.yaml"
        data = json.loads(publication.read_text(encoding="utf-8"))
        data["files"]["evidence/asic_paired_dc/nested/note.txt"] = validator._sha256(nested)
        publication.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        self.assert_fails("publication payload file set mismatch")

    def test_duplicate_provenance_claims_field_fails(self):
        self.replace_provenance(
            "evidence.yaml",
            "    claims:\n      - slvc_dma_writer_reservation_component_paired_dc",
            "    claims:\n      - slvc_dma_writer_reservation_component_paired_dc\n"
            "    claims:\n      - slvc_dma_writer_reservation_component_paired_dc",
        )
        self.assert_fails("has no claims list")

    def test_duplicate_provenance_path_field_fails(self):
        self.replace_provenance(
            "evidence.yaml",
            "    path: provenance/asic_paired_dc_publication.yaml",
            "    path: provenance/asic_paired_dc_publication.yaml\n"
            "    path: provenance/asic_paired_dc_publication.yaml",
        )
        self.assert_fails("invalid path field")

    def test_claim_evidence_misbinding_fails(self):
        self.replace_provenance(
            "claims.yaml",
            "      - slvc_dma_asic_paired_dc_publication\n    status: verified",
            "      - slvc_dma_async64_vivado_2022_2_ooc_summary\n    status: verified",
        )
        self.assert_fails("claims are not bound")

    def test_claim_source_ref_must_match_fixed_evidence_commit(self):
        self.replace_provenance(
            "claims.yaml",
            "    source_ref: adbc36aa92c6fee11253fbae31ec77216dae91cc",
            "    source_ref: " + "0" * 40,
        )
        self.assert_fails("source_ref does not match fixed evidence commit")

    def test_claim_statement_numbers_are_fixed(self):
        self.replace_provenance(
            "claims.yaml", "reduced Writer total cell area by 7.966353 percent",
            "reduced Writer total cell area by 6.991626 percent",
        )
        self.assert_fails("fixed statement mismatch")

    def test_paired_claim_must_remain_verified(self):
        self.replace_provenance(
            "claims.yaml", "    status: verified", "    status: rejected",
        )
        self.assert_fails("must remain verified")

    def test_paired_claim_must_remain_public(self):
        self.replace_provenance(
            "claims.yaml", "    public: true", "    public: false",
        )
        self.assert_fails("must remain public")

    def test_publication_evidence_claim_misbinding_fails(self):
        self.replace_provenance(
            "evidence.yaml",
            "      - slvc_dma_shared_pool_scheduler_paired_dc",
            "      - slvc_dma_async64_vivado_2022_2_ooc_200m",
        )
        self.assert_fails("publication evidence claim mapping mismatch")

    def test_wrong_provenance_publication_path_fails(self):
        self.replace_provenance(
            "evidence.yaml",
            "    path: provenance/asic_paired_dc_publication.yaml",
            "    path: evidence/asic_paired_dc/manifest.yaml",
        )
        self.assert_fails("must bind the publication manifest")

    def test_wrong_provenance_publication_hash_fails(self):
        self.replace_provenance(
            "evidence.yaml",
            "    sha256: 21357df385e5752c375f9b9c2bf6a39438761a92b601c4d4e57af709f6ba6743",
            "    sha256: " + "0" * 64,
        )
        self.assert_fails("must bind the publication manifest")

    def test_private_path_injection_fails(self):
        def mutate(data):
            data["evaluations"][0]["nonclaims"].append(
                "internal archive D:\\private\\run"
            )
        self.mutate_manifest(mutate)
        self.assert_fails("Windows absolute path")

    def test_arbitrary_posix_absolute_path_injection_fails(self):
        def mutate(data):
            data["evaluations"][0]["nonclaims"].append(
                "internal archive /root/private/customer/design.v"
            )
        self.mutate_manifest(mutate)
        self.assert_fails("POSIX absolute path")

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

    def test_write_mode_refreshes_complete_digest_chain(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "writer_component_w1",
            "leaf_cell_count", "3048",
        )
        validator.validate(self.root, write_comparisons=True)
        validator.validate(self.root)
        publication = json.loads(
            (self.root / "provenance/asic_paired_dc_publication.yaml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            publication["files"]["evidence/asic_paired_dc/points.csv"],
            validator._sha256(self.csv_path("points.csv")),
        )
        self.assertEqual(
            publication["files"]["evidence/asic_paired_dc/comparisons.csv"],
            validator._sha256(self.csv_path("comparisons.csv")),
        )
        checksum_rows = {}
        for line in (self.root / "provenance/checksums.sha256").read_text(
            encoding="utf-8"
        ).splitlines():
            digest, relative = line.split("  ", 1)
            checksum_rows[relative] = digest
        for relative in (
            "evidence/asic_paired_dc/points.csv",
            "evidence/asic_paired_dc/comparisons.csv",
            "provenance/asic_paired_dc_publication.yaml",
            "provenance/evidence.yaml",
        ):
            self.assertEqual(
                checksum_rows[relative], validator._sha256(self.root / relative)
            )


if __name__ == "__main__":
    unittest.main()
