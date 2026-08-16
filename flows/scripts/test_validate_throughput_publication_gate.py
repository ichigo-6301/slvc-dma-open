#!/usr/bin/env python3
"""Mutation tests for the Async64 publication gate."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from flows.scripts import validate_throughput_publication_gate as gate


ROOT = Path(__file__).resolve().parents[2]
SOURCE_REF = "a" * 40


def _yaml_record(item_id, fields):
    lines = ["  - id: {}".format(item_id)]
    for key, value in fields:
        if isinstance(value, list):
            lines.append("    {}:".format(key))
            lines.extend("      - {}".format(json.dumps(item)) for item in value)
        else:
            lines.append("    {}: {}".format(key, json.dumps(value)))
    return "\n".join(lines) + "\n"


CLAIM_BLOCK = _yaml_record(gate.CLAIM_ID, [
    ("profile", gate.CLAIM_FIXED["profile"]),
    ("statement", gate.CLAIM_FIXED["statement"]),
    ("metric", gate.CLAIM_FIXED["metric"]),
    ("value", gate.CLAIM_FIXED["value"]),
    ("unit", gate.CLAIM_FIXED["unit"]),
    ("benchmark", gate.CLAIM_FIXED["benchmark"]),
    ("configuration", gate.CLAIM_FIXED["configuration"]),
    ("source_ref", SOURCE_REF),
    ("tool", gate.CLAIM_FIXED["tool"]),
    ("evidence", gate.CLAIM_FIXED["evidence"]),
    ("status", gate.CLAIM_FIXED["status"]),
    ("caveat", gate.CLAIM_FIXED["caveat"]),
    ("resume_eligible", gate.CLAIM_FIXED["resume_eligible"]),
    ("public", gate.CLAIM_FIXED["public"]),
])

NONCLAIM_BLOCK = _yaml_record(
    gate.NONCLAIM_ID, list(gate.NONCLAIM_FIXED.items())
)


class ThroughputPublicationGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def _copy_provenance(self):
        for relative in (gate.CLAIMS_REL, gate.EVIDENCE_REL, gate.NONCLAIMS_REL,
                         gate.SHOWCASE_REL):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)

    @staticmethod
    def _append(path, text):
        with path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(text)

    def _published_fixture(self):
        self._copy_provenance()
        for relative in gate.REQUIRED_PATHS:
            target = self.root / relative
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture\n", encoding="utf-8")
        summary = {
            "schema": "slvc_dma_async64_end_to_end_rtl_simulation_v1",
            "classification": "VERIFIED_RTL_SIMULATION",
            "claim_id": gate.CLAIM_ID,
            "numeric_authority": (gate.PACKAGE_REL / "points.csv").as_posix(),
            "source_ref": SOURCE_REF,
            "profile": gate.SUMMARY_PROFILE,
            "main_point": gate.SUMMARY_MAIN_POINT,
            "validation": gate.SUMMARY_VALIDATION,
            "boundaries": gate.SUMMARY_BOUNDARIES,
            "fpga_emulation": {
                "status": "pending_not_measured_not_claimed", "value": None,
            },
        }
        summary_path = self.root / gate.SUMMARY_REL
        summary_path.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        package_manifest = {
            "schema_version": 3,
            "experiment_id": "slvc_dma_async64_end_to_end_rtl_simulation",
            "classification": "VERIFIED_RTL_SIMULATION",
            "flow_as_run_commit": SOURCE_REF,
            "claim_id": gate.CLAIM_ID,
            "public_claim_eligible": True,
            "resume_eligible": False,
            "formal_matrix_completed": True,
            "correctness_ladder_completed": True,
            "dual_platform_complete": True,
            "c2b4_physical_source_changed": False,
            "c2b4_physical_rerun_performed": False,
            "profile": dict(
                gate.SUMMARY_PROFILE,
                descriptor_workload_entries=1024,
                descriptor_ring_capacity_entries=2048,
                cq_entries=4096,
            ),
            "main_point": dict(
                gate.SUMMARY_MAIN_POINT,
                workload="1024 x 4096-byte full TX-to-RX loopback",
            ),
            "boundaries": {
                "hp0_shared_is_board_measurement": False,
                "score_is_fmax": False,
                "sameclock512_64_bytes_per_cycle_claim_reused": False,
                "legacy_9p5_gbps_used_in_comparison": False,
                "public_claim_updated": True,
                "fpga_emulation_measured": False,
            },
        }
        (self.root / gate.PACKAGE_REL / "manifest.json").write_text(
            json.dumps(package_manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        evidence_block = _yaml_record(gate.EVIDENCE_ID, [
            ("path", gate.SUMMARY_REL.as_posix()),
            ("type", "bounded_dual_platform_rtl_simulation"),
            ("source_ref", SOURCE_REF),
            ("tool", gate.CLAIM_FIXED["tool"]),
            ("claims", [gate.CLAIM_ID]),
            ("sha256", gate._sha256(summary_path.read_bytes())),
            ("public", "true"),
        ])
        self._append(self.root / gate.CLAIMS_REL, CLAIM_BLOCK)
        self._append(self.root / gate.EVIDENCE_REL, evidence_block)
        self._append(self.root / gate.NONCLAIMS_REL, NONCLAIM_BLOCK)
        (self.root / gate.CHART_REL).write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="1600" '
            'height="1000" viewBox="0 0 1600 1000" '
            'preserveAspectRatio="xMidYMid meet"><text>' + gate.CLAIM_ID +
            '</text><text>Pending / not measured / not claimed</text></svg>\n',
            encoding="utf-8",
        )
        manifest_path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        generator = self.root / "flows/scripts/generate_showcase_assets.py"
        manifest["assets"].append({
            "path": gate.CHART_REL.as_posix(),
            "sha256": gate._sha256((self.root / gate.CHART_REL).read_bytes()),
            "format": "svg",
            "source": "bounded Async64 RTL simulation evidence",
            "source_type": "deterministic_generated_showcase",
            "numeric_authority": False,
            "generator": "flows/scripts/generate_showcase_assets.py",
            "generator_sha256": gate._sha256(generator.read_bytes()),
            "command": "python flows/scripts/generate_showcase_assets.py --root . --write",
            "claim_ids": [gate.CLAIM_ID],
            "inputs": [
                {"path": relative.as_posix(),
                 "sha256": gate._sha256((self.root / relative).read_bytes())}
                for relative in (
                    gate.SUMMARY_REL,
                    gate.PACKAGE_REL / "points.csv",
                    gate.CLAIMS_REL,
                )
            ],
        })
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    def test_unpublished_tree_returns_explicit_status(self):
        self._copy_provenance()
        self.assertEqual(gate.validate(self.root, execute_validators=False),
                         "NOT_PUBLISHED")

    def test_complete_publication_contract_passes(self):
        self._published_fixture()
        self.assertEqual(
            gate.validate(self.root, execute_validators=False),
            "VERIFIED_RTL_SIMULATION_PUBLISHED",
        )

    def test_publication_files_without_claim_fail(self):
        self._copy_provenance()
        target = self.root / gate.SUMMARY_REL
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("{}\n", encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "without the registered claim"):
            gate.validate(self.root, execute_validators=False)

    def test_missing_validator_or_evidence_fails(self):
        self._published_fixture()
        (self.root / gate.VALIDATOR_REL).unlink()
        with self.assertRaisesRegex(gate.PublicationError, "is missing"):
            gate.validate(self.root, execute_validators=False)

    def test_existing_claim_mutation_fails(self):
        self._published_fixture()
        path = self.root / gate.CLAIMS_REL
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "unit: contiguous 512-bit AXI W beats",
                "unit: contiguous 64-bit AXI W beats",
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(gate.PublicationError, "protected"):
            gate.validate(self.root, execute_validators=False)

    def test_resume_eligibility_mutation_fails(self):
        self._published_fixture()
        path = self.root / gate.CLAIMS_REL
        text = path.read_text(encoding="utf-8").replace(
            'resume_eligible: "false"', 'resume_eligible: "true"'
        )
        path.write_text(text, encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "resume_eligible"):
            gate.validate(self.root, execute_validators=False)

    def test_decoy_resume_eligibility_text_does_not_bypass_actual_value(self):
        self._published_fixture()
        path = self.root / gate.CLAIMS_REL
        text = path.read_text(encoding="utf-8").replace(
            '    resume_eligible: "false"',
            '    resume_eligible: "true"\n'
            '    note: "resume_eligible: false"',
        )
        path.write_text(text, encoding="utf-8")
        with self.assertRaises(gate.PublicationError):
            gate.validate(self.root, execute_validators=False)

    def test_deleted_required_rtl_input_fails(self):
        self._published_fixture()
        (self.root / "rtl/tx/dma_axi_read_prefetch.v").unlink()
        with self.assertRaisesRegex(gate.PublicationError, "is missing"):
            gate.validate(self.root, execute_validators=False)

    def test_existing_showcase_binding_mutation_fails(self):
        self._published_fixture()
        path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["assets"][0]["claim_ids"] = ["rewritten_claim"]
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "existing showcase"):
            gate.validate(self.root, execute_validators=False)

    def test_chart_cannot_be_numeric_authority(self):
        self._published_fixture()
        path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["assets"][-1]["numeric_authority"] = True
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "numeric authority"):
            gate.validate(self.root, execute_validators=False)


if __name__ == "__main__":
    unittest.main()
