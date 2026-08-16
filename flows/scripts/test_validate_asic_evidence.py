#!/usr/bin/env python3
"""Mutation contracts for the public ASIC paired-DC evidence validator."""

from __future__ import print_function

import csv
import json
import shutil
import tempfile
import unittest
from unittest import mock
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
            "evidence.yaml", "nonclaims.yaml"
        ):
            shutil.copy2(ROOT / "provenance" / name, provenance / name)
        shutil.copy2(ROOT / "provenance/README.md", provenance / "README.md")
        for relative in validator.EXPECTED_DOC_SHA256:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)

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

    def test_nonclaim_point_metric_cannot_drift(self):
        self.mutate_csv(
            "points.csv",
            lambda row: row["point_id"] == "writer_component_w1",
            "hold_wns_ns", "99",
        )
        self.assert_fails("fixed points numeric authority")

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

    def test_numeric_constraint_tuple_drift_together_fails(self):
        mutations = {
            "clock_period_ns": "2.0", "setup_uncertainty_ns": "0.3",
            "hold_uncertainty_ns": "0.1", "io_delay_ns": "0.6",
            "input_transition_ns": "0.2", "output_load": "0.1",
            "max_fanout": "32", "max_transition_ns": "0.6",
        }
        for field, value in mutations.items():
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as directory:
                    nested = Path(directory) / "repo"
                    shutil.copytree(self.root, nested)
                    original_root = self.root
                    self.root = nested
                    try:
                        for point_id in (
                            "writer_component_w0", "writer_component_w1"
                        ):
                            self.mutate_csv(
                                "points.csv",
                                lambda row, point_id=point_id: (
                                    row["point_id"] == point_id
                                ),
                                field, value,
                            )
                        self.assert_fails("fixed numeric constraint mismatch")
                    finally:
                        self.root = original_root

    def test_manifest_claim_boundaries_are_fixed(self):
        mutations = {
            "claim_scope": "complete-DMA signoff",
            "nonclaims": [],
            "canary_classification": "METHODOLOGY_IDENTICAL_REPRODUCTION",
        }
        for field, value in mutations.items():
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as directory:
                    nested = Path(directory) / "repo"
                    shutil.copytree(self.root, nested)
                    original_root = self.root
                    self.root = nested
                    try:
                        def mutate(data):
                            index = 1 if field == "canary_classification" else 0
                            data["evaluations"][index][field] = value
                        self.mutate_manifest(mutate)
                        self.assert_fails("fixed {} mismatch".format(field))
                    finally:
                        self.root = original_root

    def test_manifest_unknown_field_fails(self):
        self.mutate_manifest(
            lambda data: data.__setitem__("complete_dma_signoff", "verified")
        )
        self.assert_fails("manifest field set mismatch")

    def test_evaluation_unknown_field_fails(self):
        def mutate(data):
            data["evaluations"][0]["complete_dma_signoff"] = "verified"
        self.mutate_manifest(mutate)
        self.assert_fails("writer_component manifest field set mismatch")

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

    def test_verification_digest_inventory_is_fixed(self):
        self.mutate_csv(
            "verification.csv",
            lambda row: row["point_id"] == "c2b4_writer_w0"
            and row["platform"] == "windows"
            and row["suite_id"] == "writer_2028",
            "log_sha256", "0" * 64,
        )
        self.assert_fails("fixed verification digest inventory")

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

    def test_negative_physical_area_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "c2b4_writer_w0",
            "noncombinational_area", "-1",
        )
        self.assert_fails("negative physical metric")

    def test_negative_physical_count_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "c2b4_writer_w0",
            "writer_leaf_count", "-1",
        )
        self.assert_fails("negative physical metric")

    def test_fractional_physical_count_fails(self):
        self.mutate_csv(
            "points.csv", lambda row: row["point_id"] == "c2b4_writer_w0",
            "writer_leaf_count", "100.5",
        )
        self.assert_fails("non-integral count")

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

    def test_bounded_lint_inventory_is_fixed(self):
        self.mutate_csv(
            "lint.csv",
            lambda row: row["point_id"] == "c2b4_writer_w0",
            "warning_count", "0",
        )
        self.assert_fails("fixed bounded-lint evidence inventory")

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

    def test_commercial_report_digest_inventory_is_fixed(self):
        self.mutate_csv(
            "artifacts.csv",
            lambda row: row["point_id"] == "writer_component_w0"
            and row["logical_name"] == "area",
            "sha256", "0" * 64,
        )
        self.assert_fails("fixed commercial-report digest inventory")

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
        self.assert_fails("field set mismatch")

    def test_duplicate_provenance_path_field_fails(self):
        self.replace_provenance(
            "evidence.yaml",
            "    path: provenance/asic_paired_dc_publication.yaml",
            "    path: provenance/asic_paired_dc_publication.yaml\n"
            "    path: provenance/asic_paired_dc_publication.yaml",
        )
        self.assert_fails("field set mismatch")

    def test_claim_evidence_misbinding_fails(self):
        self.replace_provenance(
            "claims.yaml",
            "      - slvc_dma_asic_paired_dc_publication\n    status: verified",
            "      - slvc_dma_async64_vivado_2022_2_ooc_summary\n    status: verified",
        )
        self.assert_fails("claim binding")

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

    def test_claim_identity_metadata_is_fixed(self):
        mutations = {
            "benchmark": "different benchmark",
            "configuration": "\"different configuration\"",
            "tool": "Vivado 2022.2",
            "caveat": "\"scope caveat removed\"",
        }
        for field, value in mutations.items():
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as directory:
                    nested = Path(directory) / "repo"
                    shutil.copytree(self.root, nested)
                    original_root = self.root
                    self.root = nested
                    try:
                        expected = validator.EXPECTED_EVALUATIONS[
                            "writer_component"
                        ]["claim_record"][field]
                        self.replace_provenance("claims.yaml", expected, value)
                        self.assert_fails("fixed {} mismatch".format(field))
                    finally:
                        self.root = original_root

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

    def test_unexpected_claim_cannot_bind_publication_evidence(self):
        path = self.root / "provenance/claims.yaml"
        path.write_text(
            path.read_text(encoding="utf-8")
            + """
  - id: slvc_dma_complete_dma_false_claim
    benchmark: fabricated
    configuration: fabricated
    tool: fabricated
    status: verified
    public: true
    evidence:
      - slvc_dma_asic_paired_dc_publication
""",
            encoding="utf-8",
        )
        self.assert_fails("unexpected claim binding")

    def test_inline_claim_binding_cannot_bypass_inventory(self):
        path = self.root / "provenance/claims.yaml"
        path.write_text(
            path.read_text(encoding="utf-8")
            + """
  - id: slvc_dma_complete_dma_inline_false_claim
    benchmark: fabricated
    configuration: fabricated
    tool: fabricated
    status: verified
    public: true
    evidence: [slvc_dma_asic_paired_dc_publication]
""",
            encoding="utf-8",
        )
        self.assert_fails("evidence list")

    def test_escaped_claim_binding_cannot_bypass_inventory(self):
        path = self.root / "provenance/claims.yaml"
        path.write_text(
            path.read_text(encoding="utf-8")
            + """
  - id: slvc_dma_complete_dma_escaped_false_claim
    benchmark: fabricated
    configuration: fabricated
    tool: fabricated
    status: verified
    public: true
    evidence: ["slvc_dma_asic_paired_dc_publicatio\\u006e"]
""",
            encoding="utf-8",
        )
        self.assert_fails("evidence list")

    def test_publication_evidence_identity_is_fixed(self):
        mutations = {
            "type": "signoff_bundle",
            "source_ref": "0" * 40,
            "tool": "Vivado 2022.2",
            "public": "false",
        }
        for field, value in mutations.items():
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as directory:
                    nested = Path(directory) / "repo"
                    shutil.copytree(self.root, nested)
                    original_root = self.root
                    self.root = nested
                    try:
                        expected = validator.EXPECTED_EVIDENCE_RECORD[field]
                        self.replace_provenance("evidence.yaml", expected, value)
                        self.assert_fails(
                            "publication evidence fixed {} mismatch".format(field)
                        )
                    finally:
                        self.root = original_root

    def test_wrong_provenance_publication_path_fails(self):
        self.replace_provenance(
            "evidence.yaml",
            "    path: provenance/asic_paired_dc_publication.yaml",
            "    path: evidence/asic_paired_dc/manifest.yaml",
        )
        self.assert_fails("must bind the publication manifest")

    def test_wrong_provenance_publication_hash_fails(self):
        records = validator._registered_records(
            self.root / "provenance/evidence.yaml"
        )
        current_hash = validator._record_scalar(
            records["slvc_dma_asic_paired_dc_publication"],
            "sha256",
            "slvc_dma_asic_paired_dc_publication",
            r"[0-9a-f]{64}",
        )
        self.replace_provenance(
            "evidence.yaml",
            "    sha256: " + current_hash,
            "    sha256: " + "0" * 64,
        )
        self.assert_fails("must bind the publication manifest")

    def test_paired_nonclaim_registry_is_fixed(self):
        self.replace_provenance(
            "nonclaims.yaml",
            "    status: not_claimed",
            "    status: claimed",
        )
        self.assert_fails("fixed status mismatch")

    def test_paired_nonclaim_registry_record_is_required(self):
        self.replace_provenance(
            "nonclaims.yaml",
            "  - id: slvc_dma_writer_component_scope_promotion",
            "  - id: slvc_dma_writer_component_scope_promotion_removed",
        )
        self.assert_fails("nonclaim registry record is missing")

    def test_extra_paired_nonclaim_record_fails(self):
        path = self.root / "provenance/nonclaims.yaml"
        path.write_text(
            path.read_text(encoding="utf-8")
            + """
  - id: slvc_dma_paired_dc_false_override
    profile: slvc_dma_asic_paired_dc_publication
    statement: Complete-DMA signoff is claimed.
    reason: fabricated
    status: claimed
    public: true
""",
            encoding="utf-8",
        )
        self.assert_fails("fixed paired-DC nonclaim registry inventory")

    def test_paired_nonclaim_unknown_field_fails(self):
        self.replace_provenance(
            "nonclaims.yaml",
            "    status: not_claimed",
            "    override: complete-DMA signoff is claimed\n"
            "    status: not_claimed",
        )
        self.assert_fails("field set mismatch")

    def test_duplicate_json_key_fails(self):
        path = self.csv_path("manifest.yaml")
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text.replace(
                '  "schema": "slvc_dma_public_asic_paired_dc_v1",',
                '  "schema": "wrong",\n'
                '  "schema": "slvc_dma_public_asic_paired_dc_v1",',
                1,
            ),
            encoding="utf-8",
        )
        self.assert_fails("duplicate key")

    def test_duplicate_publication_key_fails(self):
        path = self.root / "provenance/asic_paired_dc_publication.yaml"
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text.replace(
                '  "raw_commercial_artifacts_published": false,',
                '  "raw_commercial_artifacts_published": true,\n'
                '  "raw_commercial_artifacts_published": false,',
                1,
            ),
            encoding="utf-8",
        )
        self.assert_fails("duplicate key")

    def test_publication_unknown_field_fails(self):
        path = self.root / "provenance/asic_paired_dc_publication.yaml"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["complete_dma_signoff"] = "verified"
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        self.assert_fails("publication field set mismatch")

    def test_claim_unknown_field_fails(self):
        self.replace_provenance(
            "claims.yaml",
            "    status: verified",
            "    complete_dma_signoff: verified\n    status: verified",
        )
        self.assert_fails("field set mismatch")

    def test_nonpaired_claim_cannot_drift(self):
        self.replace_provenance(
            "claims.yaml",
            "    value: 0.000341",
            "    value: 9999",
        )
        self.assert_fails("fixed claim registry inventory")

    def test_nonpaired_evidence_cannot_drift(self):
        self.replace_provenance(
            "evidence.yaml",
            "    path: evidence/slvc_dma_c2b4_n45_register_postroute_summary.yaml",
            "    path: evidence/does-not-exist.yaml",
        )
        self.assert_fails("fixed evidence registry inventory")

    def test_provenance_readme_is_fixed(self):
        path = self.root / "provenance/README.md"
        path.write_text(
            "Complete DMA foundry signoff verified at 9999 MHz.\n",
            encoding="utf-8",
        )
        self.assert_fails("fixed provenance README content")

    def test_private_path_injection_fails(self):
        path = self.csv_path("README.md")
        path.write_text(
            path.read_text(encoding="utf-8") + "\nD:\\private\\run\n",
            encoding="utf-8",
        )
        self.assert_fails("Windows absolute path")

    def test_arbitrary_posix_absolute_path_injection_fails(self):
        path = self.csv_path("README.md")
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\n/root/private/customer/design.v\n",
            encoding="utf-8",
        )
        self.assert_fails("POSIX absolute path")

    def test_delimited_posix_absolute_path_injection_fails(self):
        for delimiter in (",", ":", ";", "(", "~", "-", "_"):
            with self.subTest(delimiter=delimiter):
                with tempfile.TemporaryDirectory() as directory:
                    nested = Path(directory) / "repo"
                    shutil.copytree(self.root, nested)
                    original_root = self.root
                    self.root = nested
                    try:
                        path = self.csv_path("README.md")
                        path.write_text(
                            path.read_text(encoding="utf-8")
                            + "\ninternal archive{}/root/private/design.v\n".format(
                                delimiter
                            ),
                            encoding="utf-8",
                        )
                        self.assert_fails("POSIX absolute path")
                    finally:
                        self.root = original_root

    def test_delimited_unc_path_injection_fails(self):
        path = self.csv_path("README.md")
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\ninternal archive,\\\\server\\share\\design.v\n",
            encoding="utf-8",
        )
        self.assert_fails("UNC path")

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

    def test_raw_report_disguised_as_readme_fails(self):
        self.csv_path("README.md").write_text(
            "Design Compiler report_area raw payload\n", encoding="utf-8"
        )
        self.assert_fails("fixed evidence README content")

    def test_published_result_table_value_is_fixed(self):
        path = self.root / "docs/en/results.md"
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text.replace("`-7.966353%`", "`-70.000000%`", 1),
            encoding="utf-8",
        )
        self.assert_fails("fixed result table row mismatch")

    def test_paired_dc_document_section_is_fixed(self):
        path = self.root / "docs/en/results.md"
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text.replace(
                "## SRAM A5 Research",
                "Complete-DMA area reduction: 50%.\n\n## SRAM A5 Research",
                1,
            ),
            encoding="utf-8",
        )
        self.assert_fails("fixed evidence document content mismatch")

    def test_paired_dc_limitations_are_fixed(self):
        path = self.root / "docs/en/limitations.md"
        text = path.read_text(encoding="utf-8")
        path.write_text(
            text.replace(
                "not a C2B4 or complete-DMA area result",
                "a complete-DMA result",
                1,
            ),
            encoding="utf-8",
        )
        self.assert_fails("fixed evidence document content mismatch")

    def test_contradictory_text_outside_paired_dc_section_fails(self):
        path = self.root / "docs/en/results.md"
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\nComplete-DMA area reduction: 50%.\n",
            encoding="utf-8",
        )
        self.assert_fails("fixed evidence document content mismatch")

    def test_authorized_throughput_records_and_result_blocks_pass(self):
        additions = {
            "claims.yaml": (
                "  - id: {}\n"
                "    profile: bounded_sim\n"
                "    evidence:\n"
                "      - {}\n"
                "    status: verified\n".format(
                    validator.AUTHORIZED_THROUGHPUT_CLAIM_ID,
                    validator.AUTHORIZED_THROUGHPUT_EVIDENCE_ID,
                )
            ),
            "evidence.yaml": (
                "  - id: {}\n"
                "    path: evidence/throughput.yaml\n"
                "    public: true\n".format(
                    validator.AUTHORIZED_THROUGHPUT_EVIDENCE_ID
                )
            ),
            "nonclaims.yaml": (
                "  - id: {}\n"
                "    statement: not hardware\n"
                "    status: not_claimed\n".format(
                    validator.AUTHORIZED_THROUGHPUT_NONCLAIM_ID
                )
            ),
        }
        for name, addition in additions.items():
            path = self.root / "provenance" / name
            path.write_text(
                path.read_text(encoding="utf-8") + addition,
                encoding="utf-8",
            )
        for relative in ("docs/en/results.md", "docs/zh-CN/results.md"):
            path = self.root / relative
            path.write_text(
                path.read_text(encoding="utf-8") +
                validator.AUTHORIZED_RESULTS_START + "\n" +
                "## Bounded Async64 RTL Simulation\n\nAuthorized addition.\n" +
                validator.AUTHORIZED_RESULTS_END + "\n",
                encoding="utf-8",
            )
        validator.validate(self.root)

    def test_authorized_result_marker_does_not_hide_unmarked_mutation(self):
        path = self.root / "docs/en/results.md"
        text = path.read_text(encoding="utf-8").replace(
            "## SRAM A5 Research", "Unmarked mutation.\n\n## SRAM A5 Research", 1
        )
        text += (
            validator.AUTHORIZED_RESULTS_START + "\nAuthorized.\n" +
            validator.AUTHORIZED_RESULTS_END + "\n"
        )
        path.write_text(text, encoding="utf-8")
        self.assert_fails("fixed evidence document content mismatch")

    def test_duplicate_authorized_registry_item_fails(self):
        path = self.root / "provenance/claims.yaml"
        addition = "  - id: {}\n    status: verified\n".format(
            validator.AUTHORIZED_THROUGHPUT_CLAIM_ID
        )
        path.write_text(
            path.read_text(encoding="utf-8") + addition + addition,
            encoding="utf-8",
        )
        self.assert_fails("duplicate")

    def test_html_closing_tag_is_not_a_posix_path(self):
        path = self.csv_path("README.md")
        text = path.read_text(encoding="utf-8")
        path.write_text(text + "\n<details></details>\n", encoding="utf-8")
        self.assert_fails("fixed evidence README content")

    def test_posix_path_ending_in_angle_bracket_fails(self):
        path = self.csv_path("README.md")
        text = path.read_text(encoding="utf-8")
        path.write_text(text + "\n/tmp>\n", encoding="utf-8")
        self.assert_fails("POSIX absolute path")

    def test_ordinary_pr_does_not_activate_evidence_scope(self):
        self.assertFalse(validator._evidence_scope_active({
            "rtl/rx/dma_axi_write_engine_512.v",
            "provenance/checksums.sha256",
        }))
        self.assertTrue(validator._evidence_scope_active({
            "docs/en/results.md",
            "provenance/checksums.sha256",
        }))

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
        updated_points_hash = validator._sha256(self.csv_path("points.csv"))
        with mock.patch.object(
            validator, "EXPECTED_POINTS_SHA256", updated_points_hash
        ):
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
