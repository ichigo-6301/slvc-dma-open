#!/usr/bin/env python3
"""Mutation tests for the Async64 publication gate."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from flows.scripts import validate_throughput_publication_gate as gate


ROOT = Path(__file__).resolve().parents[2]

CLAIM_BLOCK = """  - id: slvc_dma_async64_end_to_end_rtl_sim_throughput
    profile: slvc_dma_v1_512_async64_full_loopback_sim
    statement: \"At 100 MHz the result was 383.117735 MB/s, 3.064942 Gb/s, and 95.779434% of the bounded model ceiling.\"
    metric: end_to_end_payload_throughput
    value: 3.831177
    unit: MB/s/MHz
    evidence:
      - slvc_dma_async64_end_to_end_sim_summary
    resume_eligible: false
    status: verified
    public: true
"""

EVIDENCE_BLOCK = """  - id: slvc_dma_async64_end_to_end_sim_summary
    path: evidence/slvc_dma_async64_end_to_end_sim_summary.yaml
    type: bounded_dual_platform_rtl_simulation
    claims:
      - slvc_dma_async64_end_to_end_rtl_sim_throughput
    public: true
"""

NONCLAIM_BLOCK = """  - id: slvc_dma_async64_end_to_end_not_hardware
    profile: slvc_dma_v1_512_async64_full_loopback_sim
    statement: \"FPGA board throughput, Fmax, and the 64 B/cycle interface result are not claimed.\"
    reason: Simulation is not hardware measurement.
    status: not_claimed
    public: true
"""

SUMMARY = """classification: VERIFIED_RTL_SIMULATION
claim_id: slvc_dma_async64_end_to_end_rtl_sim_throughput
e2e_mbps_per_mhz: 3.831177
mb_per_s_at_100mhz: 383.117735
gbits_per_s_at_100mhz: 3.064942
model_efficiency_percent: 95.779434
resume_eligible: false
fpga_emulation: pending_not_measured_not_claimed
"""


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
        self._append(self.root / gate.CLAIMS_REL, CLAIM_BLOCK)
        self._append(self.root / gate.EVIDENCE_REL, EVIDENCE_BLOCK)
        self._append(self.root / gate.NONCLAIMS_REL, NONCLAIM_BLOCK)
        for relative in gate.REQUIRED_PATHS:
            target = self.root / relative
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture\n", encoding="utf-8")
        (self.root / gate.SUMMARY_REL).write_text(SUMMARY, encoding="utf-8")
        (self.root / gate.CHART_REL).write_text(
            '<svg width="1600" height="1000">'
            'slvc_dma_async64_end_to_end_rtl_sim_throughput '
            'Pending / not measured / not claimed</svg>\n',
            encoding="utf-8",
        )
        manifest_path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["assets"].append({
            "path": gate.CHART_REL.as_posix(),
            "source_type": "deterministic_generated_showcase",
            "numeric_authority": False,
            "claim_ids": [gate.CLAIM_ID],
            "inputs": [
                {"path": gate.SUMMARY_REL.as_posix()},
                {"path": (gate.PACKAGE_REL / "points.csv").as_posix()},
                {"path": gate.CLAIMS_REL.as_posix()},
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
        target.write_text(SUMMARY, encoding="utf-8")
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
            "resume_eligible: false", "resume_eligible: true"
        )
        path.write_text(text, encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "resume_eligible"):
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
