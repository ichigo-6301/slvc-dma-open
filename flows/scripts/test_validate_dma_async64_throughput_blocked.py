from __future__ import print_function

import csv
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from flows.scripts import validate_dma_async64_throughput_blocked as validator


class Async64ThroughputEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.source_root = Path(__file__).resolve().parents[2]
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for rel in validator.SOURCE_PATHS:
            target = self.root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(validator.source_bytes(self.source_root, rel))
        for rel in (validator.PACKAGE_REL,):
            source = self.source_root / rel
            target = self.root / rel
            if source.is_dir():
                shutil.copytree(str(source), str(target))
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(source), str(target))

    def tearDown(self):
        self.temp.cleanup()

    def validate(self):
        with mock.patch.object(validator.subprocess, "check_output", return_value=""):
            return validator.validate(self.root)

    def mutate_manifest(self, callback):
        path = self.root / validator.MANIFEST_REL
        data = json.loads(path.read_text(encoding="utf-8"))
        callback(data)
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")

    def mutate_csv(self, rel, callback):
        path = self.root / rel
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            header = reader.fieldnames
            rows = list(reader)
        callback(rows)
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=header, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        manifest = self.root / validator.MANIFEST_REL
        data = json.loads(manifest.read_text(encoding="utf-8"))
        data["files"][path.name] = validator.sha256_file(path)
        manifest.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n",
                            encoding="utf-8")

    def assert_rejected(self):
        with self.assertRaises(validator.ValidationError):
            self.validate()

    def test_valid_blocked_package(self):
        result = self.validate()
        self.assertEqual(result["points"], 2)

    def test_rejects_promoted_classification(self):
        self.mutate_manifest(lambda data: data.__setitem__("classification", "PASS"))
        self.assert_rejected()

    def test_rejects_public_claim_eligibility(self):
        self.mutate_manifest(lambda data: data.__setitem__("public_claim_eligible", True))
        self.assert_rejected()

    def test_rejects_claim_id(self):
        self.mutate_manifest(lambda data: data.__setitem__("claim_id", "async64_throughput"))
        self.assert_rejected()

    def test_rejects_async64_64_byte_scope_drift(self):
        self.mutate_manifest(lambda data: data["boundaries"].__setitem__(
            "async64_interface_limit_bytes_per_cycle", "64"))
        self.assert_rejected()

    def test_rejects_protocol_error_erasure(self):
        self.mutate_csv(validator.POINTS_REL,
                        lambda rows: rows[0].__setitem__("protocol_error", "0"))
        self.assert_rejected()

    def test_rejects_pass_marker_injection(self):
        self.mutate_csv(validator.POINTS_REL,
                        lambda rows: rows[0].__setitem__("pass_marker", "true"))
        self.assert_rejected()

    def test_rejects_decimal_metric_drift(self):
        self.mutate_csv(validator.METRICS_REL,
                        lambda rows: rows[0].__setitem__("bytes_per_cycle", "8.000000"))
        self.assert_rejected()

    def test_rejects_stall_counter_drift(self):
        self.mutate_csv(validator.STALLS_REL,
                        lambda rows: rows[0].__setitem__("cdc_payload_stall", "0"))
        self.assert_rejected()

    def test_rejects_formal_matrix_promotion(self):
        self.mutate_csv(validator.MATRIX_REL,
                        lambda rows: rows[0].__setitem__("status", "PASS"))
        self.assert_rejected()

    def test_rejects_source_hash_drift(self):
        self.mutate_manifest(lambda data: data["sources"][0].__setitem__(
            "sha256", "0" * 64))
        self.assert_rejected()

    def test_rejects_linux_not_run_as_pass(self):
        self.mutate_csv(validator.VERIFICATION_REL,
                        lambda rows: rows[-1].__setitem__("status", "PASS"))
        self.assert_rejected()

    def test_rejects_raw_log_publication(self):
        self.mutate_csv(validator.ARTIFACTS_REL,
                        lambda rows: rows[0].__setitem__("published", "true"))
        self.assert_rejected()

    def test_rejects_artifact_hash_erasure(self):
        self.mutate_csv(validator.ARTIFACTS_REL,
                        lambda rows: rows[0].__setitem__("sha256", ""))
        self.assert_rejected()

    def test_rejects_private_path_injection(self):
        doc = self.root / validator.PACKAGE_REL / "README.md"
        doc.write_text(doc.read_text(encoding="utf-8") + "\nC:/Users/example/run.log\n",
                       encoding="utf-8")
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
