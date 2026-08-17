#!/usr/bin/env python3

import csv
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("validate_fpga_bram_architecture_evidence.py")
SPEC = importlib.util.spec_from_file_location("fpga_bram_evidence", str(MODULE_PATH))
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def _render_scalar(value):
    if value is True:
        return "true"
    if value is False:
        return "false"
    return json.dumps(str(value), ensure_ascii=True)


def _render_record(item_id, fields):
    lines = ["  - id: {}".format(item_id)]
    for key, value in fields.items():
        if isinstance(value, list):
            lines.append("    {}:".format(key))
            lines.extend("      - {}".format(_render_scalar(item)) for item in value)
        else:
            lines.append("    {}: {}".format(key, _render_scalar(value)))
    return "\n".join(lines) + "\n"


def _write_csv(path, fields, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(fields)
        writer.writerows(rows)


def _write_fixture(root):
    root = Path(root)
    package = root / gate.PACKAGE_REL
    package.mkdir(parents=True)
    summary = (
        "id: {}\nclaim: {}\nsource_ref: {}\n"
        "headline_tiles: 45.5 vs 97.5\nheadline_reduction_percent: 53.333\n"
        "packed_bank_tiles: 28.5\nscope: resource-budget comparison\n"
        "numeric_authority: false\n"
    ).format(gate.EVIDENCE_ID, gate.CLAIM_ID, gate.SOURCE_REF)
    (root / gate.SUMMARY_REL).parent.mkdir(parents=True, exist_ok=True)
    (root / gate.SUMMARY_REL).write_text(summary, encoding="utf-8")
    summary_sha = gate._sha256(root / gate.SUMMARY_REL)

    evidence_fixed = {
        "path": str(gate.SUMMARY_REL).replace("\\", "/"),
        "type": "fpga_vivado_2018_3_resource_comparison",
        "source_ref": gate.SOURCE_REF,
        "tool": "Vivado 2018.3",
        "claims": [gate.CLAIM_ID],
        "sha256": summary_sha,
        "public": True,
    }
    (root / gate.CLAIMS_REL).parent.mkdir(parents=True, exist_ok=True)
    (root / gate.CLAIMS_REL).write_text(
        "kind: claims\nschema_version: 1.0.0\nclaims:\n" +
        _render_record(gate.CLAIM_ID, gate.CLAIM_FIXED), encoding="utf-8"
    )
    (root / gate.EVIDENCE_REL).write_text(
        "kind: evidence\nschema_version: 1.0.0\nevidence:\n" +
        _render_record(gate.EVIDENCE_ID, evidence_fixed), encoding="utf-8"
    )
    (root / gate.NONCLAIMS_REL).write_text(
        "kind: nonclaims\nschema_version: 1.0.0\nnonclaims:\n" +
        _render_record(gate.NONCLAIM_ID, gate.NONCLAIM_FIXED), encoding="utf-8"
    )

    _write_csv(package / "resources.csv", gate.RESOURCE_FIELDS, gate.RESOURCE_ROWS)
    _write_csv(package / "comparisons.csv", gate.COMPARISON_FIELDS, gate.COMPARISON_ROWS)
    _write_csv(package / "mcdma_owners.csv", gate.OWNER_FIELDS, gate.OWNER_ROWS)
    _write_csv(package / "artifacts.csv", gate.ARTIFACT_FIELDS, gate.ARTIFACT_ROWS)
    manifest = {
        "schema_version": "1.0.0",
        "evidence_id": gate.EVIDENCE_ID,
        "claim_id": gate.CLAIM_ID,
        "classification": "FPGA_VIVADO_2018_3_RESOURCE_COMPARISON",
        "status": "partial",
        "source_ref": gate.SOURCE_REF,
        "tool": "Vivado 2018.3 build 2405991",
        "device": "xc7z100ffg900-2",
        "numeric_authority": "resources.csv",
        "derived_results": "comparisons.csv",
        "resume_eligible": False,
        "public": True,
        "files": sorted(gate.PACKAGE_FILES),
    }
    (package / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (package / "README.md").write_text(
        "# U5 BRAM architecture evidence\n\nSanitized bounded resource comparison.\n",
        encoding="utf-8",
    )

    docs = {
        Path("README.md"): (
            gate.README_START + "\n53.333% 独立浅宽 FIFO\n" + gate.README_END + "\n"
        ),
        Path("README.en.md"): (
            gate.README_START + "\n53.333% independent shallow-wide FIFO\n" +
            gate.README_END + "\n"
        ),
        Path("docs/zh-CN/results.md"): (
            gate.RESULTS_START + "\n28.5 资源预算对比\n" + gate.RESULTS_END + "\n"
        ),
        Path("docs/en/results.md"): (
            gate.RESULTS_START + "\n28.5 resource-budget comparison\n" +
            gate.RESULTS_END + "\n"
        ),
        Path("docs/zh-CN/fpga_implementation.md"): (
            gate.RESULTS_START + "\n135168 Shared Pool\n" + gate.RESULTS_END + "\n"
        ),
        Path("docs/en/fpga_implementation.md"): (
            gate.RESULTS_START + "\n135168 Shared Pool\n" + gate.RESULTS_END + "\n"
        ),
    }
    for relative, text in docs.items():
        (root / relative).parent.mkdir(parents=True, exist_ok=True)
        (root / relative).write_text(text, encoding="utf-8")


class FpgaBramEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        _write_fixture(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_fixed_publication_passes(self):
        self.assertEqual(
            gate.validate(self.root), "FPGA_BRAM_ARCHITECTURE_EVIDENCE_PASS"
        )

    def test_checkout_matches_registration_state(self):
        root = Path(__file__).resolve().parents[2]
        claims = (root / gate.CLAIMS_REL).read_text(encoding="utf-8")
        expected = (
            "FPGA_BRAM_ARCHITECTURE_EVIDENCE_PASS"
            if "  - id: {}\n".format(gate.CLAIM_ID) in claims
            else "FPGA_BRAM_ARCHITECTURE_NOT_PUBLISHED"
        )
        self.assertEqual(
            gate.validate(root), expected
        )

    def test_resource_mutation_fails(self):
        path = self.root / gate.PACKAGE_REL / "resources.csv"
        path.write_text(path.read_text(encoding="utf-8").replace("97.5", "96.5", 1),
                        encoding="utf-8")
        with self.assertRaisesRegex(gate.EvidenceError, "resources.csv fixed rows"):
            gate.validate(self.root)

    def test_comparison_mutation_fails(self):
        path = self.root / gate.PACKAGE_REL / "comparisons.csv"
        path.write_text(path.read_text(encoding="utf-8").replace("53.333", "54.000", 1),
                        encoding="utf-8")
        with self.assertRaisesRegex(gate.EvidenceError, "comparisons.csv fixed rows"):
            gate.validate(self.root)

    def test_mcdma_64_512_must_remain_unsupported(self):
        path = self.root / gate.PACKAGE_REL / "resources.csv"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "unsupported_by_vivado_2018_3", "measured", 1
            ), encoding="utf-8"
        )
        with self.assertRaisesRegex(gate.EvidenceError, "resources.csv fixed rows"):
            gate.validate(self.root)

    def test_external_artifact_hash_drift_fails(self):
        path = self.root / gate.PACKAGE_REL / "artifacts.csv"
        path.write_text(path.read_text(encoding="utf-8").replace("093752e9", "193752e9", 1),
                        encoding="utf-8")
        with self.assertRaisesRegex(gate.EvidenceError, "artifacts.csv fixed rows"):
            gate.validate(self.root)

    def test_extra_package_file_fails(self):
        (self.root / gate.PACKAGE_REL / "raw_vivado.log").write_text("raw", encoding="utf-8")
        with self.assertRaisesRegex(gate.EvidenceError, "package file set"):
            gate.validate(self.root)

    def test_sensitive_path_fails(self):
        path = self.root / gate.PACKAGE_REL / "README.md"
        path.write_text("D:\\private\\result.rpt\n", encoding="utf-8")
        with self.assertRaisesRegex(gate.EvidenceError, "sensitive identity"):
            gate.validate(self.root)

    def test_resume_eligibility_cannot_be_promoted(self):
        path = self.root / gate.CLAIMS_REL
        path.write_text(path.read_text(encoding="utf-8").replace(
            "resume_eligible: false", "resume_eligible: true", 1
        ), encoding="utf-8")
        with self.assertRaisesRegex(gate.EvidenceError, "resume_eligible"):
            gate.validate(self.root)

    def test_shared_pool_overclaim_fails(self):
        path = self.root / Path("README.en.md")
        path.write_text(path.read_text(encoding="utf-8").replace(
            "independent shallow-wide FIFO",
            "independent shallow-wide FIFO Shared Pool alone reduced BRAM",
        ), encoding="utf-8")
        with self.assertRaisesRegex(gate.EvidenceError, "forbidden overclaim"):
            gate.validate(self.root)

    def test_preexisting_negative_boundary_outside_publication_is_allowed(self):
        path = self.root / Path("README.en.md")
        path.write_text(
            path.read_text(encoding="utf-8") +
            "Not a C2B4 or complete-DMA area reduction.\n",
            encoding="utf-8",
        )
        self.assertEqual(
            gate.validate(self.root),
            "FPGA_BRAM_ARCHITECTURE_EVIDENCE_PASS",
        )

    def test_orphan_payload_fails(self):
        (self.root / gate.CLAIMS_REL).write_text(
            "kind: claims\nschema_version: 1.0.0\nclaims:\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(gate.EvidenceError, "orphan"):
            gate.validate(self.root)


if __name__ == "__main__":
    unittest.main()
